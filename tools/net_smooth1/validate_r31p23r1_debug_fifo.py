#!/usr/bin/env python3
"""R31 P2.3 R1 read-only debug FIFO receipt vs raw Godot server console.

No product mutation and no claim of frame PERF_PASS. The original debug
message is detached on the authoritative completion frame and printed later,
preserving actual event time, main Godot PID, M6 generation and JSON fields.
The trace file and runtime.log must be complete; queue overflow is explicitly
reported as a performance blocker and never silently reclassified.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re

from analyze_r31p22_loop_stages import read_trace

SCHEMA="dws.net_smooth.r31p23r1.debug_fifo_receipt.v1"
SERVER_PREFIX="[m7_server] "
RUN_ID=re.compile(r"^[0-9a-f]{16}$")


def sha256(path: Path) -> str:
    hasher=hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024*1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def positive_int(obj, what: str) -> int:
    if type(obj) is not int or obj < 1:
        raise ValueError("INVALID_"+what)
    return obj


def audit(root: Path) -> dict:
    manifest=json.loads((root/"manifest.json").read_text(encoding="utf-8"))
    run_id=manifest.get("run_id")
    if (not isinstance(run_id,str) or not RUN_ID.fullmatch(run_id)
        or manifest.get("r31p23_completion_attribution") is not True
        or manifest.get("r31p23r1_defer_checkpoint_debug") is not True):
        raise ValueError("P23R1_MISSING_EXACT_CANARY")
    trace_path=root/"server"/"trace.jsonl"
    log_path=root/"server"/"runtime.log"
    checked=read_trace(trace_path,run_id)  # sequence, END and zero dropped/IO
    queued=[]
    overflows=[]
    traced_flushed=[]
    pid=None
    with trace_path.open(encoding="utf-8") as stream:
        for index, raw in enumerate(stream,1):
            if len(raw)>1048576:
                raise ValueError("P23R1_OVERSIZED_EVENT")
            record=json.loads(raw)
            if record["kind"]=="header":
                pid=positive_int(record["data"].get("pid"),"MAIN_PID")
            if record.get("kind")=="r31p23r1_debug_queued":
                data=record["data"]
                queued.append((
                    positive_int(data.get("generation"),"QUEUED_GENERATION"),
                    positive_int(data.get("time_msec"),"QUEUED_TIMESTAMP"),
                ))
            elif record.get("kind")=="r31p23r1_debug_flushed":
                d=record["data"]
                traced_flushed.append(positive_int(d.get("generation"),"FLUSHED_GENERATION"))
            elif record.get("kind")=="r31p23r1_debug_overflow":
                d=record["data"]
                overflows.append(positive_int(d.get("generation"),"OVERFLOW_GENERATION"))
    if pid is None:
        raise ValueError("P23R1_TRACE_MAIN_PID_MISSING")
    if not queued:
        raise ValueError("P23R1_NO_COMPLETION_DEBUG_QUEUED")
    if len(queued)!=len(set(queued)):
        raise ValueError("P23R1_DUPLICATE_QUEUED_IDENTITY")

    log_records=[]
    with log_path.open(encoding="utf-8",errors="replace") as stream:
        for index,line in enumerate(stream,1):
            pos=line.find(SERVER_PREFIX)
            if pos<0:
                continue
            try:
                record=json.loads(line[pos+len(SERVER_PREFIX):].strip())
            except (ValueError,TypeError):
                raise ValueError("P23R1_DEBUG_JSON_INVALID_LINE_"+str(index)) from None
            if record.get("event")!="MOVEMENT_CHECKPOINT_COMMITTED":
                continue
            details=record.get("details")
            if not isinstance(details,dict) or details.get("async") is not True:
                continue  # existing synchronous shutdown checkpoint semantics
            if positive_int(record.get("process_id"),"DEBUG_PROCESS_ID") != pid:
                raise ValueError("P23R1_WRAPPER_VS_MAIN_PID_MISMATCH")
            log_records.append((
                positive_int(details.get("generation"),"LOGGED_GENERATION"),
                positive_int(record.get("time_msec"),"LOGGED_EVENT_TIMESTAMP"),
            ))
    if not log_records:
        raise ValueError("P23R1_NO_COMPLETION_DEBUG_LOGS")
    for generation in traced_flushed:
        if generation not in [q[0] for q in queued]:
            raise ValueError("P23R1_FLUSH_WITHOUT_QUEUED_GENERATION")
    if overflows:
        raise ValueError("P23R1_DEBUG_QUEUE_OVERFLOW_RECORDED")
    if len(queued)!=len(log_records):
        raise ValueError("P23R1_DEBUG_LOG_COUNT_MISMATCH")
    if Counter(queued)!=Counter(log_records):
        raise ValueError("P23R1_DEBUG_GENERATION_OR_TIMESTAMP_MISMATCH")
    # No overflow: the bounded FIFO must preserve ordering.
    if queued!=log_records:
        raise ValueError("P23R1_DEBUG_FIFO_ORDER_MISMATCH")

    report=json.loads((root/"report.json").read_text(encoding="utf-8"))
    return {
        "schema":SCHEMA,
        "verdict":"P23R1_DEBUG_AUDIT_PASS_NOT_PERF_PASS",
        "run_id":run_id,"main_godot_pid":pid,
        "trace_sha256":checked["trace_sha256"],
        "runtime_log_sha256":sha256(log_path),
        "queued":len(queued),
        "printed":len(log_records),
        "flushed_during_trace":len(traced_flushed),
        "shutdown_flush_or_untraced":len(queued)-len(traced_flushed),
        "overflow":len(overflows),
        "first_generation":queued[0][0],
        "last_generation":queued[-1][0],
        "original_normative_verdict":report.get("verdict"),
        "notes":[
            "Recorded debug event timestamps are original completion timestamps.",
            "Console lines may print later than completion but remain FIFO and byte-structured.",
            "No gameplay or M6 checksum/persistence/ACK fields were changed.",
            "This audit cannot turn FAIL/INCONCLUSIVE into PERF_PASS.",
        ],
    }


def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root",type=Path)
    parser.add_argument("--output",required=True,type=Path)
    args=parser.parse_args()
    try:
        result=audit(args.root)
    except (OSError,ValueError,TypeError,KeyError,json.JSONDecodeError) as exc:
        print("P23R1_DEBUG_AUDIT_INCONCLUSIVE:"+str(exc))
        return 2
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf-8")
    print(json.dumps({
        "verdict":result["verdict"],
        "queued":result["queued"],"printed":result["printed"],
        "original_normative_verdict":result["original_normative_verdict"],
    }))
    return 0


if __name__=="__main__":
    raise SystemExit(main())

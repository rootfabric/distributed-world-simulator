#!/usr/bin/env python3
"""NET-SMOOTH1 R31 P2.2 exact same-process engine-frame stage attribution.

Diagnostic only. No frame is removed and none of the 25/50/100ms acceptance
thresholds is changed. Frame, server_loop, loop_stages and compact wire events
join by Engine.get_process_frames() *within the same process*. A DIFFERENT
process's engine_frame number is unrelated; do not join client clocks.

Uncovered probe interval is NOT proof of OS stall, a frame cap, GC, or GPU work.
The existing normative report's FAIL remains FAIL regardless of this report.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any

STAGES = (
    "postcommit_ms", "item_completion_ms", "movement_completion_ms",
    "deferred_disconnect_ms", "deferred_admission_ms", "boundary_poll_ms",
    "message_dispatch_ms", "fixed_simulation_ms", "snapshot_publication_ms",
    "movement_persistence_ms", "telemetry_ms",
)
MESSAGE_STAGES = STAGES[:7]
WIRE_STAGES = ("payload_clone_ms", "frame_create_ms",
               "boundary_send_ms", "outbound_flush_ms")
COMPLETION_STAGES = (
    "poll_completed_ms", "generation_ack_gate_ms", "metadata_copy_ms",
    "completion_trace_ms", "telemetry_ms", "debug_event_ms",
    "diagnostic_report_ms",
)
KIND_KEYS = ("frame", "server_loop", "server_message",
             "r31p22_loop_stages", "movement_snapshot_stages",
             "r31p22_compact_wire_stages", "r31p22_compact_wire_failed",
             "r31p23_movement_completion")
MIN_FRAMES = 100
MIN_SNAPSHOTS = 10
TOLERANCE_MS = 1.0


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1048576), b""):
            h.update(chunk)
    return h.hexdigest()


def positive_int(v: Any, name: str) -> int:
    if type(v) is not int or v < 1:
        raise ValueError("INVALID_ENGINE_FRAME_" + name)
    return v


def number(v: Any, name: str) -> float:
    if type(v) not in (int, float) or not math.isfinite(v) or v < 0:
        raise ValueError("INVALID_NONNEGATIVE_NUMBER:" + name)
    return float(v)


def percentile(values: list[float], q: float) -> float | None:
    if not values:
        return None
    a = sorted(values)
    return a[max(0, math.ceil(q*len(a))-1)]


def dist(values: list[float]) -> dict:
    return {"n": len(values), "p50": percentile(values, .5),
            "p95": percentile(values, .95), "p99": percentile(values, .99),
            "p999": percentile(values, .999),
            "max": max(values, default=None)}


def read_trace(path: Path, run_id: str) -> dict:
    """Validate complete trace footer and monotonic sequence, do not alter it."""
    out = {kind: [] for kind in KIND_KEYS}
    header = start_t = end_t = footer = None
    measured = False
    count = 0
    last_t = -1.0
    with path.open(encoding="utf-8") as handle:
        for line_no, raw in enumerate(handle, 1):
            if line_no > 1000000 or len(raw) > 1048576:
                raise ValueError("TRACE_LIMIT_EXCEEDED")
            row = json.loads(raw)
            if not isinstance(row, dict) or not isinstance(row.get("data"), dict):
                raise ValueError("INVALID_TRACE_SHAPE")
            t_us = number(row.get("t_us"), "trace_t_us")
            if t_us < last_t or footer is not None:
                raise ValueError("TRACE_CLOCK_OR_FOOTER_INVALID")
            last_t = t_us
            kind = row.get("kind")
            if line_no == 1:
                header = row["data"]
                if (kind != "header"
                    or header.get("schema") != "dws.net_smooth.trace.v1"
                    or header.get("role") != "server"
                    or header.get("run_id") != run_id
                    or header.get("clock") != "PROCESS_LOCAL_MONOTONIC_US"):
                    raise ValueError("WRONG_TRACE_IDENTITY_OR_CLOCK")
            if kind == "end":
                footer = row["data"]
                continue
            count += 1
            if type(row.get("n")) is not int or row["n"] != count:
                raise ValueError("TRACE_SEQUENCE_LOSS")
            if type(row.get("measure")) is not bool:
                raise ValueError("TRACE_MEASURE_FLAG_MISSING")
            if kind == "measure_start":
                if start_t is not None or row["measure"] is not True:
                    raise ValueError("BAD_MEASURE_START")
                start_t, measured = t_us, True
            elif kind == "measure_end":
                if start_t is None or end_t is not None or row["measure"] is not True:
                    raise ValueError("BAD_MEASURE_END")
                end_t, measured = t_us, False
                continue
            if row["measure"] != measured:
                raise ValueError("TRACE_MEASURE_FLAG_INCONSISTENT")
            if kind in out and row["measure"] is True:
                out[kind].append(row)
    if footer is None or start_t is None or end_t is None or end_t <= start_t:
        raise ValueError("INCOMPLETE_MEASURED_TRACE")
    if (number(footer.get("dropped"), "trace.dropped") != 0
        or number(footer.get("io_errors"), "trace.io_errors") != 0
        or number(footer.get("produced"), "trace.produced") != count
        or number(footer.get("written"), "trace.written") != count):
        raise ValueError("TRACE_LOSS_OR_IO_ERROR")
    return {**out, "start_us": start_t, "end_us": end_t,
            "trace_sha256": sha256(path)}


def indexed(rows: list[dict], name: str) -> dict[int, dict]:
    result = {}
    for row in rows:
        frame_id = positive_int(row["data"].get("engine_frame"), name)
        if frame_id in result:
            raise ValueError("DUPLICATE_ENGINE_FRAME_" + name)
        result[frame_id] = row
    return result


def analyze_events(trace: dict, *, minimum_frames: int = MIN_FRAMES,
                   minimum_snapshots: int = MIN_SNAPSHOTS) -> dict:
    frames = indexed(trace["frame"], "FRAME")
    old_loops = indexed(trace["server_loop"], "SERVER_LOOP")
    stages = indexed(trace["r31p22_loop_stages"], "LOOP_STAGES")
    snapshots = indexed(trace["movement_snapshot_stages"], "SNAPSHOT")
    completion = indexed(trace["r31p23_movement_completion"], "COMPLETION")
    compact_by_frame: dict[int, list[dict]] = {}
    messages_by_frame: dict[int, list[dict]] = {}
    for row in trace["server_message"]:
        frame_id = positive_int(row["data"].get("engine_frame"), "HANDLER")
        messages_by_frame.setdefault(frame_id, []).append(row)
    for row in trace["r31p22_compact_wire_stages"]:
        frame_id = positive_int(row["data"].get("engine_frame"), "COMPACT")
        compact_by_frame.setdefault(frame_id, []).append(row)
    for row in trace["r31p22_compact_wire_failed"]:
        positive_int(row["data"].get("engine_frame"), "COMPACT_FAILURE")
    if trace["r31p22_compact_wire_failed"]:
        raise ValueError("COMPACT_WIRE_FAILED")
    if len(frames) < minimum_frames or len(snapshots) < minimum_snapshots:
        raise ValueError("INSUFFICIENT_FRAME_OR_SNAPSHOT_COVERAGE")
    if not set(snapshots).issubset(set(stages)):
        raise ValueError("UNMATCHED_SNAPSHOT_ENGINE_FRAME")
    if not set(compact_by_frame).issubset(set(snapshots)):
        raise ValueError("COMPACT_WITHOUT_SNAPSHOT_ENGINE_FRAME")
    if not set(messages_by_frame).issubset(set(stages)):
        raise ValueError("HANDLER_WITHOUT_LOOP_ENGINE_FRAME")
    if not set(completion).issubset(set(stages)):
        raise ValueError("COMPLETION_WITHOUT_LOOP_ENGINE_FRAME")
    if not set(stages).issubset(set(old_loops)):
        raise ValueError("LOOP_STAGE_WITHOUT_BASE_LOOP")
    missing = sorted(set(frames)-set(stages))
    missing_old = sorted(set(frames)-set(old_loops))
    # An exact engine-frame diagnostic must NEVER silently drop even ONE
    # very slow frame. Missing joined stages makes the entire source
    # attribution INCONCLUSIVE, not a conditional p99 over a smaller sample.
    if missing or missing_old:
        raise ValueError("FRAME_JOIN_INCOMPLETE")
    if set(stages) - set(frames):
        raise ValueError("STAGE_WITHOUT_MEASURED_FRAME")

    rows=[]
    by_stage={name:[] for name in STAGES}
    by_wire={name:[] for name in WIRE_STAGES}
    by_completion={name:[] for name in COMPLETION_STAGES}
    for frame_id in sorted(set(frames)&set(stages)):
        f=frames[frame_id]["data"]
        old=old_loops[frame_id]["data"]
        stage=stages[frame_id]["data"]
        frame_ms=number(f.get("interval_ms"), "FRAME_INTERVAL")
        process_ms=number(old.get("process_ms"), "SERVER_PROCESS")
        measured_ms=number(stage.get("measured_total_ms"), "LOOP_MEASURED")
        msg_ms=number(stage.get("message_span_ms"), "MESSAGE_SPAN")
        old_msg_ms=number(old.get("message_ms"), "BASE_MESSAGE_SPAN")
        stage_vals={name:number(stage.get(name), name) for name in STAGES}
        if abs(sum(stage_vals.values())-measured_ms)>TOLERANCE_MS:
            raise ValueError("STAGE_ACCOUNTING_MISMATCH")
        if abs(sum(stage_vals[n] for n in MESSAGE_STAGES)-msg_ms)>TOLERANCE_MS:
            raise ValueError("MESSAGE_ACCOUNTING_MISMATCH")
        if msg_ms > old_msg_ms+TOLERANCE_MS:
            raise ValueError("STAGE_MESSAGE_EXCEEDS_ORIGINAL")
        if measured_ms > process_ms+TOLERANCE_MS:
            raise ValueError("STAGE_TOTAL_EXCEEDS_ORIGINAL_PROCESS")

        handler_rows=messages_by_frame.get(frame_id,[])
        handlers_ms=sum(number(row["data"].get("duration_ms"),
                               "HANDLER_DURATION") for row in handler_rows)
        if handlers_ms>stage_vals["message_dispatch_ms"]+TOLERANCE_MS:
            raise ValueError("HANDLERS_EXCEED_DISPATCH")
        completed=completion.get(frame_id)
        completion_values={}
        if completed:
            data=completed["data"]
            completion_values={
                name:number(data.get(name),name)
                for name in COMPLETION_STAGES
            }
            completion_total=number(data.get("total_ms"),"COMPLETION_TOTAL")
            if abs(sum(completion_values.values())-completion_total)>.1:
                raise ValueError("COMPLETION_STAGE_ACCOUNTING_MISMATCH")
            if completion_total>stage_vals["movement_completion_ms"]+TOLERANCE_MS:
                raise ValueError("COMPLETION_EXCEEDS_P22_MOVEMENT_STAGE")
            for key,val in completion_values.items():
                by_completion[key].append(val)
        snap=snapshots.get(frame_id)
        compact_rows=compact_by_frame.get(frame_id,[])
        compact_sums={key:0.0 for key in WIRE_STAGES}
        if snap:
            data=snap["data"]
            peers=number(data.get("peers"), "SNAPSHOT_PEERS")
            if len(compact_rows)>peers:
                raise ValueError("COMPACT_MORE_THAN_PEERS")
            compact_time=number(data.get("compact_send_ms"),"SNAPSHOT_COMPACT_TIME")
            wire_total=0.0
            for c in compact_rows:
                d=c["data"]
                parts={k:number(d.get(k), k) for k in WIRE_STAGES}
                total=number(d.get("total_ms"), "WIRE_TOTAL")
                if abs(sum(parts.values())-total)>TOLERANCE_MS:
                    raise ValueError("COMPACT_STAGE_ACCOUNTING_MISMATCH")
                wire_total+=total
                for k,v in parts.items():
                    compact_sums[k]+=v
                    by_wire[k].append(v)
            if wire_total>compact_time+.1:
                raise ValueError("WIRE_COMPONENTS_EXCEED_COMPACT_SEND")

        for name,value in stage_vals.items():
            by_stage[name].append(value)
        rows.append({
            "engine_frame": frame_id,
            "frame_interval_ms": frame_ms,
            "server_process_ms": process_ms,
            "uncovered_probe_interval_ms": max(frame_ms-process_ms, 0),
            "message_ms": old_msg_ms,
            "message_span_attributed_ms": msg_ms,
            "postcommit_ms": stage_vals["postcommit_ms"],
            "item_completion_ms": stage_vals["item_completion_ms"],
            "movement_completion_ms": stage_vals["movement_completion_ms"],
            "deferred_disconnect_ms": stage_vals["deferred_disconnect_ms"],
            "deferred_admission_ms": stage_vals["deferred_admission_ms"],
            "boundary_poll_ms": stage_vals["boundary_poll_ms"],
            "message_dispatch_ms": stage_vals["message_dispatch_ms"],
            "message_handler_sum_ms": handlers_ms,
            "unattributed_dispatch_ms":
                max(0.0, stage_vals["message_dispatch_ms"]-handlers_ms),
            "message_handler_count": len(handler_rows),
            "snapshot_ms": stage_vals["snapshot_publication_ms"],
            "movement_persistence_ms": stage_vals["movement_persistence_ms"],
            "has_movement_snapshot": snap is not None,
            "compact_send_ms": number(snap["data"].get("compact_send_ms"),
                                      "COMPACT_SEND") if snap else 0.0,
            "compact_wire_count": len(compact_rows),
            "compact_wire_sums_ms": compact_sums,
            "has_movement_completion": completed is not None,
            "movement_completion_stages_ms": completion_values,
        })
    if not rows:
        raise ValueError("NO_SAME_FRAME_METRICS")
    p99=percentile([r["frame_interval_ms"] for r in rows],.99)
    tail=[r for r in rows if r["frame_interval_ms"]>=p99]
    no_capture=[r for r in rows if not r["has_movement_snapshot"]]
    if len(no_capture)<minimum_frames//3:
        raise ValueError("INSUFFICIENT_NON_SNAPSHOT_POPULATION")
    return {
        "schema": "dws.net_smooth.r31p22.exact_engine_frame_stages.v1",
        "verdict": "STAGE_ATTRIBUTION_VALID_ONLY_NOT_PERF_PASS",
        "frame_count": len(frames),
        "same_frame_count": len(rows),
        "missing_attribution_frame_count": len(missing),
        "snapshot_frame_count": len(snapshots),
        "compact_wire_event_count": len(trace["r31p22_compact_wire_stages"]),
        "message_handler_event_count":len(trace["server_message"]),
        "movement_completion_event_count":len(completion),
        "frame_interval_ms":dist([r["frame_interval_ms"] for r in rows]),
        "without_snapshot_frame_interval_ms":
            dist([r["frame_interval_ms"] for r in no_capture]),
        "p99_tail_frame_count":len(tail),
        "p99_tail_snapshot_fraction":
            sum(r["has_movement_snapshot"] for r in tail)/len(tail),
        "components_ms":{k:dist(values) for k,values in by_stage.items()},
        "compact_wire_components_ms":{k:dist(values) for k,values in by_wire.items()},
        "movement_completion_components_ms":
            {k:dist(values) for k,values in by_completion.items()},
        "worst_frame_samples":sorted(rows,key=lambda row:row["frame_interval_ms"],
                                     reverse=True)[:100],
        "important_limitations":[
            "Engine frame indices are comparable only inside this one server process.",
            "The frame probe interval includes other callbacks, tracing and host scheduling.",
            "The difference frame interval minus process time does not prove limiter/OS cause.",
            "COMPACT wire components measure create/send/flush on main thread; "
            "they do not prove when the network actually transmits data.",
            "No measured frame or prior normative failure is excluded.",
        ],
    }


def analyze_run(root: Path, *, require_completion: bool = False) -> dict:
    manifest=json.loads((root/"manifest.json").read_text(encoding="utf-8"))
    if (manifest.get("mode")!="gui" or manifest.get("profile")!="LOCAL"
        or manifest.get("scenario")!="r31-reconnect-roundtrip"
        or manifest.get("r31p22_loop_attribution") is not True
        or manifest.get("r31bp1_durable_chunks") is not True
        or manifest.get("r3c4r2_worker_envelope") is not True
        or manifest.get("completed") is not True
        or manifest.get("errors")):
        raise ValueError("INVALID_PRODUCT_GUI_MANIFEST")
    if (type(manifest.get("run_id")) is not str
        or len(manifest["run_id"])!=16):
        raise ValueError("RUN_ID_MISSING")
    if require_completion and manifest.get("r31p23_completion_attribution") is not True:
        raise ValueError("P23_COMPLETION_CANARY_NOT_ENABLED")
    report=json.loads((root/"report.json").read_text(encoding="utf-8"))
    trace=read_trace(root/"server"/"trace.jsonl",manifest["run_id"])
    result=analyze_events(trace)
    if require_completion and result["movement_completion_event_count"] < 1:
        raise ValueError("P23_NO_REAL_MOVEMENT_COMPLETION_RECORDED")
    result["source"]={
        "run_id":manifest["run_id"],
        "head":manifest.get("identity",{}).get("head"),
        "tree":manifest.get("identity",{}).get("tree"),
        "engine_sha256":manifest.get("identity",{}).get("godot_sha256"),
        "trace_sha256":trace["trace_sha256"],
        "original_normative_verdict":report.get("verdict"),
    }
    return result


def main()->int:
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("root",type=Path)
    ap.add_argument("--output",required=True,type=Path)
    ap.add_argument("--require-completion",action="store_true",
                    help="P2.3 R0: require nonzero exact writer completion stage coverage")
    args=ap.parse_args()
    try:
        result=analyze_run(args.root,require_completion=args.require_completion)
    except (ValueError,TypeError,KeyError,OSError,json.JSONDecodeError) as exc:
        print("R31P22_INCONCLUSIVE: "+str(exc))
        return 2
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2),
                           encoding="utf-8")
    print(json.dumps({
        "verdict":result["verdict"],
        "frames":result["same_frame_count"],
        "snapshot_fraction_of_p99_tail":result["p99_tail_snapshot_fraction"],
        "worst":result["worst_frame_samples"][:3],
        "normative":result["source"]["original_normative_verdict"],
    }))
    return 0


if __name__=="__main__":
    raise SystemExit(main())

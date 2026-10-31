#!/usr/bin/env python3
"""Fail-closed P1 full-population tail stats from ORIGINAL measured server trace.

No pinned / local path and no hard-coded AGG. Reject missing/partial trace,
incorrect identity, dropped events and invalid values. No raw file mutation.
Usage: python tools/net_smooth1/p1_tail_aggregates.py RUN_ROOT --output stats.json
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
from pathlib import Path
from analyze_r31p22_loop_stages import read_trace, positive_int, number, dist


def file_sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def summarize_run(root: Path) -> dict:
    manifest_path, report_path = root/"manifest.json", root/"report.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    report = json.loads(report_path.read_text(encoding="utf-8"))
    run_id = manifest.get("run_id")
    if type(run_id) is not str or len(run_id) != 16:
        raise ValueError("RUN_ID_INVALID")
    identity = manifest.get("identity",{})
    if (not isinstance(identity,dict) or not identity.get("head")
        or not identity.get("tree") or not identity.get("godot_sha256")):
        raise ValueError("SOURCE_IDENTITY_MISSING")
    trace = read_trace(root/"server"/"trace.jsonl", run_id)
    rows = trace["frame"]
    frames = {}
    for row in rows:
        data=row["data"]
        fid=positive_int(data.get("engine_frame"),"P1_ENGINE_FRAME")
        if fid in frames:
            raise ValueError("DUPLICATE_FRAME")
        frames[fid]=number(data.get("interval_ms"),"P1_INTERVAL")
    snapshot_ids = {
        positive_int(r["data"].get("engine_frame"),"P1_SNAPSHOT_FRAME")
        for r in trace["movement_snapshot_stages"]
    }
    loop_by_frame = {
        positive_int(r["data"].get("engine_frame"),"P1_LOOP_FRAME"):r["data"]
        for r in trace["r31p22_loop_stages"]
    }
    if len(loop_by_frame) != len(trace["r31p22_loop_stages"]):
        raise ValueError("DUPLICATE_LOOP_STAGE")
    if len(frames) < 100 or len(snapshot_ids) < 10:
        raise ValueError("P1_INSUFFICIENT_FRAME_OR_SNAPSHOT_POPULATION")
    over={fid for fid,value in frames.items() if value>25.0}
    with_snapshot=over & snapshot_ids
    with_checkpoint={
        fid for fid in over
        if number(loop_by_frame.get(fid,{}).get("movement_persistence_ms",0),
                  "P1_PERSISTENCE")>5.0
    }
    bare={
        fid for fid in over
        if fid not in snapshot_ids and fid not in with_checkpoint
        and sum(number(v,"P1_STAGE") for key,v in
                loop_by_frame.get(fid,{}).items() if key.endswith("_ms"))<20.0
    }
    flush=[
        number(r["data"].get("outbound_flush_ms"),"P1_FLUSH")
        for r in trace["r31p22_compact_wire_stages"]
    ]
    if not flush:
        raise ValueError("P1_MISSING_COMPACT_WIRE")
    result={
        "schema":"dws.net_smooth.p1_full_tail_aggregates.v2",
        "source_run_id":run_id,
        "source_head":identity["head"],"source_tree":identity["tree"],
        "original_normative_verdict":report.get("verdict"),
        "manifest_sha256":file_sha(manifest_path),
        "report_sha256":file_sha(report_path),
        "server_trace_sha256":trace["trace_sha256"],
        "count_frames":len(frames),
        "count_over25":len(over),
        "count_over25_with_snapshot":len(with_snapshot),
        "count_over25_with_checkpoint":len(with_checkpoint),
        "count_over25_bare":len(bare),
        "fraction_of_over25_with_snapshot":len(with_snapshot)/len(over) if over else 0.0,
        "flush_stage_ms":dist(flush),
        "interpretation":"SNAPSHOT_COINCIDENCE_NOT_PROOF_OF_FLUSH_CAUSALITY",
    }
    return result


def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_root",type=Path)
    parser.add_argument("--output",type=Path,required=True)
    args=parser.parse_args()
    try:
        result=summarize_run(args.run_root)
    except (OSError,ValueError,TypeError,KeyError,json.JSONDecodeError) as exc:
        print("P1_RAW_AGGREGATE_INCONCLUSIVE:"+str(exc))
        return 2
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf-8")
    print(json.dumps({
        "verdict":result["original_normative_verdict"],
        "snapshot_fraction":result["fraction_of_over25_with_snapshot"],
        "trace_sha256":result["server_trace_sha256"],
    }))
    return 0


if __name__=="__main__":
    raise SystemExit(main())

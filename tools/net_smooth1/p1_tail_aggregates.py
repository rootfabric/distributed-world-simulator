#!/usr/bin/env python3
"""Aggregate tail statistics per run for the P1 evidence report."""
import json
from pathlib import Path

BASE = Path(r"C:\distributed-world-simulator\work\ns1-p0-r22-20261024\artifacts\net-smooth1")
RUNS = ["r31p23r22-p0-pair1-off", "r31p23r22-p0-pair1-on",
        "r31p23r22-p0-pair2-off", "r31p23r22-p0-pair2-on",
        "r31p23r22-p0-pair3-off", "r31p23r22-p0-pair3-on"]

for run in RUNS:
    trace = []
    lo = hi = None
    with (BASE / run / "server" / "trace.jsonl").open(encoding="utf-8") as f:
        for line in f:
            r = json.loads(line)
            if r["kind"] == "measure_start":
                lo = r["t_us"]
            elif r["kind"] == "measure_end":
                hi = r["t_us"]
            elif r["kind"] in ("frame", "r31p22_loop_stages", "r31p22_compact_wire_stages",
                               "movement_snapshot_stages"):
                r["_k"] = r["kind"]
                trace.append(r)
    frames = [r for r in trace if r["_k"] == "frame" and lo <= r["t_us"] <= hi]
    stages = {r["data"]["engine_frame"]: r["data"] for r in trace if r["_k"] == "r31p22_loop_stages"}
    snaps = {r["data"]["engine_frame"]: r["data"] for r in trace if r["_k"] == "movement_snapshot_stages"}
    over = [f for f in frames if f["data"]["interval_ms"] > 25]
    with_snap = [f for f in over if f["data"]["engine_frame"] in snaps]
    with_ckpt = [f for f in over if stages.get(f["data"]["engine_frame"], {}).get("movement_persistence_ms", 0) > 5]
    bare = [f for f in over if f["data"]["engine_frame"] not in snaps
            and stages.get(f["data"]["engine_frame"], {}).get("movement_persistence_ms", 0) <= 5
            and sum(float(v) for k, v in stages.get(f["data"]["engine_frame"], {}).items() if k.endswith("_ms")) < 20]
    wire = [r["data"] for r in trace if r["_k"] == "r31p22_compact_wire_stages" and lo <= r["t_us"] <= hi]
    fl = sorted(w["outbound_flush_ms"] for w in wire)
    print(run)
    print("  frames=%d >25ms=%d (%.1f%%) of which snapshot=%d checkpoint=%d bare-uncovered=%d" % (
        len(frames), len(over), 100 * len(over) / len(frames), len(with_snap), len(with_ckpt), len(bare)))
    print("  flush_ms p50=%.2f p99=%.2f max=%.1f" % (
        fl[len(fl) // 2], fl[max(0, int(len(fl) * .99) - 1)], fl[-1]))

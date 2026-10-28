#!/usr/bin/env python3
"""Cross-process worst-frame-gap comparison, aligned to each trace's measure_start."""
import json
from pathlib import Path

BASE = Path(r"C:\distributed-world-simulator\work\ns1-p0-r22-20261024\artifacts\net-smooth1")
RUNS = ["r31p23r22-p0-pair1-off", "r31p23r22-p0-pair1-on",
        "r31p23r22-p0-pair2-off", "r31p23r22-p0-pair2-on",
        "r31p23r22-p0-pair3-off", "r31p23r22-p0-pair3-on"]

for run in RUNS:
    print("=" * 8, run)
    for role in ["server", "a", "b"]:
        rows = []
        lo = hi = None
        with (BASE / run / role / "trace.jsonl").open(encoding="utf-8") as f:
            for line in f:
                r = json.loads(line)
                t = r["t_us"]
                k = r["kind"]
                if k == "measure_start":
                    lo = t
                elif k == "measure_end":
                    hi = t
                elif k == "frame":
                    rows.append((t, r["data"].get("interval_ms", 0)))
        rows = [(t, g) for t, g in rows if lo is not None and hi is not None and lo <= t <= hi]
        tops = sorted(rows, key=lambda x: -x[1])[:5]
        print(role, "lo/hi", lo, hi, "n", len(rows),
              [(round((t - lo) / 1e6, 2), round(g, 1)) for t, g in tops] if lo else [])

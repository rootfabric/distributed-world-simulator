#!/usr/bin/env python3
"""R3.1a/b read-only ON/OFF long-frame attribution across process-local traces.

Do not interpret absence of engine stages as proof of host noise. Trace event
clocks are local to each PROCESS; never correlate timestamps across processes.
Normative analyze_net_smooth1.py must be run separately and unchanged.
"""
from __future__ import annotations

import argparse
import bisect
import json
import math
from pathlib import Path
from typing import Any

WINDOW_US = 125000
ENGINE_KINDS = ("checkpoint_capture", "checkpoint_complete",
                "movement_snapshot_stages", "periodic_checkpoint_dispatch")


def percentile(values: list[float], q: float) -> float | None:
    if not values:
        return None
    s = sorted(values)
    return s[min(len(s) - 1, max(0, math.ceil(q * len(s)) - 1))]


def ensure_number(raw: Any, field: str, line: int) -> float:
    if type(raw) not in (float, int) or not math.isfinite(raw) or raw < 0:
        raise ValueError(f"INVALID_{field} at line {line}")
    return float(raw)


def read_events(path: Path) -> list[dict]:
    result: list[dict] = []
    last_t = -1.0
    with path.open(encoding="utf-8") as stream:
        for line_no, raw in enumerate(stream, 1):
            if len(raw) > 1024 * 1024:
                raise ValueError(f"OVERSIZED_RECORD at {line_no}")
            event = json.loads(raw)
            if not isinstance(event, dict) or not isinstance(event.get("data", {}), dict):
                raise ValueError(f"INVALID_EVENT at {line_no}")
            t = ensure_number(event.get("t_us"), "CLOCK", line_no)
            if t < last_t:
                raise ValueError(f"NONMONOTONE_CLOCK at {line_no}")
            last_t = t
            result.append(event)
    if not result:
        raise ValueError("EMPTY_TRACE")
    if result[0].get("kind") != "header":
        raise ValueError("MISSING_TRACE_HEADER")
    if result[-1].get("kind") != "end":
        raise ValueError("MISSING_TRACE_END")
    return result


def role_metrics(root: Path, role: str) -> dict:
    events = read_events(root / role / "trace.jsonl")
    frames: list[dict] = []
    loops: list[dict] = []
    stages: dict[str, list[dict]] = {name: [] for name in ENGINE_KINDS}
    stage_times: dict[str, list[float]] = {name: [] for name in ENGINE_KINDS}
    for ev in events:
        if ev.get("measure") is not True:
            continue
        kind = ev.get("kind")
        if kind == "frame":
            ms = ensure_number(ev["data"].get("interval_ms"), "FRAME_MS", 0)
            frames.append({"t_us": float(ev["t_us"]), "gap_ms": ms})
        elif kind == "server_loop":
            ms = ensure_number(ev["data"].get("process_ms"), "PROCESS_MS", 0)
            loops.append({"t_us": float(ev["t_us"]), "process_ms": ms})
        elif kind in stages:
            stages[kind].append(ev)
            stage_times[kind].append(float(ev["t_us"]))
    if len(frames) < 100:
        raise ValueError(f"{root.name}/{role}: INSUFFICIENT_FRAMES")
    gaps = [e for e in frames if e["gap_ms"] > 100]
    long_50 = [e for e in frames if e["gap_ms"] > 50]
    loop_times = [x["t_us"] for x in loops]
    # Exact server-loop interarrival gaps: a long wall gap paired with a
    # short _process() duration is observable but not proof of DPC/OS/GPU.
    long_server_intervals = [
        {
            "local_t_us": curr["t_us"],
            "server_loop_interarrival_ms": (curr["t_us"] - prior["t_us"]) / 1000.0,
            "server_process_ms": curr["process_ms"],
        }
        for prior, curr in zip(loops, loops[1:])
        if (curr["t_us"] - prior["t_us"]) / 1000.0 > 100.0
    ]
    diagnostics = []
    for gap in gaps:
        t = gap["t_us"]
        near: dict[str, int] = {}
        for kind in ENGINE_KINDS:
            timestamps = stage_times[kind]
            left = bisect.bisect_left(timestamps, t-WINDOW_US)
            right = bisect.bisect_right(timestamps, t+WINDOW_US)
            near[kind] = right-left
        i = bisect.bisect_left(loop_times, t-WINDOW_US)
        j = bisect.bisect_right(loop_times, t+WINDOW_US)
        local_process_ms = max([x["process_ms"] for x in loops[i:j]], default=None)
        diagnostics.append({
            "local_t_us": t,
            "frame_gap_ms": gap["gap_ms"],
            "nearby_engine_stage_counts_125ms": near,
            "nearby_server_process_max_ms": local_process_ms,
            "engine_stage_association_is_not_causality": True,
        })
    return {
        "role": role,
        "trace_path": str(root / role / "trace.jsonl"),
        "frame_count": len(frames),
        "gaps_over_50ms": len(long_50),
        "gaps_over_100ms": len(gaps),
        "max_gap_ms": max((e["gap_ms"] for e in frames), default=None),
        "p99_gap_ms": percentile([e["gap_ms"] for e in frames], .99),
        "server_loop_count": len(loops),
        "server_process_p99_ms": percentile([e["process_ms"] for e in loops], .99),
        "server_loop_gaps_over_100ms": len(long_server_intervals),
        "server_loop_gap_max_ms": max(
            [x["server_loop_interarrival_ms"] for x in long_server_intervals], default=0.0),
        "server_loop_gap_examples": long_server_intervals[:40],
        "long_gaps": diagnostics[:40],
        "long_gaps_truncated": len(diagnostics) > 40,
    }


def review_run(root: Path, arm: str) -> dict:
    if arm not in ("on", "off"):
        raise ValueError("INVALID_ARM")
    manifest = json.loads((root/"manifest.json").read_text(encoding="utf-8"))
    if (manifest.get("mode") != "gui" or manifest.get("profile") != "LOCAL"
            or manifest.get("completed") is not True or manifest.get("errors")):
        raise ValueError(f"{root.name}: INVALID_GUI_MANIFEST")
    expected = arm == "on"
    if manifest.get("r3c4r31_replay_projection") is not expected:
        raise ValueError(f"{root.name}: WRONG_REPLAY_CANARY")
    if manifest.get("scenario") != "r31-reconnect-roundtrip":
        raise ValueError(f"{root.name}: WRONG_SCENARIO")
    return {
        "root": str(root), "arm": arm,
        "head": manifest.get("identity", {}).get("head"),
        "engine_sha256": manifest.get("identity", {}).get("godot_sha256"),
        "assets_sha256": manifest.get("identity", {}).get("asset_manifest_sha256"),
        "roles": {role: role_metrics(root, role) for role in ("server", "a", "b")}
    }


def compare(pairs: list[tuple[Path, Path]]) -> dict:
    comparisons = []
    for idx, (off_path, on_path) in enumerate(pairs, 1):
        off = review_run(off_path, "off")
        on = review_run(on_path, "on")
        for field in ("head", "engine_sha256", "assets_sha256"):
            if not off[field] or off[field] != on[field]:
                raise ValueError(f"pair {idx}: IDENTITY_MISMATCH_{field}")
        comparisons.append({"pair": idx, "off": off, "on": on})
    def summarize(arm: str) -> dict:
        runs = [pair[arm]["roles"]["server"] for pair in comparisons]
        return {
            "runs": len(runs),
            "server_long_gap_counts": [r["gaps_over_100ms"] for r in runs],
            "server_loop_gaps_over_100ms": [r["server_loop_gaps_over_100ms"] for r in runs],
            "server_max_ms": [r["max_gap_ms"] for r in runs],
            "server_process_p99_ms": [r["server_process_p99_ms"] for r in runs],
        }
    return {"schema": "dws.net_smooth.r31_long_gap_forensics.v1",
            "verdict": "DIAGNOSTIC_ONLY_NO_CAUSAL_ATTRIBUTION",
            "off": summarize("off"), "on": summarize("on"),
            "paired": comparisons,
            "limitations": [
                "±125ms proximity is association, not proof of causality",
                "Process-local clocks never permit cross-process timestamp joins",
                "No telemetry here can by itself establish Windows DPC, GPU, GC, or scheduling as root cause",
                "Missing engine stage is not proof of external host noise",
            ]}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--pair", nargs=2, action="append", required=True,
                    metavar=("OFF_ROOT", "ON_ROOT"), type=Path)
    ap.add_argument("--output", type=Path, required=True)
    a = ap.parse_args()
    try:
        result = compare(a.pair)
    except (ValueError, OSError, KeyError, TypeError, json.JSONDecodeError) as e:
        print(f"LONG_GAP_INCONCLUSIVE: {type(e).__name__}: {e}")
        return 2
    a.output.parent.mkdir(parents=True, exist_ok=True)
    a.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"verdict": result["verdict"], "off": result["off"], "on": result["on"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

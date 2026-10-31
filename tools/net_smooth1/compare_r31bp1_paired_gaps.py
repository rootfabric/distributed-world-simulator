#!/usr/bin/env python3
"""R31b P1 three-pair same-HEAD OFF/ON paired gap forensics.

Unlike the historic R31a comparator (where OFF meant replay-cache disabled),
THIS comparator requires in BOTH arms:
- R31a replay projection ON, and
- R31b P0 durable attribution ON.
The ON arm additionally carries the R31b P1 durable chunk cache flag.

It reports all actual >100ms frame gaps server/client, server process
durations and server-loop interarrival gaps. Proximity is NOT causality and
no p99 stage values are summed.
"""
from __future__ import annotations

import argparse
import bisect
import json
import math
from pathlib import Path

WINDOW_US = 125_000


def percentile(seq: list[float], q: float) -> float:
    if not seq:
        return float("nan")
    vals = sorted(seq)
    return vals[min(len(vals)-1, max(0, math.ceil(q*len(vals))-1))]


def read_events(path: Path) -> list[dict]:
    events: list[dict] = []
    last_t = 0.0
    with path.open(encoding="utf-8") as source:
        for line_no, raw in enumerate(source, 1):
            if len(raw) > 1024 * 1024:
                raise ValueError(f"OVERSIZED_RECORD at {line_no}")
            event = json.loads(raw)
            if not isinstance(event, dict) or not isinstance(event.get("data", {}), dict):
                raise ValueError(f"INVALID_EVENT at {line_no}")
            t = event.get("t_us")
            if type(t) not in (int, float) or not math.isfinite(t):
                raise ValueError(f"BAD_CLOCK at {line_no}")
            if t < last_t:
                raise ValueError(f"NONMONOTONE_CLOCK at {line_no}")
            last_t = float(t)
            events.append(event)
    if not events or events[0].get("kind") != "header" or events[-1].get("kind") != "end":
        raise ValueError(f"{path}: MISSING_TRACE_HEADER_OR_END")
    return events


def role_metrics(root: Path, role: str) -> dict:
    events = read_events(root / role / "trace.jsonl")
    frames: list[dict] = []
    loops: list[dict] = []
    stage_times: list[float] = []
    for ev in events:
        if ev.get("measure") is not True:
            continue
        kind = ev.get("kind")
        if kind == "frame":
            ms = ev["data"].get("interval_ms")
            if type(ms) not in (int, float) or not math.isfinite(ms) or ms < 0:
                raise ValueError(f"{root.name}/{role}: BAD_FRAME_MS")
            frames.append({"t_us": float(ev["t_us"]), "gap_ms": float(ms)})
        elif kind == "server_loop":
            ms = ev["data"].get("process_ms")
            if type(ms) not in (int, float) or not math.isfinite(ms) or ms < 0:
                raise ValueError(f"{root.name}/{role}: BAD_SERVER_PROCESS_MS")
            loops.append({"t_us": float(ev["t_us"]), "process_ms": float(ms)})
        elif kind == "checkpoint_capture":
            stages = ev["data"].get("r31b_durable_stages", {})
            if isinstance(stages, dict) and type(stages.get("valid")) is bool:
                if stages["valid"] is True and stages.get("seam_coordinator_count", 0) >= 1:
                    stage_times.append(float(ev["t_us"]))
    gaps = [e for e in frames if e["gap_ms"] > 100]
    long_50 = [e for e in frames if e["gap_ms"] > 50]
    loop_times = [x["t_us"] for x in loops]
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
        i = bisect.bisect_left(stage_times, t-WINDOW_US)
        j = bisect.bisect_right(stage_times, t+WINDOW_US)
        k = bisect.bisect_left(loop_times, t-WINDOW_US)
        l = bisect.bisect_right(loop_times, t+WINDOW_US)
        diagnostics.append({
            "local_t_us": t,
            "frame_gap_ms": gap["gap_ms"],
            "nearby_r31b_durable_captures_125ms": j - i,
            "nearby_server_process_max_ms": max(
                [x["process_ms"] for x in loops[k:l]], default=None),
            "association_is_not_causality": True,
        })
    return {
        "role": role,
        "trace_path": str(root / role / "trace.jsonl"),
        "frame_count": len(frames),
        "gaps_over_50ms": len(long_50),
        "gaps_over_100ms": len(gaps),
        "max_gap_ms": max((e["gap_ms"] for e in frames), default=None),
        "p99_gap_ms": percentile([e["gap_ms"] for e in frames], .99),
        "p99_9_gap_ms": percentile([e["gap_ms"] for e in frames], .999),
        "server_loop_count": len(loops),
        "server_process_p99_ms": percentile([e["process_ms"] for e in loops], .99),
        "server_loop_gaps_over_100ms": len(long_server_intervals),
        "server_loop_gap_max_ms": max(
            [x["server_loop_interarrival_ms"] for x in long_server_intervals], default=0.0),
        "long_gaps": diagnostics[:40],
        "long_gaps_truncated": len(diagnostics) > 40,
    }


def review_run(root: Path, expect_chunks: bool) -> dict:
    manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
    if (manifest.get("mode") != "gui" or manifest.get("profile") != "LOCAL"
            or manifest.get("completed") is not True or manifest.get("errors")):
        raise ValueError(f"{root.name}: INVALID_GUI_MANIFEST")
    if manifest.get("scenario") != "r31-reconnect-roundtrip":
        raise ValueError(f"{root.name}: WRONG_SCENARIO")
    # Intentional R31b P1 contract: BOTH arms run R31a replay + P0 attribution.
    if manifest.get("r3c4r31_replay_projection") is not True:
        raise ValueError(f"{root.name}: R31A_REPLAY_NOT_ON_IN_BOTH_ARMS")
    if manifest.get("r3c4r31b_durable_attribution") is not True:
        raise ValueError(f"{root.name}: P0_ATTRIBUTION_NOT_ON_IN_BOTH_ARMS")
    if bool(manifest.get("r31bp1_durable_chunks", False)) is not expect_chunks:
        raise ValueError(f"{root.name}: WRONG_P1_CHUNK_ARM")
    return {
        "root": str(root),
        "head": manifest.get("identity", {}).get("head"),
        "engine_sha256": manifest.get("identity", {}).get("godot_sha256"),
        "assets_sha256": manifest.get("identity", {}).get("asset_manifest_sha256"),
        "roles": {role: role_metrics(root, role) for role in ("server", "a", "b")},
    }


def compare(pairs: list[tuple[Path, Path]]) -> dict:
    comparisons = []
    for idx, (off_path, on_path) in enumerate(pairs, 1):
        off = review_run(off_path, False)
        on = review_run(on_path, True)
        for field in ("head", "engine_sha256", "assets_sha256"):
            if not off[field] or off[field] != on[field]:
                raise ValueError(f"pair {idx}: IDENTITY_MISMATCH_{field}")
        comparisons.append({"pair": idx, "off": off, "on": on})

    def summarize(arm: str) -> dict:
        servers = [pair[arm]["roles"]["server"] for pair in comparisons]
        clients = [
            pair[arm]["roles"][role]
            for pair in comparisons for role in ("a", "b")
        ]
        return {
            "runs": len(servers),
            "server_gaps_over_100ms": [r["gaps_over_100ms"] for r in servers],
            "server_loop_gaps_over_100ms": [r["server_loop_gaps_over_100ms"] for r in servers],
            "server_max_gap_ms": [r["max_gap_ms"] for r in servers],
            "server_process_p99_ms": [r["server_process_p99_ms"] for r in servers],
            "client_gaps_over_100ms": [r["gaps_over_100ms"] for r in clients],
            "client_max_gap_ms": [r["max_gap_ms"] for r in clients],
        }

    return {
        "schema": "dws.net_smooth.r31bp1.paired_gap_forensics.v1",
        "verdict": "R31BP1_PAIRED_GAP_EVIDENCE_ONLY",
        "comparisons": comparisons,
        "summary": {"off": summarize("off"), "on": summarize("on")},
        "limitations": [
            "Proximity of a long gap to a durable capture is not causation.",
            "Historic unaccounted >100ms R31a spikes still block final acceptance.",
            "Stage p99 values must never be summed into a total.",
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pair", nargs=2, action="append", required=True,
                        metavar=("OFF", "ON"), type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = compare([(off, on) for off, on in args.pair])
    except (ValueError, OSError, TypeError, json.JSONDecodeError) as exc:
        print(f"R31BP1_PAIRED_GAPS_INCONCLUSIVE: {exc}")
        return 2
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({
        "status": result["verdict"],
        "pairs": len(result["comparisons"]),
        "server_gaps_off": result["summary"]["off"]["server_gaps_over_100ms"],
        "server_gaps_on": result["summary"]["on"]["server_gaps_over_100ms"],
    }))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

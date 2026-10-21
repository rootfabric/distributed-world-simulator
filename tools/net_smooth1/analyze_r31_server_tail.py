#!/usr/bin/env python3
"""Read-only PR814 six-trace review; not a new perf benchmark or a validator bypass.

Pair server frame intervals with server_loop callbacks on THE SAME PROCESS
clock. Never align clients to server clocks. Event timestamps are emit times,
not exact callback boundaries: report approximate association, not causality.
The original normative report is retained even when a conditional population
looks faster. No source trace, threshold, game state or current PR is modified.
"""
from __future__ import annotations

import argparse
import bisect
import hashlib
import json
import math
from pathlib import Path
from typing import Any

EXPECTED_HEAD = "fdfbfb3b8dff911e6fd081a157652a28e1052cff"
EXPECTED_TREE = "585062871595267cbee4de38a1a8e41cec3a2605"
CLOCK_TOLERANCE_MS = 1.0
BASE_FLAGS = ("r3c4_periodic_frame_pacing", "r3c4r2_worker_envelope",
              "r3c4r31_replay_projection", "r3c4r31b_durable_attribution",
              "r31bp1_durable_chunks")
IDENTITY_KEYS = ("head", "tree", "godot_sha256", "asset_manifest_sha256")


def number(v: Any, name: str) -> float:
    if type(v) not in (int, float) or not math.isfinite(v) or v < 0:
        raise ValueError("INVALID_NONNEGATIVE_NUMBER:" + name)
    return float(v)


def stats(values: list[float]) -> dict:
    s = sorted(values)
    def p(q):
        return s[max(0, math.ceil(q * len(s)) - 1)] if s else None
    return {"n": len(s), "p50": p(.5), "p95": p(.95), "p99": p(.99),
            "p999": p(.999), "max": s[-1] if s else None}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def read_trace(path: Path, run_id: str) -> dict:
    """Require original v1 sequence/header/footer and the complete measure window."""
    kept = {k: [] for k in ("frame", "server_loop", "checkpoint_capture")}
    n = 0
    last_t = -1.0
    header = end = start_t = end_t = None
    measured = False
    with path.open(encoding="utf-8") as stream:
        for line_no, raw in enumerate(stream, 1):
            if line_no > 1000000 or len(raw) > 1024 * 1024:
                raise ValueError("TRACE_LIMIT_EXCEEDED")
            row = json.loads(raw)
            if not isinstance(row, dict) or not isinstance(row.get("data"), dict):
                raise ValueError("BAD_TRACE_SHAPE")
            t = number(row.get("t_us"), "t_us")
            if t < last_t or end is not None:
                raise ValueError("TRACE_CLOCK_OR_END_INVALID")
            last_t = t
            kind = row.get("kind")
            if line_no == 1:
                header = row
                if (kind != "header" or row["data"].get("schema") != "dws.net_smooth.trace.v1"
                        or row["data"].get("role") != "server"
                        or row["data"].get("run_id") != run_id
                        or row["data"].get("clock") != "PROCESS_LOCAL_MONOTONIC_US"):
                    raise ValueError("WRONG_HEADER_RUN_ROLE_OR_CLOCK")
            if kind == "end":
                end = row["data"]
                continue
            n += 1
            if type(row.get("n")) is not int or row["n"] != n:
                raise ValueError("TRACE_SEQUENCE_LOSS")
            if type(row.get("measure")) is not bool:
                raise ValueError("TRACE_MEASURE_FLAG_MISSING")
            if kind == "measure_start":
                if start_t is not None or row["measure"] is not True:
                    raise ValueError("BAD_MEASURE_START")
                start_t, measured = t, True
            elif kind == "measure_end":
                if start_t is None or end_t is not None or row["measure"] is not True:
                    raise ValueError("BAD_MEASURE_END")
                end_t, measured = t, False
                continue
            if row["measure"] != measured:
                raise ValueError("MEASUREMENT_EVENT_OUTSIDE_WINDOW")
            if kind in kept:
                # Keep unmeasured boundary frames too; a first frame which
                # straddles measure_start remains normative but is not paired.
                kept[kind].append(row)
    if (header is None or end is None or start_t is None or end_t is None
            or end.get("dropped") != 0 or end.get("io_errors") != 0
            or end.get("written") != n or end.get("produced") != n):
        raise ValueError("INCOMPLETE_OR_LOSSY_TRACE")
    return {**kept, "start_us": start_t, "end_us": end_t,
            "duration_s": (end_t-start_t)/1e6, "header": header["data"]}


def analyze_trace(trace: dict) -> dict:
    loops = trace["server_loop"]
    loop_times = [float(e["t_us"]) for e in loops]
    captures = trace["checkpoint_capture"]
    cap_end = [float(e["t_us"]) for e in captures]
    cap_start = [t - number(e["data"].get("capture_ms"), "capture_ms")*1000
                 for t, e in zip(cap_end, captures)]
    if any(b < a for a, b in zip(cap_start, cap_start[1:])):
        raise ValueError("CAPTURE_INTERVALS_OUT_OF_ORDER")
    rows = []
    previous = None
    for event in trace["frame"]:
        if not event["measure"]:
            previous = event
            continue
        t = float(event["t_us"])
        ms = number(event["data"].get("interval_ms"), "frame.interval_ms")
        left = t - ms*1000
        reasons = []
        if previous is None or not previous["measure"]:
            reasons.append("measurement_boundary_frame")
        elif abs((t-float(previous["t_us"]))/1000-ms) > CLOCK_TOLERANCE_MS:
            reasons.append("emit_clock_vs_probe_clock_discrepancy")
        if left < trace["start_us"]:
            reasons.append("window_starts_before_measure_start")
        li, ri = bisect.bisect_right(loop_times, left), bisect.bisect_right(loop_times, t)
        associated = loops[li:ri]
        proc = None
        if len(associated) != 1:
            reasons.append("server_loop_count_not_one")
        else:
            proc = number(associated[0]["data"].get("process_ms"), "server_loop.process_ms")
            if proc > ms + CLOCK_TOLERANCE_MS:
                reasons.append("reported_process_exceeds_probe_interval")
        ci = bisect.bisect_left(cap_end, left)
        cj = bisect.bisect_right(cap_start, t)
        overlap = [i for i in range(ci, max(ci, cj))
                   if cap_end[i] > left and cap_start[i] < t]
        data = associated[0]["data"] if len(associated) == 1 else {}
        stages = {k: number(data[k], k) for k in
                  ("message_ms", "fixed_ms", "snapshot_ms", "persistence_ms") if k in data}
        # Never treat server_loop.capture_ms as current-frame work: this
        # runtime carries the last completed capture value into later loops.
        rows.append({
            "n": event["n"], "local_t_us": t, "frame_ms": ms,
            "engine_process_ms_monitor": event["data"].get("engine_process_ms"),
            "reported_server_process_ms": proc,
            "uncovered_probe_interval_ms": max(0.0, ms-proc) if not reasons and proc is not None else None,
            "association": "APPROXIMATE_SAME_PROCESS_WINDOW" if not reasons else "UNRESOLVED",
            "association_limitations": reasons, "server_loop_count": len(associated),
            "server_stages_ms": stages,
            "capture_overlap": bool(overlap),
            "capture_events": [{"n": captures[i]["n"],
                                "capture_ms": captures[i]["data"]["capture_ms"],
                                "authority_ms": captures[i]["data"].get("authority_ms"),
                                "replay_ms": captures[i]["data"].get("replay_ms"),
                                "handoff_ms": captures[i]["data"].get("handoff_ms"),
                                "validation_ms": captures[i]["data"].get("r31b_durable_stages", {}).get("validation_ms")}
                               for i in overlap],
        })
        previous = event
    if not rows:
        raise ValueError("NO_MEASURED_FRAMES")
    distribution = stats([r["frame_ms"] for r in rows])
    tail = [r for r in rows if r["frame_ms"] >= distribution["p99"]]
    def bucket(rs):
        aligned = [r for r in rs if r["association"] != "UNRESOLVED"]
        return {
            "frames": len(rs), "frames_over_25ms": sum(r["frame_ms"] > 25 for r in rs),
            "frames_over_100ms": sum(r["frame_ms"] > 100 for r in rs),
            "unaligned_frames": len(rs)-len(aligned),
            "frame_ms": stats([r["frame_ms"] for r in rs]),
            "reported_process_ms": stats([r["reported_server_process_ms"] for r in aligned]),
            "uncovered_probe_interval_ms": stats([r["uncovered_probe_interval_ms"] for r in aligned]),
        }
    return {
        "all_measured_frames": bucket(rows), "p99_tail": bucket(tail),
        "capture_overlap_frames": bucket([r for r in rows if r["capture_overlap"]]),
        "no_capture_overlap_frames": bucket([r for r in rows if not r["capture_overlap"]]),
        "capture_fraction_of_all_frames": sum(r["capture_overlap"] for r in rows)/len(rows),
        "capture_fraction_of_p99_tail": sum(r["capture_overlap"] for r in tail)/len(tail),
        "measured_capture_events": sum(e["measure"] for e in captures),
        "highest_intervals": sorted(rows, key=lambda r: r["frame_ms"], reverse=True)[:100],
        "tail_sample_limit": 100,
    }


def review_run(root: Path, arm: str) -> dict:
    paths = [root/"manifest.json", root/"report.json", root/"server"/"trace.jsonl"]
    before = {str(p): sha256(p) for p in paths}
    manifest = json.loads(paths[0].read_text(encoding="utf-8-sig"))
    normative = json.loads(paths[1].read_text(encoding="utf-8-sig"))
    ident = manifest.get("identity", {})
    if (manifest.get("mode") != "gui" or manifest.get("profile") != "LOCAL"
            or manifest.get("scenario") != "r31-reconnect-roundtrip"
            or manifest.get("completed") is not True
            or number(manifest.get("duration_s"), "duration_s") < 120
            or ident.get("head") != EXPECTED_HEAD or ident.get("tree") != EXPECTED_TREE
            or ident.get("tracked_dirty") is not False
            or manifest.get("r31bp20_validator_attribution") is not (arm == "on")):
        raise ValueError("WRONG_EXACT_HEAD_TREE_SCENARIO_OR_ARM:"+str(root))
    if any(manifest.get(k) is not True for k in BASE_FLAGS):
        raise ValueError("MISSING_COMMON_FLAGS:"+str(root))
    if not isinstance(manifest.get("run_id"), str) or not manifest["run_id"]:
        raise ValueError("RUN_ID_MISSING")
    trace = read_trace(paths[2], manifest["run_id"])
    if trace["duration_s"] < 118:
        raise ValueError("MEASURED_WINDOW_TOO_SHORT")
    result = analyze_trace(trace)
    after = {str(p): sha256(p) for p in paths}
    if before != after:
        raise ValueError("INPUT_CHANGED_DURING_READ")
    return {"root": str(root), "arm": arm, "run_id": manifest["run_id"],
            "identity": {k: ident.get(k) for k in IDENTITY_KEYS},
            "normative_verdict_unmodified": normative.get("verdict", "MISSING"),
            "manifest_errors_preserved": manifest.get("errors", []),
            "cleanup_report_unmodified": manifest.get("cleanup", {}),
            "server_trace_pid": trace["header"].get("pid"),
            "duration_s": trace["duration_s"], "source_sha256_before_after": before,
            "server": result}


def compare(pairs: list[tuple[Path, Path]]) -> dict:
    if len(pairs) != 3:
        raise ValueError("THREE_HISTORICAL_PAIRS_REQUIRED")
    results, reference, seen = [], None, set()
    for index, (off, on) in enumerate(pairs, 1):
        row = {"pair": index}
        for arm, root in (("off", off), ("on", on)):
            value = review_run(root.resolve(), arm)
            if value["run_id"] in seen:
                raise ValueError("DUPLICATE_RUN")
            seen.add(value["run_id"])
            if any(not value["identity"][k] for k in IDENTITY_KEYS):
                raise ValueError("IDENTITY_FIELD_MISSING")
            if reference is not None and reference != value["identity"]:
                raise ValueError("ACROSS_PAIRS_HEAD_TREE_ENGINE_OR_ASSET_DRIFT")
            reference = value["identity"]
            row[arm] = value
        results.append(row)
    return {"schema": "dws.r31bp21.historical_tail_review.v1",
            "verdict": "READ_ONLY_ASSOCIATION_NOT_PERFORMANCE_ACCEPTANCE",
            "pairs": results, "expected_product_head": EXPECTED_HEAD,
            "limitations": [
                "All measured frames and the original normative FAIL remain; conditional groups are not acceptance.",
                "Emit timestamps approximate probe/callback endpoints; unresolved windows are counted, never silently reassigned.",
                "Uncovered interval includes engine scheduling, frame cap, other callbacks, trace work and OS delays; NOT proof of sleep or host cause.",
                "server_loop.process_ms excludes its own subsequent trace emission and final SERVER_HEALTH/debug reporting.",
                "Engine Performance.TIME_PROCESS is a monitor sample, not proven same-callback CPU time.",
                "No sum of independent percentiles or cross-process monotonic clock joins.",
                "Existing server_loop.capture_ms is sticky; only actual checkpoint_capture events define overlap."]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pair", nargs=2, type=Path, action="append", required=True,
                        metavar=("P20_OFF_ROOT", "P20_ON_ROOT"))
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    dest = args.output.resolve()
    try:
        if dest.exists() or any(dest.is_relative_to(p.resolve()) for pair in args.pair for p in pair):
            raise ValueError("OUTPUT_MUST_BE_NEW_AND_OUTSIDE_EVIDENCE_ROOTS")
        report = compare(args.pair)
        report["analyzer_sha256"] = sha256(Path(__file__))
        dest.parent.mkdir(parents=True, exist_ok=True)
        with dest.open("x", encoding="utf-8") as stream:
            json.dump(report, stream, ensure_ascii=False, indent=2, allow_nan=False)
        print(json.dumps({"verdict": report["verdict"], "output": str(dest)}))
        return 0
    except (OSError, ValueError, TypeError, KeyError) as exc:
        print("TAIL_REVIEW_INCONCLUSIVE: "+str(exc), file=__import__("sys").stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

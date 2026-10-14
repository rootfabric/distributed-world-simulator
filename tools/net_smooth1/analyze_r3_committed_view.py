#!/usr/bin/env python3
"""R3 full-trace ITEM windows; evaluate only measured motion within each window.

All trace timestamps are PROCESS-LOCAL. Reconstruct ITEM begin/end using the
entire SERVER trace (including warmup and shutdown), then filter measured
movement events. Comparing a cropped pair of SUBMIT/COMMIT counters is invalid:
a legitimate commit can straddle the measurement boundary.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any


def pct(values: list[float], q: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, max(0, math.ceil(q * len(ordered)) - 1))]


def read_trace(path: Path, role: str, run_id: str) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    header: dict | None = None
    footer: dict | None = None
    previous_us = -1
    previous_n = 0
    with path.open(encoding="utf-8") as stream:
        for line_no, line in enumerate(stream, 1):
            if len(line) > 1024 * 1024:
                raise ValueError(f"{role} trace line {line_no} oversized")
            obj = json.loads(line)
            if not isinstance(obj, dict) or not isinstance(obj.get("data"), dict):
                raise ValueError(f"{role} invalid record at {line_no}")
            timestamp = obj.get("t_us")
            if not isinstance(timestamp, (int, float)) or not math.isfinite(timestamp):
                raise ValueError(f"{role} invalid clock {line_no}")
            if timestamp < previous_us:
                raise ValueError(f"{role} nonmonotonic local clock at {line_no}")
            previous_us = timestamp
            kind = obj.get("kind")
            if kind == "end":
                if footer is not None:
                    raise ValueError(f"{role} duplicate trace END")
                footer = obj["data"]
                continue
            if footer is not None:
                raise ValueError(f"{role} records after END")
            sequence = obj.get("n")
            if not isinstance(sequence, int) or sequence != previous_n + 1:
                raise ValueError(f"{role} trace sequence mismatch at {line_no}")
            previous_n = sequence
            if kind == "header":
                if header is not None or sequence != 1:
                    raise ValueError(f"{role} invalid header ordering")
                header = obj["data"]
            events.append(obj)
    if not header or header.get("schema") != "dws.net_smooth.trace.v1":
        raise ValueError(f"{role} missing/invalid header")
    if header.get("role") != role or header.get("run_id") != run_id:
        raise ValueError(f"{role} trace run identity mismatch")
    if footer is None:
        raise ValueError(f"{role} missing END")
    if (footer.get("dropped") != 0 or footer.get("io_errors") != 0
        or footer.get("produced") != previous_n
        or footer.get("written") != previous_n):
        raise ValueError(f"{role} trace loss / incomplete writer output")
    return events


def examine(root: Path) -> dict[str, Any]:
    manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
    if manifest.get("completed") is not True:
        raise ValueError("run incomplete")
    if manifest.get("scenario") != "r3-slow-item":
        raise ValueError("not a real R3 slow-ITEM scenario")
    run_id = manifest["run_id"]
    server = read_trace(root / "server" / "trace.jsonl", "server", run_id)
    clients = {
        role: read_trace(root / role / "trace.jsonl", role, run_id)
        for role in ("a", "b")
    }
    injected_ms = int(manifest.get("slow_item_writer_ms", 0))
    issues: list[str] = []
    pending: dict[str, Any] | None = None
    complete_windows: list[dict[str, Any]] = []
    submissions = 0
    completions = 0
    measured_frames: list[dict[str, Any]] = []
    wall_intervals_ms: list[float] = []
    tick_intervals: list[int] = []
    invalid_frames = 0
    for event in server:
        kind = event.get("kind")
        data = event.get("data", {})
        if kind == "p1b_item_async_stages":
            # The shared M6 writer has non-ITEM generations too.
            if data.get("kind", "ITEM") != "ITEM":
                continue
            stage = data.get("stage")
            if stage == "SUBMIT":
                submissions += 1
                if pending is not None:
                    issues.append("concurrent ITEM submission / single writer violation")
                pending = {
                    "generation": int(data.get("generation", -1)),
                    "operation_hash": str(data.get("operation_hash", "")),
                    "submit_us": event["t_us"],
                    "measured_frames": 0,
                    "previous_measured_frame": None,
                }
            elif stage == "DURABLE_COMMIT":
                completions += 1
                if pending is None:
                    issues.append("durable commit without a full-trace SUBMIT")
                elif (
                    int(data.get("generation", -2)) != pending["generation"]
                    or str(data.get("operation_hash", "")) != pending["operation_hash"]
                    or event["t_us"] < pending["submit_us"]
                ):
                    issues.append("ITEM SUBMIT/COMMIT identity or ordering mismatch")
                    pending = None
                else:
                    complete_windows.append(pending)
                    pending = None
        elif (kind == "movement_snapshot_stages"
              and data.get("committed_view") is True
              and data.get("pending_kind", "ITEM") == "ITEM"):
            if pending is None:
                issues.append("committed-view movement outside an ITEM pending window")
                continue
            if event.get("measure") is not True:
                continue
            tick = int(data.get("tick", -1))
            frame = {
                "tick": tick,
                "peers": int(data.get("peers", 0)),
                "enqueued": int(data.get("committed_enqueues", 0)),
                "all_enqueued": data.get("all_enqueued") is True,
            }
            measured_frames.append(frame)
            pending["measured_frames"] += 1
            if frame["peers"] != 2 or frame["enqueued"] < 2 or not frame["all_enqueued"]:
                invalid_frames += 1
            prior = pending["previous_measured_frame"]
            if prior is not None:
                dt = (event["t_us"] - prior["t_us"]) / 1000.0
                dtick = tick - int(prior["data"]["tick"])
                if dt < 0 or not math.isfinite(dt) or dtick <= 0:
                    issues.append("invalid committed-view frame clock/tick order")
                else:
                    wall_intervals_ms.append(dt)
                    tick_intervals.append(dtick)
            pending["previous_measured_frame"] = event
    if pending is not None:
        issues.append("incomplete ITEM window at trace END")
    if submissions != completions or submissions != len(complete_windows):
        issues.append(
            f"full-trace FIFO proof mismatch submit={submissions} "
            f"commit={completions} paired={len(complete_windows)}"
        )
    overlapping = [w for w in complete_windows if w["measured_frames"] > 0]
    received = {
        role: [e for e in events
               if e.get("kind") == "r3_committed_view_received"
               and e.get("measure") is True]
        for role, events in clients.items()
    }
    if injected_ms >= 500:
        if len(complete_windows) < 2 or len(overlapping) < 2:
            issues.append("insufficient fully paired ITEM windows overlapping measurement")
        if len(measured_frames) < 20:
            issues.append(f"insufficient measured committed-view frames ({len(measured_frames)})")
        if invalid_frames:
            issues.append(f"{invalid_frames} unsafe or missing dual-peer enqueues")
        if any(delta != 3 for delta in tick_intervals):
            issues.append("20Hz fixed-tick spacing violated inside ITEM window")
        if wall_intervals_ms and (
            pct(wall_intervals_ms, .95) > 80.0
            or max(wall_intervals_ms) > 150.0
        ):
            issues.append(
                f"movement walltime gaps p95={pct(wall_intervals_ms,.95)}, "
                f"max={max(wall_intervals_ms)}ms"
            )
        for role, events in received.items():
            if len(events) < 10:
                issues.append(f"{role}: missing real committed-view client receives ({len(events)})")
    result = {
        "schema": "dws.net_smooth.r3_committed_view_acceptance.v2",
        "run_id": run_id,
        "evidence_class": "GUI" if manifest.get("mode") == "gui" else "DIAGNOSTIC",
        "injected_writer_ms": injected_ms,
        "verdict": "FAIL" if issues else "PASS",
        "full_trace_submissions": submissions,
        "full_trace_durable_completions": completions,
        "fully_paired_windows": len(complete_windows),
        "measurement_overlapping_windows": len(overlapping),
        "measured_pending_frames": len(measured_frames),
        "bad_dual_peer_enqueues": invalid_frames,
        "client_receives": {k: len(v) for k, v in received.items()},
        "frame_interval_ms": {"p95": pct(wall_intervals_ms, .95),
                              "max": max(wall_intervals_ms, default=None)},
        "tick_intervals": {"count": len(tick_intervals),
                           "not_three": sum(v != 3 for v in tick_intervals)},
        "ack_after_commit_verified_here": False,  # must be proven by M6 tests
        "issues": issues,
    }
    (root / "r3-committed-view-acceptance.json").write_text(
        json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("output_root", type=Path)
    args = parser.parse_args()
    try:
        result = examine(args.output_root)
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(f"R3 INCONCLUSIVE: {exc}")
        return 2
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0 if result["verdict"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())

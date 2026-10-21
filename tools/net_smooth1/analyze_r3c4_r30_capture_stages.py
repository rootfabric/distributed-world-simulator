#!/usr/bin/env python3
"""R3.0 read-only server checkpoint capture attribution (not a normative gate).

Use on one complete Earth server/trace.jsonl after the unchanged normative
analyze_net_smooth1.py has accepted trace integrity. This measures why the
R2 periodic checkpoint still stalls the main thread. Never infer COW safety
or performance acceptance solely from these per-event timings.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path


FIELDS = (
    "capture_ms", "quiesce_ms", "authority_ms", "replay_ms", "handoff_ms",
    "r30_replay_gameplay_ms", "r30_replay_checksum_ms", "r30_writer_deep_copy_ms",
)


def percentile(values: list[float], q: float) -> float:
    if not values:
        raise ValueError("R30_NO_CHECKPOINT_CAPTURE_EVENTS")
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, math.ceil(q * len(ordered)) - 1)]


def metrics(values: list[float]) -> dict:
    return {"count": len(values), "p50": percentile(values, .5),
            "p95": percentile(values, .95), "p99": percentile(values, .99),
            "max": max(values)}


def analyze(path: Path) -> dict:
    series: dict[str, list[float]] = {key: [] for key in FIELDS}
    sizes: dict[str, list[int]] = {"r30_replay_ledger_count": [], "r30_outbox_count": []}
    events = 0
    replay_unattributed: list[float] = []
    violations: list[str] = []
    seen_generations: set[int] = set()
    with path.open(encoding="utf-8") as handle:
        for raw in handle:
            record = json.loads(raw)
            if record.get("kind") != "checkpoint_capture" or record.get("measure") is not True:
                continue
            events += 1
            data = record.get("data", {})
            if data.get("r3c4r2_worker_envelope") is not True:
                violations.append("R2 envelope disabled at capture")
            if not isinstance(data.get("generation"), int):
                violations.append("missing generation")
            elif data["generation"] in seen_generations:
                violations.append("duplicate generation")
            else:
                seen_generations.add(data["generation"])
            for key in FIELDS:
                value = data.get(key)
                if type(value) not in (float, int) or not math.isfinite(value) or value < 0:
                    violations.append("invalid/missing " + key)
                    break
                series[key].append(float(value))
            else:
                # Disjoint spans: replay_ms measures entire outbox.to_dict,
                # NOT deep copy; handoff_ms measures the writer call including
                # its synchronous duplicate(true).
                overhead = data["replay_ms"] - (
                    data["r30_replay_gameplay_ms"] +
                    data["r30_replay_checksum_ms"]
                )
                if overhead < -1.0:
                    violations.append("inner replay stages exceed full replay window")
                else:
                    # Scheduler pauses between nested timing boundaries are
                    # legitimate host noise, never invent a 0.5ms ceiling.
                    replay_unattributed.append(max(0.0, overhead))
                if data["r30_writer_deep_copy_ms"] > data["handoff_ms"] + 1.0:
                    violations.append("writer deep-copy larger than entire handoff")
            for field in sizes:
                count = data.get(field)
                if type(count) is not int or count < 0:
                    violations.append("invalid/missing " + field)
                else:
                    sizes[field].append(count)
    if events == 0:
        violations.append("no measured checkpoint events")
    if any(len(v) != events for v in series.values()):
        violations.append("incomplete checkpoint metrics")
    if violations:
        raise ValueError("R30_STAGE_TRACE_INVALID: " + "; ".join(sorted(set(violations))))
    return {
        "schema": "dws.net_smooth.r3c4.r30.attribution.v1",
        "mode": "R2_ON_R30_STAGE_ATTRIBUTION",
        "checkpoint_count": events,
        "replay_unattributed_ms": metrics(replay_unattributed) if replay_unattributed else None,
        "stages_ms": {key: metrics(values) for key, values in series.items()},
        "ledger_sizes": {key: {
            "min": min(values), "max": max(values), "p99": percentile(values, .99)}
            for key, values in sizes.items()},
        "notes": {
            "replay_ms": "M6ReplayOutbox.to_dict (gameplay export + detached checksum)",
            "writer_deep_copy_ms": "duplicate(true) before writer semaphore",
            "authority_ms": "service.export_durable_state + value projection",
            "not_normative": True,
            "merge_approval": False,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        report = analyze(args.trace)
    except (ValueError, OSError, json.JSONDecodeError) as exc:
        print("R30_INCONCLUSIVE: " + str(exc))
        return 2
    if args.output is not None:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False),
                               encoding="utf-8")
    print(json.dumps({"status": "R30_ATTRIBUTION_PASS", "checkpoint_count":
                      report["checkpoint_count"], "stages_p99_ms":
                      {k: v["p99"] for k, v in report["stages_ms"].items()}}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

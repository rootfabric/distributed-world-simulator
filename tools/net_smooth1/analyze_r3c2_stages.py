#!/usr/bin/env python3
"""R3C.2 process-local cost attribution for client attach and M6 postcommit.

Does not replace the normative network/smoothness acceptance analyzer.
Never compare raw client vs server monotonic timestamps; aggregate each role
independently and keep source event names/absent stages explicit.
"""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path
from collections import defaultdict


KNOWN_STAGES = {
    "a": ("r3c2_client_connect_attach", "r3c2_earth_attach",
          "r3c2_resource_attach", "frame"),
    "b": ("r3c2_client_connect_attach", "r3c2_earth_attach",
          "r3c2_resource_attach", "frame"),
    "server": ("r3c2_postcommit_stage", "p1b_item_capture_breakdown",
               "checkpoint_capture", "server_loop"),
}
METRICS = {
    "r3c2_client_connect_attach": ("attach_ms", "descriptor_ms", "total_ms"),
    "r3c2_earth_attach": ("total_ms", "replica_visual_ms", "item_ms", "construction_ms"),
    "r3c2_resource_attach": ("total_ms", "earth_ms", "resource_projection_ms"),
    "frame": ("interval_ms",),
    "r3c2_postcommit_stage": ("duration_ms",),
    "p1b_item_capture_breakdown": ("player_checksum_ms", "item_checksum_ms",
         "outbox_stage_ms", "quiesce_ms", "authority_export_ms",
         "replay_export_ms", "worker_handoff_ms"),
    "checkpoint_capture": ("capture_ms", "authority_ms", "replay_ms", "handoff_ms"),
    "server_loop": ("process_ms", "fixed_ms", "snapshot_ms", "persistence_ms"),
}


def stats(v: list[float]) -> dict:
    ordered = sorted(v)
    def p(q: float) -> float | None:
        return ordered[max(0, min(len(ordered)-1, math.ceil(q * len(ordered))-1))] if ordered else None
    return {"count": len(v), "p50": p(.50), "p95": p(.95),
            "p99": p(.99), "max": max(v, default=None)}


def read_role(path: Path, role: str, run_id: str) -> dict:
    samples: dict[str, dict[str, list[float]]] = defaultdict(lambda: defaultdict(list))
    stages = defaultdict(int)
    after_measure = 0
    lost = None
    prior_t = -1
    prior_seq = 0
    found_header = False
    with path.open(encoding="utf-8") as stream:
        for n, line in enumerate(stream, 1):
            if len(line) > 1_000_000:
                raise ValueError(f"{role}: oversized trace line {n}")
            event = json.loads(line)
            if not isinstance(event, dict) or not isinstance(event.get("data"), dict):
                raise ValueError(f"{role}: invalid trace record {n}")
            timestamp = event.get("t_us")
            if not isinstance(timestamp, (int, float)) or not math.isfinite(timestamp) or timestamp < prior_t:
                raise ValueError(f"{role}: nonmonotonic or invalid t_us")
            prior_t = timestamp
            kind, data = event.get("kind"), event["data"]
            if kind == "end":
                if lost is not None:
                    raise ValueError(f"{role}: duplicate END")
                if (data.get("dropped") != 0 or data.get("io_errors") != 0
                        or data.get("produced") != prior_seq or data.get("written") != prior_seq):
                    raise ValueError(f"{role}: trace loss / incomplete END")
                lost = False
                continue
            if lost is not None:
                raise ValueError(f"{role}: record after END")
            sequence = event.get("n")
            if not isinstance(sequence, int) or sequence != prior_seq + 1:
                raise ValueError(f"{role}: trace sequence violation at {n}")
            prior_seq = sequence
            if kind == "header":
                if found_header or sequence != 1:
                    raise ValueError(f"{role}: invalid header order")
                if data.get("role") != role or data.get("run_id") != run_id:
                    raise ValueError(f"{role}: header identity mismatch")
                if data.get("schema") != "dws.net_smooth.trace.v1":
                    raise ValueError(f"{role}: header schema invalid")
                found_header = True
            if kind not in KNOWN_STAGES[role]:
                continue
            stages[kind] += 1
            if event.get("measure") is True:
                after_measure += 1
            for metric in METRICS[kind]:
                if metric not in data:
                    continue
                value = data[metric]
                if not isinstance(value, (float, int)) or not math.isfinite(value) or value < 0:
                    raise ValueError(f"{role}:{kind}: invalid {metric}")
                samples[kind][metric].append(float(value))
    if not found_header or lost is None:
        raise ValueError(f"{role}: missing header/END")
    return {
        "role": role,
        "count_by_stage": dict(stages),
        "stage_ms": {kind: {name: stats(values) for name, values in fields.items()}
                     for kind, fields in samples.items()},
        "metric_samples_with_measure_marker": after_measure,
    }


def analyze(root: Path) -> dict:
    manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
    if not manifest.get("completed"):
        raise ValueError("incomplete run cannot be classified")
    run_id = manifest.get("run_id")
    if not isinstance(run_id, str) or not run_id:
        raise ValueError("missing run_id")
    out = {role: read_role(root / role / "trace.jsonl", role, run_id)
           for role in ("server", "a", "b")}
    return {
        "schema": "dws.net_smooth.r3c2_stage_diagnostics.v1",
        "evidence_class": "DIAGNOSTIC_ONLY",
        "run_id": run_id,
        "r3c2_avatar_prewarm": bool(manifest.get("r3c2_avatar_prewarm", False)),
        "r3c2_server_phased": bool(manifest.get("r3c2_server_phased", False)),
        "slow_item_writer_ms": int(manifest.get("slow_item_writer_ms", 0)),
        "roles": out,
        "normative_acceptance_must_use_analyze_net_smooth1": True,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    args = parser.parse_args()
    try:
        report = analyze(args.root)
    except (OSError, ValueError, KeyError, TypeError, OverflowError) as exc:
        print(f"R3C2 STAGES INCONCLUSIVE: {exc}")
        return 2
    path = args.root / "r3c2-stage-diagnostics.json"
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

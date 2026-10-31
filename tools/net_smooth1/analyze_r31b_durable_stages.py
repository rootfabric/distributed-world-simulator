#!/usr/bin/env python3
"""Read-only R3.1b P0 per-domain durable export attribution from exact GUI trace.

The normative analyze_net_smooth1.py is unchanged. This tool observes only
checkpoint_capture events with complete R31b nested stage metrics.
Percentiles of separate stages CANNOT be summed to reconstruct total p99.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

FIELDS = (
    "snapshot_ms", "players_ms", "ownership_ms", "shared_item_ms",
    "item_graph_ms", "resource_ms", "final_checksum_ms", "validation_ms",
    "total_ms",
)


def percentile(seq: list[float], q: float) -> float:
    if not seq:
        raise ValueError("R31B_MISSING_MEASURED_STAGE")
    vals = sorted(seq)
    return vals[min(len(vals)-1, max(0, math.ceil(q*len(vals))-1))]


def analyze(path: Path, min_captures: int = 10) -> dict:
    stages: dict[str, list[float]] = {key: [] for key in FIELDS}
    hits = 0
    seen = 0
    fallbacks = 0
    player_counts = []
    errors = []
    with path.open(encoding="utf-8") as source:
        for line_number, raw in enumerate(source, 1):
            if len(raw) > 1024*1024:
                raise ValueError("R31B_OVERSIZED_EVENT")
            event = json.loads(raw)
            if not isinstance(event, dict) or not isinstance(event.get("data", {}), dict):
                raise ValueError("R31B_BAD_EVENT_SHAPE")
            if event.get("kind") != "checkpoint_capture" or event.get("measure") is not True:
                continue
            data = event["data"]
            seen += 1
            if data.get("r3c4r2_worker_envelope") is not True:
                errors.append("R31B_R2_WORKER_NOT_ENABLED")
            if type(data.get("r31_cache_hit")) is not bool:
                errors.append("R31B_REPLAY_CACHE_STATUS_MISSING")
            elif data["r31_cache_hit"]:
                hits += 1
            details = data.get("r31b_durable_stages", {})
            if not isinstance(details, dict):
                errors.append("R31B_DOMAIN_STAGES_MISSING")
                continue
            if "fallback_ms" in details and type(details.get("valid")) is not bool:
                # Seam-unbound quiescent export: the profiled wrapper measured
                # the unchanged base path. No per-domain stage population.
                fallbacks += 1
                continue
            if type(details.get("valid")) is not bool:
                errors.append("R31B_DOMAIN_STAGES_MISSING")
                continue
            if details["valid"] is not True:
                errors.append("R31B_INVALID_DURABLE_STATE")
            if details.get("seam_coordinator_count", 0) < 1:
                errors.append("R31B_ACTIVE_SEAM_NOT_MEASURED")
            for field in FIELDS:
                value = details.get(field)
                if type(value) not in (float, int) or not math.isfinite(value) or value < 0:
                    errors.append(f"R31B_INVALID_{field}_LINE_{line_number}")
                else:
                    stages[field].append(float(value))
            player_counts.append(details.get("player_count"))
            if all(len(stages[x]) == seen for x in FIELDS):
                sum_parts = sum(details[k] for k in FIELDS if k != "total_ms")
                if sum_parts > details["total_ms"] + 1.0:
                    errors.append("R31B_STAGE_ACCOUNTING_OVERSHOOT")
            measured_authority_ms = data.get("authority_ms")
            if type(measured_authority_ms) not in (float,int) or not math.isfinite(measured_authority_ms):
                errors.append("R31B_AUTHORITY_DURATION_MISSING")
            elif isinstance(details.get("total_ms"), (float,int)):
                if details["total_ms"] > measured_authority_ms + 1.0:
                    errors.append("R31B_TOTAL_EXCEEDS_AUTHORITY_CAPTURE")
    if len(stages["total_ms"]) < min_captures:
        errors.append("R31B_INSUFFICIENT_SAMPLES")
    if errors:
        raise ValueError("; ".join(sorted(set(errors))))
    result = {
        "schema": "dws.net_smooth.r31b.durable_stage.v1",
        "verdict": "R31B_SOURCE_ATTRIBUTION_VALID_ONLY",
        "checkpoint_count": seen,
        "fallback_captures": fallbacks,
        "domain_captures": len(stages["total_ms"]),
        "replay_cache_hits": hits,
        "player_counts": sorted(set(player_counts)),
        "metrics_ms": {
            name: {
                "count": len(values), "p50": percentile(values,.5),
                "p95": percentile(values,.95),
                "p99": percentile(values,.99),
                "max": max(values),
            } for name, values in stages.items()
        },
        "limitations": [
            "Do not add independent stage p99 values and call the sum a total p99.",
            "These timings do not prove a cause for >100ms frame gaps.",
            "This is diagnostic only; full M6 and GUI norm gates remain separate.",
        ],
    }
    return result


def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("server_trace",type=Path)
    parser.add_argument("--output",type=Path,required=True)
    args=parser.parse_args()
    try:
        result=analyze(args.server_trace)
    except (ValueError, OSError, TypeError, json.JSONDecodeError) as exc:
        print(f"R31B_SOURCE_INCONCLUSIVE: {exc}")
        return 2
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf-8")
    print(json.dumps({
        "status": result["verdict"],
        "captures": result["checkpoint_count"],
        "stage_p99_ms": {k:v["p99"] for k,v in result["metrics_ms"].items()},
    }))
    return 0


if __name__=="__main__":
    raise SystemExit(main())

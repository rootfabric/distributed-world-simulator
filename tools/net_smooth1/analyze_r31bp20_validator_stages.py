#!/usr/bin/env python3
"""NET-SMOOTH1 R31b P2.0 — strict, read-only per-validator stage analysis.

This is an attribution tool, NOT a normative performance analyzer, M6 ACK
test, proof of cache correctness, or permission to bypass any validator.
Stage p99 values cannot be summed into a whole-frame p99. It handles real
seam-unbound fallback separately from active ProductSeam checkpoints.
"""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path

BASE_STAGES = (
    "envelope_ms",
    "outer_checksum_validation_ms",
    "player_registry_ms",
    "ownership_ms",
    "shared_item_ms",
    "item_validator_setup_ms",
    "item_validator_validate_ms",
    "cross_domain_ms",
    "json_safety_ms",
)
RESOURCE_STAGES = ("resource_validator_ms", "resource_authority_ms")
P20_STAGES = ("total_ms", "base_layer_total_ms") + BASE_STAGES + RESOURCE_STAGES


def percentile(values: list[float], quantile: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    return ordered[min(len(ordered)-1,
                       max(0, math.ceil(quantile*len(ordered))-1))]


def analyze(trace: Path, *, minimum_active: int = 10) -> dict:
    collected = {key: [] for key in P20_STAGES}
    totals = {"outer_validation_ms": [], "capture_ms": [], "authority_ms": []}
    captured = fallback = active = 0
    for line_number, raw in enumerate(trace.open(encoding="utf-8"), 1):
        if len(raw) > 1024*1024:
            raise ValueError(f"P20_OVERSIZED_EVENT_LINE_{line_number}")
        event = json.loads(raw)
        if not isinstance(event, dict) or not isinstance(event.get("data", {}), dict):
            raise ValueError(f"P20_INVALID_EVENT_LINE_{line_number}")
        if event.get("kind") != "checkpoint_capture" or event.get("measure") is not True:
            continue
        captured += 1
        data = event["data"]
        if data.get("r31bp20_validator_attribution") is not True:
            raise ValueError(f"P20_CANARY_FLAG_NOT_ON_LINE_{line_number}")
        if data.get("r3c4r2_worker_envelope") is not True:
            raise ValueError(f"P20_R2_WRITER_NOT_ON_LINE_{line_number}")
        if type(data.get("r31_cache_hit")) is not bool:
            raise ValueError(f"P20_R31A_CACHE_STATUS_MISSING_LINE_{line_number}")
        chunk_report = data.get("r31bp1_durable_chunks", {})
        if not isinstance(chunk_report, dict) or chunk_report.get("enabled") is not True:
            raise ValueError(f"P20_P1_CACHE_NOT_ON_LINE_{line_number}")
        source = data.get("r31b_durable_stages", {})
        if not isinstance(source, dict):
            raise ValueError(f"P20_P0_DOMAIN_STAGES_MISSING_LINE_{line_number}")
        if "fallback_ms" in source:
            f = source.get("fallback_ms")
            if (type(f) not in (float, int) or not math.isfinite(f) or f < 0
                    or source.get("seam_coordinator_count") != 0):
                raise ValueError(f"P20_INVALID_FALLBACK_LINE_{line_number}")
            if source.get("r31bp20_validation_stages"):
                raise ValueError(f"P20_FALLBACK_MASQUERADES_AS_ACTIVE_LINE_{line_number}")
            fallback += 1
            continue
        if source.get("valid") is not True or source.get("seam_coordinator_count", 0) < 1:
            raise ValueError(f"P20_UNACCEPTED_ACTIVE_CHECKPOINT_LINE_{line_number}")
        observed = source.get("r31bp20_validation_stages")
        if not isinstance(observed, dict):
            raise ValueError(f"P20_VALIDATION_PROFILE_ABSENT_LINE_{line_number}")
        active += 1
        for name in P20_STAGES:
            val = observed.get(name)
            if type(val) not in (float, int) or not math.isfinite(val) or val < 0:
                raise ValueError(f"P20_STAGE_MISSING_OR_NONFINITE_{name}_LINE_{line_number}")
            collected[name].append(float(val))
        for name, raw_val in [
            ("outer_validation_ms", source.get("validation_ms")),
            ("capture_ms", data.get("capture_ms")),
            ("authority_ms", data.get("authority_ms")),
        ]:
            if (type(raw_val) not in (float, int)
                    or not math.isfinite(raw_val) or raw_val < 0):
                raise ValueError(f"P20_OUTER_METRIC_INVALID_{name}_LINE_{line_number}")
            totals[name].append(float(raw_val))
        # Outer P0 validation measurement includes the profiler overhead;
        # it should never be below inner P20 validator execution time.
        if observed["total_ms"] > source["validation_ms"] + 1.0:
            raise ValueError(f"P20_TOTAL_EXCEEDS_OLD_VALIDATION_LINE_{line_number}")
        if observed["base_layer_total_ms"] > observed["total_ms"] + 1.0:
            raise ValueError(f"P20_BASE_EXCEEDS_TOTAL_LINE_{line_number}")
    if captured < minimum_active or active < minimum_active:
        raise ValueError(f"P20_INSUFFICIENT_ACTIVE_MEASUREMENTS:{captured}/{active}")
    if captured != active + fallback:
        raise ValueError("P20_UNCLASSIFIED_MEASUREMENTS")
    return {
        "schema": "dws.net_smooth.r31bp20.validation_attribution.v1",
        "verdict": "P20_VALIDATOR_ATTRIBUTION_VALID_ONLY",
        "measured_captures": captured,
        "active_seam_captures": active,
        "unbound_seam_fallback_captures": fallback,
        "components_ms": {
            name: {
                "count": len(values),
                "p50": percentile(values, .5),
                "p95": percentile(values, .95),
                "p99": percentile(values, .99),
                "max": max(values),
            }
            for name, values in {**collected, **totals}.items()
        },
        "notes": [
            "No validator or checksum has been skipped or cached by P2.0.",
            "Never add independent stage p99s to claim end-to-end p99.",
            "Use unmodified normative analyze_net_smooth1.py for frame PASS/FAIL.",
            "No cross-process clock correlation or causal explanation of host stalls.",
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("server_trace", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    try:
        result = analyze(args.server_trace)
    except (OSError, ValueError, TypeError, json.JSONDecodeError) as exc:
        print("P20_ATTRIBUTION_INCONCLUSIVE: " + str(exc))
        return 2
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({
        "verdict": result["verdict"], "active": result["active_seam_captures"],
        "p99_ms": {k: v["p99"] for k, v in result["components_ms"].items()},
    }))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

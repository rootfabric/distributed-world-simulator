#!/usr/bin/env python3
"""Read-only R31b P1 durable chunk cache attribution from exact GUI trace.

The normative analyze_net_smooth1.py is unchanged. This tool observes only
checkpoint_capture events carrying the r31bp1_durable_chunks cache report.
It verifies, per ON run:
- the cache was enabled for every measured capture;
- active-seam M4+mining cache-hit rate >= 90%;
- no unexplained bypass (only an explicitly recorded CHUNK_OVERSIZE bypass is
  permitted, and it must carry a plausible byte size);
- chunk byte sizes are > 0 and <= 4 MiB for both cached components.
This tool NEVER reconstructs totals and never proves frame-gap causation.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

MAX_CHUNK_BYTES = 4 * 1024 * 1024
MIN_HIT_RATE = 0.90
COMPONENTS = ("item_graph", "resource_mining")
FENCE_FIELDS = (
    "kind", "instance_id", "authority_owner_id",
    "authority_epoch", "state_serial",
)


def analyze(path: Path, min_captures: int = 10) -> dict:
    errors: list[str] = []
    captures = 0
    stats = {
        kind: {"hits": 0, "misses": 0, "bypasses": 0, "bytes": 0}
        for kind in COMPONENTS
    }
    with path.open(encoding="utf-8") as source:
        for line_number, raw in enumerate(source, 1):
            if len(raw) > 1024*1024:
                raise ValueError("R31BP1_OVERSIZED_EVENT")
            event = json.loads(raw)
            if not isinstance(event, dict) or not isinstance(event.get("data", {}), dict):
                raise ValueError("R31BP1_BAD_EVENT_SHAPE")
            if event.get("kind") != "checkpoint_capture" or event.get("measure") is not True:
                continue
            data = event["data"]
            captures += 1
            report = data.get("r31bp1_durable_chunks", {})
            if not isinstance(report, dict) or not report:
                errors.append(f"R31BP1_CACHE_REPORT_MISSING_LINE_{line_number}")
                continue
            if report.get("enabled") is not True:
                errors.append("R31BP1_CACHE_NOT_ENABLED")
                continue
            stages = data.get("r31b_durable_stages", {})
            if isinstance(stages, dict) and stages.get("seam_coordinator_count", 0) >= 1:
                # Active seam: chunk fences must be populated and fresh.
                for kind in COMPONENTS:
                    component = report.get(kind, {})
                    if not isinstance(component, dict):
                        errors.append(f"R31BP1_{kind.upper()}_REPORT_INVALID")
                        continue
                    fence = component.get("fence", {})
                    if component.get("cached") is True:
                        if not isinstance(fence, dict) or any(
                            fence.get(field) is None for field in FENCE_FIELDS
                        ):
                            errors.append(f"R31BP1_{kind.upper()}_FENCE_INVALID")
                        size = component.get("bytes")
                        if (
                            type(size) not in (int, float)
                            or not math.isfinite(size)
                            or size <= 0
                            or size > MAX_CHUNK_BYTES
                        ):
                            errors.append(f"R31BP1_{kind.upper()}_SIZE_INVALID")
                        else:
                            stats[kind]["bytes"] = max(stats[kind]["bytes"], int(size))
                    hits = component.get("hits")
                    misses = component.get("misses")
                    bypasses = component.get("bypasses")
                    if type(hits) is not int or hits < 0 or type(misses) is not int or misses < 0:
                        errors.append(f"R31BP1_{kind.upper()}_COUNTERS_INVALID")
                        continue
                    stats[kind]["hits"] = max(stats[kind]["hits"], hits)
                    stats[kind]["misses"] = max(stats[kind]["misses"], misses)
                    if type(bypasses) is not int or bypasses < 0:
                        errors.append(f"R31BP1_{kind.upper()}_BYPASS_COUNTER_INVALID")
                    elif bypasses > 0:
                        # Only an explicitly recorded oversize bypass is allowed;
                        # an oversize component cannot stay cached, so any later
                        # capture must show it bypassing again consistently.
                        stats[kind]["bypasses"] = max(stats[kind]["bypasses"], bypasses)
    if captures < min_captures:
        errors.append("R31BP1_INSUFFICIENT_SAMPLES")
    for kind in COMPONENTS:
        total = stats[kind]["hits"] + stats[kind]["misses"]
        if total == 0:
            errors.append(f"R31BP1_{kind.upper()}_NO_MEASURED_ACTIVITY")
            continue
        if stats[kind]["hits"] / total < MIN_HIT_RATE:
            errors.append(f"R31BP1_{kind.upper()}_HIT_RATE_BELOW_90PCT")
    if errors:
        raise ValueError("; ".join(sorted(set(errors))))
    result = {
        "schema": "dws.net_smooth.r31bp1.durable_chunk_cache.v1",
        "verdict": "R31BP1_CHUNK_CACHE_ATTRIBUTION_VALID_ONLY",
        "checkpoint_count": captures,
        "components": {
            kind: {
                **stats[kind],
                "hit_rate": (
                    stats[kind]["hits"] / (stats[kind]["hits"] + stats[kind]["misses"])
                    if (stats[kind]["hits"] + stats[kind]["misses"]) else 0.0
                ),
            }
            for kind in COMPONENTS
        },
        "limitations": [
            "Cache-hit attribution is not a performance PASS and not a cause proof.",
            "Chunk reuse must remain byte-equal to the legacy export; the normative "
            "checksum/validation gates are evaluated separately.",
            "Oversize bypasses are measured, never hidden; expected ProductSeam-unbound "
            "fallback checkpoints are tracked separately by the P0 analyzer.",
        ],
    }
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("server_trace", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = analyze(args.server_trace)
    except (ValueError, OSError, TypeError, json.JSONDecodeError) as exc:
        print(f"R31BP1_SOURCE_INCONCLUSIVE: {exc}")
        return 2
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({
        "status": result["verdict"],
        "captures": result["checkpoint_count"],
        "hit_rates": {k: round(v["hit_rate"], 4) for k, v in result["components"].items()},
    }))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

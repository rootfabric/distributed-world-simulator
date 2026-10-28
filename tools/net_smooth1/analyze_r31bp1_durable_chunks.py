#!/usr/bin/env python3
"""R31b P1 independent measured-window durable cache attribution (NOT perf PASS).

Use only after the unmodified normative analyze_net_smooth1.py. Both R31a and
P0 must be ON in either GUI arm; this reducer is for the P1 ON arm only.

Counters are CUMULATIVE from process startup; they must be DIFFERENCED from
the first ACTIVE measured checkpoint, not max()ed to advertise a measured hit
rate. Legitimate ProductSeam-unbound captures remain their own population.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

MAX_CHUNK_BYTES = 4 * 1024 * 1024
MIN_HIT_RATE = .90
COMPONENTS = ("item_graph", "resource_mining")
FENCE_FIELDS = ("kind", "instance_id", "authority_owner_id",
                "authority_epoch", "state_serial")
ACCEPTED_BYPASS_REASON = "CHUNK_OVERSIZE"
COUNTERS = ("hits", "misses", "bypasses")


def _numeric_counter(value, label: str, line: int) -> int:
    if type(value) is not int or value < 0:
        raise ValueError(f"R31BP1_INVALID_{label}_LINE_{line}")
    return value


def _parse_component(kind: str, component: dict, line: int) -> dict:
    if not isinstance(component, dict):
        raise ValueError(f"R31BP1_{kind.upper()}_REPORT_INVALID_LINE_{line}")
    values = {key: _numeric_counter(component.get(key),
                                   f"{kind.upper()}_{key.upper()}", line)
              for key in COUNTERS}
    cached = component.get("cached")
    if type(cached) is not bool:
        raise ValueError(f"R31BP1_{kind.upper()}_CACHE_STATUS_INVALID_LINE_{line}")
    size = component.get("bytes")
    if type(size) is not int or size < 0 or size > MAX_CHUNK_BYTES:
        raise ValueError(f"R31BP1_{kind.upper()}_SIZE_INVALID_LINE_{line}")
    if cached:
        if size <= 0:
            raise ValueError(f"R31BP1_{kind.upper()}_SIZE_INVALID_LINE_{line}")
        fence = component.get("fence", {})
        if (not isinstance(fence, dict)
                or any(fence.get(field) is None for field in FENCE_FIELDS)
                or fence.get("kind") != kind
                or type(fence.get("instance_id")) is not int
                or fence["instance_id"] <= 0
                or not isinstance(fence.get("authority_owner_id"), str)
                or not fence["authority_owner_id"]
                or type(fence.get("authority_epoch")) is not int
                or fence["authority_epoch"] < 1
                or type(fence.get("state_serial")) is not int
                or fence["state_serial"] < 0
                or type(fence.get("revision" if kind == "item_graph" else "generation")) is not int
                or (kind == "item_graph" and type(fence.get("tick")) is not int)):
            raise ValueError(f"R31BP1_{kind.upper()}_FENCE_INVALID_LINE_{line}")
    raw_reasons = component.get("bypass_reasons", None)
    if not isinstance(raw_reasons, dict):
        raise ValueError(f"R31BP1_{kind.upper()}_BYPASS_REASONS_MISSING_LINE_{line}")
    reasons = {k: _numeric_counter(v, f"{kind.upper()}_REASON_{k}", line)
               for k, v in raw_reasons.items() if isinstance(k, str)}
    if len(reasons) != len(raw_reasons):
        raise ValueError(f"R31BP1_{kind.upper()}_BYPASS_REASON_KEY_INVALID_LINE_{line}")
    if sum(reasons.values()) != values["bypasses"]:
        raise ValueError(f"R31BP1_{kind.upper()}_BYPASS_ACCOUNTING_LINE_{line}")
    return {**values, "bytes": size, "cached": cached,
            "reasons": reasons}


def analyze(path: Path, min_captures: int = 10) -> dict:
    first: dict[str, dict] = {}
    prev: dict[str, dict] = {}
    last: dict[str, dict] = {}
    max_size = {kind: 0 for kind in COMPONENTS}
    captures = active = fallback = 0
    measured_stages = []
    with path.open(encoding="utf-8") as handle:
        for line_no, raw in enumerate(handle, 1):
            if len(raw) > 1024 * 1024:
                raise ValueError("R31BP1_OVERSIZED_EVENT")
            event = json.loads(raw)
            if not isinstance(event, dict) or not isinstance(event.get("data", {}), dict):
                raise ValueError(f"R31BP1_BAD_EVENT_SHAPE_LINE_{line_no}")
            if event.get("kind") != "checkpoint_capture" or event.get("measure") is not True:
                continue
            captures += 1
            data = event["data"]
            if data.get("r3c4r2_worker_envelope") is not True or type(data.get("r31_cache_hit")) is not bool:
                raise ValueError(f"R31BP1_R31A_R2_REQUIRED_LINE_{line_no}")
            report = data.get("r31bp1_durable_chunks")
            if not isinstance(report, dict) or report.get("enabled") is not True:
                raise ValueError(f"R31BP1_CACHE_REPORT_MISSING_OR_DISABLED_LINE_{line_no}")
            stages = data.get("r31b_durable_stages")
            if not isinstance(stages, dict):
                raise ValueError(f"R31BP1_DOMAIN_STAGES_MISSING_LINE_{line_no}")
            if "fallback_ms" in stages:
                if (type(stages["fallback_ms"]) not in (float, int)
                        or not math.isfinite(stages["fallback_ms"])
                        or stages["fallback_ms"] < 0
                        or stages.get("seam_coordinator_count") != 0):
                    raise ValueError(f"R31BP1_INVALID_FALLBACK_LINE_{line_no}")
                fallback += 1
                continue
            if (stages.get("valid") is not True
                    or type(stages.get("seam_coordinator_count")) is not int
                    or stages["seam_coordinator_count"] < 1):
                raise ValueError(f"R31BP1_INVALID_ACTIVE_DOMAIN_LINE_{line_no}")
            active += 1
            for kind in COMPONENTS:
                cur = _parse_component(kind, report.get(kind), line_no)
                max_size[kind] = max(max_size[kind], cur["bytes"])
                if kind in prev:
                    for key in COUNTERS:
                        if cur[key] < prev[kind][key]:
                            raise ValueError(f"R31BP1_{kind.upper()}_COUNTER_RESET_LINE_{line_no}")
                    for reason, old in prev[kind]["reasons"].items():
                        if cur["reasons"].get(reason, 0) < old:
                            raise ValueError(f"R31BP1_{kind.upper()}_REASON_RESET_LINE_{line_no}")
                else:
                    first[kind] = cur
                prev[kind] = cur
                last[kind] = cur
            measured_stages.append({
                "line": line_no,
                "item_graph_ms": stages.get("item_graph_ms"),
                "resource_ms": stages.get("resource_ms"),
                "validation_ms": stages.get("validation_ms"),
                "final_checksum_ms": stages.get("final_checksum_ms"),
                "total_ms": stages.get("total_ms"),
            })
    if captures < min_captures:
        raise ValueError("R31BP1_INSUFFICIENT_SAMPLES")
    if active < min_captures:
        raise ValueError("R31BP1_INSUFFICIENT_ACTIVE_SAMPLES")
    if active + fallback != captures:
        raise ValueError("R31BP1_UNCLASSIFIED_CAPTURE")
    components = {}
    for kind in COMPONENTS:
        baseline, latest = first[kind], last[kind]
        hit_delta = latest["hits"] - baseline["hits"]
        miss_delta = latest["misses"] - baseline["misses"]
        bypass_delta = latest["bypasses"] - baseline["bypasses"]
        total = hit_delta + miss_delta
        if total == 0:
            raise ValueError(f"R31BP1_{kind.upper()}_NO_MEASURED_ACTIVITY")
        rate = hit_delta / total
        if rate < MIN_HIT_RATE:
            raise ValueError(f"R31BP1_{kind.upper()}_HIT_RATE_BELOW_90PCT")
        reasons = {key: latest["reasons"].get(key, 0) - baseline["reasons"].get(key, 0)
                   for key in set(latest["reasons"]) | set(baseline["reasons"])}
        if any(v < 0 for v in reasons.values()) or sum(reasons.values()) != bypass_delta:
            raise ValueError(f"R31BP1_{kind.upper()}_BYPASS_ACCOUNTING")
        if any(key != ACCEPTED_BYPASS_REASON and v > 0 for key, v in reasons.items()):
            raise ValueError(f"R31BP1_{kind.upper()}_UNEXPECTED_BYPASS")
        components[kind] = {
            "hits": hit_delta, "misses": miss_delta, "bypasses": bypass_delta,
            "hit_rate": rate, "bytes_max": max_size[kind],
            "bypass_reasons": reasons,
            "measurement_basis": "difference_from_first_active_measured_capture",
            "startup_baseline": {key: baseline[key] for key in COUNTERS},
            "last_cumulative": {key: latest[key] for key in COUNTERS},
        }
    return {
        "schema": "dws.net_smooth.r31bp1.measured_window_cache.v2",
        "verdict": "R31BP1_CHUNK_CACHE_ATTRIBUTION_VALID_ONLY",
        "checkpoint_count": captures,
        "active_measured": active,
        "seam_unbound_fallback_measured": fallback,
        "components": components,
        "notes": [
            "Cumulative pre-measurement cache hits never count toward active hit-rate",
            "One first active sample forms the counter baseline, excluding its own change",
            "This diagnostic is NOT frame PERF_PASS or M6/ACK acceptance",
            "CHUNK_OVERSIZE permitted only if explicitly named in bypass_reasons",
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("server_trace", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        report = analyze(args.server_trace)
    except (ValueError, TypeError, OSError, json.JSONDecodeError) as exc:
        print("R31BP1_SOURCE_INCONCLUSIVE: " + str(exc))
        return 2
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({
        "status": report["verdict"], "active": report["active_measured"],
        "hit_rates": {k: round(v["hit_rate"], 4) for k, v in report["components"].items()},
    }))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

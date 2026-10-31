#!/usr/bin/env python3
"""Read-only fail-closed R3.1a cache diagnostics for a single complete GUI run.

DOES NOT replace normative analyze_net_smooth1.py, nor certify M6 disk parity.
All metric values originate from measured checkpoint_capture events in the raw
server trace.jsonl, not guesses or cached summary tables.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path


def percentile(values: list[float], q: float) -> float | None:
    if not values:
        return None
    s = sorted(values)
    return s[min(len(s)-1, math.ceil(q*len(s))-1)]


def audit(trace_path: Path, *, minimum_count: int = 10, min_hit_fraction: float = .90) -> dict:
    metrics: dict[str, list[float]] = {
        "capture_ms": [], "authority_ms": [], "replay_ms": [],
        "handoff_ms": [],
    }
    generations = []
    hits = 0
    misses = 0
    bypasses: dict[str, int] = {}
    event_count = 0
    problems: list[str] = []
    first_gen = None
    with trace_path.open(encoding="utf-8") as stream:
        for row_number, raw in enumerate(stream, 1):
            event = json.loads(raw)
            if event.get("kind") != "checkpoint_capture" or event.get("measure") is not True:
                continue
            data = event.get("data", {})
            event_count += 1
            if data.get("r3c4r2_worker_envelope") is not True:
                problems.append("R2 worker envelope off")
            hit = data.get("r31_cache_hit")
            if type(hit) is not bool:
                problems.append(f"missing/invalid r31_cache_hit at {row_number}")
            elif hit:
                hits += 1
            else:
                misses += 1
            reason = data.get("r31_cache_bypassed", None)
            if type(reason) is not str:
                problems.append("cache bypass reason missing")
            elif reason:
                bypasses[reason] = bypasses.get(reason, 0) + 1
            generation = data.get("r31_projection_generation")
            if type(generation) is not int:
                problems.append("projection generation non-integer")
            elif generation < 1 and not reason:
                problems.append("nonpositive cached projection generation")
            else:
                generations.append(generation)
                if first_gen is None and generation > 0:
                    first_gen = generation
            for field in metrics:
                value = data.get(field)
                if type(value) not in (int, float) or not math.isfinite(value) or value < 0:
                    problems.append(f"{field} absent/nonfinite")
                else:
                    metrics[field].append(float(value))
    if event_count < minimum_count:
        problems.append(f"too few measured periodic captures: {event_count} < {minimum_count}")
    if any(len(v) != event_count for v in metrics.values()):
        problems.append("incomplete timing series")
    fraction = hits / event_count if event_count else 0.0
    if fraction < min_hit_fraction:
        problems.append(f"cache reuse {fraction:.4f} < required {min_hit_fraction:.4f}")
    if bypasses:
        problems.append("cache bypass observed; cannot claim fast-path acceptance")
    if generations and any(a > b for a, b in zip(generations, generations[1:])):
        problems.append("cache generation regressed")
    return {
        "schema": "dws.net_smooth.r3c4.r31.cache_diagnostic.v1",
        "verdict": "CACHE_DIAGNOSTIC_PASS" if not problems else "CACHE_DIAGNOSTIC_FAIL",
        "never_merge_automatically": True,
        "checkpoint_count": event_count, "cache_hits": hits, "cache_misses": misses,
        "cache_hit_fraction": fraction, "cache_bypasses": bypasses,
        "projection_generation_first": first_gen,
        "projection_generation_last": generations[-1] if generations else None,
        "timings_ms": {
            field: {
                "count": len(values), "p50": percentile(values, .5),
                "p99": percentile(values, .99), "max": max(values, default=None)
            } for field, values in metrics.items()
        },
        "problems": sorted(set(problems)),
        "note": "Use unmodified normative analyzer and independent M6 durability checks separately",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path)
    parser.add_argument("--output", type=Path)
    opts = parser.parse_args()
    try:
        report = audit(opts.trace)
    except (OSError, ValueError, TypeError, json.JSONDecodeError) as exc:
        print("CACHE_DIAGNOSTIC_INCONCLUSIVE: " + str(exc))
        return 2
    if opts.output is not None:
        opts.output.parent.mkdir(parents=True, exist_ok=True)
        opts.output.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps({
        "verdict": report["verdict"],
        "checkpoint_count": report["checkpoint_count"],
        "cache_hit_fraction": report["cache_hit_fraction"],
        "bypasses": report["cache_bypasses"],
        "problems": report["problems"],
    }))
    return 0 if report["verdict"] == "CACHE_DIAGNOSTIC_PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""R3B diagnostic: separate legacy main-thread waits from async M6 work.

This is a diagnostic, not a way to bypass the separate 59Hz / client frame
acceptance gates. Missing command classes remain UNVERIFIED.
"""
from __future__ import annotations
import argparse
from collections import Counter, defaultdict
import json
import math
from pathlib import Path


def metric(values):
    values = sorted(values)
    if not values:
        return {"count": 0, "p50": None, "p99": None, "max": None}
    def p(q):
        return values[min(len(values) - 1, max(0, math.ceil(q * len(values)) - 1))]
    return {"count": len(values), "p50": p(.5), "p99": p(.99), "max": values[-1]}


def analyze(path: Path) -> dict:
    by_command = defaultdict(lambda: {"total_ms": [], "writer_wait_ms": []})
    async_kinds = Counter()
    periodic_routes = Counter()
    capture = defaultdict(list)
    count = 0
    with path.open(encoding="utf-8") as stream:
        for line in stream:
            event = json.loads(line)
            if not isinstance(event, dict) or not isinstance(event.get("data"), dict):
                raise ValueError("invalid NET-SMOOTH trace record")
            if event.get("kind") == "end":
                footer = event["data"]
                if footer.get("dropped") or footer.get("io_errors"):
                    raise ValueError("trace loss")
                continue
            # Full trace, including reconnect/shutdown. Measurement gating is
            # left to the independently configured smoothness analyzer.
            kind, data = event.get("kind"), event["data"]
            if kind == "legacy_command_main_thread":
                name = str(data.get("command_type", "UNKNOWN"))
                for key, target in (("total_ms", "total_ms"), ("prior_writer_wait_ms", "writer_wait_ms")):
                    val = float(data[key])
                    if val < 0 or not math.isfinite(val):
                        raise ValueError("nonfinite legacy latency")
                    by_command[name][target].append(val)
                count += 1
            elif kind == "p1b_item_async_stages" and data.get("stage") == "DURABLE_COMMIT":
                async_kinds[str(data.get("kind", "ITEM"))] += 1
            elif kind == "periodic_checkpoint_dispatch":
                periodic_routes[str(data.get("route", "UNKNOWN"))] += 1
            elif kind == "p1b_item_capture_breakdown":
                for key, value in data.items():
                    if key.endswith("_ms"):
                        value = float(value)
                        if value < 0 or not math.isfinite(value):
                            raise ValueError("invalid capture stage metric")
                        capture[key].append(value)
    return {
        "schema": "dws.net_smooth.r3b_legacy_diagnostic.v1",
        "evidence_class": "DIAGNOSTIC_ONLY",
        "legacy_sync_count": count,
        "by_command": {
            name: {key: metric(values) for key, values in fields.items()}
            for name, fields in sorted(by_command.items())
        },
        "async_durable_completions": dict(async_kinds),
        "periodic_dispatch_routes": dict(periodic_routes),
        "item_capture_stages": {key: metric(values) for key, values in sorted(capture.items())},
        "legacy_types_without_observed_sync_stall_are_not_proven_async": True,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("server_trace", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        value = analyze(args.server_trace)
    except (OSError, ValueError, TypeError, KeyError) as exc:
        print(f"R3B INCONCLUSIVE: {exc}")
        return 2
    if args.output:
        args.output.write_text(json.dumps(value, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(value, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

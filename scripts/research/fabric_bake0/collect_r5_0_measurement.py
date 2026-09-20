#!/usr/bin/env python3
"""Collect R5.0 5k baseline observations without turning timing into correctness."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import statistics
from pathlib import Path
from typing import Any


BASELINE_PREFIX = "FABRIC_R5_0_BASELINE="
PASS_MARKER = "FABRIC R5.0 MEASUREMENT 5K: PASS"
EXPECTED_STAGES = [
    "source_create_with_expanded_digests",
    "source_full_rehash_validation",
    "parent_aggregate_compile",
    "bake_start",
    "baked_boundary_hot_loop_before",
    "local_unbake_20",
    "local_capsule_capture",
    "local_capsule_restore",
    "canonical_successor_create",
    "canonical_mutation_fence",
    "fenced_capsule_capture",
    "fenced_capsule_restore",
    "local_rebake_after_settle",
    "baked_boundary_hot_loop_after",
    "final_capsule_capture",
    "final_capsule_restore",
]


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()


def sha256_value(value: Any) -> str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


def parse_log(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8", errors="replace")
    if PASS_MARKER not in text:
        raise ValueError(f"PASS marker missing in {path}")
    rows = [line[len(BASELINE_PREFIX):] for line in text.splitlines() if line.startswith(BASELINE_PREFIX)]
    if len(rows) != 1:
        raise ValueError(f"expected exactly one baseline JSON in {path}, got {len(rows)}")
    data = json.loads(rows[0])
    if data.get("schema") != "planet_simulator.fabric_r5_0_measurement_harness.v1":
        raise ValueError(f"unexpected schema in {path}")
    stages = data.get("stages", {})
    missing = [name for name in EXPECTED_STAGES if name not in stages]
    if missing:
        raise ValueError(f"missing stages in {path}: {missing}")
    for name in EXPECTED_STAGES:
        duration = stages[name].get("duration_us")
        if not isinstance(duration, int) or duration < 0:
            raise ValueError(f"invalid stage duration {name} in {path}")
    return data


def parse_elapsed(value: str) -> float:
    parts = value.strip().split(":")
    if len(parts) == 2:
        return float(parts[0]) * 60.0 + float(parts[1])
    if len(parts) == 3:
        return float(parts[0]) * 3600.0 + float(parts[1]) * 60.0 + float(parts[2])
    return float(value)


def parse_time(path: Path) -> dict[str, Any]:
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    values: dict[str, str] = {}
    for raw in lines:
        line = raw.strip()
        if ": " in line:
            key, value = line.rsplit(": ", 1)
            values[key] = value.strip()

    def number(key: str, cast=float):
        if key not in values:
            raise ValueError(f"GNU time field missing in {path}: {key}")
        return cast(values[key].replace(",", ""))

    cpu_raw = values.get("Percent of CPU this job got", "")
    if not cpu_raw.endswith("%"):
        raise ValueError(f"CPU percentage missing in {path}")
    elapsed_key = next((k for k in values if k.startswith("Elapsed (wall clock) time")), None)
    if elapsed_key is None:
        raise ValueError(f"elapsed field missing in {path}")
    return {
        "user_time_s": number("User time (seconds)"),
        "system_time_s": number("System time (seconds)"),
        "cpu_percent": float(cpu_raw[:-1]),
        "elapsed_s": parse_elapsed(values[elapsed_key]),
        "max_rss_kb": number("Maximum resident set size (kbytes)", int),
        "minor_page_faults": number("Minor (reclaiming a frame) page faults", int),
        "major_page_faults": number("Major (requiring I/O) page faults", int),
        "voluntary_context_switches": number("Voluntary context switches", int),
        "involuntary_context_switches": number("Involuntary context switches", int),
    }


def median_int(values: list[int]) -> int:
    return int(statistics.median(values))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", action="append", required=True)
    ap.add_argument("--time", action="append", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    if len(args.log) != len(args.time) or len(args.log) < 3:
        raise SystemExit("R5_0_EVIDENCE_REQUIRES_AT_LEAST_THREE_PAIRED_SAMPLES")

    samples = []
    deterministic_hashes = set()
    deterministic_payload_hashes = set()
    for index, (log_name, time_name) in enumerate(zip(args.log, args.time), start=1):
        baseline = parse_log(Path(log_name))
        process = parse_time(Path(time_name))
        counters = baseline.get("counters", {})
        if counters.get("canonical_parts") != 5000:
            raise ValueError("R5_0_PART_COUNT_DRIFT")
        if counters.get("active_full_peak") != 20:
            raise ValueError("R5_0_ACTIVE_FULL_PEAK_DRIFT")
        if counters.get("local_reconstructed_parts") != 20:
            raise ValueError("R5_0_LOCAL_RECONSTRUCTION_DRIFT")
        if counters.get("rebake_local_validations") != 20:
            raise ValueError("R5_0_LOCAL_REBAKE_VALIDATION_DRIFT")
        if counters.get("global_physical_rebuilds") != 0:
            raise ValueError("R5_0_GLOBAL_REBUILD_PRESENT")
        if counters.get("duplicate_ownership_count") != 0:
            raise ValueError("R5_0_DUPLICATE_OWNER_PRESENT")
        if counters.get("boundary_execute_calls") != 128:
            raise ValueError("R5_0_BOUNDARY_CALL_COUNT_DRIFT")
        deterministic_hashes.add(str(baseline["deterministic_hash"]))
        deterministic_payload_hashes.add(sha256_value(baseline["deterministic"]))
        samples.append({
            "sample": index,
            "baseline": baseline,
            "process": process,
        })

    if len(deterministic_hashes) != 1 or len(deterministic_payload_hashes) != 1:
        raise ValueError("R5_0_DETERMINISM_MISMATCH")

    stage_summary = {}
    for name in EXPECTED_STAGES:
        durations = [int(s["baseline"]["stages"][name]["duration_us"]) for s in samples]
        memory_after = [int(s["baseline"]["stages"][name]["memory_after_bytes"]) for s in samples]
        object_delta = [int(s["baseline"]["stages"][name]["object_delta"]) for s in samples]
        stage_summary[name] = {
            "duration_us_min": min(durations),
            "duration_us_median": median_int(durations),
            "duration_us_max": max(durations),
            "memory_after_bytes_median": median_int(memory_after),
            "object_delta_median": median_int(object_delta),
        }

    rss = [int(s["process"]["max_rss_kb"]) for s in samples]
    elapsed = [float(s["process"]["elapsed_s"]) for s in samples]
    cpu = [float(s["process"]["cpu_percent"]) for s in samples]
    static_peak = [int(s["baseline"]["memory_static_peak_bytes"]) for s in samples]

    result = {
        "schema": "planet_simulator.fabric_r5_0_5k_measurement_evidence.v1",
        "sample_count": len(samples),
        "correctness": {
            "deterministic_hash": next(iter(deterministic_hashes)),
            "deterministic_payload_sha256": next(iter(deterministic_payload_hashes)),
            "part_count": 5000,
            "active_full_peak": 20,
            "local_reconstructed_parts": 20,
            "rebake_local_validations": 20,
            "global_physical_rebuilds": 0,
            "duplicate_ownership_count": 0,
            "boundary_execute_calls": 128,
        },
        "observations": {
            "stage_summary": stage_summary,
            "godot_memory_static_peak_bytes": {
                "min": min(static_peak),
                "median": median_int(static_peak),
                "max": max(static_peak),
            },
            "process_max_rss_kb": {
                "min": min(rss),
                "median": median_int(rss),
                "max": max(rss),
            },
            "process_elapsed_s": {
                "min": min(elapsed),
                "median": statistics.median(elapsed),
                "max": max(elapsed),
            },
            "process_cpu_percent": {
                "min": min(cpu),
                "median": statistics.median(cpu),
                "max": max(cpu),
            },
        },
        "samples": samples,
        "policy": {
            "timing_is_acceptance_threshold": False,
            "rss_is_acceptance_threshold": False,
            "exact_allocator_events_available": False,
            "object_count_is_allocation_proxy": True,
            "process_rss_source": "GNU time -v",
            "purpose": "R5.0 baseline for future relative comparisons; correctness is deterministic, timings are observations.",
        },
    }
    result["evidence_hash"] = sha256_value(result)
    target = Path(args.out)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("FABRIC_R5_0_EVIDENCE_HASH=" + result["evidence_hash"])
    print("FABRIC_R5_0_DETERMINISTIC_HASH=" + result["correctness"]["deterministic_hash"])
    print("FABRIC_R5_0_EVIDENCE=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

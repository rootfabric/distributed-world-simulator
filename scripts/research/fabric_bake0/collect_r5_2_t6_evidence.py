#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, statistics
from pathlib import Path

PREFIX = "FABRIC_R5_2_T6_RESULT="
PASS = "FABRIC R5.2 T6 POWER STAGE: PASS"

def canonical_hash(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()

def parse_time(path: Path):
    values = {}
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if ": " in line:
            k, v = line.rsplit(": ", 1)
            values[k] = v.strip()
    key = next(k for k in values if k.startswith("Elapsed (wall clock) time"))
    p = values[key].split(":")
    elapsed = float(p[-1])
    if len(p) >= 2: elapsed += float(p[-2]) * 60
    if len(p) >= 3: elapsed += float(p[-3]) * 3600
    return {"elapsed_s": elapsed, "max_rss_kib": int(values["Maximum resident set size (kbytes)"].replace(",", ""))}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    root = Path(args.root)
    samples = []
    hashes = set()
    for i in (1, 2, 3):
        text = (root / f"sample-{i}.log").read_text(encoding="utf-8", errors="replace")
        if PASS not in text:
            raise ValueError(f"PASS missing sample {i}")
        rows = [line[len(PREFIX):] for line in text.splitlines() if line.startswith(PREFIX)]
        if len(rows) != 1:
            raise ValueError(f"result row count sample {i}: {len(rows)}")
        data = json.loads(rows[0])
        assert data["source_dies"] == 256
        assert data["active_dies"] == 256
        assert data["banks"] == 4
        assert data["source_operations"] == 1536
        assert data["compiled_operations"] == 18
        assert data["runtime_source_die_traversals"] == 0
        assert data["sequence_ticks"] == 2048
        assert data["full_reference_die_traversals"] == 256 * 2048
        assert data["maximum_load_voltage_error"] <= 1e-9
        assert data["maximum_bus_current_error"] <= 1e-9
        assert data["maximum_conduction_heat_error"] <= 1e-9
        assert data["maximum_switching_heat_error"] <= 1e-9
        assert data["maximum_energy_residual_j"] <= 1e-9
        assert data["regeneration_seen"] is True
        assert data["damage_active_dies"] == 255
        assert data["unsafe_geometry_error"] == "POWER_STAGE_PARALLEL_CURRENT_SYNCHRONY_UNSAFE"
        assert data["mixed_profile_error"] == "POWER_STAGE_PROFILE_MISMATCH"
        assert data["open_bank_error"] == "POWER_STAGE_BANK_OPEN"
        assert data["composition_max_voltage_error"] <= 1e-9
        assert data["composition_max_energy_error"] <= 1e-9
        assert data["composition_regeneration_seen"] is True
        hashes.add(canonical_hash(data))
        samples.append({"sample": i, "deterministic": data, "process": parse_time(root / f"sample-{i}.time.txt")})
    if len(hashes) != 1:
        raise ValueError("T6_DETERMINISM_MISMATCH")
    elapsed = [s["process"]["elapsed_s"] for s in samples]
    rss = [s["process"]["max_rss_kib"] for s in samples]
    d = samples[0]["deterministic"]
    result = {
        "schema": "planet_simulator.fabric_r5_2_t6_evidence.v1",
        "sample_count": 3,
        "deterministic_hash": next(iter(hashes)),
        "claims": d,
        "observations": {
            "process_elapsed_s": {"min": min(elapsed), "median": statistics.median(elapsed), "max": max(elapsed)},
            "process_max_rss_kib": {"min": min(rss), "median": int(statistics.median(rss)), "max": max(rss)},
        },
        "samples": samples,
        "policy": {
            "timing_is_acceptance_threshold": False,
            "semiconductor_profile_is_characterized_floor": True,
            "runtime_source_traversal_claimed_zero": True,
            "t5_composition_is_acceptance_semantics": True,
        },
    }
    result["evidence_hash"] = canonical_hash(result)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("FABRIC_R5_2_T6_DETERMINISTIC_HASH=" + result["deterministic_hash"])
    print("FABRIC_R5_2_T6_EVIDENCE_HASH=" + result["evidence_hash"])
    print("FABRIC_R5_2_T6_EVIDENCE=PASS")

if __name__ == "__main__":
    main()

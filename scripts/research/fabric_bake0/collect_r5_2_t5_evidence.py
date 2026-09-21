#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, statistics
from pathlib import Path

PREFIX = "FABRIC_R5_2_T5_RESULT="
PASS = "FABRIC R5.2 T5 MOTOR GENERATOR: PASS"

def canonical_hash(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()

def parse_time(path: Path):
    values = {}
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if ": " in line:
            k, v = line.rsplit(": ", 1)
            values[k] = v.strip()
    elapsed_key = next(k for k in values if k.startswith("Elapsed (wall clock) time"))
    parts = values[elapsed_key].split(":")
    elapsed = float(parts[-1])
    if len(parts) >= 2:
        elapsed += float(parts[-2]) * 60
    if len(parts) >= 3:
        elapsed += float(parts[-3]) * 3600
    return {
        "elapsed_s": elapsed,
        "max_rss_kib": int(values["Maximum resident set size (kbytes)"].replace(",", "")),
    }

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    root = Path(args.root)

    samples = []
    hashes = set()
    identities = set()
    for i in (1, 2, 3):
        text = (root / f"sample-{i}.log").read_text(encoding="utf-8", errors="replace")
        if PASS not in text:
            raise ValueError(f"PASS missing sample {i}")
        rows = [x[len(PREFIX):] for x in text.splitlines() if x.startswith(PREFIX)]
        if len(rows) != 1:
            raise ValueError(f"result row count sample {i}: {len(rows)}")
        d = json.loads(rows[0])
        assert d["source_components"] == 256
        assert d["winding_segments"] == 192
        assert d["rotor_sectors"] == 64
        assert d["state_scalars"] == 1
        assert d["runtime_source_component_traversals"] == 0
        assert d["sequence_ticks"] == 2048
        assert d["full_reference_component_traversals"] == 256 * 2048
        assert d["maximum_voltage_error"] <= 1.0e-9
        assert d["maximum_torque_error"] <= 1.0e-12
        assert d["maximum_omega_error"] <= 1.0e-9
        assert d["maximum_electrical_energy_residual_j"] <= 1.0e-9
        assert d["maximum_total_energy_residual_j"] <= 1.0e-9
        assert d["generator_observed"] is True
        assert d["generator_electrical_energy_j"] < 0.0
        assert d["generator_torque_nm"] < 0.0
        assert d["history_voltage_delta_v"] > 1.0
        assert d["replay_max_voltage_error"] == 0.0
        assert d["replay_max_state_error"] == 0.0
        assert d["open_winding_error"] == "MOTOR_WINDING_OPEN"
        assert d["incomplete_rotor_error"] == "MOTOR_ROTOR_INCOMPLETE"
        assert d["quality_projection_kind"] == "COEFFICIENT_CHANGE_SAME_ROTOR_INERTIA"
        assert d["quality_rebuilt_parity_error"] <= 1.0e-9
        assert d["inertia_change_projection_error"] == "MOTOR_STATE_RECONSTRUCTION_INERTIA_CHANGE_UNSUPPORTED"
        assert d["overspeed_error"] == "MOTOR_GENERATOR_RUNTIME_SPEED_OUT_OF_DOMAIN"
        hashes.add(canonical_hash(d))
        identities.add((d["graph_hash"], d["descriptor_hash"], d["capsule_checksum"]))
        samples.append({"sample": i, "deterministic": d, "process": parse_time(root / f"sample-{i}.time.txt")})

    if len(hashes) != 1:
        raise ValueError("T5_DETERMINISM_MISMATCH")
    if len(identities) != 1:
        raise ValueError("T5_IDENTITY_MISMATCH")

    elapsed = [s["process"]["elapsed_s"] for s in samples]
    rss = [s["process"]["max_rss_kib"] for s in samples]
    d = samples[0]["deterministic"]
    result = {
        "schema": "planet_simulator.fabric_r5_2_t5_evidence.v1",
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
            "rss_is_acceptance_threshold": False,
            "electromagnetic_profile_is_characterized_floor": True,
            "mass_inertia_and_speed_envelope_derive_from_matter_and_geometry": True,
            "runtime_owns_persistent_state": False,
        },
    }
    result["evidence_hash"] = canonical_hash(result)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("FABRIC_R5_2_T5_DETERMINISTIC_HASH=" + result["deterministic_hash"])
    print("FABRIC_R5_2_T5_EVIDENCE_HASH=" + result["evidence_hash"])
    print("FABRIC_R5_2_T5_EVIDENCE=PASS")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, statistics
from pathlib import Path

PREFIX = "FABRIC_R5_2_T4_RESULT="
PASS = "FABRIC R5.2 T4 STATEFUL FILTER THERMAL PACK: PASS"

def canonical_hash(value):
    raw = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()

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
    payload_hashes = set()
    graph_hashes = set()
    descriptor_hashes = set()
    capsule_checksums = set()

    for i in (1, 2, 3):
        log = root / f"sample-{i}.log"
        text = log.read_text(encoding="utf-8", errors="replace")
        if PASS not in text:
            raise ValueError(f"PASS missing sample {i}")
        rows = [line[len(PREFIX):] for line in text.splitlines() if line.startswith(PREFIX)]
        if len(rows) != 1:
            raise ValueError(f"result row count sample {i}: {len(rows)}")
        data = json.loads(rows[0])

        assert data["source_cells"] == 512
        assert data["layers"] == 8
        assert data["lanes"] == 64
        assert data["state_scalars"] == 8
        assert data["source_operations"] == 3072
        assert data["compiled_operations"] == 36
        assert data["runtime_source_cell_traversals"] == 0
        assert data["sequence_ticks"] == 2048
        assert data["full_reference_cell_traversals"] == 512 * 2048
        assert data["maximum_output_temperature_error"] <= 1.0e-9
        assert data["maximum_layer_temperature_error"] <= 1.0e-9
        assert data["maximum_energy_residual_j"] <= 1.0e-8
        assert data["asymmetry_error"] == "THERMAL_PACK_LAYER_SYMMETRY_BROKEN"
        assert data["off_manifold_error"] == "THERMAL_STATE_NOT_IN_REDUCTION_MANIFOLD"
        assert data["history_output_delta_k"] > 1.0e-3
        assert data["replay_max_output_error"] == 0.0
        assert data["replay_max_state_error"] == 0.0

        payload_hashes.add(canonical_hash(data))
        graph_hashes.add(data["graph_hash"])
        descriptor_hashes.add(data["descriptor_hash"])
        capsule_checksums.add(data["capsule_checksum"])
        samples.append({
            "sample": i,
            "deterministic": data,
            "process": parse_time(root / f"sample-{i}.time.txt"),
        })

    if len(payload_hashes) != 1:
        raise ValueError("T4_DETERMINISM_MISMATCH")
    if len(graph_hashes) != 1 or len(descriptor_hashes) != 1 or len(capsule_checksums) != 1:
        raise ValueError("T4_IDENTITY_MISMATCH")

    elapsed = [s["process"]["elapsed_s"] for s in samples]
    rss = [s["process"]["max_rss_kib"] for s in samples]
    d = samples[0]["deterministic"]

    result = {
        "schema": "planet_simulator.fabric_r5_2_t4_evidence.v1",
        "sample_count": 3,
        "deterministic_hash": next(iter(payload_hashes)),
        "claims": {
            "source_cells": d["source_cells"],
            "layers": d["layers"],
            "lanes": d["lanes"],
            "state_scalars": d["state_scalars"],
            "source_operations": d["source_operations"],
            "compiled_operations": d["compiled_operations"],
            "operation_compression_ratio": d["operation_compression_ratio"],
            "runtime_source_cell_traversals_per_execute": d["runtime_source_cell_traversals"],
            "sequence_ticks": d["sequence_ticks"],
            "full_reference_cell_traversals": d["full_reference_cell_traversals"],
            "maximum_output_temperature_error": d["maximum_output_temperature_error"],
            "maximum_layer_temperature_error": d["maximum_layer_temperature_error"],
            "maximum_energy_residual_j": d["maximum_energy_residual_j"],
            "asymmetry_error": d["asymmetry_error"],
            "off_manifold_error": d["off_manifold_error"],
            "history_output_delta_k": d["history_output_delta_k"],
            "replay_max_output_error": d["replay_max_output_error"],
            "replay_max_state_error": d["replay_max_state_error"],
        },
        "identity": {
            "graph_hash": d["graph_hash"],
            "descriptor_hash": d["descriptor_hash"],
            "capsule_checksum": d["capsule_checksum"],
        },
        "observations": {
            "process_elapsed_s": {
                "min": min(elapsed),
                "median": statistics.median(elapsed),
                "max": max(elapsed),
            },
            "process_max_rss_kib": {
                "min": min(rss),
                "median": int(statistics.median(rss)),
                "max": max(rss),
            },
        },
        "samples": samples,
        "policy": {
            "timing_is_acceptance_threshold": False,
            "rss_is_acceptance_threshold": False,
            "thermal_parameters_are_derived_from_matter_and_geometry": True,
            "runtime_owns_persistent_state": False,
            "arbitrary_heterogeneous_lumping_claimed": False,
        },
    }
    result["evidence_hash"] = canonical_hash(result)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("FABRIC_R5_2_T4_DETERMINISTIC_HASH=" + result["deterministic_hash"])
    print("FABRIC_R5_2_T4_EVIDENCE_HASH=" + result["evidence_hash"])
    print("FABRIC_R5_2_T4_EVIDENCE=PASS")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

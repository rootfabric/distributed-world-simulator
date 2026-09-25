#!/usr/bin/env python3
"""Collect T12 runtime evidence; a source-carrier job is not runtime evidence."""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import re
from pathlib import Path

PREFIX = "FABRIC_R5_2_T12_RESULT="
PASS = "FABRIC R5.2 T12 SHIP MATRYOSHKA: PASS"

def digest(value: object) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()).hexdigest()

def require(ok: bool, reason: str) -> None:
    if not ok:
        raise ValueError(reason)

def validate_result(d: dict) -> None:
    require(d.get("schema") == "fabric.t12.result.v1", "wrong result schema")
    require(d.get("failures") == [], "runtime failures")
    for key, expected in {"instances": 3, "leaf_components": 4275, "state_scalars": 31,
                          "steps": 2048, "leaf_traversals": 0}.items():
        require(d.get(key) == expected, f"invalid {key}")
    require(d.get("checks", 0) >= 8300, "incomplete assertions")
    for key, limit in {"max_energy_residual_j": 1e-7, "max_bus_residual_j": 1e-9,
                       "max_reference_current_error_a": 1e-6}.items():
        v = d.get(key)
        require(isinstance(v, (float, int)) and math.isfinite(v) and 0 <= v <= limit, f"invalid {key}")
    require(0 < d["max_evaluations_per_step"] <= 48, "unbounded solver")
    require(d["evaluations"] >= d["steps"], "missing solver work")
    require(d["compiled_group_visits"] == 12 * d["evaluations"], "compiled group work missing")
    require(d["boundary_calls"] == 19 * d["evaluations"], "child work missing")
    require(d["total_optical_j"] > 0 and d["total_pump_j"] > 0, "missing useful work")
    require(d["regeneration_current_a"] < 0, "no regeneration")
    require(d["overload_error"] == "T12_SHARED_POWER_LIMIT", "no power-limit evidence")
    require(d["refine_path"] == "root/bank/unit03/cannon/emitter", "wrong refinement scope")
    for key in ("capsule_checksum", "final_state_hash"):
        require(re.fullmatch(r"[0-9a-f]{64}", str(d.get(key, ""))) is not None, f"invalid {key}")

def read_sample(path: Path) -> dict:
    text = path.read_text(encoding="utf-8", errors="strict")
    require(PASS in text, "PASS marker missing")
    require(not re.search(r"SCRIPT ERROR|Parse Error|Compile Error|Invalid call|Invalid access|ERROR:", text), "fatal engine log")
    rows = [line[len(PREFIX):] for line in text.splitlines() if line.startswith(PREFIX)]
    require(len(rows) == 1, "ambiguous or missing result")
    def reject_constant(value: str):
        raise ValueError(f"non-JSON constant {value}")
    d = json.loads(rows[0], parse_constant=reject_constant)
    validate_result(d)
    return d

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    results = [read_sample(args.root / f"sample-{i}.log") for i in (1, 2, 3)]
    hashes = [digest(d) for d in results]
    require(len(set(hashes)) == 1, "T12_DETERMINISM_MISMATCH")
    value = {"schema": "fabric.t12.evidence.v1", "status": "IMPLEMENTER_EXACT_3X_PASS",
             "sample_count": 3, "deterministic_hash": hashes[0], "claims": results[0],
             "sample_sha256": {f"sample-{i}.log": hashlib.sha256((args.root / f"sample-{i}.log").read_bytes()).hexdigest() for i in (1, 2, 3)},
             "policy": {"independent_review": "PENDING", "independent_verifier": "PENDING",
                        "production_acceptance": False, "timing_is_acceptance_threshold": False,
                        "source_carrier_is_runtime_pass": False}}
    value["evidence_hash"] = digest(value)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n", encoding="utf-8")
    print("FABRIC_R5_2_T12_DETERMINISTIC_HASH=" + hashes[0])
    print("FABRIC_R5_2_T12_EVIDENCE=PASS")

if __name__ == "__main__":
    main()

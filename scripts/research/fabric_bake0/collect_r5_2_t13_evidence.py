#!/usr/bin/env python3
"""Collect T13 shared-instance runtime evidence."""
from __future__ import annotations
import argparse
import hashlib
import json
import re
from pathlib import Path

PREFIX = "FABRIC_R5_2_T13_RESULT="
PASS = "FABRIC R5.2 T13 SHARED INSTANCES: PASS"

def digest(value: object) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()).hexdigest()

def require(ok: bool, reason: str) -> None:
    if not ok:
        raise ValueError(reason)

def validate_result(d: dict) -> None:
    require(d.get("schema") == "fabric.t13.result.v1", "wrong result schema")
    require(d.get("failures") == [], "runtime failures")
    require(d.get("instance_gates") == [1, 10, 100], "wrong scale gates")
    require(d.get("gate_counts") == {"1": 1, "10": 10, "100": 100}, "incomplete scale gate")
    require(d.get("bindings") == 100, "wrong binding count")
    require(d.get("unique_binding_checksums") == 100, "bindings are not independent")
    require(d.get("source_components_per_model") == 4275, "wrong shared model source count")
    require(d.get("state_scalars_per_instance") == 31, "wrong per-instance state size")
    require(d.get("prepare_count") == 1, "compiled model prepared more than once")
    require(d.get("recompile_events") == 0, "instance execution caused recompile")
    require(d.get("runtime_steps") == 311, "wrong executed step count")
    require(d.get("leaf_traversals") == 0, "source leaves traversed")
    require(d.get("healthy_equivalent_after_damage") == 99, "damage leaked to healthy siblings")
    require(d.get("damaged_instance") == "instance-042", "wrong damage target")
    require(d.get("damage_revision") == 1 and d.get("damaged_diverged") is True, "damage overlay not exercised")
    require(d.get("model_hash_unchanged") is True, "compiled model mutated")
    require(d.get("caller_states_unchanged") is True, "caller baseline state mutated")
    require(d.get("checks", 0) >= 1300, "incomplete assertion set")
    require(d.get("evaluations", 0) >= d["runtime_steps"], "missing solver work")
    require(d.get("compiled_group_visits") == 12 * d["evaluations"], "compiled group accounting mismatch")
    require(d.get("boundary_calls") == 19 * d["evaluations"], "boundary accounting mismatch")
    for key in ("shared_compiled_model_checksum", "shared_compiled_model_hash", "isolation_hash"):
        require(re.fullmatch(r"[0-9a-f]{64}", str(d.get(key, ""))) is not None, f"invalid {key}")

def read_sample(path: Path) -> dict:
    text = path.read_text(encoding="utf-8", errors="strict")
    require(PASS in text, "PASS marker missing")
    require(not re.search(r"SCRIPT ERROR|Parse Error|Compile Error|Invalid call|Invalid access|ERROR:", text), "fatal engine log")
    rows = [line[len(PREFIX):] for line in text.splitlines() if line.startswith(PREFIX)]
    require(len(rows) == 1, "result marker count")
    data = json.loads(rows[0])
    validate_result(data)
    return data

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ns = ap.parse_args()
    samples = [read_sample(ns.root / f"sample-{i}.log") for i in (1, 2, 3)]
    require(samples[0] == samples[1] == samples[2], "three processes are not deterministic")
    h = digest(samples[0])
    payload = {"schema":"fabric.r5_2.t13_exact_evidence.v1", "status":"PASS",
               "deterministic_hash":h, "result":samples[0]}
    ns.out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"FABRIC_R5_2_T13_DETERMINISTIC_HASH={h}")
    print("FABRIC_R5_2_T13_EVIDENCE=PASS")

if __name__ == "__main__":
    main()

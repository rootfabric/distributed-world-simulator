#!/usr/bin/env python3
"""Collect FABRIC R5.2 T14 observation-refinement evidence."""
from __future__ import annotations
import argparse
import hashlib
import json
import re
from pathlib import Path

PREFIX = "FABRIC_R5_2_T14_RESULT="
PASS = "FABRIC R5.2 T14 OBSERVATION REFINEMENT: PASS"

def digest(value: object) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()).hexdigest()

def require(ok: bool, reason: str) -> None:
    if not ok:
        raise ValueError(reason)

def is_hex64(value) -> bool:
    return isinstance(value, str) and len(value) == 64 and value == value.lower() and all(c in "0123456789abcdef" for c in value)

def validate_result(d: dict) -> None:
    require(d.get("schema") == "fabric.t14.result.v1", "wrong schema")
    require(d.get("failures") == [], "runtime failures")
    require(d.get("checks", 0) >= 650, "incomplete assertion set")
    require(d.get("instances") == 100, "wrong instance count")
    require(d.get("family_counts") == {"family-a":40, "family-b":30, "family-c":20, "family-d":10}, "wrong family population")
    require(d.get("compile_events") == 42, "T13.5 compile baseline changed")
    require(d.get("unique_family_models") == 4, "wrong family prepare count")
    require(d.get("observed_instance") == "t14-instance-058", "wrong observed instance")
    require(d.get("observed_family") == "family-b", "wrong observed family")
    require(d.get("refined_path") == "root/bank/unit03/cannon", "wrong refined path")
    require(d.get("detail_node_count") == 4, "wrong detail node count")
    require(d.get("detail_leaf_count") == 3, "wrong detail leaf count")
    require(is_hex64(d.get("selected_subtree_hash")), "invalid selected subtree hash")
    require(is_hex64(d.get("detail_manifest_hash")), "invalid detail manifest hash")
    require(d.get("refined_instances_during_observation") == 1, "wrong refined instance count")
    require(d.get("compact_instances_during_observation") == 99, "other instances not compact")
    require(d.get("same_instance_compact_siblings") == 5, "same-instance siblings not compact")
    require(d.get("other_compact_instances") == 99, "other instances resolution leaked")
    require(d.get("physics_equivalent_after_refinement") == 100, "observation changed physics")
    require(d.get("snapshot_roundtrip") is True, "refinement snapshot round-trip failed")
    require(d.get("successful_requests") == 1, "wrong successful request count")
    require(d.get("restore_count") == 1, "wrong restore count")
    require(d.get("release_count") == 2, "wrong release count")
    require(d.get("materialization_count") == 2, "wrong materialization count")
    require(d.get("detail_nodes_materialized") == 8, "refinement traversed outside selected compiled subtree")
    require(d.get("source_leaf_traversals") == 0, "observation traversed source leaves")
    require(d.get("recompile_events") == 0, "observation recompiled")
    require(d.get("active_refinements_final") == 0, "refinement leaked")
    require(d.get("runtime_steps") == 200, "wrong physics step count")
    require(d.get("physics_leaf_traversals") == 0, "physics left compact path")
    require(d.get("evaluations", 0) >= d["runtime_steps"], "solver work missing")
    require(d.get("compiled_group_visits") == 12 * d["evaluations"], "compiled group accounting mismatch")
    require(d.get("boundary_calls") == 19 * d["evaluations"], "boundary accounting mismatch")
    require(d.get("caller_instances_unchanged") is True, "caller instance state mutated")
    require(d.get("model_identities_unchanged") is True, "family model identity changed")
    require(d.get("all_models_intact") is True, "family model integrity failed")

def read_sample(path: Path) -> tuple[str, dict]:
    text = path.read_text(encoding="utf-8", errors="strict")
    require(PASS in text, "PASS marker missing")
    require(not re.search(r"SCRIPT ERROR|Parse Error|Compile Error|Invalid call|Invalid access|ERROR:", text), "fatal engine log")
    rows = [line[len(PREFIX):] for line in text.splitlines() if line.startswith(PREFIX)]
    require(len(rows) == 1, "result marker count")
    value = json.loads(rows[0])
    validate_result(value)
    return rows[0], value

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ns = ap.parse_args()
    values = [read_sample(ns.root / f"sample-{i}.log") for i in (1,2,3)]
    require(values[0][0] == values[1][0] == values[2][0], "raw payloads are not byte-identical")
    require(values[0][1] == values[1][1] == values[2][1], "parsed payloads differ")
    h = digest(values[0][1])
    payload = {
        "schema":"fabric.r5_2.t14_exact_evidence.v1",
        "status":"PASS",
        "deterministic_hash":h,
        "result":values[0][1],
    }
    ns.out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"FABRIC_R5_2_T14_DETERMINISTIC_HASH={h}")
    print("FABRIC_R5_2_T14_EVIDENCE=PASS")

if __name__ == "__main__":
    main()

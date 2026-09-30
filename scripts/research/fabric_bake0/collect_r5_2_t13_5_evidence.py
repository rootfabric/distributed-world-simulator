#!/usr/bin/env python3
"""Collect FABRIC R5.2 T13.5 shared-family evidence."""
from __future__ import annotations
import argparse
import hashlib
import json
import re
from pathlib import Path

PREFIX = "FABRIC_R5_2_T13_5_RESULT="
PASS = "FABRIC R5.2 T13.5 SHARED FAMILIES: PASS"

def digest(value: object) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()).hexdigest()

def require(ok: bool, reason: str) -> None:
    if not ok:
        raise ValueError(reason)

def validate_result(d: dict) -> None:
    require(d.get("schema") == "fabric.t13_5.result.v1", "wrong schema")
    require(d.get("failures") == [], "runtime failures")
    require(d.get("checks", 0) >= 650, "incomplete assertion set")
    require(d.get("instances") == 100, "wrong instance count")
    require(d.get("family_counts") == {"family-a":40, "family-b":30, "family-c":20, "family-d":10}, "wrong family population")
    require(d.get("family_registrations") == 5, "wrong family registration count")
    require(d.get("family_aliases") == 1, "exact-family alias not exercised")
    require(d.get("unique_family_models") == 4, "wrong unique family count")
    require(d.get("compile_events") == 42, "selective compile count changed")
    require(d.get("naive_full_compile_events") == 3000, "wrong naive baseline")
    require(d.get("compile_events_avoided") == 2958, "compile avoidance accounting mismatch")
    require(d.get("subtree_occurrences") == 120, "wrong subtree occurrence count")
    require(d.get("unique_subtree_hashes") == 42, "wrong unique subtree count")
    require(d.get("shared_subtree_hashes") == 29, "wrong shared subtree count")
    require(d.get("subtree_intern_events") == 42, "subtree pool intern count mismatch")
    require(d.get("subtree_reuse_hits") == 78, "subtree reuse accounting mismatch")
    require(d.get("max_family_reuse") == 4, "cross-family reuse not demonstrated")
    require(d.get("runtime_steps") == 200, "wrong runtime step count")
    require(d.get("leaf_traversals") == 0, "source leaves traversed")
    require(d.get("evaluations", 0) >= d["runtime_steps"], "solver work missing")
    require(d.get("compiled_group_visits") == 12 * d["evaluations"], "compiled group accounting mismatch")
    require(d.get("boundary_calls") == 19 * d["evaluations"], "boundary accounting mismatch")
    require(d.get("damaged_instance") == "family-instance-058", "wrong damage target")
    require(d.get("damaged_family") == "family-b", "wrong damaged family")
    require(d.get("damage_revision") == 1, "wrong damage revision")
    require(d.get("healthy_equivalent_after_damage") == 99, "damage leaked to other instances")
    require(d.get("damaged_diverged") is True, "damaged instance did not diverge")
    require(d.get("all_models_intact") is True, "family model integrity failed")

def read_sample(path: Path) -> dict:
    text = path.read_text(encoding="utf-8", errors="strict")
    require(PASS in text, "PASS marker missing")
    require(not re.search(r"SCRIPT ERROR|Parse Error|Compile Error|Invalid call|Invalid access|ERROR:", text), "fatal engine log")
    rows = [line[len(PREFIX):] for line in text.splitlines() if line.startswith(PREFIX)]
    require(len(rows) == 1, "result marker count")
    value = json.loads(rows[0])
    validate_result(value)
    return value

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ns = ap.parse_args()
    samples = [read_sample(ns.root / f"sample-{i}.log") for i in (1, 2, 3)]
    require(samples[0] == samples[1] == samples[2], "three processes are not deterministic")
    h = digest(samples[0])
    payload = {
        "schema":"fabric.r5_2.t13_5_exact_evidence.v1",
        "status":"PASS",
        "deterministic_hash":h,
        "result":samples[0],
    }
    ns.out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"FABRIC_R5_2_T13_5_DETERMINISTIC_HASH={h}")
    print("FABRIC_R5_2_T13_5_EVIDENCE=PASS")

if __name__ == "__main__":
    main()

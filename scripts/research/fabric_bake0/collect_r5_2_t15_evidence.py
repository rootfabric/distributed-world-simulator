#!/usr/bin/env python3
"""Collect FABRIC R5.2 T15 local-damage evidence."""
from __future__ import annotations
import argparse, hashlib, json, re
from pathlib import Path

PREFIX = "FABRIC_R5_2_T15_RESULT="
PASS = "FABRIC R5.2 T15 LOCAL DAMAGE UNBAKE REBAKE: PASS"

def require(ok: bool, reason: str) -> None:
    if not ok:
        raise ValueError(reason)

def digest(value: object) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()
    return hashlib.sha256(raw).hexdigest()

def validate_result(d: dict) -> None:
    require(d.get("schema") == "fabric.t15.result.v1", "wrong schema")
    require(d.get("failures") == [], "runtime failures")
    require(d.get("checks", 0) >= 350, "incomplete assertion set")
    require(d.get("instances") == 100, "wrong instance count")
    require(d.get("family_counts") == {"family-a":40,"family-b":30,"family-c":20,"family-d":10}, "wrong family counts")
    require(d.get("target_instance") == "t15-instance-058", "wrong target")
    require(d.get("target_original_family") == "family-b", "wrong target family")
    require(d.get("selected_path") == "root/bank/unit03/cannon/emitter", "wrong damage path")
    require(d.get("baseline_compile_events") == 42, "baseline compile drift")
    require(d.get("damage_compile_events") == 5, "damage compile scope")
    require(d.get("repair_compile_events") == 5, "repair compile scope")
    require(d.get("local_compile_events_total") == 10, "local compile total")
    require(d.get("source_leaf_traversals_rebuild") == 256, "rebuild leaf traversal scope")
    require(d.get("source_anchor_checks") == 2, "source anchor checks")
    require(d.get("source_components_per_ship") == 4275, "source component count drift")
    require(d.get("changed_paths_per_mutation") == 5, "changed-path scope")
    require(d.get("unchanged_subtrees_per_mutation") == 25, "unchanged subtree scope")
    require(d.get("original_family_models") == 4 and d.get("final_family_models") == 6, "family model accounting")
    require(d.get("final_unique_subtree_hashes") == 52, "unique subtree accounting")
    require(d.get("final_subtree_occurrences") == 180, "subtree occurrence accounting")
    require(d.get("final_subtree_reuse_hits") == 128, "subtree reuse accounting")
    require(d.get("healthy_equivalent_after_damage") == 99, "unaffected instances diverged")
    require(d.get("damaged_target_diverged") is True, "damaged target did not diverge")
    require(d.get("repair_restored_healthy_behavior") is True, "repair did not restore healthy behavior")
    require(d.get("repair_differs_from_damaged_continuation") is True, "repair equals damaged continuation")
    require(d.get("physical_state_preserved_on_damage") is True, "damage projection reset state")
    require(d.get("physical_state_preserved_on_repair") is True, "repair projection reset state")
    require(d.get("final_damage_revision") == 2, "mutation revision accounting")
    require(d.get("steady_leaf_traversals_after_damage") == 0, "steady path traversed source leaves")
    require(d.get("fork_events") == 2 and d.get("state_projection_events") == 2, "fork/projection count")
    require(d.get("superseded_rejections", 0) >= 2, "stale bindings not fenced")
    require(d.get("event_receipts") == 2, "receipt count")
    require(d.get("current_instances") == 100, "semantic population changed")
    require(d.get("original_models_intact") is True, "shared baseline models changed")
    require(d.get("all_models_intact") is True, "model integrity failed")
    require(d.get("atomicity_unsafe_reject_clean") is True, "unsafe rejection leaked live state")
    require(d.get("atomicity_retry_same_ids") is True, "rejected attempt consumed family/event ids")
    require(d.get("atomicity_alias_reject_clean") is True, "alias rejection leaked live state")
    require(d.get("atomicity_occupied_id_reject_clean") is True, "occupied-id rejection leaked live state")

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
    require(values[0][0] == values[1][0] == values[2][0], "raw payloads differ")
    h = digest(values[0][1])
    payload = {"schema":"fabric.r5_2.t15_exact_evidence.v1","status":"PASS","deterministic_hash":h,"result":values[0][1]}
    ns.out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("FABRIC_R5_2_T15_DETERMINISTIC_HASH=" + h)
    print("FABRIC_R5_2_T15_EVIDENCE=PASS")

if __name__ == "__main__":
    main()

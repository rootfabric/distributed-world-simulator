#!/usr/bin/env python3
from __future__ import annotations
import hashlib, json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MANIFEST = ROOT / "validation/fabric1_sync1/freeze-manifest.v1.json"
EXPECTED_INVARIANTS = [
    "CANONICAL_WORLD_IS_EXTERNAL_TRUTH",
    "FABRIC_AND_BAKE_ARE_DERIVED_DISCARDABLE_EXECUTION",
    "REPRESENTATION_TRANSITION_IS_NOT_CANONICAL_MUTATION",
    "PHYSICAL_STALE_NEVER_EXECUTES",
    "ONE_ACTIVE_PHYSICAL_OWNER_PER_REGION",
    "REDUCTION_MAY_FAIL_CLOSED_WITH_NO_SAFE_BAKE",
    "SAFETY_IS_INDEPENDENT_OF_COST",
    "HIDDEN_FAILURE_REQUIRES_CONSERVATIVE_REFINEMENT_GUARD",
    "LOCAL_CAUSAL_REFINEMENT_MUST_NOT_FORCE_GLOBAL_FULL",
    "RESTART_REBINDS_FROM_AUTHORITATIVE_CANONICAL_SOURCE",
    "EVENT_APPLICATION_IS_EXACTLY_ONCE",
    "GENERIC_COMPOSITION_MUST_NOT_REQUIRE_DEVICE_SPECIFIC_SOLVERS",
    "FRESH_PROCESS_REPLAY_MUST_BE_DETERMINISTIC",
]
FORBIDDEN_DEVICE_TOKENS = ("lamp", "motor", "pump", "gearbox", "generator")
GENERIC_RUNTIME_PATHS = [
    "scripts/research/fabric_bake0/fabric1_component_contract_v1.gd",
    "scripts/research/fabric_bake0/fabric1_generalized_composer_v1.gd",
    "scripts/research/fabric_bake0/fabric1_generalized_runtime_v1.gd",
]

def git_blob_sha(data: bytes) -> str:
    return hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest()

def fail(msg: str) -> None:
    print(f"FABRIC1-SYNC1 FREEZE VALIDATOR: FAIL: {msg}", file=sys.stderr)
    raise SystemExit(1)

def main() -> None:
    if not MANIFEST.is_file(): fail("manifest missing")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if manifest.get("schema") != "planet_simulator.fabric1_sync1_architecture_freeze.v1": fail("schema")
    if manifest.get("freeze_id") != "FABRIC1-SYNC1-R1": fail("freeze id")
    if manifest.get("status") not in ("CANDIDATE", "FROZEN"): fail("status")
    if manifest.get("architecture_invariants") != EXPECTED_INVARIANTS: fail("invariant set/order changed")
    predecessor = manifest.get("predecessor", {})
    if predecessor.get("final_head") != "1ccf3525ea8b9ffef28582b0232c28157d21a8b5": fail("FABRIC1 predecessor head")
    if predecessor.get("closure_hash") != "a652cfc238f5abc2574d5e2f664e578ab92f1ff1413d8706a4067c0dae4969a6": fail("FABRIC1 closure hash")
    if manifest.get("next_activation") != "BRIDGE-4_CANONICAL_WORLD_TO_FABRIC1": fail("next activation")
    if "COMPLEX4_REAL_WORLD_MACHINE_LAB" not in manifest.get("blocked_until_bridge4_closes", []): fail("COMPLEX4 gate")

    checked = 0
    for group in ("critical_git_blobs", "closure_evidence_blobs"):
        for rel, expected in manifest.get(group, {}).items():
            path = ROOT / rel
            if not path.is_file(): fail(f"missing {rel}")
            actual = git_blob_sha(path.read_bytes())
            if actual != expected: fail(f"blob identity mismatch {rel}: {actual} != {expected}")
            checked += 1

    for rel in GENERIC_RUNTIME_PATHS:
        text = (ROOT / rel).read_text(encoding="utf-8").lower()
        if "res://tests/" in text or "res://scripts/labs/" in text: fail(f"runtime depends on test/lab path: {rel}")
        for token in FORBIDDEN_DEVICE_TOKENS:
            if token in text: fail(f"device-specific token '{token}' leaked into generalized runtime: {rel}")

    canonical = json.dumps(manifest, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    digest = hashlib.sha256(canonical).hexdigest()
    print(f"FABRIC1-SYNC1 FREEZE VALIDATOR: PASS ({checked} local blob identities)")
    print(f"FABRIC1_SYNC1_MANIFEST_HASH={digest}")

if __name__ == "__main__":
    main()

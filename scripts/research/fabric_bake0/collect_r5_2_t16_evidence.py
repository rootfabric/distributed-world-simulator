#!/usr/bin/env python3
"""Strict T16 evidence oracle. Timing/RSS are deliberately outside identity."""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import re
from pathlib import Path

PREFIX = "FABRIC_R5_2_T16_RESULT="
PASS = "FABRIC R5.2 T16 NO SAFE BAKE: PASS (533 assertions)"
FATAL = re.compile(r"SCRIPT ERROR|Parse Error|Compile Error|Invalid call|Invalid access|ERROR:", re.I)
CASES = {
    "hidden_mode": ("THERMAL_STATE_NOT_IN_REDUCTION_MANIFOLD", "FULL"),
    "lossy_reconstruction": ("RECONSTRUCTION_NOT_EXACT", "FULL"),
    "missing_reconstruction": ("RECONSTRUCTION_UNAVAILABLE", "FULL"),
    "insufficient_observability": ("INSUFFICIENT_OBSERVABILITY", "FULL"),
    "hidden_event": ("UNRESOLVED_HIDDEN_EVENT", "FULL"),
    "unsafe_error_budget": ("UNSAFE_ERROR_ENVELOPE", "FULL"),
    "nonfinite_error_certificate": ("UNSAFE_ERROR_ENVELOPE", "FULL"),
    "near_critical_step": ("NEAR_CRITICAL_DYNAMICS", "FULL"),
    "unsupported_reduction_topology": ("THERMAL_PACK_LAYER_SYMMETRY_BROKEN", "FULL"),
    "stale_frontier": ("THERMAL_FILTER_RUNTIME_FRONTIER_MISMATCH", "FULL"),
    "source_mutation_stale_capsule": ("THERMAL_FILTER_RUNTIME_FRONTIER_MISMATCH", "FULL"),
    "corrupt_capsule": ("BAKE_CHECKSUM_MISMATCH", "FULL"),
    "physical_stale": ("THERMAL_FILTER_RUNTIME_ARTIFACT_NOT_READY", "FULL"),
    "cross_authority": ("AUTHORITY_ENVELOPE_CROSSED", "CANONICAL_HANDOFF_REQUIRED"),
    "authority_epoch_mismatch": ("T16_AUTHORITY_EPOCH_MISMATCH", "CANONICAL_HANDOFF_REQUIRED"),
    "canonical_source_mismatch": ("T16_CANONICAL_SOURCE_HASH_MISMATCH", "CANONICAL_HANDOFF_REQUIRED"),
    "missing_full_state": ("THERMAL_STATE_PROJECTOR_STATE_INVALID", "FULL_STEP_REFUSED"),
    "invalid_physical_state": ("THERMAL_STATE_PROJECTOR_STATE_INVALID", "FULL_STEP_REFUSED"),
    "compact_step_failure": ("T16_COMPACT_STEP_REFUSED", "COMPACT_STEP_REFUSED"),
    "singular_elimination": ("RANK_DEFICIENCY", "FULL_SOLVER_DIAGNOSTIC_REQUIRED"),
}
COUNTS = {"checks":533, "case_count":20, "source_cells":128, "compact_states":8,
          "positive_variants":8, "full_continuation_ticks":104,
          "fallback_source_cell_updates":1792, "full_events_observed":223}
REGRESSIONS = {
    "t15": "FABRIC R5.2 T15 LOCAL DAMAGE UNBAKE REBAKE: PASS (506 assertions)",
    "t14": "FABRIC R5.2 T14 OBSERVATION REFINEMENT: PASS (1208 assertions)",
    "t13-5": "FABRIC R5.2 T13.5 SHARED FAMILIES: PASS (777 assertions)",
    "t13": "FABRIC R5.2 T13 SHARED INSTANCES: PASS (1377 assertions)",
    "t12": "FABRIC R5.2 T12 SHIP MATRYOSHKA: PASS (8386 assertions)",
}

def require(ok: bool, reason: str) -> None:
    if not ok:
        raise ValueError(reason)

def digest(value: object) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()).hexdigest()

def unique_object(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate JSON key: " + key)
        result[key] = value
    return result

def strict_json(text: str) -> dict:
    def invalid_constant(value: str) -> None:
        raise ValueError("nonfinite JSON value: " + value)
    value = json.loads(text, parse_constant=invalid_constant, object_pairs_hook=unique_object)
    require(isinstance(value, dict), "result must be an object")
    return value

def validate_result(d: dict) -> None:
    require(d.get("schema") == "fabric.t16.result.v1" and d.get("failures") == [], "schema/runtime failure")
    for key, expected in COUNTS.items():
        require(type(d.get(key)) is int and d[key] == expected, "count mismatch: " + key)
    require(set(d.get("cases", {})) == set(CASES), "case matrix incomplete")
    for name, (reason, execution) in CASES.items():
        c = d["cases"][name]
        require(c.get("reason") == reason and c.get("execution") == execution, "wrong disposition: " + name)
        if name == "singular_elimination":
            require(c.get("artifact_empty") is True, "singular artifact escaped")
            continue
        require(c.get("source_preserved") is True and c.get("state_preserved") is True, "mutated inputs: " + name)
        compact = int(execution == "COMPACT_STEP_REFUSED")
        full = int(execution in ("FULL", "FULL_STEP_REFUSED"))
        for key, expected in (("compact_calls", compact), ("full_calls", full)):
            require(type(c.get(key)) is int and c[key] == expected, "executor count: " + name)
        require(type(c.get("candidate_calls")) is int and c["candidate_calls"] == int(execution != "CANONICAL_HANDOFF_REQUIRED"), "candidate count: " + name)
        expected_compiles = 0 if execution == "CANONICAL_HANDOFF_REQUIRED" or name in ("stale_frontier", "source_mutation_stale_capsule", "corrupt_capsule") else 1
        require(type(c.get("compile_calls")) is int and c["compile_calls"] == expected_compiles, "compiler count: " + name)
        if execution == "FULL":
            steps = 2 if name == "near_critical_step" else 1
            require(c.get("full_substeps") == steps and c.get("source_cell_updates") == steps * 128, "fake FULL work: " + name)
            for field in ("physical_trace_hash", "events_hash"):
                require(re.fullmatch(r"[0-9a-f]{64}", c.get(field, "")) is not None, "missing trace: " + name)
    require(re.fullmatch(r"[0-9a-f]{64}", d.get("positive_trace_hash", "")) is not None, "missing compact trace")
    for key, bound in (("max_energy_residual_j", 1e-6), ("max_positive_boundary_error_k", 1e-7)):
        v = d.get(key)
        require(type(v) in (int, float) and math.isfinite(v) and 0 <= v <= bound, "physical envelope: " + key)

def read_sample(path: Path) -> tuple[str, dict]:
    text = path.read_text(encoding="utf-8-sig", errors="strict")
    require(PASS in text and not FATAL.search(text), "sample failed: " + path.name)
    rows = [line[len(PREFIX):] for line in text.splitlines() if line.startswith(PREFIX)]
    require(len(rows) == 1, "result marker count")
    d = strict_json(rows[0])
    validate_result(d)
    return rows[0], d

def collect(root: Path, expected_hash: str | None = None) -> dict:
    samples = [read_sample(root / f"sample-{i}.log") for i in (1, 2, 3)]
    require(samples[0][0] == samples[1][0] == samples[2][0], "physical/result payloads differ")
    h = digest(samples[0][1])
    require(expected_hash is None or h == expected_hash, "cross-platform deterministic hash mismatch")
    for name, marker in REGRESSIONS.items():
        text = (root / f"{name}-regression.log").read_text(encoding="utf-8-sig")
        require(marker in text and not FATAL.search(text), "regression failed: " + name)
    for name in ("import", "parse"):
        require(not FATAL.search((root / f"{name}.log").read_text(encoding="utf-8-sig")), name + " fatal marker")
    before = (root / "identity-before.txt").read_text(encoding="utf-8-sig").splitlines()
    after = (root / "identity-after.txt").read_text(encoding="utf-8-sig").splitlines()
    require(before == after, "subject/engine moved during exact run")
    require(len(before) == 4 and re.fullmatch(r"HEAD=[0-9a-f]{40}", before[0]) is not None and re.fullmatch(r"TREE=[0-9a-f]{40}", before[1]) is not None, "identity missing")
    require(before[2] == "GODOT_VERSION=4.7.1.stable.double.custom_build.a13da4feb", "wrong engine version")
    require(before[3] in ("GODOT_SHA256=bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7", "GODOT_SHA256=3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5"), "wrong engine hash")
    return {"schema":"fabric.t16.exact_evidence.v1", "status":"IMPLEMENTER_EXACT_PASS", "identity":before,
            "deterministic_hash":h, "result":samples[0][1],
            "logs":{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.glob("*.log"))}}

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, required=True)
    ap.add_argument("--expected-hash")
    ns = ap.parse_args()
    evidence = collect(ns.root, ns.expected_hash)
    (ns.root / "evidence.json").write_text(json.dumps(evidence, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    print("FABRIC_R5_2_T16_DETERMINISTIC_HASH=" + evidence["deterministic_hash"])
    print("FABRIC_R5_2_T16_EVIDENCE=PASS")

if __name__ == "__main__":
    main()

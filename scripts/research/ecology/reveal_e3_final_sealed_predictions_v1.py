"""E3.FINAL sealed prediction reveal — post-freeze verification and comparison.

Runs ONLY after the unseen world program bytes are frozen (committed). Verifies
each sealed commitment digest against the out-of-repo plaintext, compares
predicted outcome classes and colonized-species ranges with observed results,
and emits reveal evidence. Digest mismatches fail hard; scientific divergence
is recorded as falsification evidence and never fails the run.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[3]
COMMITMENTS = ROOT / "config/ecology/accepted_inputs/e3_final/e3_final_sealed_prediction_commitments.v1.json"
ARTIFACT = ROOT / "validation/ecology/eco-evo3-e3-final-unseen-world-program.generated.json"
EVIDENCE = ROOT / "validation/ecology/eco-evo3-e3-final-sealed-reveal-evidence.json"

CLASS_MAP = {
    "NO_COLONIZATION_ALL": "NO_COLONIZATION_ALL_SPECIES",
    "MIXED_DROUGHT_GAIN": "MIXED_PARTIAL_COLONIZATION",
    "PARTIAL_REVERSAL": "MIXED_PARTIAL_COLONIZATION",
    "MIXED": "MIXED_PARTIAL_COLONIZATION",
    "PRESERVED_COLONIZED": "COLONIZED_ALL_SPECIES",
    "COLONIZED": "COLONIZED_ALL_SPECIES",
    "COLONIZED_ALL": "COLONIZED_ALL_SPECIES",
}


def canonical(v):
    return json.dumps(v, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def load_module(path: pathlib.Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> int:
    p = argparse.ArgumentParser(description="reveal E3.FINAL sealed predictions after program freeze")
    p.add_argument("--plaintext", type=pathlib.Path, required=True)
    args = p.parse_args()

    commitments_doc = json.loads(COMMITMENTS.read_bytes().decode("utf-8"))
    commitments = commitments_doc["commitments"]
    plaintext = json.loads(args.plaintext.read_bytes().decode("utf-8"))["predictions"]

    broken = [k for k in commitments if hashlib.sha256(canonical(plaintext[k])).hexdigest() != commitments[k]]
    if broken:
        raise SystemExit(f"SEALED COMMITMENT DIGEST MISMATCH: {sorted(broken)}")
    print(f"sealed commitment digests verified: {len(commitments)}/12")

    artifact = json.loads(ARTIFACT.read_bytes().decode("utf-8"))
    observed = {c["combination_id"]: c for c in artifact["combinations"]}
    records, divergences = [], []
    for key in sorted(commitments):
        pred = plaintext[key]
        combo = observed[key]
        obs_class = combo["observed_outcome_class"]
        exp_class = CLASS_MAP[pred["expected_outcome_class"]]
        lo, hi = pred["expected_colonized_species_range"]
        count = sum(1 for s in combo["species_outcomes"] if s["status"] == "COLONIZED")
        class_match = exp_class == obs_class
        range_match = lo <= count <= hi
        verdict = "CONFIRMED" if class_match and range_match else "FALSIFIED"
        if not class_match:
            divergences.append({"combination_id": key, "kind": "OUTCOME_CLASS", "predicted": pred["expected_outcome_class"], "observed": obs_class})
        if not range_match:
            divergences.append({"combination_id": key, "kind": "COLONIZED_RANGE", "predicted_range": [lo, hi], "observed_count": count})
        records.append({
            "combination_id": key,
            "commitment_digest": commitments[key],
            "predicted_outcome_class": pred["expected_outcome_class"],
            "mapped_expected_class": exp_class,
            "observed_outcome_class": obs_class,
            "predicted_colonized_species_range": [lo, hi],
            "observed_colonized_species_count": count,
            "verdict": verdict,
        })
    confirmed = sum(1 for r in records if r["verdict"] == "CONFIRMED")
    evidence = {
        "schema": "distributed_world_simulator.ecology.evo3_e3_final_sealed_reveal_evidence.v1",
        "checkpoint": "ECO.EVO3/E3.FINAL",
        "program_hash": artifact["planetary_ecology_program_hash"],
        "program_artifact_sha256": hashlib.sha256(ARTIFACT.read_bytes()).hexdigest(),
        "commitments_document_sha256": hashlib.sha256(COMMITMENTS.read_bytes()).hexdigest(),
        "plaintext_location": "OUTSIDE_REPOSITORY",
        "digest_verification": f"{len(commitments)}/12 PASS",
        "combinations_confirmed": confirmed,
        "combinations_falsified": len(records) - confirmed,
        "falsification_policy": "DIVERGENCE_RECORDED_AS_FALSIFICATION_EVIDENCE_NOT_FAILURE",
        "records": records,
        "divergences": divergences,
    }
    EVIDENCE.write_bytes(canonical(evidence) + b"\n")
    for r in records:
        print(f"reveal {r['combination_id']}: predicted={r['predicted_outcome_class']}[{r['predicted_colonized_species_range'][0]},{r['predicted_colonized_species_range'][1]}] observed={r['observed_outcome_class']}({r['observed_colonized_species_count']}) -> {r['verdict']}")
    print(f"confirmed={confirmed} falsified={len(records) - confirmed}")
    print(f"evidence: {EVIDENCE.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

"""Seal E3.FINAL outcome-class predictions BEFORE first challenge compilation.

Writes:
  - commitments file (committed): config/ecology/accepted_inputs/e3_final/e3_final_sealed_prediction_commitments.v1.json
    -> per-combination sha256 of the canonical prediction object (no plaintext);
  - plaintext store (NOT committed, revealed after program freeze):
    C:\\distributed-world-simulator\\e3-final-sealed\\predictions.v1.json

Predictions are model-informed falsifiable guesses derived from E3.8-observed
semantics (moisture collapse -> NO_COLONIZATION; thermal offset inert;
heavy disturbance -> reversals; drought-adapted traits gain on arid worlds).
"""
from __future__ import annotations
import hashlib, json, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / "config/ecology/accepted_inputs/e3_final/e3_final_sealed_prediction_commitments.v1.json"
PLAIN_DIR = pathlib.Path(r"C:\distributed-world-simulator\e3-final-sealed")

PLANETS = ("arid-basin-02", "oceanic-ridge-03", "polar-plateau-04", "volcanic-isles-05")
CATALOGS = ("baseline", "extended_r1", "mono_r1")

P = {}
for planet in PLANETS:
    for cat in CATALOGS:
        key = f"{planet}__{cat}"
        if planet == "arid-basin-02":
            if cat == "baseline":
                P[key] = {"expected_outcome_class": "NO_COLONIZATION_ALL", "expected_colonized_species_range": [0, 0],
                          "rationale": "moisture/4 equals E3.8 dry-family collapse; both baseline species water-limited"}
            elif cat == "extended_r1":
                P[key] = {"expected_outcome_class": "MIXED_DROUGHT_GAIN", "expected_colonized_species_range": [1, 4],
                          "rationale": "baseline species collapse as in dry family; drought-adapted grid species (water_preference<=0.30) gain establishment"}
            else:
                P[key] = {"expected_outcome_class": "NO_COLONIZATION_ALL", "expected_colonized_species_range": [0, 0],
                          "rationale": "mono catalog keeps only water-limited e22-beta"}
        elif planet == "oceanic-ridge-03":
            P[key] = {"expected_outcome_class": "PRESERVED_COLONIZED" if cat != "mono_r1" else "COLONIZED",
                      "expected_colonized_species_range": [1, 12] if cat == "extended_r1" else ([2, 2] if cat == "baseline" else [1, 1]),
                      "rationale": "wet x1.5 preserved in E3.8; reduced disturbance favors arrival; nutrient x0.6 assumed sub-threshold"}
        elif planet == "polar-plateau-04":
            P[key] = {"expected_outcome_class": "PRESERVED_COLONIZED" if cat != "mono_r1" else "COLONIZED",
                      "expected_colonized_species_range": [1, 12] if cat == "extended_r1" else ([2, 2] if cat == "baseline" else [1, 1]),
                      "rationale": "E3.8 cold -15C was inert (no thermal shortcut); -18C assumed still inert; light x0.7 and disturbance x1.4 assumed sub-threshold"}
        else:  # volcanic-isles-05
            if cat == "baseline":
                P[key] = {"expected_outcome_class": "PARTIAL_REVERSAL", "expected_colonized_species_range": [0, 1],
                          "rationale": "disturbance x2.2 exceeds E3.8 seasonal x2.0 that caused one reversal; expect >=1 species lost"}
            elif cat == "extended_r1":
                P[key] = {"expected_outcome_class": "MIXED", "expected_colonized_species_range": [1, 6],
                          "rationale": "disturbance-tolerant grid species may persist while sensitive ones reverse"}
            else:
                P[key] = {"expected_outcome_class": "PARTIAL_REVERSAL", "expected_colonized_species_range": [0, 1],
                          "rationale": "mono species exposed to heavy disturbance without portfolio buffering"}

def canonical(v):
    return json.dumps(v, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()

commitments = {}
for key in sorted(P):
    commitments[key] = hashlib.sha256(canonical(P[key])).hexdigest()

doc = {
    "schema": "distributed_world_simulator.ecology.evo3_e3_final_sealed_prediction_commitments.v1",
    "version": "1.0.0",
    "sealed_before_first_compilation": True,
    "commitment_algorithm": "SHA256_CANONICAL_JSON_SORTED_KEYS_V1 of the prediction object; plaintext revealed only after compiled programs are frozen",
    "combination_count": len(commitments),
    "commitments": commitments,
}
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_bytes(canonical(doc) + b"\n")
PLAIN_DIR.mkdir(parents=True, exist_ok=True)
(PLAIN_DIR / "predictions.v1.json").write_bytes(canonical({"schema": "e3.final.sealed.predictions.plaintext.v1", "predictions": dict(sorted(P.items()))}) + b"\n")
print("commitments:", len(commitments), "->", OUT.name, "sha256:", hashlib.sha256(OUT.read_bytes()).hexdigest())
print("plaintext sealed at:", PLAIN_DIR / "predictions.v1.json")

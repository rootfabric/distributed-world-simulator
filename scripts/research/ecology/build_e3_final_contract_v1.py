"""Builds and byte-freezes the E3.FINAL challenge contract (self-hashed)."""
from __future__ import annotations
import copy, hashlib, json, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / "config/ecology/eco-evo3-e3-final-unseen-world-challenge-contract.v1.json"
PKG = ROOT / "config/ecology/accepted_inputs/e3_final"

def canonical_bytes(v):
    return json.dumps(v, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()

def sha256_hex(raw):
    return hashlib.sha256(raw).hexdigest()

def git_blob_hex(raw):
    return hashlib.sha1(b"blob " + str(len(raw)).encode("ascii") + b"\0" + raw).hexdigest()

def object_hash(v, field):
    x = copy.deepcopy(v); x.pop(field, None); return sha256_hex(canonical_bytes(x))

def pin(rel):
    raw = (ROOT / rel).read_bytes()
    v = json.loads(raw.decode("utf-8"))
    return {"path": rel, "sha256": sha256_hex(raw), "git_blob": git_blob_hex(raw), "bytes": len(raw),
            "identity": v.get("snapshot_hash") or v.get("catalog_hash")}

PLANETS = {
    "arid-basin-02": {"index": "02", "transforms": [["soil_moisture_ppm", "mul", [250000, 1000000]], ["temperature_milli_c", "add", 8000], ["light_availability_ppm", "mul", [1200000, 1000000]]]},
    "oceanic-ridge-03": {"index": "03", "transforms": [["soil_moisture_ppm", "mul", [1500000, 1000000]], ["nutrient_availability_ppm", "mul", [600000, 1000000]], ["disturbance_pressure_ppm", "mul", [300000, 1000000]]]},
    "polar-plateau-04": {"index": "04", "transforms": [["temperature_milli_c", "add", -18000], ["light_availability_ppm", "mul", [700000, 1000000]], ["disturbance_pressure_ppm", "mul", [1400000, 1000000]]]},
    "volcanic-isles-05": {"index": "05", "transforms": [["nutrient_availability_ppm", "mul", [1600000, 1000000]], ["disturbance_pressure_ppm", "mul", [2200000, 1000000]], ["soil_moisture_ppm", "mul", [900000, 1000000]]]},
}

FORBIDDEN = ["canonical_binding_resolved", "production_binding_authorized", "canonical_species_declared", "canonical_time_ownership", "canonical_environment_ownership", "history_write_allowed", "forecast_authorized", "network_authority", "persistence_authority", "production_persistence_authority", "world_transaction_authority", "transaction_authority", "asset_scatter_truth", "xfer1_authority"]

c = {
    "schema": "distributed_world_simulator.ecology.evo3_e3_final_unseen_world_challenge_contract.v1",
    "version": "1.0.0",
    "name": "ECO EVO3 E3.FINAL Planetary Ecology Compiler Challenge",
    "checkpoint": "ECO.EVO3/E3.FINAL",
    "compiler_stage": "UNSEEN_WORLD_CHALLENGE",
    "status": "AUTHORIZED_PRECOMMIT_FROZEN",
    "revision": "E3-FINAL-PRECOMMIT-R1",
    "branch": "feature/eco-evolutionary-ecology",
    "authority": "RESEARCH_DERIVED_NON_AUTHORITATIVE",
    "research_only": True,
    "canonical_binding_resolved": False,
    "production_binding_authorized": False,
    "parent": {
        "accepted_control_head": "5fc9895",
        "e3_8_pr": 188,
        "e3_8_merge_commit": "847ea24b7e010e6db2d8221ed7c2706083edc6c4",
        "e3_8_matrix_artifact_sha256": "44de8474647483a6b18b6e5d88202358857f3b2b09171ae302b1c8497ea5b79c",
        "authorization": "Director mandate: autonomous execution through stage 4; E3.FINAL authorized by separate control commit on exact accepted E3.8 state",
    },
    "input_policy": {
        "raw_bytes_required": True,
        "artifact_sha256_required": True,
        "git_blob_required": True,
        "plain_parsed_json_authority_forbidden": True,
        "accepted_compiler_modification_forbidden": True,
        "catalog_retuning_forbidden": True,
        "post_reveal_prediction_tuning_forbidden": True,
        "precommit_before_first_compilation_required": True,
        "global_rng_allowed": False,
        "local_clock_allowed": False,
        "ambient_environment_allowed": False,
    },
    "precommit_inputs": {"planets": {}, "catalog_variants": {}, "baseline_catalog": None, "sealed_commitments": None},
    "unseen_planet_rule": "Byte-frozen multi-axis derivatives of the accepted alpha-01 snapshot under namespace eco-evo3-final/unseen/*; declared transforms are audit metadata, pins are authoritative",
    "catalog_variant_rule": "Variants validated by the UNMODIFIED accepted E3.4 catalog surface; entry checksums computed exclusively by imported accepted code",
    "reuse_policy": {
        "accepted_builders_reused_unmodified": True,
        "chain_scope": "E3.1 verified inputs -> E3.2 opportunity field -> E3.3 decomposition -> E3.4 causal core outcomes per (planet, catalog)",
        "fixture_pinned_stages_e3_5_e3_6_e3_7": "Represented by deterministic projection manifests derived from built artifacts; not recompiled because accepted wrappers are byte-frozen to the alpha-01 fixture",
    },
    "outcome_classes": ["COLONIZED", "NO_COLONIZATION"],
    "combination_outcome_classes": ["COLONIZED_ALL", "PRESERVED_COLONIZED", "MIXED", "MIXED_DROUGHT_GAIN", "PARTIAL_REVERSAL", "NO_COLONIZATION_ALL", "COLONIZED"],
    "sealed_predictions": {
        "verification": "Every combination prediction digest MUST be recomputed from the revealed plaintext after program freeze; mismatch between committed digest and revealed plaintext is a HIGH finding",
        "falsification_policy": "Prediction/outcome divergence is recorded as falsification evidence and does not fail compilation",
    },
    "execution_envelope": {"wall_time_seconds_max": 60, "peak_memory_mb_max": 512, "artifact_bytes_max": 10485760},
    "required_invariants": {
        "twelve_combinations_exact": True,
        "same_input_same_program_bytes_required": True,
        "fresh_process_replay_required": True,
        "null_outcome_valid": True,
        "outcome_diversity_present": True,
        "sealed_commitments_verified_after_freeze": True,
        "envelope_within_ceiling_required": True,
    },
    "forbidden_promotions": {k: False for k in FORBIDDEN},
    "output_contract": {
        "schema": "distributed_world_simulator.ecology.evo3_e3_final_unseen_world_program.v1",
        "research_derived_non_authoritative": True,
        "individual_entity_truth_forbidden": True,
        "canonical_species_declared_forbidden": True,
        "asset_scatter_truth_forbidden": True,
        "xfer1_authority_forbidden": True,
        "production_persistence_authority_forbidden": True,
    },
    "next_gate": "IMPLEMENTATION -> CLOSURE -> POST_BUILD_CRITIQUE -> INDEPENDENT_REVIEWER -> VERIFIER -> DIRECTOR_ACCEPTANCE",
    "contract_hash_algorithm": "SHA256_CANONICAL_JSON_SORTED_KEYS_V1",
}

base_rel = "config/ecology/accepted_inputs/evo2_full_persisted_species_catalog.e3_4.v1.json"
c["precommit_inputs"]["baseline_catalog"] = pin(base_rel)
for slug, spec in PLANETS.items():
    rel = f"config/ecology/accepted_inputs/e3_final/e3_final_unseen_planet_field_snapshot.{slug}.v1.json"
    entry = pin(rel)
    entry["declared_transforms"] = spec["transforms"]
    entry["planet_index"] = spec["index"]
    c["precommit_inputs"]["planets"][slug] = entry
for label in ("extended_r1", "mono_r1"):
    rel = f"config/ecology/accepted_inputs/e3_final/evo2_persisted_species_catalog.e3_final_{label}.v1.json"
    c["precommit_inputs"]["catalog_variants"][label] = pin(rel)
c["precommit_inputs"]["sealed_commitments"] = pin("config/ecology/accepted_inputs/e3_final/e3_final_sealed_prediction_commitments.v1.json")

c["contract_hash"] = object_hash(c, "contract_hash")
OUT.write_bytes(canonical_bytes(c) + b"\n")
print("contract written:", OUT.name)
print("bytes:", OUT.stat().st_size, "sha256:", sha256_hex(OUT.read_bytes()))
print("contract_hash:", c["contract_hash"])

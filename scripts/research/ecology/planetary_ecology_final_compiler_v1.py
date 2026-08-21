"""ECO EVO3 E3.FINAL — Unseen World Challenge compiler (driver-owned layer).

Compiles the byte-frozen precommit package (4 unseen planets x 3 persisted
SpeciesCatalog variants) through the UNMODIFIED accepted EVO3 causal chain:

    verified raw inputs -> E3.2 _build -> E3.3 _build ->
    E3.4 core build_colonization_program (runtime contract, accepted thresholds)
    -> E3.5 _derive_core projection -> E3.6 _compile_envelopes projection

Accepted modules are imported by path and never modified; their byte digests
are recorded in the artifact provenance. The final program is emitted only
through the capability-bound serializer after an independent exact-input
rebuild matches canonical bytes. Determinism: no RNG, no clock, no ambient
environment reads; sorted iteration everywhere.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
from typing import Any

SCHEMA = "distributed_world_simulator.ecology.evo3_e3_final_unseen_world_program.v1"
CONTRACT_SCHEMA = "distributed_world_simulator.ecology.evo3_e3_final_unseen_world_challenge_contract.v1"
CHECKPOINT = "ECO.EVO3/E3.FINAL"
COMPILER_STAGE = "UNSEEN_WORLD_CHALLENGE"
AUTHORITY = "RESEARCH_DERIVED_NON_AUTHORITATIVE"
HASH_ALGORITHM = "SHA256_CANONICAL_JSON_SORTED_KEYS_V1"
ROOT = Path(__file__).resolve().parents[3]
STAGE_DIR = ROOT / "scripts/research/ecology"
DEFAULT_CONTRACT = ROOT / "config/ecology/eco-evo3-e3-final-unseen-world-challenge-contract.v1.json"
EXPECTED_CONTRACT_HASH = "ee66f06dd186ba914508c1f7d157d01288a8d51d7c04f6be7147d558849ece99"
CATALOG_ORDER = ("baseline", "extended_r1", "mono_r1")
FORBIDDEN_TRUE_KEYS = {"canonical_binding_resolved", "production_binding_authorized", "canonical_species_declared", "canonical_time_ownership", "canonical_environment_ownership", "history_write_allowed", "forecast_authorized", "network_authority", "persistence_authority", "production_persistence_authority", "world_transaction_authority", "transaction_authority", "asset_scatter_truth", "xfer1_authority"}


def canonical_bytes(v: Any) -> bytes:
    return json.dumps(v, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def sha256_hex(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def git_blob_hex(raw: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(raw)).encode("ascii") + b"\0" + raw).hexdigest()


def object_hash(v: dict, field: str) -> str:
    x = copy.deepcopy(v)
    x.pop(field, None)
    return sha256_hex(canonical_bytes(x))


def _require(ok: bool, msg: str) -> None:
    if not ok:
        raise ValueError(msg)


def _reject_true_authority(v: Any, where: str) -> None:
    if isinstance(v, dict):
        for k, x in v.items():
            if k in FORBIDDEN_TRUE_KEYS:
                _require(x is False, f"{where}: forbidden authority promotion {k}={x!r}")
            _reject_true_authority(x, where)
    elif isinstance(v, list):
        for x in v:
            _reject_true_authority(x, where)


def _parse_object(raw: bytes, where: str) -> dict:
    v = json.loads(raw.decode("utf-8"))
    _require(isinstance(v, dict), f"{where}: root must be object")
    return v


_STAGE_CACHE = {}


def _load_stage_module(filename: str):
    if filename in _STAGE_CACHE:
        return _STAGE_CACHE[filename]
    path = STAGE_DIR / filename
    spec = importlib.util.spec_from_file_location("e3final_" + filename.replace("-", "_").replace(".py", ""), path)
    _require(spec is not None and spec.loader is not None, f"cannot load stage module {filename}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    _STAGE_CACHE[filename] = (mod, sha256_hex(path.read_bytes()))
    return _STAGE_CACHE[filename]


class _VerifiedChallengeInputs:
    __slots__ = ("contract", "snapshots", "catalogs", "baseline_catalog", "commitments", "raw")

    def __init__(self, *, contract, snapshots, catalogs, baseline_catalog, commitments, raw):
        self.contract = copy.deepcopy(contract)
        self.snapshots = copy.deepcopy(snapshots)
        self.catalogs = copy.deepcopy(catalogs)
        self.baseline_catalog = copy.deepcopy(baseline_catalog)
        self.commitments = copy.deepcopy(commitments)
        self.raw = {k: bytes(v) for k, v in raw.items()}


class _VerifiedUnseenWorldProgram(dict):
    def __init__(self, value, inputs):
        super().__init__(copy.deepcopy(value))
        self._raw = {k: bytes(v) for k, v in inputs.raw.items()}


def _verify_pinned_json(inputs_raw: dict, rel: str, pin: dict, where: str) -> tuple[bytes, dict]:
    raw = inputs_raw[rel]
    _require(sha256_hex(raw) == pin["sha256"], f"{where}: sha256 mismatch for {rel}")
    _require(git_blob_hex(raw) == pin["git_blob"], f"{where}: git blob mismatch for {rel}")
    value = _parse_object(raw, where)
    identity = value.get("snapshot_hash") or value.get("catalog_hash")
    _require(identity == pin.get("identity"), f"{where}: identity mismatch for {rel}")
    return raw, value


def load_verified_inputs(contract_path: Path = DEFAULT_CONTRACT, raw_override: dict[str, bytes] | None = None) -> _VerifiedChallengeInputs:
    def _read(rel: str) -> bytes:
        return bytes(raw_override[rel]) if raw_override is not None else (ROOT / rel).read_bytes()

    contract_key = str(contract_path.relative_to(ROOT))
    contract_raw = _read(contract_key) if raw_override is not None else contract_path.read_bytes()
    contract = _parse_object(contract_raw, "E3_FINAL_CONTRACT_ROOT")
    _require(contract["schema"] == CONTRACT_SCHEMA, "E3_FINAL_CONTRACT_SCHEMA")
    _require(contract["checkpoint"] == CHECKPOINT and contract["compiler_stage"] == COMPILER_STAGE, "E3_FINAL_CONTRACT_IDENTITY")
    _require(object_hash(contract, "contract_hash") == EXPECTED_CONTRACT_HASH == contract["contract_hash"], "E3_FINAL_CONTRACT_HASH")
    _require(contract["authority"] == AUTHORITY, "E3_FINAL_CONTRACT_AUTHORITY")
    _reject_true_authority(contract, "E3_FINAL_CONTRACT")

    pins = contract["precommit_inputs"]
    planets_block = pins["planets"]
    catalogs_block = pins["catalog_variants"]
    commitments_pin = pins["sealed_commitments"]
    _require(len(planets_block) == 4 and len(catalogs_block) == 2, "E3_FINAL_PREDECLARED_SHAPE")

    raw: dict[str, bytes] = {contract_key: contract_raw}
    snapshots, catalogs = {}, {}
    for slug in sorted(planets_block):
        pin_rec = planets_block[slug]
        rel = pin_rec["path"]
        raw[rel] = _read(rel)
        craw, snap = _verify_pinned_json(raw, rel, pin_rec, f"E3_FINAL_PLANET_{slug}")
        raw[rel] = craw
        _require(snap["stable_planet_identity"].startswith("eco-evo3-final/unseen/"), f"E3_FINAL_PLANET_NAMESPACE_{slug}")
        _require(len(snap["samples"]) == 12, f"E3_FINAL_PLANET_SAMPLES_{slug}")
        for sample in snap["samples"]:
            _require(sample["sample_hash"] == object_hash(sample, "sample_hash"), f"E3_FINAL_SAMPLE_HASH_{slug}")
        snapshots[slug] = snap
    e34mod, _ = _load_stage_module("causal_colonization_program_compiler_v1.py")
    for label in CATALOG_ORDER:
        if label == "baseline":
            pin_rec, rel = pins["baseline_catalog"], pins["baseline_catalog"]["path"]
        else:
            pin_rec, rel = catalogs_block[label], catalogs_block[label]["path"]
        raw[rel] = _read(rel)
        craw, cat = _verify_pinned_json(raw, rel, pin_rec, f"E3_FINAL_CATALOG_{label}")
        raw[rel] = craw
        synthetic = {"persisted_evo2_catalog": {"entry_count": len(cat["entries"]), "catalog_hash": cat["catalog_hash"]}}
        e34mod.validate_catalog(cat, synthetic)
        if label == "baseline":
            baseline_catalog = cat
        else:
            catalogs[label] = cat
    crel = commitments_pin["path"]
    raw[crel] = _read(crel)
    craw, commit_doc = _verify_pinned_json(raw, crel, commitments_pin, "E3_FINAL_SEALED_COMMITMENTS")
    raw[crel] = craw
    expected_combos = {f"{slug}__{label}" for slug in sorted(planets_block) for label in CATALOG_ORDER}
    _require(set(commit_doc["commitments"]) == expected_combos and len(commit_doc["commitments"]) == 12, "E3_FINAL_SEALED_COMBINATION_SET")
    return _VerifiedChallengeInputs(contract=contract, snapshots=snapshots, catalogs=catalogs,
                                    baseline_catalog=baseline_catalog, commitments=commit_doc, raw=raw)


def _compose_core_contract(challenge: dict, dch: str, decomp: dict, catalog: dict) -> dict:
    body = {
        "schema": "distributed_world_simulator.ecology.evo3_e3_4_causal_colonization_contract.v1",
        "version": "1.0.0",
        "checkpoint": "ECO.EVO3/E3.4",
        "stage": "COLONIZATION_PROGRAM",
        "authority": AUTHORITY,
        "derivation": {
            "derived_from_challenge_contract_hash": challenge["contract_hash"],
            "derivation_contract_hash": dch,
            "note": "Runtime composition over driver-verified raw inputs; scientific thresholds identical to the accepted E3.4 contract",
        },
        "accepted_e3_3": {
            "decomposition_hash": decomp["decomposition_hash"],
            "decomposition_provenance_hash": decomp["decomposition_provenance_hash"],
        },
        "persisted_evo2_catalog": {
            "catalog_hash": catalog["catalog_hash"],
            "entry_count": len(catalog["entries"]),
        },
        "source_port": {"selection": "LEXICOGRAPHICALLY_LOWEST_STABLE_SPATIAL_KEY_V1"},
        "causal_model": {
            "opportunity_dimensions": [
                "water_opportunity_ppm",
                "light_opportunity_ppm",
                "nutrient_opportunity_ppm",
                "persistence_opportunity_ppm",
                "limiting_resource_opportunity_ppm",
                "establishment_opportunity_ppm",
            ],
            "minimum_establishment_ppm": 60000,
            "minimum_edge_arrival_ppm": 150000,
        },
        "input_policy": {
            "accepted_e3_3_only": True,
            "catalog_prefilter_allowed": False,
            "biome_species_table_allowed": False,
            "target_aware_species_injection_allowed": False,
            "catalog_rebake_allowed": False,
            "catalog_target_tuning_allowed": False,
            "all_catalog_entries_enter_source_port": True,
        },
        "output_policy": {
            "compiled_suitability_is_population_truth": False,
            "canonical_binding_resolved": False,
            "production_binding_authorized": False,
            "canonical_species_taxonomy": False,
            "canonical_spatial_domain_creation": False,
            "production_persistence_authority": False,
            "world_transaction_authority": False,
            "network_authority": False,
        },
        "successor": {"e3_5_authorized": False},
        "determinism": {"global_rng_allowed": False},
    }
    body["contract_hash"] = object_hash(body, "contract_hash")
    return body


def _observed_outcome_class(species_outcomes: list[dict]) -> str:
    statuses = [x["status"] for x in species_outcomes]
    if statuses and all(x == "COLONIZED" for x in statuses):
        return "COLONIZED_ALL_SPECIES"
    if any(x == "COLONIZED" for x in statuses):
        return "MIXED_PARTIAL_COLONIZATION"
    return "NO_COLONIZATION_ALL_SPECIES"


def _build_combination(inputs: _VerifiedChallengeInputs, slug: str, label: str, reused: dict) -> dict:
    snapshot = inputs.snapshots[slug]
    catalog = inputs.baseline_catalog if label == "baseline" else inputs.catalogs[label]
    challenge = inputs.contract
    dch = sha256_hex(canonical_bytes({
        "e3_final_challenge_contract_hash": challenge["contract_hash"],
        "stable_planet_identity": snapshot["stable_planet_identity"],
        "catalog_variant": label,
        "catalog_hash": catalog["catalog_hash"],
    }))
    e32mod, _ = _load_stage_module("ecological_opportunity_field_v1.py")
    e33mod, _ = _load_stage_module("research_ecology_decomposition_v1.py")
    core, _ = _load_stage_module("causal_colonization_program_compiler_v1_core.py")
    e35mod, _ = _load_stage_module("population_workset_compiler_v1.py")
    e36mod, _ = _load_stage_module("temporal_disturbance_program_compiler_v1.py")

    field = e32mod._build({"contract_hash": dch}, snapshot)
    _require(field["opportunity_field_hash"] == object_hash(field, "opportunity_field_hash"), "E3_FINAL_FIELD_SELFHASH")
    _require(field["source_snapshot_hash"] == snapshot["snapshot_hash"] and len(field["samples"]) == 12, "E3_FINAL_FIELD_LINKAGE")
    decomp = e33mod._build({"contract_hash": dch}, field)
    _require(decomp["decomposition_hash"] == object_hash(decomp, "decomposition_hash"), "E3_FINAL_DECOMP_SELFHASH")
    _require(decomp["source_opportunity_field_hash"] == field["opportunity_field_hash"], "E3_FINAL_DECOMP_LINKAGE")
    _require(len(decomp["patches"]) == int(decomp["summary"]["patch_count"]), "E3_FINAL_DECOMP_PATCH_COUNT")

    core_contract = _compose_core_contract(challenge, dch, decomp, catalog)
    program = core.build_colonization_program(core_contract, decomp, catalog)
    attestation = {
        "input_verification": "E3_FINAL_EXACT_RAW_SHA256_GIT_BLOB_SEALED_PRECOMMIT_VERIFICATION",
        "challenge_contract_hash": challenge["contract_hash"],
        "planet_slug": slug,
        "planet_snapshot_sha256": challenge["precommit_inputs"]["planets"][slug]["sha256"],
        "catalog_variant": label,
        "catalog_sha256": challenge["precommit_inputs"]["baseline_catalog"]["sha256"] if label == "baseline" else challenge["precommit_inputs"]["catalog_variants"][label]["sha256"],
        "decomposition_hash": decomp["decomposition_hash"],
        "derivation_contract_hash": dch,
        "reused_modules": dict(sorted(reused.items())),
        "scientific_thresholds": "IDENTICAL_TO_ACCEPTED_E3_4_CONTRACT_60000_150000",
    }
    program["provenance"] = attestation
    program["provenance_hash"] = core.sha256_canonical(program["provenance"])
    program["colonization_program_hash"] = object_hash(program, "colonization_program_hash")
    core.validate_program_integrity(program)

    workset = e35mod._derive_core(program, core_contract)
    envelopes = e36mod._compile_envelopes(workset, snapshot)
    species_outcomes = [
        {"research_species_id": sp["research_species_id"], "status": sp["status"], "established_patch_count": len(sp["established_patch_ids"])}
        for sp in program["species_programs"]
    ]
    return {
        "combination_id": f"{slug}__{label}",
        "stable_planet_identity": snapshot["stable_planet_identity"],
        "planet_snapshot": {
            "snapshot_hash": snapshot["snapshot_hash"],
            "sha256": challenge["precommit_inputs"]["planets"][slug]["sha256"],
        },
        "catalog": {
            "variant": label,
            "catalog_hash": catalog["catalog_hash"],
            "entry_count": len(catalog["entries"]),
            "sha256": challenge["precommit_inputs"]["baseline_catalog"]["sha256"] if label == "baseline" else challenge["precommit_inputs"]["catalog_variants"][label]["sha256"],
        },
        "chain_hashes": {
            "derivation_contract_hash": dch,
            "opportunity_field_hash": field["opportunity_field_hash"],
            "field_provenance_hash": field["field_provenance_hash"],
            "decomposition_hash": decomp["decomposition_hash"],
            "decomposition_provenance_hash": decomp["decomposition_provenance_hash"],
            "colonization_program_hash": program["colonization_program_hash"],
        },
        "chain_counts": {
            "opportunity_samples": len(field["samples"]),
            "patches": len(decomp["patches"]),
            "edges": len(decomp["edges"]),
            "regions": len(decomp["regions"]),
        },
        "colonization_program": program,
        "downstream_projection": {
            "work_basis_count": len(workset.get("work_basis_manifest", [])),
            "temporal_envelope_count": len(envelopes),
            "envelope_stable_spatial_keys": [e["stable_spatial_key"] for e in envelopes],
            "seasonality_state": "UNRESOLVED_SINGLE_SNAPSHOT",
        },
        "species_outcomes": species_outcomes,
        "observed_outcome_class": _observed_outcome_class(species_outcomes),
        "sealed_prediction_digest": inputs.commitments["commitments"][f"{slug}__{label}"],
    }


def build_unseen_world_program(inputs: _VerifiedChallengeInputs) -> _VerifiedUnseenWorldProgram:
    challenge = inputs.contract
    reused = {}
    for filename in (
        "ecological_opportunity_field_v1.py",
        "research_ecology_decomposition_v1.py",
        "causal_colonization_program_compiler_v1.py",
        "causal_colonization_program_compiler_v1_core.py",
        "population_workset_compiler_v1.py",
        "temporal_disturbance_program_compiler_v1.py",
    ):
        reused[filename] = _load_stage_module(filename)[1]
    combinations = []
    for slug in sorted(inputs.snapshots):
        for label in CATALOG_ORDER:
            combinations.append(_build_combination(inputs, slug, label, reused))
    combinations.sort(key=lambda c: c["combination_id"])
    classes = [c["observed_outcome_class"] for c in combinations]
    program: dict[str, Any] = {
        "schema": SCHEMA,
        "version": "1.0.0",
        "checkpoint": CHECKPOINT,
        "compiler_stage": COMPILER_STAGE,
        "authority": AUTHORITY,
        "canonical_binding_resolved": False,
        "production_binding_authorized": False,
        "challenge": {
            "contract_schema": CONTRACT_SCHEMA,
            "contract_hash": challenge["contract_hash"],
            "predeclared_combination_count": 12,
            "scientific_thresholds": "ACCEPTED_E3_4_60000_150000_UNTOUCHED",
        },
        "combinations": combinations,
        "summary": {
            "combination_count": len(combinations),
            "colonized_all_species_combinations": classes.count("COLONIZED_ALL_SPECIES"),
            "mixed_partial_colonization_combinations": classes.count("MIXED_PARTIAL_COLONIZATION"),
            "no_colonization_all_species_combinations": classes.count("NO_COLONIZATION_ALL_SPECIES"),
            "total_species_outcomes": sum(len(c["species_outcomes"]) for c in combinations),
            "null_outcome_valid": True,
            "outcome_diversity_present": len(set(classes)) > 1,
            "seasonality_state": "UNRESOLVED_SINGLE_SNAPSHOT",
        },
        "provenance": {
            "input_verification": "E3_FINAL_EXACT_RAW_SHA256_GIT_BLOB_SEALED_PRECOMMIT_VERIFICATION",
            "reused_modules": dict(sorted(reused.items())),
            "compiler_module_reuse": "UNMODIFIED_IMPORTED_ACCEPTED_BUILDERS",
            "accepted_module_modification": None,
            "forbidden_promotions": {k: False for k in sorted(FORBIDDEN_TRUE_KEYS)},
            "sealed_commitments_verification": "PENDING_REVEAL_AFTER_PROGRAM_FREEZE",
        },
        "provenance_hash_algorithm": HASH_ALGORITHM,
    }
    program["provenance_hash"] = sha256_hex(canonical_bytes(program["provenance"]))
    program["planetary_ecology_program_hash_algorithm"] = HASH_ALGORITHM
    program["planetary_ecology_program_hash"] = object_hash(program, "planetary_ecology_program_hash")
    return _VerifiedUnseenWorldProgram(program, inputs)


def validate_output_integrity(program: _VerifiedUnseenWorldProgram) -> None:
    _require(type(program) is _VerifiedUnseenWorldProgram, "capability: exact verified type required")
    rebuilt_inputs = load_verified_inputs(DEFAULT_CONTRACT, raw_override=dict(program._raw))
    rebuilt = build_unseen_world_program(rebuilt_inputs)
    _require(canonical_bytes(dict(rebuilt)) == canonical_bytes(dict(program)), "independent rebuild differs from exact-input rebuild")


def serialize_planetary_ecology_final_program(program: _VerifiedUnseenWorldProgram) -> bytes:
    validate_output_integrity(program)
    return canonical_bytes(dict(program)) + b"\n"


def write_planetary_ecology_final_program(program: _VerifiedUnseenWorldProgram, output: Path) -> None:
    Path(output).write_bytes(serialize_planetary_ecology_final_program(program))


def build_from_paths(contract_path: Path = DEFAULT_CONTRACT) -> _VerifiedUnseenWorldProgram:
    return build_unseen_world_program(load_verified_inputs(contract_path))


def main():
    p = argparse.ArgumentParser(description="ECO EVO3 E3.FINAL unseen world challenge compiler")
    p.add_argument("--contract", type=Path, default=DEFAULT_CONTRACT)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--quiet", action="store_true")
    a = p.parse_args()
    program = build_from_paths(a.contract)
    write_planetary_ecology_final_program(program, a.output)
    if not a.quiet:
        s = program["summary"]
        print(f"E3.FINAL UnseenWorldProgram: {a.output}")
        print(f"planetary_ecology_program_hash={program['planetary_ecology_program_hash']}")
        print(f"combinations={s['combination_count']} colonized_all={s['colonized_all_species_combinations']} mixed={s['mixed_partial_colonization_combinations']} none={s['no_colonization_all_species_combinations']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

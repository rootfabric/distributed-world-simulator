from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
from typing import Any, Dict, Iterable, Mapping

SCHEMA = "distributed_world_simulator.ecology.evo3_e3_7_planet_ecology_program.v1"
CHECKPOINT = "ECO.EVO3/E3.7"
COMPILER_STAGE = "PLANET_COMPILATION"
AUTHORITY = "RESEARCH_DERIVED_NON_AUTHORITATIVE"
HASH_ALGORITHM = "SHA256_CANONICAL_JSON_SORTED_KEYS_V1"

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_CONTRACT = ROOT / "config/ecology/eco-evo3-e3-7-planet-compilation-contract.v1.json"
DEFAULT_BINDING = ROOT / "config/ecology/eco-evo3-e3-7-inputs.binding.v1.json"

EXPECTED_CONTRACT_HASH = "c2d0eec22d554cd6ec202a99c38c19609ad8d33ecb388bf598fe0d82b28483a1"
EXPECTED_BINDING_HASH = "a2b53bd002120a5dc4367b4550193d2cd6282f5e68154c0479b3ac1ab7fac263"
EXPECTED_CONTROL_HEAD = "c9f0b0becb3d2494097d946202788b9d1aa292f4"
EXPECTED_E3_6_MERGE = "b7c279ec60a335b91924b3f1f6a0df6ac4f61d1d"
EXPECTED_PLANET = "eco-evo3-fixture/planet-alpha-01"
EXPECTED_TIME_KEY = "tf-fixture/planet-alpha/t000180"
EXPECTED_CATALOG_HASH = "5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219"
EXPECTED_E3_3_HASH = "9736ec70f844c930f8e160a4f08ae8e0aae1cce6f73fbf106499bea15b15a51a"
EXPECTED_E3_4_HASH = "6f0b1cbe134f6b77825f66b356624975cc84e88f08c9aaba789f24c7d1cba4e6"
EXPECTED_E3_5_HASH = "b8f30e129c0f714ebc937cdac6869e63223d8d72172cecb68dd049f604557ff5"
EXPECTED_E3_6_HASH = "a2fcb297872c8d7706b854a2cb01bdd25744296f3f94921ab7613c0de8e46908"

ROOT_SELF_HASH_FIELDS = {
    "e3_1": "snapshot_hash",
    "e3_2": "opportunity_field_hash",
    "e3_3": "decomposition_hash",
    "e3_4": "colonization_program_hash",
    "e3_5": "population_workset_hash",
    "e3_6": "temporal_program_hash",
}
FORBIDDEN_TRUE_KEYS = {
    "canonical_binding_resolved",
    "production_binding_authorized",
    "canonical_species_declared",
    "canonical_time_ownership",
    "canonical_environment_ownership",
    "history_write_allowed",
    "forecast_authorized",
    "network_authority",
    "persistence_authority",
    "production_persistence_authority",
    "world_transaction_authority",
    "transaction_authority",
    "asset_scatter_truth",
    "xfer1_authority",
}


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")


def serialized_bytes(value: Any) -> bytes:
    return canonical_bytes(value) + b"\n"


def sha256_hex(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def git_blob_hex(raw: bytes) -> str:
    header = b"blob " + str(len(raw)).encode("ascii") + b"\0"
    return hashlib.sha1(header + raw).hexdigest()


def object_hash(value: Dict[str, Any], hash_field: str) -> str:
    payload = copy.deepcopy(value)
    payload.pop(hash_field, None)
    return sha256_hex(canonical_bytes(payload))


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def _parse_object(raw: bytes, where: str) -> Dict[str, Any]:
    value = json.loads(raw.decode("utf-8"))
    _require(isinstance(value, dict), f"{where}: root must be object")
    return value


def _exact_keys(value: Dict[str, Any], expected: Iterable[str], where: str) -> None:
    expected_set = set(expected)
    actual = set(value)
    _require(
        actual == expected_set,
        f"{where}: keys mismatch missing={sorted(expected_set-actual)} extra={sorted(actual-expected_set)}",
    )


def _contains_scalar(value: Any, key: str, expected: Any) -> bool:
    if isinstance(value, dict):
        if value.get(key) == expected:
            return True
        return any(_contains_scalar(v, key, expected) for v in value.values())
    if isinstance(value, list):
        return any(_contains_scalar(v, key, expected) for v in value)
    return False


def _reject_true_authority(value: Any, where: str) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if key in FORBIDDEN_TRUE_KEYS:
                _require(child is False, f"{where}: forbidden authority promotion {key}={child!r}")
            _reject_true_authority(child, where)
    elif isinstance(value, list):
        for child in value:
            _reject_true_authority(child, where)


class _VerifiedInputs:
    __slots__ = ("contract", "binding", "values", "raw")

    def __init__(
        self,
        *,
        contract: Dict[str, Any],
        binding: Dict[str, Any],
        values: Dict[str, Dict[str, Any]],
        raw: Dict[str, bytes],
    ) -> None:
        self.contract = copy.deepcopy(contract)
        self.binding = copy.deepcopy(binding)
        self.values = copy.deepcopy(values)
        self.raw = {k: bytes(v) for k, v in raw.items()}


class _VerifiedPlanetEcologyProgram(dict):
    def __init__(self, value: Dict[str, Any], inputs: _VerifiedInputs) -> None:
        super().__init__(copy.deepcopy(value))
        self._raw = {k: bytes(v) for k, v in inputs.raw.items()}


def _validate_contract(contract: Dict[str, Any]) -> None:
    _require(contract.get("schema") == "distributed_world_simulator.ecology.evo3_e3_7_planet_compilation_contract.v1", "contract schema")
    _require(contract.get("checkpoint") == CHECKPOINT, "contract checkpoint")
    _require(contract.get("compiler_stage") == COMPILER_STAGE, "contract stage")
    _require(contract.get("authority") == AUTHORITY, "contract authority")
    _require(contract.get("canonical_binding_resolved") is False, "contract canonical promotion")
    _require(contract.get("production_binding_authorized") is False, "contract production promotion")
    _require(contract.get("contract_hash") == EXPECTED_CONTRACT_HASH, "contract expected hash")
    _require(object_hash(contract, "contract_hash") == EXPECTED_CONTRACT_HASH, "contract self hash")

    policy = contract.get("input_policy", {})
    _require(policy.get("immediate_ecology_predecessor") == "EXACT_ACCEPTED_E3_6_TEMPORAL_PROGRAM", "E3.6 predecessor")
    _require(policy.get("accepted_chain_required") == ["E3.1", "E3.2", "E3.3", "E3.4", "E3.5", "E3.6"], "accepted chain")
    for key in (
        "persisted_evo2_species_catalog_required",
        "raw_bytes_required",
        "git_blob_required",
        "artifact_sha256_required",
        "semantic_identity_recompute_required_where_defined",
        "plain_parsed_json_authority_forbidden",
        "candidate_alias_authority_forbidden",
        "stage_rebake_or_retuning_forbidden",
    ):
        _require(policy.get(key) is True, f"contract input policy {key}")

    output = contract.get("output_policy", {})
    _require(output.get("program_type") == "PlanetEcologyProgram", "program type")
    _require(output.get("research_derived_non_authoritative") is True, "research authority")
    for key in (
        "canonical_foundation_ownership",
        "canonical_species_taxonomy",
        "individual_entity_truth",
        "production_persistence_authority",
        "world_transaction_authority",
        "network_authority",
        "asset_scatter_truth",
        "xfer1_authority",
    ):
        _require(output.get(key) is False, f"contract output authority {key}")

    determinism = contract.get("determinism", {})
    _require(determinism.get("canonical_json") == "SORTED_KEYS_COMPACT_UTF8_NEWLINE_V1", "canonical JSON")
    _require(determinism.get("global_rng_allowed") is False, "global RNG")
    _require(determinism.get("local_clock_allowed") is False, "local clock")
    _require(determinism.get("ambient_environment_allowed") is False, "ambient environment")
    for key in (
        "same_exact_inputs_same_program_bytes_required",
        "same_exact_inputs_same_program_hash_required",
        "fresh_process_replay_required",
    ):
        _require(determinism.get(key) is True, f"determinism {key}")


def _validate_binding(binding: Dict[str, Any], contract: Dict[str, Any]) -> None:
    _require(binding.get("schema") == "distributed_world_simulator.ecology.evo3_e3_7_inputs_binding.v1", "binding schema")
    _require(binding.get("binding_state") == "EXACT_ACCEPTED_EVO3_CHAIN_PLUS_PERSISTED_EVO2_CATALOG", "binding state")
    _require(binding.get("authority") == AUTHORITY, "binding authority")
    _require(binding.get("canonical_binding_resolved") is False, "binding canonical promotion")
    _require(binding.get("production_binding_authorized") is False, "binding production promotion")
    _require(binding.get("accepted_control_head") == EXPECTED_CONTROL_HEAD, "binding accepted control head")
    _require(binding.get("accepted_e3_6_merge_commit") == EXPECTED_E3_6_MERGE, "binding E3.6 merge")
    _require(binding.get("contract_hash") == contract["contract_hash"], "binding contract hash")
    _require(binding.get("binding_hash") == EXPECTED_BINDING_HASH, "binding expected hash")
    _require(object_hash(binding, "binding_hash") == EXPECTED_BINDING_HASH, "binding self hash")
    expected_names = {"e3_1", "e3_2", "e3_3", "e3_4", "catalog", "e3_5", "e3_6"}
    _require(set(binding.get("inputs", {})) == expected_names, "binding exact input set")


def _verify_raw(name: str, raw: bytes, spec: Dict[str, Any]) -> Dict[str, Any]:
    _require(git_blob_hex(raw) == spec["git_blob"], f"{name}: Git blob mismatch")
    _require(sha256_hex(raw) == spec["sha256"], f"{name}: SHA-256 mismatch")
    value = _parse_object(raw, name)
    for field, expected in spec.get("semantic_fields", {}).items():
        _require(value.get(field) == expected, f"{name}: semantic identity {field}")
    self_hash_field = ROOT_SELF_HASH_FIELDS.get(name)
    if self_hash_field is not None:
        _require(object_hash(value, self_hash_field) == value[self_hash_field], f"{name}: recomputed {self_hash_field}")
    _reject_true_authority(value, name)
    return value


def _validate_catalog(catalog: Dict[str, Any]) -> None:
    _require(catalog.get("schema") == "distributed_world_simulator.ecology.evo2_species_catalog.v1", "catalog schema")
    _require(catalog.get("catalog_hash") == EXPECTED_CATALOG_HASH, "catalog hash")
    _require(catalog.get("canonical_species_declared") is False, "catalog canonical promotion")
    entries = catalog.get("entries")
    _require(isinstance(entries, list) and len(entries) == 2, "catalog exact entry count")
    seen: set[str] = set()
    for entry in entries:
        _require(isinstance(entry, dict), "catalog entry type")
        species_id = str(entry.get("research_species_id", ""))
        _require(species_id.startswith("eco-research-species/") and species_id not in seen, "catalog research species identity")
        seen.add(species_id)
        _require(entry.get("canonical_species_declared") is False, "catalog entry canonical promotion")
        _require(entry.get("genome_checksum") == entry.get("genome", {}).get("checksum"), "catalog genome checksum")
        _require(entry.get("recruitment_traits_checksum") == entry.get("recruitment_traits", {}).get("checksum"), "catalog recruitment checksum")


def _validate_cross_stage(values: Mapping[str, Dict[str, Any]]) -> None:
    snapshot = values["e3_1"]
    opportunity = values["e3_2"]
    decomposition = values["e3_3"]
    colonization = values["e3_4"]
    catalog = values["catalog"]
    workset = values["e3_5"]
    temporal = values["e3_6"]

    _validate_catalog(catalog)
    planet = snapshot.get("stable_planet_identity")
    time_key = snapshot.get("stable_time_key")
    _require(planet == EXPECTED_PLANET and time_key == EXPECTED_TIME_KEY, "E3.1 stable identities")
    _require(opportunity.get("stable_planet_identity") == planet, "E3.2 planet linkage")
    _require(opportunity.get("stable_time_key") == time_key, "E3.2 time linkage")
    _require(opportunity.get("source_snapshot_hash") == snapshot.get("snapshot_hash"), "E3.2 snapshot linkage")
    _require(opportunity.get("source_field_provenance_hash") == snapshot.get("field_provenance_hash"), "E3.2 field provenance linkage")

    opportunity_by_key = {sample["stable_spatial_key"]: sample for sample in opportunity.get("samples", [])}
    decomp_by_key = {patch["stable_spatial_key"]: patch for patch in decomposition.get("patches", [])}
    _require(len(opportunity_by_key) == len(opportunity.get("samples", [])), "E3.2 duplicate spatial key")
    _require(len(decomp_by_key) == len(decomposition.get("patches", [])), "E3.3 duplicate spatial key")
    _require(set(opportunity_by_key) == set(decomp_by_key), "E3.2/E3.3 spatial coverage")
    for key in sorted(opportunity_by_key):
        sample = opportunity_by_key[key]
        patch = decomp_by_key[key]
        _require(patch.get("source_opportunity_id") == sample.get("opportunity_id"), f"E3.3 opportunity id linkage {key}")
        _require(patch.get("source_opportunity_sample_hash") == sample.get("opportunity_sample_hash"), f"E3.3 opportunity hash linkage {key}")

    _require(_contains_scalar(colonization, "decomposition_hash", EXPECTED_E3_3_HASH), "E3.4 decomposition linkage")
    _require(_contains_scalar(colonization, "catalog_hash", EXPECTED_CATALOG_HASH), "E3.4 catalog linkage")
    _require(_contains_scalar(workset, "colonization_program_hash", EXPECTED_E3_4_HASH), "E3.5 colonization linkage")
    _require(_contains_scalar(workset, "catalog_hash", EXPECTED_CATALOG_HASH), "E3.5 catalog linkage")
    _require(_contains_scalar(temporal, "population_workset_hash", EXPECTED_E3_5_HASH), "E3.6 workset linkage")
    _require(temporal.get("source_population_workset", {}).get("stable_planet_identity") == planet, "E3.6 planet linkage")
    _require(temporal.get("source_population_workset", {}).get("stable_time_key") == time_key, "E3.6 time linkage")
    _require(temporal.get("source_tf_env_snapshot", {}).get("snapshot_hash") == snapshot.get("snapshot_hash"), "E3.6 snapshot linkage")
    _require(temporal.get("refresh_contract", {}).get("seasonality_evidence_state") == "UNRESOLVED_SINGLE_SNAPSHOT", "E3.6 single snapshot semantics")


def _verified_inputs_from_raw(raw: Dict[str, bytes]) -> _VerifiedInputs:
    _require(set(raw) == {"contract", "binding", "e3_1", "e3_2", "e3_3", "e3_4", "catalog", "e3_5", "e3_6"}, "exact raw input set")
    contract = _parse_object(raw["contract"], "contract")
    binding = _parse_object(raw["binding"], "binding")
    _validate_contract(contract)
    _validate_binding(binding, contract)
    values: Dict[str, Dict[str, Any]] = {}
    for name, spec in binding["inputs"].items():
        values[name] = _verify_raw(name, raw[name], spec)
    _validate_cross_stage(values)
    return _VerifiedInputs(contract=contract, binding=binding, values=values, raw=raw)


def load_verified_inputs(
    contract_path: Path = DEFAULT_CONTRACT,
    binding_path: Path = DEFAULT_BINDING,
) -> _VerifiedInputs:
    contract_raw = Path(contract_path).read_bytes()
    binding_raw = Path(binding_path).read_bytes()
    binding = _parse_object(binding_raw, "binding preflight")
    raw: Dict[str, bytes] = {"contract": contract_raw, "binding": binding_raw}
    for name, spec in binding.get("inputs", {}).items():
        raw[name] = (ROOT / spec["path"]).read_bytes()
    return _verified_inputs_from_raw(raw)


def _chain_manifest(binding: Dict[str, Any]) -> list[Dict[str, Any]]:
    order = ("e3_1", "e3_2", "e3_3", "e3_4", "catalog", "e3_5", "e3_6")
    manifest = []
    for name in order:
        spec = binding["inputs"][name]
        manifest.append({
            "input": name,
            "path": spec["path"],
            "git_blob": spec["git_blob"],
            "sha256": spec["sha256"],
            "semantic_fields": copy.deepcopy(spec.get("semantic_fields", {})),
        })
    return manifest


def _region_manifest(workset: Dict[str, Any]) -> list[Dict[str, Any]]:
    regions = []
    for unit in workset.get("population_work_units", []):
        if unit.get("scale") != "REGION":
            continue
        regions.append({
            "scheduling_region_id": unit["scheduling_region_id"],
            "work_unit_id": unit["work_unit_id"],
            "stable_spatial_keys": sorted(unit.get("stable_spatial_keys", [])),
            "basis_keys": sorted(unit.get("basis_keys", [])),
            "aggregate_member_count": int(unit.get("aggregate_member_count", 0)),
            "authority": "RESEARCH_SCHEDULING_IDENTITY_NON_CANONICAL",
        })
    regions.sort(key=lambda item: (item["scheduling_region_id"], item["work_unit_id"]))
    return regions


def _species_manifest(catalog: Dict[str, Any]) -> list[Dict[str, Any]]:
    result = []
    for entry in catalog["entries"]:
        result.append({
            "research_species_id": entry["research_species_id"],
            "entry_hash": entry["entry_hash"],
            "genome_checksum": entry["genome_checksum"],
            "recruitment_traits_checksum": entry["recruitment_traits_checksum"],
            "canonical_species_declared": False,
        })
    result.sort(key=lambda item: item["research_species_id"])
    return result


def _build_program(inputs: _VerifiedInputs) -> Dict[str, Any]:
    values = inputs.values
    snapshot = values["e3_1"]
    opportunity = values["e3_2"]
    decomposition = values["e3_3"]
    colonization = values["e3_4"]
    catalog = values["catalog"]
    workset = values["e3_5"]
    temporal = values["e3_6"]

    regions = _region_manifest(workset)
    species_manifest = _species_manifest(catalog)
    active_spatial_keys = sorted({e["stable_spatial_key"] for e in temporal.get("temporal_envelopes", [])})
    active_basis_keys = sorted({key for e in temporal.get("temporal_envelopes", []) for key in e.get("basis_keys", [])})
    foundation_manifest = {
        "stable_planet_identity": snapshot["stable_planet_identity"],
        "stable_time_key": snapshot["stable_time_key"],
        "snapshot_hash": snapshot["snapshot_hash"],
        "field_provenance_hash": snapshot["field_provenance_hash"],
        "reference_frame_identity": snapshot.get("reference_frame_identity"),
        "tf_semantic_reference": temporal["source_tf_env_snapshot"]["tf_semantic_reference"],
        "env_semantic_reference": temporal["source_tf_env_snapshot"]["env_semantic_reference"],
        "ownership": "EXTERNAL_OWNER_SNAPSHOT_CONTEXT",
    }
    projection = {
        "authority": "RESEARCH_PROJECTION_NON_CANONICAL",
        "stable_planet_identity": snapshot["stable_planet_identity"],
        "stable_time_key": snapshot["stable_time_key"],
        "catalog_entry_count": len(catalog["entries"]),
        "opportunity_sample_count": len(opportunity.get("samples", [])),
        "research_patch_count": len(decomposition.get("patches", [])),
        "research_edge_count": len(decomposition.get("edges", [])),
        "research_region_count": len(regions),
        "active_spatial_key_count": len(active_spatial_keys),
        "active_basis_count": len(active_basis_keys),
        "temporal_envelope_count": len(temporal.get("temporal_envelopes", [])),
        "individual_entity_count": 0,
    }
    evidence_package = {
        "accepted_control_head": EXPECTED_CONTROL_HEAD,
        "accepted_e3_6_merge_commit": EXPECTED_E3_6_MERGE,
        "immediate_ecology_predecessor": "E3.6",
        "accepted_chain_exact": True,
        "persisted_evo2_catalog_exact": True,
        "external_nondeterminism_snapshot_bound": True,
        "global_rng_used": False,
        "local_clock_used": False,
        "ambient_environment_used": False,
        "input_manifest": _chain_manifest(inputs.binding),
    }
    provenance = {
        "contract_hash": inputs.contract["contract_hash"],
        "binding_hash": inputs.binding["binding_hash"],
        "accepted_control_head": EXPECTED_CONTROL_HEAD,
        "accepted_e3_6_merge_commit": EXPECTED_E3_6_MERGE,
        "input_verification": "EXACT_RAW_GIT_BLOB_SHA256_AND_ACCEPTED_SEMANTIC_IDENTITIES",
        "e3_1_snapshot_hash": snapshot["snapshot_hash"],
        "e3_2_opportunity_field_hash": opportunity["opportunity_field_hash"],
        "e3_3_decomposition_hash": decomposition["decomposition_hash"],
        "e3_4_colonization_program_hash": colonization["colonization_program_hash"],
        "evo2_species_catalog_hash": catalog["catalog_hash"],
        "e3_5_population_workset_hash": workset["population_workset_hash"],
        "e3_6_temporal_program_hash": temporal["temporal_program_hash"],
    }
    program: Dict[str, Any] = {
        "schema": SCHEMA,
        "version": "1.0.0",
        "checkpoint": CHECKPOINT,
        "compiler_stage": COMPILER_STAGE,
        "program_type": "PlanetEcologyProgram",
        "authority": AUTHORITY,
        "canonical_binding_resolved": False,
        "production_binding_authorized": False,
        "stable_planet_identity": snapshot["stable_planet_identity"],
        "stable_time_key": snapshot["stable_time_key"],
        "foundation_manifest": foundation_manifest,
        "species_manifest": species_manifest,
        "accepted_chain_manifest": _chain_manifest(inputs.binding),
        "regions": regions,
        "opportunity_field": copy.deepcopy(opportunity),
        "ecology_decomposition": copy.deepcopy(decomposition),
        "colonization_program": copy.deepcopy(colonization),
        "population_workset": copy.deepcopy(workset),
        "temporal_program": copy.deepcopy(temporal),
        "execution_budget_hints": copy.deepcopy(workset.get("execution_budget_hints", [])),
        "projection": projection,
        "evidence_package": evidence_package,
        "provenance": provenance,
        "provenance_hash": sha256_hex(canonical_bytes(provenance)),
        "planet_ecology_program_hash_algorithm": HASH_ALGORITHM,
    }
    program["planet_ecology_program_hash"] = object_hash(program, "planet_ecology_program_hash")
    return program


def build_planet_ecology_program(inputs: _VerifiedInputs) -> _VerifiedPlanetEcologyProgram:
    _require(type(inputs) is _VerifiedInputs, "build requires exact _VerifiedInputs capability")
    verified = _verified_inputs_from_raw(inputs.raw)
    program = _build_program(verified)
    validate_output_structure(program)
    return _VerifiedPlanetEcologyProgram(program, verified)


def validate_output_structure(program: Dict[str, Any]) -> None:
    _exact_keys(program, (
        "schema", "version", "checkpoint", "compiler_stage", "program_type", "authority",
        "canonical_binding_resolved", "production_binding_authorized", "stable_planet_identity",
        "stable_time_key", "foundation_manifest", "species_manifest", "accepted_chain_manifest",
        "regions", "opportunity_field", "ecology_decomposition", "colonization_program",
        "population_workset", "temporal_program", "execution_budget_hints", "projection",
        "evidence_package", "provenance", "provenance_hash",
        "planet_ecology_program_hash_algorithm", "planet_ecology_program_hash",
    ), "PlanetEcologyProgram")
    _require(program["schema"] == SCHEMA, "output schema")
    _require(program["checkpoint"] == CHECKPOINT and program["compiler_stage"] == COMPILER_STAGE, "output stage")
    _require(program["program_type"] == "PlanetEcologyProgram", "output type")
    _require(program["authority"] == AUTHORITY, "output authority")
    _require(program["canonical_binding_resolved"] is False, "output canonical promotion")
    _require(program["production_binding_authorized"] is False, "output production promotion")
    _require(program["stable_planet_identity"] == EXPECTED_PLANET, "output planet")
    _require(program["stable_time_key"] == EXPECTED_TIME_KEY, "output time")
    _require(program["planet_ecology_program_hash_algorithm"] == HASH_ALGORITHM, "output hash algorithm")
    _require(program["planet_ecology_program_hash"] == object_hash(program, "planet_ecology_program_hash"), "output program self hash")
    _require(program["provenance_hash"] == sha256_hex(canonical_bytes(program["provenance"])), "output provenance hash")
    _require(program["projection"].get("individual_entity_count") == 0, "individual entity truth forbidden")
    _require(program["evidence_package"].get("accepted_chain_exact") is True, "accepted chain evidence")
    _require(program["evidence_package"].get("persisted_evo2_catalog_exact") is True, "catalog evidence")
    _require(program["evidence_package"].get("global_rng_used") is False, "RNG evidence")
    _require(program["evidence_package"].get("local_clock_used") is False, "clock evidence")
    _require(program["evidence_package"].get("ambient_environment_used") is False, "environment evidence")
    _require(len(program["accepted_chain_manifest"]) == 7, "exact input manifest length")
    _require(len(program["species_manifest"]) == 2, "species manifest count")
    _require(len(program["regions"]) >= 1, "region manifest required")
    _reject_true_authority(program, "PlanetEcologyProgram")


def validate_output_integrity(program: Dict[str, Any]) -> None:
    _require(type(program) is _VerifiedPlanetEcologyProgram, "serialization requires _VerifiedPlanetEcologyProgram capability")
    inputs = _verified_inputs_from_raw(program._raw)
    expected = _build_program(inputs)
    validate_output_structure(expected)
    _require(canonical_bytes(dict(program)) == canonical_bytes(expected), "PlanetEcologyProgram differs from independent exact-input rebuild")


def serialize_planet_ecology_program(program: Dict[str, Any]) -> bytes:
    validate_output_integrity(program)
    return serialized_bytes(dict(program))


def write_planet_ecology_program(program: Dict[str, Any], output: Path) -> None:
    Path(output).write_bytes(serialize_planet_ecology_program(program))


def build_from_paths(
    contract_path: Path = DEFAULT_CONTRACT,
    binding_path: Path = DEFAULT_BINDING,
) -> _VerifiedPlanetEcologyProgram:
    return build_planet_ecology_program(load_verified_inputs(contract_path, binding_path))


def main() -> int:
    parser = argparse.ArgumentParser(description="ECO EVO3 E3.7 deterministic PlanetEcologyProgram compiler")
    parser.add_argument("--contract", type=Path, default=DEFAULT_CONTRACT)
    parser.add_argument("--binding", type=Path, default=DEFAULT_BINDING)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()
    program = build_from_paths(args.contract, args.binding)
    write_planet_ecology_program(program, args.output)
    if not args.quiet:
        print(f"E3.7 PlanetEcologyProgram: {args.output}")
        print(f"planet_ecology_program_hash={program['planet_ecology_program_hash']}")
        print(f"provenance_hash={program['provenance_hash']}")
        print(f"regions={len(program['regions'])}")
        print(f"species={len(program['species_manifest'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

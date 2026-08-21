from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
from typing import Any, Dict, Iterable

SCHEMA = "distributed_world_simulator.ecology.evo3_e3_6_temporal_disturbance_program.v1"
CHECKPOINT = "ECO.EVO3/E3.6"
COMPILER_STAGE = "TEMPORAL_PROGRAM"
AUTHORITY = "RESEARCH_DERIVED_NON_AUTHORITATIVE"
TEMPORAL_MODE = "SNAPSHOT_ANCHORED_ENVELOPES"
HASH_ALGORITHM = "SHA256_CANONICAL_JSON_SORTED_KEYS_V1"

CONTRACT_PATH = "config/ecology/eco-evo3-e3-6-temporal-disturbance-contract.v1.json"
BINDING_PATH = "config/ecology/eco-evo3-e3-6-inputs.binding.v1.json"
E3_5_PATH = "validation/ecology/eco-evo3-e3-5-population-workset.generated.json"
E3_1_PATH = "config/ecology/accepted_inputs/e3_1_accepted_planet_field_snapshot.v1.json"

CONTRACT_GIT_BLOB = "46904b61e183ae809a67552f67ab868ddedd876a"
BINDING_GIT_BLOB = "ecaaadf0afc3c3ec28f7028a9a226beb5d52c817"
E3_5_GIT_BLOB = "d54ce8dad2760312d414c62c88d5f4f71427514f"
E3_1_GIT_BLOB = "0d5f8b6b66b56195770af94ed2d847b5c84751c5"

EXPECTED_CONTRACT_HASH = "77077514b9cb72874a26df810bcf9bb761fe0479bce63db432ea8aeba02adc69"
EXPECTED_E3_5_CONTROL_HEAD = "bb1e62532a51841a29b5dd680d0f0f435cfc003d"
EXPECTED_E3_5_MERGE = "cf6374e30e309988f04dfd5d127cca70f10de871"
EXPECTED_E3_5_SHA256 = "0ea5351b7692564161804a3aea5fe5044f3321ded3dcb4d0c7343e93d52c4975"
EXPECTED_E3_5_WORKSET_HASH = "b8f30e129c0f714ebc937cdac6869e63223d8d72172cecb68dd049f604557ff5"
EXPECTED_E3_5_PROVENANCE_HASH = "ec9c734882ef4a97eec2ed071f3c06ec2a29df52f13a45c7054a4641cbd42738"
EXPECTED_E3_1_SHA256 = "5123ebd58e6eade5d3dab2325af49a43234bc8834182ddd7db7d6c463896b790"
EXPECTED_E3_1_SNAPSHOT_HASH = "2ceb042d905b06ae76acc699b60ed6c115d3e0ac7943ce7cbe0c94f962447b00"
EXPECTED_E3_1_FIELD_PROVENANCE_HASH = "3827c1da7d94227fb04b5fbfbd93fd5262c826cd86503af9f540a120431a82c3"
EXPECTED_PLANET = "eco-evo3-fixture/planet-alpha-01"
EXPECTED_TIME_KEY = "tf-fixture/planet-alpha/t000180"
EXPECTED_TF_REFERENCE = "tf-fixture/planet-alpha/time-r1"
EXPECTED_ENV_REFERENCE = "env-fixture/planet-alpha/environment-r1"

OBSERVED_FIELDS = (
    "temperature_milli_c",
    "soil_moisture_ppm",
    "light_availability_ppm",
    "nutrient_availability_ppm",
    "disturbance_pressure_ppm",
)
SAMPLE_VALUE_FIELDS = (
    "latitude_microdeg",
    "longitude_microdeg",
    *OBSERVED_FIELDS,
)
SAMPLE_SOURCE_FIELDS = ("sample_id", "stable_spatial_key", *SAMPLE_VALUE_FIELDS, "sample_hash")
FORBIDDEN_OUTPUT_KEYS = {
    "canonical_time_value",
    "canonical_history_entries",
    "predicted_future",
    "forecast_value",
    "network_authority",
    "persistence_authority",
    "transaction_authority",
}


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")


def sha256_hex(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def git_blob_hex(raw: bytes) -> str:
    header = b"blob " + str(len(raw)).encode("ascii") + b"\0"
    return hashlib.sha1(header + raw).hexdigest()


def object_hash(value: Dict[str, Any], hash_field: str) -> str:
    payload = copy.deepcopy(value)
    payload.pop(hash_field, None)
    return sha256_hex(canonical_bytes(payload))


def _parse_object(raw: bytes, where: str) -> Dict[str, Any]:
    value = json.loads(raw.decode("utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{where}: root must be object")
    return value


def _exact_keys(value: Dict[str, Any], expected: Iterable[str], where: str) -> None:
    if set(value) != set(expected):
        missing = sorted(set(expected) - set(value))
        extra = sorted(set(value) - set(expected))
        raise ValueError(f"{where}: keys mismatch missing={missing} extra={extra}")


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def _assert_raw_identity(raw: bytes, expected_blob: str, expected_sha256: str | None, where: str) -> None:
    _require(git_blob_hex(raw) == expected_blob, f"{where}: git blob mismatch")
    if expected_sha256 is not None:
        _require(sha256_hex(raw) == expected_sha256, f"{where}: raw SHA-256 mismatch")


class _VerifiedInputs:
    __slots__ = (
        "contract",
        "binding",
        "workset",
        "snapshot",
        "contract_raw",
        "binding_raw",
        "workset_raw",
        "snapshot_raw",
    )

    def __init__(
        self,
        *,
        contract: Dict[str, Any],
        binding: Dict[str, Any],
        workset: Dict[str, Any],
        snapshot: Dict[str, Any],
        contract_raw: bytes,
        binding_raw: bytes,
        workset_raw: bytes,
        snapshot_raw: bytes,
    ) -> None:
        self.contract = contract
        self.binding = binding
        self.workset = workset
        self.snapshot = snapshot
        self.contract_raw = contract_raw
        self.binding_raw = binding_raw
        self.workset_raw = workset_raw
        self.snapshot_raw = snapshot_raw


class _VerifiedTemporalProgram(dict):
    def __init__(
        self,
        value: Dict[str, Any],
        *,
        contract_raw: bytes,
        binding_raw: bytes,
        workset_raw: bytes,
        snapshot_raw: bytes,
    ) -> None:
        super().__init__(copy.deepcopy(value))
        self._contract_raw = bytes(contract_raw)
        self._binding_raw = bytes(binding_raw)
        self._workset_raw = bytes(workset_raw)
        self._snapshot_raw = bytes(snapshot_raw)


def _validate_contract(contract: Dict[str, Any]) -> None:
    _require(contract.get("schema") == "distributed_world_simulator.ecology.evo3_e3_6_temporal_disturbance_contract.v1", "contract schema")
    _require(contract.get("checkpoint") == CHECKPOINT, "contract checkpoint")
    _require(contract.get("compiler_stage") == COMPILER_STAGE, "contract stage")
    _require(contract.get("authority") == AUTHORITY, "contract authority")
    _require(contract.get("canonical_binding_resolved") is False, "contract canonical binding")
    _require(contract.get("production_binding_authorized") is False, "contract production binding")
    _require(contract.get("contract_hash") == EXPECTED_CONTRACT_HASH, "contract expected hash")
    _require(object_hash(contract, "contract_hash") == EXPECTED_CONTRACT_HASH, "contract self hash")

    e35 = contract.get("accepted_e3_5", {})
    _require(e35.get("accepted_control_head") == EXPECTED_E3_5_CONTROL_HEAD, "contract E3.5 control")
    _require(e35.get("canonical_merge_commit") == EXPECTED_E3_5_MERGE, "contract E3.5 merge")
    _require(e35.get("artifact_path") == E3_5_PATH, "contract E3.5 path")
    _require(e35.get("artifact_git_blob") == E3_5_GIT_BLOB, "contract E3.5 blob")
    _require(e35.get("artifact_sha256") == EXPECTED_E3_5_SHA256, "contract E3.5 sha")
    _require(e35.get("population_workset_hash") == EXPECTED_E3_5_WORKSET_HASH, "contract E3.5 hash")
    _require(e35.get("provenance_hash") == EXPECTED_E3_5_PROVENANCE_HASH, "contract E3.5 provenance")

    ctx = contract.get("tf_env_context", {})
    _require(ctx.get("role") == "IMMUTABLE_UPSTREAM_CONTEXT_NOT_ECOLOGY_PREDECESSOR", "context role")
    _require(ctx.get("artifact_path") == E3_1_PATH, "context path")
    _require(ctx.get("artifact_git_blob") == E3_1_GIT_BLOB, "context blob")
    _require(ctx.get("artifact_sha256") == EXPECTED_E3_1_SHA256, "context sha")
    _require(ctx.get("snapshot_hash") == EXPECTED_E3_1_SNAPSHOT_HASH, "context snapshot hash")
    _require(ctx.get("field_provenance_hash") == EXPECTED_E3_1_FIELD_PROVENANCE_HASH, "context provenance")
    _require(ctx.get("stable_planet_identity") == EXPECTED_PLANET, "context planet")
    _require(ctx.get("stable_time_key") == EXPECTED_TIME_KEY, "context time")
    _require(ctx.get("tf_semantic_reference") == EXPECTED_TF_REFERENCE, "context TF")
    _require(ctx.get("env_semantic_reference") == EXPECTED_ENV_REFERENCE, "context ENV")

    policy = contract.get("input_policy", {})
    for name in (
        "raw_bytes_required",
        "git_blob_required",
        "artifact_sha256_required",
        "semantic_hash_recompute_required",
        "candidate_alias_authority_forbidden",
        "plain_parsed_dict_authority_forbidden",
        "earlier_stage_scientific_reconstruction_forbidden",
    ):
        _require(policy.get(name) is True, f"contract input policy {name}")
    _require(policy.get("sole_ecology_predecessor") == "EXACT_ACCEPTED_E3_5_POPULATION_WORKSET", "sole ecology predecessor")
    _require(policy.get("tf_env_context_is_authoritative_ecology_predecessor") is False, "context predecessor escalation")

    temporal = contract.get("temporal_semantics", {})
    _require(temporal.get("mode") == TEMPORAL_MODE, "temporal mode")
    _require(temporal.get("stable_time_key_semantics") == "OPAQUE_OWNER_TIME_IDENTITY_NOT_NUMERIC_TIME", "time key semantics")
    _require(temporal.get("refresh_policy") == "RECOMPILE_FROM_NEW_EXACT_OWNER_SNAPSHOT", "refresh policy")
    for name in ("history_write_allowed", "future_forecast_allowed", "canonical_time_ownership", "canonical_environment_ownership"):
        _require(temporal.get(name) is False, f"temporal authority {name}")

    single = contract.get("single_snapshot_policy", {})
    _require(single.get("seasonality_state") == "UNRESOLVED_SINGLE_SNAPSHOT", "single snapshot state")
    _require(single.get("envelope_rule") == "MIN_EQUALS_ANCHOR_EQUALS_MAX_FOR_EACH_OBSERVED_FIELD", "single snapshot envelope")
    for name in ("invented_cycle_forbidden", "latitude_derived_cycle_forbidden", "opaque_time_key_numeric_interpretation_forbidden"):
        _require(single.get(name) is True, f"single snapshot policy {name}")
    _require(tuple(contract.get("observed_fields", ())) == OBSERVED_FIELDS, "observed fields")


def _validate_binding(binding: Dict[str, Any], contract: Dict[str, Any]) -> None:
    _require(binding.get("schema") == "distributed_world_simulator.ecology.evo3_e3_6_inputs_binding.v1", "binding schema")
    _require(binding.get("binding_state") == "EXACT_ACCEPTED_E3_5_PLUS_IMMUTABLE_TF_ENV_CONTEXT", "binding state")
    _require(binding.get("authority") == AUTHORITY, "binding authority")
    _require(binding.get("canonical_binding_resolved") is False, "binding canonical")
    _require(binding.get("production_binding_authorized") is False, "binding production")
    _require(binding.get("contract_hash") == contract["contract_hash"], "binding contract hash")

    e35 = binding.get("accepted_e3_5", {})
    _require(e35.get("accepted_control_head") == EXPECTED_E3_5_CONTROL_HEAD, "binding E3.5 control")
    _require(e35.get("canonical_merge_commit") == EXPECTED_E3_5_MERGE, "binding E3.5 merge")
    _require(e35.get("artifact_path") == E3_5_PATH, "binding E3.5 path")
    _require(e35.get("artifact_git_blob") == E3_5_GIT_BLOB, "binding E3.5 blob")
    _require(e35.get("artifact_sha256") == EXPECTED_E3_5_SHA256, "binding E3.5 sha")
    _require(e35.get("population_workset_hash") == EXPECTED_E3_5_WORKSET_HASH, "binding E3.5 hash")
    _require(e35.get("provenance_hash") == EXPECTED_E3_5_PROVENANCE_HASH, "binding E3.5 provenance")

    ctx = binding.get("tf_env_context", {})
    _require(ctx.get("role") == "IMMUTABLE_UPSTREAM_CONTEXT_NOT_ECOLOGY_PREDECESSOR", "binding context role")
    _require(ctx.get("artifact_path") == E3_1_PATH, "binding context path")
    _require(ctx.get("artifact_git_blob") == E3_1_GIT_BLOB, "binding context blob")
    _require(ctx.get("artifact_sha256") == EXPECTED_E3_1_SHA256, "binding context sha")
    _require(ctx.get("snapshot_hash") == EXPECTED_E3_1_SNAPSHOT_HASH, "binding context snapshot")
    _require(ctx.get("field_provenance_hash") == EXPECTED_E3_1_FIELD_PROVENANCE_HASH, "binding context provenance")
    _require(ctx.get("stable_planet_identity") == EXPECTED_PLANET, "binding context planet")
    _require(ctx.get("stable_time_key") == EXPECTED_TIME_KEY, "binding context time")
    _require(ctx.get("tf_semantic_reference") == EXPECTED_TF_REFERENCE, "binding context TF")
    _require(ctx.get("env_semantic_reference") == EXPECTED_ENV_REFERENCE, "binding context ENV")


def _validate_workset(workset: Dict[str, Any]) -> None:
    _require(workset.get("schema") == "distributed_world_simulator.ecology.evo3_e3_5_population_workset.v1", "E3.5 schema")
    _require(workset.get("checkpoint") == "ECO.EVO3/E3.5", "E3.5 checkpoint")
    _require(workset.get("compiler_stage") == "POPULATION_WORKSET", "E3.5 stage")
    _require(workset.get("authority") == AUTHORITY, "E3.5 authority")
    _require(workset.get("canonical_binding_resolved") is False, "E3.5 canonical binding")
    _require(workset.get("production_binding_authorized") is False, "E3.5 production binding")
    _require(workset.get("population_workset_hash_algorithm") == HASH_ALGORITHM, "E3.5 hash algorithm")
    _require(workset.get("population_workset_hash") == EXPECTED_E3_5_WORKSET_HASH, "E3.5 expected hash")
    _require(object_hash(workset, "population_workset_hash") == EXPECTED_E3_5_WORKSET_HASH, "E3.5 self hash")
    provenance = workset.get("provenance")
    _require(isinstance(provenance, dict), "E3.5 provenance object")
    _require(workset.get("provenance_hash") == EXPECTED_E3_5_PROVENANCE_HASH, "E3.5 provenance identity")
    _require(sha256_hex(canonical_bytes(provenance)) == EXPECTED_E3_5_PROVENANCE_HASH, "E3.5 provenance hash")
    source = workset.get("source_colonization_program", {})
    _require(source.get("stable_planet_identity") == EXPECTED_PLANET, "E3.5 planet")
    _require(source.get("stable_time_key") == EXPECTED_TIME_KEY, "E3.5 time")
    _require(workset.get("workset_result") in ("ACTIVE_WORKSETS", "NO_ACTIVE_POPULATION_WORK"), "E3.5 result")

    manifest = workset.get("work_basis_manifest")
    _require(isinstance(manifest, list), "E3.5 basis manifest")
    seen = set()
    for row in manifest:
        _exact_keys(row, {"basis_key", "research_patch_id", "research_species_id", "source_decision", "stable_spatial_key"}, "E3.5 basis row")
        _require(row["source_decision"] == "ESTABLISHED", "E3.5 basis decision")
        _require(row["basis_key"] not in seen, "E3.5 duplicate basis")
        seen.add(row["basis_key"])
    summary = workset.get("summary", {})
    _require(len(manifest) == summary.get("active_basis_count"), "E3.5 basis summary")
    _require(summary.get("individual_entity_count") == 0, "E3.5 individual entity truth")
    if workset["workset_result"] == "NO_ACTIVE_POPULATION_WORK":
        _require(not manifest, "E3.5 empty result with basis")


def _sample_provenance(sample: Dict[str, Any], snapshot: Dict[str, Any]) -> str:
    source_sample = {key: sample[key] for key in SAMPLE_SOURCE_FIELDS}
    material = {
        "stable_planet_identity": snapshot["stable_planet_identity"],
        "stable_time_key": snapshot["stable_time_key"],
        "reference_frame_identity": snapshot["reference_frame_identity"],
        "foundation_references": snapshot["foundation_manifest"],
        "sample": source_sample,
    }
    return sha256_hex(canonical_bytes(material))


def _validate_snapshot(snapshot: Dict[str, Any]) -> None:
    _require(snapshot.get("schema") == "distributed_world_simulator.ecology.evo3_planet_field_snapshot.v1", "E3.1 schema")
    _require(snapshot.get("authority") == AUTHORITY, "E3.1 authority")
    _require(snapshot.get("canonical_binding_resolved") is False, "E3.1 canonical binding")
    _require(snapshot.get("stable_planet_identity") == EXPECTED_PLANET, "E3.1 planet")
    _require(snapshot.get("stable_time_key") == EXPECTED_TIME_KEY, "E3.1 time")
    _require(snapshot.get("snapshot_hash_algorithm") == HASH_ALGORITHM, "E3.1 hash algorithm")
    _require(snapshot.get("snapshot_hash") == EXPECTED_E3_1_SNAPSHOT_HASH, "E3.1 expected snapshot hash")
    _require(object_hash(snapshot, "snapshot_hash") == EXPECTED_E3_1_SNAPSHOT_HASH, "E3.1 self hash")
    _require(snapshot.get("field_provenance_hash") == EXPECTED_E3_1_FIELD_PROVENANCE_HASH, "E3.1 field provenance")
    foundations = snapshot.get("foundation_manifest", {})
    _require(foundations.get("TF", {}).get("semantic_reference") == EXPECTED_TF_REFERENCE, "E3.1 TF ref")
    _require(foundations.get("ENV", {}).get("semantic_reference") == EXPECTED_ENV_REFERENCE, "E3.1 ENV ref")
    _require(foundations.get("TF", {}).get("canonical_binding_resolved") is False, "E3.1 TF canonical")
    _require(foundations.get("ENV", {}).get("canonical_binding_resolved") is False, "E3.1 ENV canonical")

    samples = snapshot.get("samples")
    _require(isinstance(samples, list), "E3.1 samples")
    seen_spatial = set()
    for sample in samples:
        spatial_key = sample.get("stable_spatial_key")
        _require(spatial_key not in seen_spatial, "E3.1 duplicate spatial key")
        seen_spatial.add(spatial_key)
        source_shape = {key: sample[key] for key in SAMPLE_SOURCE_FIELDS}
        _require(sample.get("sample_hash") == object_hash(source_shape, "sample_hash"), "E3.1 sample hash")
        _require(sample.get("field_provenance_hash") == _sample_provenance(sample, snapshot), "E3.1 sample provenance")
        for field in SAMPLE_VALUE_FIELDS:
            _require(type(sample.get(field)) is int, f"E3.1 non-integer {field}")


def _verify_raw_inputs(contract_raw: bytes, binding_raw: bytes, workset_raw: bytes, snapshot_raw: bytes) -> _VerifiedInputs:
    _assert_raw_identity(contract_raw, CONTRACT_GIT_BLOB, None, "E3.6 contract")
    _assert_raw_identity(binding_raw, BINDING_GIT_BLOB, None, "E3.6 binding")
    _assert_raw_identity(workset_raw, E3_5_GIT_BLOB, EXPECTED_E3_5_SHA256, "accepted E3.5 workset")
    _assert_raw_identity(snapshot_raw, E3_1_GIT_BLOB, EXPECTED_E3_1_SHA256, "accepted E3.1 snapshot")
    contract = _parse_object(contract_raw, "contract")
    binding = _parse_object(binding_raw, "binding")
    workset = _parse_object(workset_raw, "E3.5 workset")
    snapshot = _parse_object(snapshot_raw, "E3.1 snapshot")
    _validate_contract(contract)
    _validate_binding(binding, contract)
    _validate_workset(workset)
    _validate_snapshot(snapshot)
    source = workset["source_colonization_program"]
    _require(source["stable_planet_identity"] == snapshot["stable_planet_identity"], "planet mismatch across E3.5/E3.1")
    _require(source["stable_time_key"] == snapshot["stable_time_key"], "time mismatch across E3.5/E3.1")
    sample_keys = {sample["stable_spatial_key"] for sample in snapshot["samples"]}
    active_keys = {row["stable_spatial_key"] for row in workset["work_basis_manifest"]}
    _require(active_keys <= sample_keys, "active E3.5 spatial key missing from exact E3.1 context")
    return _VerifiedInputs(
        contract=contract,
        binding=binding,
        workset=workset,
        snapshot=snapshot,
        contract_raw=contract_raw,
        binding_raw=binding_raw,
        workset_raw=workset_raw,
        snapshot_raw=snapshot_raw,
    )


def load_verified_inputs(
    contract_path: Path | str,
    binding_path: Path | str,
    workset_path: Path | str,
    snapshot_path: Path | str,
) -> _VerifiedInputs:
    return _verify_raw_inputs(
        Path(contract_path).read_bytes(),
        Path(binding_path).read_bytes(),
        Path(workset_path).read_bytes(),
        Path(snapshot_path).read_bytes(),
    )


def _triple(value: int) -> Dict[str, int]:
    return {"min": value, "anchor": value, "max": value}


def _compile_envelopes(workset: Dict[str, Any], snapshot: Dict[str, Any]) -> list[Dict[str, Any]]:
    grouped: Dict[str, list[str]] = {}
    for row in workset["work_basis_manifest"]:
        grouped.setdefault(row["stable_spatial_key"], []).append(row["basis_key"])
    samples = {sample["stable_spatial_key"]: sample for sample in snapshot["samples"]}
    envelopes: list[Dict[str, Any]] = []
    for spatial_key in sorted(grouped):
        basis_keys = sorted(grouped[spatial_key])
        sample = samples[spatial_key]
        identity = {
            "stable_planet_identity": snapshot["stable_planet_identity"],
            "stable_spatial_key": spatial_key,
            "stable_time_key": snapshot["stable_time_key"],
            "basis_keys": basis_keys,
            "source_sample_id": sample["sample_id"],
            "source_sample_hash": sample["sample_hash"],
            "source_field_provenance_hash": sample["field_provenance_hash"],
        }
        envelopes.append(
            {
                "envelope_id": "eco-evo3/e3.6/envelope/" + sha256_hex(canonical_bytes(identity))[:24],
                "authority": "RESEARCH_TEMPORAL_ENVELOPE_NON_CANONICAL",
                "stable_planet_identity": snapshot["stable_planet_identity"],
                "stable_spatial_key": spatial_key,
                "stable_time_key": snapshot["stable_time_key"],
                "basis_keys": basis_keys,
                "source_sample_id": sample["sample_id"],
                "source_sample_hash": sample["sample_hash"],
                "source_field_provenance_hash": sample["field_provenance_hash"],
                "seasonality_state": "UNRESOLVED_SINGLE_SNAPSHOT",
                "temporal_evidence_state": "SINGLE_ACCEPTED_OWNER_SNAPSHOT_ONLY",
                "observed_envelopes": {field: _triple(sample[field]) for field in OBSERVED_FIELDS},
                "disturbance_schedule": {
                    "state": "NOT_DERIVABLE_FROM_SINGLE_SNAPSHOT",
                    "observed_pressure_ppm": sample["disturbance_pressure_ppm"],
                    "scheduled_events": [],
                    "authority": "NO_FUTURE_DISTURBANCE_EVENT_AUTHORITY",
                },
                "refresh_policy": "RECOMPILE_FROM_NEW_EXACT_OWNER_SNAPSHOT",
                "history_write_allowed": False,
                "forecast_authorized": False,
            }
        )
    return envelopes


def _build_temporal_program(inputs: _VerifiedInputs) -> Dict[str, Any]:
    workset = inputs.workset
    snapshot = inputs.snapshot
    binding = inputs.binding
    envelopes = _compile_envelopes(workset, snapshot)
    source_e35 = binding["accepted_e3_5"]
    source_ctx = binding["tf_env_context"]
    provenance = {
        "contract_hash": inputs.contract["contract_hash"],
        "binding_git_blob": BINDING_GIT_BLOB,
        "accepted_e3_5_control_head": EXPECTED_E3_5_CONTROL_HEAD,
        "accepted_e3_5_merge_commit": EXPECTED_E3_5_MERGE,
        "accepted_e3_5_git_blob": E3_5_GIT_BLOB,
        "accepted_e3_5_artifact_sha256": EXPECTED_E3_5_SHA256,
        "accepted_e3_5_population_workset_hash": EXPECTED_E3_5_WORKSET_HASH,
        "accepted_e3_5_provenance_hash": EXPECTED_E3_5_PROVENANCE_HASH,
        "tf_env_context_git_blob": E3_1_GIT_BLOB,
        "tf_env_context_artifact_sha256": EXPECTED_E3_1_SHA256,
        "tf_env_context_snapshot_hash": EXPECTED_E3_1_SNAPSHOT_HASH,
        "tf_env_context_field_provenance_hash": EXPECTED_E3_1_FIELD_PROVENANCE_HASH,
        "input_verification": "EXACT_ACCEPTED_E3_5_AND_TF_ENV_CONTEXT_RAW_BYTES_VERIFIED",
        "single_snapshot_seasonality_unresolved": True,
    }
    program = {
        "schema": SCHEMA,
        "checkpoint": CHECKPOINT,
        "compiler_stage": COMPILER_STAGE,
        "authority": AUTHORITY,
        "canonical_binding_resolved": False,
        "production_binding_authorized": False,
        "temporal_mode": TEMPORAL_MODE,
        "temporal_result": "TEMPORAL_PROGRAM_PRESENT" if envelopes else "NO_ACTIVE_POPULATION_TEMPORAL_WORK",
        "source_population_workset": {
            "accepted_control_head": source_e35["accepted_control_head"],
            "canonical_merge_commit": source_e35["canonical_merge_commit"],
            "artifact_sha256": source_e35["artifact_sha256"],
            "git_blob": source_e35["artifact_git_blob"],
            "population_workset_hash": source_e35["population_workset_hash"],
            "provenance_hash": source_e35["provenance_hash"],
            "workset_result": workset["workset_result"],
            "stable_planet_identity": workset["source_colonization_program"]["stable_planet_identity"],
            "stable_time_key": workset["source_colonization_program"]["stable_time_key"],
        },
        "source_tf_env_snapshot": {
            "context_role": source_ctx["role"],
            "artifact_sha256": source_ctx["artifact_sha256"],
            "git_blob": source_ctx["artifact_git_blob"],
            "snapshot_hash": source_ctx["snapshot_hash"],
            "field_provenance_hash": source_ctx["field_provenance_hash"],
            "stable_planet_identity": source_ctx["stable_planet_identity"],
            "stable_time_key": source_ctx["stable_time_key"],
            "tf_semantic_reference": source_ctx["tf_semantic_reference"],
            "env_semantic_reference": source_ctx["env_semantic_reference"],
        },
        "temporal_envelopes": envelopes,
        "refresh_contract": {
            "policy": "RECOMPILE_FROM_NEW_EXACT_OWNER_SNAPSHOT",
            "stable_time_key_semantics": "OPAQUE_OWNER_TIME_IDENTITY_NOT_NUMERIC_TIME",
            "seasonality_evidence_state": "UNRESOLVED_SINGLE_SNAPSHOT",
            "history_write_allowed": False,
            "forecast_authorized": False,
            "canonical_time_ownership": False,
            "canonical_environment_ownership": False,
        },
        "summary": {
            "active_basis_count": len(workset["work_basis_manifest"]),
            "active_spatial_key_count": len(envelopes),
            "temporal_envelope_count": len(envelopes),
            "unresolved_seasonality_count": len(envelopes),
            "future_disturbance_event_count": 0,
            "canonical_history_write_count": 0,
            "individual_entity_count": 0,
        },
        "provenance": provenance,
        "provenance_hash": sha256_hex(canonical_bytes(provenance)),
        "temporal_program_hash_algorithm": HASH_ALGORITHM,
    }
    program["temporal_program_hash"] = object_hash(program, "temporal_program_hash")
    return program


def _assert_no_forbidden_output_keys(value: Any) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if str(key) in FORBIDDEN_OUTPUT_KEYS:
                raise ValueError(f"forbidden output authority/history key: {key}")
            _assert_no_forbidden_output_keys(child)
    elif isinstance(value, list):
        for child in value:
            _assert_no_forbidden_output_keys(child)


def validate_output_structure(program: Dict[str, Any]) -> None:
    expected_top = {
        "schema", "checkpoint", "compiler_stage", "authority", "canonical_binding_resolved",
        "production_binding_authorized", "temporal_mode", "temporal_result",
        "source_population_workset", "source_tf_env_snapshot", "temporal_envelopes",
        "refresh_contract", "summary", "provenance", "provenance_hash",
        "temporal_program_hash_algorithm", "temporal_program_hash",
    }
    _exact_keys(program, expected_top, "temporal program")
    _require(program["schema"] == SCHEMA, "program schema")
    _require(program["checkpoint"] == CHECKPOINT, "program checkpoint")
    _require(program["compiler_stage"] == COMPILER_STAGE, "program stage")
    _require(program["authority"] == AUTHORITY, "program authority")
    _require(program["canonical_binding_resolved"] is False, "program canonical binding")
    _require(program["production_binding_authorized"] is False, "program production binding")
    _require(program["temporal_mode"] == TEMPORAL_MODE, "program temporal mode")
    _require(program["temporal_program_hash_algorithm"] == HASH_ALGORITHM, "program hash algorithm")
    _require(program["temporal_program_hash"] == object_hash(program, "temporal_program_hash"), "program self hash")
    _require(program["provenance_hash"] == sha256_hex(canonical_bytes(program["provenance"])), "program provenance hash")

    source = program["source_population_workset"]
    _require(source["accepted_control_head"] == EXPECTED_E3_5_CONTROL_HEAD, "program source control")
    _require(source["canonical_merge_commit"] == EXPECTED_E3_5_MERGE, "program source merge")
    _require(source["artifact_sha256"] == EXPECTED_E3_5_SHA256, "program source sha")
    _require(source["git_blob"] == E3_5_GIT_BLOB, "program source blob")
    _require(source["population_workset_hash"] == EXPECTED_E3_5_WORKSET_HASH, "program source workset")
    _require(source["provenance_hash"] == EXPECTED_E3_5_PROVENANCE_HASH, "program source provenance")
    _require(source["stable_planet_identity"] == EXPECTED_PLANET, "program source planet")
    _require(source["stable_time_key"] == EXPECTED_TIME_KEY, "program source time")

    context = program["source_tf_env_snapshot"]
    _require(context["context_role"] == "IMMUTABLE_UPSTREAM_CONTEXT_NOT_ECOLOGY_PREDECESSOR", "program context role")
    _require(context["artifact_sha256"] == EXPECTED_E3_1_SHA256, "program context sha")
    _require(context["git_blob"] == E3_1_GIT_BLOB, "program context blob")
    _require(context["snapshot_hash"] == EXPECTED_E3_1_SNAPSHOT_HASH, "program context snapshot")
    _require(context["field_provenance_hash"] == EXPECTED_E3_1_FIELD_PROVENANCE_HASH, "program context provenance")
    _require(context["stable_planet_identity"] == EXPECTED_PLANET, "program context planet")
    _require(context["stable_time_key"] == EXPECTED_TIME_KEY, "program context time")
    _require(context["tf_semantic_reference"] == EXPECTED_TF_REFERENCE, "program TF ref")
    _require(context["env_semantic_reference"] == EXPECTED_ENV_REFERENCE, "program ENV ref")

    refresh = program["refresh_contract"]
    _require(refresh["policy"] == "RECOMPILE_FROM_NEW_EXACT_OWNER_SNAPSHOT", "program refresh policy")
    _require(refresh["stable_time_key_semantics"] == "OPAQUE_OWNER_TIME_IDENTITY_NOT_NUMERIC_TIME", "program time semantics")
    _require(refresh["seasonality_evidence_state"] == "UNRESOLVED_SINGLE_SNAPSHOT", "program seasonality state")
    for name in ("history_write_allowed", "forecast_authorized", "canonical_time_ownership", "canonical_environment_ownership"):
        _require(refresh[name] is False, f"program authority {name}")

    envelopes = program["temporal_envelopes"]
    spatial_keys = [item["stable_spatial_key"] for item in envelopes]
    _require(spatial_keys == sorted(spatial_keys), "program envelope order")
    _require(len(spatial_keys) == len(set(spatial_keys)), "program duplicate envelope")
    all_basis: list[str] = []
    for envelope in envelopes:
        _require(envelope["authority"] == "RESEARCH_TEMPORAL_ENVELOPE_NON_CANONICAL", "envelope authority")
        _require(envelope["stable_planet_identity"] == EXPECTED_PLANET, "envelope planet")
        _require(envelope["stable_time_key"] == EXPECTED_TIME_KEY, "envelope time")
        _require(envelope["seasonality_state"] == "UNRESOLVED_SINGLE_SNAPSHOT", "envelope seasonality")
        _require(envelope["temporal_evidence_state"] == "SINGLE_ACCEPTED_OWNER_SNAPSHOT_ONLY", "envelope evidence")
        _require(envelope["refresh_policy"] == "RECOMPILE_FROM_NEW_EXACT_OWNER_SNAPSHOT", "envelope refresh")
        _require(envelope["history_write_allowed"] is False and envelope["forecast_authorized"] is False, "envelope authority")
        basis_keys = envelope["basis_keys"]
        _require(basis_keys == sorted(basis_keys) and len(basis_keys) == len(set(basis_keys)) and basis_keys, "envelope basis")
        all_basis.extend(basis_keys)
        for field in OBSERVED_FIELDS:
            triple = envelope["observed_envelopes"][field]
            _require(set(triple) == {"min", "anchor", "max"}, f"{field} triple keys")
            _require(type(triple["anchor"]) is int, f"{field} anchor type")
            _require(triple["min"] == triple["anchor"] == triple["max"], f"{field} fabricated variation")
        disturbance = envelope["disturbance_schedule"]
        _require(disturbance["state"] == "NOT_DERIVABLE_FROM_SINGLE_SNAPSHOT", "disturbance state")
        _require(disturbance["scheduled_events"] == [], "future disturbance events")
        _require(disturbance["authority"] == "NO_FUTURE_DISTURBANCE_EVENT_AUTHORITY", "disturbance authority")
        _require(disturbance["observed_pressure_ppm"] == envelope["observed_envelopes"]["disturbance_pressure_ppm"]["anchor"], "disturbance anchor")

    _require(len(all_basis) == len(set(all_basis)), "basis covered more than once")
    summary = program["summary"]
    _require(summary["active_basis_count"] == len(all_basis), "summary basis")
    _require(summary["active_spatial_key_count"] == len(envelopes), "summary spatial")
    _require(summary["temporal_envelope_count"] == len(envelopes), "summary envelopes")
    _require(summary["unresolved_seasonality_count"] == len(envelopes), "summary unresolved")
    _require(summary["future_disturbance_event_count"] == 0, "summary future")
    _require(summary["canonical_history_write_count"] == 0, "summary history")
    _require(summary["individual_entity_count"] == 0, "summary individuals")
    _require(program["temporal_result"] == ("TEMPORAL_PROGRAM_PRESENT" if envelopes else "NO_ACTIVE_POPULATION_TEMPORAL_WORK"), "temporal result")
    _assert_no_forbidden_output_keys(program)


def validate_output_integrity(program: Dict[str, Any]) -> None:
    if not isinstance(program, _VerifiedTemporalProgram):
        raise ValueError("authoritative integrity requires _VerifiedTemporalProgram exact-input capability")
    validate_output_structure(program)
    inputs = _verify_raw_inputs(
        program._contract_raw,
        program._binding_raw,
        program._workset_raw,
        program._snapshot_raw,
    )
    expected = _build_temporal_program(inputs)
    if canonical_bytes(dict(program)) != canonical_bytes(expected):
        raise ValueError("temporal program differs from independent exact-input rebuild")


def build_temporal_program(inputs: _VerifiedInputs) -> _VerifiedTemporalProgram:
    if not isinstance(inputs, _VerifiedInputs):
        raise ValueError("build requires _VerifiedInputs exact-input capability")
    value = _build_temporal_program(inputs)
    program = _VerifiedTemporalProgram(
        value,
        contract_raw=inputs.contract_raw,
        binding_raw=inputs.binding_raw,
        workset_raw=inputs.workset_raw,
        snapshot_raw=inputs.snapshot_raw,
    )
    validate_output_integrity(program)
    return program


def serialize_temporal_program(program: Dict[str, Any]) -> bytes:
    validate_output_integrity(program)
    return canonical_bytes(dict(program)) + b"\n"


def write_temporal_program(path: Path | str, program: Dict[str, Any]) -> None:
    Path(path).write_bytes(serialize_temporal_program(program))


def build_from_paths(
    contract_path: Path | str,
    binding_path: Path | str,
    workset_path: Path | str,
    snapshot_path: Path | str,
) -> _VerifiedTemporalProgram:
    return build_temporal_program(load_verified_inputs(contract_path, binding_path, workset_path, snapshot_path))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", default=CONTRACT_PATH)
    parser.add_argument("--binding", default=BINDING_PATH)
    parser.add_argument("--workset", default=E3_5_PATH)
    parser.add_argument("--snapshot", default=E3_1_PATH)
    parser.add_argument("--output")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()
    program = build_from_paths(args.contract, args.binding, args.workset, args.snapshot)
    if args.output:
        write_temporal_program(args.output, program)
    if not args.quiet:
        print("ECO.EVO3 E3.6 Seasonal & Disturbance Temporal Program: PASS")
        print(f"temporal_result={program['temporal_result']}")
        print(f"active_basis={program['summary']['active_basis_count']}")
        print(f"active_spatial_keys={program['summary']['active_spatial_key_count']}")
        print(f"temporal_envelopes={program['summary']['temporal_envelope_count']}")
        print(f"seasonality={program['refresh_contract']['seasonality_evidence_state']}")
        print(f"future_disturbance_events={program['summary']['future_disturbance_event_count']}")
        print(f"provenance_hash={program['provenance_hash']}")
        print(f"temporal_program_hash={program['temporal_program_hash']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

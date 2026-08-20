#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import pathlib
from typing import Any

_REPO_ROOT = pathlib.Path(__file__).resolve().parents[3]
CONTRACT_GIT_BLOB = "b2afe370aa505e3d8448e5bd2ebb065a00dd7f38"
BINDING_GIT_BLOB = "3705d33cd1c393f9a8ce03ce59d89a883933f05f"
ACCEPTED_E3_4_GIT_BLOB = "db725ef37912547527dff5fffe39ca63e5f8c22e"

AUTHORITY = "RESEARCH_DERIVED_NON_AUTHORITATIVE"
UNVERIFIED_AUTHORITY = "UNVERIFIED_PARSED_INPUTS_NO_ACCEPTED_INPUT_ATTESTATION"
SCHEDULING_AUTHORITY = "RESEARCH_SCHEDULING_IDENTITY_NON_CANONICAL"
OUTPUT_SCHEMA = "distributed_world_simulator.ecology.evo3_e3_5_population_workset.v1"
SCALE_LEVELS = ("PLANET", "REGION", "PATCH", "LOCAL_ACTIVE")
REPRESENTATIONS = {
    "PLANET": "PLANET_AGGREGATE",
    "REGION": "REGION_AGGREGATE",
    "PATCH": "PATCH_AGGREGATE",
    "LOCAL_ACTIVE": "LOCAL_ACTIVE_AGGREGATE_COHORT_PROJECTION",
}
BUDGET_OVERHEAD = {"PLANET": 100, "REGION": 80, "PATCH": 40, "LOCAL_ACTIVE": 100}
BUDGET_PER_MEMBER = {"PLANET": 2, "REGION": 4, "PATCH": 8, "LOCAL_ACTIVE": 16}
BUDGET_POLICY = "INTEGER_OVERHEAD_PLUS_MEMBER_COST_V1"
BUDGET_MEANING = "NON_AUTHORITATIVE_EXECUTION_BUDGET_HINT_ONLY"


class E35Error(ValueError):
    pass


class _VerifiedInput(dict[str, Any]):
    def __init__(self, value: dict[str, Any], *, kind: str, raw: bytes, binding_raw: bytes | None = None) -> None:
        super().__init__(value)
        self.kind = kind
        self.raw = bytes(raw)
        self.binding_raw = None if binding_raw is None else bytes(binding_raw)


def _require(condition: bool, code: str) -> None:
    if not condition:
        raise E35Error(code)


def _canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def sha256_canonical(value: Any) -> str:
    return hashlib.sha256(_canonical_bytes(value)).hexdigest()


def _git_blob_sha1(raw: bytes) -> str:
    return hashlib.sha1(f"blob {len(raw)}\0".encode("ascii") + raw).hexdigest()


def _verify_blob(raw: bytes, expected: str, code: str) -> None:
    _require(_git_blob_sha1(raw) == expected, code)


def _parse_object(raw: bytes, code: str) -> dict[str, Any]:
    try:
        value = json.loads(raw.decode("utf-8"))
    except Exception as exc:
        raise E35Error(code) from exc
    _require(isinstance(value, dict), code)
    return value


def validate_contract(contract: dict[str, Any]) -> None:
    _require(contract.get("schema") == "distributed_world_simulator.ecology.evo3_e3_5_population_workset_contract.v1", "E3_5_CONTRACT_SCHEMA")
    _require(contract.get("checkpoint") == "ECO.EVO3/E3.5", "E3_5_CONTRACT_CHECKPOINT")
    _require(contract.get("compiler_stage") == "POPULATION_WORKSET", "E3_5_CONTRACT_STAGE")
    _require(contract.get("authority") == AUTHORITY, "E3_5_CONTRACT_AUTHORITY")
    _require(contract.get("canonical_binding_resolved") is False, "E3_5_CONTRACT_CANONICAL_BINDING")
    _require(contract.get("production_binding_authorized") is False, "E3_5_CONTRACT_PRODUCTION_BINDING")
    expected_hash = str(contract.get("contract_hash", ""))
    body = copy.deepcopy(contract)
    body.pop("contract_hash", None)
    _require(sha256_canonical(body) == expected_hash, "E3_5_CONTRACT_HASH")
    accepted = contract.get("accepted_e3_4")
    _require(isinstance(accepted, dict), "E3_5_CONTRACT_ACCEPTED_E3_4")
    _require(accepted.get("artifact_git_blob") == ACCEPTED_E3_4_GIT_BLOB, "E3_5_CONTRACT_E3_4_BLOB")
    _require(contract.get("scale_model", {}).get("levels") == list(SCALE_LEVELS), "E3_5_SCALE_LEVELS")
    _require(contract.get("population_basis", {}).get("individual_entity_truth") is False, "E3_5_INDIVIDUAL_TRUTH_FORBIDDEN")
    _require(contract.get("population_basis", {}).get("population_count_truth") is False, "E3_5_POPULATION_COUNT_TRUTH_FORBIDDEN")
    budget = contract.get("budget_policy", {})
    _require(budget.get("algorithm") == BUDGET_POLICY, "E3_5_BUDGET_POLICY")
    _require(budget.get("overhead_units") == BUDGET_OVERHEAD, "E3_5_BUDGET_OVERHEAD")
    _require(budget.get("per_basis_member_units") == BUDGET_PER_MEMBER, "E3_5_BUDGET_PER_MEMBER")
    _require(budget.get("meaning") == BUDGET_MEANING, "E3_5_BUDGET_MEANING")
    _require(budget.get("global_rng_forbidden") is True, "E3_5_GLOBAL_RNG_POLICY")


def _validate_binding(binding: dict[str, Any], contract: dict[str, Any]) -> None:
    _require(binding.get("schema") == "distributed_world_simulator.ecology.evo3_e3_5_accepted_e3_4_binding.v1", "E3_5_BINDING_SCHEMA")
    _require(binding.get("binding_state") == "ACCEPTED_E3_4_EXACT_INPUT", "E3_5_BINDING_STATE")
    _require(binding.get("authority") == AUTHORITY, "E3_5_BINDING_AUTHORITY")
    _require(binding.get("canonical_binding_resolved") is False, "E3_5_BINDING_CANONICAL")
    _require(binding.get("production_binding_authorized") is False, "E3_5_BINDING_PRODUCTION")
    expected = contract["accepted_e3_4"]
    for key in ("accepted_control_head", "canonical_merge_commit", "artifact_path", "artifact_git_blob", "artifact_sha256", "colonization_program_hash", "provenance_hash", "full_catalog_hash", "review_relay_comment_id"):
        _require(binding.get(key) == expected.get(key), f"E3_5_BINDING_{key.upper()}")


def _validate_e3_4_program(program: dict[str, Any], contract: dict[str, Any]) -> None:
    expected = contract["accepted_e3_4"]
    _require(program.get("schema") == "distributed_world_simulator.ecology.evo3_e3_4_causal_colonization_program.v1", "E3_5_E3_4_SCHEMA")
    _require(program.get("checkpoint") == "ECO.EVO3/E3.4", "E3_5_E3_4_CHECKPOINT")
    _require(program.get("authority") == AUTHORITY, "E3_5_E3_4_AUTHORITY")
    _require(program.get("canonical_binding_resolved") is False, "E3_5_E3_4_CANONICAL")
    _require(program.get("production_binding_authorized") is False, "E3_5_E3_4_PRODUCTION")
    provenance = program.get("provenance")
    _require(isinstance(provenance, dict), "E3_5_E3_4_PROVENANCE")
    _require(sha256_canonical(provenance) == program.get("provenance_hash"), "E3_5_E3_4_PROVENANCE_HASH_CONTENT")
    _require(program.get("provenance_hash") == expected["provenance_hash"], "E3_5_E3_4_PROVENANCE_HASH")
    unhashed = copy.deepcopy(program)
    claimed = unhashed.pop("colonization_program_hash", None)
    _require(sha256_canonical(unhashed) == claimed, "E3_5_E3_4_PROGRAM_HASH_CONTENT")
    _require(claimed == expected["colonization_program_hash"], "E3_5_E3_4_PROGRAM_HASH")
    source_catalog = program.get("source_catalog")
    source_decomposition = program.get("source_decomposition")
    _require(isinstance(source_catalog, dict), "E3_5_E3_4_SOURCE_CATALOG")
    _require(isinstance(source_decomposition, dict), "E3_5_E3_4_SOURCE_DECOMPOSITION")
    _require(source_catalog.get("catalog_hash") == expected["full_catalog_hash"], "E3_5_E3_4_CATALOG_HASH")
    _require(source_decomposition.get("decomposition_hash") == expected["decomposition_hash"], "E3_5_E3_4_DECOMPOSITION_HASH")
    _require(program.get("colonization_result") in {"COLONIZATION_PRESENT", "NO_COLONIZATION"}, "E3_5_E3_4_RESULT")
    manifest = program.get("input_species_manifest")
    species_programs = program.get("species_programs")
    _require(isinstance(manifest, list), "E3_5_E3_4_SPECIES_MANIFEST")
    _require(isinstance(species_programs, list), "E3_5_E3_4_SPECIES_PROGRAMS")
    manifest_ids = sorted(str(entry.get("research_species_id", "")) for entry in manifest if isinstance(entry, dict))
    program_ids = sorted(str(entry.get("research_species_id", "")) for entry in species_programs if isinstance(entry, dict))
    _require(manifest_ids == program_ids, "E3_5_E3_4_SPECIES_COVERAGE")


def load_contract(path: pathlib.Path) -> _VerifiedInput:
    raw = path.read_bytes()
    _verify_blob(raw, CONTRACT_GIT_BLOB, "E3_5_CONTRACT_GIT_BLOB")
    value = _parse_object(raw, "E3_5_CONTRACT_ROOT")
    validate_contract(value)
    return _VerifiedInput(value, kind="contract", raw=raw)


def load_accepted_e3_4(path: pathlib.Path, binding_path: pathlib.Path, contract: dict[str, Any]) -> _VerifiedInput:
    _require(isinstance(contract, _VerifiedInput) and contract.kind == "contract", "E3_5_EXACT_RAW_CONTRACT_REQUIRED")
    binding_raw = binding_path.read_bytes()
    program_raw = path.read_bytes()
    _verify_blob(binding_raw, BINDING_GIT_BLOB, "E3_5_BINDING_GIT_BLOB")
    _verify_blob(program_raw, ACCEPTED_E3_4_GIT_BLOB, "E3_5_E3_4_GIT_BLOB")
    binding = _parse_object(binding_raw, "E3_5_BINDING_ROOT")
    _validate_binding(binding, contract)
    _require(hashlib.sha256(program_raw).hexdigest() == contract["accepted_e3_4"]["artifact_sha256"], "E3_5_E3_4_ARTIFACT_SHA256")
    program = _parse_object(program_raw, "E3_5_E3_4_ROOT")
    _validate_e3_4_program(program, contract)
    return _VerifiedInput(program, kind="accepted_e3_4", raw=program_raw, binding_raw=binding_raw)


def _basis_key(species_id: str, patch_id: str) -> str:
    token = hashlib.sha256(f"{species_id}|{patch_id}".encode("utf-8")).hexdigest()[:24]
    return f"eco-evo3/e3.5/basis/{token}"


def _scheduling_region_id(patch_ids: list[str]) -> str:
    token = hashlib.sha256("\n".join(sorted(patch_ids)).encode("utf-8")).hexdigest()[:24]
    return f"eco-evo3/e3.5/scheduling-region/{token}"


def _work_unit_id(scale: str, basis_keys: list[str]) -> str:
    slug = scale.lower().replace("_", "-")
    token = hashlib.sha256((scale + "\n" + "\n".join(sorted(basis_keys))).encode("utf-8")).hexdigest()[:24]
    return f"eco-evo3/e3.5/work/{slug}/{token}"


def _connected_components(patch_ids: set[str], edges: set[tuple[str, str]]) -> list[list[str]]:
    adjacency = {patch_id: set() for patch_id in patch_ids}
    for a, b in edges:
        if a in adjacency and b in adjacency and a != b:
            adjacency[a].add(b)
            adjacency[b].add(a)
    components: list[list[str]] = []
    remaining = set(patch_ids)
    while remaining:
        start = min(remaining)
        stack = [start]
        component: set[str] = set()
        while stack:
            node = stack.pop()
            if node in component:
                continue
            component.add(node)
            remaining.discard(node)
            stack.extend(sorted(adjacency[node] - component, reverse=True))
        components.append(sorted(component))
    return sorted(components, key=lambda values: tuple(values))


def _derive_core(program: dict[str, Any], contract: dict[str, Any]) -> dict[str, Any]:
    species_programs = program.get("species_programs", [])
    _require(isinstance(species_programs, list), "E3_5_SPECIES_PROGRAMS")
    basis_records: dict[str, dict[str, Any]] = {}
    patch_to_spatial: dict[str, str] = {}
    edges: set[tuple[str, str]] = set()
    for species in sorted((item for item in species_programs if isinstance(item, dict)), key=lambda item: str(item.get("research_species_id", ""))):
        species_id = str(species.get("research_species_id", ""))
        _require(species_id.startswith("eco-research-species/"), "E3_5_SPECIES_ID")
        evaluations = species.get("patch_evaluations")
        declared = species.get("established_patch_ids")
        _require(isinstance(evaluations, list), "E3_5_PATCH_EVALUATIONS")
        _require(isinstance(declared, list), "E3_5_ESTABLISHED_PATCH_IDS")
        evaluated_established: set[str] = set()
        for evaluation in evaluations:
            _require(isinstance(evaluation, dict), "E3_5_PATCH_EVALUATION_TYPE")
            patch_id = str(evaluation.get("research_patch_id", ""))
            spatial_key = str(evaluation.get("stable_spatial_key", ""))
            decision = str(evaluation.get("decision", ""))
            _require(patch_id.startswith("eco-evo3/e3.3/patch/"), "E3_5_PATCH_ID")
            _require(bool(spatial_key), "E3_5_STABLE_SPATIAL_KEY")
            if patch_id in patch_to_spatial:
                _require(patch_to_spatial[patch_id] == spatial_key, "E3_5_PATCH_SPATIAL_IDENTITY_CONFLICT")
            else:
                patch_to_spatial[patch_id] = spatial_key
            if decision != "ESTABLISHED":
                continue
            evaluated_established.add(patch_id)
            key = _basis_key(species_id, patch_id)
            _require(key not in basis_records, "E3_5_DUPLICATE_BASIS")
            basis_records[key] = {
                "basis_key": key,
                "research_species_id": species_id,
                "research_patch_id": patch_id,
                "stable_spatial_key": spatial_key,
                "source_decision": "ESTABLISHED",
            }
            origin = str(evaluation.get("route_origin_patch_id", ""))
            if origin:
                edge = tuple(sorted((origin, patch_id)))
                if edge[0] != edge[1]:
                    edges.add(edge)
        _require(evaluated_established == {str(value) for value in declared}, "E3_5_ESTABLISHED_DECLARATION_MISMATCH")
    basis = sorted(basis_records.values(), key=lambda item: (item["stable_spatial_key"], item["research_species_id"], item["basis_key"]))
    basis_keys = [item["basis_key"] for item in basis]
    active_patch_ids = {item["research_patch_id"] for item in basis}
    active_species_ids = {item["research_species_id"] for item in basis}
    result = str(program.get("colonization_result", ""))
    if result == "NO_COLONIZATION":
        _require(not basis, "E3_5_NO_COLONIZATION_HAS_ACTIVE_BASIS")
    elif result == "COLONIZATION_PRESENT":
        _require(bool(basis), "E3_5_COLONIZATION_PRESENT_WITHOUT_BASIS")
    else:
        raise E35Error("E3_5_UNKNOWN_COLONIZATION_RESULT")
    source_decomposition = program.get("source_decomposition", {})
    planet_id = str(source_decomposition.get("stable_planet_identity", ""))
    time_key = str(source_decomposition.get("stable_time_key", ""))
    _require(bool(planet_id) and bool(time_key), "E3_5_SOURCE_IDENTITY")
    if not basis:
        return {
            "workset_result": "NO_ACTIVE_POPULATION_WORK",
            "work_basis_manifest": [],
            "population_work_units": [],
            "execution_budget_hints": [],
            "summary": {
                "active_basis_count": 0,
                "active_species_count": 0,
                "active_patch_count": 0,
                "active_scheduling_region_count": 0,
                "planet_work_unit_count": 0,
                "region_work_unit_count": 0,
                "patch_work_unit_count": 0,
                "local_active_work_unit_count": 0,
                "total_work_unit_count": 0,
                "budget_hint_count": 0,
                "individual_entity_count": 0,
            },
        }
    components = _connected_components(active_patch_ids, edges)
    groups: list[tuple[str, list[str], str | None]] = [("PLANET", list(basis_keys), None)]
    for component in components:
        component_set = set(component)
        keys = [item["basis_key"] for item in basis if item["research_patch_id"] in component_set]
        groups.append(("REGION", keys, _scheduling_region_id(component)))
    for patch_id in sorted(active_patch_ids, key=lambda value: patch_to_spatial[value]):
        keys = [item["basis_key"] for item in basis if item["research_patch_id"] == patch_id]
        groups.append(("PATCH", keys, None))
        groups.append(("LOCAL_ACTIVE", keys, None))
    basis_by_key = {item["basis_key"]: item for item in basis}
    work_units: list[dict[str, Any]] = []
    budget_hints: list[dict[str, Any]] = []
    for scale, keys, scheduling_region in groups:
        keys = sorted(keys)
        spatial_keys = sorted({basis_by_key[key]["stable_spatial_key"] for key in keys})
        unit = {
            "work_unit_id": _work_unit_id(scale, keys),
            "scale": scale,
            "basis_keys": keys,
            "aggregate_member_count": len(keys),
            "stable_planet_identity": planet_id,
            "stable_spatial_keys": spatial_keys,
            "representation": REPRESENTATIONS[scale],
            "authority": SCHEDULING_AUTHORITY,
        }
        if scheduling_region is not None:
            unit["scheduling_region_id"] = scheduling_region
        work_units.append(unit)
        budget_hints.append({
            "work_unit_id": unit["work_unit_id"],
            "scale": scale,
            "budget_units": BUDGET_OVERHEAD[scale] + len(keys) * BUDGET_PER_MEMBER[scale],
            "policy": BUDGET_POLICY,
            "meaning": BUDGET_MEANING,
        })
    scale_order = {"PLANET": 0, "REGION": 1, "PATCH": 2, "LOCAL_ACTIVE": 3}
    work_units.sort(key=lambda item: (scale_order[item["scale"]], item["work_unit_id"]))
    budget_hints.sort(key=lambda item: (scale_order[item["scale"]], item["work_unit_id"]))
    expected_keys = sorted(basis_keys)
    for scale in SCALE_LEVELS:
        covered = sorted(key for unit in work_units if unit["scale"] == scale for key in unit["basis_keys"])
        _require(covered == expected_keys, f"E3_5_{scale}_COVERAGE")
    counts = {scale: sum(1 for item in work_units if item["scale"] == scale) for scale in SCALE_LEVELS}
    return {
        "workset_result": "ACTIVE_WORKSETS",
        "work_basis_manifest": basis,
        "population_work_units": work_units,
        "execution_budget_hints": budget_hints,
        "summary": {
            "active_basis_count": len(basis),
            "active_species_count": len(active_species_ids),
            "active_patch_count": len(active_patch_ids),
            "active_scheduling_region_count": len(components),
            "planet_work_unit_count": counts["PLANET"],
            "region_work_unit_count": counts["REGION"],
            "patch_work_unit_count": counts["PATCH"],
            "local_active_work_unit_count": counts["LOCAL_ACTIVE"],
            "total_work_unit_count": len(work_units),
            "budget_hint_count": len(budget_hints),
            "individual_entity_count": 0,
        },
    }


def _unverified_output(program: dict[str, Any], contract: dict[str, Any]) -> dict[str, Any]:
    derived = _derive_core(program, contract)
    return {
        "schema": OUTPUT_SCHEMA,
        "checkpoint": "ECO.EVO3/E3.5",
        "compiler_stage": "POPULATION_WORKSET",
        "authority": UNVERIFIED_AUTHORITY,
        "canonical_binding_resolved": False,
        "production_binding_authorized": False,
        **derived,
        "provenance": {"input_verification": UNVERIFIED_AUTHORITY},
    }


def _reparse_verified_inputs(contract_input: _VerifiedInput, program_input: _VerifiedInput) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any], bytes]:
    _require(contract_input.kind == "contract", "E3_5_EXACT_RAW_CONTRACT_REQUIRED")
    _require(program_input.kind == "accepted_e3_4", "E3_5_EXACT_RAW_E3_4_REQUIRED")
    _require(program_input.binding_raw is not None, "E3_5_EXACT_RAW_BINDING_REQUIRED")
    contract_raw = contract_input.raw
    binding_raw = program_input.binding_raw
    program_raw = program_input.raw
    _verify_blob(contract_raw, CONTRACT_GIT_BLOB, "E3_5_CONTRACT_GIT_BLOB")
    _verify_blob(binding_raw, BINDING_GIT_BLOB, "E3_5_BINDING_GIT_BLOB")
    _verify_blob(program_raw, ACCEPTED_E3_4_GIT_BLOB, "E3_5_E3_4_GIT_BLOB")
    contract = _parse_object(contract_raw, "E3_5_CONTRACT_ROOT")
    validate_contract(contract)
    binding = _parse_object(binding_raw, "E3_5_BINDING_ROOT")
    _validate_binding(binding, contract)
    _require(hashlib.sha256(program_raw).hexdigest() == contract["accepted_e3_4"]["artifact_sha256"], "E3_5_E3_4_ARTIFACT_SHA256")
    program = _parse_object(program_raw, "E3_5_E3_4_ROOT")
    _validate_e3_4_program(program, contract)
    return contract, binding, program, program_raw


def build_population_workset(contract: dict[str, Any], program: dict[str, Any]) -> dict[str, Any]:
    if not (
        isinstance(contract, _VerifiedInput)
        and contract.kind == "contract"
        and isinstance(program, _VerifiedInput)
        and program.kind == "accepted_e3_4"
    ):
        return _unverified_output(program, contract)
    contract_value, binding, program_value, program_raw = _reparse_verified_inputs(contract, program)
    derived = _derive_core(program_value, contract_value)
    source = program_value["source_decomposition"]
    accepted = contract_value["accepted_e3_4"]
    output: dict[str, Any] = {
        "schema": OUTPUT_SCHEMA,
        "checkpoint": "ECO.EVO3/E3.5",
        "compiler_stage": "POPULATION_WORKSET",
        "authority": AUTHORITY,
        "canonical_binding_resolved": False,
        "production_binding_authorized": False,
        **derived,
        "source_colonization_program": {
            "colonization_program_hash": program_value["colonization_program_hash"],
            "provenance_hash": program_value["provenance_hash"],
            "artifact_sha256": hashlib.sha256(program_raw).hexdigest(),
            "git_blob": ACCEPTED_E3_4_GIT_BLOB,
            "accepted_control_head": binding["accepted_control_head"],
            "canonical_merge_commit": binding["canonical_merge_commit"],
            "colonization_result": program_value["colonization_result"],
            "stable_planet_identity": source["stable_planet_identity"],
            "stable_time_key": source["stable_time_key"],
        },
        "provenance": {
            "contract_hash": contract_value["contract_hash"],
            "accepted_e3_4_program_hash": program_value["colonization_program_hash"],
            "accepted_e3_4_provenance_hash": program_value["provenance_hash"],
            "accepted_e3_4_artifact_sha256": accepted["artifact_sha256"],
            "accepted_e3_4_git_blob": accepted["artifact_git_blob"],
            "accepted_e3_4_control_head": accepted["accepted_control_head"],
            "accepted_e3_4_merge_commit": accepted["canonical_merge_commit"],
            "full_persisted_evo2_catalog_hash": accepted["full_catalog_hash"],
            "input_verification": "EXACT_ACCEPTED_E3_4_RAW_BYTES_VERIFIED",
        },
        "population_workset_hash_algorithm": "SHA256_CANONICAL_JSON_SORTED_KEYS_V1",
    }
    output["provenance_hash"] = sha256_canonical(output["provenance"])
    output["population_workset_hash"] = sha256_canonical(output)
    return output


def _assert_exact_keys(value: dict[str, Any], expected: set[str], code: str) -> None:
    _require(set(value) == expected, code)


def validate_output_integrity(output: dict[str, Any]) -> None:
    _require(isinstance(output, dict), "E3_5_OUTPUT_ROOT")
    _assert_exact_keys(output, {
        "schema", "checkpoint", "compiler_stage", "authority", "canonical_binding_resolved",
        "production_binding_authorized", "workset_result", "source_colonization_program",
        "work_basis_manifest", "population_work_units", "execution_budget_hints", "summary",
        "provenance", "provenance_hash", "population_workset_hash", "population_workset_hash_algorithm",
    }, "E3_5_OUTPUT_TOP_LEVEL_FIELDS")
    _require(output.get("schema") == OUTPUT_SCHEMA, "E3_5_OUTPUT_SCHEMA")
    _require(output.get("checkpoint") == "ECO.EVO3/E3.5", "E3_5_OUTPUT_CHECKPOINT")
    _require(output.get("compiler_stage") == "POPULATION_WORKSET", "E3_5_OUTPUT_STAGE")
    _require(output.get("authority") == AUTHORITY, "E3_5_OUTPUT_AUTHORITY")
    _require(output.get("canonical_binding_resolved") is False, "E3_5_OUTPUT_CANONICAL_BINDING")
    _require(output.get("production_binding_authorized") is False, "E3_5_OUTPUT_PRODUCTION_BINDING")
    _require(output.get("population_workset_hash_algorithm") == "SHA256_CANONICAL_JSON_SORTED_KEYS_V1", "E3_5_OUTPUT_HASH_ALGORITHM")

    source = output.get("source_colonization_program")
    _require(isinstance(source, dict), "E3_5_OUTPUT_SOURCE")
    _assert_exact_keys(source, {
        "colonization_program_hash", "provenance_hash", "artifact_sha256", "git_blob",
        "accepted_control_head", "canonical_merge_commit", "colonization_result",
        "stable_planet_identity", "stable_time_key",
    }, "E3_5_OUTPUT_SOURCE_FIELDS")
    _require(source.get("git_blob") == ACCEPTED_E3_4_GIT_BLOB, "E3_5_OUTPUT_SOURCE_GIT_BLOB")
    _require(source.get("colonization_result") in {"COLONIZATION_PRESENT", "NO_COLONIZATION"}, "E3_5_OUTPUT_SOURCE_RESULT")
    _require(bool(source.get("stable_planet_identity")) and bool(source.get("stable_time_key")), "E3_5_OUTPUT_SOURCE_IDENTITY")

    provenance = output.get("provenance")
    _require(isinstance(provenance, dict), "E3_5_OUTPUT_PROVENANCE")
    _assert_exact_keys(provenance, {
        "contract_hash", "accepted_e3_4_program_hash", "accepted_e3_4_provenance_hash",
        "accepted_e3_4_artifact_sha256", "accepted_e3_4_git_blob", "accepted_e3_4_control_head",
        "accepted_e3_4_merge_commit", "full_persisted_evo2_catalog_hash", "input_verification",
    }, "E3_5_OUTPUT_PROVENANCE_FIELDS")
    _require(provenance.get("input_verification") == "EXACT_ACCEPTED_E3_4_RAW_BYTES_VERIFIED", "E3_5_OUTPUT_INPUT_VERIFICATION")
    _require(provenance.get("accepted_e3_4_git_blob") == ACCEPTED_E3_4_GIT_BLOB, "E3_5_OUTPUT_PROVENANCE_GIT_BLOB")
    _require(provenance.get("accepted_e3_4_program_hash") == source.get("colonization_program_hash"), "E3_5_OUTPUT_PROGRAM_LINK")
    _require(provenance.get("accepted_e3_4_provenance_hash") == source.get("provenance_hash"), "E3_5_OUTPUT_SOURCE_PROVENANCE_LINK")
    _require(provenance.get("accepted_e3_4_artifact_sha256") == source.get("artifact_sha256"), "E3_5_OUTPUT_ARTIFACT_LINK")
    _require(provenance.get("accepted_e3_4_control_head") == source.get("accepted_control_head"), "E3_5_OUTPUT_CONTROL_HEAD_LINK")
    _require(provenance.get("accepted_e3_4_merge_commit") == source.get("canonical_merge_commit"), "E3_5_OUTPUT_MERGE_LINK")
    _require(sha256_canonical(provenance) == output.get("provenance_hash"), "E3_5_OUTPUT_PROVENANCE_HASH")

    basis = output.get("work_basis_manifest")
    work_units = output.get("population_work_units")
    hints = output.get("execution_budget_hints")
    summary = output.get("summary")
    _require(isinstance(basis, list), "E3_5_OUTPUT_BASIS_LIST")
    _require(isinstance(work_units, list), "E3_5_OUTPUT_WORK_UNITS_LIST")
    _require(isinstance(hints, list), "E3_5_OUTPUT_HINTS_LIST")
    _require(isinstance(summary, dict), "E3_5_OUTPUT_SUMMARY")
    _assert_exact_keys(summary, {
        "active_basis_count", "active_species_count", "active_patch_count", "active_scheduling_region_count",
        "planet_work_unit_count", "region_work_unit_count", "patch_work_unit_count",
        "local_active_work_unit_count", "total_work_unit_count", "budget_hint_count", "individual_entity_count",
    }, "E3_5_OUTPUT_SUMMARY_FIELDS")
    _require(summary.get("individual_entity_count") == 0, "E3_5_OUTPUT_INDIVIDUAL_TRUTH")

    basis_by_key: dict[str, dict[str, Any]] = {}
    species_ids: set[str] = set()
    patch_ids: set[str] = set()
    for item in basis:
        _require(isinstance(item, dict), "E3_5_OUTPUT_BASIS_TYPE")
        _assert_exact_keys(item, {"basis_key", "research_species_id", "research_patch_id", "stable_spatial_key", "source_decision"}, "E3_5_OUTPUT_BASIS_FIELDS")
        species_id = str(item.get("research_species_id", ""))
        patch_id = str(item.get("research_patch_id", ""))
        basis_key = str(item.get("basis_key", ""))
        _require(species_id.startswith("eco-research-species/"), "E3_5_OUTPUT_BASIS_SPECIES_ID")
        _require(patch_id.startswith("eco-evo3/e3.3/patch/"), "E3_5_OUTPUT_BASIS_PATCH_ID")
        _require(bool(item.get("stable_spatial_key")), "E3_5_OUTPUT_BASIS_SPATIAL_KEY")
        _require(item.get("source_decision") == "ESTABLISHED", "E3_5_OUTPUT_BASIS_DECISION")
        _require(basis_key == _basis_key(species_id, patch_id), "E3_5_OUTPUT_BASIS_KEY")
        _require(basis_key not in basis_by_key, "E3_5_OUTPUT_DUPLICATE_BASIS_KEY")
        basis_by_key[basis_key] = item
        species_ids.add(species_id)
        patch_ids.add(patch_id)

    expected_basis_keys = sorted(basis_by_key)
    work_ids: set[str] = set()
    counts = {scale: 0 for scale in SCALE_LEVELS}
    for unit in work_units:
        _require(isinstance(unit, dict), "E3_5_OUTPUT_WORK_UNIT_TYPE")
        scale = str(unit.get("scale", ""))
        _require(scale in SCALE_LEVELS, "E3_5_OUTPUT_WORK_UNIT_SCALE")
        expected_fields = {"work_unit_id", "scale", "basis_keys", "aggregate_member_count", "stable_planet_identity", "stable_spatial_keys", "representation", "authority"}
        if scale == "REGION":
            expected_fields.add("scheduling_region_id")
        _assert_exact_keys(unit, expected_fields, "E3_5_OUTPUT_WORK_UNIT_FIELDS")
        _require(unit.get("authority") == SCHEDULING_AUTHORITY, "E3_5_OUTPUT_WORK_UNIT_AUTHORITY")
        _require(unit.get("representation") == REPRESENTATIONS[scale], "E3_5_OUTPUT_WORK_UNIT_REPRESENTATION")
        keys = unit.get("basis_keys")
        _require(isinstance(keys, list) and keys, "E3_5_OUTPUT_WORK_UNIT_BASIS_KEYS")
        _require(len(keys) == len(set(keys)), "E3_5_OUTPUT_WORK_UNIT_DUPLICATE_BASIS")
        _require(all(key in basis_by_key for key in keys), "E3_5_OUTPUT_WORK_UNIT_UNKNOWN_BASIS")
        _require(unit.get("aggregate_member_count") == len(keys), "E3_5_OUTPUT_WORK_UNIT_MEMBER_COUNT")
        _require(unit.get("stable_planet_identity") == source.get("stable_planet_identity"), "E3_5_OUTPUT_WORK_UNIT_PLANET")
        spatial_keys = sorted({str(basis_by_key[key]["stable_spatial_key"]) for key in keys})
        _require(unit.get("stable_spatial_keys") == spatial_keys, "E3_5_OUTPUT_WORK_UNIT_SPATIAL_KEYS")
        work_unit_id = str(unit.get("work_unit_id", ""))
        _require(work_unit_id == _work_unit_id(scale, list(keys)), "E3_5_OUTPUT_WORK_UNIT_ID")
        _require(work_unit_id not in work_ids, "E3_5_OUTPUT_DUPLICATE_WORK_UNIT_ID")
        work_ids.add(work_unit_id)
        if scale == "REGION":
            region_patch_ids = sorted({str(basis_by_key[key]["research_patch_id"]) for key in keys})
            _require(unit.get("scheduling_region_id") == _scheduling_region_id(region_patch_ids), "E3_5_OUTPUT_REGION_ID")
        elif scale in {"PATCH", "LOCAL_ACTIVE"}:
            _require(len({basis_by_key[key]["research_patch_id"] for key in keys}) == 1, "E3_5_OUTPUT_PATCH_SCOPE")
        counts[scale] += 1

    for scale in SCALE_LEVELS:
        covered = sorted(key for unit in work_units if unit["scale"] == scale for key in unit["basis_keys"])
        _require(covered == expected_basis_keys, f"E3_5_OUTPUT_{scale}_COVERAGE")

    hint_ids: set[str] = set()
    for hint in hints:
        _require(isinstance(hint, dict), "E3_5_OUTPUT_HINT_TYPE")
        _assert_exact_keys(hint, {"work_unit_id", "scale", "budget_units", "policy", "meaning"}, "E3_5_OUTPUT_HINT_FIELDS")
        work_id = str(hint.get("work_unit_id", ""))
        _require(work_id in work_ids, "E3_5_OUTPUT_HINT_UNKNOWN_WORK_UNIT")
        _require(work_id not in hint_ids, "E3_5_OUTPUT_DUPLICATE_HINT")
        hint_ids.add(work_id)
        matching = next(unit for unit in work_units if unit["work_unit_id"] == work_id)
        scale = matching["scale"]
        _require(hint.get("scale") == scale, "E3_5_OUTPUT_HINT_SCALE")
        _require(hint.get("policy") == BUDGET_POLICY, "E3_5_OUTPUT_HINT_POLICY")
        _require(hint.get("meaning") == BUDGET_MEANING, "E3_5_OUTPUT_HINT_MEANING")
        expected_budget = BUDGET_OVERHEAD[scale] + matching["aggregate_member_count"] * BUDGET_PER_MEMBER[scale]
        _require(hint.get("budget_units") == expected_budget, "E3_5_OUTPUT_HINT_BUDGET")

    _require(work_ids == hint_ids, "E3_5_OUTPUT_BUDGET_LINKS")
    expected_summary = {
        "active_basis_count": len(basis),
        "active_species_count": len(species_ids),
        "active_patch_count": len(patch_ids),
        "active_scheduling_region_count": counts["REGION"],
        "planet_work_unit_count": counts["PLANET"],
        "region_work_unit_count": counts["REGION"],
        "patch_work_unit_count": counts["PATCH"],
        "local_active_work_unit_count": counts["LOCAL_ACTIVE"],
        "total_work_unit_count": len(work_units),
        "budget_hint_count": len(hints),
        "individual_entity_count": 0,
    }
    _require(summary == expected_summary, "E3_5_OUTPUT_SUMMARY_CONTENT")
    if output.get("workset_result") == "NO_ACTIVE_POPULATION_WORK":
        _require(source.get("colonization_result") == "NO_COLONIZATION", "E3_5_OUTPUT_EMPTY_SOURCE_RESULT")
        _require(not basis and not work_units and not hints, "E3_5_OUTPUT_EMPTY_CONTENT")
    elif output.get("workset_result") == "ACTIVE_WORKSETS":
        _require(source.get("colonization_result") == "COLONIZATION_PRESENT", "E3_5_OUTPUT_ACTIVE_SOURCE_RESULT")
        _require(bool(basis), "E3_5_OUTPUT_ACTIVE_WITHOUT_BASIS")
        _require(counts["PLANET"] == 1 and counts["PATCH"] == len(patch_ids) and counts["LOCAL_ACTIVE"] == len(patch_ids), "E3_5_OUTPUT_SCALE_COUNTS")
    else:
        raise E35Error("E3_5_OUTPUT_WORKSET_RESULT")

    unhashed = copy.deepcopy(output)
    claimed = unhashed.pop("population_workset_hash", None)
    _require(sha256_canonical(unhashed) == claimed, "E3_5_OUTPUT_WORKSET_HASH")


def serialize_workset(output: dict[str, Any]) -> bytes:
    validate_output_integrity(output)
    return _canonical_bytes(output) + b"\n"


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", type=pathlib.Path, default=_REPO_ROOT / "config/ecology/eco-evo3-e3-5-population-workset-contract.v1.json")
    parser.add_argument("--accepted-e3-4-binding", type=pathlib.Path, default=_REPO_ROOT / "config/ecology/accepted_inputs/e3_4_accepted_causal_colonization_program.binding.v1.json")
    parser.add_argument("--accepted-e3-4", type=pathlib.Path, default=_REPO_ROOT / "config/ecology/accepted_inputs/e3_4_candidate_causal_colonization_program.v1.json")
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--quiet", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    contract = load_contract(args.contract)
    program = load_accepted_e3_4(args.accepted_e3_4, args.accepted_e3_4_binding, contract)
    output = build_population_workset(contract, program)
    data = serialize_workset(output)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(data)
    if not args.quiet:
        print("ECO.EVO3 E3.5 Multi-scale Population Workset Compiler: PASS")
        print(f"workset_result={output['workset_result']}")
        print(f"active_basis_count={output['summary']['active_basis_count']}")
        print(f"active_species_count={output['summary']['active_species_count']}")
        print(f"active_patch_count={output['summary']['active_patch_count']}")
        print(f"active_scheduling_region_count={output['summary']['active_scheduling_region_count']}")
        print(f"total_work_unit_count={output['summary']['total_work_unit_count']}")
        print(f"population_workset_hash={output['population_workset_hash']}")
        print(f"provenance_hash={output['provenance_hash']}")
        print(f"artifact_sha256={hashlib.sha256(data).hexdigest()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

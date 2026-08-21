from __future__ import annotations

import copy
import hashlib
import json
import pathlib
from typing import Any, Dict, Iterable, List, Tuple

SCHEMA = "distributed_world_simulator.ecology.xfer0_contract.v1"
VERSION = "1.0.0"
CHECKPOINT = "ECO.XFER0"
EXPECTED_BRANCH = "feature/eco-evolutionary-ecology"
EXPECTED_PARENT_FINAL_HEAD = "376796ab8c8370b7370fcd220ed207d07955cb42"
EXPECTED_PARENT_FINAL_DURABLE_HEAD = "3367615b8ad5fed59ac13ac6fcc215e36155b27d"
EXPECTED_FINAL_AGGREGATE = "6daab256af3d1e7693c66a8afaad4d04fd1564c4376b9f3cd747a268a10c2250"
EXPECTED_FINAL_EVIDENCE = "989e5ae02e66052ca7d2e46f5f452446300ba625dd4efd5cd6b5ffd9db2f2cd1"
EXPECTED_E28_CATALOG = "5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219"
EXPECTED_E28_AGGREGATE = "4182176c1cc8b6d609fefc7057b5ff5307c92f839682e76f6168841d60275061"
EXPECTED_E28_TRANSPORT = "b31c863f8e1943e5778d56631f8c8ad75b95f3b9d3930a699f80fd07595d45d1"
REQUIRED_FOUNDATIONS = ["G", "ENV", "MAT", "WQ", "SD", "TF"]
REQUIRED_INTERFACES = [
    "ENVIRONMENT_INPUT",
    "ECOLOGY_STATE_OUTPUT",
    "QUERY_PROJECTION",
    "PERSISTENCE_PAYLOAD",
    "IDENTITY_PROVENANCE",
    "REPRESENTATION_PROMOTION_REQUEST",
]
BINDING_MODE = "SEMANTIC_ONLY_NO_PRODUCTION_API_BINDING"
HASH_ALGORITHM = "SHA256_CANONICAL_JSON_SORTED_KEYS_V1"
FORBIDDEN_OWNERSHIP = {
    "GEOLOGY_OR_TERRAIN_TRUTH",
    "ENVIRONMENT_TRUTH",
    "MATERIAL_ONTOLOGY",
    "WORLD_QUERY_FABRIC",
    "SPATIAL_DOMAIN_FABRIC",
    "TIME_FABRIC",
    "GENERIC_POPULATION_RUNTIME",
    "WORLD_LIFECYCLE_FABRIC",
    "WORLD_WORK_BUDGET",
    "AUTHORITY_FOUNDATION",
    "NETWORK_REPLICATION_POLICY",
    "PRODUCTION_PERSISTENCE_DURABILITY",
    "WORLD_TRANSACTION_MODEL",
    "PRESENTATION_MESH_AS_TRUTH",
    "PLANET_WIDE_INDIVIDUAL_ENTITY_TRUTH",
    "CANONICAL_SPECIES_TAXONOMY",
}


def _canonical_hash(value: Dict[str, Any]) -> str:
    payload = copy.deepcopy(value)
    payload.pop("contract_hash", None)
    raw = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def load_contract(path: pathlib.Path) -> Dict[str, Any]:
    with path.open("r", encoding="utf-8") as fh:
        value = json.load(fh)
    if not isinstance(value, dict):
        raise ValueError("contract root must be an object")
    return value


def _require(condition: bool, errors: List[str], code: str) -> None:
    if not condition:
        errors.append(code)


def _interface_map(contract: Dict[str, Any], errors: List[str]) -> Dict[str, Dict[str, Any]]:
    raw = contract.get("interfaces")
    _require(isinstance(raw, list), errors, "INTERFACES_NOT_ARRAY")
    if not isinstance(raw, list):
        return {}
    result: Dict[str, Dict[str, Any]] = {}
    for item in raw:
        if not isinstance(item, dict):
            errors.append("INTERFACE_NOT_OBJECT")
            continue
        interface_id = item.get("id")
        if not isinstance(interface_id, str) or not interface_id:
            errors.append("INTERFACE_ID_INVALID")
            continue
        if interface_id in result:
            errors.append(f"INTERFACE_DUPLICATE:{interface_id}")
            continue
        result[interface_id] = item
    return result


def validate_contract(contract: Dict[str, Any]) -> Tuple[bool, List[str]]:
    errors: List[str] = []
    _require(contract.get("schema") == SCHEMA, errors, "SCHEMA_MISMATCH")
    _require(contract.get("version") == VERSION, errors, "VERSION_MISMATCH")
    _require(contract.get("checkpoint") == CHECKPOINT, errors, "CHECKPOINT_MISMATCH")
    _require(contract.get("branch") == EXPECTED_BRANCH, errors, "BRANCH_MISMATCH")
    _require(contract.get("research_only") is True, errors, "RESEARCH_ONLY_REQUIRED")
    _require(contract.get("contract_hash_algorithm") == HASH_ALGORITHM, errors, "HASH_ALGORITHM_MISMATCH")
    contract_hash = contract.get("contract_hash")
    _require(isinstance(contract_hash, str) and len(contract_hash) == 64, errors, "CONTRACT_HASH_SHAPE")
    _require(contract_hash == _canonical_hash(contract), errors, "CONTRACT_HASH_MISMATCH")

    parent = contract.get("parent_evo2")
    _require(isinstance(parent, dict), errors, "PARENT_EVO2_REQUIRED")
    if isinstance(parent, dict):
        expected_parent = {
            "final_code_under_test": EXPECTED_PARENT_FINAL_HEAD,
            "final_durable_head": EXPECTED_PARENT_FINAL_DURABLE_HEAD,
            "final_aggregate_hash": EXPECTED_FINAL_AGGREGATE,
            "final_evidence_hash": EXPECTED_FINAL_EVIDENCE,
            "e2_8_catalog_hash": EXPECTED_E28_CATALOG,
            "e2_8_persistence_aggregate": EXPECTED_E28_AGGREGATE,
            "e2_8_transport_sha256": EXPECTED_E28_TRANSPORT,
        }
        for key, expected in expected_parent.items():
            _require(parent.get(key) == expected, errors, f"PARENT_PIN_MISMATCH:{key}")

    scope = contract.get("scope")
    _require(isinstance(scope, dict), errors, "SCOPE_REQUIRED")
    if isinstance(scope, dict):
        _require(scope.get("design_only") is True, errors, "DESIGN_ONLY_REQUIRED")
        for key in [
            "runtime_implementation",
            "production_activation",
            "canonical_owner_mutation",
            "production_path_mutation",
            "network_protocol_mutation",
            "production_persistence_mutation",
            "world_transaction_mutation",
            "canonical_taxonomy_mutation",
            "biome_species_table_allowed",
            "asset_scatter_as_ecology_truth_allowed",
        ]:
            _require(scope.get(key) is False, errors, f"SCOPE_MUST_BE_FALSE:{key}")

    authority = contract.get("authority_model")
    _require(isinstance(authority, dict), errors, "AUTHORITY_MODEL_REQUIRED")
    if isinstance(authority, dict):
        owned = authority.get("eco_research_owns")
        denied = authority.get("eco_must_not_own")
        _require(isinstance(owned, list) and bool(owned), errors, "ECO_RESEARCH_OWNERSHIP_REQUIRED")
        _require(isinstance(denied, list), errors, "ECO_FORBIDDEN_OWNERSHIP_REQUIRED")
        if isinstance(denied, list):
            _require(set(denied) == FORBIDDEN_OWNERSHIP, errors, "FORBIDDEN_OWNERSHIP_SET_MISMATCH")
        if isinstance(owned, list):
            _require(not (set(owned) & FORBIDDEN_OWNERSHIP), errors, "OWNERSHIP_COLLISION")

    foundations = contract.get("canonical_foundation_dependencies")
    _require(isinstance(foundations, dict), errors, "FOUNDATION_DEPENDENCIES_REQUIRED")
    if isinstance(foundations, dict):
        _require(foundations.get("required_before_xfer1") == REQUIRED_FOUNDATIONS, errors, "FOUNDATION_ORDER_OR_SET_MISMATCH")
        _require(foundations.get("binding_state") == "UNRESOLVED_CANONICAL_CONTRACTS", errors, "FOUNDATIONS_MUST_REMAIN_UNRESOLVED")
        _require(foundations.get("binding_mode") == BINDING_MODE, errors, "FOUNDATION_BINDING_MODE_MISMATCH")
        _require(foundations.get("xfer0_may_invent_production_api") is False, errors, "PRODUCTION_API_INVENTION_FORBIDDEN")
        _require(foundations.get("xfer0_may_copy_research_contract_into_owner") is False, errors, "RESEARCH_TO_OWNER_COPY_FORBIDDEN")

    interfaces = _interface_map(contract, errors)
    _require(list(interfaces.keys()) == REQUIRED_INTERFACES, errors, "INTERFACE_ORDER_OR_SET_MISMATCH")
    for interface_id in REQUIRED_INTERFACES:
        item = interfaces.get(interface_id)
        if not item:
            continue
        _require(item.get("binding_mode") == BINDING_MODE, errors, f"INTERFACE_BINDING_MODE:{interface_id}")
        for key in ["required_semantics", "allowed_operations", "forbidden_operations"]:
            value = item.get(key)
            _require(isinstance(value, list) and bool(value) and all(isinstance(x, str) and x for x in value), errors, f"INTERFACE_LIST_INVALID:{interface_id}:{key}")

    env = interfaces.get("ENVIRONMENT_INPUT", {})
    _require(env.get("direction") == "SIMULATOR_TO_ECO", errors, "ENV_DIRECTION")
    _require(env.get("provider_foundations") == REQUIRED_FOUNDATIONS, errors, "ENV_PROVIDER_FOUNDATIONS")
    _require(set(env.get("allowed_operations", [])) <= {"READ_SAMPLE", "READ_REGION_SUMMARY"}, errors, "ENV_WRITE_SURFACE_DETECTED")

    state = interfaces.get("ECOLOGY_STATE_OUTPUT", {})
    _require(state.get("direction") == "ECO_TO_SIMULATOR", errors, "STATE_DIRECTION")
    _require("CREATE_PLANET_WIDE_ENTITY_TRUTH" in state.get("forbidden_operations", []), errors, "STATE_ENTITY_TRUTH_BARRIER_MISSING")
    _require("AUTHORIZE_WORLD_MUTATION" in state.get("forbidden_operations", []), errors, "STATE_WORLD_MUTATION_BARRIER_MISSING")

    query = interfaces.get("QUERY_PROJECTION", {})
    _require(query.get("direction") == "ECO_TO_QUERY_PRESENTATION", errors, "QUERY_DIRECTION")
    _require(set(query.get("allowed_operations", [])) <= {"READ_ONLY_QUERY", "DERIVE_PRESENTATION"}, errors, "QUERY_WRITE_SURFACE_DETECTED")
    _require("MUTATE_ECOLOGY" in query.get("forbidden_operations", []), errors, "QUERY_ECOLOGY_WRITE_BARRIER_MISSING")
    _require("MUTATE_WORLD" in query.get("forbidden_operations", []), errors, "QUERY_WORLD_WRITE_BARRIER_MISSING")

    persistence = interfaces.get("PERSISTENCE_PAYLOAD", {})
    _require(persistence.get("direction") == "ECO_TO_PERSISTENCE_OWNER", errors, "PERSISTENCE_DIRECTION")
    for op in ["OWN_DURABILITY", "CHOOSE_COMMIT_POINT", "WRITE_DISTRIBUTED_LOG", "DECLARE_TRANSACTION_COMMITTED"]:
        _require(op in persistence.get("forbidden_operations", []), errors, f"PERSISTENCE_BARRIER_MISSING:{op}")

    identity = interfaces.get("IDENTITY_PROVENANCE", {})
    _require(identity.get("direction") == "BIDIRECTIONAL_REFERENCE_ONLY", errors, "IDENTITY_DIRECTION")
    _require("PROMOTE_TO_CANONICAL_TAXONOMY" in identity.get("forbidden_operations", []), errors, "TAXONOMY_BARRIER_MISSING")

    promotion = interfaces.get("REPRESENTATION_PROMOTION_REQUEST", {})
    _require(promotion.get("direction") == "ECO_TO_CANONICAL_WORLD_OWNERS", errors, "PROMOTION_DIRECTION")
    _require(promotion.get("allowed_operations") == ["REQUEST_PROMOTION"], errors, "PROMOTION_MUST_BE_REQUEST_ONLY")
    for op in ["CREATE_DURABLE_ENTITY", "ASSIGN_AUTHORITY", "COMMIT_TRANSACTION", "DELETE_POPULATION_TRUTH"]:
        _require(op in promotion.get("forbidden_operations", []), errors, f"PROMOTION_BARRIER_MISSING:{op}")

    invariants = contract.get("handoff_invariants")
    _require(isinstance(invariants, list) and len(invariants) >= 7, errors, "HANDOFF_INVARIANTS_REQUIRED")
    if isinstance(invariants, list):
        joined = "\n".join(str(x) for x in invariants)
        _require("second ecology truth" in joined, errors, "SECOND_TRUTH_BARRIER_MISSING")
        _require("read-only" in joined, errors, "READ_ONLY_PROJECTION_INVARIANT_MISSING")
        _require("durability" in joined, errors, "PERSISTENCE_OWNERSHIP_INVARIANT_MISSING")
        _require("canonical taxonomy" in joined, errors, "TAXONOMY_INVARIANT_MISSING")

    xfer1 = contract.get("xfer1_gate")
    _require(isinstance(xfer1, dict), errors, "XFER1_GATE_REQUIRED")
    if isinstance(xfer1, dict):
        _require(xfer1.get("status") == "BLOCKED_WAIT_CANONICAL_FOUNDATIONS", errors, "XFER1_MUST_REMAIN_BLOCKED")
        _require(xfer1.get("required_foundations") == REQUIRED_FOUNDATIONS, errors, "XFER1_FOUNDATION_SET_MISMATCH")
        _require(xfer1.get("requires_main_owned_contracts") is True, errors, "XFER1_MAIN_OWNED_CONTRACT_GATE_MISSING")
        _require(xfer1.get("requires_explicit_owner_mapping") is True, errors, "XFER1_OWNER_MAPPING_GATE_MISSING")
        _require(xfer1.get("requires_authority_review") is True, errors, "XFER1_AUTHORITY_REVIEW_GATE_MISSING")
        _require(xfer1.get("may_treat_xfer0_as_production_authorization") is False, errors, "XFER0_PRODUCTION_AUTHORIZATION_FORBIDDEN")

    evo3 = contract.get("evo3_gate")
    _require(isinstance(evo3, dict), errors, "EVO3_GATE_REQUIRED")
    if isinstance(evo3, dict):
        _require(evo3.get("after_xfer0_acceptance") == "AUTHORIZED_FOR_RESEARCH_PLANNING_ONLY", errors, "EVO3_RESEARCH_ONLY_GATE")
        _require(evo3.get("production_runtime_authorized") is False, errors, "EVO3_RUNTIME_MUST_REMAIN_UNAUTHORIZED")
        _require(evo3.get("xfer1_required_before_production_binding") is True, errors, "EVO3_XFER1_BINDING_GATE_MISSING")

    acceptance = contract.get("acceptance_requirements")
    _require(isinstance(acceptance, list) and len(acceptance) >= 10, errors, "ACCEPTANCE_REQUIREMENTS_REQUIRED")

    return not errors, errors


def validate_file(path: pathlib.Path) -> Tuple[bool, List[str]]:
    try:
        contract = load_contract(path)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        return False, [f"LOAD_ERROR:{type(exc).__name__}"]
    return validate_contract(contract)


def default_contract_path() -> pathlib.Path:
    return pathlib.Path(__file__).resolve().parents[3] / "config" / "ecology" / "eco-xfer0-contract.v1.json"


def main() -> int:
    path = default_contract_path()
    ok, errors = validate_file(path)
    if ok:
        contract = load_contract(path)
        print("ECO.XFER0 contract validation: PASS")
        print("contract_hash=" + str(contract["contract_hash"]))
        print("interfaces=" + str(len(contract["interfaces"])))
        print("foundations=" + ",".join(contract["canonical_foundation_dependencies"]["required_before_xfer1"]))
        return 0
    print("ECO.XFER0 contract validation: FAIL")
    for error in errors:
        print(error)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

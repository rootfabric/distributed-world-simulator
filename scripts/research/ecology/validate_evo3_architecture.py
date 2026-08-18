from __future__ import annotations

import copy
import hashlib
import json
import pathlib
import sys
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parents[3]
ARCH_PATH = ROOT / "config/ecology/eco-evo3-planetary-ecology-compiler.v1.json"
ROADMAP_PATH = ROOT / "config/ecology/eco-evo3-roadmap.v1.json"

EXPECTED_BRANCH = "feature/eco-evolutionary-ecology"
EXPECTED_XFER0_HEAD = "bb80beac95d838b56cccbe5d98f7e1bcbfd80376"
EXPECTED_XFER0_DURABLE = "66bb9fdb2a5efa0bd7d3cf7f216d042639a60b34"
EXPECTED_XFER0_HASH = "06024c88fba045ba98e74594e55dce717d2c8dcd26f3d6a559a789bb5e39d309"
EXPECTED_XFER0_AGG = "1adf3d0fa733ed74e3a28bfe1d0632f5d45c62ca5df932bce3e55693a18e9044"
EXPECTED_EVO2_FINAL = "6daab256af3d1e7693c66a8afaad4d04fd1564c4376b9f3cd747a268a10c2250"
FOUNDATIONS = ["G", "ENV", "MAT", "WQ", "SD", "TF"]
STAGE_IDS = ["FIELD_INGEST","OPPORTUNITY_FIELD","ECOLOGY_DECOMPOSITION","COLONIZATION_PROGRAM","POPULATION_WORKSET","TEMPORAL_PROGRAM","EVIDENCE_PACKAGE"]
STEP_IDS = ["E3.0","E3.1","E3.2","E3.3","E3.4","E3.5","E3.6","E3.7","E3.8","E3.FINAL"]

class ContractError(ValueError):
    pass

def load(path: pathlib.Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))

def canonical_hash(obj: dict[str, Any], field: str) -> str:
    value = copy.deepcopy(obj)
    value.pop(field, None)
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()

def require(condition: bool, message: str) -> None:
    if not condition:
        raise ContractError(message)

def validate_architecture(a: dict[str, Any]) -> None:
    require(a.get("schema") == "distributed_world_simulator.ecology.evo3_planetary_ecology_compiler.v1", "wrong architecture schema")
    require(a.get("version") == "1.0.0", "wrong architecture version")
    require(a.get("branch") == EXPECTED_BRANCH, "wrong branch")
    require(a.get("program") == "ECO.EVO3", "wrong program")
    require(a.get("status") == "ACCEPTED_RESEARCH_ARCHITECTURE", "architecture not accepted")
    require(a.get("research_only") is True, "research_only must be true")
    p = a.get("parent", {})
    require(p.get("xfer0_code_under_test_head") == EXPECTED_XFER0_HEAD, "wrong XFER0 code parent")
    require(p.get("xfer0_durable_head") == EXPECTED_XFER0_DURABLE, "wrong XFER0 durable parent")
    require(p.get("xfer0_contract_hash") == EXPECTED_XFER0_HASH, "wrong XFER0 contract")
    require(p.get("xfer0_aggregate_hash") == EXPECTED_XFER0_AGG, "wrong XFER0 aggregate")
    require(p.get("evo2_final_aggregate_hash") == EXPECTED_EVO2_FINAL, "wrong EVO2 final aggregate")
    s = a.get("scope", {})
    for key in ["runtime_implementation","production_binding","production_activation","canonical_owner_mutation","canonical_spatial_domain_creation","production_persistence_authority","world_transaction_authority","network_authority","canonical_species_taxonomy","biome_species_table_allowed","asset_scatter_as_ecology_truth_allowed"]:
        require(s.get(key) is False, f"{key} must stay false")
    require(s.get("research_architecture_only") is True, "research_architecture_only must be true")
    ci = a.get("canonical_inputs", {})
    require(ci.get("required_foundations") == FOUNDATIONS, "foundation set/order changed")
    require(ci.get("binding_state") == "UNRESOLVED_CANONICAL_CONTRACTS", "canonical bindings prematurely resolved")
    require(ci.get("binding_mode") == "XFER0_SEMANTIC_ONLY_NO_PRODUCTION_API_BINDING", "production binding invented")
    cat = a.get("catalog_input", {})
    require(cat.get("source") == "EVO2_PERSISTED_RESEARCH_SPECIES_CATALOG_AND_PROVENANCE", "catalog source bypass")
    rules = " ".join(cat.get("rules", [])).lower()
    require("biome" in rules and "may not choose species" in rules, "biome/species prohibition missing")
    require("rebake" in rules and "target-tune" in rules, "catalog retuning prohibition missing")
    ir = a.get("compiler_ir", {})
    require(ir.get("name") == "PlanetEcologyProgram", "wrong IR")
    require(ir.get("authority") == "RESEARCH_DERIVED_NON_AUTHORITATIVE", "IR authority escalation")
    sections = ir.get("required_sections", [])
    require(len(sections) == len(set(sections)) == 9, "IR sections must be unique 9")
    stages = a.get("stages", [])
    require([x.get("id") for x in stages] == STAGE_IDS, "stage order/set changed")
    joined = json.dumps(stages, sort_keys=True).lower()
    require("biome species labels" in joined, "opportunity biome barrier missing")
    require("canonical sd" in joined, "SD barrier missing")
    require("target-aware species injection" in joined, "target-aware barrier missing")
    require("planet-wide individual entity truth" in joined, "individual truth barrier missing")
    require("own canonical time" in joined, "TF barrier missing")
    det = a.get("determinism", {})
    require(det.get("required") is True, "determinism not required")
    require(det.get("program_hash_required") is True, "program hash not required")
    require(det.get("same_inputs_same_program_required") is True, "same-input determinism missing")
    require(det.get("global_rng_consumption_forbidden") is True, "global RNG must be forbidden")
    require(det.get("all_non_deterministic_external_inputs_must_be_snapshot_bound") is True, "external inputs not snapshot bound")
    scale = a.get("scale_model", {})
    require(scale.get("levels") == ["PLANET","REGION","PATCH","LOCAL_ACTIVE"], "scale levels changed")
    require("same ecology state meaning" in scale.get("principle","").lower(), "single state meaning missing")
    barriers = set(a.get("authority_barriers", []))
    required_barriers = {
        "NO_CANONICAL_G_ENV_MAT_WQ_SD_TF_OWNERSHIP","NO_PRODUCTION_PERSISTENCE_OR_TRANSACTION_AUTHORITY",
        "NO_NETWORK_OR_AUTHORITY_ASSIGNMENT","NO_CANONICAL_SPECIES_TAXONOMY_PROMOTION",
        "NO_BIOME_TO_SPECIES_MAPPING","NO_ASSET_SCATTER_AS_ECOLOGY_TRUTH",
        "NO_RESEARCH_REGION_AS_CANONICAL_SD_DOMAIN","NO_COMPILED_SUITABILITY_AS_POPULATION_TRUTH",
        "NO_EVO2_EVIDENCE_AS_PRODUCTION_AUTHORIZATION"
    }
    require(barriers == required_barriers, "authority barrier set changed")
    require(a.get("architecture_hash_algorithm") == "SHA256_CANONICAL_JSON_SORTED_KEYS_V1", "hash algorithm changed")
    require(a.get("architecture_hash") == canonical_hash(a, "architecture_hash"), "architecture hash mismatch")

def _assert_acyclic(steps: list[dict[str, Any]]) -> None:
    graph = {x["id"]: list(x.get("depends_on", [])) for x in steps}
    visiting: set[str] = set()
    done: set[str] = set()
    def visit(node: str) -> None:
        if node in done: return
        if node in visiting: raise ContractError("roadmap dependency cycle")
        visiting.add(node)
        for dep in graph[node]:
            require(dep in graph, f"unknown dependency {dep}")
            visit(dep)
        visiting.remove(node); done.add(node)
    for node in graph: visit(node)

def validate_roadmap(r: dict[str, Any], a: dict[str, Any]) -> None:
    require(r.get("schema") == "distributed_world_simulator.ecology.evo3_roadmap.v1", "wrong roadmap schema")
    require(r.get("version") == "1.0.0", "wrong roadmap version")
    require(r.get("branch") == EXPECTED_BRANCH, "roadmap branch mismatch")
    require(r.get("program") == "ECO.EVO3", "roadmap program mismatch")
    require(r.get("status") == "RESEARCH_ROADMAP_ACCEPTED_E3_0_CURRENT", "roadmap status mismatch")
    require(r.get("parent_architecture_revision") == a.get("revision"), "roadmap architecture mismatch")
    require(r.get("parent_xfer0_contract_hash") == EXPECTED_XFER0_HASH, "roadmap XFER0 mismatch")
    policy = r.get("execution_policy", {})
    for key in ["sequential","no_stage_skip","post_freeze_executable_drift_requires_reverification","production_binding_forbidden_until_xfer1","independent_role_not_implicit"]:
        require(policy.get(key) is True, f"roadmap policy {key} must be true")
    steps = r.get("steps", [])
    require([x.get("id") for x in steps] == STEP_IDS, "checkpoint order/set changed")
    require(steps[0].get("status") == "ACCEPTED", "E3.0 not accepted")
    require(steps[1].get("status") == "AUTHORIZED_NOT_STARTED", "E3.1 must be current")
    require(all(x.get("status") == "BLOCKED" for x in steps[2:]), "later steps must stay blocked")
    for i in range(1, len(steps)):
        require(steps[i].get("depends_on") == [steps[i-1]["id"]], f"{steps[i]['id']} must depend only on predecessor")
    _assert_acyclic(steps)
    rules = r.get("checkpoint_rules", {})
    for key, expected in {
        "e3_1_must_use_semantic_adapter_not_production_api":True,
        "e3_2_may_not_emit_species_assignment":True,
        "e3_3_region_ids_must_be_research_namespaced":True,
        "e3_4_full_catalog_input_required":True,
        "e3_4_null_no_colonization_valid":True,
        "e3_5_planet_wide_individual_truth_forbidden":True,
        "e3_6_canonical_time_environment_ownership_forbidden":True,
        "e3_7_fresh_process_determinism_required":True,
        "e3_8_predeclared_planet_matrix_required":True,
        "final_no_rebake_target_tuning_biome_table_or_asset_scatter":True}.items():
        require(rules.get(key) is expected, f"checkpoint rule {key} changed")
    xr = r.get("xfer1_relation", {})
    require(xr.get("status") == "BLOCKED_WAIT_CANONICAL_FOUNDATIONS", "XFER1 prematurely unblocked")
    require(xr.get("required_foundations") == FOUNDATIONS, "XFER1 foundations changed")
    require(xr.get("evo3_research_may_continue_without_xfer1") is True, "research planning incorrectly blocked")
    require(xr.get("production_binding_may_not_continue_without_xfer1") is True, "production binding bypass")
    require(r.get("next") == "E3.1_PLANET_FIELD_SNAPSHOT_CONTRACT", "wrong next")
    require(r.get("roadmap_hash") == canonical_hash(r, "roadmap_hash"), "roadmap hash mismatch")

def validate_pair(a: dict[str, Any], r: dict[str, Any]) -> None:
    validate_architecture(a)
    validate_roadmap(r, a)

def main() -> int:
    try:
        a, r = load(ARCH_PATH), load(ROADMAP_PATH)
        validate_pair(a, r)
    except (OSError, json.JSONDecodeError, ContractError) as exc:
        print(f"ECO.EVO3 architecture validation: FAIL: {exc}")
        return 1
    print("ECO.EVO3 architecture validation: PASS")
    print("architecture_hash=" + a["architecture_hash"])
    print("roadmap_hash=" + r["roadmap_hash"])
    print("stages=7")
    print("checkpoints=10")
    print("required_foundations=G,ENV,MAT,WQ,SD,TF")
    print("next=E3.1_PLANET_FIELD_SNAPSHOT_CONTRACT")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

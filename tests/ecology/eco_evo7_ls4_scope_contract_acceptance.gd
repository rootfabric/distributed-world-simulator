extends SceneTree

const CONTRACT_PATH := "res://config/ecology/eco-evo7-ls4-scope-contract.v1.json"
const ACTIVATION_PATH := "res://config/ecology/eco-evo7-ls4-activation.v1.json"

const EXPECTED_PREDECESSOR_HEAD := "b4f73a4073ac16b2a1de535acd64ae16641d4588"
const EXPECTED_PREDECESSOR_TREE := "81caf408e75059fde6b897e0f967e8b7d373ca1e"
const EXPECTED_TESTED_HEAD := "81a0b3fa60664684b02d8387e4693c5f328dbe28"
const EXPECTED_TESTED_TREE := "a192950483267dd428baf2d1daa25de915df2370"
const EXPECTED_REPORT_HASH := "1064567c83c1bd023589fdf9e36f8436b9624eeb928e8b7d413b92ce3254c3f6"

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
    var contract := _load_json(CONTRACT_PATH)
    _check(not contract.is_empty(), "LS4 scope contract parses")
    _check(String(contract.get("schema", "")) == "distributed_world_simulator.ecology.evo7_ls4_scope_contract.v1", "LS4 contract schema exact")
    _check(String(contract.get("status", "")) == "SCOPE_FROZEN_LS4_1_AUTHORIZED", "LS4 scope is frozen and only LS4.1 is authorized")
    _check(String(contract.get("checkpoint", "")) == "ECO.EVO7/LS4", "LS4 checkpoint exact")

    var predecessor: Dictionary = contract.get("accepted_predecessor", {})
    _check(String(predecessor.get("perf2_conv_control_head", "")) == EXPECTED_PREDECESSOR_HEAD, "LS4 binds exact accepted PERF2.CONV control HEAD")
    _check(String(predecessor.get("perf2_conv_control_tree", "")) == EXPECTED_PREDECESSOR_TREE, "LS4 binds exact accepted PERF2.CONV control TREE")
    _check(String(predecessor.get("perf2_conv_tested_runtime_head", "")) == EXPECTED_TESTED_HEAD, "LS4 binds exact tested PERF2.CONV runtime HEAD")
    _check(String(predecessor.get("perf2_conv_tested_runtime_tree", "")) == EXPECTED_TESTED_TREE, "LS4 binds exact tested PERF2.CONV runtime TREE")
    _check(String(predecessor.get("perf2_conv_report_hash", "")) == EXPECTED_REPORT_HASH, "LS4 binds exact accepted PERF2.CONV report hash")

    var authority: Dictionary = contract.get("authority", {})
    _check(String(authority.get("mode", "")) == "RESEARCH_SHADOW_ONLY", "LS4 remains research-shadow-only")
    _check(not bool(authority.get("production_promotion", true)), "LS4 cannot promote production authority")
    _check(not bool(authority.get("world_write", true)), "LS4 cannot write canonical WORLD")
    _check(not bool(authority.get("persistence_authority", true)), "LS4 cannot own persistence")
    _check(not bool(authority.get("network_authority", true)), "LS4 cannot own network authority")
    _check(not bool(authority.get("renderer_truth_owner", true)), "renderer cannot become ecology truth")
    _check(bool(authority.get("accepted_perf2_evidence_immutable", false)), "PERF2 evidence remains immutable")
    _check(bool(authority.get("accepted_vis4_evidence_immutable", false)), "VIS4 evidence remains immutable")

    var core: Dictionary = contract.get("core_contracts", {})
    var catalog: Dictionary = core.get("species_catalog", {})
    _check(int(catalog.get("minimum_species", 0)) >= 3, "LS4.1 requires at least three species")
    _check(not bool(catalog.get("per_world_retuning_allowed", true)), "species catalog cannot be retuned per world")
    var axes: Array = catalog.get("required_functional_axes", [])
    for axis in ["growth_strategy", "water_demand", "light_demand", "nutrient_demand", "stress_tolerance", "reproduction_strategy"]:
        _check(axes.has(axis), "species catalog includes functional axis %s" % axis)

    var interactions: Dictionary = core.get("interaction_graph", {})
    var kinds: Array = interactions.get("allowed_kinds", [])
    for kind in ["COMPETITION", "HERBIVORY", "PREDATION", "POLLINATION", "SYMBIOSIS", "DECOMPOSITION"]:
        _check(kinds.has(kind), "interaction graph freezes kind %s" % kind)
    _check(String(interactions.get("unknown_kind_policy", "")) == "FAIL_CLOSED", "unknown interaction kinds fail closed")

    var resources: Dictionary = core.get("shared_resource_field", {})
    var resource_ids: Array = resources.get("resources", [])
    for resource_id in ["LIGHT", "WATER", "NUTRIENTS", "SPACE"]:
        _check(resource_ids.has(resource_id), "shared resource %s frozen" % resource_id)
    var resource_requirements: Array = resources.get("requirements", [])
    for rule in ["non_negative_supply", "non_negative_demand", "bounded_allocation", "deterministic_tie_breaking", "no_hidden_resource_creation"]:
        _check(resource_requirements.has(rule), "resource invariant %s frozen" % rule)

    var disturbance: Dictionary = core.get("disturbance_event", {})
    _check(String(disturbance.get("duplicate_event_policy", "")) == "FAIL_CLOSED", "duplicate disturbances fail closed")
    _check(String(disturbance.get("stale_source_policy", "")) == "FAIL_CLOSED", "stale disturbances fail closed")
    for kind in ["DROUGHT", "FLOOD", "FIRE", "FROST", "EXCAVATION", "IMPACT"]:
        _check(Array(disturbance.get("allowed_kinds", [])).has(kind), "disturbance kind %s frozen" % kind)

    var feedback: Dictionary = core.get("environment_feedback_proposal", {})
    _check(not bool(feedback.get("direct_world_mutation", true)), "feedback proposal cannot mutate WORLD directly")
    _check(String(feedback.get("producer", "")) == "ECO_LS4_DERIVED_ONLY", "feedback is ECO-derived only")
    _check(String(feedback.get("consumer", "")) == "EXTERNAL_WORLD_ENVIRONMENT_OWNER", "feedback is applied only by WORLD owner")
    _check(String(feedback.get("stale_or_unbounded_policy", "")) == "FAIL_CLOSED", "stale/unbounded feedback fails closed")
    for channel in ["SHADE", "WATER_RETENTION", "ORGANIC_MATTER", "SOIL_STABILITY", "SURFACE_ROUGHNESS"]:
        _check(Array(feedback.get("allowed_channels", [])).has(channel), "feedback channel %s frozen" % channel)

    var identity: Dictionary = contract.get("deterministic_identity", {})
    _check(bool(identity.get("canonical_ordering_required", false)), "canonical ordering required")
    _check(bool(identity.get("generation_bound_identity_required", false)), "generation-bound identity required")
    _check(bool(identity.get("replay_same_inputs_same_hashes_required", false)), "same-input replay required")
    for hash_name in ["species_catalog_hash", "interaction_graph_hash", "resource_field_hash", "ecology_state_hash", "disturbance_event_hash", "feedback_proposal_hash"]:
        _check(Array(identity.get("required_hashes", [])).has(hash_name), "identity hash %s required" % hash_name)

    var roadmap: Array = contract.get("roadmap", [])
    var expected_ids := ["LS4.1", "LS4.2", "LS4.3", "LS4.4", "LS4.5", "LS4.6", "LS4.7", "LS4.8", "LS4.FINAL"]
    _check(roadmap.size() == expected_ids.size(), "LS4 roadmap has exact frozen stage count")
    for i in range(expected_ids.size()):
        _check(String(Dictionary(roadmap[i]).get("id", "")) == expected_ids[i], "LS4 roadmap order[%d] is %s" % [i, expected_ids[i]])
        _check(not String(Dictionary(roadmap[i]).get("visual_gate", "")).is_empty(), "%s requires visual gate" % expected_ids[i])
    _check(String(Dictionary(roadmap[0]).get("status", "")) == "AUTHORIZED_NEXT", "only LS4.1 is next-authorized")
    for i in range(1, roadmap.size()):
        _check(String(Dictionary(roadmap[i]).get("status", "")).begins_with("BLOCKED_BY_"), "%s remains predecessor-blocked" % expected_ids[i])

    var acceptance: Dictionary = contract.get("acceptance_policy", {})
    _check(bool(acceptance.get("visual_evidence_required_for_every_major_substage", false)), "every LS4 major substage requires visual evidence")
    _check(bool(acceptance.get("exact_local_runtime_pass_required", false)), "exact local runtime pass required")
    _check(bool(acceptance.get("canonical_double_godot_required", false)), "canonical double Godot required")
    _check(bool(acceptance.get("same_input_replay_required", false)), "same-input replay acceptance required")
    _check(bool(acceptance.get("tamper_tests_required", false)), "tamper tests required")
    _check(bool(acceptance.get("stale_source_tests_required", false)), "stale-source tests required")
    _check(String(acceptance.get("performance_regression_rule", "")).contains("PERF2.CONV"), "PERF2.CONV remains performance regression baseline")
    _check(String(acceptance.get("working_set_rule", "")).contains("bound"), "LS4 working-set rule requires explicit bounds")

    var final_challenge: Dictionary = contract.get("ls4_final_challenge", {})
    _check(int(final_challenge.get("minimum_worlds", 0)) >= 3, "LS4.FINAL requires at least three worlds")
    _check(int(final_challenge.get("minimum_generations_per_world", 0)) >= 200, "LS4.FINAL requires at least 200 generations/world")
    _check(bool(final_challenge.get("same_species_catalog", false)), "LS4.FINAL freezes one species catalog")
    _check(bool(final_challenge.get("same_interaction_rules", false)), "LS4.FINAL freezes one interaction ruleset")
    _check(bool(final_challenge.get("same_founder_setup", false)), "LS4.FINAL freezes founder setup")
    _check(not bool(final_challenge.get("per_world_retuning", true)), "LS4.FINAL forbids per-world retuning")
    _check(bool(final_challenge.get("distinct_ecosystem_outcomes_required", false)), "LS4.FINAL requires distinct ecosystem outcomes")
    _check(bool(final_challenge.get("disturbance_recovery_required", false)), "LS4.FINAL requires disturbance recovery")
    _check(bool(final_challenge.get("deterministic_replay_required", false)), "LS4.FINAL requires deterministic replay")
    _check(bool(final_challenge.get("visual_playground_required", false)), "LS4.FINAL requires PLAY1 visual playground")

    var authorization: Dictionary = contract.get("authorization", {})
    _check(bool(authorization.get("scope_frozen", false)), "LS4 scope frozen")
    _check(bool(authorization.get("runtime_implementation_authorized", false)), "runtime implementation now authorized")
    _check(String(authorization.get("authorized_next_substage", "")) == "LS4.1", "LS4.1 is exact next executable substage")
    _check(bool(authorization.get("later_substages_require_predecessor_acceptance", false)), "later LS4 stages require predecessor acceptance")
    _check(bool(authorization.get("substage_ids_frozen", false)), "LS4 substage IDs frozen")

    var activation := _load_json(ACTIVATION_PATH)
    _check(not activation.is_empty(), "LS4 activation record parses")
    _check(String(activation.get("checkpoint", "")) == "ECO.EVO7/LS4", "activation checkpoint matches scope")

    _finish()

func _load_json(path: String) -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parsed = JSON.parse_string(file.get_as_text())
    return parsed if parsed is Dictionary else {}

func _check(condition: bool, message: String) -> void:
    assertions += 1
    if not condition:
        failures.append(message)
        push_error("FAIL: %s" % message)

func _finish() -> void:
    if failures.is_empty():
        print("ECO.EVO7 LS4 Scope Contract: PASS (%d assertions)" % assertions)
        quit(0)
        return
    print("ECO.EVO7 LS4 Scope Contract: FAIL (%d/%d failed)" % [failures.size(), assertions])
    for failure in failures:
        print(" - %s" % failure)
    quit(1)

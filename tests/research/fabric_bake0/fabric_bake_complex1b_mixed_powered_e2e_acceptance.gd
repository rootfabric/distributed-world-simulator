extends SceneTree

const Observation = preload("res://scripts/research/fabric_bake0/complex1b_mixed_powered_observation_v1.gd")
const Ownership = preload("res://scripts/research/fabric_bake0/mixed_representation_ownership_contract_v1.gd")
const Complex1A = preload("res://tests/research/fabric_bake0/fabric_bake_complex1a_fixture.gd")

var _checks := 0
var _failed := false

func _initialize() -> void:
	var result := Observation.build()
	_require(bool(result.get("success", false)), "COMPLEX1B observation builds", result)
	if _failed:
		_finish()
		return

	_require(String(result.get("schema", "")) == Observation.SCHEMA, "schema exact")
	_require(int(result["scale"]) == 2000, "canonical subject remains 2000 parts")
	_require(int(result["construction_revision_after"]) == int(result["construction_revision_before"]) + 1, "Construction revision advances exactly once")
	_require(String(result["event"]["event_type"]) == "BOND_BREAK", "canonical event remains BOND_BREAK")
	_require(String(result["event_commit"]["state"]) == "APPLIED", "canonical event commit applied")

	var kinds: Array = Array(result["representation_kinds"]).duplicate()
	kinds.sort()
	var expected := ["CONTACT_BAKE", "DYNAMIC_ROM", "FULL", "HYBRID_BAKE", "STRUCTURAL_BAKE"]
	expected.sort()
	_require(kinds == expected, "closed BRIDGE-2 five-kind registry preserved")
	for required_kind in ["FULL", "STRUCTURAL_BAKE", "DYNAMIC_ROM", "HYBRID_BAKE"]:
		_require(kinds.has(required_kind), "%s active in same mixed subject" % required_kind)
	_require(int(result["representation_part_counts"].get("FULL", 0)) == 20, "impact FULL remains bounded to 20 visual parts")
	for kind in expected:
		_require(int(result["representation_part_counts"].get(kind, 0)) > 0, "%s owns non-empty visual partition" % kind)

	var resolution: Dictionary = result["ownership_resolution"]
	_require(String(resolution["event_id"]) == String(result["event"]["event_id"]), "ownership resolution uses same canonical event ID")
	_require(String(resolution["evaluator_representation_id"]) == Observation.REP_FULL, "FULL is active event evaluator")
	_require(String(resolution["evaluator_representation_kind"]) == "FULL", "event evaluator kind FULL")
	_require(resolution["observer_representation_ids"] == [Observation.REP_CONTACT, Observation.REP_STRUCTURAL], "baked impact observers exact")
	_require(String(resolution["event_commit_policy"]) == Ownership.EVENT_COMMIT_POLICY, "event policy exactly once")
	_require(not bool(resolution["evaluator_canonical_write_authorized"]), "derived FULL evaluator cannot write canonical truth")
	_require(String(result["duplicate_event_error"]) == "BRIDGE2_A_EVENT_ALREADY_COMMITTED", "ownership duplicate event fails closed")

	_require(Array(result["projection_mutable_source_ids"]).is_empty(), "BRIDGE-2 projection owns no canonical mutable source")
	_require(Array(result["projection_readonly_source_ids"]).size() == 5, "all executable projection slices are read-only")
	var affected: Array = Array(result["affected_regions"]).duplicate()
	affected.sort()
	var expected_affected := [Observation.REGION_IMPACT, Observation.REGION_STABLE]
	expected_affected.sort()
	_require(affected == expected_affected, "canonical break refreshes only impact + structural projection dependencies")
	_require(String(result["stale_block_error_before_rebuild"]) == "BRIDGE2_MIXED_STEP_BLOCKED", "mixed execution blocks on stale projection")
	_require(String(result["stale_block_error_after_full_refresh"]) == "BRIDGE2_MIXED_STEP_BLOCKED", "structural STALE still blocks after FULL refresh")
	_require(float(result["impact_rebuild_handoff_error"]) == 0.0, "FULL projection refresh has exact state handoff")
	_require(float(result["structural_rebuild_handoff_error"]) == 0.0, "STRUCTURAL_BAKE rebuild has exact state handoff")
	_require(float(result["mixed_full_max_state_delta"]) <= 1.0e-12, "mixed executable flow equals FULL reference")

	var final_states := {}
	for region in result["region_states"]:
		final_states[String(region["region_id"])] = String(region["artifact_state"])
	_require(String(final_states[Observation.REGION_IMPACT]) == "FULL", "impact region remains FULL after refresh")
	_require(String(final_states[Observation.REGION_STABLE]) == "READY", "structural region rebaked READY")
	_require(String(final_states[Observation.REGION_DYNAMIC]) == "READY", "DYNAMIC_ROM remains READY")
	_require(String(final_states[Observation.REGION_HYBRID]) == "READY", "HYBRID_BAKE remains READY")
	_require(String(final_states[Observation.REGION_CONTACT]) == "READY", "CONTACT_BAKE remains READY")

	var power: Dictionary = result["power"]
	_require(String(power["event_id"]) == String(result["event"]["event_id"]), "functional consequence uses same event identity")
	_require(String(power["structural_support_bond_id"]) == String(result["break_bond_id"]), "wire support binds exact broken structural bond")
	_require(String(power["functional_mutation_reason"]) == "SUPPORT_TOPOLOGY_LOST", "wire topology changes only from support loss")
	_require(bool(power["before"]["on"]), "FULL baseline lamp ON before break")
	_require(not bool(power["after"]["on"]), "mixed causal outcome lamp OFF after break")
	_require(Array(power["active_functional_bond_ids_after"]).is_empty(), "functional path removed after break")
	_require(absf(float(power["after"]["voltage"])) <= Complex1A.EPSILON, "lamp voltage collapses")
	_require(absf(float(power["after"]["absorbed_power"])) <= Complex1A.EPSILON, "lamp absorbed power collapses")
	_require(String(power["duplicate_event_error"]) == "COMPLEX1A_STRUCTURAL_EVENT_ALREADY_APPLIED", "functional duplicate event fails closed")

	_require(int(result["full_topology"]["split_component_count"]) == 2, "same canonical split has two components")
	_require(int(result["full_topology"]["executable_rebake_count"]) == 2, "same canonical split has two executable rebakes")
	_require(bool(result["causal_equal_to_full"]), "causal outcome equals FULL baseline")
	_require(not String(result["checksum"]).is_empty(), "observation checksum present")

	var packed := load("res://scenes/labs/fabric/complex1b_mixed_powered_e2e.tscn")
	_require(packed is PackedScene, "visual mixed scene loads")
	if packed is PackedScene:
		var scene := (packed as PackedScene).instantiate()
		_require(scene != null, "visual mixed scene instantiates")
		if scene != null:
			_require(String(scene.name) == "COMPLEX1BMixedPoweredE2E", "visual scene identity exact")
			scene.free()

	_finish()

func _require(condition: bool, label: String, details = null) -> bool:
	if condition:
		_checks += 1
		return true
	_failed = true
	printerr("COMPLEX1B FAILURE: %s details=%s" % [label, str(details)])
	return false

func _finish() -> void:
	if _failed:
		printerr("FABRIC COMPLEX1B Mixed Powered E2E Acceptance: FAIL (%d successful assertions)" % _checks)
		quit(1)
		return
	print("FABRIC COMPLEX1B Mixed Powered E2E Acceptance: PASS (%d assertions) FULL+STRUCTURAL_BAKE+DYNAMIC_ROM+HYBRID_BAKE causal=FULL_REFERENCE" % _checks)
	quit(0)

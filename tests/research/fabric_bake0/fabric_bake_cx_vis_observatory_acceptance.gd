extends SceneTree

const ObservationModel = preload("res://scripts/research/fabric_bake0/cx_vis_observation_model_v1.gd")
const Complex0Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_complex0_fixture.gd")
const Complex1AFixture = preload("res://tests/research/fabric_bake0/fabric_bake_complex1a_fixture.gd")

var _checks := 0

func _initialize() -> void:
	var observation := ObservationModel.build(true)
	_check(bool(observation.get("success", false)))
	_check(String(observation.get("schema", "")) == ObservationModel.SCHEMA)
	_check(int(observation["scale"]) == 2000)
	_check(observation["parts"].size() == 2000)
	_check(int(observation["active_full_part_count"]) == Complex0Fixture.REGION_SIZE)
	_check(int(observation["active_full_part_count"]) == 20)
	_check(String(observation["guard_status"]) == "STRUCTURAL_REFINEMENT_REQUIRED")
	_check(String(observation["guard_request"]["mapped_source_region"]) == String(observation["target_region_id"]))
	_check(String(observation["guard_request"]["peak_bond_id"]) == String(observation["break_bond_id"]))
	_check(String(observation["event"]["event_type"]) == "BOND_BREAK")
	_check(String(observation["event_commit"]["state"]) == "APPLIED")
	_check(String(observation["event_commit"]["event_id"]) == String(observation["event"]["event_id"]))
	_check(String(observation["parent_artifact_state_after_break"]) == "STALE")
	_check(String(observation["stale_rejection_error"]) == "STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN")
	_check(int(observation["invalidated_reduced_piece_count"]) == 3)
	_check(int(observation["executable_rebake_count"]) == 2)
	_check(observation["components"].size() == 2)

	var component_sizes: Array = []
	var total_parts := 0
	for component in observation["components"]:
		_check(bool(component["artifact_valid"]))
		component_sizes.append(int(component["part_count"]))
		total_parts += int(component["part_count"])
	component_sizes.sort()
	var expected_sizes := [
		int(observation["break_index"]),
		2000 - int(observation["break_index"]),
	]
	expected_sizes.sort()
	_check(component_sizes == expected_sizes)
	_check(total_parts == 2000)
	_check(absf(float(observation["post_split_reduction_ratio"]) - 1000.0) <= 1.0e-12)
	_check(float(observation["mass_error"]) <= Complex0Fixture.CONSERVATION_TOLERANCE)
	_check(float(observation["linear_momentum_error"]) <= Complex0Fixture.CONSERVATION_TOLERANCE)
	_check(float(observation["angular_momentum_error"]) <= Complex0Fixture.CONSERVATION_TOLERANCE)
	_check(float(observation["max_state_handoff_error"]) <= Complex0Fixture.CONTINUITY_TOLERANCE)

	var power: Dictionary = observation["power"]
	_check(bool(observation["powered"]))
	_check(bool(power.get("success", false)))
	_check(String(power["event_id"]) == String(observation["event"]["event_id"]))
	_check(String(power["structural_support_bond_id"]) == String(observation["break_bond_id"]))
	_check(String(power["functional_bond_id"]) == "wire/path-a")
	_check(String(power["functional_mutation_reason"]) == "SUPPORT_TOPOLOGY_LOST")
	_check(bool(power["before"]["on"]))
	_check(not bool(power["after"]["on"]))
	_check(absf(float(power["before"]["voltage"]) - Complex1AFixture.SOURCE_VOLTAGE) <= Complex1AFixture.EPSILON)
	_check(absf(float(power["before"]["absorbed_power"])) > Complex1AFixture.POWER_ON_THRESHOLD)
	_check(absf(float(power["after"]["voltage"])) <= Complex1AFixture.EPSILON)
	_check(absf(float(power["after"]["current"])) <= Complex1AFixture.EPSILON)
	_check(absf(float(power["after"]["absorbed_power"])) <= Complex1AFixture.EPSILON)
	_check(Array(power["active_functional_bond_ids_before"]) == ["wire/path-a"])
	_check(Array(power["active_functional_bond_ids_after"]).is_empty())
	_check(String(power["duplicate_event_error"]) == "COMPLEX1A_STRUCTURAL_EVENT_ALREADY_APPLIED")
	_check(float(power["before"]["max_balance_residual"]) <= Complex1AFixture.EPSILON)
	_check(float(power["before"]["max_power_residual"]) <= Complex1AFixture.EPSILON)
	_check(float(power["after"]["max_balance_residual"]) <= Complex1AFixture.EPSILON)
	_check(float(power["after"]["max_power_residual"]) <= Complex1AFixture.EPSILON)

	var stages: Array = observation["stages"]
	_check(stages == ObservationModel.STAGES_POWERED)
	_check(stages[0] == "BASELINE_BAKED")
	_check(stages[2] == "LOCAL_FULL")
	_check(stages[3] == "CANONICAL_BREAK")
	_check(stages[4] == "STALE_REJECTED")
	_check(stages[5] == "SPLIT_REBAKED")
	_check(stages[6] == "WIRE_TOPOLOGY_LOST")
	_check(stages[7] == "LAMP_OFF")
	_check(not String(observation["checksum"]).is_empty())

	_check_scene(
		"res://scenes/labs/fabric/cx_vis0_break_observatory.tscn",
		false,
		"CXVIS0BreakObservatory"
	)
	_check_scene(
		"res://scenes/labs/fabric/cx_vis1_powered_break_observatory.tscn",
		true,
		"CXVIS1PoweredBreakObservatory"
	)

	print("FABRIC CX-VIS0/1 Observatory Acceptance: PASS (%d assertions) parts=2000 full_at_event=20 split=2 lamp=ON->OFF event=%s" % [
		_checks,
		String(observation["event"]["event_id"]),
	])
	quit(0)

func _check_scene(path: String, powered: bool, expected_name: String) -> void:
	var resource := load(path)
	_check(resource is PackedScene)
	var scene := (resource as PackedScene).instantiate()
	_check(scene != null)
	_check(String(scene.name) == expected_name)
	_check(bool(scene.get("powered_chain_enabled")) == powered)
	scene.free()

func _check(condition: bool) -> void:
	assert(condition)
	_checks += 1

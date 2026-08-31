extends SceneTree

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Reconstruction = preload("res://scripts/research/fabric_bake0/structural_reconstruction_mapping_v1.gd")
const LocalPlan = preload("res://scripts/research/fabric_bake0/structural_local_unbake_plan_v1.gd")
const Compiler = preload("res://scripts/research/fabric_bake0/structural_local_unbake_compiler_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/structural_local_unbake_runtime_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_2_d_fixture.gd")
const CFixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_2_c_fixture.gd")

func error_code(result: Dictionary) -> String:
	return String(result.get("error_code", ""))

func component_by_id(plan: Dictionary, component_id: String) -> Dictionary:
	for component in plan["residual_components"]:
		if String(component["component_id"]) == component_id:
			return component
	return {}

func _init() -> void:
	var checks := 0
	var fixture := Fixture.build(false)
	assert(bool(fixture.get("success", false))); checks += 1
	var compiled := Compiler.compile(fixture["request"])
	assert(bool(compiled.get("success", false))); checks += 1
	assert(String(compiled.get("status", "")) == Compiler.READY); checks += 1
	var plan: Dictionary = compiled["plan"]
	assert(bool(LocalPlan.validate(plan).get("success", false))); checks += 1
	assert(String(plan["source_frontier_hash"]) == String(fixture["c_fixture"]["ab"]["frontier"]["frontier_hash"])); checks += 1
	assert(String(plan["parent_structural_descriptor_hash"]) == String(fixture["c_fixture"]["aggregate"]["descriptor"]["checksum"])); checks += 1
	assert(String(plan["parent_reconstruction_mapping_hash"]) == String(fixture["c_fixture"]["aggregate"]["reconstruction_mapping"]["checksum"])); checks += 1
	assert(String(plan["guard_field_hash"]) == String(fixture["c_compiled"]["guard_field"]["checksum"])); checks += 1
	assert(String(plan["target_region_id"]) == Fixture.TARGET_REGION_ID); checks += 1
	assert(plan["target_part_ids"].size() == 20); checks += 1
	assert(plan["target_part_models"].size() == 20); checks += 1
	assert(plan["target_internal_bond_ids"].size() == 19); checks += 1
	assert(plan["residual_components"].size() == 2); checks += 1
	assert(plan["cut_interfaces"].size() == 2); checks += 1
	assert(int(plan["canonical_part_count"]) == 500); checks += 1
	assert(int(plan["canonical_bond_count"]) == 499); checks += 1
	assert(int(compiled["diagnostics"]["full_part_count"]) == 20); checks += 1
	assert(int(compiled["diagnostics"]["retained_part_count"]) == 480); checks += 1
	assert(int(compiled["diagnostics"]["retained_component_count"]) == 2); checks += 1
	assert(int(compiled["diagnostics"]["cut_interface_count"]) == 2); checks += 1
	assert(int(compiled["diagnostics"]["full_dof"]) == 6500); checks += 1
	assert(int(compiled["diagnostics"]["mixed_dof"]) == 286); checks += 1
	assert(float(compiled["diagnostics"]["preserved_reduction_ratio"]) > 22.7); checks += 1
	assert(float(compiled["diagnostics"]["preserved_reduction_ratio"]) < 22.8); checks += 1
	assert(absf(float(compiled["diagnostics"]["unbaked_fraction"]) - 0.04) <= 1.0e-12); checks += 1
	assert(not bool(compiled["diagnostics"]["physical_bake_artifact_emitted"])); checks += 1
	assert(String(compiled["diagnostics"]["next_required_stage"]) == "B0.2-E_TOPOLOGY_SPLIT_REBAKE"); checks += 1

	var component_sizes: Array = []
	var component_bonds: Array = []
	var covered_parts: Dictionary = {}
	for part_id in plan["target_part_ids"]:
		covered_parts[String(part_id)] = true
	for component in plan["residual_components"]:
		component_sizes.append(component["part_ids"].size())
		component_bonds.append(component["bond_ids"].size())
		assert(component["part_ids"].size() == 240); checks += 1
		assert(component["bond_ids"].size() == 239); checks += 1
		assert(component["anchor_ids"].size() >= 1); checks += 1
		assert(String(component["descriptor"]["reconstruction_mapping_hash"]) == String(component["reconstruction_mapping"]["checksum"])); checks += 1
		for part_id in component["part_ids"]:
			assert(not covered_parts.has(String(part_id))); checks += 1
			covered_parts[String(part_id)] = true
	assert(covered_parts.size() == 500); checks += 1
	component_sizes.sort(); component_bonds.sort()
	assert(component_sizes == [240, 240]); checks += 1
	assert(component_bonds == [239, 239]); checks += 1

	var interface_bonds: Array = []
	for interface in plan["cut_interfaces"]:
		interface_bonds.append(String(interface["bond_id"]))
		assert(plan["target_part_ids"].has(String(interface["full_part_id"]))); checks += 1
		var component := component_by_id(plan, String(interface["residual_component_id"]))
		assert(not component.is_empty()); checks += 1
		assert(component["part_ids"].has(String(interface["residual_part_id"]))); checks += 1
		assert(component["anchor_ids"].has(String(interface["residual_anchor_id"]))); checks += 1
	interface_bonds.sort()
	assert(interface_bonds == ["bond/b0-2-0240", "bond/b0-2-0260"]); checks += 1

	# Reverse-input compile must produce the same content-addressed local unbake plan.
	var reversed_fixture := Fixture.build(true)
	assert(bool(reversed_fixture.get("success", false))); checks += 1
	var reversed_compiled := Compiler.compile(reversed_fixture["request"])
	assert(bool(reversed_compiled.get("success", false))); checks += 1
	assert(String(reversed_compiled["plan"]["checksum"]) == String(plan["checksum"])); checks += 1

	# Main transition: C requests region 12 at load=30, D materializes only that region as FULL.
	var reduced_state: Dictionary = fixture["c_fixture"]["ab"].get("reduced_state", {})
	if reduced_state.is_empty():
		reduced_state = preload("res://tests/research/fabric_bake0/fabric_bake_b0_2_ab_fixture.gd").reduced_state()
	var trigger_context := CFixture.runtime_context(fixture["c_fixture"], 30.0, true)
	var result := Runtime.execute(
		plan,
		fixture["c_fixture"]["aggregate"]["descriptor"],
		fixture["c_fixture"]["aggregate"]["reconstruction_mapping"],
		fixture["c_compiled"]["guard_field"],
		reduced_state,
		trigger_context
	)
	assert(bool(result.get("success", false))); checks += 1
	assert(String(result.get("status", "")) == Runtime.READY); checks += 1
	assert(String(result["target_region_id"]) == Fixture.TARGET_REGION_ID); checks += 1
	assert(String(result["trigger"]["mapped_source_region"]) == Fixture.TARGET_REGION_ID); checks += 1
	assert(String(result["trigger"]["peak_bond_id"]) == CFixture.WEAK_BOND_ID); checks += 1
	assert(result["full_part_states"].size() == 20); checks += 1
	assert(result["residual_reduced_states"].size() == 2); checks += 1
	assert(result["cut_interfaces"].size() == 2); checks += 1
	assert(int(result["diagnostics"]["full_part_count"]) == 20); checks += 1
	assert(int(result["diagnostics"]["retained_part_count"]) == 480); checks += 1
	assert(int(result["diagnostics"]["mixed_dof"]) == 286); checks += 1
	assert(float(result["diagnostics"]["preserved_reduction_ratio"]) > 22.7); checks += 1
	assert(float(result["diagnostics"]["mass_error"]) <= Fixture.CONSERVATION_TOLERANCE); checks += 1
	assert(float(result["diagnostics"]["linear_momentum_error"]) <= Fixture.CONSERVATION_TOLERANCE); checks += 1
	assert(float(result["diagnostics"]["angular_momentum_error"]) <= Fixture.CONSERVATION_TOLERANCE); checks += 1
	assert(float(result["diagnostics"]["max_residual_state_error"]) <= Fixture.CONTINUITY_TOLERANCE); checks += 1
	assert(float(result["diagnostics"]["max_interface_position_error"]) <= Fixture.CONTINUITY_TOLERANCE); checks += 1
	assert(float(result["diagnostics"]["max_interface_velocity_error"]) <= Fixture.CONTINUITY_TOLERANCE); checks += 1
	assert(not bool(result["diagnostics"]["physical_bake_artifact_emitted"])); checks += 1
	assert(String(result["diagnostics"]["next_required_stage"]) == "B0.2-E_TOPOLOGY_SPLIT_REBAKE"); checks += 1

	# FULL target states must equal the exact A/B reconstruction at the transition instant.
	var parent_full := Reconstruction.reconstruct(fixture["c_fixture"]["aggregate"]["reconstruction_mapping"], reduced_state)
	assert(bool(parent_full.get("success", false))); checks += 1
	var expected_states: Dictionary = parent_full["details"]["full_states"]
	for part_id in plan["target_part_ids"]:
		var key := String(part_id)
		assert(result["full_part_states"].has(key)); checks += 1
		assert(JSON.stringify(result["full_part_states"][key]) == JSON.stringify(expected_states[key])); checks += 1

	# Every retained component reconstructs exactly the parent rigid state for its 240 parts.
	var residual_covered := 0
	for state_entry in result["residual_reduced_states"]:
		var component := component_by_id(plan, String(state_entry["component_id"]))
		assert(not component.is_empty()); checks += 1
		var rebuilt := Reconstruction.reconstruct(component["reconstruction_mapping"], state_entry["reduced_state"])
		assert(bool(rebuilt.get("success", false))); checks += 1
		assert(rebuilt["details"]["full_states"].size() == component["part_ids"].size()); checks += 1
		residual_covered += component["part_ids"].size()
	assert(residual_covered == 480); checks += 1

	# Capacity crossing may already be present, but D must still reconstruct the same bounded region.
	var crossed := Runtime.execute(
		plan, fixture["c_fixture"]["aggregate"]["descriptor"], fixture["c_fixture"]["aggregate"]["reconstruction_mapping"],
		fixture["c_compiled"]["guard_field"], reduced_state, CFixture.runtime_context(fixture["c_fixture"], 41.0, true)
	)
	assert(bool(crossed.get("success", false))); checks += 1
	assert(String(crossed["target_region_id"]) == Fixture.TARGET_REGION_ID); checks += 1
	assert(crossed["full_part_states"].size() == 20); checks += 1

	# A safe guard state must not unbake anything.
	var safe := Runtime.execute(
		plan, fixture["c_fixture"]["aggregate"]["descriptor"], fixture["c_fixture"]["aggregate"]["reconstruction_mapping"],
		fixture["c_compiled"]["guard_field"], reduced_state, CFixture.runtime_context(fixture["c_fixture"], 20.0, true)
	)
	assert(error_code(safe) == "STRUCTURAL_LOCAL_UNBAKE_GUARD_NOT_TRIGGERED"); checks += 1

	# A plan for another region cannot consume region 12's guard request.
	var wrong_region_request: Dictionary = fixture["request"].duplicate(true)
	wrong_region_request["plan_id"] = "unbake-plan/b0-2-d-wrong-region"
	wrong_region_request["target_region_id"] = "region/b0-2-013"
	var wrong_region_compiled := Compiler.compile(wrong_region_request)
	assert(bool(wrong_region_compiled.get("success", false))); checks += 1
	var wrong_region_result := Runtime.execute(
		wrong_region_compiled["plan"], fixture["c_fixture"]["aggregate"]["descriptor"], fixture["c_fixture"]["aggregate"]["reconstruction_mapping"],
		fixture["c_compiled"]["guard_field"], reduced_state, trigger_context
	)
	assert(error_code(wrong_region_result) == "STRUCTURAL_LOCAL_UNBAKE_TARGET_NOT_REQUESTED"); checks += 1

	# Boundedness is explicit and fail-closed.
	var too_tight: Dictionary = fixture["request"].duplicate(true)
	too_tight["max_full_parts"] = 19
	assert(error_code(Compiler.compile(too_tight)) == "NO_SAFE_BOUNDED_LOCAL_UNBAKE_LIMIT"); checks += 1
	var too_large_residual_min: Dictionary = fixture["request"].duplicate(true)
	too_large_residual_min["minimum_retained_component_parts"] = 241
	assert(error_code(Compiler.compile(too_large_residual_min)) == "NO_SAFE_BOUNDED_LOCAL_UNBAKE_RESIDUAL_TOO_SMALL"); checks += 1

	# Canonical source drift is rejected before a plan is emitted.
	var source_mutation: Dictionary = fixture["request"].duplicate(true)
	source_mutation["parts"] = fixture["request"]["parts"].duplicate(true)
	source_mutation["parts"][237] = source_mutation["parts"][237].duplicate(true)
	source_mutation["parts"][237]["mass"] = float(source_mutation["parts"][237]["mass"]) + 0.125
	assert(error_code(Compiler.compile(source_mutation)) == "STRUCTURAL_LOCAL_UNBAKE_CANONICAL_SOURCE_MISMATCH"); checks += 1

	# Valid-but-foreign guard identity cannot execute an existing plan.
	var foreign_guard: Dictionary = fixture["c_compiled"]["guard_field"].duplicate(true)
	foreign_guard["field_id"] = "guard-field/b0-2-c-foreign"
	foreign_guard["checksum"] = ""
	foreign_guard["checksum"] = Utils.compute_checksum(foreign_guard)
	assert(error_code(Runtime.execute(
		plan, fixture["c_fixture"]["aggregate"]["descriptor"], fixture["c_fixture"]["aggregate"]["reconstruction_mapping"],
		foreign_guard, reduced_state, trigger_context
	)) == "STRUCTURAL_LOCAL_UNBAKE_GUARD_BINDING_MISMATCH"); checks += 1

	# Tampered ownership coverage remains invalid even if the checksum is recomputed.
	var tampered_plan: Dictionary = plan.duplicate(true)
	tampered_plan["residual_components"][0]["part_ids"][0] = String(plan["target_part_ids"][0])
	tampered_plan["checksum"] = ""
	tampered_plan["checksum"] = Utils.compute_checksum(tampered_plan)
	assert(not bool(LocalPlan.validate(tampered_plan).get("success", false))); checks += 1

	print("FABRIC-BAKE B0.2-D Acceptance: PASS (%d assertions) full=%d retained=%d components=%d interfaces=%d dof=%d->%d ratio=%.6f mass_err=%s linear_err=%s angular_err=%s interface_pos=%s interface_vel=%s plan=%s" % [
		checks,
		int(result["diagnostics"]["full_part_count"]),
		int(result["diagnostics"]["retained_part_count"]),
		int(result["diagnostics"]["retained_component_count"]),
		int(result["diagnostics"]["cut_interface_count"]),
		int(result["diagnostics"]["full_dof"]),
		int(result["diagnostics"]["mixed_dof"]),
		float(result["diagnostics"]["preserved_reduction_ratio"]),
		str(result["diagnostics"]["mass_error"]),
		str(result["diagnostics"]["linear_momentum_error"]),
		str(result["diagnostics"]["angular_momentum_error"]),
		str(result["diagnostics"]["max_interface_position_error"]),
		str(result["diagnostics"]["max_interface_velocity_error"]),
		String(plan["checksum"]),
	])
	quit(0)

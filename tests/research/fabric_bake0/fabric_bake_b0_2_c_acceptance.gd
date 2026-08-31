extends SceneTree

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const RefinementGuard = preload("res://scripts/research/fabric_bake0/refinement_guard_v1.gd")
const GuardField = preload("res://scripts/research/fabric_bake0/structural_refinement_guard_field_descriptor_v1.gd")
const Compiler = preload("res://scripts/research/fabric_bake0/structural_refinement_guard_compiler_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/structural_refinement_guard_runtime_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_2_c_fixture.gd")

func error_code(value: Dictionary) -> String:
	return String(value.get("error_code", ""))

func find_guard(field: Dictionary, region_id: String) -> Dictionary:
	for guard in field["region_guards"]:
		if String(guard["mapped_source_region"]) == region_id:
			return guard
	return {}

func find_region(result: Dictionary, region_id: String) -> Dictionary:
	for region in result.get("region_results", []):
		if String(region["mapped_source_region"]) == region_id:
			return region
	return {}

func _init() -> void:
	var checks := 0
	var fixture: Dictionary = Fixture.build()
	assert(bool(fixture.get("success", false))); checks += 1
	var compiled: Dictionary = Compiler.compile(fixture["request"])
	assert(bool(compiled.get("success", false))); checks += 1
	assert(String(compiled.get("status", "")) == Compiler.READY_FOR_LOCAL_UNBAKE); checks += 1
	assert(not bool(compiled["diagnostics"]["physical_bake_artifact_emitted"])); checks += 1
	assert(String(compiled["diagnostics"]["next_required_stage"]) == "B0.2-D_BOUNDED_LOCAL_UNBAKE"); checks += 1
	var field: Dictionary = compiled["guard_field"]
	assert(bool(GuardField.validate(field).get("success", false))); checks += 1
	assert(String(field["source_frontier_hash"]) == String(fixture["ab"]["frontier"]["frontier_hash"])); checks += 1
	assert(String(field["structural_descriptor_hash"]) == String(fixture["aggregate"]["descriptor"]["checksum"])); checks += 1
	assert(String(field["reconstruction_mapping_hash"]) == String(fixture["aggregate"]["reconstruction_mapping"]["checksum"])); checks += 1
	assert(String(field["capacity_certificate_hash"]) == String(fixture["request"]["capacity_certificate_hash"])); checks += 1
	assert(String(field["root_part_id"]) == Fixture.ROOT_PART_ID); checks += 1
	assert(String(field["dynamics_model"]) == GuardField.DYNAMICS_MODEL); checks += 1
	assert(field["part_models"].size() == 500); checks += 1
	assert(field["bond_models"].size() == 499); checks += 1
	assert(field["region_guards"].size() == 25); checks += 1
	assert(int(compiled["diagnostics"]["region_guard_count"]) == 25); checks += 1

	var weak_guard := find_guard(field, Fixture.WEAK_REGION_ID)
	assert(not weak_guard.is_empty()); checks += 1
	assert(bool(RefinementGuard.validate(weak_guard).get("success", false))); checks += 1
	assert(absf(float(weak_guard["conservative_bound"]) - 1.0) <= 1.0e-12); checks += 1
	assert(absf(float(weak_guard["trigger_threshold"]) - Fixture.TRIGGER_RATIO) <= 1.0e-12); checks += 1
	assert(absf(float(weak_guard["uncertainty_margin"]) - Fixture.TARGET_UNCERTAINTY) <= 1.0e-12); checks += 1
	assert(int(weak_guard["required_refinement_level"]) == 2); checks += 1

	var reversed_fixture: Dictionary = Fixture.build(true)
	assert(bool(reversed_fixture.get("success", false))); checks += 1
	var reversed_compiled: Dictionary = Compiler.compile(reversed_fixture["request"])
	assert(bool(reversed_compiled.get("success", false))); checks += 1
	assert(String(reversed_compiled["guard_field"]["checksum"]) == String(field["checksum"])); checks += 1
	assert(String(reversed_compiled["guard_field"]["capacity_certificate_hash"]) == String(field["capacity_certificate_hash"])); checks += 1

	var zero_result: Dictionary = Runtime.evaluate(field, Fixture.runtime_context(fixture, 0.0, true))
	assert(bool(zero_result.get("success", false))); checks += 1
	assert(String(zero_result.get("status", "")) == Runtime.SAFE); checks += 1
	assert(zero_result["refinement_requests"].is_empty()); checks += 1
	assert(float(zero_result["diagnostics"]["residual_force_norm"]) <= Fixture.RESIDUAL_FORCE_TOLERANCE); checks += 1
	assert(float(zero_result["diagnostics"]["residual_moment_norm"]) <= Fixture.RESIDUAL_MOMENT_TOLERANCE); checks += 1
	assert(float(zero_result["diagnostics"]["global_peak_utilization"]) <= 1.0e-10); checks += 1

	var safe_result: Dictionary = Runtime.evaluate(field, Fixture.runtime_context(fixture, 20.0, true))
	assert(bool(safe_result.get("success", false))); checks += 1
	assert(String(safe_result.get("status", "")) == Runtime.SAFE); checks += 1
	assert(safe_result["refinement_requests"].is_empty()); checks += 1
	var safe_weak_region := find_region(safe_result, Fixture.WEAK_REGION_ID)
	assert(not safe_weak_region.is_empty()); checks += 1
	assert(float(safe_weak_region["max_utilization"]) > 0.49); checks += 1
	assert(float(safe_weak_region["max_utilization"]) < 0.51); checks += 1
	assert(String(safe_weak_region["peak_bond_id"]) == Fixture.WEAK_BOND_ID); checks += 1
	assert(not bool(safe_weak_region["refinement_required"])); checks += 1
	assert(not bool(safe_weak_region["capacity_envelope_crossed"])); checks += 1

	var trigger_result: Dictionary = Runtime.evaluate(field, Fixture.runtime_context(fixture, 30.0, true))
	assert(bool(trigger_result.get("success", false))); checks += 1
	assert(String(trigger_result.get("status", "")) == Runtime.REFINEMENT_REQUIRED); checks += 1
	assert(trigger_result["refinement_requests"].size() == 1); checks += 1
	var request: Dictionary = trigger_result["refinement_requests"][0]
	assert(String(request["mapped_source_region"]) == Fixture.WEAK_REGION_ID); checks += 1
	assert(String(request["peak_bond_id"]) == Fixture.WEAK_BOND_ID); checks += 1
	assert(int(request["required_refinement_level"]) == 2); checks += 1
	assert(float(request["utilization"]) >= 0.75); checks += 1
	assert(float(request["utilization"]) < 1.0); checks += 1
	assert(float(request["remaining_guard_margin"]) <= 1.0e-9); checks += 1
	var trigger_region := find_region(trigger_result, Fixture.WEAK_REGION_ID)
	assert(bool(trigger_region["refinement_required"])); checks += 1
	assert(not bool(trigger_region["capacity_envelope_crossed"])); checks += 1
	var active_regions := 0
	for region in trigger_result["region_results"]:
		if float(region["max_utilization"]) > 1.0e-9:
			active_regions += 1
	assert(active_regions <= 3); checks += 1

	var crossed_result: Dictionary = Runtime.evaluate(field, Fixture.runtime_context(fixture, 41.0, true))
	assert(bool(crossed_result.get("success", false))); checks += 1
	assert(String(crossed_result.get("status", "")) == Runtime.REFINEMENT_REQUIRED); checks += 1
	var crossed_region := find_region(crossed_result, Fixture.WEAK_REGION_ID)
	assert(bool(crossed_region["capacity_envelope_crossed"])); checks += 1
	assert(bool(crossed_region["refinement_required"])); checks += 1
	assert(float(crossed_region["max_utilization"]) > 1.0); checks += 1

	var first_trigger_load := -1
	var first_capacity_cross_load := -1
	for load_value in range(0, 46):
		var swept: Dictionary = Runtime.evaluate(field, Fixture.runtime_context(fixture, float(load_value), false))
		assert(bool(swept.get("success", false))); checks += 1
		var weak_region := find_region(swept, Fixture.WEAK_REGION_ID)
		if first_trigger_load < 0 and bool(weak_region["refinement_required"]):
			first_trigger_load = load_value
		if first_capacity_cross_load < 0 and bool(weak_region["capacity_envelope_crossed"]):
			first_capacity_cross_load = load_value
	assert(first_trigger_load >= 0); checks += 1
	assert(first_capacity_cross_load >= 0); checks += 1
	assert(first_trigger_load < first_capacity_cross_load); checks += 1
	assert(first_trigger_load == 30); checks += 1
	assert(first_capacity_cross_load == 40); checks += 1

	var incomplete_context: Dictionary = Fixture.runtime_context(fixture, 20.0, true)
	incomplete_context["complete_external_wrench_set"] = false
	assert(error_code(Runtime.evaluate(field, incomplete_context)) == "STRUCTURAL_GUARD_LOAD_COVERAGE_UNCERTIFIED"); checks += 1

	var missing_load_context: Dictionary = Fixture.runtime_context(fixture, 20.0, true)
	missing_load_context["external_wrenches"].remove_at(0)
	assert(error_code(Runtime.evaluate(field, missing_load_context)) == "STRUCTURAL_GUARD_DYNAMICS_INCONSISTENT"); checks += 1

	var foreign_context: Dictionary = Fixture.runtime_context(fixture, 20.0, false)
	foreign_context["structural_descriptor_hash"] = Utils.canonical_hash({"foreign": "descriptor"})
	assert(error_code(Runtime.evaluate(field, foreign_context)) == "STRUCTURAL_GUARD_DESCRIPTOR_BINDING_MISMATCH"); checks += 1

	var unknown_part_context: Dictionary = Fixture.runtime_context(fixture, 20.0, false)
	unknown_part_context["external_wrenches"].append({
		"wrench_id": "wrench/foreign",
		"part_id": "part/foreign",
		"point_from_com": [0.0, 0.0, 0.0],
		"force_body": [0.0, 0.0, 0.0],
		"torque_body_about_point": [0.0, 0.0, 0.0],
	})
	assert(error_code(Runtime.evaluate(field, unknown_part_context)) == "STRUCTURAL_GUARD_WRENCH_PART_MISSING"); checks += 1

	var missing_capacity_request: Dictionary = fixture["request"].duplicate(true)
	missing_capacity_request["bond_capacity_specs"].remove_at(missing_capacity_request["bond_capacity_specs"].size() - 1)
	missing_capacity_request["capacity_certificate_hash"] = Fixture.capacity_hash(String(missing_capacity_request["source_frontier_hash"]), missing_capacity_request["bond_capacity_specs"])
	assert(error_code(Compiler.compile(missing_capacity_request)) == "NO_SAFE_GUARD_CAPACITY_COVERAGE_MISMATCH"); checks += 1

	var bad_certificate_request: Dictionary = fixture["request"].duplicate(true)
	bad_certificate_request["capacity_certificate_hash"] = Utils.canonical_hash({"bad": "certificate"})
	assert(error_code(Compiler.compile(bad_certificate_request)) == "NO_SAFE_GUARD_CAPACITY_CERTIFICATE_MISMATCH"); checks += 1

	var unsafe_margin_request: Dictionary = fixture["request"].duplicate(true)
	for spec in unsafe_margin_request["bond_capacity_specs"]:
		if String(spec["bond_id"]) == Fixture.WEAK_BOND_ID:
			spec["uncertainty_ratio"] = 0.25
	unsafe_margin_request["capacity_certificate_hash"] = Fixture.capacity_hash(String(unsafe_margin_request["source_frontier_hash"]), unsafe_margin_request["bond_capacity_specs"])
	assert(error_code(Compiler.compile(unsafe_margin_request)) == "NO_SAFE_GUARD_UNCERTIFIED_MARGIN"); checks += 1

	var cyclic_fixture: Dictionary = Fixture.build(false, true)
	assert(bool(cyclic_fixture.get("success", false))); checks += 1
	assert(error_code(Compiler.compile(cyclic_fixture["request"])) == "NO_SAFE_GUARD_CYCLIC_OR_REDUNDANT_STRUCTURAL_GRAPH"); checks += 1

	print("FABRIC-BAKE B0.2-C Acceptance: PASS (%d assertions) parts=%d bonds=%d regions=%d first_trigger=%d capacity_cross=%d peak_region=%s field=%s" % [
		checks,
		field["part_models"].size(),
		field["bond_models"].size(),
		field["region_guards"].size(),
		first_trigger_load,
		first_capacity_cross_load,
		Fixture.WEAK_REGION_ID,
		String(field["checksum"]),
	])
	quit(0)

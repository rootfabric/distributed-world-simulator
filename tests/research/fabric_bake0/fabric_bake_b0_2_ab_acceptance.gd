extends SceneTree

const Compiler = preload("res://scripts/research/fabric_bake0/structural_aggregate_compiler_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/structural_aggregate_descriptor_v1.gd")
const Reconstruction = preload("res://scripts/research/fabric_bake0/structural_reconstruction_mapping_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_2_ab_fixture.gd")

func error_code(value: Dictionary) -> String:
	return String(value.get("error_code", ""))

func vec3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func quat(value: Array) -> Quaternion:
	return Quaternion(float(value[0]), float(value[1]), float(value[2]), float(value[3])).normalized()

func quat_error(a: Array, b: Array) -> float:
	return 1.0 - absf(quat(a).dot(quat(b)))

func _init() -> void:
	var checks := 0
	var fixture := Fixture.build()
	var compiled := Compiler.compile(fixture["request"])
	assert(bool(compiled.get("success", false))); checks += 1
	assert(String(compiled.get("status", "")) == Compiler.READY_FOR_GUARDS); checks += 1
	assert(not bool(compiled["diagnostics"]["physical_bake_artifact_emitted"])); checks += 1
	assert(String(compiled["diagnostics"]["next_required_stage"]) == "B0.2-C_REFINEMENT_GUARDS"); checks += 1
	var descriptor: Dictionary = compiled["descriptor"]
	var mapping: Dictionary = compiled["reconstruction_mapping"]
	assert(bool(Descriptor.validate(descriptor).get("success", false))); checks += 1
	assert(bool(Reconstruction.validate(mapping).get("success", false))); checks += 1
	assert(int(descriptor["part_count"]) == Fixture.PART_COUNT); checks += 1
	assert(int(descriptor["bond_count"]) == Fixture.PART_COUNT - 1); checks += 1
	assert(int(descriptor["region_count"]) == Fixture.PART_COUNT / Fixture.REGION_SIZE); checks += 1
	assert(int(descriptor["full_state_dof"]) == Fixture.PART_COUNT * 13); checks += 1
	assert(int(descriptor["reduced_state_dof"]) == 13); checks += 1
	assert(float(descriptor["state_reduction_ratio"]) == 500.0); checks += 1
	assert(descriptor["boundary_anchors"].size() == 4); checks += 1
	assert(descriptor["support_envelope"]["points"].size() == Fixture.PART_COUNT * 8); checks += 1
	assert(String(descriptor["reconstruction_mapping_hash"]) == String(mapping["checksum"])); checks += 1

	var mass_sum := 0.0
	var weighted := Vector3.ZERO
	for part in fixture["parts"]:
		mass_sum += float(part["mass"])
		weighted += vec3(part["position"]) * float(part["mass"])
	assert(absf(float(descriptor["total_mass"]) - mass_sum) <= 1.0e-11); checks += 1
	assert(vec3(descriptor["center_of_mass"]).distance_to(weighted / mass_sum) <= 1.0e-12); checks += 1
	for row in range(3):
		for column in range(3):
			assert(absf(float(descriptor["inertia_tensor_body"][row][column]) - float(descriptor["inertia_tensor_body"][column][row])) <= 1.0e-10); checks += 1

	var reversed := Compiler.compile(Fixture.build(0, true)["request"])
	assert(String(reversed["descriptor"]["checksum"]) == String(descriptor["checksum"])); checks += 1
	assert(String(reversed["reconstruction_mapping"]["checksum"]) == String(mapping["checksum"])); checks += 1

	var reduced_state := Fixture.reduced_state()
	var reconstructed := Reconstruction.reconstruct(mapping, reduced_state)
	assert(bool(reconstructed.get("success", false))); checks += 1
	var full_states: Dictionary = reconstructed["details"]["full_states"]
	assert(full_states.size() == Fixture.PART_COUNT); checks += 1
	var projected := Reconstruction.project(mapping, full_states, 2.0e-10)
	assert(bool(projected.get("success", false))); checks += 1
	var projected_state: Dictionary = projected["details"]["reduced_state"]
	assert(vec3(projected_state["position"]).distance_to(vec3(reduced_state["position"])) <= 2.0e-10); checks += 1
	assert(vec3(projected_state["linear_velocity"]).distance_to(vec3(reduced_state["linear_velocity"])) <= 2.0e-10); checks += 1
	assert(vec3(projected_state["angular_velocity"]).distance_to(vec3(reduced_state["angular_velocity"])) <= 2.0e-10); checks += 1
	assert(quat_error(projected_state["orientation"], reduced_state["orientation"]) <= 2.0e-12); checks += 1
	var roundtrip := Reconstruction.maximum_roundtrip_error(mapping, reduced_state)
	assert(bool(roundtrip.get("success", false))); checks += 1
	assert(float(roundtrip["details"]["maximum_error"]) <= 2.0e-10); checks += 1

	var full_momentum := Compiler.full_momentum(fixture["parts"], full_states, reduced_state["position"])
	var reduced_momentum := Compiler.reduced_momentum(descriptor, reduced_state)
	assert(bool(full_momentum.get("success", false)) and bool(reduced_momentum.get("success", false))); checks += 1
	var linear_error := vec3(full_momentum["details"]["linear_momentum"]).distance_to(vec3(reduced_momentum["details"]["linear_momentum"]))
	var angular_error := vec3(full_momentum["details"]["angular_momentum_about_com"]).distance_to(vec3(reduced_momentum["details"]["angular_momentum_about_com"]))
	assert(linear_error <= 5.0e-10); checks += 1
	assert(angular_error <= 5.0e-9); checks += 1

	for anchor in fixture["anchors"]:
		var anchor_id := String(anchor["anchor_id"])
		var evaluated := Compiler.evaluate_anchor(descriptor, reduced_state, anchor_id)
		assert(bool(evaluated.get("success", false))); checks += 1
		var part_state: Dictionary = full_states[String(anchor["part_id"])]
		var expected_position := vec3(part_state["position"]) + quat(part_state["orientation"]) * vec3(anchor["position_local"])
		var expected_orientation := quat(part_state["orientation"]) * quat(anchor["orientation_local"])
		var lever := expected_position - vec3(reduced_state["position"])
		var expected_velocity := vec3(reduced_state["linear_velocity"]) + vec3(reduced_state["angular_velocity"]).cross(lever)
		assert(vec3(evaluated["details"]["position"]).distance_to(expected_position) <= 2.0e-10); checks += 1
		assert(quat_error(evaluated["details"]["orientation"], Fixture.arr4(expected_orientation)) <= 2.0e-12); checks += 1
		assert(vec3(evaluated["details"]["linear_velocity"]).distance_to(expected_velocity) <= 2.0e-10); checks += 1
		assert(evaluated["details"]["linear_velocity_jacobian_world"].size() == 3); checks += 1

	for direction in [[1.0, 0.0, 0.0], [-0.2, 0.7, 0.4], [0.1, -0.3, 1.0]]:
		var support := Compiler.support(descriptor, direction)
		assert(bool(support.get("success", false))); checks += 1
		var d := vec3(direction)
		var brute := -INF
		for point in descriptor["support_envelope"]["points"]:
			brute = maxf(brute, d.dot(vec3(point["point_from_com"])))
		assert(absf(float(support["details"]["support"]) - brute) <= 1.0e-12); checks += 1

	var non_rigid_request: Dictionary = fixture["request"].duplicate(true)
	non_rigid_request["bonds"][111]["rigid"] = false
	assert(error_code(Compiler.compile(non_rigid_request)) == "NON_RIGID_STRUCTURAL_BOND"); checks += 1

	var disconnected_request: Dictionary = fixture["request"].duplicate(true)
	disconnected_request["bonds"].remove_at(disconnected_request["bonds"].size() - 1)
	assert(error_code(Compiler.compile(disconnected_request)) == "DISCONNECTED_STRUCTURAL_AGGREGATE"); checks += 1

	var undersized_request: Dictionary = fixture["request"].duplicate(true)
	undersized_request["parts"] = undersized_request["parts"].slice(0, 64)
	undersized_request["bonds"] = undersized_request["bonds"].slice(0, 63)
	undersized_request["boundary_anchors"] = [undersized_request["boundary_anchors"][0]]
	assert(error_code(Compiler.compile(undersized_request)) == "INSUFFICIENT_STRUCTURAL_COMPLEXITY_REDUCTION"); checks += 1

	var bad_inertia_request: Dictionary = fixture["request"].duplicate(true)
	bad_inertia_request["parts"][17]["inertia_tensor"][1][1] = -1.0
	assert(error_code(Compiler.compile(bad_inertia_request)) == "NONPOSITIVE_STRUCTURAL_INERTIA"); checks += 1

	var bad_full_states: Dictionary = full_states.duplicate(true)
	bad_full_states["part/b0-2-0217"]["position"][0] = float(bad_full_states["part/b0-2-0217"]["position"][0]) + 0.01
	assert(error_code(Reconstruction.project(mapping, bad_full_states, 1.0e-9)) == "NON_RIGID_FULL_STATE"); checks += 1

	var mutated := Compiler.compile(Fixture.build(1)["request"])
	assert(bool(mutated.get("success", false))); checks += 1
	assert(String(mutated["descriptor"]["checksum"]) != String(descriptor["checksum"])); checks += 1
	assert(String(mutated["reconstruction_mapping"]["checksum"]) != String(mapping["checksum"])); checks += 1
	var mutated_again := Compiler.compile(Fixture.build(1)["request"])
	assert(String(mutated_again["descriptor"]["checksum"]) == String(mutated["descriptor"]["checksum"])); checks += 1
	assert(String(mutated_again["reconstruction_mapping"]["checksum"]) == String(mutated["reconstruction_mapping"]["checksum"])); checks += 1

	print("FABRIC-BAKE B0.2-A/B Acceptance: PASS (%d assertions) parts=%d state=%d->%d ratio=%.1fx regions=%d supports=%d linear_momentum_error=%s angular_momentum_error=%s descriptor=%s mapping=%s" % [
		checks,
		int(descriptor["part_count"]),
		int(descriptor["full_state_dof"]),
		int(descriptor["reduced_state_dof"]),
		float(descriptor["state_reduction_ratio"]),
		int(descriptor["region_count"]),
		descriptor["support_envelope"]["points"].size(),
		linear_error,
		angular_error,
		String(descriptor["checksum"]),
		String(mapping["checksum"]),
	])
	quit(0)

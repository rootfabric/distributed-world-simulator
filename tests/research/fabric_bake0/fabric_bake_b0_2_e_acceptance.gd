extends SceneTree

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/physical_bake_artifact_v1.gd")
const Reconstruction = preload("res://scripts/research/fabric_bake0/structural_reconstruction_mapping_v1.gd")
const Transaction = preload("res://scripts/research/fabric_bake0/structural_topology_rebake_transaction_v1.gd")
const Compiler = preload("res://scripts/research/fabric_bake0/structural_topology_rebake_compiler_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/structural_topology_rebake_runtime_v1.gd")
const ABFixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_2_ab_fixture.gd")
const CFixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_2_c_fixture.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_2_e_fixture.gd")

func _initialize() -> void:
	var checks := 0
	var fixture := Fixture.build(false)
	assert(bool(fixture.get("success", false))); checks += 1
	var compiled := Compiler.compile(fixture["request"])
	assert(bool(compiled.get("success", false))); checks += 1
	assert(String(compiled.get("status", "")) == Compiler.READY); checks += 1
	var transaction: Dictionary = compiled["transaction"]
	assert(bool(Transaction.validate(transaction).get("success", false))); checks += 1
	assert(String(transaction["previous_source_frontier_hash"]) == String(fixture["previous_frontier"]["frontier_hash"])); checks += 1
	assert(String(transaction["current_source_frontier_hash"]) == String(fixture["current_frontier"]["frontier_hash"])); checks += 1
	assert(String(transaction["event"]["event_id"]) == Fixture.EVENT_ID); checks += 1
	assert(String(transaction["event"]["bond_id"]) == Fixture.BREAK_BOND_ID); checks += 1
	assert(String(transaction["event"]["target_region_id"]) == Fixture.TARGET_REGION_ID); checks += 1
	assert(String(transaction["event"]["event_type"]) == "BOND_BREAK"); checks += 1
	assert(String(transaction["event"]["event_hash"]) == Transaction.event_hash(transaction["event"])); checks += 1
	assert(transaction["invalidated_pieces"].size() == 3); checks += 1
	assert(transaction["rebaked_components"].size() == 2); checks += 1
	assert(int(compiled["diagnostics"]["physical_bake_artifact_count"]) == 2); checks += 1
	assert(bool(compiled["diagnostics"]["physical_bake_artifact_emitted"])); checks += 1
	assert(String(compiled["diagnostics"]["next_required_stage"]) == "B0.2_COMPLETE"); checks += 1
	assert(int(compiled["diagnostics"]["full_dof"]) == 6500); checks += 1
	assert(int(compiled["diagnostics"]["rebaked_dof"]) == 26); checks += 1
	assert(absf(float(compiled["diagnostics"]["post_split_reduction_ratio"]) - 250.0) <= 1.0e-12); checks += 1

	var component_sizes: Array = []
	var component_bonds: Array = []
	var covered_parts: Dictionary = {}
	var covered_bonds: Dictionary = {}
	var artifact_ids: Array = []
	for component in transaction["rebaked_components"]:
		component_sizes.append(component["part_ids"].size())
		component_bonds.append(component["bond_ids"].size())
		assert(component["anchor_ids"].size() >= 2); checks += 1
		assert(bool(Artifact.validate(component["physical_bake_artifact"]).get("success", false))); checks += 1
		assert(String(component["physical_bake_artifact"]["reduction_class"]) == "APPROXIMATE"); checks += 1
		assert(String(component["physical_bake_artifact"]["source_binding"]["frontier_hash"]) == String(fixture["current_frontier"]["frontier_hash"])); checks += 1
		assert(String(component["physical_bake_artifact"]["reduced_model_descriptor_hash"]) == String(component["descriptor"]["checksum"])); checks += 1
		assert(JSON.stringify(component["physical_bake_artifact"]["refinement_guards"]) == JSON.stringify(component["guard_field"]["region_guards"])); checks += 1
		artifact_ids.append(String(component["physical_bake_artifact"]["artifact_id"]))
		assert(component["predecessor_piece_ids"].has("piece/b0-2-d-full-target")); checks += 1
		for part_id in component["part_ids"]:
			assert(not covered_parts.has(String(part_id))); checks += 1
			covered_parts[String(part_id)] = true
		for bond_id in component["bond_ids"]:
			assert(String(bond_id) != Fixture.BREAK_BOND_ID); checks += 1
			assert(not covered_bonds.has(String(bond_id))); checks += 1
			covered_bonds[String(bond_id)] = true
	component_sizes.sort(); component_bonds.sort(); artifact_ids.sort()
	assert(component_sizes == [243, 257]); checks += 1
	assert(component_bonds == [242, 256]); checks += 1
	assert(covered_parts.size() == 500); checks += 1
	assert(covered_bonds.size() == 498); checks += 1
	assert(artifact_ids == ["bake/b0-2-e-000", "bake/b0-2-e-001"]); checks += 1

	# Input order must not change the topology transaction identity or any rebaked artifact identity.
	var reversed_fixture := Fixture.build(true)
	assert(bool(reversed_fixture.get("success", false))); checks += 1
	var reversed := Compiler.compile(reversed_fixture["request"])
	assert(bool(reversed.get("success", false))); checks += 1
	assert(String(reversed["transaction"]["checksum"]) == String(transaction["checksum"])); checks += 1
	for index in range(transaction["rebaked_components"].size()):
		assert(String(reversed["transaction"]["rebaked_components"][index]["descriptor"]["checksum"]) == String(transaction["rebaked_components"][index]["descriptor"]["checksum"])); checks += 1
		assert(String(reversed["transaction"]["rebaked_components"][index]["guard_field"]["checksum"]) == String(transaction["rebaked_components"][index]["guard_field"]["checksum"])); checks += 1
		assert(String(reversed["transaction"]["rebaked_components"][index]["physical_bake_artifact"]["checksum"]) == String(transaction["rebaked_components"][index]["physical_bake_artifact"]["checksum"])); checks += 1

	# Execute the real C -> D -> E lifecycle at the exact event instant.
	var reduced_state := ABFixture.reduced_state()
	var guard_context := CFixture.runtime_context(fixture["d_fixture"]["c_fixture"], 30.0, true)
	var result := Runtime.execute(
		transaction,
		fixture["d_compiled"]["plan"],
		fixture["d_fixture"]["c_fixture"]["aggregate"]["descriptor"],
		fixture["d_fixture"]["c_fixture"]["aggregate"]["reconstruction_mapping"],
		fixture["d_fixture"]["c_compiled"]["guard_field"],
		reduced_state,
		guard_context,
		fixture["current_frontier"],
		fixture["authority"],
		fixture["dependencies"],
		[]
	)
	assert(bool(result.get("success", false))); checks += 1
	assert(String(result.get("status", "")) == Runtime.READY); checks += 1
	assert(String(result["event_commit"]["event_id"]) == Fixture.EVENT_ID); checks += 1
	assert(String(result["event_commit"]["state"]) == "APPLIED"); checks += 1
	assert(result["invalidated_pieces"].size() == 3); checks += 1
	assert(result["rebaked_component_states"].size() == 2); checks += 1
	assert(int(result["diagnostics"]["split_component_count"]) == 2); checks += 1
	assert(int(result["diagnostics"]["invalidated_reduced_piece_count"]) == 3); checks += 1
	assert(int(result["diagnostics"]["executable_physical_bake_artifact_count"]) == 2); checks += 1
	assert(int(result["diagnostics"]["full_dof"]) == 6500); checks += 1
	assert(int(result["diagnostics"]["mixed_before_event_dof"]) == 286); checks += 1
	assert(int(result["diagnostics"]["rebaked_dof"]) == 26); checks += 1
	assert(absf(float(result["diagnostics"]["post_split_reduction_ratio"]) - 250.0) <= 1.0e-12); checks += 1
	assert(float(result["diagnostics"]["mass_error"]) <= Fixture.CONSERVATION_TOLERANCE); checks += 1
	assert(float(result["diagnostics"]["linear_momentum_error"]) <= Fixture.CONSERVATION_TOLERANCE); checks += 1
	assert(float(result["diagnostics"]["angular_momentum_error"]) <= Fixture.CONSERVATION_TOLERANCE); checks += 1
	assert(float(result["diagnostics"]["max_state_handoff_error"]) <= Fixture.CONTINUITY_TOLERANCE); checks += 1
	assert(int(result["diagnostics"]["duplicate_event_count"]) == 0); checks += 1
	assert(bool(result["diagnostics"]["physical_bake_artifact_emitted"])); checks += 1
	assert(bool(result["diagnostics"]["b0_2_complete"])); checks += 1

	# Reconstruct both new bakes and prove exact one-time coverage of all 500 canonical parts.
	var state_by_component: Dictionary = {}
	for entry in result["rebaked_component_states"]:
		state_by_component[String(entry["component_id"])] = entry
		assert(String(entry["execution_gate"]["artifact_id"]) == String(entry["artifact_id"])); checks += 1
	var rebuilt_parts: Dictionary = {}
	var parent_full := Reconstruction.reconstruct(fixture["d_fixture"]["c_fixture"]["aggregate"]["reconstruction_mapping"], reduced_state)
	assert(bool(parent_full.get("success", false))); checks += 1
	var expected_full: Dictionary = parent_full["details"]["full_states"]
	for component in transaction["rebaked_components"]:
		var component_id := String(component["component_id"])
		assert(state_by_component.has(component_id)); checks += 1
		var rebuilt := Reconstruction.reconstruct(component["reconstruction_mapping"], state_by_component[component_id]["reduced_state"])
		assert(bool(rebuilt.get("success", false))); checks += 1
		for part_id in component["part_ids"]:
			var key := String(part_id)
			assert(not rebuilt_parts.has(key)); checks += 1
			rebuilt_parts[key] = true
			assert(state_error(rebuilt["details"]["full_states"][key], expected_full[key]) <= Fixture.CONTINUITY_TOLERANCE); checks += 1
	assert(rebuilt_parts.size() == 500); checks += 1

	# Event ownership is exactly-once. A replay cannot produce a second split or second mutation.
	var replay := Runtime.execute(
		transaction, fixture["d_compiled"]["plan"],
		fixture["d_fixture"]["c_fixture"]["aggregate"]["descriptor"],
		fixture["d_fixture"]["c_fixture"]["aggregate"]["reconstruction_mapping"],
		fixture["d_fixture"]["c_compiled"]["guard_field"], reduced_state, guard_context,
		fixture["current_frontier"], fixture["authority"], fixture["dependencies"], [Fixture.EVENT_ID]
	)
	assert(error_code(replay) == "STRUCTURAL_TOPOLOGY_EVENT_ALREADY_APPLIED"); checks += 1

	# Current frontier must be the committed post-topology canonical source.
	var stale_frontier := Runtime.execute(
		transaction, fixture["d_compiled"]["plan"],
		fixture["d_fixture"]["c_fixture"]["aggregate"]["descriptor"],
		fixture["d_fixture"]["c_fixture"]["aggregate"]["reconstruction_mapping"],
		fixture["d_fixture"]["c_compiled"]["guard_field"], reduced_state, guard_context,
		fixture["previous_frontier"], fixture["authority"], fixture["dependencies"], []
	)
	assert(error_code(stale_frontier) == "STRUCTURAL_TOPOLOGY_REBAKE_CURRENT_FRONTIER_MISMATCH"); checks += 1

	# Compiler fail-closed gates.
	var no_revision: Dictionary = fixture["request"].duplicate(true)
	no_revision["current_source_frontier"] = fixture["previous_frontier"].duplicate(true)
	assert(error_code(Compiler.compile(no_revision)) == "STRUCTURAL_TOPOLOGY_REBAKE_FRONTIER_NOT_ADVANCED"); checks += 1

	var outside: Dictionary = fixture["request"].duplicate(true)
	outside["topology_event"] = fixture["topology_event"].duplicate(true)
	outside["topology_event"]["event_id"] = "topology-event/b0-2-e-outside"
	outside["topology_event"]["bond_id"] = "bond/b0-2-0260"
	outside["current_bonds"] = []
	for bond in fixture["d_fixture"]["c_fixture"]["ab"]["bonds"]:
		if String(bond["bond_id"]) != "bond/b0-2-0260":
			outside["current_bonds"].append(bond.duplicate(true))
	assert(error_code(Compiler.compile(outside)) == "STRUCTURAL_TOPOLOGY_EVENT_OUTSIDE_UNBAKED_REGION"); checks += 1

	var part_mutation: Dictionary = fixture["request"].duplicate(true)
	part_mutation["current_parts"] = fixture["request"]["current_parts"].duplicate(true)
	part_mutation["current_parts"][0] = part_mutation["current_parts"][0].duplicate(true)
	part_mutation["current_parts"][0]["mass"] = float(part_mutation["current_parts"][0]["mass"]) + 0.1
	assert(error_code(Compiler.compile(part_mutation)) == "STRUCTURAL_TOPOLOGY_REBAKE_PART_STATE_MUTATION_UNSUPPORTED"); checks += 1

	var undeclared_bond_mutation: Dictionary = fixture["request"].duplicate(true)
	undeclared_bond_mutation["current_bonds"] = fixture["request"]["current_bonds"].duplicate(true)
	undeclared_bond_mutation["current_bonds"][0] = undeclared_bond_mutation["current_bonds"][0].duplicate(true)
	undeclared_bond_mutation["current_bonds"][0]["part_b"] = "part/b0-2-0002"
	assert(error_code(Compiler.compile(undeclared_bond_mutation)) == "STRUCTURAL_TOPOLOGY_REBAKE_UNDECLARED_BOND_MUTATION"); checks += 1

	var too_large_minimum: Dictionary = fixture["request"].duplicate(true)
	too_large_minimum["minimum_rebake_component_parts"] = 258
	assert(error_code(Compiler.compile(too_large_minimum)) == "NO_SAFE_TOPOLOGY_REBAKE_COMPONENT_TOO_SMALL"); checks += 1

	var missing_capacity: Dictionary = fixture["request"].duplicate(true)
	missing_capacity["bond_capacity_specs"] = fixture["request"]["bond_capacity_specs"].duplicate(true)
	missing_capacity["bond_capacity_specs"].remove_at(0)
	assert(error_code(Compiler.compile(missing_capacity)) == "NO_SAFE_TOPOLOGY_REBAKE_CAPACITY_COVERAGE_MISMATCH"); checks += 1

	# A content-tampered transaction remains invalid even if its checksum is recomputed.
	var tampered: Dictionary = transaction.duplicate(true)
	tampered["rebaked_components"][0]["part_ids"][0] = String(tampered["rebaked_components"][1]["part_ids"][0])
	tampered["checksum"] = ""
	tampered["checksum"] = Utils.compute_checksum(tampered)
	assert(not bool(Transaction.validate(tampered).get("success", false))); checks += 1

	print("FABRIC-BAKE B0.2-E Acceptance: PASS (%d assertions) split=%d sizes=%s invalidated=%d artifacts=%d dof=%d->%d->%d ratio=%.6f mass_err=%s linear_err=%s angular_err=%s state_err=%s event=%s transaction=%s" % [
		checks,
		int(result["diagnostics"]["split_component_count"]),
		str(component_sizes),
		int(result["diagnostics"]["invalidated_reduced_piece_count"]),
		int(result["diagnostics"]["executable_physical_bake_artifact_count"]),
		int(result["diagnostics"]["full_dof"]),
		int(result["diagnostics"]["mixed_before_event_dof"]),
		int(result["diagnostics"]["rebaked_dof"]),
		float(result["diagnostics"]["post_split_reduction_ratio"]),
		str(result["diagnostics"]["mass_error"]),
		str(result["diagnostics"]["linear_momentum_error"]),
		str(result["diagnostics"]["angular_momentum_error"]),
		str(result["diagnostics"]["max_state_handoff_error"]),
		String(transaction["event"]["event_hash"]),
		String(transaction["checksum"]),
	])
	quit(0)

func error_code(value: Dictionary) -> String:
	return String(value.get("error_code", ""))

func state_error(left: Dictionary, right: Dictionary) -> float:
	return maxf(
		vec3(left["position"]).distance_to(vec3(right["position"])),
		maxf(
			vec3(left["linear_velocity"]).distance_to(vec3(right["linear_velocity"])),
			maxf(
				vec3(left["angular_velocity"]).distance_to(vec3(right["angular_velocity"])),
				quat_distance(quat(left["orientation"]), quat(right["orientation"]))
			)
		)
	)

func quat_distance(a: Quaternion, b: Quaternion) -> float:
	return 1.0 - absf(a.normalized().dot(b.normalized()))

func vec3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func quat(value: Array) -> Quaternion:
	return Quaternion(float(value[0]), float(value[1]), float(value[2]), float(value[3])).normalized()

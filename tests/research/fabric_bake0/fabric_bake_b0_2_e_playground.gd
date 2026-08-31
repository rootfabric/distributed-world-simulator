extends SceneTree

const Compiler = preload("res://scripts/research/fabric_bake0/structural_topology_rebake_compiler_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/structural_topology_rebake_runtime_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_2_e_fixture.gd")
const CFixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_2_c_fixture.gd")
const ABFixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_2_ab_fixture.gd")

func _init() -> void:
	var fixture := Fixture.build(false)
	if not bool(fixture.get("success", false)):
		push_error("B0.2-E playground fixture failed: %s" % JSON.stringify(fixture))
		quit(1)
		return
	var compiled := Compiler.compile(fixture["request"])
	if not bool(compiled.get("success", false)):
		push_error("B0.2-E playground compile failed: %s" % JSON.stringify(compiled))
		quit(1)
		return
	var result := Runtime.execute(
		compiled["transaction"],
		fixture["d_compiled"]["plan"],
		fixture["d_fixture"]["c_fixture"]["aggregate"]["descriptor"],
		fixture["d_fixture"]["c_fixture"]["aggregate"]["reconstruction_mapping"],
		fixture["d_fixture"]["c_compiled"]["guard_field"],
		ABFixture.reduced_state(),
		CFixture.runtime_context(fixture["d_fixture"]["c_fixture"], 30.0, true),
		fixture["current_frontier"], fixture["authority"], fixture["dependencies"], []
	)
	if not bool(result.get("success", false)):
		push_error("B0.2-E playground execute failed: %s" % JSON.stringify(result))
		quit(1)
		return
	var sizes: Array = []
	for component in compiled["transaction"]["rebaked_components"]:
		sizes.append(component["part_ids"].size())
	sizes.sort()
	print("FABRIC-BAKE B0.2-E Playground: PASS")
	print("  event: %s break=%s" % [String(result["event_commit"]["event_id"]), String(compiled["transaction"]["event"]["bond_id"])])
	print("  split components: %d sizes=%s" % [int(result["diagnostics"]["split_component_count"]), str(sizes)])
	print("  invalidated reduced pieces: %d" % int(result["diagnostics"]["invalidated_reduced_piece_count"]))
	print("  executable rebaked artifacts: %d" % int(result["diagnostics"]["executable_physical_bake_artifact_count"]))
	print("  state DOF: %d -> %d -> %d (%.6fx post-split reduction)" % [
		int(result["diagnostics"]["full_dof"]), int(result["diagnostics"]["mixed_before_event_dof"]),
		int(result["diagnostics"]["rebaked_dof"]), float(result["diagnostics"]["post_split_reduction_ratio"]),
	])
	print("  mass error: %s" % str(result["diagnostics"]["mass_error"]))
	print("  linear momentum error: %s" % str(result["diagnostics"]["linear_momentum_error"]))
	print("  angular momentum error: %s" % str(result["diagnostics"]["angular_momentum_error"]))
	print("  max state handoff error: %s" % str(result["diagnostics"]["max_state_handoff_error"]))
	print("  event hash: %s" % String(compiled["transaction"]["event"]["event_hash"]))
	print("  transaction: %s" % String(compiled["transaction"]["checksum"]))
	print("  B0.2 complete: %s" % str(result["diagnostics"]["b0_2_complete"]))
	quit(0)

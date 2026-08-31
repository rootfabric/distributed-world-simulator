extends SceneTree

const Compiler = preload("res://scripts/research/fabric_bake0/structural_local_unbake_compiler_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/structural_local_unbake_runtime_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_2_d_fixture.gd")
const CFixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_2_c_fixture.gd")
const ABFixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_2_ab_fixture.gd")

func _init() -> void:
	var fixture := Fixture.build(false)
	if not bool(fixture.get("success", false)):
		push_error("B0.2-D playground fixture failed: %s" % JSON.stringify(fixture))
		quit(1)
		return
	var compiled := Compiler.compile(fixture["request"])
	if not bool(compiled.get("success", false)):
		push_error("B0.2-D playground compile failed: %s" % JSON.stringify(compiled))
		quit(1)
		return
	var result := Runtime.execute(
		compiled["plan"],
		fixture["c_fixture"]["aggregate"]["descriptor"],
		fixture["c_fixture"]["aggregate"]["reconstruction_mapping"],
		fixture["c_compiled"]["guard_field"],
		ABFixture.reduced_state(),
		CFixture.runtime_context(fixture["c_fixture"], 30.0, true)
	)
	if not bool(result.get("success", false)):
		push_error("B0.2-D playground execute failed: %s" % JSON.stringify(result))
		quit(1)
		return
	print("FABRIC-BAKE B0.2-D Playground: PASS")
	print("  guard region: %s" % String(result["target_region_id"]))
	print("  representation: %d FULL parts + %d BAKED components retaining %d parts" % [
		int(result["diagnostics"]["full_part_count"]),
		int(result["diagnostics"]["retained_component_count"]),
		int(result["diagnostics"]["retained_part_count"]),
	])
	print("  state DOF: %d -> %d (%.6fx retained reduction)" % [
		int(result["diagnostics"]["full_dof"]),
		int(result["diagnostics"]["mixed_dof"]),
		float(result["diagnostics"]["preserved_reduction_ratio"]),
	])
	print("  cut interfaces: %d" % int(result["diagnostics"]["cut_interface_count"]))
	print("  mass error: %s" % str(result["diagnostics"]["mass_error"]))
	print("  linear momentum error: %s" % str(result["diagnostics"]["linear_momentum_error"]))
	print("  angular momentum error: %s" % str(result["diagnostics"]["angular_momentum_error"]))
	print("  max interface position error: %s" % str(result["diagnostics"]["max_interface_position_error"]))
	print("  max interface velocity error: %s" % str(result["diagnostics"]["max_interface_velocity_error"]))
	print("  plan: %s" % String(compiled["plan"]["checksum"]))
	print("  next required stage: %s" % String(result["diagnostics"]["next_required_stage"]))
	quit(0)

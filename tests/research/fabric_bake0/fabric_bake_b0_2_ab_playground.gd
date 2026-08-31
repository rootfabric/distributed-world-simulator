extends SceneTree

const Compiler = preload("res://scripts/research/fabric_bake0/structural_aggregate_compiler_v1.gd")
const Reconstruction = preload("res://scripts/research/fabric_bake0/structural_reconstruction_mapping_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_2_ab_fixture.gd")

func _init() -> void:
	var fixture := Fixture.build()
	var compiled := Compiler.compile(fixture["request"])
	if not bool(compiled.get("success", false)):
		push_error("B0.2-A/B playground compile failed: %s" % JSON.stringify(compiled))
		quit(1)
		return
	var descriptor: Dictionary = compiled["descriptor"]
	var mapping: Dictionary = compiled["reconstruction_mapping"]
	var reduced_state := Fixture.reduced_state()
	var full := Reconstruction.reconstruct(mapping, reduced_state)
	if not bool(full.get("success", false)):
		push_error("B0.2-A/B playground reconstruction failed: %s" % JSON.stringify(full))
		quit(1)
		return
	var projected := Reconstruction.project(mapping, full["details"]["full_states"])
	if not bool(projected.get("success", false)):
		push_error("B0.2-A/B playground projection failed: %s" % JSON.stringify(projected))
		quit(1)
		return
	print("FABRIC-BAKE B0.2-A/B Playground: PASS")
	print("  structural state: %d parts / %d DOF -> %d DOF (%.1fx)" % [descriptor["part_count"], descriptor["full_state_dof"], descriptor["reduced_state_dof"], descriptor["state_reduction_ratio"]])
	print("  regions: %d" % descriptor["region_count"])
	print("  boundary anchors: %d" % descriptor["boundary_anchors"].size())
	print("  support points: %d" % descriptor["support_envelope"]["points"].size())
	print("  total mass: %.6f" % float(descriptor["total_mass"]))
	print("  center of mass: %s" % str(descriptor["center_of_mass"]))
	print("  descriptor: %s" % descriptor["checksum"])
	print("  reconstruction mapping: %s" % mapping["checksum"])
	print("  next required stage: %s" % compiled["diagnostics"]["next_required_stage"])
	quit(0)

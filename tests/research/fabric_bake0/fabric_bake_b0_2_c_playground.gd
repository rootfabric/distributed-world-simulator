extends SceneTree

const Compiler = preload("res://scripts/research/fabric_bake0/structural_refinement_guard_compiler_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/structural_refinement_guard_runtime_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_2_c_fixture.gd")

func _init() -> void:
	var fixture: Dictionary = Fixture.build()
	var compiled: Dictionary = Compiler.compile(fixture["request"])
	if not bool(compiled.get("success", false)):
		push_error("B0.2-C playground compile failed: %s" % JSON.stringify(compiled))
		quit(1)
		return
	var field: Dictionary = compiled["guard_field"]
	for load_value in [20.0, 30.0, 41.0]:
		var result: Dictionary = Runtime.evaluate(field, Fixture.runtime_context(fixture, load_value, true))
		if not bool(result.get("success", false)):
			push_error("B0.2-C playground evaluate failed: %s" % JSON.stringify(result))
			quit(1)
			return
		print("load=%.1f status=%s peak=%s utilization=%.6f requests=%d residual_force=%s residual_moment=%s" % [
			load_value,
			String(result["status"]),
			String(result["diagnostics"]["global_peak_bond_id"]),
			float(result["diagnostics"]["global_peak_utilization"]),
			result["refinement_requests"].size(),
			str(result["diagnostics"]["residual_force_norm"]),
			str(result["diagnostics"]["residual_moment_norm"]),
		])
	print("FABRIC-BAKE B0.2-C Playground: PASS")
	print("guard_field=%s" % String(field["checksum"]))
	print("next=%s" % String(compiled["diagnostics"]["next_required_stage"]))
	quit(0)

extends SceneTree

const Compiler = preload("res://scripts/research/fabric_bake0/dynamic_full_model_compiler_v1.gd")
const Solver = preload("res://scripts/research/fabric_bake0/dynamic_full_reference_solver_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_4_a_fixture.gd")

func _init() -> void:
	var fixture := Fixture.build("ZERO")
	var compiled := Compiler.compile(fixture["request"])
	assert(bool(compiled.get("success", false)))
	var model: Dictionary = compiled["model"]
	var initial := Solver.initial_state(model)
	assert(bool(initial.get("success", false)))
	var flows := Fixture.zero_flows(model["boundary_contract"])
	flows["port/electrical/000-left"] = 0.5
	flows["port/electrical/170-mid-a"] = 0.1
	var run := Solver.advance_constant(model, initial["state"], flows, 0.005, 400)
	assert(bool(run.get("success", false)))
	print("FABRIC-BAKE B0.4-A Playground: PASS model=%s states=%d ports=%d E_final=%.12f Ein=%.12f Ediss=%.12f Enumeric=%.12f balance=%s" % [
		String(model["model_hash"]),
		int(model["full_state_schema"]["state_count"]),
		model["boundary_contract"]["ports"].size(),
		float(run["summary"]["final_stored_energy"]),
		float(run["summary"]["boundary_energy_in"]),
		float(run["summary"]["dissipated_energy"]),
		float(run["summary"]["numerical_dissipation_energy"]),
		String.num_scientific(float(run["summary"]["max_balance_residual"])),
	])
	quit(0)

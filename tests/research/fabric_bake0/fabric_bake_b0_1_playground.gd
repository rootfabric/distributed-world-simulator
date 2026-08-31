extends SceneTree

const Compiler = preload("res://scripts/research/fabric_bake0/exact_boundary_bake_compiler_v1.gd")
const CompileResult = preload("res://scripts/research/fabric_bake0/bake_compile_result_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/exact_boundary_runtime_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_1_fixture.gd")

func _init() -> void:
	var fixture := Fixture.build()
	var compiled := Compiler.compile(fixture["request"])
	if String(compiled.get("status", "")) != CompileResult.BAKE_READY:
		push_error("B0.1 playground compile failed: %s" % JSON.stringify(compiled))
		quit(1)
		return
	var descriptor: Dictionary = compiled["diagnostics"]["reduction"]
	var artifact: Dictionary = compiled["artifact"]
	var effort: Array = [12.0, -7.0, 3.5, 0.25]
	var executed := Runtime.execute(artifact, descriptor, Fixture.live_context(artifact), effort)
	if not bool(executed.get("success", false)):
		push_error("B0.1 playground execute failed: %s" % JSON.stringify(executed))
		quit(1)
		return
	print("FABRIC-BAKE B0.1 Playground: PASS")
	print("  equations: %d -> %d" % [descriptor["full_equation_count"], descriptor["reduced_equation_count"]])
	print("  ranks: internal=%d reduced=%d" % [descriptor["internal_rank"], descriptor["reduced_rank"]])
	print("  work ratio: %.1fx" % float(descriptor["runtime_work_ratio"]))
	print("  effort: %s" % str(effort))
	print("  flow: %s" % str(executed["details"]["boundary_flow"]))
	print("  power: %s" % str(executed["details"]["boundary_power"]))
	print("  descriptor: %s" % descriptor["checksum"])
	print("  artifact: %s" % artifact["checksum"])
	quit(0)

extends SceneTree

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const RepresentationInvalidation = preload("res://scripts/simulation/representation/contracts/representation_invalidation.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/physical_bake_artifact_v1.gd")
const CompileResult = preload("res://scripts/research/fabric_bake0/bake_compile_result_v1.gd")
const Bridge0 = preload("res://scripts/research/fabric_bake0/fabric_bake_bridge0_v1.gd")
const LinearAlgebra = preload("res://scripts/research/fabric_bake0/dense_linear_algebra_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/exact_boundary_reduction_descriptor_v1.gd")
const Reducer = preload("res://scripts/research/fabric_bake0/exact_boundary_reducer_v1.gd")
const Compiler = preload("res://scripts/research/fabric_bake0/exact_boundary_bake_compiler_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/exact_boundary_runtime_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_1_fixture.gd")

func error_code(value: Dictionary) -> String:
	return String(value.get("error_code", ""))

func _assert_close(a: float, b: float, tolerance: float) -> void:
	assert(absf(a - b) <= tolerance)

func _init() -> void:
	var checks := 0
	var fixture := Fixture.build()
	var request: Dictionary = fixture["request"]
	var system: Dictionary = fixture["linear_system"]

	assert(system["boundary_port_ids"].size() == 4); checks += 1
	assert(system["internal_variable_ids"].size() == 128); checks += 1
	assert(system["coefficient_matrix"].size() == 132); checks += 1

	var policy := {
		"pivot_relative_tolerance": Fixture.PIVOT_TOLERANCE,
		"symmetry_tolerance": Fixture.SYMMETRY_TOLERANCE,
		"passivity_tolerance": Fixture.PASSIVITY_TOLERANCE,
		"require_symmetric": true,
		"require_passive_laplacian": true,
	}
	var reduced := Reducer.reduce(system, policy)
	assert(bool(reduced.get("success", false))); checks += 1
	assert(String(reduced.get("status", "")) == Reducer.REDUCED); checks += 1
	var descriptor: Dictionary = reduced["descriptor"]
	assert(bool(Descriptor.validate(descriptor).get("success", false))); checks += 1
	assert(int(descriptor["full_equation_count"]) == 132); checks += 1
	assert(int(descriptor["reduced_equation_count"]) == 4); checks += 1
	assert(int(descriptor["internal_rank"]) == 128); checks += 1
	assert(int(descriptor["reduced_rank"]) == 3); checks += 1
	assert(bool(descriptor["passivity_certified"])); checks += 1
	assert(float(descriptor["runtime_work_ratio"]) >= 1000.0); checks += 1
	assert(float(descriptor["symmetry_error"]) <= 2.0e-11); checks += 1
	assert(float(descriptor["nullspace_residual"]) <= 2.0e-11); checks += 1

	var reduced_again := Reducer.reduce(system, policy)
	assert(String(reduced_again["descriptor"]["checksum"]) == String(descriptor["checksum"])); checks += 1
	var reversed_system := Fixture.make_linear_system(Fixture.INTERNAL_COUNT, 0, false, false, true)
	assert(String(reversed_system["system_hash"]) == String(system["system_hash"])); checks += 1
	var reversed_reduction := Reducer.reduce(reversed_system, policy)
	assert(String(reversed_reduction["descriptor"]["checksum"]) == String(descriptor["checksum"])); checks += 1

	var excitations: Array = [
		[12.0, -7.0, 3.5, 0.25],
		[1.0, 0.0, 0.0, 0.0],
		[0.0, 1.0, -1.0, 0.0],
		[-4.25, 2.75, 8.5, -7.0],
		[100.0, 100.0, 100.0, 100.0],
	]
	var maximum_flow_error := 0.0
	var maximum_power_error := 0.0
	for effort in excitations:
		var full := Reducer.evaluate_full(system, effort, Fixture.PIVOT_TOLERANCE)
		var baked := Reducer.evaluate_reduced(descriptor, effort)
		assert(bool(full.get("success", false)) and bool(baked.get("success", false))); checks += 1
		var flow_error := LinearAlgebra.max_abs_delta(full["details"]["boundary_flow"], baked["details"]["boundary_flow"])
		var power_error := absf(float(full["details"]["boundary_power"]) - float(baked["details"]["boundary_power"]))
		maximum_flow_error = maxf(maximum_flow_error, flow_error)
		maximum_power_error = maxf(maximum_power_error, power_error)
		assert(flow_error <= float(request["error_envelope"]["flow_abs"])); checks += 1
		assert(power_error <= float(request["error_envelope"]["power_abs"])); checks += 1
		assert(float(baked["details"]["boundary_power"]) >= -float(request["conservation_envelope"]["power_balance_error_max"])); checks += 1

	var compiled := Compiler.compile(request)
	assert(String(compiled.get("status", "")) == CompileResult.BAKE_READY); checks += 1
	assert(bool(CompileResult.validate(compiled).get("success", false))); checks += 1
	var artifact: Dictionary = compiled["artifact"]
	assert(bool(Artifact.validate(artifact).get("success", false))); checks += 1
	var compiled_descriptor: Dictionary = compiled["diagnostics"]["reduction"]
	assert(String(artifact["reduced_model_descriptor_hash"]) == String(compiled_descriptor["checksum"])); checks += 1
	assert(String(compiled_descriptor["source_system_hash"]) == String(system["system_hash"])); checks += 1
	assert(artifact["source_binding"]["dependency_set"]["dependencies"].size() == fixture["dependencies"]["dependencies"].size() + 1); checks += 1

	var live := Fixture.live_context(artifact)
	var runtime_result := Runtime.execute(artifact, compiled_descriptor, live, excitations[0])
	assert(bool(runtime_result.get("success", false))); checks += 1
	var direct := Reducer.evaluate_reduced(compiled_descriptor, excitations[0])
	assert(LinearAlgebra.max_abs_delta(runtime_result["details"]["boundary_flow"], direct["details"]["boundary_flow"]) == 0.0); checks += 1

	var foreign_descriptor := compiled_descriptor.duplicate(true)
	foreign_descriptor["schur_matrix"][0][0] = float(foreign_descriptor["schur_matrix"][0][0]) + 0.001
	foreign_descriptor["checksum"] = Utils.compute_checksum(foreign_descriptor)
	assert(bool(Descriptor.validate(foreign_descriptor).get("success", false))); checks += 1
	assert(error_code(Runtime.execute(artifact, foreign_descriptor, live, excitations[0])) == "B0_1_REDUCTION_DESCRIPTOR_BINDING_MISMATCH"); checks += 1

	var singular_request: Dictionary = request.duplicate(true)
	singular_request["linear_system"] = Fixture.make_linear_system(Fixture.INTERNAL_COUNT, 0, true)
	var singular_result := Compiler.compile(singular_request)
	assert(String(singular_result.get("status", "")) == CompileResult.NO_SAFE_BAKE); checks += 1
	assert(String(singular_result.get("reason", "")) == "RANK_DEFICIENCY"); checks += 1

	var non_passive_request: Dictionary = request.duplicate(true)
	non_passive_request["linear_system"] = Fixture.make_linear_system(Fixture.INTERNAL_COUNT, 0, false, true)
	var non_passive_result := Compiler.compile(non_passive_request)
	assert(String(non_passive_result.get("status", "")) == CompileResult.NO_SAFE_BAKE); checks += 1
	assert(String(non_passive_result.get("reason", "")) == "UNSAFE_ELIMINATION"); checks += 1

	var undersized_request: Dictionary = request.duplicate(true)
	undersized_request["linear_system"] = Fixture.make_linear_system(64)
	var undersized_result := Compiler.compile(undersized_request)
	assert(String(undersized_result.get("status", "")) == CompileResult.NO_SAFE_BAKE); checks += 1
	assert(String(undersized_result.get("reason", "")) == "INSUFFICIENT_COMPLEXITY_REDUCTION"); checks += 1

	var bad_dimension_request: Dictionary = request.duplicate(true)
	bad_dimension_request["boundary_contract"] = Fixture.make_boundary_contract([0, 1, -1, 0, 0, 0, 0])
	var bad_dimension_result := Compiler.compile(bad_dimension_request)
	assert(error_code(bad_dimension_result) == "B0_1_NON_POWER_CONJUGATE_BOUNDARY_DIMENSIONS"); checks += 1

	var mutated_fixture := Fixture.build(1)
	var changed_construction: Dictionary = mutated_fixture["construction"]
	var source_invalidation := RepresentationInvalidation.create(
		"invalidation/b0-1-network-r21",
		fixture["construction"],
		changed_construction,
		[0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
		"MUTATION",
		["scope/b0-1-network"],
		41
	)
	assert(not source_invalidation.is_empty()); checks += 1
	var current_frontier := Frontier.create([changed_construction, fixture["matter"]])
	var bake_invalidation := Bridge0.invalidate_from_source_mutation(
		artifact, source_invalidation, current_frontier, 41
	)
	assert(not bake_invalidation.is_empty()); checks += 1
	assert(String(bake_invalidation["reason"]) == "SOURCE_REVISION"); checks += 1
	var stale_live := Fixture.live_context(artifact, [bake_invalidation])
	assert(error_code(Runtime.execute(artifact, compiled_descriptor, stale_live, excitations[0])) == "STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN"); checks += 1

	var rebuilt_a := Compiler.compile(mutated_fixture["request"])
	var rebuilt_b := Compiler.compile(mutated_fixture["request"])
	assert(String(rebuilt_a.get("status", "")) == CompileResult.BAKE_READY); checks += 1
	assert(String(rebuilt_a["artifact"]["checksum"]) == String(rebuilt_b["artifact"]["checksum"])); checks += 1
	assert(String(rebuilt_a["diagnostics"]["reduction"]["checksum"]) == String(rebuilt_b["diagnostics"]["reduction"]["checksum"])); checks += 1
	assert(String(rebuilt_a["artifact"]["checksum"]) != String(artifact["checksum"])); checks += 1
	assert(String(rebuilt_a["diagnostics"]["reduction"]["checksum"]) != String(compiled_descriptor["checksum"])); checks += 1
	var rebuilt_live := Fixture.live_context(rebuilt_a["artifact"])
	assert(error_code(Runtime.execute(rebuilt_a["artifact"], compiled_descriptor, rebuilt_live, excitations[0])) == "B0_1_REDUCTION_DESCRIPTOR_BINDING_MISMATCH"); checks += 1

	print("FABRIC-BAKE B0.1 Acceptance: PASS (%d assertions) full=%d reduced=%d internal_rank=%d reduced_rank=%d work_ratio=%.1f max_flow_error=%s max_power_error=%s descriptor=%s artifact=%s" % [
		checks,
		int(compiled_descriptor["full_equation_count"]),
		int(compiled_descriptor["reduced_equation_count"]),
		int(compiled_descriptor["internal_rank"]),
		int(compiled_descriptor["reduced_rank"]),
		float(compiled_descriptor["runtime_work_ratio"]),
		maximum_flow_error,
		maximum_power_error,
		String(compiled_descriptor["checksum"]),
		String(artifact["checksum"]),
	])
	quit(0)

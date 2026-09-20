extends SceneTree

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/linear_conductance_component_graph_v1.gd")
const GraphCompiler = preload("res://scripts/research/fabric_bake0/linear_conductance_graph_compiler_v1.gd")
const Capsule = preload("res://scripts/research/fabric_bake0/behavior_capsule_contract_v1.gd")
const T1Compiler = preload("res://scripts/research/fabric_bake0/r5_t1_boundary_network_capsule_compiler_v1.gd")
const T1Runtime = preload("res://scripts/research/fabric_bake0/r5_t1_boundary_network_capsule_runtime_v1.gd")
const ExactCompiler = preload("res://scripts/research/fabric_bake0/exact_boundary_bake_compiler_v1.gd")
const Reducer = preload("res://scripts/research/fabric_bake0/exact_boundary_reducer_v1.gd")
const LinearAlgebra = preload("res://scripts/research/fabric_bake0/dense_linear_algebra_v1.gd")
const CompileResult = preload("res://scripts/research/fabric_bake0/bake_compile_result_v1.gd")
const Measure = preload("res://scripts/research/fabric_bake0/r5_measurement_harness_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_r5_2_t1_boundary_network_fixture.gd")

const HOT_LOOP_CALLS := 512

var checks := 0
var failed := false

func check(ok: bool, label: String, details = null) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("R5.2-T1: " + label + " " + JSON.stringify(details))

func begin_stage(m: Object, name: String) -> void:
	var result: Dictionary = m.begin_stage(name)
	check(result.success, "measurement begin " + name, result)

func end_stage(m: Object, name: String) -> void:
	var result: Dictionary = m.end_stage(name)
	check(result.success, "measurement end " + name, result)

func _initialize() -> void:
	var m = Measure.new("R5.2-T1-BOUNDARY-NETWORK-R1")
	var fixture := Fixture.build()
	check(not fixture.is_empty(), "fixture build")
	if fixture.is_empty():
		_finish()
		return
	var graph: Dictionary = fixture.graph
	check(Graph.validate(graph).success, "graph contract")
	check(graph.components.size() >= 500 and graph.components.size() <= 1000, "T1 internal component range", {"count": graph.components.size()})
	check(graph.nodes.size() == Fixture.BOUNDARY_COUNT + Fixture.INTERNAL_NODE_COUNT, "node count")

	var reversed_graph := Fixture.make_graph(0, false, false, true)
	check(not reversed_graph.is_empty(), "reordered graph builds")
	check(String(reversed_graph.graph_hash) == String(graph.graph_hash), "graph ordering invariant")

	begin_stage(m, "component_graph_to_linear_system")
	var graph_compiled := GraphCompiler.compile(graph)
	end_stage(m, "component_graph_to_linear_system")
	check(graph_compiled.success, "graph compiler", graph_compiled)
	if not graph_compiled.success:
		_finish()
		return
	check(int(graph_compiled.details.component_count) == graph.components.size(), "component count preserved")
	check(int(graph_compiled.details.internal_count) == Fixture.INTERNAL_NODE_COUNT, "internal node count")
	check(int(graph_compiled.details.boundary_count) == Fixture.BOUNDARY_COUNT, "boundary node count")

	begin_stage(m, "behavior_capsule_compile")
	var compiled := T1Compiler.compile(graph, fixture.request, "capsule/r5-t1-boundary-network")
	end_stage(m, "behavior_capsule_compile")
	check(compiled.success, "T1 capsule compile", compiled)
	if not compiled.success:
		_finish()
		return
	var capsule: Dictionary = compiled.details.capsule
	var artifact: Dictionary = compiled.details.artifact
	var descriptor: Dictionary = compiled.details.reduction
	var system: Dictionary = compiled.details.linear_system
	var request: Dictionary = compiled.details.bake_request
	check(Capsule.validate(capsule).success, "capsule contract")
	check(int(capsule.source_component_count) == graph.components.size(), "capsule source complexity")
	check(int(capsule.full_equation_count) == Fixture.BOUNDARY_COUNT + Fixture.INTERNAL_NODE_COUNT, "capsule full equations")
	check(int(capsule.executable_equation_count) == Fixture.BOUNDARY_COUNT, "capsule executable equations")
	check(float(capsule.equation_compression_ratio) >= 30.0, "equation compression", capsule)
	check(float(capsule.component_to_executable_ratio) >= 100.0, "component compression", capsule)
	check(int(capsule.runtime_source_traversals_per_execute) == 0, "runtime source traversal contract")
	check(String(capsule.fabric_graph_hash) == String(graph.graph_hash), "capsule graph provenance")

	var reversed_compiled := T1Compiler.compile(reversed_graph, Fixture.build(0, false, true).request, "capsule/r5-t1-boundary-network")
	check(reversed_compiled.success, "reordered compile")
	check(String(reversed_compiled.details.linear_system.system_hash) == String(system.system_hash), "linear compilation ordering invariant")
	check(String(reversed_compiled.details.reduction.checksum) == String(descriptor.checksum), "reduction ordering invariant")
	check(String(reversed_compiled.details.capsule.checksum) == String(capsule.checksum), "capsule ordering invariant")

	var excitations: Array = [
		[12.0, -7.0, 3.5, 0.25],
		[1.0, 0.0, 0.0, 0.0],
		[0.0, 1.0, -1.0, 0.0],
		[-4.25, 2.75, 8.5, -7.0],
		[100.0, 100.0, 100.0, 100.0],
		[-25.0, 14.0, 3.0, 8.0],
	]
	var live := ExactCompiler.live_context_from_request(request)
	check(not live.is_empty(), "live context")
	var maximum_flow_error := 0.0
	var maximum_power_error := 0.0

	begin_stage(m, "full_reference_excitation_batch")
	var full_rows: Array = []
	for effort in excitations:
		var full := Reducer.evaluate_full(system, effort, Fixture.PIVOT_TOLERANCE)
		check(full.success, "full reference excitation", full)
		full_rows.append(full)
	end_stage(m, "full_reference_excitation_batch")

	begin_stage(m, "capsule_excitation_batch")
	for index in range(excitations.size()):
		var executed := T1Runtime.execute(capsule, artifact, descriptor, live, excitations[index])
		check(executed.success, "capsule excitation", executed)
		if not executed.success:
			continue
		var full: Dictionary = full_rows[index]
		var flow_error := LinearAlgebra.max_abs_delta(full.details.boundary_flow, executed.details.boundary_flow)
		var power_error := absf(float(full.details.boundary_power) - float(executed.details.boundary_power))
		maximum_flow_error = maxf(maximum_flow_error, flow_error)
		maximum_power_error = maxf(maximum_power_error, power_error)
		check(flow_error <= float(request.error_envelope.flow_abs), "boundary flow equivalence", {"error": flow_error})
		check(power_error <= float(request.error_envelope.power_abs), "boundary power equivalence", {"error": power_error})
		check(int(executed.details.runtime_source_component_traversals) == 0, "no source component traversal")
	end_stage(m, "capsule_excitation_batch")

	begin_stage(m, "capsule_hot_loop")
	var hot_accumulator := 0.0
	for i in range(HOT_LOOP_CALLS):
		var effort: Array = excitations[i % excitations.size()]
		var executed := T1Runtime.execute(capsule, artifact, descriptor, live, effort)
		check(executed.success, "hot loop execution", {"index": i, "result": executed} if not executed.success else {})
		if executed.success:
			hot_accumulator += float(executed.details.boundary_power)
	end_stage(m, "capsule_hot_loop")
	check(is_finite(hot_accumulator), "hot loop finite")

	var foreign_descriptor := descriptor.duplicate(true)
	foreign_descriptor.schur_matrix[0][0] = float(foreign_descriptor.schur_matrix[0][0]) + 0.001
	foreign_descriptor.checksum = U.compute_checksum(foreign_descriptor)
	check(not T1Runtime.execute(capsule, artifact, foreign_descriptor, live, excitations[0]).success, "foreign descriptor fail closed")

	begin_stage(m, "mutation_recompile")
	var mutated_fixture := Fixture.build(1)
	var mutated := T1Compiler.compile(mutated_fixture.graph, mutated_fixture.request, "capsule/r5-t1-boundary-network")
	end_stage(m, "mutation_recompile")
	check(mutated.success, "mutated graph recompile", mutated)
	if mutated.success:
		check(String(mutated.details.capsule.checksum) != String(capsule.checksum), "mutation changes capsule")
		check(String(mutated.details.reduction.checksum) != String(descriptor.checksum), "mutation changes reduction")
		var mutated_live := ExactCompiler.live_context_from_request(mutated.details.bake_request)
		check(not T1Runtime.execute(capsule, artifact, descriptor, mutated_live, excitations[0]).success, "old capsule rejects mutated live graph")
		var new_exec := T1Runtime.execute(mutated.details.capsule, mutated.details.artifact, mutated.details.reduction, mutated_live, excitations[0])
		check(new_exec.success, "rebuilt capsule executes")

	begin_stage(m, "singular_fail_closed")
	var singular_fixture := Fixture.build(0, true)
	var singular := T1Compiler.compile(singular_fixture.graph, singular_fixture.request, "capsule/r5-t1-singular")
	end_stage(m, "singular_fail_closed")
	check(String(singular.get("status", "")) == CompileResult.NO_SAFE_BAKE, "singular graph NO_SAFE_BAKE", singular)
	check(String(singular.get("reason", "")) == "RANK_DEFICIENCY", "singular graph rank diagnostic", singular)

	var negative_graph := Fixture.make_graph(0, false, true)
	check(negative_graph.is_empty(), "negative conductance graph rejected before compile")

	var deterministic := {
		"schema": "planet_simulator.fabric_r5_2_t1_boundary_network_result.v1",
		"graph_hash": graph.graph_hash,
		"system_hash": system.system_hash,
		"capsule_checksum": capsule.checksum,
		"artifact_checksum": artifact.checksum,
		"descriptor_checksum": descriptor.checksum,
		"source_component_count": int(capsule.source_component_count),
		"internal_node_count": Fixture.INTERNAL_NODE_COUNT,
		"boundary_port_count": Fixture.BOUNDARY_COUNT,
		"full_equation_count": int(capsule.full_equation_count),
		"executable_equation_count": int(capsule.executable_equation_count),
		"runtime_source_traversals_per_execute": int(capsule.runtime_source_traversals_per_execute),
		"equation_compression_ratio": float(capsule.equation_compression_ratio),
		"component_to_executable_ratio": float(capsule.component_to_executable_ratio),
		"maximum_flow_error": maximum_flow_error,
		"maximum_power_error": maximum_power_error,
		"hot_loop_calls": HOT_LOOP_CALLS,
		"singular_status": String(singular.get("status", "")),
		"singular_reason": String(singular.get("reason", "")),
	}
	m.set_counter("source_components", int(capsule.source_component_count))
	m.set_counter("internal_nodes", Fixture.INTERNAL_NODE_COUNT)
	m.set_counter("boundary_ports", Fixture.BOUNDARY_COUNT)
	m.set_counter("full_equations", int(capsule.full_equation_count))
	m.set_counter("executable_equations", int(capsule.executable_equation_count))
	m.set_counter("runtime_source_traversals_per_execute", int(capsule.runtime_source_traversals_per_execute))
	m.set_counter("hot_loop_calls", HOT_LOOP_CALLS)
	var applicability := {
		"dynamic_state": {"applicable": false, "reason": "T1 is an exact stateless linear boundary capsule. Dynamic ROM begins at later fixtures."},
		"material_property_derivation": {"applicable": false, "reason": "T1 uses characterized conductance components; deriving cell/material properties is T3 Battery."},
	}
	var measured := m.finish(deterministic, applicability)
	check(measured.success, "measurement finalize", measured)
	if measured.success:
		print("FABRIC_R5_2_T1_DETERMINISTIC_HASH=" + String(measured.details.deterministic_hash))
		print("FABRIC_R5_2_T1_RESULT=" + JSON.stringify(measured.details))
	if not failed:
		print("FABRIC R5.2 T1 BOUNDARY NETWORK CAPSULE: PASS (%d assertions)" % checks)
	quit(1 if failed else 0)

func _finish() -> void:
	print("FABRIC R5.2 T1 BOUNDARY NETWORK CAPSULE: FAIL (%d assertions)" % checks)
	quit(1)

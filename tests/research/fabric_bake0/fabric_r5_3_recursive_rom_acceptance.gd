extends SceneTree
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Compiler = preload("res://scripts/research/fabric_bake0/r5_3_recursive_rom_compiler_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/r5_3_recursive_rom_runtime_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_r5_3_recursive_rom_fixture.gd")
const GraphCompiler = preload("res://scripts/research/fabric_bake0/linear_conductance_graph_compiler_v1.gd")
const Reducer = preload("res://scripts/research/fabric_bake0/exact_boundary_reducer_v1.gd")
const Linear = preload("res://scripts/research/fabric_bake0/dense_linear_algebra_v1.gd")
const Measure = preload("res://scripts/research/fabric_bake0/r5_measurement_harness_v1.gd")

const STEADY_CALLS := 512
const FLOW_TOL := 2.0e-8
const POWER_TOL := 2.0e-7
var checks := 0
var failures: Array = []
var max_flow_error := 0.0
var max_power_error := 0.0
var parity_rows := 0
var m = Measure.new("FABRIC-R5-3-RECURSIVE-ROM-R1")

func check(ok: bool, label: String, details = null) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("R5.3: " + label + " " + JSON.stringify(details))

func _paths(root: Dictionary) -> Array:
	var keys: Array = Compiler.manifest(root).keys(); keys.sort(); return keys

func _parity(runtime, node: Dictionary, path: String, label: String, efforts: Array) -> Dictionary:
	var graph: Dictionary = node.compiled_graph
	check(not graph.is_empty(), label + " compiled input graph")
	var compiled := GraphCompiler.compile(graph)
	check(compiled.success, label + " direct child-ROM graph compile", compiled)
	if not compiled.success: return {}
	for effort in efforts:
		var full := Reducer.evaluate_full(compiled.details.linear_system, effort, 1.0e-12)
		var compact: Dictionary = runtime.execute(path, effort)
		check(full.success and compact.success, label + " direct/ROM execute", {"full":full,"compact":compact})
		if not full.success or not compact.success: continue
		var ferr := Linear.max_abs_delta(full.details.boundary_flow, compact.details.boundary_flow)
		var perr := absf(float(full.details.boundary_power) - float(compact.details.boundary_power))
		max_flow_error = maxf(max_flow_error, ferr); max_power_error = maxf(max_power_error, perr); parity_rows += 1
		check(ferr <= FLOW_TOL, label + " boundary flow parity", {"error":ferr})
		check(perr <= POWER_TOL, label + " boundary power parity", {"error":perr})
		check(int(compact.details.runtime_source_component_traversals) == 0, label + " zero source traversal")
	return {"input_components":graph.components.size(), "input_nodes":graph.nodes.size(), "system_hash":compiled.details.linear_system.system_hash}

func _flat_module_parity(runtime, module: Dictionary, path: String, label: String, efforts: Array) -> Dictionary:
	var expanded := Fixture.expanded_graph(module)
	check(not expanded.is_empty(), label + " expanded leaf-source graph")
	if expanded.is_empty(): return {}
	var compiled := GraphCompiler.compile(expanded)
	check(compiled.success, label + " expanded leaf-source compile", compiled)
	if not compiled.success: return {}
	for effort in efforts:
		var full := Reducer.evaluate_full(compiled.details.linear_system, effort, 1.0e-12)
		var compact: Dictionary = runtime.execute(path, effort)
		check(full.success and compact.success, label + " flat-source/recursive execute", {"full":full,"compact":compact})
		if not full.success or not compact.success: continue
		var ferr := Linear.max_abs_delta(full.details.boundary_flow, compact.details.boundary_flow)
		var perr := absf(float(full.details.boundary_power) - float(compact.details.boundary_power))
		max_flow_error=maxf(max_flow_error,ferr);max_power_error=maxf(max_power_error,perr);parity_rows+=1
		check(ferr<=FLOW_TOL,label+" flat boundary flow parity",{"error":ferr})
		check(perr<=POWER_TOL,label+" flat boundary power parity",{"error":perr})
	return {"expanded_components":expanded.components.size(),"expanded_nodes":expanded.nodes.size(),"system_hash":compiled.details.linear_system.system_hash}

func _changed(old_root: Dictionary, new_root: Dictionary, expected: Array, label: String) -> Array:
	var actual := Compiler.changed_paths(old_root, new_root); var exp := expected.duplicate(); exp.sort(); actual.sort()
	check(actual == exp, label + " exact causal changed path", {"expected":exp,"actual":actual})
	return actual

func _refresh(runtime, new_root: Dictionary, changed: Array, expected_prepared: int, label: String) -> void:
	var wrong := changed.duplicate(); if not wrong.is_empty(): wrong.pop_back()
	var rejected: Dictionary = runtime.refresh(new_root, wrong)
	check(not rejected.success and rejected.error_code == "R5_3_RUNTIME_CHANGED_PATH_MISMATCH", label + " wrong refresh map rejected")
	var result: Dictionary = runtime.refresh(new_root, changed)
	check(result.success, label + " refresh", result)
	if result.success:
		check(int(result.details.prepared_sessions) == expected_prepared, label + " only changed sessions prepared", result.details)
		check(int(result.details.reused_sessions) == 15 - expected_prepared, label + " unaffected sessions reused", result.details)

func _initialize() -> void:
	m.begin_stage("baseline_hierarchy_compile")
	var built := Fixture.build_hierarchy()
	m.end_stage("baseline_hierarchy_compile")
	check(bool(built.get("success", false)), "baseline hierarchy build", built)
	if not bool(built.get("success", false)): _finish({}); return
	var root: Dictionary = built.details.root
	var manifest := Compiler.manifest(root)
	check(manifest.size() == 15 and int(built.details.leaf_count) == 8, "4-level 15-node hierarchy")
	check(int(root.level) == 3 and int(root.capsule.executable_equation_count) == 4, "machine ROM is four-equation executable")
	check(int(root.capsule.runtime_source_traversals_per_execute) == 0, "machine source traversal contract zero")
	check(int(root.physical_source_components) > int(root.compiled_input_components) * 10, "hidden physical complexity compressed", {"physical":root.physical_source_components,"compiled_input":root.compiled_input_components})
	check(int(root.compiled_input_components) < 40, "machine compile input bounded by child ROM ports", root.compiled_input_components)

	var runtime = Runtime.new()
	var prepared := runtime.prepare(root)
	check(prepared.success and int(prepared.details.node_count) == 15 and int(prepared.details.prepared_sessions) == 15, "all hierarchy ROMs prepare", prepared)
	var baseline_paths := _paths(root)
	for path in baseline_paths:
		var step := runtime.execute(String(path), [12.0,-7.0,3.5,0.25])
		check(step.success, "ROM executable at " + String(path), step)
		if step.success: check(int(step.details.runtime_source_component_traversals) == 0, "zero source traversal at " + String(path))
	var expanded_root := Fixture.expanded_graph(root)
	check(not expanded_root.is_empty() and int(root.physical_source_components) == expanded_root.components.size(), "root physical source accounting")
	var baseline_oracle := _parity(runtime, root, "root", "baseline root", Fixture.excitation_set())
	_parity(runtime, root.children.assembly0, "root/assembly0", "baseline assembly", [[12.0,-7.0,3.5,0.25]])
	_parity(runtime, root.children.assembly0.children.module0, "root/assembly0/module0", "baseline module", [[12.0,-7.0,3.5,0.25]])
	_flat_module_parity(runtime, root.children.assembly0.children.module0, "root/assembly0/module0", "baseline flat module oracle", [[12.0,-7.0,3.5,0.25],[1.0,0.0,0.0,0.0]])

	m.begin_stage("prepared_root_steady_execution")
	var accumulator := 0.0
	for i in range(STEADY_CALLS):
		var effort: Array = Fixture.excitation_set()[i % Fixture.excitation_set().size()]
		var step := runtime.execute_root(effort)
		check(step.success, "steady root execute %d" % i, step if not step.success else {})
		if step.success:
			accumulator += float(step.details.boundary_power)
			check(int(step.details.runtime_source_component_traversals) == 0, "steady root does not unfold sources")
	m.end_stage("prepared_root_steady_execution")
	check(is_finite(accumulator), "steady accumulator finite")

	var old_physical := int(root.physical_source_components); var old_compiled_input := int(root.compiled_input_components)
	var leaf := Fixture.compile_leaf("r53/leaf-0-0-0", 1, 2, 120)
	check(leaf.success, "leaf topology mutation recompiles", leaf)
	if not leaf.success: _finish(baseline_oracle); return
	var rebuilt := Compiler.rebuild_path(root, ["assembly0","module0","leaf0"], leaf.details)
	check(rebuilt.success, "leaf rebuild to root", rebuilt)
	if not rebuilt.success: _finish(baseline_oracle); return
	var leaf_root: Dictionary = rebuilt.details.root
	var leaf_changed := _changed(root, leaf_root, ["root","root/assembly0","root/assembly0/module0","root/assembly0/module0/leaf0"], "leaf mutation")
	check(int(rebuilt.details.compile_events) + 1 == 4, "leaf mutation rebuilds four hierarchy levels")
	check(leaf_root.children.assembly1.node_hash == root.children.assembly1.node_hash and leaf_root.children.assembly0.children.module1.node_hash == root.children.assembly0.children.module1.node_hash and leaf_root.children.assembly0.children.module0.children.leaf1.node_hash == root.children.assembly0.children.module0.children.leaf1.node_hash, "leaf mutation leaves siblings byte-identical by identity")
	check(int(leaf_root.physical_source_components) > old_physical, "hidden source complexity can grow locally")
	check(int(leaf_root.compiled_input_components) == old_compiled_input, "machine ROM compile size independent of hidden leaf growth")
	var stale := runtime.execute("root", [1.0,0.0,0.0,0.0], leaf_root.live)
	check(not stale.success, "old root session fenced by rebuilt live")
	_refresh(runtime, leaf_root, leaf_changed, 4, "leaf mutation")
	root = leaf_root
	_parity(runtime, root, "root", "after leaf mutation", [[12.0,-7.0,3.5,0.25],[-4.25,2.75,8.5,-7.0]])
	_flat_module_parity(runtime, root.children.assembly0.children.module0, "root/assembly0/module0", "after leaf flat module oracle", [[12.0,-7.0,3.5,0.25]])

	var module_old: Dictionary = root.children.assembly0.children.module0
	var module_new := Compiler.compose(String(module_old.node_id), 1, module_old.children, int(module_old.topology_revision) + 1, int(module_old.build_generation) + 1)
	check(module_new.success, "module-level UNBAKE/rebake", module_new)
	var module_rebuilt := Compiler.rebuild_path(root, ["assembly0","module0"], module_new.details)
	check(module_rebuilt.success, "module rebuild to root", module_rebuilt)
	var module_root: Dictionary = module_rebuilt.details.root
	var module_changed := _changed(root, module_root, ["root","root/assembly0","root/assembly0/module0"], "module mutation")
	check(int(module_rebuilt.details.compile_events) + 1 == 3, "module mutation rebuilds three hierarchy levels")
	check(module_root.children.assembly0.children.module0.children.leaf0.node_hash == root.children.assembly0.children.module0.children.leaf0.node_hash, "module mutation does not recompile leaves")
	_refresh(runtime, module_root, module_changed, 3, "module mutation")
	root = module_root
	_parity(runtime, root, "root", "after module mutation", [[1.0,0.0,0.0,0.0]])

	var assembly_old: Dictionary = root.children.assembly0
	var assembly_new := Compiler.compose(String(assembly_old.node_id), 2, assembly_old.children, int(assembly_old.topology_revision) + 1, int(assembly_old.build_generation) + 1)
	check(assembly_new.success, "assembly-level UNBAKE/rebake", assembly_new)
	var assembly_rebuilt := Compiler.rebuild_path(root, ["assembly0"], assembly_new.details)
	check(assembly_rebuilt.success, "assembly rebuild to root", assembly_rebuilt)
	var assembly_root: Dictionary = assembly_rebuilt.details.root
	var assembly_changed := _changed(root, assembly_root, ["root","root/assembly0"], "assembly mutation")
	check(int(assembly_rebuilt.details.compile_events) + 1 == 2, "assembly mutation rebuilds two hierarchy levels")
	_refresh(runtime, assembly_root, assembly_changed, 2, "assembly mutation")
	root = assembly_root
	_parity(runtime, root, "root", "after assembly mutation", [[0.0,1.0,-1.0,0.0]])

	var root_new := Compiler.compose(String(root.node_id), 3, root.children, int(root.topology_revision) + 1, int(root.build_generation) + 1)
	check(root_new.success, "machine-level rebake", root_new)
	var machine_root: Dictionary = root_new.details
	var machine_changed := _changed(root, machine_root, ["root"], "machine mutation")
	check(machine_root.children.assembly0.node_hash == root.children.assembly0.node_hash and machine_root.children.assembly1.node_hash == root.children.assembly1.node_hash, "machine mutation reuses both assemblies")
	_refresh(runtime, machine_root, machine_changed, 1, "machine mutation")
	root = machine_root
	var final_oracle := _parity(runtime, root, "root", "after machine mutation", Fixture.excitation_set())

	var bad_child: Dictionary = root.children.assembly0.duplicate(true)
	bad_child.reduction.reduced_rhs[0] = 1.0
	bad_child.reduction.checksum = U.compute_checksum(bad_child.reduction)
	bad_child.capsule.descriptor_checksum = String(bad_child.reduction.checksum)
	bad_child.capsule.checksum = U.compute_checksum(bad_child.capsule)
	bad_child.node_hash = Compiler._node_hash(bad_child.capsule, bad_child.reduction)
	bad_child.live.node_hash = bad_child.node_hash
	var rejected := Compiler.compose("r53/reject-affine", 3, {"bad":bad_child}, 0, 1)
	check(not rejected.success and rejected.error_code == "R5_3_CHILD_AFFINE_SOURCE_UNSUPPORTED", "unsupported child affine source NO_SAFE_BAKE boundary", rejected)

	var result := {
		"schema":"fabric.r5_3.recursive_rom.result.v1", "checks":checks, "failures":failures,
		"levels":4, "nodes":15, "leaves":8, "steady_calls":STEADY_CALLS,
		"baseline_physical_components":old_physical, "final_physical_components":int(root.physical_source_components),
		"machine_compiled_input_components":int(root.compiled_input_components), "machine_executable_equations":int(root.capsule.executable_equation_count),
		"max_flow_error":max_flow_error, "max_power_error":max_power_error, "parity_rows":parity_rows,
		"leaf_rebuild_levels":leaf_changed.size(), "module_rebuild_levels":module_changed.size(), "assembly_rebuild_levels":assembly_changed.size(), "machine_rebuild_levels":machine_changed.size(),
		"runtime_prepare_events":int(runtime.stats().prepare_events), "runtime_reuse_events":int(runtime.stats().reuse_events), "runtime_execute_events":int(runtime.stats().execute_events),
		"baseline_expanded_system_hash":String(baseline_oracle.get("system_hash", "")), "final_expanded_system_hash":String(final_oracle.get("system_hash", "")),
		"final_root_node_hash":String(root.node_hash), "final_root_capsule_checksum":String(root.capsule.checksum),
	}
	_finish(result)

func _finish(result: Dictionary) -> void:
	if result.is_empty(): result = {"schema":"fabric.r5_3.recursive_rom.result.v1", "checks":checks, "failures":failures}
	m.set_counter("checks", checks); m.set_counter("parity_rows", parity_rows); m.set_counter("steady_calls", STEADY_CALLS)
	var measured := m.finish({"result_hash":U.canonical_hash(result), "checks":checks}, {"scope":"R5.3 recursive exact-linear hierarchy; compile/rebuild and steady execution separated"})
	check(measured.success, "measurement finish", measured)
	result.checks = checks; result.failures = failures
	print("FABRIC_R5_3_RESULT=" + JSON.stringify(result, "", true, true))
	print("FABRIC_R5_3_MEASUREMENT=" + JSON.stringify(measured, "", true, true))
	print("FABRIC R5.3 RECURSIVE HIERARCHICAL EXECUTION: " + ("PASS" if failures.is_empty() else "FAIL") + " (%d assertions)" % checks)
	quit(0 if failures.is_empty() else 1)

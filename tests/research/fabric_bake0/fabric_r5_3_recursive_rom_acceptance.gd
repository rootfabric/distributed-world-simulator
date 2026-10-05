extends SceneTree
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Compiler = preload("res://scripts/research/fabric_bake0/r5_3_recursive_rom_compiler_v1.gd")
const T1 = preload("res://scripts/research/fabric_bake0/r5_t1_boundary_network_capsule_compiler_v1.gd")
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

func _rehash_node(node: Dictionary) -> Dictionary:
	node.reduction.checksum = U.compute_checksum(node.reduction)
	node.capsule.descriptor_checksum = String(node.reduction.checksum)
	node.capsule.checksum = U.compute_checksum(node.capsule)
	node.node_hash = Compiler._node_hash(node.capsule, node.reduction)
	node.live.node_hash = node.node_hash
	return node

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

func _leaf_provenance_falsifier() -> void:
	var graph_a := Fixture.leaf_graph("r53/provenance-a", 0, Fixture.LEAF_INTERNAL)
	var graph_b := Fixture.leaf_graph("r53/provenance-b", 1, Fixture.LEAF_INTERNAL)
	check(not graph_a.is_empty() and not graph_b.is_empty(), "T1 provenance falsifier graphs valid")
	check(String(graph_a.get("graph_hash", "")) != String(graph_b.get("graph_hash", "")), "T1 provenance falsifier graphs differ")
	if graph_a.is_empty() or graph_b.is_empty(): return
	var request := Compiler._request(graph_a, "r53/provenance-a", [], 0, 1)
	var compiled := T1.compile(graph_a, request, "capsule/r53-provenance-a")
	check(compiled.success, "T1 provenance source compile succeeds", compiled)
	if not compiled.success: return
	var rebound := Compiler.leaf_from_t1("r53/provenance-b", graph_b, compiled)
	check(not rebound.success and rebound.error_code == "R5_3_LEAF_T1_GRAPH_BINDING_MISMATCH", "R5.3 refuses T1 ROM rebound onto different source graph", rebound)
	var compiled_b := T1.compile(graph_b, Compiler._request(graph_b, "r53/provenance-b", [], 1, 1), "capsule/r53-provenance-b")
	check(compiled_b.success, "T1 provenance target compile succeeds", compiled_b)
	if compiled_b.success:
		var forged := compiled_b.duplicate(true)
		forged.details.reduction = compiled.details.reduction.duplicate(true)
		forged.details.artifact.reduced_model_descriptor_hash = String(forged.details.reduction.checksum)
		forged.details.artifact.checksum = U.compute_checksum(forged.details.artifact)
		forged.details.capsule.executable_descriptor_hash = String(forged.details.reduction.checksum)
		forged.details.capsule.physical_bake_artifact_checksum = String(forged.details.artifact.checksum)
		forged.details.capsule.checksum = U.compute_checksum(forged.details.capsule)
		var forged_rebound := Compiler.leaf_from_t1("r53/provenance-b", graph_b, forged)
		check(not forged_rebound.success and forged_rebound.error_code == "R5_3_LEAF_T1_SYSTEM_BINDING_MISMATCH", "R5.3 refuses descriptor rebound across source systems after contract rehash", forged_rebound)
		var forged_content := compiled_b.duplicate(true)
		forged_content.details.reduction = compiled.details.reduction.duplicate(true)
		forged_content.details.reduction.source_system_hash = String(compiled_b.details.linear_system.system_hash)
		forged_content.details.reduction.checksum = U.compute_checksum(forged_content.details.reduction)
		forged_content.details.artifact.reduced_model_descriptor_hash = String(forged_content.details.reduction.checksum)
		forged_content.details.artifact.checksum = U.compute_checksum(forged_content.details.artifact)
		forged_content.details.capsule.executable_descriptor_hash = String(forged_content.details.reduction.checksum)
		forged_content.details.capsule.physical_bake_artifact_checksum = String(forged_content.details.artifact.checksum)
		forged_content.details.capsule.checksum = U.compute_checksum(forged_content.details.capsule)
		var forged_content_rebound := Compiler.leaf_from_t1("r53/provenance-b", graph_b, forged_content)
		check(not forged_content_rebound.success and forged_content_rebound.error_code == "R5_3_LEAF_T1_CANONICAL_RECOMPILE_MISMATCH", "R5.3 refuses forged Schur content even after source-system/hash repair", forged_content_rebound)

func _initialize() -> void:
	_leaf_provenance_falsifier()
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
	var skipped_level := Compiler.compose("r53/invalid-machine-direct-leaf", 3, {"leaf0":root.children.assembly0.children.module0.children.leaf0}, 0, 1)
	check(not skipped_level.success and skipped_level.error_code == "R5_3_CHILD_LEVEL_MISMATCH", "parent composition cannot skip recursive hierarchy levels", skipped_level)
	var forged_parent: Dictionary = root.children.assembly0.duplicate(true)
	var forged_delta := 0.05
	forged_parent.reduction.schur_matrix[0][0] = float(forged_parent.reduction.schur_matrix[0][0]) + forged_delta
	forged_parent.reduction.schur_matrix[1][1] = float(forged_parent.reduction.schur_matrix[1][1]) + forged_delta
	forged_parent.reduction.schur_matrix[0][1] = float(forged_parent.reduction.schur_matrix[0][1]) - forged_delta
	forged_parent.reduction.schur_matrix[1][0] = float(forged_parent.reduction.schur_matrix[1][0]) - forged_delta
	forged_parent = _rehash_node(forged_parent)
	var forged_parent_checked := Compiler.validate_node(forged_parent)
	check(not forged_parent_checked.success and forged_parent_checked.error_code == "R5_3_PARENT_REDUCTION_BINDING_MISMATCH", "parent ROM content must match canonical child-ROM composition", forged_parent_checked)
	var forged_parent_composed := Compiler.compose("r53/reject-forged-parent", 3, {"assembly0":forged_parent,"assembly1":root.children.assembly1}, 0, 1)
	check(not forged_parent_composed.success and forged_parent_composed.error_code == "R5_3_CHILD_NODE_INVALID" and String(forged_parent_composed.details.cause.get("error_code", "")) == "R5_3_PARENT_REDUCTION_BINDING_MISMATCH", "forged parent ROM cannot enter higher-level composition", forged_parent_composed)

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

	# Transactional refresh falsifier: root + assembly sessions validate first, while
	# a deeper changed module is corrupted. A rejected refresh must leave every live
	# prepared session and registry counter untouched.
	var atomic_effort := [12.0,-7.0,3.5,0.25]
	var atomic_before := runtime.execute_root(atomic_effort)
	var atomic_stats_before := runtime.stats()
	var atomic_bad: Dictionary = leaf_root.duplicate(true)
	atomic_bad.children.assembly0.children.module0.compiled_graph.graph_hash = "0".repeat(64)
	var atomic_rejected := runtime.refresh(atomic_bad, leaf_changed)
	var atomic_after := runtime.execute_root(atomic_effort)
	var atomic_stats_after := runtime.stats()
	check(not atomic_rejected.success and atomic_rejected.error_code == "R5_3_CAPSULE_GRAPH_BINDING_MISMATCH", "failed deep prepare rejects refresh atomically", atomic_rejected)
	check(atomic_before.success and atomic_after.success, "atomicity probe root remains executable")
	if atomic_before.success and atomic_after.success:
		check(atomic_before.details.boundary_flow == atomic_after.details.boundary_flow and atomic_before.details.boundary_power == atomic_after.details.boundary_power, "rejected refresh leaves root execution byte-equivalent")
	check(String(runtime.bundle("root").node_hash) == String(root.node_hash), "rejected refresh leaves root bundle unchanged")
	check(int(atomic_stats_after.prepare_events) == int(atomic_stats_before.prepare_events) and int(atomic_stats_after.reuse_events) == int(atomic_stats_before.reuse_events), "rejected refresh leaves prepare/reuse counters unchanged")
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
	bad_child = _rehash_node(bad_child)
	var rejected := Compiler.compose("r53/reject-affine", 3, {"bad":bad_child}, 0, 1)
	check(not rejected.success and rejected.error_code == "R5_3_CHILD_AFFINE_SOURCE_UNSUPPORTED", "unsupported child affine source NO_SAFE_BAKE boundary", rejected)

	var bad_diagonal: Dictionary = root.children.assembly0.duplicate(true)
	bad_diagonal.reduction.schur_matrix[0][0] = float(bad_diagonal.reduction.schur_matrix[0][0]) + 1.0
	bad_diagonal = _rehash_node(bad_diagonal)
	var diagonal_rejected := Compiler.compose("r53/reject-diagonal", 3, {"bad":bad_diagonal}, 0, 1)
	check(not diagonal_rejected.success and diagonal_rejected.error_code == "R5_3_CHILD_ROM_LAPLACIAN_MISMATCH", "child ROM diagonal cannot be silently reconstructed", diagonal_rejected)

	var uncertified: Dictionary = root.children.assembly0.duplicate(true)
	uncertified.reduction.passivity_certified = false
	uncertified = _rehash_node(uncertified)
	var uncertified_rejected := Compiler.compose("r53/reject-uncertified", 3, {"bad":uncertified}, 0, 1)
	check(not uncertified_rejected.success and uncertified_rejected.error_code == "R5_3_CHILD_ROM_PASSIVITY_UNCERTIFIED", "uncertified child ROM cannot enter recursive composition", uncertified_rejected)

	var bad_ports: Dictionary = root.children.assembly0.duplicate(true)
	bad_ports.reduction.boundary_port_ids[3] = "port/electrical-z"
	bad_ports = _rehash_node(bad_ports)
	var ports_rejected := Compiler.compose("r53/reject-ports", 3, {"bad":bad_ports}, 0, 1)
	check(not ports_rejected.success and ports_rejected.error_code == "R5_3_CHILD_PORT_CONTRACT_UNSUPPORTED", "child boundary port semantics are exact", ports_rejected)

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

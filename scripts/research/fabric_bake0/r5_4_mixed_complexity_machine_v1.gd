extends RefCounted
## R5.4 mixed-complexity 100k machine research orchestrator.
## Reuses the closed R5.1 structural scale path and the closed R5.3 recursive-ROM
## path. This file owns only cross-representation causality/workset accounting.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Source = preload("res://scripts/research/fabric_bake0/complex3_streaming_canonical_structure_v1.gd")
const RangeIndex = preload("res://scripts/research/fabric_bake0/r5_range_aggregate_index_v1.gd")
const Life = preload("res://scripts/research/fabric_bake0/r5_indexed_sparse_damage_lifecycle_v1.gd")
const Compiler = preload("res://scripts/research/fabric_bake0/r5_3_recursive_rom_compiler_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/r5_3_recursive_rom_runtime_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_r5_3_recursive_rom_fixture.gd")

const SCHEMA := "planet_simulator.fabric_r5_4_mixed_complexity_machine.v1"
const MACHINE_PARTS := 100000
const LOCAL_RECURSIVE_PATH := ["assembly0", "module0", "leaf0"]
const LOCAL_EXPECTED_CHANGED := ["root", "root/assembly0", "root/assembly0/module0", "root/assembly0/module0/leaf0"]

var structural_source: Dictionary = {}
var structural_index: Dictionary = {}
var structural_runtime
var recursive_root: Dictionary = {}
var recursive_runtime
var local_event_count := 0
var global_event_count := 0
var local_recursive_changed := 0
var local_recursive_reused := 0
var global_recursive_changed := 0
var global_recursive_reused := 0
var global_structural_parts_scanned := 0
var steady_calls := 0
var last_machine_hash := ""

static func _build_recursive(revision: int, grown_leaf0: bool) -> Dictionary:
	var assemblies := {}
	for a in range(2):
		var modules := {}
		for m in range(2):
			var leaves := {}
			for l in range(2):
				var internal_count := Fixture.LEAF_INTERNAL
				if grown_leaf0 and a == 0 and m == 0 and l == 0:
					internal_count = 120
				var leaf: Dictionary = Fixture.compile_leaf("r53/leaf-%d-%d-%d" % [a,m,l], revision, revision + 1, internal_count)
				if not bool(leaf.get("success", false)):
					return leaf
				leaves["leaf%d" % l] = leaf.details
			var module: Dictionary = Compiler.compose("r53/module-%d-%d" % [a,m], 1, leaves, revision, revision + 1)
			if not bool(module.get("success", false)):
				return module
			modules["module%d" % m] = module.details
		var assembly: Dictionary = Compiler.compose("r53/assembly-%d" % a, 2, modules, revision, revision + 1)
		if not bool(assembly.get("success", false)):
			return assembly
		assemblies["assembly%d" % a] = assembly.details
	var machine: Dictionary = Compiler.compose("r53/machine", 3, assemblies, revision, revision + 1)
	if not bool(machine.get("success", false)):
		return machine
	return U.success(machine.details)

func initialize() -> Dictionary:
	if not structural_source.is_empty():
		return U.failure("R5_4_ALREADY_INITIALIZED")
	structural_source = Source.create_subject(MACHINE_PARTS, false)
	if not bool(structural_source.get("success", false)):
		return U.failure("R5_4_STRUCTURAL_SOURCE_FAILED", {"cause": structural_source})
	var index: Dictionary = RangeIndex.build(structural_source.spec)
	if not index.success:
		return U.failure("R5_4_RANGE_INDEX_FAILED", {"cause": index})
	structural_index = index.details.index
	var parent: Dictionary = RangeIndex.aggregate(structural_index, structural_source.spec, 0, MACHINE_PARTS)
	if not parent.success:
		return U.failure("R5_4_STRUCTURAL_PARENT_FAILED", {"cause": parent})
	structural_runtime = Life.new()
	var attached: Dictionary = structural_runtime.attach_range_index(structural_index, structural_source)
	if not attached.success:
		return attached
	var started: Dictionary = structural_runtime.start_baked(structural_source, parent.details.descriptor, Source.reference_state())
	if not started.success:
		return started
	var built: Dictionary = _build_recursive(0, false)
	if not built.success:
		return built
	recursive_root = built.details
	recursive_runtime = Runtime.new()
	var prepared: Dictionary = recursive_runtime.prepare(recursive_root)
	if not prepared.success:
		return prepared
	last_machine_hash = machine_hash()
	return U.success(status())

func execute_steady(boundary_effort: Array) -> Dictionary:
	if structural_runtime == null or recursive_runtime == null:
		return U.failure("R5_4_NOT_INITIALIZED")
	var structural: Dictionary = structural_runtime.execute_boundary(structural_source)
	if not structural.success:
		return structural
	var recursive: Dictionary = recursive_runtime.execute_root(boundary_effort)
	if not recursive.success:
		return recursive
	steady_calls += 1
	return U.success({
		"structural_mode": String(structural.details.mode),
		"recursive_node_hash": String(recursive.details.node_hash),
		"recursive_source_traversals": int(recursive.details.runtime_source_component_traversals),
		"recursive_equations": int(recursive.details.executable_equation_count),
		"machine_hash": machine_hash(),
	})

func local_damage_and_refine() -> Dictionary:
	if structural_runtime == null or recursive_runtime == null:
		return U.failure("R5_4_NOT_INITIALIZED")
	var before_root: Dictionary = recursive_root
	var local: Dictionary = structural_runtime.local_unbake(1, Life.IMPACT_LOAD)
	if not local.success:
		return U.failure("R5_4_STRUCTURAL_LOCAL_UNBAKE_FAILED", {"cause": local})
	var leaf: Dictionary = Fixture.compile_leaf("r53/leaf-0-0-0", 1, 2, 120)
	if not leaf.success:
		return U.failure("R5_4_RECURSIVE_LEAF_REFINE_FAILED", {"cause": leaf})
	var rebuilt: Dictionary = Compiler.rebuild_path(recursive_root, LOCAL_RECURSIVE_PATH, leaf.details)
	if not rebuilt.success:
		return U.failure("R5_4_RECURSIVE_REBUILD_FAILED", {"cause": rebuilt})
	var next_root: Dictionary = rebuilt.details.root
	var changed: Array = Compiler.changed_paths(recursive_root, next_root)
	changed.sort()
	var expected := LOCAL_EXPECTED_CHANGED.duplicate(); expected.sort()
	if changed != expected:
		return U.failure("R5_4_LOCAL_CAUSAL_WORKSET_MISMATCH", {"expected":expected,"actual":changed})
	var refreshed: Dictionary = recursive_runtime.refresh(next_root, changed)
	if not refreshed.success:
		return U.failure("R5_4_RECURSIVE_LOCAL_REFRESH_FAILED", {"cause": refreshed})
	recursive_root = next_root
	var successor: Dictionary = Source.create_subject(MACHINE_PARTS, true)
	if not bool(successor.get("success", false)):
		return U.failure("R5_4_STRUCTURAL_SUCCESSOR_FAILED", {"cause": successor})
	var observed: Dictionary = structural_runtime.observe_canonical_break(successor, "topology-event/r5-4-local-break", 2)
	if not observed.success:
		return U.failure("R5_4_STRUCTURAL_MUTATION_FAILED", {"cause": observed})
	var rebaked: Dictionary = structural_runtime.rebake_after_settle(true)
	if not rebaked.success:
		return U.failure("R5_4_STRUCTURAL_REBAKE_FAILED", {"cause": rebaked})
	structural_source = successor
	local_event_count += 1
	local_recursive_changed = changed.size()
	local_recursive_reused = int(refreshed.details.reused_sessions)
	last_machine_hash = machine_hash()
	return U.success({
		"changed_paths": changed,
		"prepared_sessions": int(refreshed.details.prepared_sessions),
		"reused_sessions": int(refreshed.details.reused_sessions),
		"structural_status": structural_runtime.status(),
		"recursive_physical_before": int(before_root.physical_source_components),
		"recursive_physical_after": int(recursive_root.physical_source_components),
		"machine_hash": last_machine_hash,
	})

func global_reconfigure() -> Dictionary:
	if structural_runtime == null or recursive_runtime == null:
		return U.failure("R5_4_NOT_INITIALIZED")
	# This is deliberately a true machine-wide causal event: the global structural
	# aggregate is re-derived and every recursive leaf receives a new source revision.
	var global: Dictionary = Source.aggregate_span(structural_source.spec, 0, MACHINE_PARTS)
	if not global.success:
		return U.failure("R5_4_GLOBAL_STRUCTURAL_REBUILD_FAILED", {"cause": global})
	var next: Dictionary = _build_recursive(2, true)
	if not next.success:
		return U.failure("R5_4_GLOBAL_RECURSIVE_REBUILD_FAILED", {"cause": next})
	var next_root: Dictionary = next.details
	var changed: Array = Compiler.changed_paths(recursive_root, next_root); changed.sort()
	if changed.size() != 15:
		return U.failure("R5_4_GLOBAL_CAUSAL_WORKSET_MISMATCH", {"changed": changed})
	var refreshed: Dictionary = recursive_runtime.refresh(next_root, changed)
	if not refreshed.success:
		return U.failure("R5_4_GLOBAL_RECURSIVE_REFRESH_FAILED", {"cause": refreshed})
	recursive_root = next_root
	global_event_count += 1
	global_structural_parts_scanned = int(global.details.parts_scanned)
	global_recursive_changed = changed.size()
	global_recursive_reused = int(refreshed.details.reused_sessions)
	last_machine_hash = machine_hash()
	return U.success({
		"changed_paths": changed,
		"prepared_sessions": int(refreshed.details.prepared_sessions),
		"reused_sessions": int(refreshed.details.reused_sessions),
		"structural_parts_scanned": global_structural_parts_scanned,
		"machine_hash": last_machine_hash,
	})

func machine_hash() -> String:
	if structural_source.is_empty() or recursive_root.is_empty():
		return ""
	return U.canonical_hash({
		"schema": SCHEMA,
		"structural_source_checksum": String(structural_source.spec.checksum),
		"recursive_root_node_hash": String(recursive_root.node_hash),
		"dependencies": {
			"local_structural_damage": LOCAL_EXPECTED_CHANGED,
			"global_reconfigure": "all-structural+all-recursive",
		},
	})

func status() -> Dictionary:
	var structural_status: Dictionary = {} if structural_runtime == null else structural_runtime.status()
	var recursive_stats: Dictionary = {} if recursive_runtime == null else recursive_runtime.stats()
	return {
		"schema": SCHEMA,
		"machine_parts": MACHINE_PARTS,
		"structural_mode": String(structural_status.get("mode", "")),
		"structural_active_full_parts": int(structural_status.get("active_full_parts", 0)),
		"structural_work": structural_status.get("work", {}).duplicate(true),
		"recursive_levels": 4,
		"recursive_nodes": int(recursive_stats.get("node_count", 0)),
		"recursive_physical_components": int(recursive_root.get("physical_source_components", 0)),
		"recursive_compiled_input_components": int(recursive_root.get("compiled_input_components", 0)),
		"recursive_executable_equations": int(recursive_root.get("capsule", {}).get("executable_equation_count", 0)),
		"recursive_prepare_events": int(recursive_stats.get("prepare_events", 0)),
		"recursive_reuse_events": int(recursive_stats.get("reuse_events", 0)),
		"recursive_execute_events": int(recursive_stats.get("execute_events", 0)),
		"local_event_count": local_event_count,
		"global_event_count": global_event_count,
		"local_recursive_changed": local_recursive_changed,
		"local_recursive_reused": local_recursive_reused,
		"global_recursive_changed": global_recursive_changed,
		"global_recursive_reused": global_recursive_reused,
		"global_structural_parts_scanned": global_structural_parts_scanned,
		"steady_calls": steady_calls,
		"machine_hash": machine_hash(),
	}

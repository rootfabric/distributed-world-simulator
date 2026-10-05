extends SceneTree
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Machine = preload("res://scripts/research/fabric_bake0/r5_4_mixed_complexity_machine_v1.gd")
const Measure = preload("res://scripts/research/fabric_bake0/r5_measurement_harness_v1.gd")

const STEADY_BEFORE := 128
const STEADY_AFTER_LOCAL := 128
const STEADY_AFTER_GLOBAL := 64
var checks := 0
var failures: Array = []
var m = Measure.new("FABRIC-R5-4-MIXED-100K-R1")

func check(ok: bool, label: String, details = null) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("R5.4: " + label + " " + JSON.stringify(details))

func stage_begin(name: String) -> void:
	check(m.begin_stage(name).success, "measurement begin " + name)

func stage_end(name: String) -> void:
	check(m.end_stage(name).success, "measurement end " + name)

func steady(machine, calls: int, label: String) -> void:
	for i in range(calls):
		var effort := [12.0 + float(i % 3), -7.0, 3.5, 0.25]
		var r: Dictionary = machine.execute_steady(effort)
		check(r.success, label + " execute", r)
		if r.success:
			check(int(r.details.recursive_source_traversals) == 0, label + " recursive zero hidden traversal")
			check(int(r.details.recursive_equations) == 4, label + " recursive four-equation root")

func _initialize() -> void:
	var machine = Machine.new()
	stage_begin("mixed_machine_build")
	var initialized: Dictionary = machine.initialize()
	stage_end("mixed_machine_build")
	check(initialized.success, "100k mixed machine initialize", initialized)
	if not initialized.success:
		_finish(machine); return
	var baseline: Dictionary = machine.status()
	check(int(baseline.machine_parts) == 100000, "canonical structural machine is 100k", baseline)
	check(int(baseline.recursive_levels) == 4 and int(baseline.recursive_nodes) == 15, "recursive subsystem has four levels and fifteen nodes", baseline)
	check(int(baseline.recursive_physical_components) == 1812, "baseline hidden recursive physical complexity", baseline)
	check(int(baseline.recursive_compiled_input_components) == 24, "machine recursive compile graph stays compact", baseline)
	check(int(baseline.recursive_executable_equations) == 4, "machine recursive executable stays four equations", baseline)
	check(int(baseline.structural_active_full_parts) == 0, "baseline structural detail fully baked")
	var baseline_hash := String(baseline.machine_hash)
	check(U.is_lower_hex_64(baseline_hash), "baseline machine identity")

	stage_begin("steady_before")
	steady(machine, STEADY_BEFORE, "baseline steady")
	stage_end("steady_before")

	stage_begin("local_damage_refine")
	var local: Dictionary = machine.local_damage_and_refine()
	stage_end("local_damage_refine")
	check(local.success, "local mixed-complexity damage/refine", local)
	if not local.success:
		_finish(machine); return
	var local_status: Dictionary = machine.status()
	check(int(local.details.prepared_sessions) == 4 and int(local.details.reused_sessions) == 11, "local event prepares only causal recursive path", local.details)
	check(int(local_status.local_recursive_changed) == 4 and int(local_status.local_recursive_reused) == 11, "local recursive workset exact 4/11", local_status)
	check(int(local_status.structural_work.active_full_peak) == 20, "local structural FULL peak remains twenty", local_status.structural_work)
	check(int(local_status.structural_work.local_reconstructed_parts) == 20, "local structural reconstruction remains twenty", local_status.structural_work)
	check(int(local_status.structural_work.metadata_parts_scanned) == 0, "local indexed lifecycle performs zero O(N) residual scans", local_status.structural_work)
	check(int(local_status.structural_work.range_query_count) == 4 and int(local_status.structural_work.range_query_prefix_reads) == 80, "local structural queries bounded", local_status.structural_work)
	check(int(local_status.structural_work.global_physical_rebuilds) == 0, "local event causes no global structural rebuild", local_status.structural_work)
	check(int(local.details.recursive_physical_before) == 1812 and int(local.details.recursive_physical_after) == 1852, "local hidden complexity grows without global expansion", local.details)
	check(int(local_status.recursive_compiled_input_components) == 24 and int(local_status.recursive_executable_equations) == 4, "local refinement does not inflate machine executable", local_status)
	check(String(local_status.machine_hash) != baseline_hash, "local event advances machine identity")

	stage_begin("steady_after_local")
	steady(machine, STEADY_AFTER_LOCAL, "post-local steady")
	stage_end("steady_after_local")

	stage_begin("global_causal_reconfigure")
	var global: Dictionary = machine.global_reconfigure()
	stage_end("global_causal_reconfigure")
	check(global.success, "global causal reconfigure", global)
	if not global.success:
		_finish(machine); return
	var global_status: Dictionary = machine.status()
	check(int(global.details.structural_parts_scanned) == 100000, "global event may scan full 100k because causality is global", global.details)
	check(int(global.details.prepared_sessions) == 15 and int(global.details.reused_sessions) == 0, "global event invalidates full recursive hierarchy", global.details)
	check(int(global_status.global_recursive_changed) == 15 and int(global_status.global_recursive_reused) == 0, "global recursive workset exact", global_status)
	check(int(global_status.recursive_physical_components) == 1852, "global reconfigure preserves grown local physical complexity", global_status)
	check(int(global_status.recursive_compiled_input_components) == 24 and int(global_status.recursive_executable_equations) == 4, "global rebuild returns to compact root executable", global_status)

	stage_begin("steady_after_global")
	steady(machine, STEADY_AFTER_GLOBAL, "post-global steady")
	stage_end("steady_after_global")

	var final: Dictionary = machine.status()
	check(int(final.steady_calls) == STEADY_BEFORE + STEADY_AFTER_LOCAL + STEADY_AFTER_GLOBAL, "steady call accounting exact", final)
	check(int(final.local_event_count) == 1 and int(final.global_event_count) == 1, "local/global event accounting exact", final)
	check(U.is_lower_hex_64(String(final.machine_hash)), "final machine identity")

	m.set_counter("machine_parts", int(final.machine_parts))
	m.set_counter("recursive_nodes", int(final.recursive_nodes))
	m.set_counter("recursive_levels", int(final.recursive_levels))
	m.set_counter("baseline_recursive_physical_components", 1812)
	m.set_counter("final_recursive_physical_components", int(final.recursive_physical_components))
	m.set_counter("recursive_compiled_input_components", int(final.recursive_compiled_input_components))
	m.set_counter("recursive_executable_equations", int(final.recursive_executable_equations))
	m.set_counter("local_full_peak", int(final.structural_work.active_full_peak))
	m.set_counter("local_recursive_changed", int(final.local_recursive_changed))
	m.set_counter("global_recursive_changed", int(final.global_recursive_changed))
	m.set_counter("global_structural_parts_scanned", int(final.global_structural_parts_scanned))
	m.set_counter("steady_calls", int(final.steady_calls))
	var deterministic := {
		"schema": "fabric.r5_4.mixed_complexity_100k.result.v1",
		"checks": checks + 1,
		"failures": failures.duplicate(),
		"machine_parts": int(final.machine_parts),
		"recursive_levels": int(final.recursive_levels),
		"recursive_nodes": int(final.recursive_nodes),
		"baseline_recursive_physical_components": 1812,
		"final_recursive_physical_components": int(final.recursive_physical_components),
		"recursive_compiled_input_components": int(final.recursive_compiled_input_components),
		"recursive_executable_equations": int(final.recursive_executable_equations),
		"local_full_peak": int(final.structural_work.active_full_peak),
		"local_reconstructed_parts": int(final.structural_work.local_reconstructed_parts),
		"local_metadata_parts_scanned": int(final.structural_work.metadata_parts_scanned),
		"local_range_query_count": int(final.structural_work.range_query_count),
		"local_range_query_prefix_reads": int(final.structural_work.range_query_prefix_reads),
		"local_recursive_changed": int(final.local_recursive_changed),
		"local_recursive_reused": int(final.local_recursive_reused),
		"global_structural_parts_scanned": int(final.global_structural_parts_scanned),
		"global_recursive_changed": int(final.global_recursive_changed),
		"global_recursive_reused": int(final.global_recursive_reused),
		"steady_calls": int(final.steady_calls),
		"final_machine_hash": String(final.machine_hash),
	}
	var measured: Dictionary = m.finish(deterministic, {
		"wall_time": {"applicable": false, "reason": "observational only"},
		"production_integration": {"applicable": false, "reason": "R5.4 research subject only"},
	})
	check(measured.success, "measurement finalize", measured)
	if measured.success:
		deterministic.checks = checks
		deterministic.failures = failures.duplicate()
		print("FABRIC_R5_4_RESULT=" + JSON.stringify(deterministic))
		print("FABRIC_R5_4_DETERMINISTIC_HASH=" + U.canonical_hash(deterministic))
	_finish(machine)

func _finish(machine) -> void:
	if failures.is_empty():
		print("FABRIC R5.4 MIXED COMPLEXITY 100K MACHINE: PASS (%d assertions)" % checks)
		quit(0)
	else:
		print("FABRIC R5.4 MIXED COMPLEXITY 100K MACHINE: FAIL (%d assertions, %d failures)" % [checks, failures.size()])
		quit(1)

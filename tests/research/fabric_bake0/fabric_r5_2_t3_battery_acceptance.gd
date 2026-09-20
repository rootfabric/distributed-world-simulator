extends SceneTree

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/battery_cell_graph_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/battery_pack_descriptor_v1.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/battery_execution_artifact_v1.gd")
const Capsule = preload("res://scripts/research/fabric_bake0/behavior_capsule_contract_v2.gd")
const Compiler = preload("res://scripts/research/fabric_bake0/r5_t3_battery_compiler_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/r5_t3_battery_runtime_v1.gd")
const FullReference = preload("res://scripts/research/fabric_bake0/r5_t3_battery_full_reference_v1.gd")
const Measure = preload("res://scripts/research/fabric_bake0/r5_measurement_harness_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_r5_2_t3_battery_fixture.gd")

const SEQUENCE_TICKS := 2048
const FULL_HOT_CALLS := 4096
const CAPSULE_HOT_CALLS := 32768

var checks := 0
var failed := false

func check(ok: bool, label: String, details = null) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("R5.2-T3: " + label + " " + JSON.stringify(details))

func begin_stage(m: Object, name: String) -> void:
	var r: Dictionary = m.begin_stage(name)
	check(r.success, "measurement begin " + name, r)

func end_stage(m: Object, name: String) -> void:
	var r: Dictionary = m.end_stage(name)
	check(r.success, "measurement end " + name, r)

func max_charge_error(a: Array, b: Array) -> float:
	if a.size() != b.size():
		return INF
	var out := 0.0
	for index in range(a.size()):
		out = maxf(out, absf(float(a[index]) - float(b[index])))
	return out

func sum_numbers(values: Array) -> float:
	var total := 0.0
	for value in values:
		total += float(value)
	return total

func compile_graph(graph: Dictionary, revision: int = 0) -> Dictionary:
	return Compiler.compile(graph, Fixture.build_request(graph, revision), "capsule/r5-t3-battery")

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--preflight":
			var preflight_graph := Fixture.make_graph()
			var preflight_compile := compile_graph(preflight_graph)
			var preflight_reference := FullReference.prepare(preflight_graph)
			if not preflight_compile.success or not preflight_reference.success:
				print("FABRIC_R5_2_T3_PREFLIGHT=FAIL")
				quit(1)
				return
			print("FABRIC_R5_2_T3_PREFLIGHT=PASS")
			quit(0)
			return

	var m = Measure.new("R5.2-T3-BATTERY-CELLS-MATERIALS-R1")
	var base_graph := Fixture.make_graph()
	var reversed_graph := Fixture.make_graph("LFP", 1.0, false, false, false, false, true)
	check(Graph.validate(base_graph).success, "base battery graph")
	check(base_graph.cells.size() == Fixture.CELL_COUNT, "96-cell source", {"count": base_graph.cells.size()})
	check(String(base_graph.graph_hash) == String(reversed_graph.graph_hash), "raw ordering invariant")

	begin_stage(m, "base_compile")
	var compiled := compile_graph(base_graph)
	end_stage(m, "base_compile")
	check(compiled.success, "base battery compile", compiled)
	if not compiled.success:
		_finish()
		return
	var descriptor: Dictionary = compiled.details.descriptor
	var artifact: Dictionary = compiled.details.artifact
	var capsule: Dictionary = compiled.details.capsule
	check(Descriptor.validate(descriptor).success, "battery descriptor")
	check(Artifact.verify_descriptor(artifact, descriptor).success, "battery artifact")
	check(Capsule.validate(capsule).success, "battery capsule")
	check(int(descriptor.source_cell_count) == 96 and int(descriptor.active_cell_count) == 96, "base cell counts")
	check(int(descriptor.series_group_count) == 12, "series group count")
	check(int(capsule.runtime_source_traversals_per_execute) == 0, "capsule source traversal contract")
	check(float(capsule.operation_compression_ratio) > 5.0, "operation compression", capsule)
	check(float(capsule.component_to_executable_ratio) > 2.0, "component/executable compression", capsule)

	var reversed_compiled := compile_graph(reversed_graph)
	check(reversed_compiled.success, "reordered compile")
	check(reversed_compiled.success and String(reversed_compiled.details.descriptor.descriptor_hash) == String(descriptor.descriptor_hash), "descriptor ordering invariant")
	check(reversed_compiled.success and String(reversed_compiled.details.capsule.checksum) == String(capsule.checksum), "capsule ordering invariant")

	var runtime = Runtime.new()
	var live := Fixture.live_from(artifact)
	begin_stage(m, "runtime_prepare")
	var prepared := runtime.prepare(capsule, artifact, descriptor, live)
	end_stage(m, "runtime_prepare")
	check(prepared.success, "battery runtime prepare", prepared)
	if not prepared.success:
		_finish()
		return

	var reference_plan_result := FullReference.prepare(base_graph)
	check(reference_plan_result.success, "full reference prepare", reference_plan_result)
	if not reference_plan_result.success:
		_finish()
		return
	var reference_plan: Dictionary = reference_plan_result.details
	var capsule_state := runtime.initial_state(0.82, 300.0)
	var full_state := FullReference.initial_state(reference_plan, 0.82, 300.0)
	check(not capsule_state.is_empty() and not full_state.is_empty(), "initial states")
	check(max_charge_error(capsule_state.group_charge_c, full_state.group_charge_c) <= 1.0e-9, "initial charge parity")

	var max_voltage_error := 0.0
	var max_heat_error := 0.0
	var max_charge_state_error := 0.0
	var max_temperature_error := 0.0
	var max_energy_residual := 0.0
	var full_traversals := 0

	begin_stage(m, "full_vs_capsule_sequence")
	for tick in range(SEQUENCE_TICKS):
		var current := 15.0
		if tick % 17 == 0:
			current = -8.0
		elif tick % 5 == 0:
			current = 30.0
		var ambient := 298.15 + 0.01 * float((tick % 20) - 10)
		var dt := 0.25
		var full := FullReference.execute(reference_plan, full_state, current, dt, ambient)
		var fast := runtime.execute(live, capsule_state, current, dt, ambient)
		check(full.success, "full sequence step", {"tick": tick, "result": full} if not full.success else {})
		check(fast.success, "capsule sequence step", {"tick": tick, "result": fast} if not fast.success else {})
		if not full.success or not fast.success:
			break
		max_voltage_error = maxf(max_voltage_error, absf(float(full.details.terminal_voltage_v) - float(fast.details.terminal_voltage_v)))
		max_heat_error = maxf(max_heat_error, absf(float(full.details.heat_generated_j) - float(fast.details.heat_generated_j)))
		max_charge_state_error = maxf(max_charge_state_error, max_charge_error(full.details.next_state.group_charge_c, fast.details.next_state.group_charge_c))
		max_temperature_error = maxf(max_temperature_error, absf(float(full.details.next_state.temperature_k) - float(fast.details.next_state.temperature_k)))
		max_energy_residual = maxf(max_energy_residual, absf(float(fast.details.energy_residual_j)))
		full_traversals += int(full.details.source_cell_traversals)
		full_state = full.details.next_state
		capsule_state = fast.details.next_state
	end_stage(m, "full_vs_capsule_sequence")
	check(max_voltage_error <= 1.0e-9, "sequence voltage equivalence", {"error": max_voltage_error})
	check(max_heat_error <= 1.0e-9, "sequence heat equivalence", {"error": max_heat_error})
	check(max_charge_state_error <= 1.0e-9, "sequence charge equivalence", {"error": max_charge_state_error})
	check(max_temperature_error <= 1.0e-9, "sequence temperature equivalence", {"error": max_temperature_error})
	check(max_energy_residual <= 1.0e-7, "capsule energy conservation", {"residual": max_energy_residual})
	check(full_traversals == SEQUENCE_TICKS * Fixture.CELL_COUNT, "full reference traverses all cells", {"traversals": full_traversals})
	check(int(prepared.details.runtime_source_cell_traversals) == 0, "prepared runtime traverses zero cells")

	var hot_state := runtime.initial_state(0.75, 300.0)
	var full_hot_state := FullReference.initial_state(reference_plan, 0.75, 300.0)
	begin_stage(m, "full_reference_hot_loop")
	var full_acc := 0.0
	for i in range(FULL_HOT_CALLS):
		var current := 20.0 if i % 3 != 0 else -6.0
		var full := FullReference.execute(reference_plan, full_hot_state, current, 0.1, 298.15)
		check(full.success, "full hot loop", {"index": i} if not full.success else {})
		if full.success:
			full_acc += float(full.details.terminal_voltage_v)
	end_stage(m, "full_reference_hot_loop")

	begin_stage(m, "capsule_hot_loop")
	var capsule_acc := 0.0
	for i in range(CAPSULE_HOT_CALLS):
		var current := 20.0 if i % 3 != 0 else -6.0
		var fast := runtime.execute(live, hot_state, current, 0.1, 298.15)
		check(fast.success, "capsule hot loop", {"index": i} if not fast.success else {})
		if fast.success:
			capsule_acc += float(fast.details.terminal_voltage_v)
	end_stage(m, "capsule_hot_loop")
	check(is_finite(full_acc + capsule_acc), "hot-loop accumulators")

	begin_stage(m, "material_variant_compile")
	var nmc_graph := Fixture.make_graph("NMC")
	var nmc := compile_graph(nmc_graph)
	end_stage(m, "material_variant_compile")
	check(nmc.success, "NMC material variant compile", nmc)
	if nmc.success:
		var base_specific_energy := float(descriptor.full_chemical_energy_j) / float(descriptor.total_mass_kg)
		var nmc_specific_energy := float(nmc.details.descriptor.full_chemical_energy_j) / float(nmc.details.descriptor.total_mass_kg)
		check(nmc_specific_energy > base_specific_energy, "material changes derived specific energy", {"lfp": base_specific_energy, "nmc": nmc_specific_energy})
		check(float(nmc.details.descriptor.nominal_voltage_v) > float(descriptor.nominal_voltage_v), "material changes nominal voltage")

	begin_stage(m, "quality_variant_compile")
	var lower_quality_graph := Fixture.make_graph("LFP", 0.85)
	var lower_quality := compile_graph(lower_quality_graph)
	end_stage(m, "quality_variant_compile")
	check(lower_quality.success, "quality variant compile", lower_quality)
	if lower_quality.success:
		check(float(lower_quality.details.descriptor.group_capacity_c[0]) < float(descriptor.group_capacity_c[0]), "quality lowers capacity")
		check(float(lower_quality.details.descriptor.group_resistance_ref_ohm[0]) > float(descriptor.group_resistance_ref_ohm[0]), "quality raises resistance")
		check(float(lower_quality.details.descriptor.max_continuous_current_a) < float(descriptor.max_continuous_current_a), "quality lowers current capability")
		check(absf(float(lower_quality.details.descriptor.total_mass_kg) - float(descriptor.total_mass_kg)) <= 1.0e-9, "quality does not invent/remove mass")

	begin_stage(m, "damage_recompile")
	var damaged_graph := Fixture.make_graph("LFP", 1.0, true)
	var damaged := compile_graph(damaged_graph, 1)
	end_stage(m, "damage_recompile")
	check(damaged.success, "damaged pack recompile", damaged)
	if damaged.success:
		var affected := 5
		check(int(damaged.details.descriptor.active_cell_count) == 95, "one disabled cell")
		check(float(damaged.details.descriptor.group_capacity_c[affected]) < float(descriptor.group_capacity_c[affected]), "damage lowers affected group capacity")
		check(float(damaged.details.descriptor.group_resistance_ref_ohm[affected]) > float(descriptor.group_resistance_ref_ohm[affected]), "damage raises affected group resistance")
		check(float(damaged.details.descriptor.max_continuous_current_a) < float(descriptor.max_continuous_current_a), "damage lowers pack current limit")
		check(absf(float(damaged.details.descriptor.total_mass_kg) - float(descriptor.total_mass_kg)) <= 1.0e-9, "disabled cell remains physical mass")
		var damaged_live := Fixture.live_from(damaged.details.artifact)
		check(not runtime.execute(damaged_live, hot_state, 5.0, 0.1, 298.15).success, "old capsule rejects damaged graph")
		var damaged_runtime = Runtime.new()
		check(damaged_runtime.prepare(damaged.details.capsule, damaged.details.artifact, damaged.details.descriptor, damaged_live).success, "damaged capsule prepare")
		var damaged_state := damaged_runtime.initial_state(0.75, 300.0)
		check(damaged_runtime.execute(damaged_live, damaged_state, 5.0, 0.1, 298.15).success, "damaged capsule executes")

	var mismatch_request := Fixture.build_request(nmc_graph if nmc.success else Fixture.make_graph("NMC"), 2)
	var mismatch := Compiler.compile(base_graph, mismatch_request, "capsule/r5-t3-battery")
	check(not mismatch.success and String(mismatch.error_code) == "BATTERY_CANONICAL_GRAPH_SOURCE_MISMATCH", "graph/frontier mismatch rejected", mismatch)

	begin_stage(m, "mixed_parallel_fail_closed")
	var mixed := compile_graph(Fixture.make_graph("LFP", 1.0, false, false, true))
	end_stage(m, "mixed_parallel_fail_closed")
	check(not mixed.success and String(mixed.error_code) == "BATTERY_PARALLEL_PROFILE_MISMATCH", "mixed parallel chemistry fail closed", mixed)

	begin_stage(m, "unsafe_geometry_fail_closed")
	var unsafe_geometry := compile_graph(Fixture.make_graph("LFP", 1.0, false, true))
	end_stage(m, "unsafe_geometry_fail_closed")
	check(not unsafe_geometry.success and String(unsafe_geometry.error_code) == "BATTERY_PARALLEL_SOC_SYNCHRONY_UNSAFE", "unsafe geometry fail closed", unsafe_geometry)

	begin_stage(m, "open_group_fail_closed")
	var open_group := compile_graph(Fixture.make_graph("LFP", 1.0, false, false, false, true))
	end_stage(m, "open_group_fail_closed")
	check(not open_group.success and String(open_group.error_code) == "BATTERY_SERIES_GROUP_OPEN", "open series group fail closed", open_group)

	var over_current := runtime.execute(live, hot_state, float(descriptor.max_continuous_current_a) * 1.01, 0.1, 298.15)
	check(not over_current.success and String(over_current.error_code) == "BATTERY_RUNTIME_CURRENT_LIMIT", "current limit fail closed")
	var stale_live: Dictionary = live.duplicate(true)
	stale_live.artifact_state = "STALE"
	check(not runtime.execute(stale_live, hot_state, 5.0, 0.1, 298.15).success, "STALE fail closed")
	var invalidated_live: Dictionary = live.duplicate(true)
	invalidated_live.invalidations = [{"synthetic": true}]
	check(not runtime.execute(invalidated_live, hot_state, 5.0, 0.1, 298.15).success, "invalidation fail closed")
	var authority_drift: Dictionary = live.duplicate(true)
	authority_drift.authority_envelope = live.authority_envelope.duplicate(true)
	authority_drift.authority_envelope.checksum = "0".repeat(64)
	check(not runtime.execute(authority_drift, hot_state, 5.0, 0.1, 298.15).success, "authority drift fail closed")

	var deterministic := {
		"schema": "planet_simulator.fabric_r5_2_t3_battery_result.v1",
		"graph_hash": base_graph.graph_hash,
		"descriptor_hash": descriptor.descriptor_hash,
		"capsule_checksum": capsule.checksum,
		"source_cells": int(descriptor.source_cell_count),
		"active_cells": int(descriptor.active_cell_count),
		"series_groups": int(descriptor.series_group_count),
		"state_scalar_count": int(descriptor.series_group_count) + 1,
		"source_operations": int(descriptor.source_operation_count),
		"compiled_operations": int(descriptor.compiled_operation_count),
		"runtime_source_cell_traversals": 0,
		"nominal_voltage_v": float(descriptor.nominal_voltage_v),
		"full_voltage_v": float(descriptor.full_voltage_v),
		"empty_voltage_v": float(descriptor.empty_voltage_v),
		"total_mass_kg": float(descriptor.total_mass_kg),
		"full_chemical_energy_j": float(descriptor.full_chemical_energy_j),
		"full_specific_energy_wh_kg": float(descriptor.full_chemical_energy_j) / 3600.0 / float(descriptor.total_mass_kg),
		"max_continuous_current_a": float(descriptor.max_continuous_current_a),
		"pack_resistance_ref_ohm": sum_numbers(descriptor.group_resistance_ref_ohm),
		"group0_capacity_c": float(descriptor.group_capacity_c[0]),
		"thermal_capacity_j_k": float(descriptor.thermal_capacity_j_k),
		"thermal_conductance_w_k": float(descriptor.thermal_conductance_w_k),
		"nmc_specific_energy_wh_kg": float(nmc.details.descriptor.full_chemical_energy_j) / 3600.0 / float(nmc.details.descriptor.total_mass_kg) if nmc.success else -1.0,
		"lower_quality_group0_capacity_c": float(lower_quality.details.descriptor.group_capacity_c[0]) if lower_quality.success else -1.0,
		"lower_quality_group0_resistance_ohm": float(lower_quality.details.descriptor.group_resistance_ref_ohm[0]) if lower_quality.success else -1.0,
		"lower_quality_max_current_a": float(lower_quality.details.descriptor.max_continuous_current_a) if lower_quality.success else -1.0,
		"damaged_group5_capacity_c": float(damaged.details.descriptor.group_capacity_c[5]) if damaged.success else -1.0,
		"damaged_group5_resistance_ohm": float(damaged.details.descriptor.group_resistance_ref_ohm[5]) if damaged.success else -1.0,
		"damaged_max_current_a": float(damaged.details.descriptor.max_continuous_current_a) if damaged.success else -1.0,
		"sequence_ticks": SEQUENCE_TICKS,
		"maximum_voltage_error": max_voltage_error,
		"maximum_heat_error": max_heat_error,
		"maximum_charge_state_error": max_charge_state_error,
		"maximum_temperature_error": max_temperature_error,
		"maximum_energy_residual_j": max_energy_residual,
		"damage_active_cells": int(damaged.details.descriptor.active_cell_count) if damaged.success else -1,
		"mixed_error": String(mixed.get("error_code", "")),
		"unsafe_geometry_error": String(unsafe_geometry.get("error_code", "")),
		"open_group_error": String(open_group.get("error_code", "")),
	}
	m.set_counter("source_cells", int(descriptor.source_cell_count))
	m.set_counter("active_cells", int(descriptor.active_cell_count))
	m.set_counter("series_groups", int(descriptor.series_group_count))
	m.set_counter("state_scalars", int(descriptor.series_group_count) + 1)
	m.set_counter("sequence_ticks", SEQUENCE_TICKS)
	m.set_counter("full_reference_cell_traversals", full_traversals)
	m.set_counter("runtime_source_cell_traversals_per_execute", 0)
	m.set_counter("full_hot_calls", FULL_HOT_CALLS)
	m.set_counter("capsule_hot_calls", CAPSULE_HOT_CALLS)
	var measured := m.finish(deterministic, {
		"electrochemical_floor": {"applicable": true, "reason": "Profiles are characterized bounded primitives linked to canonical Matter materials; T3 does not claim atom-level chemistry."},
		"active_cooling_system": {"applicable": false, "reason": "T3 includes passive case thermal conductance only. Pump/radiator cooling is T8."},
		"health_degradation": {"applicable": false, "reason": "Manufacturing quality is static in T3; dynamic SOH/wear is not claimed."},
	})
	check(measured.success, "measurement finalize", measured)
	if measured.success:
		print("FABRIC_R5_2_T3_DETERMINISTIC_HASH=" + String(measured.details.deterministic_hash))
		print("FABRIC_R5_2_T3_RESULT=" + JSON.stringify(measured.details))
	if not failed:
		print("FABRIC R5.2 T3 BATTERY CELLS MATERIALS: PASS (%d assertions)" % checks)
	quit(1 if failed else 0)

func _finish() -> void:
	print("FABRIC R5.2 T3 BATTERY CELLS MATERIALS: FAIL (%d assertions)" % checks)
	quit(1)

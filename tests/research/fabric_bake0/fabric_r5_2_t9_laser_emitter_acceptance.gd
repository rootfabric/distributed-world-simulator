extends SceneTree

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/laser_emitter_graph_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/laser_emitter_descriptor_v1.gd")
const Compiler = preload("res://scripts/research/fabric_bake0/r5_t9_laser_emitter_compiler_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/r5_t9_laser_emitter_runtime_v1.gd")
const FullReference = preload("res://scripts/research/fabric_bake0/r5_t9_laser_emitter_full_reference_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_r5_2_t9_laser_emitter_fixture.gd")

const PowerCompiler = preload("res://scripts/research/fabric_bake0/r5_t6_power_stage_compiler_v1.gd")
const PowerRuntime = preload("res://scripts/research/fabric_bake0/r5_t6_power_stage_runtime_v1.gd")
const PowerFixture = preload("res://tests/research/fabric_bake0/fabric_r5_2_t6_power_stage_fixture.gd")

const SEQUENCE_TICKS := 2048
const DT_S := 0.001

var checks := 0
var failed := false

func check(ok: bool, label: String, details = null) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("R5.2-T9: " + label + " " + JSON.stringify(details))

func compile_graph(graph: Dictionary, revision: int = 0) -> Dictionary:
	return Compiler.compile(graph, Fixture.build_request(graph, revision), "capsule/r5-t9-laser-emitter")

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--preflight":
			var g := Fixture.make_graph()
			var c := compile_graph(g)
			var r := FullReference.prepare(g)
			if not c.success or not r.success:
				print("FABRIC_R5_2_T9_PREFLIGHT=FAIL")
				quit(1)
				return
			print("FABRIC_R5_2_T9_PREFLIGHT=PASS")
			quit(0)
			return

	var graph := Fixture.make_graph()
	var reversed_graph := Fixture.make_graph("GAAS", false, false, false, true)
	check(Graph.validate(graph).success, "base graph valid")
	check(graph.gain_cells.size() == Fixture.CELLS, "128 source gain cells")
	check(String(graph.graph_hash) == String(reversed_graph.graph_hash), "raw ordering invariant")

	var compiled := compile_graph(graph)
	check(compiled.success, "base compile", compiled)
	if not compiled.success:
		_finish()
		return
	var descriptor: Dictionary = compiled.details.descriptor
	var artifact: Dictionary = compiled.details.artifact
	var capsule: Dictionary = compiled.details.capsule
	check(int(descriptor.source_cell_count) == Fixture.CELLS, "source-cell count")
	check(int(descriptor.active_cell_count) == Fixture.CELLS, "all base cells active")
	check(int(capsule.runtime_source_traversals_per_execute) == 0, "zero source traversal contract")
	check(float(capsule.operation_compression_ratio) > 30.0, "qualitative operation compression", {"ratio": capsule.operation_compression_ratio})
	check(float(descriptor.total_max_current_a) > float(descriptor.total_threshold_current_a), "nonempty current window")
	check(float(descriptor.wavelength_m) > 0.0 and float(descriptor.beam_divergence_half_angle_rad) > 0.0, "optical boundary derived")

	var inconsistent: Dictionary = descriptor.duplicate(true)
	inconsistent.beam_divergence_half_angle_rad = float(inconsistent.beam_divergence_half_angle_rad) * 1.01
	var payload: Dictionary = inconsistent.duplicate(true)
	payload.erase("descriptor_hash")
	payload.erase("checksum")
	inconsistent.descriptor_hash = U.canonical_hash(payload)
	inconsistent.checksum = U.compute_checksum(inconsistent)
	var inconsistent_check := Descriptor.validate(inconsistent)
	check(not inconsistent_check.success and String(inconsistent_check.error_code) == "LASER_EMITTER_DESCRIPTOR_RELATION_MISMATCH", "rehashed inconsistent optical descriptor rejected", inconsistent_check)

	var live := Fixture.live_from(artifact)
	var runtime = Runtime.new()
	var prepared := runtime.prepare(capsule, artifact, descriptor, live)
	check(prepared.success, "runtime prepare", prepared)
	var reference := FullReference.prepare(graph)
	check(reference.success, "detailed reference prepare", reference)
	if not prepared.success or not reference.success:
		_finish()
		return

	var max_voltage_error := 0.0
	var max_optical_error := 0.0
	var max_heat_error := 0.0
	var max_photon_error_relative := 0.0
	var max_divergence_error := 0.0
	var max_energy_residual := 0.0
	var full_traversals := 0
	var optical_seen := false
	var below_threshold_zero_seen := false
	for tick in range(SEQUENCE_TICKS):
		var phase := tick % 512
		var current := 200.0
		if phase >= 128 and phase < 384:
			current = 400.0
		elif phase >= 384:
			current = 500.0
		var temperature_k := 305.0 + 45.0 * (0.5 + 0.5 * sin(float(tick) * 0.009))
		var full := FullReference.execute(reference.details, current, temperature_k, DT_S)
		var fast := runtime.execute(live, current, temperature_k, DT_S)
		check(full.success and fast.success, "sequence execute", {"tick": tick, "full": full, "fast": fast})
		if not full.success or not fast.success:
			break
		max_voltage_error = maxf(max_voltage_error, absf(float(full.details.terminal_voltage_v) - float(fast.details.terminal_voltage_v)))
		max_optical_error = maxf(max_optical_error, absf(float(full.details.optical_energy_j) - float(fast.details.optical_energy_j)))
		max_heat_error = maxf(max_heat_error, absf(float(full.details.waste_heat_j) - float(fast.details.waste_heat_j)))
		var photon_scale := maxf(1.0, absf(float(full.details.photon_count)))
		max_photon_error_relative = maxf(max_photon_error_relative, absf(float(full.details.photon_count) - float(fast.details.photon_count)) / photon_scale)
		max_divergence_error = maxf(max_divergence_error, absf(float(full.details.beam_divergence_half_angle_rad) - float(fast.details.beam_divergence_half_angle_rad)))
		max_energy_residual = maxf(max_energy_residual, absf(float(full.details.energy_residual_j)))
		max_energy_residual = maxf(max_energy_residual, absf(float(fast.details.energy_residual_j)))
		full_traversals += int(full.details.source_cell_traversals)
		if float(fast.details.optical_energy_j) > 0.0:
			optical_seen = true
		if current < float(descriptor.total_threshold_current_a) and float(fast.details.optical_energy_j) == 0.0:
			below_threshold_zero_seen = true

	check(max_voltage_error <= 1.0e-12, "terminal voltage parity", {"error": max_voltage_error})
	check(max_optical_error <= 1.0e-12, "optical energy parity", {"error": max_optical_error})
	check(max_heat_error <= 1.0e-12, "waste heat parity", {"error": max_heat_error})
	check(max_photon_error_relative <= 1.0e-12, "photon-count parity", {"relative_error": max_photon_error_relative})
	check(max_divergence_error <= 1.0e-15, "beam divergence parity", {"error": max_divergence_error})
	check(max_energy_residual <= 1.0e-12, "energy audit", {"residual": max_energy_residual})
	check(full_traversals == Fixture.CELLS * SEQUENCE_TICKS, "detailed source traversal count", {"count": full_traversals})
	check(optical_seen, "optical emission observed above threshold")
	check(below_threshold_zero_seen, "below-threshold electrical drive emits zero optical energy")

	var cool_probe := runtime.execute(live, 400.0, 300.0, DT_S)
	var hot_probe := runtime.execute(live, 400.0, 380.0, DT_S)
	check(cool_probe.success and hot_probe.success, "thermal derating probes execute")
	var thermal_derating_ratio := -1.0
	if cool_probe.success and hot_probe.success:
		thermal_derating_ratio = float(hot_probe.details.optical_energy_j) / float(cool_probe.details.optical_energy_j)
		check(thermal_derating_ratio > 0.0 and thermal_derating_ratio < 1.0, "higher temperature derates optical output", {"ratio": thermal_derating_ratio})

	var gan := compile_graph(Fixture.make_graph("GAN"), 1)
	check(gan.success, "GaN-like material/profile variant compiles", gan)
	if gan.success:
		check(float(gan.details.descriptor.wavelength_m) < float(descriptor.wavelength_m), "GaN variant has shorter wavelength")
		check(float(gan.details.descriptor.forward_voltage_v) > float(descriptor.forward_voltage_v), "GaN variant has higher forward voltage")

	var damaged_graph := Fixture.make_graph("GAAS", true)
	var damaged := compile_graph(damaged_graph, 2)
	check(damaged.success, "one disabled gain cell recompiles", damaged)
	var damaged_divergence_ratio := -1.0
	var damage_mass_retained := false
	if damaged.success:
		check(int(damaged.details.descriptor.active_cell_count) == Fixture.CELLS - 1, "damage removes one active cell")
		damage_mass_retained = absf(float(damaged.details.descriptor.total_physical_mass_kg) - float(descriptor.total_physical_mass_kg)) <= 1.0e-15
		check(damage_mass_retained, "disabled cell retains physical mass")
		damaged_divergence_ratio = float(damaged.details.descriptor.beam_divergence_half_angle_rad) / float(descriptor.beam_divergence_half_angle_rad)
		check(damaged_divergence_ratio > 1.0, "smaller active aperture increases diffraction floor")
		var damaged_live := Fixture.live_from(damaged.details.artifact)
		var old_on_damaged := runtime.execute(damaged_live, 350.0, 320.0, DT_S)
		check(not old_on_damaged.success and String(old_on_damaged.error_code) == "LASER_EMITTER_RUNTIME_FRONTIER_MISMATCH", "old capsule rejects damaged source", old_on_damaged)

	var geometry_mismatch := compile_graph(Fixture.make_graph("GAAS", false, true), 3)
	check(not geometry_mismatch.success and String(geometry_mismatch.error_code) == "LASER_GAIN_CELL_SYNCHRONY_UNSAFE", "gain geometry mismatch is NO_SAFE_BAKE", geometry_mismatch)
	var mixed := compile_graph(Fixture.make_graph("GAAS", false, false, true), 4)
	check(not mixed.success and String(mixed.error_code) == "LASER_GAIN_PROFILE_MISMATCH", "mixed gain profile fails safe reduction", mixed)

	var frontier_mismatch := Compiler.compile(graph, Fixture.build_request(damaged_graph, 5), "capsule/r5-t9-laser-emitter")
	check(not frontier_mismatch.success and String(frontier_mismatch.error_code) == "LASER_EMITTER_CANONICAL_GRAPH_SOURCE_MISMATCH", "frontier mismatch rejected", frontier_mismatch)
	var overcurrent := runtime.execute(live, float(descriptor.total_max_current_a) * 1.01, 320.0, DT_S)
	check(not overcurrent.success and String(overcurrent.error_code) == "LASER_EMITTER_RUNTIME_CURRENT_LIMIT", "overcurrent rejected", overcurrent)
	var bad_temp := runtime.execute(live, 300.0, float(descriptor.max_temperature_k) + 1.0, DT_S)
	check(not bad_temp.success and String(bad_temp.error_code) == "LASER_GAIN_CELL_TEMPERATURE_OUT_OF_DOMAIN", "temperature-domain violation rejected", bad_temp)
	var stale_live: Dictionary = live.duplicate(true)
	stale_live.artifact_state = "STALE"
	check(not runtime.execute(stale_live, 300.0, 320.0, DT_S).success, "STALE rejected")
	var invalidated_live: Dictionary = live.duplicate(true)
	invalidated_live.invalidations = [{"synthetic": true}]
	check(not runtime.execute(invalidated_live, 300.0, 320.0, DT_S).success, "invalidation rejected")

	# T6 -> T9 electrical composition.
	var power_graph := PowerFixture.make_graph()
	var power_compiled := PowerCompiler.compile(power_graph, PowerFixture.build_request(power_graph), "capsule/r5-t9-composition-power-stage")
	check(power_compiled.success, "T6 power stage compiles for laser composition", power_compiled)
	var composition_max_voltage_error := 0.0
	var composition_max_energy_error := 0.0
	var composition_stage_loss_j := 0.0
	var composition_optical_j := 0.0
	var composition_laser_heat_j := 0.0
	if power_compiled.success:
		var power_live := PowerFixture.live_from(power_compiled.details.artifact)
		var power_runtime = PowerRuntime.new()
		var pp := power_runtime.prepare(power_compiled.details.capsule, power_compiled.details.artifact, power_compiled.details.descriptor, power_live)
		check(pp.success, "T6 runtime prepare for T9 composition", pp)
		if pp.success:
			var stage_temp := 320.0
			var path_factor := 1.0 + float(power_compiled.details.descriptor.resistance_temp_coefficient_per_k) * (stage_temp - float(power_compiled.details.descriptor.reference_temperature_k))
			var path_r := float(power_compiled.details.descriptor.positive_path_resistance_ref_ohm) * path_factor
			for tick in range(512):
				var current := 400.0
				var emitter := runtime.execute(live, current, 320.0, DT_S)
				check(emitter.success, "T9 composition emitter step", {"tick": tick, "result": emitter})
				if not emitter.success:
					break
				var required_v := float(emitter.details.terminal_voltage_v)
				var bus_v := 480.0
				var duty := (required_v + current * path_r) / bus_v
				var stage := power_runtime.execute(power_live, bus_v, duty, current, 20000.0, stage_temp, DT_S)
				check(stage.success, "T6 composition stage step", {"tick": tick, "result": stage, "duty": duty})
				if not stage.success:
					break
				composition_max_voltage_error = maxf(composition_max_voltage_error, absf(float(stage.details.load_voltage_v) - required_v))
				composition_max_energy_error = maxf(composition_max_energy_error, absf(float(stage.details.electrical_output_energy_j) - float(emitter.details.electrical_energy_j)))
				composition_stage_loss_j += float(stage.details.conduction_heat_j) + float(stage.details.switching_heat_j)
				composition_optical_j += float(emitter.details.optical_energy_j)
				composition_laser_heat_j += float(emitter.details.waste_heat_j)
	check(composition_max_voltage_error <= 1.0e-12, "T6->T9 terminal voltage parity", {"error": composition_max_voltage_error})
	check(composition_max_energy_error <= 1.0e-12, "T6->T9 electrical energy parity", {"error": composition_max_energy_error})
	check(composition_stage_loss_j > 0.0 and composition_optical_j > 0.0 and composition_laser_heat_j > 0.0, "composition separates stage loss, optical output and emitter heat")

	var deterministic := {
		"schema": "planet_simulator.fabric_r5_2_t9_laser_emitter_result.v1",
		"graph_hash": graph.graph_hash,
		"descriptor_hash": descriptor.descriptor_hash,
		"capsule_checksum": capsule.checksum,
		"source_cells": int(descriptor.source_cell_count),
		"active_cells": int(descriptor.active_cell_count),
		"source_operations": int(descriptor.source_operation_count),
		"compiled_operations": int(descriptor.compiled_operation_count),
		"operation_compression_ratio": float(capsule.operation_compression_ratio),
		"runtime_source_cell_traversals": 0,
		"total_threshold_current_a": float(descriptor.total_threshold_current_a),
		"total_max_current_a": float(descriptor.total_max_current_a),
		"wavelength_m": float(descriptor.wavelength_m),
		"beam_divergence_half_angle_rad": float(descriptor.beam_divergence_half_angle_rad),
		"sequence_ticks": SEQUENCE_TICKS,
		"full_reference_cell_traversals": full_traversals,
		"maximum_terminal_voltage_error_v": max_voltage_error,
		"maximum_optical_energy_error_j": max_optical_error,
		"maximum_waste_heat_error_j": max_heat_error,
		"maximum_photon_count_relative_error": max_photon_error_relative,
		"maximum_divergence_error_rad": max_divergence_error,
		"maximum_energy_residual_j": max_energy_residual,
		"optical_emission_seen_above_threshold": optical_seen,
		"below_threshold_zero_optical_seen": below_threshold_zero_seen,
		"thermal_derating_ratio_380k_to_300k": thermal_derating_ratio,
		"gan_wavelength_m": float(gan.details.descriptor.wavelength_m) if gan.success else -1.0,
		"gan_forward_voltage_v": float(gan.details.descriptor.forward_voltage_v) if gan.success else -1.0,
		"damage_active_cells": int(damaged.details.descriptor.active_cell_count) if damaged.success else -1,
		"damage_mass_retained": damage_mass_retained,
		"damage_divergence_ratio": damaged_divergence_ratio,
		"geometry_mismatch_error": String(geometry_mismatch.get("error_code", "")),
		"mixed_profile_error": String(mixed.get("error_code", "")),
		"descriptor_relation_error": String(inconsistent_check.get("error_code", "")),
		"composition_max_voltage_error_v": composition_max_voltage_error,
		"composition_max_energy_error_j": composition_max_energy_error,
		"composition_stage_loss_j": composition_stage_loss_j,
		"composition_optical_energy_j": composition_optical_j,
		"composition_laser_heat_j": composition_laser_heat_j,
	}
	print("FABRIC_R5_2_T9_RESULT=" + JSON.stringify(deterministic))
	if not failed:
		print("FABRIC R5.2 T9 LASER EMITTER: PASS (%d assertions)" % checks)
	quit(1 if failed else 0)

func _finish() -> void:
	print("FABRIC R5.2 T9 LASER EMITTER: FAIL (%d assertions)" % checks)
	quit(1)

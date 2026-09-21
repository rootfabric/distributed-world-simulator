extends SceneTree

const Graph = preload("res://scripts/research/fabric_bake0/motor_generator_graph_v1.gd")
const Compiler = preload("res://scripts/research/fabric_bake0/r5_t5_motor_generator_compiler_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/r5_t5_motor_generator_runtime_v1.gd")
const FullReference = preload("res://scripts/research/fabric_bake0/r5_t5_motor_generator_full_reference_v1.gd")
const StateProjector = preload("res://scripts/research/fabric_bake0/motor_generator_state_projector_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_r5_2_t5_motor_generator_fixture.gd")

const SEQUENCE_TICKS := 2048
const DT_S := 0.002

var checks := 0
var failed := false

func check(ok: bool, label: String, details = null) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("R5.2-T5: " + label + " " + JSON.stringify(details))

func compile_graph(graph: Dictionary, revision: int = 0) -> Dictionary:
	return Compiler.compile(graph, Fixture.build_request(graph, revision), "capsule/r5-t5-motor-generator")

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--preflight":
			var g := Fixture.make_graph()
			var c := compile_graph(g)
			var r := FullReference.prepare(g)
			if not c.success or not r.success:
				print("FABRIC_R5_2_T5_PREFLIGHT=FAIL")
				quit(1)
				return
			print("FABRIC_R5_2_T5_PREFLIGHT=PASS")
			quit(0)
			return

	var graph := Fixture.make_graph()
	var reversed_graph := Fixture.make_graph(1.0, "matter/motor-steel", false, false, true)
	check(Graph.validate(graph).success, "base graph valid")
	check(graph.winding_segments.size() == Fixture.WINDINGS, "192 winding segments")
	check(graph.rotor_sectors.size() == Fixture.ROTOR_SECTORS, "64 rotor sectors")
	check(String(graph.graph_hash) == String(reversed_graph.graph_hash), "raw ordering invariant")

	var compiled := compile_graph(graph)
	check(compiled.success, "base compile", compiled)
	if not compiled.success:
		_finish()
		return
	var descriptor: Dictionary = compiled.details.descriptor
	var artifact: Dictionary = compiled.details.artifact
	var capsule: Dictionary = compiled.details.capsule
	check(int(capsule.source_component_count) == Fixture.COMPONENT_COUNT, "256 source components")
	check(int(capsule.runtime_source_traversals_per_execute) == 0, "zero source traversal contract")
	check(int(capsule.full_operation_count) > int(capsule.executable_operation_count), "operation compression")
	check(float(capsule.operation_compression_ratio) > 50.0, "meaningful operation compression", {"ratio": capsule.operation_compression_ratio})
	check(absf(float(descriptor.torque_constant_nm_a) - float(descriptor.back_emf_constant_v_s_rad)) <= 1.0e-12, "SI reciprocity kT == kE")

	var live := Fixture.live_from(artifact)
	var runtime = Runtime.new()
	var prepared := runtime.prepare(capsule, artifact, descriptor, live)
	check(prepared.success, "runtime prepare", prepared)
	var reference := FullReference.prepare(graph)
	check(reference.success, "detailed reference prepare", reference)
	if not prepared.success or not reference.success:
		_finish()
		return

	# One-step motor mode.
	var zero_state := runtime.initial_state(0.0)
	var motor_step := runtime.execute(live, zero_state, 6.0, -1.5, DT_S)
	check(motor_step.success, "motor mode executes", motor_step)
	if motor_step.success:
		check(float(motor_step.details.electromagnetic_torque_nm) > 0.0, "motor torque positive")
		check(float(motor_step.details.electrical_energy_j) > 0.0, "motor consumes electrical energy")
		check(float(motor_step.details.next_state.angular_velocity_rad_s) > 0.0, "motor accelerates rotor")

	var fast_state := runtime.initial_state(0.0)
	var full_state := FullReference.initial_state(reference.details, 0.0)
	var max_voltage_error := 0.0
	var max_torque_error := 0.0
	var max_omega_error := 0.0
	var max_electrical_residual := 0.0
	var max_total_residual := 0.0
	var full_traversals := 0
	var generator_observed := false
	var generator_voltage_v := 0.0
	var generator_electrical_energy_j := 0.0
	var generator_torque_nm := 0.0

	for tick in range(SEQUENCE_TICKS):
		var current_a := 0.0
		var external_torque_nm := 0.0
		if tick < 800:
			current_a = 6.0
			external_torque_nm = -1.5
		elif tick < 1200:
			current_a = 0.0
			external_torque_nm = -0.15
		else:
			current_a = -4.0
			external_torque_nm = 3.0

		var full := FullReference.execute(reference.details, full_state, current_a, external_torque_nm, DT_S)
		var fast := runtime.execute(live, fast_state, current_a, external_torque_nm, DT_S)
		check(full.success and fast.success, "sequence execute", {"tick": tick, "full": full, "fast": fast})
		if not full.success or not fast.success:
			break
		max_voltage_error = maxf(max_voltage_error, absf(float(full.details.terminal_voltage_v) - float(fast.details.terminal_voltage_v)))
		max_torque_error = maxf(max_torque_error, absf(float(full.details.electromagnetic_torque_nm) - float(fast.details.electromagnetic_torque_nm)))
		max_omega_error = maxf(max_omega_error, absf(float(full.details.next_state.angular_velocity_rad_s) - float(fast.details.next_state.angular_velocity_rad_s)))
		max_electrical_residual = maxf(max_electrical_residual, absf(float(fast.details.electrical_energy_residual_j)))
		max_total_residual = maxf(max_total_residual, absf(float(fast.details.total_energy_residual_j)))
		max_electrical_residual = maxf(max_electrical_residual, absf(float(full.details.electrical_energy_residual_j)))
		max_total_residual = maxf(max_total_residual, absf(float(full.details.total_energy_residual_j)))
		full_traversals += int(full.details.source_component_traversals)
		if tick >= 1200 and not generator_observed and float(fast.details.terminal_voltage_v) > 0.0 and float(fast.details.electrical_energy_j) < 0.0:
			generator_observed = true
			generator_voltage_v = float(fast.details.terminal_voltage_v)
			generator_electrical_energy_j = float(fast.details.electrical_energy_j)
			generator_torque_nm = float(fast.details.electromagnetic_torque_nm)
		full_state = full.details.next_state
		fast_state = fast.details.next_state

	check(max_voltage_error <= 1.0e-9, "terminal voltage parity", {"max_error": max_voltage_error})
	check(max_torque_error <= 1.0e-12, "torque parity", {"max_error": max_torque_error})
	check(max_omega_error <= 1.0e-9, "omega state parity", {"max_error": max_omega_error})
	check(max_electrical_residual <= 1.0e-9, "electrical energy audit", {"max_residual_j": max_electrical_residual})
	check(max_total_residual <= 1.0e-9, "total energy audit", {"max_residual_j": max_total_residual})
	check(full_traversals == Fixture.COMPONENT_COUNT * SEQUENCE_TICKS, "detailed traversal count", {"count": full_traversals})
	check(generator_observed, "generator mode observed")
	if generator_observed:
		check(generator_electrical_energy_j < 0.0, "generator exports electrical energy")
		check(generator_torque_nm < 0.0, "generator electromagnetic torque opposes rotation")

	# Statefulness: identical instantaneous command at different omega gives different back-EMF.
	var stationary_state := runtime.initial_state(0.0)
	var spinning_state := runtime.initial_state(120.0)
	var stationary_response := runtime.execute(live, stationary_state, 0.0, 0.0, DT_S)
	var spinning_response := runtime.execute(live, spinning_state, 0.0, 0.0, DT_S)
	check(stationary_response.success and spinning_response.success, "history/state comparison executes")
	var history_voltage_delta_v := 0.0
	if stationary_response.success and spinning_response.success:
		history_voltage_delta_v = absf(float(spinning_response.details.terminal_voltage_v) - float(stationary_response.details.terminal_voltage_v))
	check(history_voltage_delta_v > 1.0, "same command differs by stored angular state", {"delta_v": history_voltage_delta_v})

	# Caller-owned snapshot replay must be exact.
	var replay_a: Dictionary = fast_state.duplicate(true)
	var replay_b: Dictionary = fast_state.duplicate(true)
	var replay_max_voltage_error := 0.0
	var replay_max_state_error := 0.0
	for replay_tick in range(128):
		var replay_current := 2.0 if replay_tick < 64 else -1.0
		var replay_external := -0.4 if replay_tick < 64 else 0.8
		var a := runtime.execute(live, replay_a, replay_current, replay_external, DT_S)
		var b := runtime.execute(live, replay_b, replay_current, replay_external, DT_S)
		check(a.success and b.success, "snapshot replay execute", {"tick": replay_tick})
		if not a.success or not b.success:
			break
		replay_max_voltage_error = maxf(replay_max_voltage_error, absf(float(a.details.terminal_voltage_v) - float(b.details.terminal_voltage_v)))
		replay_max_state_error = maxf(replay_max_state_error, absf(float(a.details.next_state.angular_velocity_rad_s) - float(b.details.next_state.angular_velocity_rad_s)))
		replay_a = a.details.next_state
		replay_b = b.details.next_state
	check(replay_max_voltage_error == 0.0 and replay_max_state_error == 0.0, "snapshot replay exact", {"voltage_error": replay_max_voltage_error, "state_error": replay_max_state_error})

	# Manufacturing quality changes electrical behavior but not conductor mass.
	var lower_quality_graph := Fixture.make_graph(0.85)
	var lower_quality := compile_graph(lower_quality_graph, 1)
	check(lower_quality.success, "lower winding quality compiles", lower_quality)
	var quality_projection: Dictionary = {"success": false, "error_code": "NOT_RUN", "details": {}}
	var quality_rebuilt_parity_error := INF
	if lower_quality.success:
		check(float(lower_quality.details.descriptor.total_resistance_ohm) > float(descriptor.total_resistance_ohm), "lower quality raises resistance")
		check(float(lower_quality.details.descriptor.torque_constant_nm_a) < float(descriptor.torque_constant_nm_a), "lower quality lowers coupling")
		check(float(lower_quality.details.descriptor.max_abs_current_a) < float(descriptor.max_abs_current_a), "lower quality lowers current limit")
		check(absf(float(lower_quality.details.descriptor.winding_mass_kg) - float(descriptor.winding_mass_kg)) <= 1.0e-12, "quality does not alter conductor mass")

		# Coefficient-only mutation: old capsule must reject the new canonical graph,
		# while state reconstruction may preserve omega because rotor inertia is unchanged.
		var lower_live := Fixture.live_from(lower_quality.details.artifact)
		var old_on_new_live := runtime.execute(lower_live, fast_state, 0.0, 0.0, DT_S)
		check(not old_on_new_live.success and String(old_on_new_live.error_code) == "MOTOR_GENERATOR_RUNTIME_FRONTIER_MISMATCH", "old capsule rejects winding mutation", old_on_new_live)
		quality_projection = StateProjector.project(descriptor, lower_quality.details.descriptor, fast_state)
		check(quality_projection.success, "winding mutation state projection", quality_projection)
		if quality_projection.success:
			check(String(quality_projection.details.projection_kind) == "COEFFICIENT_CHANGE_SAME_ROTOR_INERTIA", "quality projection kind")
			check(absf(float(quality_projection.details.angular_momentum_before_kg_m2_rad_s) - float(quality_projection.details.angular_momentum_after_kg_m2_rad_s)) <= 1.0e-12, "quality projection preserves angular momentum")
			check(absf(float(quality_projection.details.kinetic_energy_before_j) - float(quality_projection.details.kinetic_energy_after_j)) <= 1.0e-12, "quality projection preserves kinetic energy")
			var rebuilt_runtime = Runtime.new()
			check(rebuilt_runtime.prepare(lower_quality.details.capsule, lower_quality.details.artifact, lower_quality.details.descriptor, lower_live).success, "rebuilt lower-quality runtime prepare")
			var rebuilt_reference := FullReference.prepare(lower_quality_graph)
			check(rebuilt_reference.success, "rebuilt lower-quality reference prepare")
			if rebuilt_reference.success:
				var rebuilt_fast := rebuilt_runtime.execute(lower_live, quality_projection.details.next_state, 2.0, -0.3, DT_S)
				var rebuilt_full := FullReference.execute(rebuilt_reference.details, quality_projection.details.next_state, 2.0, -0.3, DT_S)
				check(rebuilt_fast.success and rebuilt_full.success, "projected rebuilt state executes")
				if rebuilt_fast.success and rebuilt_full.success:
					quality_rebuilt_parity_error = absf(float(rebuilt_fast.details.terminal_voltage_v) - float(rebuilt_full.details.terminal_voltage_v))
					check(quality_rebuilt_parity_error <= 1.0e-9, "projected rebuilt voltage parity", {"error": quality_rebuilt_parity_error})
					check(absf(float(rebuilt_fast.details.next_state.angular_velocity_rad_s) - float(rebuilt_full.details.next_state.angular_velocity_rad_s)) <= 1.0e-9, "projected rebuilt state parity")

	# Rotor Matter changes mass/inertia/speed envelope.
	var aluminum_graph := Fixture.make_graph(1.0, "matter/motor-aluminum")
	var aluminum := compile_graph(aluminum_graph, 2)
	check(aluminum.success, "aluminum rotor compiles", aluminum)
	var inertia_change_projection: Dictionary = {"success": false, "error_code": "NOT_RUN", "details": {}}
	if aluminum.success:
		check(float(aluminum.details.descriptor.rotor_mass_kg) < float(descriptor.rotor_mass_kg), "aluminum rotor mass lower")
		check(float(aluminum.details.descriptor.rotor_inertia_kg_m2) < float(descriptor.rotor_inertia_kg_m2), "aluminum rotor inertia lower")
		check(absf(float(aluminum.details.descriptor.max_abs_angular_velocity_rad_s) - float(descriptor.max_abs_angular_velocity_rad_s)) > 1.0e-6, "rotor material changes speed envelope")
		inertia_change_projection = StateProjector.project(descriptor, aluminum.details.descriptor, fast_state)
		check(not inertia_change_projection.success and String(inertia_change_projection.error_code) == "MOTOR_STATE_RECONSTRUCTION_INERTIA_CHANGE_UNSUPPORTED", "rotor inertia mutation requires richer reconstruction", inertia_change_projection)

	var open_graph := Fixture.make_graph(1.0, "matter/motor-steel", true)
	var open_result := compile_graph(open_graph, 3)
	check(not open_result.success and String(open_result.error_code) == "MOTOR_WINDING_OPEN", "open winding fails closed", open_result)
	var incomplete_graph := Fixture.make_graph(1.0, "matter/motor-steel", false, true)
	var incomplete_result := compile_graph(incomplete_graph, 4)
	check(not incomplete_result.success and String(incomplete_result.error_code) == "MOTOR_ROTOR_INCOMPLETE", "incomplete rotor fails closed", incomplete_result)

	var mismatch := Compiler.compile(graph, Fixture.build_request(lower_quality_graph, 5), "capsule/r5-t5-motor-generator")
	check(not mismatch.success and String(mismatch.error_code) == "MOTOR_GENERATOR_CANONICAL_GRAPH_SOURCE_MISMATCH", "frontier/graph mismatch rejected", mismatch)

	var over_current := runtime.execute(live, fast_state, float(descriptor.max_abs_current_a) * 1.01, 0.0, DT_S)
	check(not over_current.success and String(over_current.error_code) == "MOTOR_GENERATOR_RUNTIME_CURRENT_LIMIT", "over-current rejected", over_current)
	var nonfinite_state := {"angular_velocity_rad_s": NAN}
	var nonfinite_result := runtime.execute(live, nonfinite_state, 0.0, 0.0, DT_S)
	check(not nonfinite_result.success and String(nonfinite_result.error_code) == "MOTOR_GENERATOR_RUNTIME_STATE_INVALID", "non-finite state rejected", nonfinite_result)
	var overspeed_state := {"angular_velocity_rad_s": float(descriptor.max_abs_angular_velocity_rad_s) * 1.001}
	var overspeed_result := runtime.execute(live, overspeed_state, 0.0, 0.0, DT_S)
	check(not overspeed_result.success and String(overspeed_result.error_code) == "MOTOR_GENERATOR_RUNTIME_SPEED_OUT_OF_DOMAIN", "overspeed state rejected", overspeed_result)

	var stale_live: Dictionary = live.duplicate(true)
	stale_live.artifact_state = "STALE"
	check(not runtime.execute(stale_live, fast_state, 0.0, 0.0, DT_S).success, "STALE rejected")
	var invalidated_live: Dictionary = live.duplicate(true)
	invalidated_live.invalidations = [{"synthetic": true}]
	check(not runtime.execute(invalidated_live, fast_state, 0.0, 0.0, DT_S).success, "invalidation rejected")
	var authority_drift: Dictionary = live.duplicate(true)
	authority_drift.authority_envelope = live.authority_envelope.duplicate(true)
	authority_drift.authority_envelope.checksum = "0".repeat(64)
	check(not runtime.execute(authority_drift, fast_state, 0.0, 0.0, DT_S).success, "authority drift rejected")
	var graph_drift: Dictionary = live.duplicate(true)
	graph_drift.graph_hash = String(lower_quality_graph.graph_hash)
	var graph_drift_result := runtime.execute(graph_drift, fast_state, 0.0, 0.0, DT_S)
	check(not graph_drift_result.success and String(graph_drift_result.error_code) == "MOTOR_GENERATOR_RUNTIME_GRAPH_MISMATCH", "graph drift rejected", graph_drift_result)

	var deterministic := {
		"schema": "planet_simulator.fabric_r5_2_t5_motor_generator_result.v1",
		"graph_hash": graph.graph_hash,
		"descriptor_hash": descriptor.descriptor_hash,
		"capsule_checksum": capsule.checksum,
		"source_components": Fixture.COMPONENT_COUNT,
		"winding_segments": Fixture.WINDINGS,
		"rotor_sectors": Fixture.ROTOR_SECTORS,
		"state_scalars": 1,
		"source_operations": int(descriptor.source_operation_count),
		"compiled_operations": int(descriptor.compiled_operation_count),
		"operation_compression_ratio": float(capsule.operation_compression_ratio),
		"runtime_source_component_traversals": 0,
		"total_resistance_ohm": float(descriptor.total_resistance_ohm),
		"torque_constant_nm_a": float(descriptor.torque_constant_nm_a),
		"max_abs_current_a": float(descriptor.max_abs_current_a),
		"winding_mass_kg": float(descriptor.winding_mass_kg),
		"rotor_mass_kg": float(descriptor.rotor_mass_kg),
		"rotor_inertia_kg_m2": float(descriptor.rotor_inertia_kg_m2),
		"max_abs_angular_velocity_rad_s": float(descriptor.max_abs_angular_velocity_rad_s),
		"sequence_ticks": SEQUENCE_TICKS,
		"full_reference_component_traversals": full_traversals,
		"maximum_voltage_error": max_voltage_error,
		"maximum_torque_error": max_torque_error,
		"maximum_omega_error": max_omega_error,
		"maximum_electrical_energy_residual_j": max_electrical_residual,
		"maximum_total_energy_residual_j": max_total_residual,
		"generator_observed": generator_observed,
		"generator_voltage_v": generator_voltage_v,
		"generator_electrical_energy_j": generator_electrical_energy_j,
		"generator_torque_nm": generator_torque_nm,
		"history_voltage_delta_v": history_voltage_delta_v,
		"replay_max_voltage_error": replay_max_voltage_error,
		"replay_max_state_error": replay_max_state_error,
		"lower_quality_resistance_ohm": float(lower_quality.details.descriptor.total_resistance_ohm) if lower_quality.success else -1.0,
		"lower_quality_torque_constant_nm_a": float(lower_quality.details.descriptor.torque_constant_nm_a) if lower_quality.success else -1.0,
		"aluminum_rotor_mass_kg": float(aluminum.details.descriptor.rotor_mass_kg) if aluminum.success else -1.0,
		"aluminum_rotor_inertia_kg_m2": float(aluminum.details.descriptor.rotor_inertia_kg_m2) if aluminum.success else -1.0,
		"quality_projection_kind": String(quality_projection.details.get("projection_kind", "")) if quality_projection.success else "",
		"quality_rebuilt_parity_error": quality_rebuilt_parity_error,
		"inertia_change_projection_error": String(inertia_change_projection.get("error_code", "")),
		"overspeed_error": String(overspeed_result.get("error_code", "")),
		"open_winding_error": String(open_result.get("error_code", "")),
		"incomplete_rotor_error": String(incomplete_result.get("error_code", "")),
	}
	print("FABRIC_R5_2_T5_RESULT=" + JSON.stringify(deterministic))
	if not failed:
		print("FABRIC R5.2 T5 MOTOR GENERATOR: PASS (%d assertions)" % checks)
	quit(1 if failed else 0)

func _finish() -> void:
	print("FABRIC R5.2 T5 MOTOR GENERATOR: FAIL (%d assertions)" % checks)
	quit(1)

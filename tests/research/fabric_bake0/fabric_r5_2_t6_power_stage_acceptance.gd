extends SceneTree

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/power_stage_graph_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/power_stage_descriptor_v1.gd")
const Compiler = preload("res://scripts/research/fabric_bake0/r5_t6_power_stage_compiler_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/r5_t6_power_stage_runtime_v1.gd")
const FullReference = preload("res://scripts/research/fabric_bake0/r5_t6_power_stage_full_reference_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_r5_2_t6_power_stage_fixture.gd")

const MotorCompiler = preload("res://scripts/research/fabric_bake0/r5_t5_motor_generator_compiler_v1.gd")
const MotorRuntime = preload("res://scripts/research/fabric_bake0/r5_t5_motor_generator_runtime_v1.gd")
const MotorFixture = preload("res://tests/research/fabric_bake0/fabric_r5_2_t5_motor_generator_fixture.gd")

const SEQUENCE_TICKS := 2048
const DT_S := 0.001

var checks := 0
var failed := false

func check(ok: bool, label: String, details = null) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("R5.2-T6: " + label + " " + JSON.stringify(details))

func compile_graph(graph: Dictionary, revision: int = 0) -> Dictionary:
	return Compiler.compile(graph, Fixture.build_request(graph, revision), "capsule/r5-t6-power-stage")

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--preflight":
			var g := Fixture.make_graph()
			var c := compile_graph(g)
			var r := FullReference.prepare(g)
			if not c.success or not r.success:
				print("FABRIC_R5_2_T6_PREFLIGHT=FAIL")
				quit(1)
				return
			print("FABRIC_R5_2_T6_PREFLIGHT=PASS")
			quit(0)
			return

	var graph := Fixture.make_graph()
	var reversed_graph := Fixture.make_graph("SIC", false, false, false, false, true)
	check(Graph.validate(graph).success, "base graph valid")
	check(graph.switch_dies.size() == Fixture.DIE_COUNT, "256 source dies", {"count": graph.switch_dies.size()})
	check(String(graph.graph_hash) == String(reversed_graph.graph_hash), "raw ordering invariant")

	var compiled := compile_graph(graph)
	check(compiled.success, "base compile", compiled)
	if not compiled.success:
		_finish()
		return
	var descriptor: Dictionary = compiled.details.descriptor
	var artifact: Dictionary = compiled.details.artifact
	var capsule: Dictionary = compiled.details.capsule
	check(int(descriptor.switch_die_count) == Fixture.DIE_COUNT, "descriptor die count")
	check(int(descriptor.active_die_count) == Fixture.DIE_COUNT, "all dies active")
	check(int(capsule.runtime_source_traversals_per_execute) == 0, "zero source traversal contract")
	check(float(capsule.operation_compression_ratio) > 50.0, "qualitative operation compression", {"ratio": capsule.operation_compression_ratio})

	# Rehashing an internally inconsistent descriptor must not bypass structural relations.
	var inconsistent_descriptor: Dictionary = descriptor.duplicate(true)
	inconsistent_descriptor.positive_path_resistance_ref_ohm = float(inconsistent_descriptor.positive_path_resistance_ref_ohm) * 1.01
	var inconsistent_payload: Dictionary = inconsistent_descriptor.duplicate(true)
	inconsistent_payload.erase("descriptor_hash")
	inconsistent_payload.erase("checksum")
	inconsistent_descriptor.descriptor_hash = U.canonical_hash(inconsistent_payload)
	inconsistent_descriptor.checksum = U.compute_checksum(inconsistent_descriptor)
	var inconsistent_check := Descriptor.validate(inconsistent_descriptor)
	check(not inconsistent_check.success and String(inconsistent_check.error_code) == "POWER_STAGE_DESCRIPTOR_PATH_RELATION_MISMATCH", "rehashed inconsistent descriptor rejected", inconsistent_check)

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
	var max_bus_current_error := 0.0
	var max_conduction_error := 0.0
	var max_switching_error := 0.0
	var max_energy_residual := 0.0
	var full_traversals := 0
	var regeneration_seen := false
	for tick in range(SEQUENCE_TICKS):
		var quarter := tick / 512
		var duty := 0.68
		var current := 180.0
		if quarter == 1:
			duty = 0.30
			current = 110.0
		elif quarter == 2:
			duty = 0.58
			current = -140.0
		elif quarter >= 3:
			duty = -0.42
			current = 95.0
		var bus_v := 480.0 + 20.0 * sin(float(tick) * 0.009)
		var temperature_k := 315.0 + 15.0 * sin(float(tick) * 0.005)
		var pwm_hz := 20000.0 + 1500.0 * sin(float(tick) * 0.003)
		var full := FullReference.execute(reference.details, bus_v, duty, current, pwm_hz, temperature_k, DT_S)
		var fast := runtime.execute(live, bus_v, duty, current, pwm_hz, temperature_k, DT_S)
		check(full.success and fast.success, "sequence execute", {"tick": tick, "full": full, "fast": fast})
		if not full.success or not fast.success:
			break
		max_voltage_error = maxf(max_voltage_error, absf(float(full.details.load_voltage_v) - float(fast.details.load_voltage_v)))
		max_bus_current_error = maxf(max_bus_current_error, absf(float(full.details.bus_current_a) - float(fast.details.bus_current_a)))
		max_conduction_error = maxf(max_conduction_error, absf(float(full.details.conduction_heat_j) - float(fast.details.conduction_heat_j)))
		max_switching_error = maxf(max_switching_error, absf(float(full.details.switching_heat_j) - float(fast.details.switching_heat_j)))
		max_energy_residual = maxf(max_energy_residual, absf(float(fast.details.energy_residual_j)))
		full_traversals += int(full.details.source_die_traversals)
		if current < 0.0 and float(fast.details.bus_current_a) < 0.0:
			regeneration_seen = true

	check(max_voltage_error <= 1.0e-9, "load voltage parity", {"error": max_voltage_error})
	check(max_bus_current_error <= 1.0e-9, "bus current parity", {"error": max_bus_current_error})
	check(max_conduction_error <= 1.0e-9, "conduction heat parity", {"error": max_conduction_error})
	check(max_switching_error <= 1.0e-9, "switching heat parity", {"error": max_switching_error})
	check(max_energy_residual <= 1.0e-9, "energy audit", {"residual": max_energy_residual})
	check(full_traversals == Fixture.DIE_COUNT * SEQUENCE_TICKS, "detailed traversal count", {"count": full_traversals})
	check(regeneration_seen, "negative bus current observed in regeneration")

	var silicon := compile_graph(Fixture.make_graph("SI"), 1)
	check(silicon.success, "silicon material variant compiles", silicon)
	if silicon.success:
		check(float(silicon.details.descriptor.positive_path_resistance_ref_ohm) > float(descriptor.positive_path_resistance_ref_ohm), "material changes conduction resistance")
		check(float(silicon.details.descriptor.positive_path_transition_time_s) > float(descriptor.positive_path_transition_time_s), "material changes switching transition")

	var damaged_graph := Fixture.make_graph("SIC", true)
	var damaged := compile_graph(damaged_graph, 2)
	check(damaged.success, "one disabled die recompiles", damaged)
	if damaged.success:
		check(int(damaged.details.descriptor.active_die_count) == Fixture.DIE_COUNT - 1, "disabled die removes electrical contribution")
		check(absf(float(damaged.details.descriptor.total_semiconductor_mass_kg) - float(descriptor.total_semiconductor_mass_kg)) <= 1.0e-15, "disabled die retains physical mass")
		check(float(damaged.details.descriptor.positive_path_resistance_ref_ohm) > float(descriptor.positive_path_resistance_ref_ohm), "damaged positive path resistance increases")
		var damaged_live := Fixture.live_from(damaged.details.artifact)
		var old_on_damaged := runtime.execute(damaged_live, 480.0, 0.5, 50.0, 20000.0, 320.0, DT_S)
		check(not old_on_damaged.success and String(old_on_damaged.error_code) == "POWER_STAGE_RUNTIME_FRONTIER_MISMATCH", "old capsule rejects damaged source", old_on_damaged)

	var unsafe_graph := Fixture.make_graph("SIC", false, true)
	var unsafe := compile_graph(unsafe_graph, 3)
	check(not unsafe.success and String(unsafe.error_code) == "POWER_STAGE_PARALLEL_CURRENT_SYNCHRONY_UNSAFE", "unsafe parallel geometry fails closed", unsafe)
	var unsafe_reference := FullReference.prepare(unsafe_graph)
	check(unsafe_reference.success, "unsafe geometry remains physically executable in detailed reference", unsafe_reference)
	var unsafe_reference_executes := false
	if unsafe_reference.success:
		var unsafe_reference_step := FullReference.execute(unsafe_reference.details, 480.0, 0.5, 50.0, 20000.0, 320.0, DT_S)
		unsafe_reference_executes = bool(unsafe_reference_step.success)
		check(unsafe_reference_executes, "unsafe geometry is NO_SAFE_BAKE rather than invalid physics", unsafe_reference_step)
	var mixed := compile_graph(Fixture.make_graph("SIC", false, false, true), 4)
	check(not mixed.success and String(mixed.error_code) == "POWER_STAGE_PROFILE_MISMATCH", "mixed semiconductor profile fails closed", mixed)
	var open_bank := compile_graph(Fixture.make_graph("SIC", false, false, false, true), 5)
	check(not open_bank.success and String(open_bank.error_code) == "POWER_STAGE_BANK_OPEN", "open switch bank fails closed", open_bank)

	var mismatch := Compiler.compile(graph, Fixture.build_request(damaged_graph, 6), "capsule/r5-t6-power-stage")
	check(not mismatch.success and String(mismatch.error_code) == "POWER_STAGE_CANONICAL_GRAPH_SOURCE_MISMATCH", "frontier graph mismatch rejected", mismatch)
	var over_voltage := runtime.execute(live, float(descriptor.max_bus_voltage_v) * 1.01, 0.5, 50.0, 20000.0, 320.0, DT_S)
	check(not over_voltage.success and String(over_voltage.error_code) == "POWER_STAGE_RUNTIME_BUS_VOLTAGE_LIMIT", "over-voltage fail closed")
	var over_current := runtime.execute(live, 480.0, 0.5, float(descriptor.positive_path_max_abs_current_a) * 1.01, 20000.0, 320.0, DT_S)
	check(not over_current.success and String(over_current.error_code) == "POWER_STAGE_RUNTIME_CURRENT_LIMIT", "over-current fail closed")
	check(not runtime.execute(live, 480.0, 1.01, 50.0, 20000.0, 320.0, DT_S).success, "invalid duty rejected")
	check(not runtime.execute(live, 480.0, 0.5, 50.0, 20000.0, float(descriptor.max_temperature_k) + 1.0, DT_S).success, "temperature domain rejected")
	var stale_live: Dictionary = live.duplicate(true)
	stale_live.artifact_state = "STALE"
	check(not runtime.execute(stale_live, 480.0, 0.5, 50.0, 20000.0, 320.0, DT_S).success, "STALE rejected")
	var invalidated_live: Dictionary = live.duplicate(true)
	invalidated_live.invalidations = [{"synthetic": true}]
	check(not runtime.execute(invalidated_live, 480.0, 0.5, 50.0, 20000.0, 320.0, DT_S).success, "invalidation rejected")

	# Direct T5 composition: choose duty so T6 reproduces the motor terminal voltage.
	var motor_graph := MotorFixture.make_graph()
	var motor_compiled := MotorCompiler.compile(motor_graph, MotorFixture.build_request(motor_graph), "capsule/r5-t6-composition-motor")
	check(motor_compiled.success, "T5 motor compiles for T6 composition", motor_compiled)
	var composition_max_voltage_error := 0.0
	var composition_max_energy_error := 0.0
	var composition_regeneration_seen := false
	if motor_compiled.success:
		var motor_live := MotorFixture.live_from(motor_compiled.details.artifact)
		var motor_runtime = MotorRuntime.new()
		var motor_prepared := motor_runtime.prepare(motor_compiled.details.capsule, motor_compiled.details.artifact, motor_compiled.details.descriptor, motor_live)
		check(motor_prepared.success, "T5 motor runtime prepare for composition", motor_prepared)
		if motor_prepared.success:
			var motor_state := motor_runtime.initial_state(120.0)
			var stage_temp := 325.0
			var factor := 1.0 + float(descriptor.resistance_temp_coefficient_per_k) * (stage_temp - float(descriptor.reference_temperature_k))
			var path_r := float(descriptor.positive_path_resistance_ref_ohm) * factor
			for tick in range(512):
				var current := 10.0 if tick < 256 else -8.0
				var external_torque := -2.0 if tick < 256 else 4.0
				var motor_step := motor_runtime.execute(motor_live, motor_state, current, external_torque, 0.002)
				check(motor_step.success, "T5 composition motor step", {"tick": tick, "result": motor_step})
				if not motor_step.success:
					break
				var required_v := float(motor_step.details.terminal_voltage_v)
				check(required_v > 0.0, "composition target voltage stays positive", {"tick": tick, "voltage": required_v})
				var bus_v := 600.0
				var duty := (required_v + current * path_r) / bus_v
				var stage_step := runtime.execute(live, bus_v, duty, current, 20000.0, stage_temp, 0.002)
				check(stage_step.success, "T6 composition power-stage step", {"tick": tick, "result": stage_step, "duty": duty})
				if not stage_step.success:
					break
				composition_max_voltage_error = maxf(composition_max_voltage_error, absf(float(stage_step.details.load_voltage_v) - required_v))
				composition_max_energy_error = maxf(composition_max_energy_error, absf(float(stage_step.details.electrical_output_energy_j) - float(motor_step.details.electrical_energy_j)))
				if current < 0.0 and float(stage_step.details.bus_current_a) < 0.0:
					composition_regeneration_seen = true
				motor_state = motor_step.details.next_state
	check(composition_max_voltage_error <= 1.0e-9, "T6->T5 terminal voltage composition parity", {"error": composition_max_voltage_error})
	check(composition_max_energy_error <= 1.0e-9, "T6->T5 electrical energy composition parity", {"error": composition_max_energy_error})
	check(composition_regeneration_seen, "T6->T5 composition preserves regeneration")

	var deterministic := {
		"schema": "planet_simulator.fabric_r5_2_t6_power_stage_result.v1",
		"graph_hash": graph.graph_hash,
		"descriptor_hash": descriptor.descriptor_hash,
		"capsule_checksum": capsule.checksum,
		"source_dies": int(descriptor.switch_die_count),
		"active_dies": int(descriptor.active_die_count),
		"banks": int(descriptor.bank_count),
		"source_operations": int(descriptor.source_operation_count),
		"compiled_operations": int(descriptor.compiled_operation_count),
		"operation_compression_ratio": float(capsule.operation_compression_ratio),
		"runtime_source_die_traversals": 0,
		"sequence_ticks": SEQUENCE_TICKS,
		"full_reference_die_traversals": full_traversals,
		"maximum_load_voltage_error": max_voltage_error,
		"maximum_bus_current_error": max_bus_current_error,
		"maximum_conduction_heat_error": max_conduction_error,
		"maximum_switching_heat_error": max_switching_error,
		"maximum_energy_residual_j": max_energy_residual,
		"positive_path_resistance_ref_ohm": float(descriptor.positive_path_resistance_ref_ohm),
		"positive_path_max_abs_current_a": float(descriptor.positive_path_max_abs_current_a),
		"positive_path_transition_time_s": float(descriptor.positive_path_transition_time_s),
		"regeneration_seen": regeneration_seen,
		"silicon_positive_path_resistance_ref_ohm": float(silicon.details.descriptor.positive_path_resistance_ref_ohm) if silicon.success else -1.0,
		"silicon_positive_path_transition_time_s": float(silicon.details.descriptor.positive_path_transition_time_s) if silicon.success else -1.0,
		"damage_active_dies": int(damaged.details.descriptor.active_die_count) if damaged.success else -1,
		"unsafe_geometry_error": String(unsafe.get("error_code", "")),
		"unsafe_geometry_detailed_reference_executes": unsafe_reference_executes,
		"descriptor_relation_error": String(inconsistent_check.get("error_code", "")),
		"mixed_profile_error": String(mixed.get("error_code", "")),
		"open_bank_error": String(open_bank.get("error_code", "")),
		"composition_max_voltage_error": composition_max_voltage_error,
		"composition_max_energy_error": composition_max_energy_error,
		"composition_regeneration_seen": composition_regeneration_seen,
	}
	print("FABRIC_R5_2_T6_RESULT=" + JSON.stringify(deterministic))
	if not failed:
		print("FABRIC R5.2 T6 POWER STAGE: PASS (%d assertions)" % checks)
	quit(1 if failed else 0)

func _finish() -> void:
	print("FABRIC R5.2 T6 POWER STAGE: FAIL (%d assertions)" % checks)
	quit(1)

extends SceneTree

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/gearbox_graph_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/gearbox_descriptor_v1.gd")
const Compiler = preload("res://scripts/research/fabric_bake0/r5_t7_gearbox_compiler_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/r5_t7_gearbox_runtime_v1.gd")
const FullReference = preload("res://scripts/research/fabric_bake0/r5_t7_gearbox_full_reference_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_r5_2_t7_gearbox_fixture.gd")

const MotorCompiler = preload("res://scripts/research/fabric_bake0/r5_t5_motor_generator_compiler_v1.gd")
const MotorRuntime = preload("res://scripts/research/fabric_bake0/r5_t5_motor_generator_runtime_v1.gd")
const MotorFixture = preload("res://tests/research/fabric_bake0/fabric_r5_2_t5_motor_generator_fixture.gd")

const SEQUENCE_TICKS := 2048
const DT_S := 0.002

var checks := 0
var failed := false

func check(ok: bool, label: String, details = null) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("R5.2-T7: " + label + " " + JSON.stringify(details))

func compile_graph(graph: Dictionary, revision: int = 0) -> Dictionary:
	return Compiler.compile(graph, Fixture.build_request(graph, revision), "capsule/r5-t7-gearbox")

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--preflight":
			var g := Fixture.make_graph()
			var c := compile_graph(g)
			var r := FullReference.prepare(g)
			if not c.success or not r.success:
				print("FABRIC_R5_2_T7_PREFLIGHT=FAIL")
				quit(1)
				return
			print("FABRIC_R5_2_T7_PREFLIGHT=PASS")
			quit(0)
			return

	var graph := Fixture.make_graph()
	var reversed_graph := Fixture.make_graph("STEEL", false, false, false, true)
	check(Graph.validate(graph).success, "base graph valid")
	check(graph.gears.size() == Fixture.GEAR_COUNT, "six gear bodies")
	check(graph.teeth.size() == Fixture.TOOTH_COUNT, "232 explicit teeth")
	check(String(graph.graph_hash) == String(reversed_graph.graph_hash), "raw ordering invariant")

	var compiled := compile_graph(graph)
	check(compiled.success, "base compile", compiled)
	if not compiled.success:
		_finish()
		return
	var descriptor: Dictionary = compiled.details.descriptor
	var artifact: Dictionary = compiled.details.artifact
	var capsule: Dictionary = compiled.details.capsule
	check(int(descriptor.stage_count) == Fixture.STAGES, "three stages")
	check(int(capsule.source_component_count) == Fixture.SOURCE_COMPONENT_COUNT, "238 source components")
	check(int(capsule.runtime_source_traversals_per_execute) == 0, "zero source traversal contract")
	check(float(capsule.operation_compression_ratio) > 80.0, "qualitative operation compression", {"ratio": capsule.operation_compression_ratio})
	check(absf(float(descriptor.total_speed_ratio) + 1.0 / 36.0) <= 1.0e-15, "3-stage ratio derives to -1/36", {"ratio": descriptor.total_speed_ratio})

	var inconsistent: Dictionary = descriptor.duplicate(true)
	inconsistent.max_abs_output_torque_nm = float(inconsistent.max_abs_output_torque_nm) * 1.01
	var payload: Dictionary = inconsistent.duplicate(true)
	payload.erase("descriptor_hash")
	payload.erase("checksum")
	inconsistent.descriptor_hash = U.canonical_hash(payload)
	inconsistent.checksum = U.compute_checksum(inconsistent)
	var inconsistent_check := Descriptor.validate(inconsistent)
	check(not inconsistent_check.success and String(inconsistent_check.error_code) == "GEARBOX_DESCRIPTOR_OUTPUT_TORQUE_MISMATCH", "rehashed inconsistent descriptor rejected", inconsistent_check)

	var live := Fixture.live_from(artifact)
	var runtime = Runtime.new()
	var prepared := runtime.prepare(capsule, artifact, descriptor, live)
	check(prepared.success, "runtime prepare", prepared)
	var reference := FullReference.prepare(graph)
	check(reference.success, "detailed reference prepare", reference)
	if not prepared.success or not reference.success:
		_finish()
		return

	var max_omega_error := 0.0
	var max_torque_error := 0.0
	var max_inertia_error := 0.0
	var max_energy_residual := 0.0
	var full_traversals := 0
	var reverse_power_seen := false
	for tick in range(SEQUENCE_TICKS):
		var omega := 120.0 + 25.0 * sin(float(tick) * 0.009)
		var torque := 5.0 + 1.5 * sin(float(tick) * 0.017)
		if tick >= 1024:
			omega = -omega
		if tick >= 1536:
			torque = -torque
		var full := FullReference.execute(reference.details, omega, torque, DT_S)
		var fast := runtime.execute(live, omega, torque, DT_S)
		check(full.success and fast.success, "sequence execute", {"tick": tick, "full": full, "fast": fast})
		if not full.success or not fast.success:
			break
		max_omega_error = maxf(max_omega_error, absf(float(full.details.output_angular_velocity_rad_s) - float(fast.details.output_angular_velocity_rad_s)))
		max_torque_error = maxf(max_torque_error, absf(float(full.details.output_torque_nm) - float(fast.details.output_torque_nm)))
		max_inertia_error = maxf(max_inertia_error, absf(float(full.details.equivalent_input_inertia_kg_m2) - float(fast.details.equivalent_input_inertia_kg_m2)))
		max_energy_residual = maxf(max_energy_residual, absf(float(fast.details.energy_residual_j)))
		full_traversals += int(full.details.source_component_traversals)
		if float(fast.details.input_mechanical_energy_j) < 0.0:
			reverse_power_seen = true

	check(max_omega_error <= 1.0e-12, "output omega parity", {"error": max_omega_error})
	check(max_torque_error <= 1.0e-9, "output torque parity", {"error": max_torque_error})
	check(max_inertia_error <= 1.0e-12, "reflected inertia parity", {"error": max_inertia_error})
	check(max_energy_residual <= 1.0e-12, "lossless energy audit", {"residual": max_energy_residual})
	check(full_traversals == Fixture.SOURCE_COMPONENT_COUNT * SEQUENCE_TICKS, "detailed traversal count", {"count": full_traversals})
	check(reverse_power_seen, "reverse mechanical power observed")

	var aluminum := compile_graph(Fixture.make_graph("ALUMINUM"), 1)
	check(aluminum.success, "aluminum material variant compiles", aluminum)
	if aluminum.success:
		check(float(aluminum.details.descriptor.total_mass_kg) < float(descriptor.total_mass_kg), "aluminum reduces mass")
		check(float(aluminum.details.descriptor.equivalent_input_inertia_kg_m2) < float(descriptor.equivalent_input_inertia_kg_m2), "aluminum reduces reflected inertia")
		check(float(aluminum.details.descriptor.max_abs_input_torque_nm) < float(descriptor.max_abs_input_torque_nm), "aluminum lowers torque envelope")

	var weak_graph := Fixture.make_graph("STEEL", true)
	var weak := compile_graph(weak_graph, 2)
	check(weak.success, "weak-tooth variant recompiles", weak)
	if weak.success:
		check(float(weak.details.descriptor.max_abs_input_torque_nm) < float(descriptor.max_abs_input_torque_nm), "weak tooth lowers torque envelope")
		var weak_live := Fixture.live_from(weak.details.artifact)
		var old_on_weak := runtime.execute(weak_live, 100.0, 2.0, DT_S)
		check(not old_on_weak.success and String(old_on_weak.error_code) == "GEARBOX_RUNTIME_FRONTIER_MISMATCH", "old capsule rejects tooth mutation", old_on_weak)

	var disabled := compile_graph(Fixture.make_graph("STEEL", false, true), 3)
	check(not disabled.success and String(disabled.error_code) == "GEARBOX_TOOTH_DISABLED", "disabled tooth fails closed", disabled)
	var mismatch_module_graph := Fixture.make_graph("STEEL", false, false, true)
	var mismatch_module := compile_graph(mismatch_module_graph, 4)
	check(not mismatch_module.success and String(mismatch_module.error_code) == "GEARBOX_MESH_MODULE_MISMATCH", "mesh module mismatch fails closed", mismatch_module)
	var mismatch_reference := FullReference.prepare(mismatch_module_graph)
	check(mismatch_reference.success, "module-mismatch detailed graph can be prepared")
	if mismatch_reference.success:
		var mismatch_step := FullReference.execute(mismatch_reference.details, 100.0, 2.0, DT_S)
		check(not mismatch_step.success and String(mismatch_step.error_code) == "GEARBOX_REFERENCE_MESH_MODULE_MISMATCH", "detailed reference independently catches incompatible mesh", mismatch_step)

	var frontier_mismatch := Compiler.compile(graph, Fixture.build_request(weak_graph, 5), "capsule/r5-t7-gearbox")
	check(not frontier_mismatch.success and String(frontier_mismatch.error_code) == "GEARBOX_CANONICAL_GRAPH_SOURCE_MISMATCH", "frontier mismatch rejected", frontier_mismatch)
	check(not runtime.execute(live, float(descriptor.max_abs_input_omega_rad_s) * 1.01, 1.0, DT_S).success, "overspeed rejected")
	check(not runtime.execute(live, 10.0, float(descriptor.max_abs_input_torque_nm) * 1.01, DT_S).success, "over-torque rejected")
	var stale_live: Dictionary = live.duplicate(true)
	stale_live.artifact_state = "STALE"
	check(not runtime.execute(stale_live, 10.0, 1.0, DT_S).success, "STALE rejected")
	var invalidated_live: Dictionary = live.duplicate(true)
	invalidated_live.invalidations = [{"synthetic": true}]
	check(not runtime.execute(invalidated_live, 10.0, 1.0, DT_S).success, "invalidation rejected")

	# T5 -> T7 mechanical composition.
	var motor_graph := MotorFixture.make_graph()
	var motor_compiled := MotorCompiler.compile(motor_graph, MotorFixture.build_request(motor_graph), "capsule/r5-t7-composition-motor")
	check(motor_compiled.success, "T5 motor compiles for gearbox composition", motor_compiled)
	var composition_max_ratio_error := 0.0
	var composition_max_power_error := 0.0
	var composition_torque_gain_seen := false
	if motor_compiled.success:
		var motor_live := MotorFixture.live_from(motor_compiled.details.artifact)
		var motor_runtime = MotorRuntime.new()
		var mp := motor_runtime.prepare(motor_compiled.details.capsule, motor_compiled.details.artifact, motor_compiled.details.descriptor, motor_live)
		check(mp.success, "T5 motor runtime prepare", mp)
		if mp.success:
			var motor_state := motor_runtime.initial_state(80.0)
			for tick in range(512):
				var current := 4.0 if tick < 256 else -3.0
				var external_torque := -1.0 if tick < 256 else 1.5
				var motor_step := motor_runtime.execute(motor_live, motor_state, current, external_torque, 0.002)
				check(motor_step.success, "T5 composition step", {"tick": tick, "result": motor_step})
				if not motor_step.success:
					break
				var motor_omega := float(motor_step.details.next_state.angular_velocity_rad_s)
				var motor_torque := float(motor_step.details.electromagnetic_torque_nm)
				var gear_step := runtime.execute(live, motor_omega, motor_torque, 0.002)
				check(gear_step.success, "T7 gearbox composition step", {"tick": tick, "result": gear_step})
				if not gear_step.success:
					break
				composition_max_ratio_error = maxf(composition_max_ratio_error, absf(float(gear_step.details.output_angular_velocity_rad_s) - motor_omega * float(descriptor.total_speed_ratio)))
				composition_max_power_error = maxf(composition_max_power_error, absf(float(gear_step.details.input_mechanical_energy_j) - float(gear_step.details.output_mechanical_energy_j)))
				if absf(float(gear_step.details.output_torque_nm)) > absf(motor_torque) * 30.0:
					composition_torque_gain_seen = true
				motor_state = motor_step.details.next_state
	check(composition_max_ratio_error <= 1.0e-12, "T5->T7 speed ratio composition parity", {"error": composition_max_ratio_error})
	check(composition_max_power_error <= 1.0e-12, "T5->T7 mechanical power conservation", {"error": composition_max_power_error})
	check(composition_torque_gain_seen, "T5->T7 torque multiplication observed")

	var deterministic := {
		"schema": "planet_simulator.fabric_r5_2_t7_gearbox_result.v1",
		"graph_hash": graph.graph_hash,
		"descriptor_hash": descriptor.descriptor_hash,
		"capsule_checksum": capsule.checksum,
		"source_gears": int(descriptor.source_gear_count),
		"source_teeth": int(descriptor.source_tooth_count),
		"source_components": int(capsule.source_component_count),
		"stages": int(descriptor.stage_count),
		"source_operations": int(descriptor.source_operation_count),
		"compiled_operations": int(descriptor.compiled_operation_count),
		"operation_compression_ratio": float(capsule.operation_compression_ratio),
		"runtime_source_component_traversals": 0,
		"total_speed_ratio": float(descriptor.total_speed_ratio),
		"equivalent_input_inertia_kg_m2": float(descriptor.equivalent_input_inertia_kg_m2),
		"total_mass_kg": float(descriptor.total_mass_kg),
		"max_abs_input_torque_nm": float(descriptor.max_abs_input_torque_nm),
		"max_abs_input_omega_rad_s": float(descriptor.max_abs_input_omega_rad_s),
		"sequence_ticks": SEQUENCE_TICKS,
		"full_reference_component_traversals": full_traversals,
		"maximum_output_omega_error": max_omega_error,
		"maximum_output_torque_error": max_torque_error,
		"maximum_reflected_inertia_error": max_inertia_error,
		"maximum_energy_residual_j": max_energy_residual,
		"reverse_power_seen": reverse_power_seen,
		"aluminum_mass_kg": float(aluminum.details.descriptor.total_mass_kg) if aluminum.success else -1.0,
		"aluminum_inertia_kg_m2": float(aluminum.details.descriptor.equivalent_input_inertia_kg_m2) if aluminum.success else -1.0,
		"aluminum_max_input_torque_nm": float(aluminum.details.descriptor.max_abs_input_torque_nm) if aluminum.success else -1.0,
		"weak_tooth_max_input_torque_nm": float(weak.details.descriptor.max_abs_input_torque_nm) if weak.success else -1.0,
		"disabled_tooth_error": String(disabled.get("error_code", "")),
		"module_mismatch_error": String(mismatch_module.get("error_code", "")),
		"descriptor_relation_error": String(inconsistent_check.get("error_code", "")),
		"composition_max_ratio_error": composition_max_ratio_error,
		"composition_max_power_error": composition_max_power_error,
		"composition_torque_gain_seen": composition_torque_gain_seen,
	}
	print("FABRIC_R5_2_T7_RESULT=" + JSON.stringify(deterministic))
	if not failed:
		print("FABRIC R5.2 T7 GEARBOX: PASS (%d assertions)" % checks)
	quit(1 if failed else 0)

func _finish() -> void:
	print("FABRIC R5.2 T7 GEARBOX: FAIL (%d assertions)" % checks)
	quit(1)

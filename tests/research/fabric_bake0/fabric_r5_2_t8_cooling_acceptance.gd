extends SceneTree

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/cooling_loop_graph_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/cooling_loop_descriptor_v1.gd")
const Compiler = preload("res://scripts/research/fabric_bake0/r5_t8_cooling_loop_compiler_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/r5_t8_cooling_loop_runtime_v1.gd")
const FullReference = preload("res://scripts/research/fabric_bake0/r5_t8_cooling_loop_full_reference_v1.gd")
const Projector = preload("res://scripts/research/fabric_bake0/cooling_loop_state_projector_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_r5_2_t8_cooling_fixture.gd")

const PowerCompiler = preload("res://scripts/research/fabric_bake0/r5_t6_power_stage_compiler_v1.gd")
const PowerRuntime = preload("res://scripts/research/fabric_bake0/r5_t6_power_stage_runtime_v1.gd")
const PowerFixture = preload("res://tests/research/fabric_bake0/fabric_r5_2_t6_power_stage_fixture.gd")

const SEQUENCE_TICKS := 2048
const DT_S := 0.01

var checks := 0
var failed := false

func check(ok: bool, label: String, details = null) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("R5.2-T8: " + label + " " + JSON.stringify(details))

func compile_graph(graph: Dictionary, revision: int = 0) -> Dictionary:
	return Compiler.compile(graph, Fixture.build_request(graph, revision), "capsule/r5-t8-cooling-loop")

func max_state_error(detailed: Dictionary, compact: Dictionary) -> float:
	var out := 0.0
	for field in ["plate_temperature_k", "hot_coolant_temperature_k", "radiator_temperature_k", "cold_coolant_temperature_k"]:
		for raw in detailed[field]:
			out = maxf(out, absf(float(raw) - float(compact[field])))
	return out

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--preflight":
			var g := Fixture.make_graph()
			var c := compile_graph(g)
			var r := FullReference.prepare(g)
			if not c.success or not r.success:
				print("FABRIC_R5_2_T8_PREFLIGHT=FAIL")
				quit(1)
				return
			print("FABRIC_R5_2_T8_PREFLIGHT=PASS")
			quit(0)
			return

	var graph := Fixture.make_graph()
	var reversed_graph := Fixture.make_graph("WATER", false, false, true)
	check(Graph.validate(graph).success, "base graph valid")
	check(graph.lanes.size() == Fixture.LANES, "64 cooling lanes")
	check(String(graph.graph_hash) == String(reversed_graph.graph_hash), "raw ordering invariant")

	var compiled := compile_graph(graph)
	check(compiled.success, "base compile", compiled)
	if not compiled.success:
		_finish()
		return
	var descriptor: Dictionary = compiled.details.descriptor
	var artifact: Dictionary = compiled.details.artifact
	var capsule: Dictionary = compiled.details.capsule
	check(int(descriptor.source_thermal_node_count) == Fixture.SOURCE_THERMAL_NODES, "256 detailed thermal nodes")
	check(int(capsule.source_component_count) == Fixture.SOURCE_THERMAL_NODES, "capsule source thermal-node count")
	check(int(capsule.runtime_source_traversals_per_execute) == 0, "zero source traversal contract")
	check(float(capsule.operation_compression_ratio) > 40.0, "qualitative operation compression", {"ratio": capsule.operation_compression_ratio})
	check(descriptor.interface_contract.output_quantities.has("PUMP_HYDRAULIC_ENERGY_J"), "pump hydraulic cost is explicit boundary output")

	var inconsistent: Dictionary = descriptor.duplicate(true)
	inconsistent.max_total_mass_flow_kg_s = float(inconsistent.max_total_mass_flow_kg_s) * 1.01
	var payload: Dictionary = inconsistent.duplicate(true)
	payload.erase("descriptor_hash")
	payload.erase("checksum")
	inconsistent.descriptor_hash = U.canonical_hash(payload)
	inconsistent.checksum = U.compute_checksum(inconsistent)
	var inconsistent_check := Descriptor.validate(inconsistent)
	check(not inconsistent_check.success and String(inconsistent_check.error_code) == "COOLING_LOOP_DESCRIPTOR_MAX_FLOW_RELATION_MISMATCH", "rehashed inconsistent max-flow descriptor rejected", inconsistent_check)

	var live := Fixture.live_from(artifact)
	var runtime = Runtime.new()
	var prepared := runtime.prepare(capsule, artifact, descriptor, live)
	check(prepared.success, "runtime prepare", prepared)
	var reference := FullReference.prepare(graph)
	check(reference.success, "detailed reference prepare", reference)
	if not prepared.success or not reference.success:
		_finish()
		return

	var compact_state := runtime.initial_state(300.0)
	var detailed_state := FullReference.initial_state(reference.details, 300.0)
	var initial_projection := Projector.project(graph, descriptor, detailed_state)
	check(initial_projection.success, "initial detailed state projects", initial_projection)
	if initial_projection.success:
		check(JSON.stringify(initial_projection.details.next_state) == JSON.stringify(compact_state), "initial projected state equals compact state")

	var max_plate_error := 0.0
	var max_hot_error := 0.0
	var max_cold_error := 0.0
	var max_radiator_error := 0.0
	var max_state_parity_error := 0.0
	var max_ambient_error := 0.0
	var max_pump_error := 0.0
	var max_energy_residual := 0.0
	var full_traversals := 0
	var pump_energy_observed := false
	for tick in range(SEQUENCE_TICKS):
		var phase := tick % 512
		var heat_w := 2200.0 if phase < 320 else 450.0
		var flow := 0.25 if tick < 1536 else 0.12
		var ambient_k := 294.0 + 2.0 * sin(float(tick) * 0.007)
		var full := FullReference.execute(reference.details, detailed_state, heat_w, flow, ambient_k, DT_S)
		var fast := runtime.execute(live, compact_state, heat_w, flow, ambient_k, DT_S)
		check(full.success and fast.success, "sequence execute", {"tick": tick, "full": full, "fast": fast})
		if not full.success or not fast.success:
			break
		max_plate_error = maxf(max_plate_error, absf(float(full.details.plate_temperature_k) - float(fast.details.plate_temperature_k)))
		max_hot_error = maxf(max_hot_error, absf(float(full.details.hot_coolant_temperature_k) - float(fast.details.hot_coolant_temperature_k)))
		max_cold_error = maxf(max_cold_error, absf(float(full.details.cold_coolant_temperature_k) - float(fast.details.cold_coolant_temperature_k)))
		max_radiator_error = maxf(max_radiator_error, absf(float(full.details.radiator_temperature_k) - float(fast.details.radiator_temperature_k)))
		max_state_parity_error = maxf(max_state_parity_error, max_state_error(full.details.next_state, fast.details.next_state))
		max_ambient_error = maxf(max_ambient_error, absf(float(full.details.ambient_exchange_j) - float(fast.details.ambient_exchange_j)))
		max_pump_error = maxf(max_pump_error, absf(float(full.details.pump_hydraulic_energy_j) - float(fast.details.pump_hydraulic_energy_j)))
		max_energy_residual = maxf(max_energy_residual, absf(float(full.details.energy_residual_j)))
		max_energy_residual = maxf(max_energy_residual, absf(float(fast.details.energy_residual_j)))
		full_traversals += int(full.details.source_thermal_node_traversals)
		if float(fast.details.pump_hydraulic_energy_j) > 0.0:
			pump_energy_observed = true
		detailed_state = full.details.next_state
		compact_state = fast.details.next_state

	check(max_plate_error <= 1.0e-9, "plate temperature parity", {"error": max_plate_error})
	check(max_hot_error <= 1.0e-9, "hot coolant parity", {"error": max_hot_error})
	check(max_cold_error <= 1.0e-9, "cold coolant parity", {"error": max_cold_error})
	check(max_radiator_error <= 1.0e-9, "radiator parity", {"error": max_radiator_error})
	check(max_state_parity_error <= 1.0e-9, "state parity", {"error": max_state_parity_error})
	check(max_ambient_error <= 1.0e-9, "ambient exchange parity", {"error": max_ambient_error})
	check(max_pump_error <= 1.0e-9, "pump energy parity", {"error": max_pump_error})
	check(max_energy_residual <= 1.0e-8, "energy audit", {"residual": max_energy_residual})
	check(full_traversals == Fixture.SOURCE_THERMAL_NODES * SEQUENCE_TICKS, "detailed thermal-node traversal count", {"count": full_traversals})
	check(pump_energy_observed, "nonzero hydraulic pump cost observed")

	var final_projection := Projector.project(graph, descriptor, detailed_state)
	check(final_projection.success, "final detailed state remains on reduction manifold", final_projection)
	if final_projection.success:
		check(maxf(
			absf(float(final_projection.details.next_state.plate_temperature_k) - float(compact_state.plate_temperature_k)),
			absf(float(final_projection.details.next_state.hot_coolant_temperature_k) - float(compact_state.hot_coolant_temperature_k))
		) <= 1.0e-9, "final projected compact state matches")

	var glycol := compile_graph(Fixture.make_graph("GLYCOL"), 1)
	check(glycol.success, "glycol coolant variant compiles", glycol)
	var glycol_pump_ratio := -1.0
	if glycol.success:
		check(float(glycol.details.descriptor.hot_coolant_capacity_j_k) < float(descriptor.hot_coolant_capacity_j_k), "glycol variant lowers hot-side thermal capacity")
		var glycol_live := Fixture.live_from(glycol.details.artifact)
		var glycol_runtime = Runtime.new()
		var gp := glycol_runtime.prepare(glycol.details.capsule, glycol.details.artifact, glycol.details.descriptor, glycol_live)
		check(gp.success, "glycol runtime prepare")
		if gp.success:
			var water_probe := runtime.execute(live, runtime.initial_state(300.0), 0.0, 0.20, 294.0, DT_S)
			var glycol_probe := glycol_runtime.execute(glycol_live, glycol_runtime.initial_state(300.0), 0.0, 0.20, 294.0, DT_S)
			check(water_probe.success and glycol_probe.success, "coolant pump probes execute")
			if water_probe.success and glycol_probe.success:
				glycol_pump_ratio = float(glycol_probe.details.pump_hydraulic_energy_j) / float(water_probe.details.pump_hydraulic_energy_j)
				check(glycol_pump_ratio > 3.0, "higher viscosity materially raises hydraulic cost", {"ratio": glycol_pump_ratio})

	var asymmetric_graph := Fixture.make_graph("WATER", true)
	var asymmetric := compile_graph(asymmetric_graph, 2)
	check(not asymmetric.success and String(asymmetric.error_code) == "COOLING_LANE_SYMMETRY_BROKEN", "asymmetric lane fails safe reduction", asymmetric)
	var asymmetric_reference := FullReference.prepare(asymmetric_graph)
	check(asymmetric_reference.success, "asymmetric detailed loop remains executable", asymmetric_reference)
	var asymmetric_reference_executes := false
	if asymmetric_reference.success:
		var asym_state := FullReference.initial_state(asymmetric_reference.details, 300.0)
		var asym_step := FullReference.execute(asymmetric_reference.details, asym_state, 1000.0, 0.15, 294.0, DT_S)
		asymmetric_reference_executes = bool(asym_step.success)
		check(asymmetric_reference_executes, "asymmetric loop is NO_SAFE_BAKE rather than invalid physics", asym_step)

	var disabled := compile_graph(Fixture.make_graph("WATER", false, true), 3)
	check(not disabled.success and String(disabled.error_code) == "COOLING_LANE_DISABLED", "disabled lane fails closed", disabled)

	var off_manifold: Dictionary = detailed_state.duplicate(true)
	off_manifold.plate_temperature_k = detailed_state.plate_temperature_k.duplicate()
	off_manifold.plate_temperature_k[4] = float(off_manifold.plate_temperature_k[4]) + 0.05
	var projection_fail := Projector.project(graph, descriptor, off_manifold)
	check(not projection_fail.success and String(projection_fail.error_code) == "COOLING_STATE_NOT_IN_REDUCTION_MANIFOLD", "off-manifold detailed state rejected", projection_fail)

	var nonfinite_state: Dictionary = detailed_state.duplicate(true)
	nonfinite_state.hot_coolant_temperature_k = detailed_state.hot_coolant_temperature_k.duplicate()
	nonfinite_state.hot_coolant_temperature_k[7] = NAN
	var nonfinite_projection := Projector.project(graph, descriptor, nonfinite_state)
	check(not nonfinite_projection.success and String(nonfinite_projection.error_code) == "COOLING_STATE_PROJECTOR_STATE_INVALID", "non-finite projector state rejected", nonfinite_projection)
	var nonfinite_reference := FullReference.execute(reference.details, nonfinite_state, 100.0, 0.10, 294.0, DT_S)
	check(not nonfinite_reference.success and String(nonfinite_reference.error_code) == "COOLING_REFERENCE_STATE_INVALID", "non-finite detailed reference state rejected", nonfinite_reference)

	var out_of_domain_state: Dictionary = detailed_state.duplicate(true)
	out_of_domain_state.plate_temperature_k = detailed_state.plate_temperature_k.duplicate()
	out_of_domain_state.plate_temperature_k[0] = float(descriptor.max_temperature_k) + 1.0
	var out_of_domain_projection := Projector.project(graph, descriptor, out_of_domain_state)
	check(not out_of_domain_projection.success and String(out_of_domain_projection.error_code) == "COOLING_STATE_PROJECTOR_TEMPERATURE_OUT_OF_DOMAIN", "projector domain violation rejected", out_of_domain_projection)
	var out_of_domain_reference := FullReference.execute(reference.details, out_of_domain_state, 100.0, 0.10, 294.0, DT_S)
	check(not out_of_domain_reference.success and String(out_of_domain_reference.error_code) == "COOLING_REFERENCE_TEMPERATURE_OUT_OF_DOMAIN", "detailed reference domain violation rejected", out_of_domain_reference)

	var regime_descriptor: Dictionary = descriptor.duplicate(true)
	regime_descriptor.laminar_reynolds_limit = 2400.0
	regime_descriptor.max_total_mass_flow_kg_s = float(regime_descriptor.laminar_reynolds_limit) * float(regime_descriptor.dynamic_viscosity_pa_s) * float(regime_descriptor.channel_flow_area_m2) / float(regime_descriptor.channel_hydraulic_diameter_m) * float(regime_descriptor.lane_count)
	var regime_payload: Dictionary = regime_descriptor.duplicate(true)
	regime_payload.erase("descriptor_hash")
	regime_payload.erase("checksum")
	regime_descriptor.descriptor_hash = U.canonical_hash(regime_payload)
	regime_descriptor.checksum = U.compute_checksum(regime_descriptor)
	var regime_check := Descriptor.validate(regime_descriptor)
	check(not regime_check.success and String(regime_check.error_code) == "COOLING_LOOP_DESCRIPTOR_FLOW_REGIME_UNSUPPORTED", "rehashed turbulent descriptor rejected", regime_check)

	var frontier_mismatch := Compiler.compile(graph, Fixture.build_request(asymmetric_graph, 4), "capsule/r5-t8-cooling-loop")
	check(not frontier_mismatch.success and String(frontier_mismatch.error_code) == "COOLING_LOOP_CANONICAL_GRAPH_SOURCE_MISMATCH", "frontier mismatch rejected", frontier_mismatch)
	var flow_limit := runtime.execute(live, runtime.initial_state(300.0), 1000.0, float(descriptor.max_total_mass_flow_kg_s) * 1.01, 294.0, DT_S)
	check(not flow_limit.success and String(flow_limit.error_code) == "COOLING_LOOP_RUNTIME_FLOW_LIMIT", "over-flow rejected", flow_limit)
	var stale_live: Dictionary = live.duplicate(true)
	stale_live.artifact_state = "STALE"
	check(not runtime.execute(stale_live, runtime.initial_state(300.0), 1000.0, 0.10, 294.0, DT_S).success, "STALE rejected")
	var invalidated_live: Dictionary = live.duplicate(true)
	invalidated_live.invalidations = [{"synthetic": true}]
	check(not runtime.execute(invalidated_live, runtime.initial_state(300.0), 1000.0, 0.10, 294.0, DT_S).success, "invalidation rejected")

	# T6 -> T8 composition: feed real semiconductor heat into identical active/passive cooling loops.
	var power_graph := PowerFixture.make_graph()
	var power_compiled := PowerCompiler.compile(power_graph, PowerFixture.build_request(power_graph), "capsule/r5-t8-composition-power-stage")
	check(power_compiled.success, "T6 power stage compiles for cooling composition", power_compiled)
	var cooling_temperature_advantage_k := -1.0
	var composition_heat_j := 0.0
	var composition_pump_j := 0.0
	if power_compiled.success:
		var power_live := PowerFixture.live_from(power_compiled.details.artifact)
		var power_runtime = PowerRuntime.new()
		var pp := power_runtime.prepare(power_compiled.details.capsule, power_compiled.details.artifact, power_compiled.details.descriptor, power_live)
		check(pp.success, "T6 runtime prepare for cooling composition", pp)
		if pp.success:
			var active_state := runtime.initial_state(300.0)
			var passive_state := runtime.initial_state(300.0)
			for tick in range(1024):
				var pstep := power_runtime.execute(power_live, 480.0, 0.55, 450.0, 20000.0, 320.0, DT_S)
				check(pstep.success, "T6 heat-source step", {"tick": tick, "result": pstep})
				if not pstep.success:
					break
				var heat_j := float(pstep.details.conduction_heat_j) + float(pstep.details.switching_heat_j)
				var heat_w := heat_j / DT_S
				var active := runtime.execute(live, active_state, heat_w, 0.25, 294.0, DT_S)
				var passive := runtime.execute(live, passive_state, heat_w, 0.0, 294.0, DT_S)
				check(active.success and passive.success, "T6->T8 cooling steps", {"tick": tick, "active": active, "passive": passive})
				if not active.success or not passive.success:
					break
				composition_heat_j += heat_j
				composition_pump_j += float(active.details.pump_hydraulic_energy_j)
				active_state = active.details.next_state
				passive_state = passive.details.next_state
			cooling_temperature_advantage_k = float(passive_state.plate_temperature_k) - float(active_state.plate_temperature_k)
			check(cooling_temperature_advantage_k > 0.10, "active flow cools T6 heat source versus zero-flow loop", {"advantage_k": cooling_temperature_advantage_k})
			check(composition_heat_j > 0.0 and composition_pump_j > 0.0, "T6 heat and pump cost both accounted")

	var deterministic := {
		"schema": "planet_simulator.fabric_r5_2_t8_cooling_result.v1",
		"graph_hash": graph.graph_hash,
		"descriptor_hash": descriptor.descriptor_hash,
		"capsule_checksum": capsule.checksum,
		"lanes": int(descriptor.lane_count),
		"source_thermal_nodes": int(descriptor.source_thermal_node_count),
		"state_scalars": 4,
		"source_operations": int(descriptor.source_operation_count),
		"compiled_operations": int(descriptor.compiled_operation_count),
		"operation_compression_ratio": float(capsule.operation_compression_ratio),
		"runtime_source_thermal_node_traversals": 0,
		"max_total_mass_flow_kg_s": float(descriptor.max_total_mass_flow_kg_s),
		"sequence_ticks": SEQUENCE_TICKS,
		"full_reference_thermal_node_traversals": full_traversals,
		"maximum_plate_temperature_error": max_plate_error,
		"maximum_hot_coolant_temperature_error": max_hot_error,
		"maximum_cold_coolant_temperature_error": max_cold_error,
		"maximum_radiator_temperature_error": max_radiator_error,
		"maximum_state_parity_error": max_state_parity_error,
		"maximum_ambient_exchange_error_j": max_ambient_error,
		"maximum_pump_energy_error_j": max_pump_error,
		"maximum_energy_residual_j": max_energy_residual,
		"glycol_pump_energy_ratio": glycol_pump_ratio,
		"asymmetric_lane_error": String(asymmetric.get("error_code", "")),
		"asymmetric_detailed_reference_executes": asymmetric_reference_executes,
		"disabled_lane_error": String(disabled.get("error_code", "")),
		"off_manifold_error": String(projection_fail.get("error_code", "")),
		"nonfinite_projection_error": String(nonfinite_projection.get("error_code", "")),
		"nonfinite_reference_error": String(nonfinite_reference.get("error_code", "")),
		"out_of_domain_projection_error": String(out_of_domain_projection.get("error_code", "")),
		"out_of_domain_reference_error": String(out_of_domain_reference.get("error_code", "")),
		"descriptor_relation_error": String(inconsistent_check.get("error_code", "")),
		"flow_regime_descriptor_error": String(regime_check.get("error_code", "")),
		"t6_cooling_temperature_advantage_k": cooling_temperature_advantage_k,
		"t6_composition_heat_j": composition_heat_j,
		"t6_composition_pump_hydraulic_energy_j": composition_pump_j,
	}
	print("FABRIC_R5_2_T8_RESULT=" + JSON.stringify(deterministic))
	if not failed:
		print("FABRIC R5.2 T8 COOLING: PASS (%d assertions)" % checks)
	quit(1 if failed else 0)

func _finish() -> void:
	print("FABRIC R5.2 T8 COOLING: FAIL (%d assertions)" % checks)
	quit(1)

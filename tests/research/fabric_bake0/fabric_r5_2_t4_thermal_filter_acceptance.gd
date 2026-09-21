extends SceneTree

const Graph = preload("res://scripts/research/fabric_bake0/thermal_pack_graph_v1.gd")
const Compiler = preload("res://scripts/research/fabric_bake0/r5_t4_thermal_filter_compiler_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/r5_t4_thermal_filter_runtime_v1.gd")
const FullReference = preload("res://scripts/research/fabric_bake0/r5_t4_thermal_filter_full_reference_v1.gd")
const StateProjector = preload("res://scripts/research/fabric_bake0/thermal_filter_state_projector_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_r5_2_t4_thermal_filter_fixture.gd")

const SEQUENCE_TICKS := 2048
const DT_S := 0.05

var checks := 0
var failed := false

func check(ok: bool, label: String, details = null) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("R5.2-T4: " + label + " " + JSON.stringify(details))

func compile_graph(graph: Dictionary, revision: int = 0) -> Dictionary:
	return Compiler.compile(graph, Fixture.build_request(graph, revision), "capsule/r5-t4-thermal-filter")

func max_layer_error(detailed: Array, compact: Array, layers: int, lanes: int) -> float:
	if detailed.size() != layers * lanes or compact.size() != layers:
		return INF
	var out := 0.0
	for layer in range(layers):
		for lane in range(lanes):
			out = maxf(out, absf(float(detailed[layer * lanes + lane]) - float(compact[layer])))
	return out

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--preflight":
			var g := Fixture.make_graph()
			var c := compile_graph(g)
			var r := FullReference.prepare(g)
			if not c.success or not r.success:
				print("FABRIC_R5_2_T4_PREFLIGHT=FAIL")
				quit(1)
				return
			print("FABRIC_R5_2_T4_PREFLIGHT=PASS")
			quit(0)
			return

	var graph := Fixture.make_graph()
	var reversed_graph := Fixture.make_graph(false, true)
	check(Graph.validate(graph).success, "base graph valid")
	check(graph.cells.size() == Fixture.CELL_COUNT, "512 source cells", {"count": graph.cells.size()})
	check(String(graph.graph_hash) == String(reversed_graph.graph_hash), "raw ordering invariant")

	var compiled := compile_graph(graph)
	check(compiled.success, "base compile", compiled)
	if not compiled.success:
		_finish()
		return
	var descriptor: Dictionary = compiled.details.descriptor
	var artifact: Dictionary = compiled.details.artifact
	var capsule: Dictionary = compiled.details.capsule
	check(int(descriptor.source_cell_count) == Fixture.CELL_COUNT, "descriptor source count")
	check(int(descriptor.layer_count) == Fixture.LAYERS, "descriptor layer count")
	check(int(capsule.runtime_source_traversals_per_execute) == 0, "zero source traversal contract")
	check(int(capsule.full_operation_count) > int(capsule.executable_operation_count), "operation compression")
	check(float(capsule.operation_compression_ratio) > 10.0, "meaningful operation compression", {"ratio": capsule.operation_compression_ratio})

	var live := Fixture.live_from(artifact)
	var runtime = Runtime.new()
	var prepared := runtime.prepare(capsule, artifact, descriptor, live)
	check(prepared.success, "runtime prepare", prepared)
	var reference := FullReference.prepare(graph)
	check(reference.success, "detailed reference prepare", reference)
	if not prepared.success or not reference.success:
		_finish()
		return

	var compact_state := runtime.initial_state(293.15)
	var detailed_state := FullReference.initial_state(reference.details, 293.15)
	check(not compact_state.is_empty() and not detailed_state.is_empty(), "initial states")
	var projected := StateProjector.project(graph, descriptor, detailed_state)
	check(projected.success, "initial detailed state projects", projected)
	if projected.success:
		check(JSON.stringify(projected.details.next_state) == JSON.stringify(compact_state), "projected initial state equals runtime initial state")

	var max_temperature_error := 0.0
	var max_output_error := 0.0
	var max_energy_residual := 0.0
	var full_traversals := 0
	var last_output := 293.15
	for tick in range(SEQUENCE_TICKS):
		var phase := tick % 320
		var heat_input_w := 3200.0 if phase < 200 else 350.0
		var ambient_k := 293.15 + 3.0 * sin(float(tick) * 0.013)
		var full := FullReference.execute(reference.details, detailed_state, heat_input_w, DT_S, ambient_k)
		var fast := runtime.execute(live, compact_state, heat_input_w, DT_S, ambient_k)
		check(full.success and fast.success, "sequence execute", {"tick": tick, "full": full, "fast": fast})
		if not full.success or not fast.success:
			break
		max_output_error = maxf(max_output_error, absf(float(full.details.output_temperature_k) - float(fast.details.output_temperature_k)))
		max_temperature_error = maxf(max_temperature_error, max_layer_error(
			full.details.next_state.cell_temperature_k,
			fast.details.next_state.layer_temperature_k,
			Fixture.LAYERS,
			Fixture.LANES
		))
		max_energy_residual = maxf(max_energy_residual, absf(float(full.details.energy_residual_j)))
		max_energy_residual = maxf(max_energy_residual, absf(float(fast.details.energy_residual_j)))
		full_traversals += int(full.details.source_cell_traversals)
		detailed_state = full.details.next_state
		compact_state = fast.details.next_state
		last_output = float(fast.details.output_temperature_k)

	check(max_output_error <= 1.0e-9, "output parity", {"max_error": max_output_error})
	check(max_temperature_error <= 1.0e-9, "state parity", {"max_error": max_temperature_error})
	check(max_energy_residual <= 1.0e-8, "energy audit", {"max_residual_j": max_energy_residual})
	check(full_traversals == Fixture.CELL_COUNT * SEQUENCE_TICKS, "detailed traversal count", {"count": full_traversals})

	var asymmetric_graph := Fixture.make_graph(true)
	var asymmetric := compile_graph(asymmetric_graph, 1)
	check(not asymmetric.success and String(asymmetric.error_code) == "THERMAL_PACK_LAYER_SYMMETRY_BROKEN", "asymmetric lane fails closed", asymmetric)

	var mismatch := Compiler.compile(graph, Fixture.build_request(asymmetric_graph, 2), "capsule/r5-t4-thermal-filter")
	check(not mismatch.success and String(mismatch.error_code) == "THERMAL_FILTER_CANONICAL_GRAPH_SOURCE_MISMATCH", "frontier/graph mismatch rejected", mismatch)

	var perturbed: Dictionary = detailed_state.duplicate(true)
	perturbed.cell_temperature_k = detailed_state.cell_temperature_k.duplicate()
	perturbed.cell_temperature_k[3] = float(perturbed.cell_temperature_k[3]) + 0.01
	var rejected_projection := StateProjector.project(graph, descriptor, perturbed)
	check(not rejected_projection.success and String(rejected_projection.error_code) == "THERMAL_STATE_NOT_IN_REDUCTION_MANIFOLD", "off-manifold detailed state rejected", rejected_projection)

	var stale_live: Dictionary = live.duplicate(true)
	stale_live.artifact_state = "STALE"
	check(not runtime.execute(stale_live, compact_state, 100.0, DT_S, 293.15).success, "STALE rejected")
	var invalidated_live: Dictionary = live.duplicate(true)
	invalidated_live.invalidations = [{"synthetic": true}]
	check(not runtime.execute(invalidated_live, compact_state, 100.0, DT_S, 293.15).success, "invalidation rejected")
	var authority_drift: Dictionary = live.duplicate(true)
	authority_drift.authority_envelope = live.authority_envelope.duplicate(true)
	authority_drift.authority_envelope.checksum = "0".repeat(64)
	check(not runtime.execute(authority_drift, compact_state, 100.0, DT_S, 293.15).success, "authority drift rejected")

	var deterministic := {
		"schema": "planet_simulator.fabric_r5_2_t4_thermal_filter_result.v1",
		"graph_hash": graph.graph_hash,
		"descriptor_hash": descriptor.descriptor_hash,
		"capsule_checksum": capsule.checksum,
		"source_cells": int(descriptor.source_cell_count),
		"layers": int(descriptor.layer_count),
		"lanes": int(descriptor.lane_count),
		"state_scalars": int(descriptor.layer_count),
		"source_operations": int(descriptor.source_operation_count),
		"compiled_operations": int(descriptor.compiled_operation_count),
		"operation_compression_ratio": float(capsule.operation_compression_ratio),
		"runtime_source_cell_traversals": 0,
		"sequence_ticks": SEQUENCE_TICKS,
		"full_reference_cell_traversals": full_traversals,
		"maximum_output_temperature_error": max_output_error,
		"maximum_layer_temperature_error": max_temperature_error,
		"maximum_energy_residual_j": max_energy_residual,
		"final_output_temperature_k": last_output,
		"asymmetry_error": String(asymmetric.get("error_code", "")),
		"off_manifold_error": String(rejected_projection.get("error_code", "")),
	}
	print("FABRIC_R5_2_T4_RESULT=" + JSON.stringify(deterministic))
	if not failed:
		print("FABRIC R5.2 T4 STATEFUL FILTER THERMAL PACK: PASS (%d assertions)" % checks)
	quit(1 if failed else 0)

func _finish() -> void:
	print("FABRIC R5.2 T4 STATEFUL FILTER THERMAL PACK: FAIL (%d assertions)" % checks)
	quit(1)

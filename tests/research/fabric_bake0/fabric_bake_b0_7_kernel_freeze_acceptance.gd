extends SceneTree

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/unseen_machine_generic_graph_v1.gd")
const GenericCompiler = preload("res://scripts/research/fabric_bake0/unseen_machine_generic_compiler_v1.gd")
const Protocol = preload("res://scripts/research/fabric_bake0/unseen_machine_challenge_protocol_v1.gd")
const Reducer = preload("res://scripts/research/fabric_bake0/exact_boundary_reducer_v1.gd")

var checks := 0

func _check(condition: bool, label: String) -> void:
	if not condition:
		push_error("B0.7 KERNEL ASSERTION FAILED: %s" % label)
		quit(1)
		return
	checks += 1

func _init() -> void:
	var base := _probe_spec(false, false)
	_check(not base.is_empty(), "generic probe graph builds")
	_check(bool(Graph.validate(base).get("success", false)), "generic probe graph validates")
	_check(base["internal_node_ids"].size() == 128, "probe has reduction-scale internal block")
	var compiled := GenericCompiler.compile(base)
	_check(String(compiled.get("status", "")) == "BAKE_READY", "generic compiler reaches BAKE_READY")
	if String(compiled.get("status", "")) != "BAKE_READY":
		return
	var descriptor: Dictionary = compiled["compile_result"]["diagnostics"]["reduction"]
	_check(int(descriptor["full_equation_count"]) == 132, "full probe has 132 equations")
	_check(int(descriptor["reduced_equation_count"]) == 4, "generic bake has four boundary equations")
	_check(float(descriptor["runtime_work_ratio"]) >= 1000.0, "generic bake has meaningful work reduction")
	_check(bool(descriptor["passivity_certified"]), "generic passive graph remains passive after reduction")

	var system: Dictionary = compiled["context"]["linear_system"]
	var effort := [7.0, -3.0, 1.25, 0.5]
	var full := Reducer.evaluate_full(system, effort, GenericCompiler.PIVOT_TOLERANCE)
	var reduced := Reducer.evaluate_reduced(descriptor, effort)
	_check(bool(full.get("success", false)) and bool(reduced.get("success", false)), "full and reduced generic evaluations succeed")
	if not bool(full.get("success", false)) or not bool(reduced.get("success", false)):
		return
	var max_error := 0.0
	for index in range(effort.size()):
		max_error = maxf(max_error, absf(float(full["details"]["boundary_flow"][index]) - float(reduced["details"]["boundary_flow"][index])))
	_check(max_error <= GenericCompiler.FLOW_ERROR_LIMIT, "generic reduced boundary flow matches FULL")
	_check(absf(float(full["details"]["boundary_power"]) - float(reduced["details"]["boundary_power"])) <= GenericCompiler.POWER_ERROR_LIMIT, "generic reduced boundary power matches FULL")

	var reordered := _probe_spec(true, false)
	_check(String(reordered["graph_hash"]) == String(base["graph_hash"]), "input edge order cannot change generic graph identity")
	_check(String(Graph.to_linear_system(reordered)["system_hash"]) == String(system["system_hash"]), "input order cannot change full linear system")

	var successor := _probe_successor(base, ["edge/probe-output"], "event/probe-output-loss")
	_check(not successor.is_empty(), "pure external successor fixture builds")
	var case := Protocol.run_case(base, successor, "event/probe-output-loss", ["edge/probe-output"], [[8.0, 0.0, 0.0, 0.0], [3.0, -1.0, 2.0, -0.5]], "port/probe-d")
	_check(bool(case.get("success", false)), "generic unseen protocol executes probe lifecycle")
	if bool(case.get("success", false)):
		var result: Dictionary = case["details"]
		_check(String(result["stale_error"]) == "STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN", "old bake is fenced after canonical successor")
		_check(float(result["observation_flow_delta"]) > 1.0e-6, "generic topology loss causes measurable downstream consequence")
		_check(int(result["base_active_edges"]) == int(result["successor_active_edges"]) + 1, "exactly one physical edge is lost")

	var duplicate_successor := successor.duplicate(true)
	duplicate_successor["applied_event_ids"].append("event/probe-output-loss")
	duplicate_successor["graph_hash"] = Utils.canonical_hash({
		"machine_id": duplicate_successor["machine_id"], "revision": duplicate_successor["revision"],
		"boundary_node_ids": duplicate_successor["boundary_node_ids"], "internal_node_ids": duplicate_successor["internal_node_ids"],
		"edges": duplicate_successor["edges"], "applied_event_ids": duplicate_successor["applied_event_ids"],
	})
	duplicate_successor["checksum"] = Utils.compute_checksum(duplicate_successor)
	_check(not bool(Graph.validate(duplicate_successor).get("success", false)), "duplicate event ledger cannot be rehashed into validity")

	var bad_conductance := base.duplicate(true)
	bad_conductance["edges"][0]["conductance"] = -1.0
	bad_conductance["graph_hash"] = Utils.canonical_hash({
		"machine_id": bad_conductance["machine_id"], "revision": bad_conductance["revision"],
		"boundary_node_ids": bad_conductance["boundary_node_ids"], "internal_node_ids": bad_conductance["internal_node_ids"],
		"edges": bad_conductance["edges"], "applied_event_ids": bad_conductance["applied_event_ids"],
	})
	bad_conductance["checksum"] = Utils.compute_checksum(bad_conductance)
	_check(not bool(Graph.validate(bad_conductance).get("success", false)), "negative edge law fails closed even if rehashed")

	var unsafe := _probe_spec(false, true)
	var unsafe_result := Protocol.expect_no_safe_bake(unsafe)
	_check(bool(unsafe_result.get("success", false)), "disconnected hidden internal state produces NO_SAFE_BAKE")
	if bool(unsafe_result.get("success", false)):
		_check(String(unsafe_result["details"]["reason"]) == "RANK_DEFICIENCY", "unsafe generic graph fails for exact rank reason")

	var kernel_hash := Utils.canonical_hash({
		"graph": base["graph_hash"],
		"descriptor": descriptor["checksum"],
		"case": case.get("details", {}).get("result_hash", ""),
	})
	print("FABRIC-BAKE B0.7 KERNEL FREEZE: PASS (%d assertions) full=%d reduced=%d work_ratio=%.1f kernel=%s" % [checks, int(descriptor["full_equation_count"]), int(descriptor["reduced_equation_count"]), float(descriptor["runtime_work_ratio"]), kernel_hash])
	quit(0)

func _probe_spec(reverse_edges: bool, isolate_last_internal: bool) -> Dictionary:
	var boundaries: Array = ["port/probe-a", "port/probe-b", "port/probe-c", "port/probe-d"]
	var internals: Array = []
	for index in range(128):
		internals.append("node/probe-%03d" % index)
	var edges: Array = []
	var connected_count := 127 if isolate_last_internal else 128
	for index in range(connected_count - 1):
		edges.append(_edge("edge/probe-chain-%03d" % index, internals[index], internals[index + 1], 1.0 + float(index % 7) * 0.05))
	for index in range(connected_count):
		var other := (index + 11) % connected_count
		if index < other:
			edges.append(_edge("edge/probe-skip-%03d-%03d" % [index, other], internals[index], internals[other], 0.17 + float(index % 5) * 0.02))
	for boundary_index in range(3):
		for lane in range(2):
			var internal_index := (boundary_index * 29 + lane * 17) % connected_count
			edges.append(_edge("edge/probe-port-%d-%d" % [boundary_index, lane], boundaries[boundary_index], internals[internal_index], 0.8 + 0.1 * float(boundary_index + lane)))
	edges.append(_edge("edge/probe-output", boundaries[3], internals[connected_count - 1], 1.3))
	if reverse_edges:
		edges.reverse()
	return Graph.create("machine/kernel-probe", 1, boundaries, internals, edges, [])

func _probe_successor(base: Dictionary, failed_edge_ids: Array, event_id: String) -> Dictionary:
	var edges: Array = []
	for edge in base["edges"]:
		var next := Dictionary(edge).duplicate(true)
		if failed_edge_ids.has(String(next["edge_id"])):
			next["active"] = false
		edges.append(next)
	var events: Array = base["applied_event_ids"].duplicate()
	events.append(event_id)
	return Graph.create(String(base["machine_id"]), int(base["revision"]) + 1, base["boundary_node_ids"], base["internal_node_ids"], edges, events)

func _edge(edge_id: String, a: String, b: String, conductance: float) -> Dictionary:
	return {"edge_id": edge_id, "node_a": a, "node_b": b, "conductance": conductance, "active": true}

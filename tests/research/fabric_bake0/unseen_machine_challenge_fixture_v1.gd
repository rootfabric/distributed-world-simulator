extends RefCounted

const Graph = preload("res://scripts/research/fabric_bake0/unseen_machine_generic_graph_v1.gd")

const FREEZE_HEAD := "9dda6872081c19ce2add86bb590a9aa4925c6ac9"
const HEX := "0123456789abcdef"
const CASE_NAMES: Array[String] = ["alpha", "beta", "gamma"]

static func all_cases() -> Array:
	var result: Array = []
	for case_index in range(CASE_NAMES.size()):
		result.append(_build_case(case_index))
	return result

static func unsafe_case() -> Dictionary:
	var source: Dictionary = _build_case(2)["base"]
	var isolate_id := String(source["internal_node_ids"][0])
	var edges: Array = []
	for raw in source["edges"]:
		var edge: Dictionary = Dictionary(raw).duplicate(true)
		if String(edge["node_a"]) == isolate_id or String(edge["node_b"]) == isolate_id:
			edge["active"] = false
		edges.append(edge)
	return Graph.create(
		"machine/unseen-unsafe-%s" % FREEZE_HEAD.substr(0, 8),
		1,
		source["boundary_node_ids"],
		source["internal_node_ids"],
		edges,
		[]
	)

static func forged_successor(case_data: Dictionary) -> Dictionary:
	var successor: Dictionary = case_data["successor"]
	var edges: Array = successor["edges"].duplicate(true)
	for index in range(edges.size()):
		if bool(edges[index]["active"]):
			edges[index]["conductance"] = float(edges[index]["conductance"]) * 1.125
			break
	return Graph.create(
		String(successor["machine_id"]),
		int(successor["revision"]),
		successor["boundary_node_ids"],
		successor["internal_node_ids"],
		edges,
		successor["applied_event_ids"]
	)

static func _build_case(case_index: int) -> Dictionary:
	var label := CASE_NAMES[case_index]
	var seed_a := _seed(case_index * 9)
	var seed_b := _seed(case_index * 9 + 5)
	var internal_count := 128 + case_index * 32 + (seed_a % 4) * 8
	var boundaries: Array = [
		"port/unseen-%s-a" % label,
		"port/unseen-%s-b" % label,
		"port/unseen-%s-c" % label,
		"port/unseen-%s-d" % label,
	]
	var internals: Array = []
	for index in range(internal_count):
		internals.append("node/unseen-%s-%03d" % [label, index])
	var edges: Array = []
	for index in range(internal_count - 1):
		edges.append(_edge(
			"edge/unseen-%s-backbone-%03d" % [label, index],
			internals[index], internals[index + 1],
			0.85 + 0.025 * float((seed_a + index) % 11)
		))
	var stride_one := 7 + int(seed_a % 11)
	var stride_two := 19 + int(seed_b % 17)
	for index in range(internal_count):
		var other_one := index + stride_one
		if other_one < internal_count:
			edges.append(_edge(
				"edge/unseen-%s-x1-%03d-%03d" % [label, index, other_one],
				internals[index], internals[other_one],
				0.11 + 0.01 * float((seed_b + index) % 9)
			))
		var other_two := index + stride_two
		if other_two < internal_count and (index + case_index) % 2 == 0:
			edges.append(_edge(
				"edge/unseen-%s-x2-%03d-%03d" % [label, index, other_two],
				internals[index], internals[other_two],
				0.07 + 0.008 * float((seed_a + index * 3) % 7)
			))
	for port_index in range(3):
		for lane in range(2):
			var attach := int((seed_a + seed_b * (port_index + 1) + lane * stride_two + port_index * 31) % internal_count)
			edges.append(_edge(
				"edge/unseen-%s-port-%d-%d" % [label, port_index, lane],
				boundaries[port_index], internals[attach],
				0.72 + 0.06 * float((seed_a + port_index * 5 + lane) % 8)
			))
	var critical_edge_id := "edge/unseen-%s-critical-output" % label
	var critical_attach := int((seed_b + internal_count - 1) % internal_count)
	edges.append(_edge(
		critical_edge_id,
		boundaries[3], internals[critical_attach],
		1.05 + 0.05 * float(seed_b % 6)
	))
	var machine_id := "machine/unseen-%s-%s" % [label, FREEZE_HEAD.substr(case_index * 8, 8)]
	var base := Graph.create(machine_id, 1, boundaries, internals, edges, [])
	var successor_edges: Array = []
	for raw in base.get("edges", []):
		var next: Dictionary = Dictionary(raw).duplicate(true)
		if String(next["edge_id"]) == critical_edge_id:
			next["active"] = false
		successor_edges.append(next)
	var event_id := "event/unseen-%s-output-loss" % label
	var successor := Graph.create(machine_id, 2, boundaries, internals, successor_edges, [event_id])
	return {
		"name": label,
		"seed_a": seed_a,
		"seed_b": seed_b,
		"internal_count": internal_count,
		"base": base,
		"successor": successor,
		"failure_event_id": event_id,
		"failed_edge_ids": [critical_edge_id],
		"observation_port_id": boundaries[3],
		"excitations": [
			[12.0, 0.0, 0.0, 0.0],
			[3.0, -1.0, 2.0, -0.5],
			[0.0, 4.0, -2.0, 1.0],
			[-2.5, 1.5, 0.25, 3.0],
		],
	}

static func _seed(offset: int) -> int:
	var total := 0
	for index in range(8):
		var position := (offset + index) % FREEZE_HEAD.length()
		var digit := HEX.find(FREEZE_HEAD.substr(position, 1))
		total = (total * 16 + digit) % 2147483629
	return total

static func _edge(edge_id: String, a: String, b: String, conductance: float) -> Dictionary:
	return {
		"edge_id": edge_id,
		"node_a": a,
		"node_b": b,
		"conductance": conductance,
		"active": true,
	}

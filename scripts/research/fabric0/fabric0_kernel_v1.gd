class_name Fabric0KernelV1
extends RefCounted

const EPSILON := 1.0e-9
const DEFAULT_SETTLE_ITERATIONS := 32

static func new_graph() -> Dictionary:
	return {
		"elements": {},
		"bonds": [],
		"events": [],
		"tick": 0,
	}

static func source(element_id: String, domain: String, value: float) -> Dictionary:
	return _element(
		element_id,
		{"op": "source", "value": value},
		{"out": _port("out", domain)},
	)

static func gain(element_id: String, domain: String, factor: float) -> Dictionary:
	return _element(
		element_id,
		{"op": "gain", "factor": factor},
		{"in": _port("in", domain), "out": _port("out", domain)},
	)

static func transducer(element_id: String, input_domain: String, output_domain: String, efficiency: float) -> Dictionary:
	return _element(
		element_id,
		{"op": "gain", "factor": efficiency},
		{"in": _port("in", input_domain), "out": _port("out", output_domain)},
	)

static func threshold(element_id: String, input_domain: String, threshold_value: float, mode: String = "gte") -> Dictionary:
	assert(mode == "gte" or mode == "lte")
	return _element(
		element_id,
		{"op": "threshold", "threshold": threshold_value, "mode": mode},
		{"in": _port("in", input_domain), "out": _port("out", "signal")},
	)

static func gate(element_id: String, domain: String) -> Dictionary:
	return _element(
		element_id,
		{"op": "gate"},
		{
			"in": _port("in", domain),
			"control": _port("in", "signal"),
			"out": _port("out", domain),
		},
	)

static func integrator(
	element_id: String,
	flow_domain: String,
	value_domain: String,
	initial_value: float,
	minimum: float = -INF,
	maximum: float = INF
) -> Dictionary:
	return _element(
		element_id,
		{"op": "integrator", "minimum": minimum, "maximum": maximum},
		{
			"flow": _port("in", flow_domain),
			"value": _port("out", value_domain),
		},
		{"value": initial_value},
	)

static func sink(element_id: String, domain: String) -> Dictionary:
	return _element(
		element_id,
		{"op": "sink"},
		{"in": _port("in", domain)},
	)

static func add_element(graph: Dictionary, element: Dictionary) -> bool:
	var element_id := String(element.get("id", ""))
	if element_id.is_empty() or graph["elements"].has(element_id):
		return false
	graph["elements"][element_id] = element.duplicate(true)
	return true

static func link(
	graph: Dictionary,
	bond_id: String,
	from_element: String,
	from_port: String,
	to_element: String,
	to_port: String,
	capacity: float = INF
) -> bool:
	if bond_id.is_empty() or _find_bond_index(graph, bond_id) >= 0:
		return false
	if not graph["elements"].has(from_element) or not graph["elements"].has(to_element):
		return false
	var from_spec: Dictionary = graph["elements"][from_element]["ports"].get(from_port, {})
	var to_spec: Dictionary = graph["elements"][to_element]["ports"].get(to_port, {})
	if from_spec.is_empty() or to_spec.is_empty():
		return false
	if String(from_spec.get("direction", "")) != "out" or String(to_spec.get("direction", "")) != "in":
		return false
	if String(from_spec.get("domain", "")) != String(to_spec.get("domain", "")):
		return false
	graph["bonds"].append({
		"id": bond_id,
		"from_element": from_element,
		"from_port": from_port,
		"to_element": to_element,
		"to_port": to_port,
		"domain": String(from_spec["domain"]),
		"capacity": maxf(capacity, 0.0),
		"active": true,
		"last_transfer": 0.0,
	})
	return true

static func set_source_value(graph: Dictionary, element_id: String, value: float) -> bool:
	if not graph["elements"].has(element_id):
		return false
	var element: Dictionary = graph["elements"][element_id]
	if String(element["law"].get("op", "")) != "source":
		return false
	element["law"]["value"] = value
	return true

static func step(graph: Dictionary, delta: float = 1.0, settle_iterations: int = DEFAULT_SETTLE_ITERATIONS) -> Dictionary:
	assert(delta >= 0.0)
	_settle(graph, settle_iterations)
	var topology_changed := _break_overloaded_bonds(graph)
	if topology_changed:
		_settle(graph, settle_iterations)
	_advance_stateful_elements(graph, delta)
	_settle(graph, settle_iterations)
	graph["tick"] = int(graph.get("tick", 0)) + 1
	return graph

static func settle(graph: Dictionary, settle_iterations: int = DEFAULT_SETTLE_ITERATIONS) -> Dictionary:
	_settle(graph, settle_iterations)
	return graph

static func read_input(graph: Dictionary, element_id: String, port_name: String = "in") -> float:
	if not graph["elements"].has(element_id):
		return 0.0
	return float(graph["elements"][element_id]["inputs"].get(port_name, 0.0))

static func read_output(graph: Dictionary, element_id: String, port_name: String = "out") -> float:
	if not graph["elements"].has(element_id):
		return 0.0
	return float(graph["elements"][element_id]["outputs"].get(port_name, 0.0))

static func read_state(graph: Dictionary, element_id: String, key: String) -> Variant:
	if not graph["elements"].has(element_id):
		return null
	return graph["elements"][element_id]["state"].get(key)

static func is_bond_active(graph: Dictionary, bond_id: String) -> bool:
	var index := _find_bond_index(graph, bond_id)
	return index >= 0 and bool(graph["bonds"][index].get("active", false))

static func connected_components(graph: Dictionary) -> Array:
	var adjacency := {}
	var ids: Array = graph["elements"].keys()
	ids.sort()
	for element_id in ids:
		adjacency[element_id] = []
	for bond in graph["bonds"]:
		if not bool(bond.get("active", false)):
			continue
		var a := String(bond["from_element"])
		var b := String(bond["to_element"])
		adjacency[a].append(b)
		adjacency[b].append(a)
	var visited := {}
	var result: Array = []
	for root in ids:
		if visited.has(root):
			continue
		var queue: Array = [root]
		var component: Array = []
		visited[root] = true
		while not queue.is_empty():
			var current: String = queue.pop_front()
			component.append(current)
			var neighbours: Array = adjacency[current]
			neighbours.sort()
			for neighbour in neighbours:
				if not visited.has(neighbour):
					visited[neighbour] = true
					queue.append(neighbour)
		component.sort()
		result.append(component)
	return result

static func canonical_snapshot(graph: Dictionary) -> Dictionary:
	var element_ids: Array = graph["elements"].keys()
	element_ids.sort()
	var elements: Array = []
	for element_id in element_ids:
		var element: Dictionary = graph["elements"][element_id]
		elements.append({
			"id": element_id,
			"law": _sorted_dictionary(element["law"]),
			"state": _sorted_dictionary(element["state"]),
			"inputs": _sorted_dictionary(element["inputs"]),
			"outputs": _sorted_dictionary(element["outputs"]),
		})
	var bonds: Array = []
	for bond in graph["bonds"]:
		bonds.append({
			"id": String(bond["id"]),
			"from_element": String(bond["from_element"]),
			"from_port": String(bond["from_port"]),
			"to_element": String(bond["to_element"]),
			"to_port": String(bond["to_port"]),
			"domain": String(bond["domain"]),
			"capacity": float(bond["capacity"]),
			"active": bool(bond["active"]),
			"last_transfer": float(bond["last_transfer"]),
		})
	bonds.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"]))
	return {"tick": int(graph["tick"]), "elements": elements, "bonds": bonds}

static func state_hash(graph: Dictionary) -> String:
	var payload := JSON.stringify(canonical_snapshot(graph), "", false)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(payload.to_utf8_buffer())
	return context.finish().hex_encode()

static func _settle(graph: Dictionary, settle_iterations: int) -> void:
	var iterations := maxi(settle_iterations, 1)
	for _iteration in range(iterations):
		_rebuild_inputs(graph)
		var max_delta := 0.0
		var element_ids: Array = graph["elements"].keys()
		element_ids.sort()
		for element_id in element_ids:
			var element: Dictionary = graph["elements"][element_id]
			var previous: Dictionary = element["outputs"].duplicate(true)
			_evaluate_outputs(element)
			for key in element["outputs"].keys():
				max_delta = maxf(max_delta, absf(float(element["outputs"][key]) - float(previous.get(key, 0.0))))
		if max_delta <= EPSILON:
			break
	_rebuild_inputs(graph)

static func _rebuild_inputs(graph: Dictionary) -> void:
	for element in graph["elements"].values():
		for port_name in element["ports"].keys():
			var spec: Dictionary = element["ports"][port_name]
			if String(spec["direction"]) == "in":
				element["inputs"][port_name] = 0.0
	for bond in graph["bonds"]:
		if not bool(bond.get("active", false)):
			bond["last_transfer"] = 0.0
			continue
		var source: Dictionary = graph["elements"][String(bond["from_element"])]
		var target: Dictionary = graph["elements"][String(bond["to_element"])]
		var transfer := float(source["outputs"].get(String(bond["from_port"]), 0.0))
		bond["last_transfer"] = transfer
		var input_name := String(bond["to_port"])
		target["inputs"][input_name] = float(target["inputs"].get(input_name, 0.0)) + transfer

static func _evaluate_outputs(element: Dictionary) -> void:
	var op := String(element["law"].get("op", ""))
	match op:
		"source":
			element["outputs"]["out"] = float(element["law"].get("value", 0.0))
		"gain":
			element["outputs"]["out"] = float(element["inputs"].get("in", 0.0)) * float(element["law"].get("factor", 1.0))
		"threshold":
			var value := float(element["inputs"].get("in", 0.0))
			var threshold_value := float(element["law"].get("threshold", 0.0))
			var mode := String(element["law"].get("mode", "gte"))
			var enabled := value >= threshold_value if mode == "gte" else value <= threshold_value
			element["outputs"]["out"] = 1.0 if enabled else 0.0
		"gate":
			var enabled := float(element["inputs"].get("control", 0.0)) > 0.5
			element["outputs"]["out"] = float(element["inputs"].get("in", 0.0)) if enabled else 0.0
		"integrator":
			element["outputs"]["value"] = float(element["state"].get("value", 0.0))
		"sink":
			pass
		_:
			push_error("FABRIC0 unknown law op: %s" % op)

static func _advance_stateful_elements(graph: Dictionary, delta: float) -> void:
	var element_ids: Array = graph["elements"].keys()
	element_ids.sort()
	for element_id in element_ids:
		var element: Dictionary = graph["elements"][element_id]
		if String(element["law"].get("op", "")) != "integrator":
			continue
		var value := float(element["state"].get("value", 0.0))
		value += float(element["inputs"].get("flow", 0.0)) * delta
		value = clampf(value, float(element["law"].get("minimum", -INF)), float(element["law"].get("maximum", INF)))
		element["state"]["value"] = value

static func _break_overloaded_bonds(graph: Dictionary) -> bool:
	var changed := false
	for bond in graph["bonds"]:
		if not bool(bond.get("active", false)):
			continue
		var capacity := float(bond.get("capacity", INF))
		var transfer := absf(float(bond.get("last_transfer", 0.0)))
		if transfer <= capacity + EPSILON:
			continue
		bond["active"] = false
		changed = true
		graph["events"].append({
			"type": "bond_broken",
			"bond_id": String(bond["id"]),
			"tick": int(graph.get("tick", 0)),
			"transfer": transfer,
			"capacity": capacity,
		})
	return changed

static func _find_bond_index(graph: Dictionary, bond_id: String) -> int:
	for index in range(graph["bonds"].size()):
		if String(graph["bonds"][index].get("id", "")) == bond_id:
			return index
	return -1

static func _port(direction: String, domain: String) -> Dictionary:
	return {"direction": direction, "domain": domain}

static func _element(
	element_id: String,
	law: Dictionary,
	ports: Dictionary,
	state: Dictionary = {}
) -> Dictionary:
	var inputs := {}
	var outputs := {}
	for port_name in ports.keys():
		var spec: Dictionary = ports[port_name]
		if String(spec["direction"]) == "in":
			inputs[port_name] = 0.0
		else:
			outputs[port_name] = 0.0
	return {
		"id": element_id,
		"law": law.duplicate(true),
		"ports": ports.duplicate(true),
		"state": state.duplicate(true),
		"inputs": inputs,
		"outputs": outputs,
	}

static func _sorted_dictionary(source: Dictionary) -> Dictionary:
	var result := {}
	var keys: Array = source.keys()
	keys.sort()
	for key in keys:
		result[key] = source[key]
	return result

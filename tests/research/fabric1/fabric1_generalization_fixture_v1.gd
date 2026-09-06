extends RefCounted

const Component = preload("res://scripts/research/fabric_bake0/fabric1_component_contract_v1.gd")
const Composer = preload("res://scripts/research/fabric_bake0/fabric1_generalized_composer_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/unseen_machine_generic_graph_v1.gd")

static func build(width: int = 48, revision: int = 1, applied_event_ids: Array = []) -> Dictionary:
	var components := [
		_component("a", ["port/fabric1-a-in", "port/fabric1-a-link"], width, 0),
		_component("b", ["port/fabric1-b-link-in", "port/fabric1-b-sense-a", "port/fabric1-b-sense-b", "port/fabric1-b-link-out"], width, 1),
		_component("c", ["port/fabric1-c-link", "port/fabric1-c-out"], width, 2),
	]
	if components.has({}):
		return {}
	var connectors := [
		{"connector_id": "edge/fabric1-connector-ab", "port_a": "port/fabric1-a-link", "port_b": "port/fabric1-b-link-in", "conductance": 0.91, "active": true},
		{"connector_id": "edge/fabric1-connector-bc", "port_a": "port/fabric1-b-link-out", "port_b": "port/fabric1-c-link", "conductance": 1.07, "active": true},
	]
	var composed := Composer.compose("machine/fabric1-generalized", revision, components, connectors, applied_event_ids)
	if not bool(composed.get("success", false)):
		return {}
	return {
		"components": components,
		"connectors": connectors,
		"composition": composed["details"],
		"spec": composed["details"]["spec"],
		"critical_edge_id": "edge/fabric1-c-critical-output",
		"event_id": "event/fabric1-output-loss",
		"observation_port_id": "port/fabric1-c-out",
		"excitations": [
			[12.0, 0.0, 0.0, 0.0],
			[2.5, -1.0, 1.5, -0.25],
			[0.0, 4.0, -2.0, 1.0],
		],
	}

static func successor(base_data: Dictionary) -> Dictionary:
	var base: Dictionary = base_data["spec"]
	var edges: Array = []
	for raw in base["edges"]:
		var edge: Dictionary = Dictionary(raw).duplicate(true)
		if String(edge["edge_id"]) == String(base_data["critical_edge_id"]):
			edge["active"] = false
		edges.append(edge)
	return Graph.create(
		String(base["machine_id"]),
		int(base["revision"]) + 1,
		base["boundary_node_ids"],
		base["internal_node_ids"],
		edges,
		[String(base_data["event_id"])]
	)

static func reordered(base_data: Dictionary) -> Dictionary:
	var components: Array = base_data["components"].duplicate(true)
	components.reverse()
	var connectors: Array = base_data["connectors"].duplicate(true)
	connectors.reverse()
	var result := Composer.compose("machine/fabric1-generalized", 1, components, connectors, [])
	return result["details"]["spec"] if bool(result.get("success", false)) else {}

static func overlapping_component(base_data: Dictionary) -> Dictionary:
	var components: Array = base_data["components"].duplicate(true)
	var bad: Dictionary = Dictionary(components[1]).duplicate(true)
	var internals: Array = bad["internal_node_ids"].duplicate()
	internals[0] = String(components[0]["internal_node_ids"][0])
	var edges: Array = bad["edges"].duplicate(true)
	for index in range(edges.size()):
		if String(edges[index]["node_a"]) == String(bad["internal_node_ids"][0]):
			edges[index]["node_a"] = internals[0]
		if String(edges[index]["node_b"]) == String(bad["internal_node_ids"][0]):
			edges[index]["node_b"] = internals[0]
	bad = Component.create(String(bad["component_id"]), bad["port_node_ids"], internals, edges)
	components[1] = bad
	return Composer.compose("machine/fabric1-overlap", 1, components, base_data["connectors"], [])

static func double_bound_connector(base_data: Dictionary) -> Dictionary:
	var connectors: Array = base_data["connectors"].duplicate(true)
	connectors.append({"connector_id": "edge/fabric1-connector-illegal", "port_a": "port/fabric1-a-link", "port_b": "port/fabric1-c-link", "conductance": 0.5, "active": true})
	return Composer.compose("machine/fabric1-double-bound", 1, base_data["components"], connectors, [])

static func _component(label: String, ports: Array, width: int, salt: int) -> Dictionary:
	if width < 24:
		return {}
	var internals: Array = []
	for index in range(width):
		internals.append("node/fabric1-%s-%03d" % [label, index])
	var edges: Array = []
	for index in range(width - 1):
		edges.append(_edge("edge/fabric1-%s-backbone-%03d" % [label, index], internals[index], internals[index + 1], 0.82 + 0.017 * float((index + salt * 3) % 11)))
	for index in range(width - 9):
		if (index + salt) % 2 == 0:
			edges.append(_edge("edge/fabric1-%s-cross-%03d" % [label, index], internals[index], internals[index + 9], 0.13 + 0.009 * float((index + salt) % 7)))
	for port_index in range(ports.size()):
		var attach := int((port_index * 17 + salt * 13 + 3) % width)
		var edge_id := "edge/fabric1-%s-port-%02d" % [label, port_index]
		if label == "c" and String(ports[port_index]) == "port/fabric1-c-out":
			edge_id = "edge/fabric1-c-critical-output"
		edges.append(_edge(edge_id, String(ports[port_index]), internals[attach], 0.95 + 0.05 * float((port_index + salt) % 5)))
	return Component.create("component/fabric1-%s" % label, ports, internals, edges)

static func _edge(edge_id: String, a: String, b: String, conductance: float) -> Dictionary:
	return {"edge_id": edge_id, "node_a": a, "node_b": b, "conductance": conductance, "active": true}

extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Component = preload("res://scripts/research/fabric_bake0/fabric1_component_contract_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/unseen_machine_generic_graph_v1.gd")

const CONNECTOR_FIELDS: Array[String] = ["connector_id", "port_a", "port_b", "conductance", "active"]

static func compose(machine_id: String, revision: int, components: Array, connectors: Array, applied_event_ids: Array = []) -> Dictionary:
	if not Utils.is_canonical_id(machine_id, 2) or not Utils.is_json_integer(revision) or revision < 1:
		return Utils.failure("FABRIC1_COMPOSITION_ID_INVALID")
	if components.size() < 2:
		return Utils.failure("FABRIC1_COMPOSITION_REQUIRES_COMPONENTS")
	var ordered_components: Array = components.duplicate(true)
	ordered_components.sort_custom(func(a, b): return String(a.get("component_id", "")) < String(b.get("component_id", "")))
	var component_ids := {}
	var all_nodes := {}
	var all_ports := {}
	var final_edges: Array = []
	var component_hashes: Array = []
	for raw in ordered_components:
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("FABRIC1_COMPONENT_RECORD_INVALID")
		var component: Dictionary = raw
		var checked := Component.validate(component)
		if not bool(checked.get("success", false)):
			return Utils.failure("FABRIC1_COMPONENT_INVALID", {"cause": checked.get("error_code", "")})
		var component_id := String(component["component_id"])
		if component_ids.has(component_id):
			return Utils.failure("FABRIC1_COMPONENT_ID_DUPLICATE")
		component_ids[component_id] = true
		component_hashes.append(String(component["component_hash"]))
		for port_id in component["port_node_ids"]:
			var id := String(port_id)
			if all_nodes.has(id):
				return Utils.failure("FABRIC1_COMPOSITION_NODE_OVERLAP", {"node_id": id})
			all_nodes[id] = component_id
			all_ports[id] = component_id
		for node_id in component["internal_node_ids"]:
			var id := String(node_id)
			if all_nodes.has(id):
				return Utils.failure("FABRIC1_COMPOSITION_NODE_OVERLAP", {"node_id": id})
			all_nodes[id] = component_id
		for edge in component["edges"]:
			final_edges.append(Dictionary(edge).duplicate(true))

	var ordered_connectors: Array = connectors.duplicate(true)
	ordered_connectors.sort_custom(func(a, b): return String(a.get("connector_id", "")) < String(b.get("connector_id", "")))
	var connected_ports := {}
	var connector_ids := {}
	var previous := ""
	for index in range(ordered_connectors.size()):
		var raw = ordered_connectors[index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("FABRIC1_CONNECTOR_RECORD_INVALID")
		var connector: Dictionary = raw
		var checked := Utils.validate_exact_fields(connector, CONNECTOR_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		var connector_id := String(connector.get("connector_id", ""))
		if not Utils.is_canonical_id(connector_id, 2) or connector_ids.has(connector_id) or (index > 0 and connector_id <= previous):
			return Utils.failure("FABRIC1_CONNECTOR_ID_INVALID")
		previous = connector_id
		connector_ids[connector_id] = true
		var a := String(connector.get("port_a", ""))
		var b := String(connector.get("port_b", ""))
		if a == b or not all_ports.has(a) or not all_ports.has(b):
			return Utils.failure("FABRIC1_CONNECTOR_PORT_INVALID", {"connector_id": connector_id})
		if String(all_ports[a]) == String(all_ports[b]):
			return Utils.failure("FABRIC1_CONNECTOR_MUST_CROSS_COMPONENTS", {"connector_id": connector_id})
		if connected_ports.has(a) or connected_ports.has(b):
			return Utils.failure("FABRIC1_CONNECTOR_PORT_ALREADY_BOUND", {"connector_id": connector_id})
		if not Utils.is_positive_number(connector.get("conductance")) or typeof(connector.get("active")) != TYPE_BOOL:
			return Utils.failure("FABRIC1_CONNECTOR_PHYSICS_INVALID", {"connector_id": connector_id})
		connected_ports[a] = true
		connected_ports[b] = true
		final_edges.append({
			"edge_id": connector_id,
			"node_a": a,
			"node_b": b,
			"conductance": float(connector["conductance"]),
			"active": bool(connector["active"]),
		})

	var boundary_nodes: Array = []
	var internal_nodes: Array = []
	for node_id in all_nodes.keys():
		if all_ports.has(node_id) and not connected_ports.has(node_id):
			boundary_nodes.append(String(node_id))
		else:
			internal_nodes.append(String(node_id))
	boundary_nodes.sort()
	internal_nodes.sort()
	var spec := Graph.create(machine_id, revision, boundary_nodes, internal_nodes, final_edges, applied_event_ids)
	if spec.is_empty():
		return Utils.failure("FABRIC1_COMPOSED_GRAPH_INVALID")
	component_hashes.sort()
	return Utils.success({
		"spec": spec,
		"component_count": ordered_components.size(),
		"connector_count": ordered_connectors.size(),
		"component_hashes": component_hashes,
		"composition_hash": Utils.canonical_hash({
			"machine_id": machine_id,
			"revision": revision,
			"component_hashes": component_hashes,
			"connector_ids": connector_ids.keys().duplicate(),
			"graph_hash": spec["graph_hash"],
		}),
	})

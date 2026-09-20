extends RefCounted
## Device-agnostic linear conductance component graph for R5.2 T1.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_linear_conductance_component_graph.v1"
const FIELDS: Array[String] = [
	"schema", "graph_id", "nodes", "boundary_ports", "components", "graph_hash", "checksum",
]
const PORT_FIELDS: Array[String] = ["port_id", "node_id"]
const COMPONENT_FIELDS: Array[String] = [
	"component_id", "law_kind", "node_a", "node_b", "conductance", "material_tag",
]
const LAW_KIND := "LINEAR_CONDUCTANCE"

static func create(graph_id: String, nodes: Array, boundary_ports: Array, components: Array) -> Dictionary:
	var ordered_nodes := U.sorted_strings(nodes)
	var ordered_ports := U.sorted_dicts(boundary_ports, "port_id")
	var ordered_components := U.sorted_dicts(components, "component_id")
	var identity := {
		"graph_id": graph_id,
		"nodes": ordered_nodes,
		"boundary_ports": ordered_ports,
		"components": ordered_components,
	}
	var value := {
		"schema": SCHEMA,
		"graph_id": graph_id,
		"nodes": ordered_nodes,
		"boundary_ports": ordered_ports,
		"components": ordered_components,
		"graph_hash": U.canonical_hash(identity),
		"checksum": "",
	}
	value.checksum = U.compute_checksum(value)
	return value if validate(value).success else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := U.validate_exact_fields(value, FIELDS)
	if not checked.success:
		return checked
	if value.get("schema") != SCHEMA:
		return U.failure("UNSUPPORTED_LINEAR_CONDUCTANCE_GRAPH_SCHEMA")
	if not U.is_canonical_id(value.get("graph_id"), 2):
		return U.failure("INVALID_LINEAR_CONDUCTANCE_GRAPH_ID")
	checked = U.validate_sorted_unique_strings(value.get("nodes"), false)
	if not checked.success:
		return U.failure("INVALID_LINEAR_CONDUCTANCE_NODES")
	for node_id in value.nodes:
		if not U.is_canonical_id(node_id, 2):
			return U.failure("INVALID_LINEAR_CONDUCTANCE_NODE_ID")
	if typeof(value.get("boundary_ports")) != TYPE_ARRAY or value.boundary_ports.size() < 2 or value.boundary_ports.size() > 8:
		return U.failure("INVALID_LINEAR_CONDUCTANCE_BOUNDARY_PORTS")
	var boundary_nodes := {}
	var previous_port := ""
	for index in range(value.boundary_ports.size()):
		var port = value.boundary_ports[index]
		if typeof(port) != TYPE_DICTIONARY:
			return U.failure("INVALID_LINEAR_CONDUCTANCE_BOUNDARY_PORT", {"index": index})
		checked = U.validate_exact_fields(port, PORT_FIELDS)
		if not checked.success:
			return checked
		if not U.is_canonical_id(port.port_id, 2) or not U.is_canonical_id(port.node_id, 2):
			return U.failure("INVALID_LINEAR_CONDUCTANCE_BOUNDARY_PORT_ID", {"index": index})
		if not value.nodes.has(port.node_id):
			return U.failure("LINEAR_CONDUCTANCE_BOUNDARY_NODE_MISSING", {"index": index})
		if boundary_nodes.has(port.node_id):
			return U.failure("LINEAR_CONDUCTANCE_BOUNDARY_NODE_DUPLICATE", {"node_id": port.node_id})
		boundary_nodes[port.node_id] = true
		if index > 0 and String(port.port_id) <= previous_port:
			return U.failure("LINEAR_CONDUCTANCE_BOUNDARY_PORTS_NOT_SORTED")
		previous_port = String(port.port_id)
	if typeof(value.get("components")) != TYPE_ARRAY or value.components.is_empty():
		return U.failure("INVALID_LINEAR_CONDUCTANCE_COMPONENTS")
	var previous_component := ""
	for index in range(value.components.size()):
		var component = value.components[index]
		if typeof(component) != TYPE_DICTIONARY:
			return U.failure("INVALID_LINEAR_CONDUCTANCE_COMPONENT", {"index": index})
		checked = U.validate_exact_fields(component, COMPONENT_FIELDS)
		if not checked.success:
			return checked
		if not U.is_canonical_id(component.component_id, 2):
			return U.failure("INVALID_LINEAR_CONDUCTANCE_COMPONENT_ID", {"index": index})
		if String(component.law_kind) != LAW_KIND:
			return U.failure("UNSUPPORTED_LINEAR_CONDUCTANCE_LAW", {"index": index})
		if not value.nodes.has(component.node_a) or not value.nodes.has(component.node_b) or component.node_a == component.node_b:
			return U.failure("INVALID_LINEAR_CONDUCTANCE_COMPONENT_NODES", {"index": index})
		if not U.is_positive_number(component.conductance):
			return U.failure("INVALID_LINEAR_CONDUCTANCE_VALUE", {"index": index})
		if not U.is_canonical_id(component.material_tag, 2):
			return U.failure("INVALID_LINEAR_CONDUCTANCE_MATERIAL_TAG", {"index": index})
		if index > 0 and String(component.component_id) <= previous_component:
			return U.failure("LINEAR_CONDUCTANCE_COMPONENTS_NOT_SORTED")
		previous_component = String(component.component_id)
	if not U.is_lower_hex_64(value.get("graph_hash")):
		return U.failure("INVALID_LINEAR_CONDUCTANCE_GRAPH_HASH")
	var identity := {
		"graph_id": value.graph_id,
		"nodes": value.nodes,
		"boundary_ports": value.boundary_ports,
		"components": value.components,
	}
	if String(value.graph_hash) != U.canonical_hash(identity):
		return U.failure("LINEAR_CONDUCTANCE_GRAPH_HASH_MISMATCH")
	return U.validate_checksum(value)

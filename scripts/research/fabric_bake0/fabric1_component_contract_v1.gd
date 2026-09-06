extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric1_component_graph.v1"
const FIELDS: Array[String] = [
	"schema", "component_id", "port_node_ids", "internal_node_ids", "edges",
	"component_hash", "checksum",
]
const EDGE_FIELDS: Array[String] = ["edge_id", "node_a", "node_b", "conductance", "active"]

static func create(component_id: String, port_node_ids: Array, internal_node_ids: Array, edges: Array) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"component_id": component_id,
		"port_node_ids": Utils.sorted_strings(port_node_ids),
		"internal_node_ids": Utils.sorted_strings(internal_node_ids),
		"edges": Utils.sorted_dicts(edges, "edge_id"),
		"component_hash": "",
		"checksum": "",
	}
	value["component_hash"] = Utils.canonical_hash(_identity(value))
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("FABRIC1_UNSUPPORTED_COMPONENT_SCHEMA")
	if not Utils.is_canonical_id(value.get("component_id"), 2):
		return Utils.failure("FABRIC1_INVALID_COMPONENT_ID")
	checked = Utils.validate_sorted_unique_strings(value.get("port_node_ids"), false)
	if not bool(checked.get("success", false)):
		return Utils.failure("FABRIC1_INVALID_COMPONENT_PORTS")
	checked = Utils.validate_sorted_unique_strings(value.get("internal_node_ids"), false)
	if not bool(checked.get("success", false)):
		return Utils.failure("FABRIC1_INVALID_COMPONENT_INTERNALS")
	if value["port_node_ids"].size() < 2:
		return Utils.failure("FABRIC1_COMPONENT_REQUIRES_TWO_PORTS")
	if value["internal_node_ids"].size() < 8:
		return Utils.failure("FABRIC1_COMPONENT_TOO_SMALL")
	var nodes := {}
	for port_id in value["port_node_ids"]:
		if not Utils.is_canonical_id(port_id, 2) or nodes.has(String(port_id)):
			return Utils.failure("FABRIC1_INVALID_COMPONENT_PORT_NODE")
		nodes[String(port_id)] = true
	for node_id in value["internal_node_ids"]:
		if not Utils.is_canonical_id(node_id, 2) or nodes.has(String(node_id)):
			return Utils.failure("FABRIC1_COMPONENT_NODE_OVERLAP")
		nodes[String(node_id)] = true
	if typeof(value.get("edges")) != TYPE_ARRAY or value["edges"].is_empty():
		return Utils.failure("FABRIC1_COMPONENT_EDGES_REQUIRED")
	var previous := ""
	for index in range(value["edges"].size()):
		var raw = value["edges"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("FABRIC1_INVALID_COMPONENT_EDGE", {"index": index})
		var edge: Dictionary = raw
		checked = Utils.validate_exact_fields(edge, EDGE_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		var edge_id := String(edge.get("edge_id", ""))
		if not Utils.is_canonical_id(edge_id, 2) or (index > 0 and edge_id <= previous):
			return Utils.failure("FABRIC1_COMPONENT_EDGES_NOT_SORTED_UNIQUE")
		previous = edge_id
		var a := String(edge.get("node_a", ""))
		var b := String(edge.get("node_b", ""))
		if a == b or not nodes.has(a) or not nodes.has(b):
			return Utils.failure("FABRIC1_COMPONENT_EDGE_ENDPOINT_INVALID", {"edge_id": edge_id})
		if not Utils.is_positive_number(edge.get("conductance")):
			return Utils.failure("FABRIC1_COMPONENT_CONDUCTANCE_INVALID", {"edge_id": edge_id})
		if typeof(edge.get("active")) != TYPE_BOOL:
			return Utils.failure("FABRIC1_COMPONENT_EDGE_ACTIVE_INVALID", {"edge_id": edge_id})
	if not Utils.is_lower_hex_64(value.get("component_hash")) or String(value["component_hash"]) != Utils.canonical_hash(_identity(value)):
		return Utils.failure("FABRIC1_COMPONENT_HASH_MISMATCH")
	return Utils.validate_checksum(value)

static func _identity(value: Dictionary) -> Dictionary:
	return {
		"component_id": value["component_id"],
		"port_node_ids": value["port_node_ids"],
		"internal_node_ids": value["internal_node_ids"],
		"edges": value["edges"],
	}

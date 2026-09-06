extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const LinearSystem = preload("res://scripts/research/fabric_bake0/linear_boundary_system_v1.gd")

const SCHEMA := "planet_simulator.fabric_b0_7_generic_power_graph.v1"
const FIELDS: Array[String] = [
	"schema", "machine_id", "revision", "boundary_node_ids", "internal_node_ids",
	"edges", "applied_event_ids", "graph_hash", "checksum",
]
const EDGE_FIELDS: Array[String] = ["edge_id", "node_a", "node_b", "conductance", "active"]

static func create(
	machine_id: String,
	revision: int,
	boundary_node_ids: Array,
	internal_node_ids: Array,
	edges: Array,
	applied_event_ids: Array = []
) -> Dictionary:
	var boundaries := Utils.sorted_strings(boundary_node_ids)
	var internals := Utils.sorted_strings(internal_node_ids)
	var ordered_edges := Utils.sorted_dicts(edges, "edge_id")
	var events := Utils.sorted_strings(applied_event_ids)
	var value: Dictionary = {
		"schema": SCHEMA,
		"machine_id": machine_id,
		"revision": revision,
		"boundary_node_ids": boundaries,
		"internal_node_ids": internals,
		"edges": ordered_edges,
		"applied_event_ids": events,
		"graph_hash": "",
		"checksum": "",
	}
	value["graph_hash"] = Utils.canonical_hash(_identity_payload(value))
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_B0_7_GENERIC_GRAPH_SCHEMA")
	if not Utils.is_canonical_id(value.get("machine_id"), 2):
		return Utils.failure("INVALID_B0_7_MACHINE_ID")
	if not Utils.is_json_integer(value.get("revision")) or int(value["revision"]) < 1:
		return Utils.failure("INVALID_B0_7_MACHINE_REVISION")
	checked = Utils.validate_sorted_unique_strings(value.get("boundary_node_ids"), false)
	if not bool(checked.get("success", false)):
		return Utils.failure("INVALID_B0_7_BOUNDARY_NODE_IDS")
	checked = Utils.validate_sorted_unique_strings(value.get("internal_node_ids"), false)
	if not bool(checked.get("success", false)):
		return Utils.failure("INVALID_B0_7_INTERNAL_NODE_IDS")
	if value["boundary_node_ids"].size() < 2 or value["boundary_node_ids"].size() > 8:
		return Utils.failure("B0_7_BOUNDARY_COUNT_OUT_OF_SCOPE")
	if value["internal_node_ids"].size() < 100:
		return Utils.failure("B0_7_INTERNAL_COUNT_BELOW_REDUCTION_SCOPE")
	var all_nodes := {}
	for node_id in value["boundary_node_ids"]:
		if not Utils.is_canonical_id(node_id, 2):
			return Utils.failure("INVALID_B0_7_BOUNDARY_NODE_ID")
		all_nodes[String(node_id)] = "BOUNDARY"
	for node_id in value["internal_node_ids"]:
		if not Utils.is_canonical_id(node_id, 2):
			return Utils.failure("INVALID_B0_7_INTERNAL_NODE_ID")
		if all_nodes.has(String(node_id)):
			return Utils.failure("B0_7_BOUNDARY_INTERNAL_NODE_OVERLAP")
		all_nodes[String(node_id)] = "INTERNAL"
	if typeof(value.get("edges")) != TYPE_ARRAY or value["edges"].is_empty():
		return Utils.failure("INVALID_B0_7_EDGE_SET")
	var previous := ""
	for index in range(value["edges"].size()):
		var raw = value["edges"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_B0_7_EDGE_RECORD", {"index": index})
		var edge: Dictionary = raw
		checked = Utils.validate_exact_fields(edge, EDGE_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		if not Utils.is_canonical_id(edge.get("edge_id"), 2):
			return Utils.failure("INVALID_B0_7_EDGE_ID", {"index": index})
		var edge_id := String(edge["edge_id"])
		if index > 0 and edge_id <= previous:
			return Utils.failure("B0_7_EDGES_NOT_SORTED_UNIQUE")
		previous = edge_id
		var a := String(edge.get("node_a", ""))
		var b := String(edge.get("node_b", ""))
		if a == b or not all_nodes.has(a) or not all_nodes.has(b):
			return Utils.failure("INVALID_B0_7_EDGE_ENDPOINT", {"edge_id": edge_id})
		if not Utils.is_positive_number(edge.get("conductance")):
			return Utils.failure("INVALID_B0_7_EDGE_CONDUCTANCE", {"edge_id": edge_id})
		if typeof(edge.get("active")) != TYPE_BOOL:
			return Utils.failure("INVALID_B0_7_EDGE_ACTIVE", {"edge_id": edge_id})
	checked = Utils.validate_sorted_unique_strings(value.get("applied_event_ids"), true)
	if not bool(checked.get("success", false)):
		return Utils.failure("INVALID_B0_7_EVENT_LEDGER")
	for event_id in value["applied_event_ids"]:
		if not Utils.is_canonical_id(event_id, 2):
			return Utils.failure("INVALID_B0_7_EVENT_ID")
	if not Utils.is_lower_hex_64(value.get("graph_hash")):
		return Utils.failure("INVALID_B0_7_GRAPH_HASH")
	if String(value["graph_hash"]) != Utils.canonical_hash(_identity_payload(value)):
		return Utils.failure("B0_7_GRAPH_HASH_MISMATCH")
	return Utils.validate_checksum(value)

static func to_linear_system(value: Dictionary) -> Dictionary:
	var checked := validate(value)
	if not bool(checked.get("success", false)):
		return {}
	var boundary_count: int = int(value["boundary_node_ids"].size())
	var internal_count: int = int(value["internal_node_ids"].size())
	var node_ids: Array = value["boundary_node_ids"].duplicate()
	node_ids.append_array(value["internal_node_ids"])
	var index_by_id := {}
	for index in range(node_ids.size()):
		index_by_id[String(node_ids[index])] = index
	var matrix: Array = []
	for _row in range(node_ids.size()):
		var row: Array = []
		row.resize(node_ids.size())
		row.fill(0.0)
		matrix.append(row)
	for edge in value["edges"]:
		if not bool(edge["active"]):
			continue
		var a := int(index_by_id[String(edge["node_a"])])
		var b := int(index_by_id[String(edge["node_b"])])
		var g := float(edge["conductance"])
		matrix[a][a] = float(matrix[a][a]) + g
		matrix[b][b] = float(matrix[b][b]) + g
		matrix[a][b] = float(matrix[a][b]) - g
		matrix[b][a] = float(matrix[b][a]) - g
	var rhs: Array = []
	rhs.resize(boundary_count + internal_count)
	rhs.fill(0.0)
	return LinearSystem.create(
		"system/b0-7-%s-r%03d" % [_slug(String(value["machine_id"])), int(value["revision"])],
		value["boundary_node_ids"], value["internal_node_ids"], matrix, rhs
	)

static func active_edge_ids(value: Dictionary) -> Array:
	var result: Array = []
	for edge in value.get("edges", []):
		if bool(edge.get("active", false)):
			result.append(String(edge.get("edge_id", "")))
	result.sort()
	return result

static func edge_by_id(value: Dictionary, edge_id: String) -> Dictionary:
	for edge in value.get("edges", []):
		if String(edge.get("edge_id", "")) == edge_id:
			return Dictionary(edge).duplicate(true)
	return {}

static func _identity_payload(value: Dictionary) -> Dictionary:
	return {
		"machine_id": value["machine_id"],
		"revision": value["revision"],
		"boundary_node_ids": value["boundary_node_ids"],
		"internal_node_ids": value["internal_node_ids"],
		"edges": value["edges"],
		"applied_event_ids": value["applied_event_ids"],
	}

static func _slug(machine_id: String) -> String:
	return machine_id.replace("/", "-").replace("_", "-").to_lower()

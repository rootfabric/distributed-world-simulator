extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ContractUtils = preload("res://scripts/construction/utilities/construction_utility_contract_utils.gd")
const NodeScript = preload("res://scripts/construction/utilities/construction_utility_node_definition.gd")
const LinkScript = preload("res://scripts/construction/utilities/construction_utility_link_definition.gd")
const SCHEMA := "planet_simulator.construction_utility_network_definition.v1"
const FIELDS: Array[String] = ["schema", "network_id", "utility_kind", "unit", "construct_id", "construct_revision", "construct_checksum", "nodes", "links", "properties", "checksum"]

static func create(network_id: String, utility_kind: String, construct_id: String, construct_revision: int, construct_checksum: String, nodes: Array, links: Array, properties: Dictionary = {}) -> Dictionary:
	var sorted_nodes := nodes.duplicate(true); sorted_nodes.sort_custom(func(a,b): return String(a.get("node_id", "")) < String(b.get("node_id", "")))
	var sorted_links := links.duplicate(true); sorted_links.sort_custom(func(a,b): return String(a.get("link_id", "")) < String(b.get("link_id", "")))
	var value := {"schema": SCHEMA, "network_id": network_id, "utility_kind": utility_kind, "unit": String(ContractUtils.VALID_UNITS.get(utility_kind, "")), "construct_id": construct_id, "construct_revision": construct_revision, "construct_checksum": construct_checksum, "nodes": sorted_nodes, "links": sorted_links, "properties": properties.duplicate(true), "checksum": ""}
	value["checksum"] = compute_checksum(value); return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return ContractUtils.failure("UNSUPPORTED_CONSTRUCTION_UTILITY_NETWORK_SCHEMA")
	var network_id := String(value.get("network_id", "")); var kind := String(value.get("utility_kind", ""))
	if not ContractUtils.is_path(network_id, "utility-network/"): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_NETWORK_ID")
	if not ContractUtils.VALID_KINDS.has(kind) or String(value.get("unit", "")) != String(ContractUtils.VALID_UNITS.get(kind, "")): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_NETWORK_KIND_OR_UNIT")
	if not ContractUtils.is_path(String(value.get("construct_id", "")), "construct/"): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_NETWORK_CONSTRUCT")
	if not UtilsScript.is_json_integer(value.get("construct_revision")) or int(value["construct_revision"]) < 0 or String(value.get("construct_checksum", "")).length() != 64: return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_NETWORK_SOURCE")
	if typeof(value.get("nodes")) != TYPE_ARRAY or Array(value["nodes"]).is_empty() or typeof(value.get("links")) != TYPE_ARRAY: return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_NETWORK_COLLECTIONS")
	var nodes := {}; var previous := ""; var source_count := 0; var consumer_count := 0
	for raw in value["nodes"]:
		if typeof(raw) != TYPE_DICTIONARY: return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_NETWORK_NODE")
		var checked := NodeScript.validate(raw); if not bool(checked.get("success", false)): return checked
		var node_id := String(raw["node_id"])
		if String(raw["network_id"]) != network_id or String(raw["utility_kind"]) != kind or nodes.has(node_id) or (not previous.is_empty() and node_id < previous): return ContractUtils.failure("NON_CANONICAL_CONSTRUCTION_UTILITY_NETWORK_NODES")
		nodes[node_id] = raw; previous = node_id
		if String(raw["node_kind"]) == "SOURCE": source_count += 1
		if String(raw["node_kind"]) == "CONSUMER": consumer_count += 1
	if source_count == 0 and not _has_storage(value["nodes"]): return ContractUtils.failure("CONSTRUCTION_UTILITY_NETWORK_SUPPLY_REQUIRED")
	if consumer_count == 0: return ContractUtils.failure("CONSTRUCTION_UTILITY_NETWORK_CONSUMER_REQUIRED")
	previous = ""; var seen_links := {}
	for raw in value["links"]:
		if typeof(raw) != TYPE_DICTIONARY: return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_NETWORK_LINK")
		var checked := LinkScript.validate(raw); if not bool(checked.get("success", false)): return checked
		var link_id := String(raw["link_id"])
		if String(raw["network_id"]) != network_id or String(raw["utility_kind"]) != kind or not nodes.has(String(raw["node_a_id"])) or not nodes.has(String(raw["node_b_id"])) or seen_links.has(link_id) or (not previous.is_empty() and link_id < previous): return ContractUtils.failure("NON_CANONICAL_CONSTRUCTION_UTILITY_NETWORK_LINKS")
		seen_links[link_id] = true; previous = link_id
	if typeof(value.get("properties")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value["properties"]).get("success", false)): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_NETWORK_PROPERTIES")
	if String(value.get("checksum", "")) != compute_checksum(value): return ContractUtils.failure("CONSTRUCTION_UTILITY_NETWORK_CHECKSUM_MISMATCH")
	return ContractUtils.success()

static func _has_storage(nodes: Array) -> bool:
	for node in nodes:
		if String(node.get("node_kind", "")) == "STORAGE": return true
	return false
static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)

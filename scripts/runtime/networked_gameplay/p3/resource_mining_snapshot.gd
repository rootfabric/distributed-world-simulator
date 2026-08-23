extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA := "planet_simulator.resource_mining_snapshot.v1"


static func create(
	authority_owner_id: String,
	authority_epoch: int,
	generation: int,
	nodes: Array
) -> Dictionary:
	var body: Dictionary = {
		"schema": SCHEMA,
		"authority_owner_id": authority_owner_id,
		"authority_epoch": authority_epoch,
		"generation": generation,
		"nodes": _sorted_nodes(nodes),
	}
	body["checksum"] = Utils.payload_hash(body)
	return body


static func validate(value: Dictionary) -> Dictionary:
	for field in ["schema", "authority_owner_id", "authority_epoch", "generation", "nodes", "checksum"]:
		if not value.has(field):
			return _failure("RESOURCE_SNAPSHOT_FIELD_MISSING", {"field": field})
	if String(value.get("schema", "")) != SCHEMA:
		return _failure("INVALID_RESOURCE_SNAPSHOT_SCHEMA")
	if String(value.get("authority_owner_id", "")).strip_edges().is_empty():
		return _failure("INVALID_RESOURCE_SNAPSHOT_AUTHORITY")
	if int(value.get("authority_epoch", 0)) < 1 or int(value.get("generation", -1)) < 0:
		return _failure("INVALID_RESOURCE_SNAPSHOT_GENERATION")
	if typeof(value.get("nodes")) != TYPE_ARRAY or typeof(value.get("checksum")) != TYPE_STRING:
		return _failure("INVALID_RESOURCE_SNAPSHOT_SHAPE")
	var expected_checksum := _checksum(value)
	if String(value.get("checksum", "")) != expected_checksum:
		return _failure("RESOURCE_SNAPSHOT_CHECKSUM_MISMATCH")
	var seen: Dictionary = {}
	for node_value in value.get("nodes", []):
		if not node_value is Dictionary:
			return _failure("INVALID_RESOURCE_NODE_RECORD")
		var node: Dictionary = node_value
		var node_id := String(node.get("resource_node_id", ""))
		var spatial_value = node.get("spatial", {})
		if (
			node_id.is_empty()
			or node_id != node_id.strip_edges().to_lower()
			or seen.has(node_id)
			or String(node.get("resource_definition_id", "")).is_empty()
			or String(node.get("output_definition_id", "")).is_empty()
			or int(node.get("remaining_units", -1)) < 0
			or int(node.get("unit_item_quantity", 0)) < 1
			or not spatial_value is Dictionary
		):
			return _failure("INVALID_RESOURCE_NODE_RECORD")
		var spatial: Dictionary = spatial_value
		if (
			String(spatial.get("frame", "")) != "earth-fixed"
			or not _is_number(spatial.get("latitude_deg"))
			or not _is_number(spatial.get("longitude_deg"))
			or not _is_number(spatial.get("altitude_m"))
		):
			return _failure("INVALID_RESOURCE_NODE_SPATIAL")
		seen[node_id] = true
	var safe := Utils.canonicalize(value, "$.resource_mining_snapshot")
	if not bool(safe.get("success", false)):
		return _failure("RESOURCE_SNAPSHOT_NOT_JSON_SAFE")
	return _success({"node_count": seen.size()})


static func _sorted_nodes(values: Array) -> Array:
	var by_id: Dictionary = {}
	for value in values:
		if value is Dictionary:
			var node: Dictionary = value
			by_id[String(node.get("resource_node_id", ""))] = node.duplicate(true)
	var ids := by_id.keys()
	ids.sort()
	var result: Array = []
	for node_id in ids:
		result.append(Dictionary(by_id[node_id]).duplicate(true))
	return result


static func _checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload.erase("checksum")
	return Utils.payload_hash(payload)


static func _is_number(value) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}

extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ResourceSnapshot = preload(
	"res://scripts/runtime/networked_gameplay/p3/resource_mining_snapshot.gd"
)

const SCHEMA := "planet_simulator.resource_mining_delta.v1"


static func create(before: Dictionary, after: Dictionary) -> Dictionary:
	var before_validation := ResourceSnapshot.validate(before)
	if not bool(before_validation.get("success", false)):
		return _failure("INVALID_RESOURCE_DELTA_BASE", {"cause": before_validation})
	var after_validation := ResourceSnapshot.validate(after)
	if not bool(after_validation.get("success", false)):
		return _failure("INVALID_RESOURCE_DELTA_TARGET", {"cause": after_validation})
	if (
		String(before.get("authority_owner_id", "")) != String(after.get("authority_owner_id", ""))
		or int(before.get("authority_epoch", 0)) != int(after.get("authority_epoch", 0))
	):
		return _failure("RESOURCE_DELTA_AUTHORITY_MISMATCH")
	var base_generation := int(before.get("generation", -1))
	var generation := int(after.get("generation", -1))
	if generation != base_generation + 1:
		return _failure("RESOURCE_DELTA_GENERATION_STEP_INVALID")
	var before_nodes := _nodes_by_id(before)
	var changed_nodes: Array = []
	for node_value in after.get("nodes", []):
		if not node_value is Dictionary:
			continue
		var node: Dictionary = node_value
		var node_id := String(node.get("resource_node_id", ""))
		if not before_nodes.has(node_id) or Dictionary(before_nodes[node_id]) != node:
			changed_nodes.append(node.duplicate(true))
	if changed_nodes.is_empty():
		return _failure("RESOURCE_DELTA_WITHOUT_CHANGE")
	var body: Dictionary = {
		"schema": SCHEMA,
		"authority_owner_id": String(after.get("authority_owner_id", "")),
		"authority_epoch": int(after.get("authority_epoch", 0)),
		"base_generation": base_generation,
		"generation": generation,
		"changed_nodes": changed_nodes,
		"target_checksum": String(after.get("checksum", "")),
	}
	body["checksum"] = Utils.payload_hash(body)
	return _success({"delta": body})


static func validate(value: Dictionary) -> Dictionary:
	for field in [
		"schema", "authority_owner_id", "authority_epoch", "base_generation",
		"generation", "changed_nodes", "target_checksum", "checksum",
	]:
		if not value.has(field):
			return _failure("RESOURCE_DELTA_FIELD_MISSING", {"field": field})
	if String(value.get("schema", "")) != SCHEMA:
		return _failure("INVALID_RESOURCE_DELTA_SCHEMA")
	if String(value.get("authority_owner_id", "")).strip_edges().is_empty() or int(value.get("authority_epoch", 0)) < 1:
		return _failure("INVALID_RESOURCE_DELTA_AUTHORITY")
	if int(value.get("generation", -1)) != int(value.get("base_generation", -1)) + 1:
		return _failure("RESOURCE_DELTA_GENERATION_STEP_INVALID")
	if typeof(value.get("changed_nodes")) != TYPE_ARRAY or Array(value.get("changed_nodes", [])).is_empty():
		return _failure("INVALID_RESOURCE_DELTA_NODES")
	if String(value.get("target_checksum", "")).length() != 64 or String(value.get("checksum", "")) != _checksum(value):
		return _failure("RESOURCE_DELTA_CHECKSUM_MISMATCH")
	var seen: Dictionary = {}
	for node_value in value.get("changed_nodes", []):
		if not node_value is Dictionary:
			return _failure("INVALID_RESOURCE_DELTA_NODE")
		var node: Dictionary = node_value
		var node_id := String(node.get("resource_node_id", ""))
		if node_id.is_empty() or seen.has(node_id):
			return _failure("INVALID_RESOURCE_DELTA_NODE")
		var probe := ResourceSnapshot.create(
			String(value.get("authority_owner_id", "")),
			int(value.get("authority_epoch", 0)),
			int(value.get("generation", 0)),
			[node]
		)
		if not bool(ResourceSnapshot.validate(probe).get("success", false)):
			return _failure("INVALID_RESOURCE_DELTA_NODE")
		seen[node_id] = true
	return _success({"changed_node_count": seen.size()})


static func apply(base: Dictionary, delta: Dictionary) -> Dictionary:
	var base_validation := ResourceSnapshot.validate(base)
	if not bool(base_validation.get("success", false)):
		return _failure("INVALID_RESOURCE_DELTA_BASE", {"cause": base_validation})
	var delta_validation := validate(delta)
	if not bool(delta_validation.get("success", false)):
		return delta_validation
	if (
		String(base.get("authority_owner_id", "")) != String(delta.get("authority_owner_id", ""))
		or int(base.get("authority_epoch", 0)) != int(delta.get("authority_epoch", 0))
	):
		return _failure("RESOURCE_DELTA_AUTHORITY_MISMATCH")
	if int(base.get("generation", -1)) != int(delta.get("base_generation", -2)):
		return _failure("RESOURCE_DELTA_BASE_MISMATCH")
	var by_id := _nodes_by_id(base)
	for node_value in delta.get("changed_nodes", []):
		var node: Dictionary = Dictionary(node_value).duplicate(true)
		by_id[String(node.get("resource_node_id", ""))] = node
	var values: Array = []
	for node_value in by_id.values():
		values.append(Dictionary(node_value).duplicate(true))
	var target := ResourceSnapshot.create(
		String(delta.get("authority_owner_id", "")),
		int(delta.get("authority_epoch", 0)),
		int(delta.get("generation", 0)),
		values
	)
	if String(target.get("checksum", "")) != String(delta.get("target_checksum", "")):
		return _failure("RESOURCE_DELTA_TARGET_CHECKSUM_MISMATCH")
	return _success({"snapshot": target})


static func _nodes_by_id(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for node_value in snapshot.get("nodes", []):
		if node_value is Dictionary:
			var node: Dictionary = node_value
			result[String(node.get("resource_node_id", ""))] = node.duplicate(true)
	return result


static func _checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload.erase("checksum")
	return Utils.payload_hash(payload)


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}

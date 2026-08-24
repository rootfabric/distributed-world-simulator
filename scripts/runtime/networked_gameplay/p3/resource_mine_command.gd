extends RefCounted

const SCHEMA := "planet_simulator.resource_mine_command.v1"
const COMMAND_TYPE := "resource.mine"


static func validate_payload(payload: Dictionary) -> Dictionary:
	if payload.size() != 2 or not payload.has("resource_node_id") or not payload.has("requested_units"):
		return _failure("INVALID_RESOURCE_COMMAND")
	if typeof(payload.get("resource_node_id")) != TYPE_STRING:
		return _failure("INVALID_RESOURCE_COMMAND")
	if typeof(payload.get("requested_units")) != TYPE_INT:
		return _failure("INVALID_MINING_QUANTITY")
	var node_id := String(payload.get("resource_node_id", "")).strip_edges()
	if node_id.is_empty() or node_id != node_id.to_lower():
		return _failure("INVALID_RESOURCE_COMMAND")
	return _success()


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": {}}

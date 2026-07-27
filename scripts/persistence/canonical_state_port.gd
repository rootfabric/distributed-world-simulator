extends RefCounted

const SCHEMA: String = "planet_simulator.canonical_state_port.v1"
const MAX_SAFE_JSON_INTEGER: int = 9007199254740991


func save_state(_state_key: String, _state: Dictionary) -> Dictionary:
	return _failure("NOT_IMPLEMENTED")


func load_state(_state_key: String) -> Dictionary:
	return _failure("NOT_IMPLEMENTED")


func delete_state(_state_key: String) -> Dictionary:
	return _failure("NOT_IMPLEMENTED")


func has_state(_state_key: String) -> bool:
	return false


func validate_payload(value) -> Dictionary:
	return {"success": true} if _is_json_safe(value) else _failure("NON_CANONICAL_STATE_PAYLOAD")


func create_port_snapshot(port_id: String = "canonical-state") -> Dictionary:
	return {
		"schema": SCHEMA,
		"port_id": port_id,
		"server_safe": true,
		"node_backed": false,
	}


func _success(extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true}
	result.merge(extra, true)
	return result


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"details": details.duplicate(true),
	}


func _is_json_safe(value) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return true
		TYPE_INT:
			return abs(int(value)) <= MAX_SAFE_JSON_INTEGER
		TYPE_FLOAT:
			return is_finite(float(value)) and absf(float(value)) <= float(MAX_SAFE_JSON_INTEGER)
		TYPE_ARRAY:
			for child in value:
				if not _is_json_safe(child):
					return false
			return true
		TYPE_DICTIONARY:
			for key in value.keys():
				if typeof(key) != TYPE_STRING or not _is_json_safe(value[key]):
					return false
			return true
	return false

extends RefCounted


func save_state(_state_key: String, _state: Dictionary) -> Dictionary:
	return _failure("NOT_IMPLEMENTED")


func load_state(_state_key: String) -> Dictionary:
	return _failure("NOT_IMPLEMENTED")


func delete_state(_state_key: String) -> Dictionary:
	return _failure("NOT_IMPLEMENTED")


func has_state(_state_key: String) -> bool:
	return false


func _success(extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true}
	for key in extra.keys():
		result[key] = extra[key]
	return result


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"details": details.duplicate(true),
	}

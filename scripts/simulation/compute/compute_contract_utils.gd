extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")


static func is_identifier(value: String, prefix: String = "") -> bool:
	if value.is_empty() or value != value.strip_edges() or value.length() > 256:
		return false
	if not prefix.is_empty() and not value.begins_with(prefix):
		return false
	for character in value:
		if not String(character) in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._:/":
			return false
	return true


static func is_upper_kind(value: String) -> bool:
	if value.is_empty() or value != value.to_upper():
		return false
	for character in value:
		if not String(character) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_":
			return false
	return true


static func is_versioned_schema(value: String) -> bool:
	return is_identifier(value) and value.contains(".") and value.get_slice(".", value.get_slice_count(".") - 1).begins_with("v")


static func is_lower_hex_64(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for character in value:
		if not String(character) in "0123456789abcdef":
			return false
	return true


static func is_state_path(path: String) -> bool:
	if path.is_empty() or path != path.strip_edges() or path.begins_with(".") or path.ends_with("."):
		return false
	for segment in path.split(".", true):
		if segment.is_empty() or segment != segment.strip_edges():
			return false
		for character in segment:
			if not String(character) in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_/:":
				return false
	return true


static func paths_overlap(first: String, second: String) -> bool:
	return first == second or first.begins_with(second + ".") or second.begins_with(first + ".")


static func canonical_copy(value) -> Dictionary:
	var round_trip: Dictionary = NetworkUtilsScript.json_round_trip(value)
	if not bool(round_trip.get("success", false)):
		return failure("NON_CANONICAL_COMPUTE_VALUE")
	return success({"value": round_trip.get("value")})


static func serialized_size(value) -> int:
	var encoded: String = NetworkUtilsScript.canonical_json(value)
	if encoded.is_empty():
		return -1
	return encoded.to_utf8_buffer().size()


static func read_state_path(source: Dictionary, path: String) -> Dictionary:
	var current = source
	for segment in path.split(".", true):
		if typeof(current) != TYPE_DICTIONARY or not current.has(segment):
			return failure("COMPUTE_PATH_NOT_FOUND", {"path": path})
		current = current[segment]
	var copied := canonical_copy(current)
	if not bool(copied.get("success", false)):
		return copied
	return success({"value": copied["details"]["value"]})


static func write_state_path(target: Dictionary, path: String, value) -> Dictionary:
	if not is_state_path(path):
		return failure("INVALID_COMPUTE_STATE_PATH")
	var copied := canonical_copy(value)
	if not bool(copied.get("success", false)):
		return copied
	var parts: PackedStringArray = path.split(".", true)
	var current: Dictionary = target
	for index in range(parts.size() - 1):
		var segment: String = parts[index]
		if not current.has(segment):
			current[segment] = {}
		if typeof(current[segment]) != TYPE_DICTIONARY:
			return failure("COMPUTE_PATH_TYPE_CONFLICT", {"path": path})
		current = current[segment]
	current[parts[parts.size() - 1]] = copied["details"]["value"]
	return success()


static func remove_state_path(target: Dictionary, path: String) -> Dictionary:
	if not is_state_path(path):
		return failure("INVALID_COMPUTE_STATE_PATH")
	var parts: PackedStringArray = path.split(".", true)
	var current: Dictionary = target
	for index in range(parts.size() - 1):
		if typeof(current.get(parts[index])) != TYPE_DICTIONARY:
			return failure("COMPUTE_PATH_NOT_FOUND", {"path": path})
		current = current[parts[index]]
	var leaf: String = parts[parts.size() - 1]
	if not current.has(leaf):
		return failure("COMPUTE_PATH_NOT_FOUND", {"path": path})
	current.erase(leaf)
	return success()


static func success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "message": "", "details": details.duplicate(true)}


static func failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}

extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

static func success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": "", "details": details.duplicate(true)}
	for key in details:
		result[key] = details[key]
	return result

static func failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}

static func path_id(value: String, prefix: String) -> bool:
	if not value.begins_with(prefix) or value.length() <= prefix.length() or value != value.to_lower() or value.contains("//"):
		return false
	for segment in value.split("/", true):
		if segment.is_empty():
			return false
		for character in segment:
			if not String(character) in "abcdefghijklmnopqrstuvwxyz0123456789-_":
				return false
	return true

static func hash64(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for character in value:
		if not String(character) in "0123456789abcdef":
			return false
	return true

static func finite_number(value) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and not is_nan(float(value)) and not is_inf(float(value))

static func finite_vector(value, size: int) -> bool:
	if typeof(value) != TYPE_ARRAY or Array(value).size() != size:
		return false
	for component in value:
		if not finite_number(component):
			return false
	return true

static func sorted_unique_strings(value, prefix: String = "") -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	var previous := ""
	for raw in value:
		if typeof(raw) != TYPE_STRING:
			return false
		var current := String(raw)
		if current.is_empty() or (not prefix.is_empty() and not path_id(current, prefix)):
			return false
		if not previous.is_empty() and current <= previous:
			return false
		previous = current
	return true

static func sorted_strings(value: Array) -> Array:
	var result := value.duplicate(true)
	result.sort()
	return result

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload["checksum"] = ""
	return Utils.payload_hash(payload)

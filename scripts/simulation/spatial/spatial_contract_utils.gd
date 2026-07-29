extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const MAX_HIERARCHY_LEVEL: int = 64
const MAX_CHILD_INDEX: int = 65535


static func is_canonical_id(value, minimum_parts: int = 1) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text: String = String(value)
	if text.is_empty() or text != text.strip_edges().to_lower() or text.begins_with("/") or text.ends_with("/"):
		return false
	var parts: PackedStringArray = text.split("/", true)
	if parts.size() < minimum_parts:
		return false
	for part in parts:
		if not is_lower_segment(part, true):
			return false
	return true


static func is_lower_segment(value: String, allow_colon: bool = false) -> bool:
	if value.is_empty() or value != value.to_lower():
		return false
	var allowed: String = "abcdefghijklmnopqrstuvwxyz0123456789-_ ."
	allowed = allowed.replace(" ", "")
	if allow_colon:
		allowed += ":"
	for character in value:
		if allowed.find(String(character)) < 0:
			return false
	return true


static func is_kind(value) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text: String = String(value)
	if text.is_empty() or text != text.strip_edges().to_upper():
		return false
	var allowed: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
	for character in text:
		if allowed.find(String(character)) < 0:
			return false
	return true


static func is_schema_id(value) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text: String = String(value)
	if text.is_empty() or text != text.strip_edges().to_lower():
		return false
	var parts: PackedStringArray = text.split(".", true)
	if parts.size() < 2:
		return false
	for part in parts:
		if not is_lower_segment(part, false):
			return false
	return true


static func is_vector3_array(value) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return false
	for component in value:
		if typeof(component) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(component)):
			return false
	return true


static func validate_sorted_unique_ids(value, allow_empty: bool = false) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return failure("INVALID_ID_ARRAY")
	if not allow_empty and value.is_empty():
		return failure("EMPTY_ID_ARRAY")
	var previous: String = ""
	for index in range(value.size()):
		var raw = value[index]
		if not is_canonical_id(raw, 2):
			return failure("INVALID_ID_ARRAY_ENTRY", {"index": index})
		var current: String = String(raw)
		if index > 0 and current <= previous:
			return failure("ID_ARRAY_NOT_SORTED_UNIQUE", {"index": index})
		previous = current
	return success()


static func sorted_unique_ids(values: Array) -> Array:
	var seen: Dictionary = {}
	for raw in values:
		if is_canonical_id(raw, 2):
			seen[String(raw)] = true
	var result: Array = seen.keys()
	result.sort()
	return result


static func json_copy(value) -> Dictionary:
	var round_trip: Dictionary = NetworkUtilsScript.json_round_trip(value)
	if not bool(round_trip.get("success", false)):
		return failure("JSON_COPY_FAILED")
	return success({"value": round_trip.get("value")})


static func success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}

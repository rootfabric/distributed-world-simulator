extends RefCounted

const ContractUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")

const HEX := "0123456789abcdef"

static func success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result

static func failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	var result := {"success": false, "error_code": error_code, "message": error_code}
	for key in details:
		result[key] = details[key]
	return result

static func checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload["checksum"] = ""
	return ContractUtils.payload_hash(payload)

static func validate_checksum(value: Dictionary, error_code: String) -> Dictionary:
	if not is_hash(value.get("checksum")):
		return failure(error_code)
	var expected := checksum(value)
	if expected.is_empty() or String(value["checksum"]) != expected:
		return failure(error_code)
	return success()

static func is_hash(value) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text := String(value)
	if text.length() != 64 or text != text.to_lower():
		return false
	for character in text:
		if not String(character) in HEX:
			return false
	return true

static func is_path_id(value, prefix: String) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text := String(value)
	if not text.begins_with(prefix) or text.length() <= prefix.length():
		return false
	if text != text.to_lower() or text != text.strip_edges() or text.contains("//"):
		return false
	for segment in text.split("/", true):
		if segment.is_empty():
			return false
		for character in segment:
			if not String(character) in "abcdefghijklmnopqrstuvwxyz0123456789-_":
				return false
	return true

static func is_token(value) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text := String(value)
	if text.is_empty() or text != text.strip_edges():
		return false
	for character in text:
		if not String(character) in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:":
			return false
	return true

static func is_non_negative_integer(value) -> bool:
	return ContractUtils.is_json_integer(value) and int(value) >= 0

static func is_positive_integer(value) -> bool:
	return ContractUtils.is_json_integer(value) and int(value) > 0

static func sorted_unique_strings(value) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	var previous := ""
	for raw in value:
		if not is_token(raw):
			return false
		var current := String(raw)
		if not previous.is_empty() and current <= previous:
			return false
		previous = current
	return true

static func sorted_string_array(values: Array) -> Array:
	var result: Array = []
	for value in values:
		result.append(String(value))
	result.sort()
	return result

static func exact_fields(value: Dictionary, fields: Array[String]) -> Dictionary:
	var checked := ContractUtils.validate_exact_fields(value, fields)
	if bool(checked.get("success", false)):
		return success()
	return failure(String(checked.get("error_code", "INVALID_FIELDS")))

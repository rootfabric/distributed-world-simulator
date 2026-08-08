extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SpatialUtilsScript = preload("res://scripts/simulation/spatial/spatial_contract_utils.gd")

const DEFAULT_FLOAT_TOLERANCE: float = 0.000000001


static func success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}


static func validate_exact_fields(value: Dictionary, fields: Array[String]) -> Dictionary:
	var result: Dictionary = NetworkUtilsScript.validate_exact_fields(value, fields)
	if bool(result.get("success", false)):
		return success()
	return failure(String(result.get("error_code", "INVALID_FIELDS")))


static func is_finite_number(value) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func is_non_negative_number(value) -> bool:
	return is_finite_number(value) and float(value) >= 0.0


static func is_positive_number(value) -> bool:
	return is_finite_number(value) and float(value) > 0.0


static func is_ratio(value) -> bool:
	return is_finite_number(value) and float(value) >= 0.0 and float(value) <= 1.0


static func is_json_integer(value) -> bool:
	return NetworkUtilsScript.is_json_integer(value)


static func is_canonical_id(value, minimum_parts: int = 2) -> bool:
	return SpatialUtilsScript.is_canonical_id(value, minimum_parts)


static func is_vector3_array(value) -> bool:
	return SpatialUtilsScript.is_vector3_array(value)


static func validate_sorted_unique_ids(value, allow_empty: bool = false) -> Dictionary:
	return SpatialUtilsScript.validate_sorted_unique_ids(value, allow_empty)


static func sorted_unique_ids(values: Array) -> Array:
	return SpatialUtilsScript.sorted_unique_ids(values)


static func is_lower_hex_64(value) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text: String = String(value)
	if text.length() != 64 or text != text.to_lower():
		return false
	for character in text:
		if not String(character) in [
			"0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
			"a", "b", "c", "d", "e", "f",
		]:
			return false
	return true


static func is_semantic_version(value) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text: String = String(value)
	if text.is_empty() or text != text.strip_edges():
		return false
	var build_parts: PackedStringArray = text.split("+", true, 1)
	if build_parts.size() > 2:
		return false
	if build_parts.size() == 2 and not _validate_dot_identifiers(build_parts[1], false):
		return false
	var pre_parts: PackedStringArray = build_parts[0].split("-", true, 1)
	if pre_parts.size() > 2:
		return false
	if pre_parts.size() == 2 and not _validate_dot_identifiers(pre_parts[1], true):
		return false
	var core: PackedStringArray = pre_parts[0].split(".", true)
	if core.size() != 3:
		return false
	for identifier in core:
		if not _is_numeric_identifier(identifier):
			return false
	return true


static func canonical_json(value) -> String:
	return NetworkUtilsScript.canonical_json(value)


static func payload_hash(value) -> String:
	return NetworkUtilsScript.payload_hash(value)


static func compute_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload.erase("checksum")
	return payload_hash(payload)


static func validate_checksum(value: Dictionary) -> Dictionary:
	if not is_lower_hex_64(value.get("checksum")):
		return failure("INVALID_CHECKSUM")
	if String(value["checksum"]) != compute_checksum(value):
		return failure("CHECKSUM_MISMATCH")
	return success()


static func validate_json_safe(value, path: String = "$.geo") -> Dictionary:
	var result: Dictionary = NetworkUtilsScript.canonicalize(value, path)
	if not bool(result.get("success", false)):
		return failure("NON_CANONICAL_JSON_VALUE", {"error": String(result.get("error", ""))})
	return success()


static func normalize(value: Dictionary, validator: Callable) -> Dictionary:
	if not bool(validator.call(value).get("success", false)):
		return {}
	var normalized: Dictionary = value.duplicate(true)
	var encoded: String = canonical_json(normalized)
	if encoded.is_empty() or payload_hash(normalized) != payload_hash(value):
		return {}
	return normalized


static func approximately_equal(a: float, b: float, tolerance: float = DEFAULT_FLOAT_TOLERANCE) -> bool:
	return is_finite(a) and is_finite(b) and is_finite(tolerance) and tolerance >= 0.0 and absf(a - b) <= tolerance


static func _validate_dot_identifiers(value: String, reject_numeric_leading_zero: bool) -> bool:
	if value.is_empty():
		return false
	for identifier in value.split(".", true):
		if identifier.is_empty():
			return false
		if reject_numeric_leading_zero and identifier.is_valid_int() and identifier.length() > 1 and identifier.begins_with("0"):
			return false
		for character in identifier:
			var text: String = String(character)
			if not text in [
				"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
				"n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
				"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
				"N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
				"0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "-",
			]:
				return false
	return true


static func _is_numeric_identifier(value: String) -> bool:
	if value.is_empty() or (value.length() > 1 and value.begins_with("0")):
		return false
	for character in value:
		if not String(character) in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]:
			return false
	return true

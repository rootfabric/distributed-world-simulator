extends RefCounted

const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SpatialUtils = preload("res://scripts/simulation/spatial/spatial_contract_utils.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")

const SOURCE_DOMAINS: Array[String] = ["CONSTRUCTION", "MATTER"]

static func success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}

static func failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}

static func validate_exact_fields(value: Dictionary, fields: Array[String]) -> Dictionary:
	var checked: Dictionary = NetworkUtils.validate_exact_fields(value, fields)
	if bool(checked.get("success", false)):
		return success()
	return failure(String(checked.get("error_code", "INVALID_FIELDS")))

static func is_json_integer(value) -> bool:
	return NetworkUtils.is_json_integer(value)

static func is_finite_number(value) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))

static func is_non_negative_number(value) -> bool:
	return is_finite_number(value) and float(value) >= 0.0

static func is_positive_number(value) -> bool:
	return is_finite_number(value) and float(value) > 0.0

static func is_lower_hex_64(value) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text: String = String(value)
	if text.length() != 64 or text != text.to_lower():
		return false
	for character in text:
		if "0123456789abcdef".find(String(character)) < 0:
			return false
	return true

static func is_canonical_id(value, minimum_parts: int = 2) -> bool:
	return SpatialUtils.is_canonical_id(value, minimum_parts)

static func is_source_domain(value) -> bool:
	return typeof(value) == TYPE_STRING and SOURCE_DOMAINS.has(String(value))

static func is_upper_kind(value, allow_empty: bool = false) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text: String = String(value)
	if text.is_empty():
		return allow_empty
	if text != text.strip_edges().to_upper():
		return false
	for character in text:
		if "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_".find(String(character)) < 0:
			return false
	return true

static func source_key(source_domain: String, source_id: String) -> String:
	return "%s/%s" % [source_domain.to_lower(), source_id]

static func validate_source_revision(value: Dictionary) -> Dictionary:
	return SourceRevision.validate(value)

static func validate_dimension(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.size() != 7:
		return failure("INVALID_PHYSICAL_DIMENSION")
	for exponent in value:
		if not is_json_integer(exponent):
			return failure("INVALID_PHYSICAL_DIMENSION")
	return success()

static func validate_sorted_unique_strings(value, allow_empty: bool = false, uppercase: bool = false) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return failure("INVALID_STRING_ARRAY")
	if value.is_empty() and not allow_empty:
		return failure("EMPTY_STRING_ARRAY")
	var previous: String = ""
	for index in range(value.size()):
		if typeof(value[index]) != TYPE_STRING:
			return failure("INVALID_STRING_ARRAY_ENTRY", {"index": index})
		var current: String = String(value[index])
		if current.is_empty():
			return failure("INVALID_STRING_ARRAY_ENTRY", {"index": index})
		if uppercase and not is_upper_kind(current):
			return failure("INVALID_STRING_ARRAY_ENTRY", {"index": index})
		if index > 0 and current <= previous:
			return failure("STRING_ARRAY_NOT_SORTED_UNIQUE", {"index": index})
		previous = current
	return success()

static func canonical_hash(value) -> String:
	return NetworkUtils.payload_hash(value)

static func compute_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload.erase("checksum")
	return canonical_hash(payload)

static func validate_checksum(value: Dictionary) -> Dictionary:
	if not is_lower_hex_64(value.get("checksum")):
		return failure("INVALID_BAKE_CHECKSUM")
	if String(value["checksum"]) != compute_checksum(value):
		return failure("BAKE_CHECKSUM_MISMATCH")
	return success()

static func sorted_dicts(values: Array, key_field: String) -> Array:
	var output: Array = []
	for raw in values:
		output.append(raw.duplicate(true) if typeof(raw) == TYPE_DICTIONARY else raw)
	output.sort_custom(func(a, b): return String(a.get(key_field, "")) < String(b.get(key_field, "")))
	return output

static func sorted_strings(values: Array) -> Array:
	var output: Array = values.duplicate()
	output.sort()
	return output

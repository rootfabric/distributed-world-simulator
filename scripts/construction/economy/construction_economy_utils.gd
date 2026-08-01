extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const P = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")

static func check_fields(value: Dictionary, fields: Array[String], schema: String, schema_code: String) -> Dictionary:
	var exact := Utils.validate_exact_fields(value, fields)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != schema:
		return P.failure(schema_code)
	return P.success()

static func checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload["checksum"] = ""
	return Utils.payload_hash(payload)

static func money(value) -> bool:
	return P.non_negative_number(value) and float(value) <= 1000000000000.0

static func positive(value) -> bool:
	return (typeof(value) == TYPE_FLOAT or Utils.is_json_integer(value)) and float(value) > 0.0 and is_finite(float(value))

static func canonical_dict(value) -> bool:
	return typeof(value) == TYPE_DICTIONARY and bool(Utils.canonicalize(value).get("success", false))

static func sorted_unique_strings(value, prefix: String = "") -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	var previous := ""
	for raw in value:
		if typeof(raw) != TYPE_STRING:
			return false
		var text := String(raw)
		if text.is_empty() or (not prefix.is_empty() and not P.path_id(text, prefix)):
			return false
		if not previous.is_empty() and text <= previous:
			return false
		previous = text
	return true

static func sorted_rows(rows: Array, key: String) -> Array:
	return P.sorted_rows(rows, key)

static func operation_result(success: bool, code: String = "", details: Dictionary = {}) -> Dictionary:
	return P.success(details) if success else P.failure(code, details)

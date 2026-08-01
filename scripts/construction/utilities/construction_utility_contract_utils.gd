extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const VALID_KINDS: Array[String] = ["POWER", "WATER", "AIR", "HEAT", "DATA"]
const VALID_UNITS := {"POWER": "KWH", "WATER": "L", "AIR": "M3", "HEAT": "MJ", "DATA": "MB"}

static func is_path(value: String, prefix: String) -> bool:
	if not value.begins_with(prefix) or value.length() <= prefix.length() or value != value.to_lower() or value.contains("//"):
		return false
	for segment in value.split("/", true):
		if segment.is_empty(): return false
		for character in segment:
			if not String(character) in "abcdefghijklmnopqrstuvwxyz0123456789-_": return false
	return true

static func is_number(value) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and not is_nan(float(value)) and not is_inf(float(value))

static func non_negative(value) -> bool: return is_number(value) and float(value) >= 0.0
static func positive(value) -> bool: return is_number(value) and float(value) > 0.0
static func ratio(value, allow_zero: bool = true) -> bool:
	if not is_number(value): return false
	var number := float(value)
	return number >= (0.0 if allow_zero else 0.000000001) and number <= 1.0

static func sorted_unique_strings(value, prefix: String = "", allow_empty: bool = true) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or (not allow_empty and Array(value).is_empty()): return failure("INVALID_CONSTRUCTION_UTILITY_REFERENCE_COLLECTION")
	var previous := ""; var seen := {}
	for raw in value:
		if typeof(raw) != TYPE_STRING: return failure("INVALID_CONSTRUCTION_UTILITY_REFERENCE")
		var text := String(raw)
		if (not prefix.is_empty() and not is_path(text, prefix)) or seen.has(text) or (not previous.is_empty() and text < previous): return failure("NON_CANONICAL_CONSTRUCTION_UTILITY_REFERENCES")
		seen[text] = true; previous = text
	return success()

static func success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": "", "details": details.duplicate(true)}
	for key in details: result[key] = details[key]
	return result
static func failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}

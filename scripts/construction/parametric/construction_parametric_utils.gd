extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const METRIC_SCALE: float = 1000000000.0
const EPSILON: float = 0.00000001

static func metric(value: float) -> float:
	return round(value * METRIC_SCALE) / METRIC_SCALE

static func positive_number(value) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and not is_nan(float(value)) and not is_inf(float(value)) and float(value) > 0.0

static func non_negative_number(value) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and not is_nan(float(value)) and not is_inf(float(value)) and float(value) >= 0.0

static func nearly_equal(left: float, right: float, epsilon: float = EPSILON) -> bool:
	return absf(left - right) <= epsilon * maxf(1.0, maxf(absf(left), absf(right)))

static func path_id(value: String, prefix: String) -> bool:
	if not value.begins_with(prefix) or value.length() <= prefix.length() or value != value.strip_edges() or value.contains("//"):
		return false
	for segment in value.split("/", true):
		if not token(segment):
			return false
	return true

static func token(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges():
		return false
	for character in value:
		if not String(character) in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:":
			return false
	return true

static func upper_kind(value: String) -> bool:
	if value.is_empty() or value != value.to_upper():
		return false
	for character in value:
		if not String(character) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_":
			return false
	return true

static func sorted_strings(values: Array) -> Array:
	var result: Array = []
	for value in values:
		result.append(String(value))
	result.sort()
	return result

static func sorted_rows(values: Array, key: String) -> Array:
	var result: Array = values.duplicate(true)
	result.sort_custom(func(left, right): return String(left.get(key, "")) < String(right.get(key, "")))
	return result

static func success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result

static func failure(code: String, details: Dictionary = {}) -> Dictionary:
	var result := {"success": false, "error_code": code, "message": code}
	for key in details:
		result[key] = details[key]
	return result

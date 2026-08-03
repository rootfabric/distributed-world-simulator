extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SpatialUtilsScript = preload("res://scripts/simulation/spatial/spatial_contract_utils.gd")

const SOURCE_DOMAINS: Array[String] = ["CONSTRUCTION", "MATTER"]
const ARTIFACT_KINDS: Array[String] = [
	"DETAIL",
	"SIMPLIFIED_MESH",
	"MACRO_PROXY",
	"IMPOSTOR",
	"NONE",
]
const CACHE_STATES: Array[String] = ["BUILDING", "EVICTED", "FAILED", "READY", "STALE"]
const INVALIDATION_REASONS: Array[String] = ["DEPENDENCY", "HANDOFF", "MANUAL", "MUTATION", "POLICY"]
const MAX_LOD_LEVEL: int = 32


static func success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}


static func validate_exact_fields(value: Dictionary, fields: Array[String]) -> Dictionary:
	var checked: Dictionary = NetworkUtilsScript.validate_exact_fields(value, fields)
	if bool(checked.get("success", false)):
		return success()
	return failure(String(checked.get("error_code", "INVALID_FIELDS")))


static func is_finite_number(value) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func is_non_negative_number(value) -> bool:
	return is_finite_number(value) and float(value) >= 0.0


static func is_positive_number(value) -> bool:
	return is_finite_number(value) and float(value) > 0.0


static func is_json_integer(value) -> bool:
	return NetworkUtilsScript.is_json_integer(value)


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
	return SpatialUtilsScript.is_canonical_id(value, minimum_parts)


static func is_source_domain(value) -> bool:
	return typeof(value) == TYPE_STRING and SOURCE_DOMAINS.has(String(value))


static func is_artifact_kind(value) -> bool:
	return typeof(value) == TYPE_STRING and ARTIFACT_KINDS.has(String(value))


static func validate_bounds_m(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.size() != 6:
		return failure("INVALID_REPRESENTATION_BOUNDS")
	for component in value:
		if not is_finite_number(component):
			return failure("INVALID_REPRESENTATION_BOUNDS")
	if float(value[0]) > float(value[3]) \
		or float(value[1]) > float(value[4]) \
		or float(value[2]) > float(value[5]):
		return failure("INVALID_REPRESENTATION_BOUNDS_ORDER")
	return success()


static func validate_sorted_unique_ids(value, allow_empty: bool = false) -> Dictionary:
	return SpatialUtilsScript.validate_sorted_unique_ids(value, allow_empty)


static func validate_sorted_unique_kinds(value, allow_empty: bool = false) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return failure("INVALID_REPRESENTATION_KIND_ARRAY")
	if value.is_empty() and not allow_empty:
		return failure("EMPTY_REPRESENTATION_KIND_ARRAY")
	var previous: String = ""
	for index in range(value.size()):
		if not is_artifact_kind(value[index]):
			return failure("INVALID_REPRESENTATION_KIND_ARRAY", {"index": index})
		var current: String = String(value[index])
		if index > 0 and current <= previous:
			return failure("REPRESENTATION_KIND_ARRAY_NOT_SORTED_UNIQUE", {"index": index})
		previous = current
	return success()


static func compute_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload.erase("checksum")
	return NetworkUtilsScript.payload_hash(payload)


static func validate_checksum(value: Dictionary) -> Dictionary:
	if not is_lower_hex_64(value.get("checksum")):
		return failure("INVALID_REPRESENTATION_CHECKSUM")
	if String(value["checksum"]) != compute_checksum(value):
		return failure("REPRESENTATION_CHECKSUM_MISMATCH")
	return success()


static func payload_hash(value) -> String:
	return NetworkUtilsScript.payload_hash(value)


static func canonical_json(value) -> String:
	return NetworkUtilsScript.canonical_json(value)


static func screen_error_px(geometric_error_m: float, distance_m: float, projection_scale_px: float) -> float:
	if not is_finite(geometric_error_m) or not is_finite(distance_m) or not is_finite(projection_scale_px):
		return INF
	if geometric_error_m < 0.0 or distance_m <= 0.0 or projection_scale_px <= 0.0:
		return INF
	return geometric_error_m * projection_scale_px / distance_m

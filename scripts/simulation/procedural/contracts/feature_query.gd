extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const FeatureTypeScript = preload("res://scripts/simulation/procedural/contracts/feature_type.gd")

const SCHEMA: String = "planet_simulator.feature_query.v1"
const FIELDS: Array[String] = [
	"schema",
	"body_id",
	"frame_id",
	"center_m",
	"radius_m",
	"feature_types",
	"checksum",
]


static func create(body_id: String, frame_id: String, center_m: Array, radius_m: float, feature_types: Array = []) -> Dictionary:
	var canonical_types: Array = []
	var seen: Dictionary = {}
	for raw_type in feature_types:
		if bool(FeatureTypeScript.validate(raw_type).get("success", false)):
			seen[String(raw_type)] = true
	canonical_types = seen.keys()
	canonical_types.sort()
	var value: Dictionary = {
		"schema": SCHEMA,
		"body_id": body_id,
		"frame_id": frame_id,
		"center_m": center_m.duplicate(),
		"radius_m": radius_m,
		"feature_types": canonical_types,
		"checksum": "",
	}
	value["checksum"] = GeoUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return GeoUtilsScript.failure("UNSUPPORTED_FEATURE_QUERY_SCHEMA")
	if not GeoUtilsScript.is_canonical_id(value.get("body_id"), 2):
		return GeoUtilsScript.failure("INVALID_FEATURE_QUERY_BODY_ID")
	if not GeoUtilsScript.is_canonical_id(value.get("frame_id"), 2):
		return GeoUtilsScript.failure("INVALID_FEATURE_QUERY_FRAME_ID")
	if not GeoUtilsScript.is_vector3_array(value.get("center_m")):
		return GeoUtilsScript.failure("INVALID_FEATURE_QUERY_CENTER")
	if not GeoUtilsScript.is_non_negative_number(value.get("radius_m")):
		return GeoUtilsScript.failure("INVALID_FEATURE_QUERY_RADIUS")
	if typeof(value.get("feature_types")) != TYPE_ARRAY:
		return GeoUtilsScript.failure("INVALID_FEATURE_QUERY_TYPES")
	var previous: String = ""
	for index in range(value["feature_types"].size()):
		var current: String = String(value["feature_types"][index])
		if not bool(FeatureTypeScript.validate(current).get("success", false)):
			return GeoUtilsScript.failure("INVALID_FEATURE_QUERY_TYPE", {"index": index})
		if index > 0 and current <= previous:
			return GeoUtilsScript.failure("FEATURE_QUERY_TYPES_NOT_SORTED_UNIQUE")
		previous = current
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.feature_query")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)

extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")

const SCHEMA: String = "planet_simulator.geo_surface_query.v1"
const FIELDS: Array[String] = [
	"schema",
	"body_id",
	"body_fixed_position_m",
	"requested_fields",
	"checksum",
]


static func create(body_id: String, body_fixed_position_m: Array, requested_fields: Array) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"body_id": body_id,
		"body_fixed_position_m": body_fixed_position_m.duplicate(true),
		"requested_fields": GeoUtilsScript.sorted_unique_ids(requested_fields),
		"checksum": "",
	}
	value["checksum"] = GeoUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return GeoUtilsScript.failure("UNSUPPORTED_GEO_SURFACE_QUERY_SCHEMA")
	if not GeoUtilsScript.is_canonical_id(value.get("body_id"), 2):
		return GeoUtilsScript.failure("INVALID_GEO_SURFACE_QUERY_BODY_ID")
	if not GeoUtilsScript.is_vector3_array(value.get("body_fixed_position_m")):
		return GeoUtilsScript.failure("INVALID_BODY_FIXED_POSITION")
	var requested: Dictionary = GeoUtilsScript.validate_sorted_unique_ids(value.get("requested_fields"), false)
	if not bool(requested.get("success", false)):
		return GeoUtilsScript.failure("INVALID_REQUESTED_GEO_FIELDS")
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.geo_surface_query")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return GeoUtilsScript.normalize(value, validate)

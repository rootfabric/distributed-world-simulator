extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")

const SCHEMA: String = "planet_simulator.body_fixed_position.v1"
const FIELDS: Array[String] = [
	"schema",
	"body_id",
	"position_m",
	"checksum",
]


static func create(body_id: String, position_m: Array) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"body_id": body_id,
		"position_m": position_m.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = GeoUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return GeoUtilsScript.failure("UNSUPPORTED_BODY_FIXED_POSITION_SCHEMA")
	if not GeoUtilsScript.is_canonical_id(value.get("body_id"), 2):
		return GeoUtilsScript.failure("INVALID_BODY_FIXED_POSITION_BODY_ID")
	if not GeoUtilsScript.is_vector3_array(value.get("position_m")):
		return GeoUtilsScript.failure("INVALID_BODY_FIXED_POSITION_VECTOR")
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.body_fixed_position")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return GeoUtilsScript.normalize(value, validate)

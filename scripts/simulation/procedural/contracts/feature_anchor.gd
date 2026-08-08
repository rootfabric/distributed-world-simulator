extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")

const SCHEMA: String = "planet_simulator.feature_anchor.v1"
const ANCHOR_PREFIX: String = "feature-anchor/"
const ROLE_PREFIX: String = "feature-anchor-role/"
const FIELDS: Array[String] = [
	"schema",
	"anchor_id",
	"frame_id",
	"role",
	"position_m",
	"checksum",
]


static func create(anchor_id: String, frame_id: String, role: String, position_m: Array) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"anchor_id": anchor_id,
		"frame_id": frame_id,
		"role": role,
		"position_m": position_m.duplicate(),
		"checksum": "",
	}
	value["checksum"] = GeoUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return GeoUtilsScript.failure("UNSUPPORTED_FEATURE_ANCHOR_SCHEMA")
	if not GeoUtilsScript.is_canonical_id(value.get("anchor_id"), 2) or not String(value["anchor_id"]).begins_with(ANCHOR_PREFIX):
		return GeoUtilsScript.failure("INVALID_FEATURE_ANCHOR_ID")
	if not GeoUtilsScript.is_canonical_id(value.get("frame_id"), 2):
		return GeoUtilsScript.failure("INVALID_FEATURE_ANCHOR_FRAME_ID")
	if not GeoUtilsScript.is_canonical_id(value.get("role"), 2) or not String(value["role"]).begins_with(ROLE_PREFIX):
		return GeoUtilsScript.failure("INVALID_FEATURE_ANCHOR_ROLE")
	if not GeoUtilsScript.is_vector3_array(value.get("position_m")):
		return GeoUtilsScript.failure("INVALID_FEATURE_ANCHOR_POSITION")
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.feature_anchor")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)

extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const FieldIdScript = preload("res://scripts/simulation/procedural/contracts/semantic_field_id.gd")

const SCHEMA: String = "planet_simulator.semantic_field_query.v1"
const FIELDS: Array[String] = [
	"schema",
	"body_id",
	"frame_id",
	"body_fixed_position_m",
	"requested_field_ids",
	"checksum",
]


static func create(body_id: String, frame_id: String, body_fixed_position_m: Array, requested_field_ids: Array) -> Dictionary:
	var normalized_ids: Array = []
	var normalized_result: Dictionary = FieldIdScript.normalize_many(requested_field_ids)
	if bool(normalized_result.get("success", false)):
		normalized_ids = normalized_result["details"]["field_ids"]
	var value: Dictionary = {
		"schema": SCHEMA,
		"body_id": body_id,
		"frame_id": frame_id,
		"body_fixed_position_m": body_fixed_position_m.duplicate(true),
		"requested_field_ids": normalized_ids,
		"checksum": "",
	}
	value["checksum"] = GeoUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return GeoUtilsScript.failure("UNSUPPORTED_SEMANTIC_FIELD_QUERY_SCHEMA")
	if not GeoUtilsScript.is_canonical_id(value.get("body_id"), 2):
		return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_QUERY_BODY_ID")
	if not GeoUtilsScript.is_canonical_id(value.get("frame_id"), 2):
		return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_QUERY_FRAME_ID")
	if not GeoUtilsScript.is_vector3_array(value.get("body_fixed_position_m")):
		return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_QUERY_POSITION")
	if typeof(value.get("requested_field_ids")) != TYPE_ARRAY or value["requested_field_ids"].is_empty():
		return GeoUtilsScript.failure("INVALID_SEMANTIC_FIELD_QUERY_FIELDS")
	var previous: String = ""
	for index in range(value["requested_field_ids"].size()):
		var raw_id = value["requested_field_ids"][index]
		var field_validation: Dictionary = FieldIdScript.validate(raw_id)
		if not bool(field_validation.get("success", false)):
			return field_validation
		var field_id: String = String(raw_id)
		if index > 0 and field_id <= previous:
			return GeoUtilsScript.failure("SEMANTIC_FIELD_QUERY_FIELDS_NOT_SORTED_UNIQUE")
		previous = field_id
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.semantic_field_query")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return GeoUtilsScript.normalize(value, validate)

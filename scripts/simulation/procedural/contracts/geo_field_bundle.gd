extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")

const SCHEMA: String = "planet_simulator.geo_field_bundle.v1"
const FIELDS: Array[String] = ["schema", "values", "provenance", "checksum"]


static func create(values: Dictionary, provenance: Dictionary) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"values": values.duplicate(true),
		"provenance": provenance.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = GeoUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return GeoUtilsScript.failure("UNSUPPORTED_GEO_FIELD_BUNDLE_SCHEMA")
	if typeof(value.get("values")) != TYPE_DICTIONARY or typeof(value.get("provenance")) != TYPE_DICTIONARY:
		return GeoUtilsScript.failure("INVALID_GEO_FIELD_BUNDLE_MAP")
	var values: Dictionary = value["values"]
	var provenance: Dictionary = value["provenance"]
	if values.size() != provenance.size():
		return GeoUtilsScript.failure("GEO_FIELD_PROVENANCE_MISMATCH")
	var field_ids: Array = values.keys()
	field_ids.sort()
	var provenance_ids: Array = provenance.keys()
	provenance_ids.sort()
	if field_ids != provenance_ids:
		return GeoUtilsScript.failure("GEO_FIELD_PROVENANCE_MISMATCH")
	for raw_field_id in field_ids:
		var field_id: String = String(raw_field_id)
		if not GeoUtilsScript.is_canonical_id(field_id, 2):
			return GeoUtilsScript.failure("INVALID_GEO_FIELD_ID", {"field": field_id})
		if not GeoUtilsScript.is_canonical_id(provenance[field_id], 2):
			return GeoUtilsScript.failure("INVALID_GEO_FIELD_PROVENANCE", {"field": field_id})
		var safe_value: Dictionary = GeoUtilsScript.validate_json_safe(values[field_id], "$.geo_field_bundle.values.%s" % field_id)
		if not bool(safe_value.get("success", false)):
			return safe_value
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.geo_field_bundle")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return GeoUtilsScript.normalize(value, validate)

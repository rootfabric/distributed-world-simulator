extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const FieldBundleScript = preload("res://scripts/simulation/procedural/contracts/geo_field_bundle.gd")

const SCHEMA: String = "planet_simulator.geo_sample.v1"
const QUERY_SURFACE: String = "SURFACE"
const QUERY_VOLUME: String = "VOLUME"
const FIELDS: Array[String] = [
	"schema",
	"body_id",
	"query_kind",
	"body_fixed_position_m",
	"fields",
	"provider_manifest_hash",
	"checksum",
]


static func create(
	body_id: String,
	query_kind: String,
	body_fixed_position_m: Array,
	fields: Dictionary,
	provider_manifest_hash: String
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"body_id": body_id,
		"query_kind": query_kind,
		"body_fixed_position_m": body_fixed_position_m.duplicate(true),
		"fields": fields.duplicate(true),
		"provider_manifest_hash": provider_manifest_hash,
		"checksum": "",
	}
	value["checksum"] = GeoUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return GeoUtilsScript.failure("UNSUPPORTED_GEO_SAMPLE_SCHEMA")
	if not GeoUtilsScript.is_canonical_id(value.get("body_id"), 2):
		return GeoUtilsScript.failure("INVALID_GEO_SAMPLE_BODY_ID")
	if typeof(value.get("query_kind")) != TYPE_STRING or String(value["query_kind"]) not in [QUERY_SURFACE, QUERY_VOLUME]:
		return GeoUtilsScript.failure("INVALID_GEO_SAMPLE_QUERY_KIND")
	if not GeoUtilsScript.is_vector3_array(value.get("body_fixed_position_m")):
		return GeoUtilsScript.failure("INVALID_BODY_FIXED_POSITION")
	if typeof(value.get("fields")) != TYPE_DICTIONARY or not bool(FieldBundleScript.validate(value["fields"]).get("success", false)):
		return GeoUtilsScript.failure("INVALID_GEO_SAMPLE_FIELDS")
	if not GeoUtilsScript.is_lower_hex_64(value.get("provider_manifest_hash")):
		return GeoUtilsScript.failure("INVALID_PROVIDER_MANIFEST_HASH")
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.geo_sample")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return GeoUtilsScript.normalize(value, validate)


static func field_value(value: Dictionary, field_id: String, fallback = null):
	if not bool(validate(value).get("success", false)):
		return fallback
	return value["fields"]["values"].get(field_id, fallback)

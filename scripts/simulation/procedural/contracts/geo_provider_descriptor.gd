extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")

const SCHEMA: String = "planet_simulator.geo_provider_descriptor.v1"
const FIELDS: Array[String] = [
	"schema",
	"provider_id",
	"contract_version",
	"generator_version",
	"requires",
	"provides",
	"deterministic",
	"parameters",
	"checksum",
]


static func create(
	provider_id: String,
	contract_version: String,
	generator_version: String,
	requires: Array,
	provides: Array,
	deterministic: bool = true,
	parameters: Dictionary = {}
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"provider_id": provider_id,
		"contract_version": contract_version,
		"generator_version": generator_version,
		"requires": GeoUtilsScript.sorted_unique_ids(requires),
		"provides": GeoUtilsScript.sorted_unique_ids(provides),
		"deterministic": deterministic,
		"parameters": parameters.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = GeoUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return GeoUtilsScript.failure("UNSUPPORTED_GEO_PROVIDER_DESCRIPTOR_SCHEMA")
	if not GeoUtilsScript.is_canonical_id(value.get("provider_id"), 2):
		return GeoUtilsScript.failure("INVALID_GEO_PROVIDER_ID")
	for field in ["contract_version", "generator_version"]:
		if not GeoUtilsScript.is_semantic_version(value.get(field)):
			return GeoUtilsScript.failure("INVALID_GEO_PROVIDER_VERSION", {"field": field})
	var requires_result: Dictionary = GeoUtilsScript.validate_sorted_unique_ids(value.get("requires"), true)
	if not bool(requires_result.get("success", false)):
		return GeoUtilsScript.failure("INVALID_GEO_PROVIDER_REQUIRES")
	var provides_result: Dictionary = GeoUtilsScript.validate_sorted_unique_ids(value.get("provides"), false)
	if not bool(provides_result.get("success", false)):
		return GeoUtilsScript.failure("INVALID_GEO_PROVIDER_PROVIDES")
	for required_field in value["requires"]:
		if value["provides"].has(required_field):
			return GeoUtilsScript.failure("GEO_PROVIDER_SELF_DEPENDENCY", {"field": String(required_field)})
	if typeof(value.get("deterministic")) != TYPE_BOOL:
		return GeoUtilsScript.failure("INVALID_GEO_PROVIDER_DETERMINISM")
	if typeof(value.get("parameters")) != TYPE_DICTIONARY:
		return GeoUtilsScript.failure("INVALID_GEO_PROVIDER_PARAMETERS")
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.geo_provider_descriptor")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return GeoUtilsScript.normalize(value, validate)

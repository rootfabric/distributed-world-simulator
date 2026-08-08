extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")

const SCHEMA: String = "planet_simulator.planet_definition.v1"
const FIELDS: Array[String] = [
	"schema",
	"body_id",
	"body_seed",
	"recipe_id",
	"body_shape_id",
	"nominal_radius_m",
	"generator_manifest_version",
	"checksum",
]


static func create(
	body_id: String,
	body_seed: int,
	recipe_id: String,
	body_shape_id: String,
	nominal_radius_m: float,
	generator_manifest_version: String
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"body_id": body_id,
		"body_seed": body_seed,
		"recipe_id": recipe_id,
		"body_shape_id": body_shape_id,
		"nominal_radius_m": nominal_radius_m,
		"generator_manifest_version": generator_manifest_version,
		"checksum": "",
	}
	value["checksum"] = GeoUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return GeoUtilsScript.failure("UNSUPPORTED_PLANET_DEFINITION_SCHEMA")
	for field in ["body_id", "recipe_id", "body_shape_id"]:
		if not GeoUtilsScript.is_canonical_id(value.get(field), 2):
			return GeoUtilsScript.failure("INVALID_PLANET_DEFINITION_ID", {"field": field})
	if not GeoUtilsScript.is_json_integer(value.get("body_seed")):
		return GeoUtilsScript.failure("INVALID_BODY_SEED")
	if not GeoUtilsScript.is_positive_number(value.get("nominal_radius_m")):
		return GeoUtilsScript.failure("INVALID_NOMINAL_RADIUS")
	if not GeoUtilsScript.is_semantic_version(value.get("generator_manifest_version")):
		return GeoUtilsScript.failure("INVALID_GENERATOR_MANIFEST_VERSION")
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.planet_definition")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return GeoUtilsScript.normalize(value, validate)

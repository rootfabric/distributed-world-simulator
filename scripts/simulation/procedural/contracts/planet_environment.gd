extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")

const SCHEMA: String = "planet_simulator.planet_environment.v1"
const FIELDS: Array[String] = [
	"schema",
	"environment_id",
	"gravity_model_id",
	"atmosphere_model_id",
	"temperature_model_id",
	"surface_fluid_catalog_id",
	"weathering_model_id",
	"material_catalog_id",
	"parameters",
	"checksum",
]


static func create(
	environment_id: String,
	gravity_model_id: String,
	atmosphere_model_id: String,
	temperature_model_id: String,
	surface_fluid_catalog_id: String,
	weathering_model_id: String,
	material_catalog_id: String,
	parameters: Dictionary = {}
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"environment_id": environment_id,
		"gravity_model_id": gravity_model_id,
		"atmosphere_model_id": atmosphere_model_id,
		"temperature_model_id": temperature_model_id,
		"surface_fluid_catalog_id": surface_fluid_catalog_id,
		"weathering_model_id": weathering_model_id,
		"material_catalog_id": material_catalog_id,
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
		return GeoUtilsScript.failure("UNSUPPORTED_PLANET_ENVIRONMENT_SCHEMA")
	for field in [
		"environment_id",
		"gravity_model_id",
		"atmosphere_model_id",
		"temperature_model_id",
		"surface_fluid_catalog_id",
		"weathering_model_id",
		"material_catalog_id",
	]:
		if not GeoUtilsScript.is_canonical_id(value.get(field), 2):
			return GeoUtilsScript.failure("INVALID_PLANET_ENVIRONMENT_ID", {"field": field})
	if typeof(value.get("parameters")) != TYPE_DICTIONARY:
		return GeoUtilsScript.failure("INVALID_PLANET_ENVIRONMENT_PARAMETERS")
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.planet_environment")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return GeoUtilsScript.normalize(value, validate)

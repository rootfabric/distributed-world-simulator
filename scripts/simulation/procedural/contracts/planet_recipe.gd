extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const EnvironmentScript = preload("res://scripts/simulation/procedural/contracts/planet_environment.gd")
const ProviderDescriptorScript = preload("res://scripts/simulation/procedural/contracts/geo_provider_descriptor.gd")

const SCHEMA: String = "planet_simulator.planet_recipe.v1"
const FIELDS: Array[String] = [
	"schema",
	"recipe_id",
	"recipe_version",
	"environment",
	"provider_descriptors",
	"checksum",
]


static func create(
	recipe_id: String,
	recipe_version: String,
	environment: Dictionary,
	provider_descriptors: Array
) -> Dictionary:
	var canonical_providers: Array = []
	for descriptor in provider_descriptors:
		if descriptor is Dictionary:
			canonical_providers.append(Dictionary(descriptor).duplicate(true))
	canonical_providers.sort_custom(func(a, b): return String(a.get("provider_id", "")) < String(b.get("provider_id", "")))
	var value: Dictionary = {
		"schema": SCHEMA,
		"recipe_id": recipe_id,
		"recipe_version": recipe_version,
		"environment": environment.duplicate(true),
		"provider_descriptors": canonical_providers,
		"checksum": "",
	}
	value["checksum"] = GeoUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return GeoUtilsScript.failure("UNSUPPORTED_PLANET_RECIPE_SCHEMA")
	if not GeoUtilsScript.is_canonical_id(value.get("recipe_id"), 2):
		return GeoUtilsScript.failure("INVALID_PLANET_RECIPE_ID")
	if not GeoUtilsScript.is_semantic_version(value.get("recipe_version")):
		return GeoUtilsScript.failure("INVALID_PLANET_RECIPE_VERSION")
	if typeof(value.get("environment")) != TYPE_DICTIONARY or not bool(EnvironmentScript.validate(value["environment"]).get("success", false)):
		return GeoUtilsScript.failure("INVALID_PLANET_RECIPE_ENVIRONMENT")
	if typeof(value.get("provider_descriptors")) != TYPE_ARRAY or value["provider_descriptors"].is_empty():
		return GeoUtilsScript.failure("EMPTY_PLANET_RECIPE_PROVIDERS")
	var previous_provider_id: String = ""
	for index in range(value["provider_descriptors"].size()):
		var descriptor = value["provider_descriptors"][index]
		if not descriptor is Dictionary or not bool(ProviderDescriptorScript.validate(descriptor).get("success", false)):
			return GeoUtilsScript.failure("INVALID_PLANET_RECIPE_PROVIDER", {"index": index})
		var provider_id: String = String(descriptor["provider_id"])
		if index > 0 and provider_id <= previous_provider_id:
			return GeoUtilsScript.failure("PLANET_RECIPE_PROVIDERS_NOT_CANONICAL", {"index": index})
		previous_provider_id = provider_id
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.planet_recipe")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return GeoUtilsScript.normalize(value, validate)


static func provider_descriptor_by_id(value: Dictionary, provider_id: String) -> Dictionary:
	if not bool(validate(value).get("success", false)):
		return {}
	for descriptor in value["provider_descriptors"]:
		if String(descriptor.get("provider_id", "")) == provider_id:
			return Dictionary(descriptor).duplicate(true)
	return {}

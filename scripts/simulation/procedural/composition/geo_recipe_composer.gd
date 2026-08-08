extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const PlanetRecipeScript = preload("res://scripts/simulation/procedural/contracts/planet_recipe.gd")


func configure_kernel(kernel, planet_definition: Dictionary, recipe: Dictionary, registry) -> Dictionary:
	if kernel == null or not kernel is RefCounted or not kernel.has_method("configure"):
		return GeoUtilsScript.failure("INVALID_GEO_KERNEL_FOR_COMPOSITION")
	if registry == null or not registry is RefCounted or not registry.has_method("instantiate"):
		return GeoUtilsScript.failure("INVALID_GEO_PROVIDER_REGISTRY")
	var recipe_validation: Dictionary = PlanetRecipeScript.validate(recipe)
	if not bool(recipe_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_COMPOSITION_RECIPE", {"cause": recipe_validation.get("error_code", "")})

	var providers: Array = []
	var instantiated_ids: Array[String] = []
	for raw_descriptor in recipe["provider_descriptors"]:
		var descriptor: Dictionary = Dictionary(raw_descriptor)
		var built: Dictionary = registry.instantiate(descriptor)
		if not bool(built.get("success", false)):
			return GeoUtilsScript.failure("GEO_RECIPE_PROVIDER_INSTANTIATION_FAILED", {
				"provider_id": String(descriptor.get("provider_id", "")),
				"cause": String(built.get("error_code", "")),
			})
		providers.append(built["details"]["provider"])
		instantiated_ids.append(String(descriptor["provider_id"]))

	var configured: Dictionary = kernel.configure(planet_definition, recipe, providers)
	if not bool(configured.get("success", false)):
		return GeoUtilsScript.failure("GEO_RECIPE_COMPOSITION_FAILED", {
			"cause": String(configured.get("error_code", "")),
			"details": configured.get("details", {}).duplicate(true),
		})
	return GeoUtilsScript.success({
		"instantiated_provider_ids": instantiated_ids,
		"provider_order": configured["details"]["provider_order"].duplicate(),
		"provider_manifest_hash": String(configured["details"]["provider_manifest_hash"]),
	})

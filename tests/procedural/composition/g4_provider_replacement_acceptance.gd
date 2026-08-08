extends SceneTree

const GeoUtils = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const PlanetDefinition = preload("res://scripts/simulation/procedural/contracts/planet_definition.gd")
const PlanetEnvironment = preload("res://scripts/simulation/procedural/contracts/planet_environment.gd")
const PlanetRecipe = preload("res://scripts/simulation/procedural/contracts/planet_recipe.gd")
const Context = preload("res://scripts/simulation/procedural/contracts/geo_generation_context.gd")
const SurfaceQuery = preload("res://scripts/simulation/procedural/contracts/geo_surface_query.gd")
const GeoSample = preload("res://scripts/simulation/procedural/contracts/geo_sample.gd")
const GeoKernel = preload("res://scripts/simulation/procedural/geo_kernel.gd")
const Composer = preload("res://scripts/simulation/procedural/composition/geo_recipe_composer.gd")
const Catalog = preload("res://scripts/simulation/procedural/composition/g4_surface_provider_catalog.gd")
const ValleyModifier = preload("res://scripts/simulation/procedural/providers/casual_valley_modifier_provider_v1.gd")

const BODY_ID := "body/procedural-g4-swap"
const RECIPE_ID := "world-recipe/g4-hot-swap"
const SHAPE_ID := "body-shape/sphere-v1"
const MANIFEST_VERSION := "1.0.0"
const RADIUS_M := 6000000.0
const SEED := 2026080801
const FINAL_FIELD := "geo/surface-height-m"

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	var catalog_result: Dictionary = Catalog.create_registry()
	_ok(catalog_result, "shared registry")
	if not _success(catalog_result):
		_finish()
		return
	var registry = catalog_result["details"]["registry"]
	var composer = Composer.new()
	var definition := PlanetDefinition.create(BODY_ID, SEED, RECIPE_ID, SHAPE_ID, RADIUS_M, MANIFEST_VERSION)
	var environment := PlanetEnvironment.create("planet-environment/g4-swap", "gravity-model/unspecified", "atmosphere-model/unspecified", "temperature-model/unspecified", "fluid-catalog/none", "weathering-model/none", "material-catalog/unspecified", {})

	var recipes := [
		PlanetRecipe.create(RECIPE_ID, "1.0.0", environment, Catalog.casual_descriptors(SEED, RADIUS_M)),
		PlanetRecipe.create(RECIPE_ID, "2.0.0", environment, Catalog.alternative_descriptors(SEED, RADIUS_M)),
		PlanetRecipe.create(RECIPE_ID, "1.0.0", environment, Catalog.casual_descriptors(SEED, RADIUS_M)),
		PlanetRecipe.create(RECIPE_ID, "2.0.0", environment, Catalog.alternative_descriptors(SEED, RADIUS_M)),
	]

	var reference_hashes: Dictionary = {}
	var reference_profiles: Dictionary = {}
	for index in range(recipes.size()):
		var recipe: Dictionary = recipes[index]
		var kernel = GeoKernel.new()
		var configured: Dictionary = composer.configure_kernel(kernel, definition, recipe, registry)
		_ok(configured, "replacement cycle %d configure" % index)
		if not _success(configured):
			continue
		var version: String = String(recipe["recipe_version"])
		var manifest_hash: String = String(configured["details"]["provider_manifest_hash"])
		var profile: Array = _profile(kernel)
		_check(profile.size() == 81, "replacement cycle profile complete")
		if not reference_hashes.has(version):
			reference_hashes[version] = manifest_hash
			reference_profiles[version] = profile
		else:
			_check(String(reference_hashes[version]) == manifest_hash, "returning to recipe reproduces manifest")
			_check(Array(reference_profiles[version]) == profile, "returning to recipe reproduces exact geography")

	_check(reference_hashes.size() == 2, "both recipe variants observed")
	if reference_hashes.size() == 2:
		_check(String(reference_hashes["1.0.0"]) != String(reference_hashes["2.0.0"]), "recipe replacement provenance differs")
		_check(Array(reference_profiles["1.0.0"]) != Array(reference_profiles["2.0.0"]), "recipe replacement geography differs")

	# Caller contract remains stable for both worlds.
	_check(FINAL_FIELD == ValleyModifier.FIELD_SURFACE_HEIGHT_M, "same final semantic field across replacement")
	_finish()


func _profile(kernel) -> Array:
	var result: Array = []
	for lat in [-60.0, -45.0, -30.0, -15.0, 0.0, 15.0, 30.0, 45.0, 60.0]:
		for lon in [-160.0, -120.0, -80.0, -40.0, 0.0, 40.0, 80.0, 120.0, 160.0]:
			var direction := _direction(lat, lon)
			var point := direction * RADIUS_M
			var context := Context.create(BODY_ID, "geo-scope/g4-swap", 1000.0, 100.0, 0.0, 0.0, 0.0, false, false, MANIFEST_VERSION)
			var query := SurfaceQuery.create(BODY_ID, [point.x, point.y, point.z], [FINAL_FIELD])
			var sample_result: Dictionary = kernel.sample_surface(context, query)
			if not _success(sample_result):
				failures.append("profile sample failed: %s" % sample_result.get("error_code", ""))
				continue
			var sample: Dictionary = sample_result["details"]["sample"]
			var height: float = float(GeoSample.field_value(sample, FINAL_FIELD, NAN))
			_check(is_finite(height), "profile height finite")
			result.append(height)
	return result


func _direction(latitude_deg: float, longitude_deg: float) -> Vector3:
	var lat := deg_to_rad(latitude_deg)
	var lon := deg_to_rad(longitude_deg)
	var cos_lat := cos(lat)
	return Vector3(cos_lat * cos(lon), sin(lat), cos_lat * sin(lon)).normalized()


func _success(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _ok(result: Dictionary, label: String) -> void:
	_check(_success(result), "%s: %s %s" % [label, String(result.get("error_code", "")), result.get("details", {})])


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("G4 provider replacement: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("G4 provider replacement: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)

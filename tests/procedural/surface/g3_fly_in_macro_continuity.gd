extends SceneTree

const PlanetDefinition = preload("res://scripts/simulation/procedural/contracts/planet_definition.gd")
const PlanetEnvironment = preload("res://scripts/simulation/procedural/contracts/planet_environment.gd")
const PlanetRecipe = preload("res://scripts/simulation/procedural/contracts/planet_recipe.gd")
const Context = preload("res://scripts/simulation/procedural/contracts/geo_generation_context.gd")
const SurfaceQuery = preload("res://scripts/simulation/procedural/contracts/geo_surface_query.gd")
const GeoSample = preload("res://scripts/simulation/procedural/contracts/geo_sample.gd")
const BodyFixedPosition = preload("res://scripts/simulation/procedural/contracts/body_fixed_position.gd")
const SurfaceCellKey = preload("res://scripts/simulation/procedural/contracts/surface_cell_key.gd")
const SurfaceLodPolicy = preload("res://scripts/simulation/procedural/contracts/surface_lod_policy.gd")
const CubeSphereAddressing = preload("res://scripts/simulation/procedural/surface/cube_sphere_addressing.gd")
const SurfaceLodSelector = preload("res://scripts/simulation/procedural/surface/surface_lod_selector.gd")
const GeoKernel = preload("res://scripts/simulation/procedural/geo_kernel.gd")
const GeoUtils = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const MacroProvider = preload("res://scripts/simulation/procedural/providers/casual_macro_terrain_provider_v1.gd")

const BODY_ID := "body/procedural-g3-fly"
const RECIPE_ID := "planet-recipe/g3-fly"
const SHAPE_ID := "body-shape/sphere-v1"
const MANIFEST_VERSION := "1.0.0"
const RADIUS_M := 6000000.0
const SEED := 2026080801
const HEIGHT_FIELD := "geo/surface-height-m"
const LATITUDE := 37.25
const LONGITUDE := -122.5

var assertions := 0
var failures: Array[String] = []
var addressing = CubeSphereAddressing.new()


func _init() -> void:
	var provider = MacroProvider.new(SEED, RADIUS_M, 900.0, 600000.0, 4, 0.5, 0.0)
	var environment := PlanetEnvironment.create("planet-environment/g3-fly", "gravity-model/unspecified", "atmosphere-model/unspecified", "temperature-model/unspecified", "fluid-catalog/none", "weathering-model/none", "material-catalog/unspecified", {})
	var recipe := PlanetRecipe.create(RECIPE_ID, "1.0.0", environment, [provider.get_descriptor()])
	var definition := PlanetDefinition.create(BODY_ID, SEED, RECIPE_ID, SHAPE_ID, RADIUS_M, MANIFEST_VERSION)
	var kernel = GeoKernel.new()
	_ok(kernel.configure(definition, recipe, [provider]), "kernel configure")
	var selector = SurfaceLodSelector.new()
	_ok(selector.configure(definition, SurfaceLodPolicy.create(0, 10, 0.45, 0.30, 10.0, 2048)), "selector configure")

	var surface_direction := _direction_from_lat_lon(LATITUDE, LONGITUDE)
	var surface_point := surface_direction * RADIUS_M
	var profile_hash := _profile_hash(kernel, surface_direction)
	_check(not profile_hash.is_empty(), "reference macro profile hash")

	var previous: Array = []
	var approach_max_lods: Array[int] = []
	var altitudes := [50000000.0, 10000000.0, 2000000.0, 500000.0, 100000.0, 50000.0, 10000.0, 2000.0, 500.0, 100.0, 10.0, 0.0]
	for altitude in altitudes:
		var observer_position := surface_direction * (RADIUS_M + float(altitude) + 5.0)
		var observer := BodyFixedPosition.create(BODY_ID, [observer_position.x, observer_position.y, observer_position.z])
		var selected: Dictionary = selector.select_cells(observer, previous)
		_ok(selected, "fly-in selection %.1f" % altitude)
		if not _success(selected):
			continue
		var leaves: Array = selected["details"]["leaves"]
		_check(leaves.size() <= 2048, "fly-in leaf budget")
		_check(_cover_count(surface_direction, leaves) == 1, "surface point covered exactly once")
		approach_max_lods.append(int(selected["details"]["max_selected_lod"]))
		previous = leaves
		_check(_profile_hash(kernel, surface_direction) == profile_hash, "macro profile invariant through fly-in")
		var context := Context.create(BODY_ID, "geo-scope/g3-fly", maxf(1.0, float(altitude) * 0.01 + 1.0), 10.0, 0.0, 0.0, 0.0, false, false, MANIFEST_VERSION)
		var query := SurfaceQuery.create(BODY_ID, [surface_point.x, surface_point.y, surface_point.z], [HEIGHT_FIELD])
		var sample: Dictionary = kernel.sample_surface(context, query)
		_ok(sample, "surface sample through fly-in")
		if _success(sample):
			_check(is_finite(float(GeoSample.field_value(sample["details"]["sample"], HEIGHT_FIELD, NAN))), "surface height finite")

	_check(approach_max_lods.front() <= approach_max_lods.back(), "fly-in refines representation")
	_check(approach_max_lods.back() >= 5, "near surface reaches meaningful LOD")

	for altitude in [10.0, 100.0, 500.0, 2000.0, 10000.0, 50000.0, 100000.0, 500000.0, 2000000.0, 10000000.0, 50000000.0]:
		var observer_position := surface_direction * (RADIUS_M + float(altitude) + 5.0)
		var observer := BodyFixedPosition.create(BODY_ID, [observer_position.x, observer_position.y, observer_position.z])
		var selected: Dictionary = selector.select_cells(observer, previous)
		_ok(selected, "fly-out selection %.1f" % altitude)
		if _success(selected):
			previous = selected["details"]["leaves"]
			_check(_profile_hash(kernel, surface_direction) == profile_hash, "macro profile invariant through fly-out")

	_finish()


func _profile_hash(kernel, center_direction: Vector3) -> String:
	var values: Array = []
	for lat_offset in [-0.50, -0.25, 0.0, 0.25, 0.50]:
		for lon_offset in [-0.50, -0.25, 0.0, 0.25, 0.50]:
			var direction := _direction_from_lat_lon(LATITUDE + lat_offset, LONGITUDE + lon_offset)
			var point := direction * RADIUS_M
			var context := Context.create(BODY_ID, "geo-scope/g3-profile", 1000.0, 100.0, 0.0, 0.0, 0.0, false, false, MANIFEST_VERSION)
			var query := SurfaceQuery.create(BODY_ID, [point.x, point.y, point.z], [HEIGHT_FIELD])
			var result: Dictionary = kernel.sample_surface(context, query)
			if not _success(result):
				return ""
			values.append(float(GeoSample.field_value(result["details"]["sample"], HEIGHT_FIELD, NAN)))
	return GeoUtils.payload_hash({"center": [center_direction.x, center_direction.y, center_direction.z], "heights": values})


func _cover_count(direction: Vector3, leaves: Array) -> int:
	var count := 0
	for leaf in leaves:
		var mapped: Dictionary = addressing.direction_to_cell(BODY_ID, [direction.x, direction.y, direction.z], int(leaf["lod"]))
		if _success(mapped) and SurfaceCellKey.token(mapped["details"]["cell"]) == SurfaceCellKey.token(leaf):
			count += 1
	return count


func _direction_from_lat_lon(latitude_deg: float, longitude_deg: float) -> Vector3:
	var lat := deg_to_rad(latitude_deg)
	var lon := deg_to_rad(longitude_deg)
	var cos_lat := cos(lat)
	return Vector3(cos_lat * cos(lon), sin(lat), cos_lat * sin(lon)).normalized()


func _success(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _ok(result: Dictionary, label: String) -> void:
	_check(_success(result), "%s: %s" % [label, String(result.get("error_code", ""))])


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("G3 fly-in macro continuity: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("G3 fly-in macro continuity: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)

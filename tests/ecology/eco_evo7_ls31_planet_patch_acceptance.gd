extends SceneTree

const PlanetPatch = preload("res://scripts/ecology/shadow/eco_evo7_ls30_planet_patch_v1.gd")
const EnvironmentField = preload("res://scripts/ecology/shadow/eco_evo7_ls31_environment_field_v1.gd")
const ProceduralEarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")

const CENTER_RAW := Vector3(0.41, 0.71, 0.57)
const GRID_SIZE := 32
const CELL_SIZE_M := 16.0
const ENV_SEED := 20260831

var assertions := 0
var failures: Array[String] = []

class FakePipeline:
	extends RefCounted
	func sample(direction: Vector3, _lod_level: int = 0) -> Dictionary:
		var d := direction.normalized()
		var elevation := 180.0 + d.x * 920.0 + d.z * 410.0 + sin(d.y * 23.0) * 85.0
		var moisture := clampf(0.50 + d.z * 0.18 - d.x * 0.10, 0.0, 1.0)
		var river := clampf(0.16 + sin(d.x * 91.0 + d.z * 37.0) * 0.10, 0.0, 1.0)
		var lake := clampf(0.08 + cos(d.z * 67.0) * 0.05, 0.0, 1.0)
		var base_elevation := elevation - 7.0
		return {
			# Deliberately poison the downstream composed surface. LS3.0 must not
			# consume it because the production composer formally reads biome_code.
			"elevation_m": elevation + 10000.0,
			"base_elevation_m": base_elevation,
			"land_mask": 1.0,
			"water_kind": 0,
			"sea_mask": 0.0,
			"river_mask": river,
			"lake_mask": lake,
			"channel_depth_m": 18.0 * river,
			"lake_depth_m": 32.0 * lake,
			"shore_mask": 0.0,
			"temperature_c": 21.0 - maxf(0.0, elevation) * 0.002,
			"moisture": moisture,
			"aridity": clampf(1.0 - moisture, 0.0, 1.0),
			"biome_code": 4,
			"biome_name": "forest",
			"tree_density": 0.92,
		}

class FakeEarth:
	extends RefCounted
	var pipeline = FakePipeline.new()
	var planet_radius_m := 6_371_000.0
	var surface_center_direction := CENTER_RAW.normalized()
	var surface_east := Vector3.UP.cross(surface_center_direction).normalized()
	var surface_north := surface_east.cross(surface_center_direction).normalized()
	func get_canonical_spawn_direction() -> Vector3:
		return surface_center_direction

func _init() -> void:
	var center := CENTER_RAW.normalized()
	var earth = FakeEarth.new()
	var builder = PlanetPatch.new()
	var patch := builder.build(earth, center, GRID_SIZE, CELL_SIZE_M)
	_check(not patch.is_empty(), "LS3.0 patch builds")
	if patch.is_empty():
		_finish(); return
	_check(int(patch.get("grid_size", 0)) == GRID_SIZE, "patch grid size is 32")
	_check(Array(patch.get("cells", [])).size() == GRID_SIZE * GRID_SIZE, "patch contains 1024 cells")
	_check(absf(float(patch.get("patch_width_m", 0.0)) - 512.0) < 1e-9, "patch width is 512 m")
	_check(not String(patch.get("patch_hash", "")).is_empty(), "patch has deterministic hash")
	_check(Vector3(patch["east"]).dot(earth.surface_east) > 1.0 - 1e-12, "patch east aligns with canonical Earth east")
	_check(Vector3(patch["north"]).dot(earth.surface_north) > 1.0 - 1e-12, "patch north aligns with canonical Earth north")
	_check_polar_frame(builder, Vector3(0.0005, 0.999999875, 0.0).normalized(), "north-polar")
	_check_polar_frame(builder, Vector3(0.0005, -0.999999875, 0.0).normalized(), "south-polar")
	var reordered_patch: Dictionary = patch.duplicate(true)
	var reordered_cells: Array = reordered_patch["cells"]
	reordered_cells.reverse()
	reordered_patch["cells"] = reordered_cells
	_check(String(builder.call("_patch_hash", reordered_patch)) == String(patch["patch_hash"]), "cell input order does not change patch hash")

	var replay := builder.build(earth, center, GRID_SIZE, CELL_SIZE_M)
	_check(String(replay.get("patch_hash", "")) == String(patch.get("patch_hash", "")), "same physical source replays identical patch hash")
	var shifted := builder.build(earth, (center + Vector3(0.0002, -0.0001, 0.00015)).normalized(), GRID_SIZE, CELL_SIZE_M)
	_check(String(shifted.get("patch_hash", "")) != String(patch.get("patch_hash", "")), "different patch origin changes physical hash")

	var cells: Array = patch["cells"]
	var mid_x := GRID_SIZE / 2
	var south_mid: Dictionary = cells[(GRID_SIZE / 2 - 1) * GRID_SIZE + mid_x]
	var north_mid: Dictionary = cells[(GRID_SIZE / 2) * GRID_SIZE + mid_x]
	var north_step := Vector3(north_mid["direction"]) - Vector3(south_mid["direction"])
	_check(north_step.dot(earth.surface_north) > 0.0, "increasing patch y moves toward canonical Earth north")
	var first: Dictionary = cells[0]
	var east_neighbor: Dictionary = cells[1]
	var distance := _surface_distance(Vector3(first["direction"]), Vector3(east_neighbor["direction"]), float(patch["planet_radius_m"]))
	_check(absf(distance - CELL_SIZE_M) < 0.01, "adjacent patch cells are contiguous at 16 m spacing")
	for required in ["elevation_m", "base_elevation_m", "land_mask", "water_kind", "river_mask", "lake_mask", "channel_depth_m", "lake_depth_m", "temperature_c", "moisture", "aridity", "slope_ratio"]:
		_check(first.has(required), "physical cell exposes %s" % required)
	for forbidden in ["biome_code", "biome_name", "tree_density"]:
		_check(not first.has(forbidden), "physical cell excludes legacy %s" % forbidden)
	_check(float(first["slope_ratio"]) >= 0.0 and is_finite(float(first["slope_ratio"])), "slope is finite and non-negative")
	var raw_first: Dictionary = earth.pipeline.sample(Vector3(first["direction"]), 0)
	var expected_physical_elevation := (
		float(raw_first["base_elevation_m"])
		- float(raw_first["channel_depth_m"]) * float(raw_first["river_mask"])
		- float(raw_first["lake_depth_m"]) * float(raw_first["lake_mask"])
	)
	_check(absf(float(first["elevation_m"]) - expected_physical_elevation) < 1e-9, "patch elevation is reconstructed from pre-biome relief and hydrology")
	_check(absf(float(first["elevation_m"]) - float(raw_first["elevation_m"])) > 1000.0, "patch ignores poisoned downstream composed elevation")

	var generator = EnvironmentField.new()
	_check(generator.recipe_ids().size() == 3, "LS3.1 exposes three physical recipes")
	for recipe_id in generator.recipe_ids():
		var recipe := generator.get_recipe(recipe_id)
		_check(not recipe.is_empty(), "recipe %s resolves" % recipe_id)
		for key_value in recipe.keys():
			var key := String(key_value).to_lower()
			_check(not key.contains("biome") and not key.contains("plant") and not key.contains("forest") and not key.contains("desert") and not key.contains("wetland"), "recipe key %s is physical-only" % key)

	var field := generator.generate(patch, "WATER_GRADIENT_STRONG", ENV_SEED)
	_check(not field.is_empty(), "LS3.1 environment field builds")
	if field.is_empty():
		_finish(); return
	_check(Array(field["cells"]).size() == GRID_SIZE * GRID_SIZE, "environment field covers all patch cells")
	_check(not String(field.get("field_hash", "")).is_empty(), "environment field has hash")
	var field_replay := generator.generate(patch, "WATER_GRADIENT_STRONG", ENV_SEED)
	_check(String(field_replay["field_hash"]) == String(field["field_hash"]), "same patch recipe and seed replay identically")
	var field_other_seed := generator.generate(patch, "WATER_GRADIENT_STRONG", ENV_SEED + 1)
	_check(String(field_other_seed["field_hash"]) != String(field["field_hash"]), "environment seed changes physical field")
	var field_other_recipe := generator.generate(patch, "RELIEF_DRAINAGE_STRONG", ENV_SEED)
	_check(String(field_other_recipe["field_hash"]) != String(field["field_hash"]), "physical recipe changes field")

	var reversed_patch: Dictionary = patch.duplicate(true)
	var reversed_cells: Array = reversed_patch["cells"]
	reversed_cells.reverse()
	reversed_patch["cells"] = reversed_cells
	var field_reordered := generator.generate(reversed_patch, "WATER_GRADIENT_STRONG", ENV_SEED)
	_check(String(field_reordered["field_hash"]) == String(field["field_hash"]), "cell input order does not change environment field hash")

	var left_moisture := 0.0
	var right_moisture := 0.0
	var left_count := 0
	var right_count := 0
	var min_moisture := 1.0
	var max_moisture := 0.0
	var min_relief := INF
	var max_relief := -INF
	var min_sand := 1.0
	var max_sand := 0.0
	var min_light := 1.0
	var max_light := 0.0
	for value in Array(field["cells"]):
		var cell: Dictionary = value
		var moisture := float(cell["soil_moisture"])
		var sand := float(cell["soil_texture_sand"])
		var clay := float(cell["soil_texture_clay"])
		var loam := float(cell["soil_texture_loam"])
		var light := float(cell["incident_light"])
		var drainage := float(cell["drainage_index"])
		var rainfall := float(cell["rainfall_forcing"])
		_check(moisture >= 0.0 and moisture <= 1.0 and is_finite(moisture), "soil moisture bounded")
		_check(sand >= 0.0 and sand <= 1.0 and clay >= 0.0 and clay <= 1.0 and loam >= 0.0 and loam <= 1.0, "soil fractions bounded")
		_check(sand + clay + loam <= 1.0000001 and sand + clay + loam >= 0.9999999, "soil fractions conserve unit mixture")
		_check(float(cell["soil_water_retention"]) >= 0.0 and float(cell["soil_water_retention"]) <= 1.0, "retention bounded")
		_check(light >= 0.05 and light <= 1.0 and is_finite(light), "incident light bounded")
		_check(drainage >= 0.0 and drainage <= 1.0, "drainage bounded")
		_check(rainfall >= 0.0 and rainfall <= 1.0, "rainfall forcing bounded")
		_check(is_finite(float(cell["temperature_c"])) and is_finite(float(cell["elevation_m"])) and is_finite(float(cell["local_relief_m"])), "unbounded physical values remain finite")
		for forbidden in ["biome_code", "biome_name", "tree_density"]:
			_check(not cell.has(forbidden), "environment cell excludes %s" % forbidden)
		min_moisture = minf(min_moisture, moisture); max_moisture = maxf(max_moisture, moisture)
		min_relief = minf(min_relief, float(cell["local_relief_m"])); max_relief = maxf(max_relief, float(cell["local_relief_m"]))
		min_sand = minf(min_sand, sand); max_sand = maxf(max_sand, sand)
		min_light = minf(min_light, light); max_light = maxf(max_light, light)
		if int(cell["x"]) < 8:
			left_moisture += moisture; left_count += 1
		elif int(cell["x"]) >= 24:
			right_moisture += moisture; right_count += 1
	left_moisture /= float(left_count)
	right_moisture /= float(right_count)
	_check(right_moisture - left_moisture > 0.35, "strong water recipe creates a strong eastward moisture gradient")
	_check(max_moisture - min_moisture > 0.45, "soil moisture has strong spatial variance")
	_check(max_relief - min_relief > 3.0, "local relief varies spatially")
	_check(max_sand - min_sand > 0.05, "soil texture varies spatially")
	_check(max_light - min_light > 0.02, "incident light varies spatially")

	_source_guard()
	_finish()

func _check_polar_frame(builder, center: Vector3, label: String) -> void:
	var production_earth = ProceduralEarthWorld.new()
	var earth_east: Vector3 = production_earth.call("_make_east", center)
	production_earth.free()
	var earth_north := earth_east.cross(center).normalized()
	var basis: Dictionary = builder.call("_tangent_basis", center)
	_check(Vector3(basis["east"]).dot(earth_east) > 1.0 - 1e-12, "%s east matches ProceduralEarthWorld fallback" % label)
	_check(Vector3(basis["north"]).dot(earth_north) > 1.0 - 1e-12, "%s north matches ProceduralEarthWorld fallback" % label)

	var earth = FakeEarth.new()
	earth.surface_center_direction = center
	var polar_patch: Dictionary = builder.build(earth, center, GRID_SIZE, CELL_SIZE_M)
	_check(not polar_patch.is_empty(), "%s patch builds" % label)
	if polar_patch.is_empty():
		return
	var cells: Array = polar_patch["cells"]
	var mid_x := GRID_SIZE / 2
	var south_mid: Dictionary = cells[(GRID_SIZE / 2 - 1) * GRID_SIZE + mid_x]
	var north_mid: Dictionary = cells[(GRID_SIZE / 2) * GRID_SIZE + mid_x]
	var north_step := Vector3(north_mid["direction"]) - Vector3(south_mid["direction"])
	_check(north_step.dot(earth_north) > 0.0, "%s y+1 moves toward ProceduralEarthWorld north" % label)

func _surface_distance(a: Vector3, b: Vector3, radius_m: float) -> float:
	return acos(clampf(a.normalized().dot(b.normalized()), -1.0, 1.0)) * radius_m

func _source_guard() -> void:
	for path in [
		"res://scripts/ecology/shadow/eco_evo7_ls30_planet_patch_v1.gd",
		"res://scripts/ecology/shadow/eco_evo7_ls31_environment_field_v1.gd",
	]:
		var source := FileAccess.get_file_as_string(path).to_lower()
		_check(not source.contains("reproduce_bundle("), "%s has no reproduction call site" % path)
		_check(not source.contains("mutation_seed"), "%s has no mutation seed path" % path)
		_check(not source.contains("fileaccess.open"), "%s has no persistence write path" % path)
		_check(not source.contains("diraccess"), "%s has no directory write path" % path)
		_check(not source.contains("multiplayer"), "%s has no network path" % path)
		_check(not source.contains("biome_code") and not source.contains("biome_name"), "%s has no biome-causality read" % path)

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO7 LS3.0/LS3.1 Planet Patch: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 LS3.0/LS3.1 FAIL: %s" % failure)
	print("ECO.EVO7 LS3.0/LS3.1 Planet Patch: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)

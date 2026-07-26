extends "res://scripts/world/planetary/rules/earth_rule_base.gd"

const BIOME_OCEAN: int = 0
const BIOME_INLAND_WATER: int = 1
const BIOME_DESERT: int = 2
const BIOME_TUNDRA: int = 3
const BIOME_FOREST: int = 4
const BIOME_GRASSLAND: int = 5
const BIOME_ALPINE: int = 6
const BIOME_ROCK: int = 7


func get_requires() -> Array[String]:
	return [
		"water_kind",
		"base_elevation_m",
		"mountain_mask",
		"rockiness",
		"temperature_c",
		"moisture",
		"polar_mask",
		"aridity",
		"land_mask",
	]


func get_writes() -> Array[String]:
	return [
		"biome_code",
		"snow_mask",
		"tree_density",
		"grass_density",
		"rock_density",
	]


func apply(state: Dictionary) -> void:
	var water_kind: int = int(state["water_kind"])
	var elevation: float = float(state["base_elevation_m"])
	var mountain_mask: float = float(state["mountain_mask"])
	var rockiness: float = float(state["rockiness"])
	var temperature: float = float(state["temperature_c"])
	var moisture: float = float(state["moisture"])
	var polar_mask: float = float(state["polar_mask"])
	var aridity: float = float(state["aridity"])
	var land_mask: float = float(state["land_mask"])

	var altitude_snow: float = smoothstep(
		float(get_parameter("snow_start_m", 2500.0)),
		float(get_parameter("snow_full_m", 4700.0)),
		elevation
	)
	var cold_snow: float = 1.0 - smoothstep(-12.0, 2.0, temperature)
	var snow_mask: float = clampf(maxf(altitude_snow, cold_snow * polar_mask), 0.0, 1.0)

	var biome_code: int = BIOME_GRASSLAND
	if water_kind == 1:
		biome_code = BIOME_OCEAN
	elif water_kind == 2 or water_kind == 3:
		biome_code = BIOME_INLAND_WATER
	elif (
		polar_mask > float(get_parameter("tundra_polar_threshold", 0.48))
		or temperature < float(get_parameter("tundra_temperature_c", -5.0))
	):
		biome_code = BIOME_TUNDRA
	elif (
		elevation > float(get_parameter("alpine_elevation_m", 3300.0))
		or mountain_mask > float(get_parameter("alpine_mountain_threshold", 0.74))
	):
		biome_code = BIOME_ALPINE if snow_mask > 0.18 else BIOME_ROCK
	elif (
		aridity > float(get_parameter("desert_aridity_threshold", 0.66))
		and temperature > float(get_parameter("desert_min_temperature_c", 8.0))
	):
		biome_code = BIOME_DESERT
	elif (
		moisture > float(get_parameter("forest_moisture_threshold", 0.50))
		and temperature > float(get_parameter("forest_min_temperature_c", -3.0))
	):
		biome_code = BIOME_FOREST
	else:
		biome_code = BIOME_GRASSLAND

	var tree_density: float = 0.0
	var grass_density: float = 0.0
	var rock_density: float = 0.0
	match biome_code:
		BIOME_FOREST:
			tree_density = clampf((moisture - 0.42) * 1.65, 0.18, 0.92)
			grass_density = clampf(0.32 + moisture * 0.48, 0.0, 0.88)
			rock_density = rockiness * 0.34
		BIOME_GRASSLAND:
			tree_density = clampf((moisture - 0.36) * 0.34, 0.0, 0.16)
			grass_density = clampf(0.50 + moisture * 0.42, 0.0, 0.95)
			rock_density = rockiness * 0.28
		BIOME_DESERT:
			rock_density = clampf(0.34 + aridity * 0.48 + rockiness * 0.28, 0.0, 1.0)
		BIOME_TUNDRA:
			rock_density = clampf(0.48 + polar_mask * 0.42 + rockiness * 0.35, 0.0, 1.0)
		BIOME_ALPINE, BIOME_ROCK:
			rock_density = clampf(0.62 + rockiness * 0.46, 0.0, 1.0)

	tree_density *= land_mask * (1.0 - snow_mask)
	grass_density *= land_mask * (1.0 - snow_mask)
	if snow_mask > float(get_parameter("tree_snow_cutoff", 0.22)):
		tree_density = 0.0
	if snow_mask > float(get_parameter("grass_snow_cutoff", 0.16)):
		grass_density = 0.0

	state["biome_code"] = biome_code
	state["snow_mask"] = snow_mask
	state["tree_density"] = clampf(tree_density, 0.0, 1.0)
	state["grass_density"] = clampf(grass_density, 0.0, 1.0)
	state["rock_density"] = clampf(rock_density, 0.0, 1.0)

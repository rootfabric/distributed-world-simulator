extends "res://scripts/world/planetary/rules/earth_rule_base.gd"

const WATER_NONE: int = 0
const WATER_OCEAN: int = 1
const WATER_RIVER: int = 2
const WATER_LAKE: int = 3

var river_noise_a := FastNoiseLite.new()
var river_noise_b := FastNoiseLite.new()
var basin_noise := FastNoiseLite.new()
var shore_noise := FastNoiseLite.new()


func configure() -> void:
	river_noise_a.seed = world_seed + 211
	river_noise_a.frequency = 1.0
	river_noise_a.noise_type = FastNoiseLite.TYPE_SIMPLEX
	river_noise_a.fractal_type = FastNoiseLite.FRACTAL_FBM
	river_noise_a.fractal_octaves = 4

	river_noise_b.seed = world_seed + 223
	river_noise_b.frequency = 1.0
	river_noise_b.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	river_noise_b.fractal_type = FastNoiseLite.FRACTAL_FBM
	river_noise_b.fractal_octaves = 3

	basin_noise.seed = world_seed + 251
	basin_noise.frequency = 1.0
	basin_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	basin_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	basin_noise.fractal_octaves = 4

	shore_noise.seed = world_seed + 277
	shore_noise.frequency = 1.0
	shore_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	shore_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	shore_noise.fractal_octaves = 3


func get_requires() -> Array[String]:
	return [
		"direction",
		"land_mask",
		"base_elevation_m",
		"continentalness",
		"mountain_mask",
	]


func get_writes() -> Array[String]:
	return [
		"water_kind",
		"sea_mask",
		"river_mask",
		"lake_mask",
		"channel_depth_m",
		"lake_depth_m",
		"shore_mask",
	]


func apply(state: Dictionary) -> void:
	var direction: Vector3 = state["direction"]
	var land_mask: float = float(state["land_mask"])
	var base_elevation: float = float(state["base_elevation_m"])
	var mountain_mask: float = float(state["mountain_mask"])
	var continentalness: float = float(state["continentalness"])

	var sea_mask: float = 1.0 - smoothstep(-180.0, 45.0, base_elevation)
	sea_mask = maxf(sea_mask, 1.0 - land_mask)

	var river_field: float = (
		river_noise_a.get_noise_3d(
			direction.x * float(get_parameter("river_scale", 31.0)),
			direction.y * float(get_parameter("river_scale", 31.0)),
			direction.z * float(get_parameter("river_scale", 31.0))
		) * 0.68
		+ river_noise_b.get_noise_3d(
			direction.x * 13.0 + 9.0,
			direction.y * 13.0 - 4.0,
			direction.z * 13.0 + 17.0
		) * 0.32
	)
	var channel_distance: float = absf(river_field)
	var river_mask: float = 1.0 - smoothstep(
		float(get_parameter("river_core_width", 0.008)),
		float(get_parameter("river_outer_width", 0.060)),
		channel_distance
	)
	river_mask *= land_mask
	river_mask *= smoothstep(20.0, 850.0, base_elevation)
	river_mask *= 1.0 - smoothstep(0.68, 0.96, mountain_mask)
	river_mask *= smoothstep(-0.06, 0.30, continentalness)

	var basin_field: float = basin_noise.get_noise_3d(
		direction.x * 19.0 - 14.0,
		direction.y * 19.0 + 6.0,
		direction.z * 19.0 + 2.0
	)
	var lake_core: float = 1.0 - smoothstep(-0.74, -0.52, basin_field)
	var lake_altitude_band: float = smoothstep(35.0, 180.0, base_elevation)
	lake_altitude_band *= 1.0 - smoothstep(850.0, 1550.0, base_elevation)
	var lake_mask: float = lake_core * lake_altitude_band * land_mask
	lake_mask *= 1.0 - mountain_mask * 0.72

	var channel_depth: float = lerpf(4.0, 42.0, clampf(base_elevation / 2200.0, 0.0, 1.0))
	channel_depth *= river_mask
	var lake_depth: float = lerpf(8.0, 95.0, lake_core) * lake_mask

	var shore_field: float = shore_noise.get_noise_3d(
		direction.x * 80.0,
		direction.y * 80.0,
		direction.z * 80.0
	)
	var shore_mask: float = 1.0 - smoothstep(0.0, 260.0, absf(base_elevation))
	shore_mask *= clampf(0.78 + shore_field * 0.22, 0.0, 1.0)

	var water_kind: int = WATER_NONE
	if sea_mask > 0.52:
		water_kind = WATER_OCEAN
	elif lake_mask > float(get_parameter("lake_water_threshold", 0.42)):
		water_kind = WATER_LAKE
	elif river_mask > float(get_parameter("river_water_threshold", 0.34)):
		water_kind = WATER_RIVER

	state["water_kind"] = water_kind
	state["sea_mask"] = clampf(sea_mask, 0.0, 1.0)
	state["river_mask"] = clampf(river_mask, 0.0, 1.0)
	state["lake_mask"] = clampf(lake_mask, 0.0, 1.0)
	state["channel_depth_m"] = channel_depth
	state["lake_depth_m"] = lake_depth
	state["shore_mask"] = clampf(shore_mask, 0.0, 1.0)

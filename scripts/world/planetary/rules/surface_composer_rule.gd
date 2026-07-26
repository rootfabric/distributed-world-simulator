extends "res://scripts/world/planetary/rules/earth_rule_base.gd"

var regional_noise := FastNoiseLite.new()
var meso_noise := FastNoiseLite.new()
var micro_noise := FastNoiseLite.new()


func configure() -> void:
	_configure_noise(regional_noise, world_seed + 401, 4, FastNoiseLite.FRACTAL_FBM)
	_configure_noise(meso_noise, world_seed + 433, 4, FastNoiseLite.FRACTAL_RIDGED)
	_configure_noise(micro_noise, world_seed + 467, 3, FastNoiseLite.FRACTAL_FBM)


func _configure_noise(
	noise: FastNoiseLite,
	seed_value: int,
	octaves: int,
	fractal_type: int
) -> void:
	noise.seed = seed_value
	noise.frequency = 1.0
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.fractal_type = fractal_type
	noise.fractal_octaves = octaves
	noise.fractal_gain = 0.50


func get_requires() -> Array[String]:
	return [
		"direction",
		"base_elevation_m",
		"river_mask",
		"lake_mask",
		"channel_depth_m",
		"lake_depth_m",
		"shore_mask",
		"water_kind",
		"biome_code",
		"snow_mask",
		"moisture",
		"rockiness",
	]


func get_writes() -> Array[String]:
	return ["elevation_m", "surface_color"]


func apply(state: Dictionary) -> void:
	var direction: Vector3 = state["direction"]
	var base_elevation: float = float(state["base_elevation_m"])
	var river_mask: float = float(state["river_mask"])
	var lake_mask: float = float(state["lake_mask"])
	var channel_depth: float = float(state["channel_depth_m"])
	var lake_depth: float = float(state["lake_depth_m"])
	var shore_mask: float = float(state["shore_mask"])
	var water_kind: int = int(state["water_kind"])
	var biome_code: int = int(state["biome_code"])
	var snow_mask: float = float(state["snow_mask"])
	var moisture: float = float(state["moisture"])
	var rockiness: float = float(state["rockiness"])
	var lod_level: int = int(state.get("lod_level", 0))

	var regional_scale: float = float(get_parameter("regional_texture_scale", 1050.0))
	var regional_texture: float = regional_noise.get_noise_3d(
		direction.x * regional_scale,
		direction.y * regional_scale,
		direction.z * regional_scale
	)
	var meso_texture: float = 0.0
	var micro_texture: float = 0.0
	if lod_level <= 1:
		var meso_scale: float = float(get_parameter("meso_texture_scale", 6200.0))
		meso_texture = meso_noise.get_noise_3d(
			direction.x * meso_scale,
			direction.y * meso_scale,
			direction.z * meso_scale
		)
	if lod_level == 0:
		var micro_scale: float = float(get_parameter("micro_texture_scale", 30000.0))
		micro_texture = micro_noise.get_noise_3d(
			direction.x * micro_scale,
			direction.y * micro_scale,
			direction.z * micro_scale
		)

	var elevation: float = base_elevation
	elevation -= channel_depth * river_mask
	elevation -= lake_depth * lake_mask
	if water_kind == 1:
		elevation -= absf(regional_texture) * 42.0
	elif water_kind == 2 or water_kind == 3:
		elevation -= 1.5 + absf(micro_texture) * 1.8
	else:
		var regional_amplitude: float = float(get_parameter("regional_relief_m", 135.0))
		var meso_amplitude: float = float(get_parameter("meso_relief_m", 38.0))
		var micro_amplitude: float = float(get_parameter("micro_relief_m", 6.0))
		elevation += regional_texture * regional_amplitude * lerpf(0.44, 1.20, rockiness)
		elevation += meso_texture * meso_amplitude * lerpf(0.42, 1.45, rockiness)
		elevation += micro_texture * micro_amplitude * lerpf(0.35, 1.55, rockiness)

	var color := Color(0.30, 0.48, 0.18)
	match biome_code:
		0:
			color = Color(0.018, 0.115, 0.235).lerp(Color(0.015, 0.24, 0.40), shore_mask)
		1:
			color = Color(0.025, 0.25, 0.38).lerp(Color(0.055, 0.34, 0.44), shore_mask)
		2:
			color = Color(0.48, 0.39, 0.24).lerp(Color(0.64, 0.52, 0.31), regional_texture * 0.5 + 0.5)
		3:
			color = Color(0.63, 0.67, 0.68).lerp(Color(0.91, 0.94, 0.96), snow_mask)
		4:
			color = Color(0.055, 0.21, 0.075).lerp(Color(0.12, 0.31, 0.10), regional_texture * 0.5 + 0.5)
		5:
			color = Color(0.20, 0.40, 0.115).lerp(Color(0.39, 0.52, 0.16), moisture * 0.55)
		6:
			color = Color(0.34, 0.35, 0.36).lerp(Color(0.96, 0.97, 0.99), snow_mask)
		7:
			color = Color(0.29, 0.28, 0.27).lerp(Color(0.48, 0.46, 0.43), regional_texture * 0.5 + 0.5)

	if snow_mask > 0.0 and biome_code != 0 and biome_code != 1:
		var snow_color := Color(0.90, 0.94, 0.98).lerp(
			Color(1.0, 1.0, 1.0),
			micro_texture * 0.5 + 0.5
		)
		color = color.lerp(snow_color, snow_mask)
	if water_kind == 0:
		color = color.lightened(micro_texture * 0.035)

	state["elevation_m"] = elevation
	state["surface_color"] = color

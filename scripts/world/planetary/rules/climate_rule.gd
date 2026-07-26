extends "res://scripts/world/planetary/rules/earth_rule_base.gd"

var temperature_noise := FastNoiseLite.new()
var moisture_noise := FastNoiseLite.new()
var rain_shadow_noise := FastNoiseLite.new()


func configure() -> void:
	temperature_noise.seed = world_seed + 307
	temperature_noise.frequency = 1.0
	temperature_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	temperature_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	temperature_noise.fractal_octaves = 3

	moisture_noise.seed = world_seed + 331
	moisture_noise.frequency = 1.0
	moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	moisture_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	moisture_noise.fractal_octaves = 5

	rain_shadow_noise.seed = world_seed + 353
	rain_shadow_noise.frequency = 1.0
	rain_shadow_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	rain_shadow_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	rain_shadow_noise.fractal_octaves = 3


func get_requires() -> Array[String]:
	return [
		"direction",
		"latitude_rad",
		"base_elevation_m",
		"continentalness",
		"mountain_mask",
		"river_mask",
		"lake_mask",
		"sea_mask",
	]


func get_writes() -> Array[String]:
	return [
		"temperature_c",
		"moisture",
		"polar_mask",
		"aridity",
	]


func apply(state: Dictionary) -> void:
	var direction: Vector3 = state["direction"]
	var latitude: float = absf(float(state["latitude_rad"])) / (PI * 0.5)
	var elevation: float = maxf(0.0, float(state["base_elevation_m"]))
	var mountain_mask: float = float(state["mountain_mask"])
	var continentalness: float = float(state["continentalness"])
	var river_mask: float = float(state["river_mask"])
	var lake_mask: float = float(state["lake_mask"])
	var sea_mask: float = float(state["sea_mask"])

	var temp_variation: float = temperature_noise.get_noise_3d(
		direction.x * 5.0,
		direction.y * 5.0,
		direction.z * 5.0
	) * 8.0
	var temperature: float = lerpf(
		float(get_parameter("equator_temperature_c", 31.0)),
		float(get_parameter("pole_temperature_c", -31.0)),
		pow(latitude, float(get_parameter("latitude_exponent", 1.25)))
	)
	temperature -= elevation * float(get_parameter("lapse_rate_c_per_m", 0.0062))
	temperature += temp_variation

	var moisture_field: float = moisture_noise.get_noise_3d(
		direction.x * 8.0 + 5.0,
		direction.y * 8.0 - 3.0,
		direction.z * 8.0 + 11.0
	)
	var ocean_proximity: float = 1.0 - smoothstep(-0.08, 0.72, continentalness)
	var moisture: float = moisture_field * 0.40 + 0.48
	moisture += ocean_proximity * 0.25
	moisture += river_mask * 0.24 + lake_mask * 0.34 + sea_mask * 0.20
	var rain_shadow: float = rain_shadow_noise.get_noise_3d(
		direction.x * 17.0,
		direction.y * 17.0,
		direction.z * 17.0
	)
	moisture -= mountain_mask * smoothstep(-0.20, 0.70, rain_shadow) * 0.32
	moisture = clampf(moisture, 0.0, 1.0)

	var polar_mask: float = smoothstep(0.58, 0.88, latitude)
	var heat: float = smoothstep(-6.0, 28.0, temperature)
	var aridity: float = clampf((1.0 - moisture) * 0.82 + heat * 0.22, 0.0, 1.0)

	state["temperature_c"] = temperature
	state["moisture"] = moisture
	state["polar_mask"] = polar_mask
	state["aridity"] = aridity

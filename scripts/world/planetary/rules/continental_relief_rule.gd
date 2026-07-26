extends "res://scripts/world/planetary/rules/earth_rule_base.gd"

var continent_noise := FastNoiseLite.new()
var continent_detail_noise := FastNoiseLite.new()
var mountain_selector_noise := FastNoiseLite.new()
var mountain_noise := FastNoiseLite.new()
var ridge_detail_noise := FastNoiseLite.new()
var hills_noise := FastNoiseLite.new()
var local_relief_noise := FastNoiseLite.new()
var plains_noise := FastNoiseLite.new()


func configure() -> void:
	_configure_fbm(continent_noise, world_seed + 11, 5, 0.52, true)
	_configure_fbm(continent_detail_noise, world_seed + 37, 4, 0.50, false)
	_configure_fbm(mountain_selector_noise, world_seed + 59, 3, 0.52, true)
	_configure_fbm(mountain_noise, world_seed + 71, 5, 0.55, false)
	_configure_fbm(ridge_detail_noise, world_seed + 101, 4, 0.53, false)
	_configure_fbm(hills_noise, world_seed + 127, 4, 0.50, true)
	_configure_fbm(local_relief_noise, world_seed + 149, 3, 0.48, false)
	_configure_fbm(plains_noise, world_seed + 137, 3, 0.50, true)


func _configure_fbm(
	noise: FastNoiseLite,
	seed_value: int,
	octaves: int,
	gain: float,
	smooth: bool
) -> void:
	noise.seed = seed_value
	noise.frequency = 1.0
	noise.noise_type = (
		FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		if smooth
		else FastNoiseLite.TYPE_SIMPLEX
	)
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	noise.fractal_gain = gain


func get_requires() -> Array[String]:
	return ["direction"]


func get_writes() -> Array[String]:
	return [
		"continentalness",
		"land_mask",
		"base_elevation_m",
		"mountain_mask",
		"plains_mask",
		"rockiness",
		"slope_hint_deg",
		"mountain_elevation_m",
		"hill_elevation_m",
		"local_relief_m",
	]


func apply(state: Dictionary) -> void:
	var direction: Vector3 = state["direction"]
	var continent_scale: float = float(get_parameter("continent_scale", 1.45))
	var macro: float = continent_noise.get_noise_3d(
		direction.x * continent_scale,
		direction.y * continent_scale,
		direction.z * continent_scale
	)
	var detail: float = continent_detail_noise.get_noise_3d(
		direction.x * 5.2 + 13.0,
		direction.y * 5.2 - 7.0,
		direction.z * 5.2 + 3.0
	)
	var continentalness: float = clampf(macro * 0.88 + detail * 0.24, -1.0, 1.0)
	var land_mask: float = smoothstep(
		float(get_parameter("coast_low", -0.12)),
		float(get_parameter("coast_high", 0.055)),
		continentalness
	)

	# Mountain chains are selected by a broad tectonic field, while the actual
	# ridges come from zero-crossings of a higher-frequency field. This creates
	# long ranges instead of one almost constant value across a 24 km patch.
	var selector_scale: float = float(get_parameter("mountain_selector_scale", 4.2))
	var selector_field: float = mountain_selector_noise.get_noise_3d(
		direction.x * selector_scale - 4.0,
		direction.y * selector_scale + 8.0,
		direction.z * selector_scale + 2.0
	)
	var tectonic_selector: float = smoothstep(-0.18, 0.54, selector_field)
	var mountain_scale: float = float(get_parameter("mountain_scale", 13.0))
	var mountain_field: float = mountain_noise.get_noise_3d(
		direction.x * mountain_scale,
		direction.y * mountain_scale,
		direction.z * mountain_scale
	)
	var ridge_line: float = pow(clampf(1.0 - absf(mountain_field), 0.0, 1.0), 2.25)
	var mountain_region: float = smoothstep(0.22, 0.78, ridge_line)
	mountain_region *= lerpf(0.22, 1.0, tectonic_selector)
	mountain_region *= smoothstep(-0.04, 0.24, continentalness)
	mountain_region *= land_mask

	var ridge_scale: float = float(get_parameter("ridge_detail_scale", 86.0))
	var ridge_field: float = ridge_detail_noise.get_noise_3d(
		direction.x * ridge_scale + 11.0,
		direction.y * ridge_scale - 17.0,
		direction.z * ridge_scale + 5.0
	)
	var ridge_detail: float = pow(
		clampf(1.0 - absf(ridge_field), 0.0, 1.0),
		3.1
	)
	var mountain_mask: float = clampf(
		mountain_region * (0.72 + ridge_detail * 0.62),
		0.0,
		1.0
	)

	var plain_field: float = plains_noise.get_noise_3d(
		direction.x * 12.0,
		direction.y * 12.0,
		direction.z * 12.0
	)
	var plains_mask: float = land_mask * (1.0 - mountain_mask)
	plains_mask *= smoothstep(-0.58, 0.34, plain_field)

	var ocean_depth: float = lerpf(
		float(get_parameter("ocean_depth_m", -6200.0)),
		float(get_parameter("continental_shelf_m", -180.0)),
		smoothstep(-0.72, -0.12, continentalness)
	)
	var continental_height: float = lerpf(
		65.0,
		1050.0,
		smoothstep(-0.10, 0.72, continentalness)
	)

	var mountain_height: float = pow(mountain_mask, 1.48) * float(
		get_parameter("mountain_height_m", 7600.0)
	)
	mountain_height += ridge_detail * mountain_mask * float(
		get_parameter("ridge_height_m", 1850.0)
	)
	var foothill_mask: float = smoothstep(0.06, 0.58, mountain_region)
	foothill_mask *= 1.0 - smoothstep(0.64, 0.96, mountain_mask)
	var foothill_height: float = foothill_mask * maxf(0.0, detail) * float(
		get_parameter("foothill_height_m", 780.0)
	)

	# These two bands are deliberately expressed in planet-space directions.
	# Their configured scales correspond roughly to 15 km and 3 km features,
	# so a local surface patch no longer collapses into a single flat plane.
	var hill_scale: float = float(get_parameter("hill_scale", 430.0))
	var hill_field: float = hills_noise.get_noise_3d(
		direction.x * hill_scale,
		direction.y * hill_scale,
		direction.z * hill_scale
	)
	var hill_envelope: float = land_mask * (1.0 - mountain_mask * 0.70)
	var hill_elevation: float = hill_field * float(
		get_parameter("hill_height_m", 360.0)
	) * lerpf(0.42, 1.0, 1.0 - plains_mask * 0.55) * hill_envelope

	var local_scale: float = float(get_parameter("local_relief_scale", 2200.0))
	var local_field: float = local_relief_noise.get_noise_3d(
		direction.x * local_scale + 29.0,
		direction.y * local_scale - 41.0,
		direction.z * local_scale + 7.0
	)
	var local_relief: float = local_field * float(
		get_parameter("local_relief_height_m", 115.0)
	) * land_mask * lerpf(0.72, 1.65, mountain_mask)

	var rolling_relief: float = plain_field * lerpf(35.0, 165.0, 1.0 - plains_mask)
	var land_elevation: float = (
		continental_height
		+ mountain_height
		+ foothill_height
		+ hill_elevation
		+ local_relief
		+ rolling_relief
	)
	var base_elevation: float = lerpf(ocean_depth, land_elevation, land_mask)

	var relief_activity: float = clampf(
		absf(hill_field) * 0.26
		+ absf(local_field) * 0.18
		+ ridge_detail * mountain_mask * 0.74,
		0.0,
		1.0
	)
	state["continentalness"] = continentalness
	state["land_mask"] = land_mask
	state["base_elevation_m"] = base_elevation
	state["mountain_mask"] = mountain_mask
	state["plains_mask"] = plains_mask
	state["rockiness"] = clampf(
		mountain_mask * 0.78 + ridge_detail * mountain_mask * 0.42 + relief_activity * 0.16,
		0.0,
		1.0
	)
	state["slope_hint_deg"] = clampf(
		mountain_mask * 42.0
		+ ridge_detail * mountain_mask * 23.0
		+ absf(hill_field) * 8.0
		+ absf(local_field) * 5.0,
		0.0,
		72.0
	)
	state["mountain_elevation_m"] = mountain_height + foothill_height
	state["hill_elevation_m"] = hill_elevation
	state["local_relief_m"] = local_relief

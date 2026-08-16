extends RefCounted

const VIS20_EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const VIS20_ContinuousModel = preload("res://scripts/labs/ecology/eco_vis1_8b_continuous_turnover_model.gd")

const SCHEMA := "distributed_world_simulator.ecology.vis2_0_environment_experiment.v1"
const VERSION := "1.0.0"
const PROFILE_BASELINE := "BASELINE"
const PROFILE_DROUGHT := "DROUGHT"
const PROFILE_FLOOD := "FLOOD"
const PROFILE_NUTRIENT := "NUTRIENT_PULSE"
const PROFILE_SHADE := "SHADE"
const PROFILES: Array[String] = [
	PROFILE_BASELINE,
	PROFILE_DROUGHT,
	PROFILE_FLOOD,
	PROFILE_NUTRIENT,
	PROFILE_SHADE,
]

static func normalize_profile(profile: String) -> String:
	var normalized := profile.strip_edges().to_upper()
	if normalized in PROFILES:
		return normalized
	return PROFILE_BASELINE

static func normalize_intensity(profile: String, intensity: float) -> float:
	if normalize_profile(profile) == PROFILE_BASELINE:
		return 0.0
	return clampf(intensity, 0.10, 1.0)

static func apply(base_sample: Dictionary, profile: String, intensity: float, epoch: int) -> Dictionary:
	if not bool(VIS20_EnvironmentSample.validate(base_sample).get("success", false)):
		return {}
	var normalized_profile := normalize_profile(profile)
	var normalized_intensity := normalize_intensity(normalized_profile, intensity)
	if normalized_profile == PROFILE_BASELINE or normalized_intensity <= 0.000001:
		return base_sample.duplicate(true)
	var temperature := float(base_sample.get("temperature_c", 0.0))
	var moisture := float(base_sample.get("soil_moisture", 0.0))
	var sunlight := float(base_sample.get("sunlight", 0.0))
	var nutrients := float(base_sample.get("nutrients", 0.0))
	var flood := float(base_sample.get("flood_frequency", 0.0))
	match normalized_profile:
		PROFILE_DROUGHT:
			temperature += 6.0 * normalized_intensity
			moisture *= 1.0 - 0.78 * normalized_intensity
			flood *= 1.0 - 0.92 * normalized_intensity
			sunlight += 0.08 * normalized_intensity
			nutrients *= 1.0 - 0.18 * normalized_intensity
		PROFILE_FLOOD:
			temperature -= 1.5 * normalized_intensity
			moisture += (1.0 - moisture) * 0.76 * normalized_intensity
			flood += (1.0 - flood) * 0.90 * normalized_intensity
			sunlight *= 1.0 - 0.08 * normalized_intensity
			nutrients += (1.0 - nutrients) * 0.08 * normalized_intensity
		PROFILE_NUTRIENT:
			nutrients += (1.0 - nutrients) * 0.88 * normalized_intensity
			moisture += (1.0 - moisture) * 0.08 * normalized_intensity
		PROFILE_SHADE:
			sunlight *= 1.0 - 0.74 * normalized_intensity
			moisture += (1.0 - moisture) * 0.14 * normalized_intensity
			temperature -= 2.5 * normalized_intensity
	moisture = clampf(moisture, 0.0, 1.0)
	sunlight = clampf(sunlight, 0.0, 1.0)
	nutrients = clampf(nutrients, 0.0, 1.0)
	flood = clampf(flood, 0.0, 1.0)
	var revision := "%s/vis2.0/%s/i%.2f" % [
		String(base_sample.get("environment_revision", "baseline")),
		normalized_profile.to_lower(),
		normalized_intensity,
	]
	return VIS20_EnvironmentSample.create(
		float(base_sample.get("world_x_m", 0.0)),
		float(base_sample.get("world_z_m", 0.0)),
		temperature,
		moisture,
		sunlight,
		nutrients,
		flood,
		int(base_sample.get("seed", 0)),
		revision
	)

static func delta(base_sample: Dictionary, experimental_sample: Dictionary) -> Dictionary:
	if not bool(VIS20_EnvironmentSample.validate(base_sample).get("success", false)):
		return {}
	if not bool(VIS20_EnvironmentSample.validate(experimental_sample).get("success", false)):
		return {}
	return {
		"temperature_c": float(experimental_sample.get("temperature_c", 0.0)) - float(base_sample.get("temperature_c", 0.0)),
		"soil_moisture": float(experimental_sample.get("soil_moisture", 0.0)) - float(base_sample.get("soil_moisture", 0.0)),
		"sunlight": float(experimental_sample.get("sunlight", 0.0)) - float(base_sample.get("sunlight", 0.0)),
		"nutrients": float(experimental_sample.get("nutrients", 0.0)) - float(base_sample.get("nutrients", 0.0)),
		"flood_frequency": float(experimental_sample.get("flood_frequency", 0.0)) - float(base_sample.get("flood_frequency", 0.0)),
	}

static func profile_color(profile: String, intensity: float = 1.0) -> Color:
	var amount := clampf(intensity, 0.0, 1.0)
	match normalize_profile(profile):
		PROFILE_DROUGHT:
			return Color(1.0, 0.55 + 0.20 * (1.0 - amount), 0.18, 1.0)
		PROFILE_FLOOD:
			return Color(0.22, 0.62, 1.0, 1.0)
		PROFILE_NUTRIENT:
			return Color(0.38, 1.0, 0.38, 1.0)
		PROFILE_SHADE:
			return Color(0.58, 0.66, 0.86, 1.0)
	return Color(0.82, 0.86, 0.90, 1.0)

static func truncate_future(model: RefCounted, generation: int) -> Dictionary:
	var continuous := model as VIS20_ContinuousModel
	if continuous == null or generation < 0:
		return {"success": false, "removed_generations": 0}
	if not continuous.generation_cache.has(generation):
		return {"success": false, "removed_generations": 0}
	var removed := 0
	var cache_keys := continuous.generation_cache.keys()
	for generation_variant in cache_keys:
		var cached_generation := int(generation_variant)
		if cached_generation > generation:
			continuous.generation_cache.erase(generation_variant)
			removed += 1
	var stat_keys := continuous.generation_stats.keys()
	for generation_variant in stat_keys:
		if int(generation_variant) > generation:
			continuous.generation_stats.erase(generation_variant)
	var trimmed_history: Array[Dictionary] = []
	for point in continuous.history_points:
		if int(point.get("generation", 0)) <= generation:
			trimmed_history.append(point.duplicate(true))
	continuous.history_points = trimmed_history
	continuous.max_cached_generation = generation
	var current_stats: Dictionary = continuous.generation_stats.get(generation, {})
	continuous.cumulative_births = int(current_stats.get("cumulative_births", 0))
	continuous.cumulative_deaths = int(current_stats.get("cumulative_deaths", 0))
	continuous.cumulative_survivals = int(current_stats.get("cumulative_survivals", 0))
	continuous.peak_visual_count = continuous.founder_count
	for point in trimmed_history:
		continuous.peak_visual_count = maxi(continuous.peak_visual_count, int(point.get("visual_count", 0)))
	var floor_generation := 0
	for generation_variant in continuous.generation_cache.keys():
		var cached_generation := int(generation_variant)
		if cached_generation <= 0:
			continue
		if floor_generation == 0 or cached_generation < floor_generation:
			floor_generation = cached_generation
	continuous.cache_floor_generation = floor_generation
	return {
		"success": true,
		"generation": generation,
		"removed_generations": removed,
		"history_points": continuous.history_points.size(),
		"cache_floor_generation": continuous.cache_floor_generation,
	}

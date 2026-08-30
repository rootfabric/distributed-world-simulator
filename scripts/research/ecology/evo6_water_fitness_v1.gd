extends RefCounted

## ECO.EVO6-WATER/R1 deterministic water availability + genome fitness model.
## Consumes existing water observations and plant genome traits only.

const MIN_FITNESS := 0.05
const MAX_FITNESS := 4.0
const DEFAULT_SOIL_MOISTURE_PPM := 400000.0


static func water_availability(site: Dictionary) -> float:
	var features: Dictionary = site.get("features", site)
	var conditions: Dictionary = site.get("effective_conditions", site)
	if bool(features.get("in_water", false)):
		return 1.0
	var moisture := clampf(float(conditions.get("soil_moisture_ppm", DEFAULT_SOIL_MOISTURE_PPM)) / 1000000.0, 0.0, 1.0)
	if not features.has("water_dist_m"):
		return moisture
	var distance := maxf(0.0, float(features["water_dist_m"]))
	var proximity := exp(-distance / 3.0)
	return clampf(maxf(moisture, 0.15 + 0.75 * proximity), 0.0, 1.0)


static func evaluate(genome: Dictionary, site: Dictionary) -> Dictionary:
	var features: Dictionary = site.get("features", site)
	var surface_water := water_availability(site)
	var preference := clampf(float(genome.get("water_preference", 0.5)), 0.0, 1.0)
	var tolerance := clampf(float(genome.get("water_tolerance_width", 0.30)), 0.02, 1.0)
	var root_depth := maxf(0.05, float(genome.get("root_depth_m", 0.85)))

	var dryness := clampf((0.45 - surface_water) / 0.45, 0.0, 1.0)
	var root_depth_factor := clampf((root_depth - 0.35) / 2.65, 0.0, 1.0)
	var root_water_gain := dryness * root_depth_factor * 0.18
	var effective_water := clampf(surface_water + root_water_gain, 0.0, 1.0)

	var delta := absf(effective_water - preference)
	var tolerance_half_width := maxf(0.02, tolerance * 0.5)
	var stress := maxf(0.0, delta - tolerance_half_width)
	var match_score := exp(-12.0 * stress * stress)
	var fitness := 0.05 + 2.95 * match_score

	if bool(features.get("in_water", false)):
		fitness *= 1.20 if preference >= 0.65 else 0.08

	if surface_water < 0.25:
		if root_depth < 0.70:
			fitness *= 0.30
		else:
			fitness *= 1.0 + minf(0.80, (root_depth - 0.70) * 0.32)

	fitness = clampf(fitness, MIN_FITNESS, MAX_FITNESS)
	return {
		"fitness": snappedf(fitness, 0.000000001),
		"surface_water": snappedf(surface_water, 0.000000001),
		"effective_water": snappedf(effective_water, 0.000000001),
		"water_stress": snappedf(stress, 0.000000001),
		"root_water_gain": snappedf(root_water_gain, 0.000000001),
	}

extends RefCounted

const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const MorphologyProfile = preload("res://scripts/research/ecology/plant_morphology_resource_profile_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.relative_vertical_light_competition.v1"
const VERSION := "1.0.0"
const CONTEXT_SCHEMA := "distributed_world_simulator.ecology.canopy_competition_context.v1"
const EPSILON := 0.000000000001

static func create_context(canopy_overlap: float, local_density: float, label: String = "") -> Dictionary:
	if not is_finite(canopy_overlap) or not is_finite(local_density):
		return {}
	if canopy_overlap < 0.0 or canopy_overlap > 1.0 or local_density < 0.0 or local_density > 1.0:
		return {}
	var result := {
		"schema": CONTEXT_SCHEMA,
		"version": VERSION,
		"canopy_overlap": canopy_overlap,
		"local_density": local_density,
		"label": label,
	}
	result["checksum"] = _context_checksum(result)
	return result

static func validate_context(context: Dictionary) -> bool:
	if String(context.get("schema", "")) != CONTEXT_SCHEMA or String(context.get("version", "")) != VERSION:
		return false
	for name in ["canopy_overlap", "local_density"]:
		if not context.has(name):
			return false
		var value := float(context[name])
		if not is_finite(value) or value < 0.0 or value > 1.0:
			return false
	if String(context.get("checksum", "")) != _context_checksum(context):
		return false
	return true

static func evaluate_pair(
	environment: Dictionary,
	phenotype_a: Dictionary,
	phenotype_b: Dictionary,
	context: Dictionary
) -> Dictionary:
	if not bool(EnvironmentSample.validate(environment).get("success", false)):
		return {}
	if not validate_context(context):
		return {}
	var a := _phenotype_metrics(phenotype_a)
	var b := _phenotype_metrics(phenotype_b)
	if a.is_empty() or b.is_empty():
		return {}
	if String(phenotype_a.get("environment_checksum", "")) != String(environment.get("checksum", "")):
		return {}
	if String(phenotype_b.get("environment_checksum", "")) != String(environment.get("checksum", "")):
		return {}

	var profile: Dictionary = MorphologyProfile.create_default()
	if not bool(MorphologyProfile.validate(profile).get("success", false)):
		return {}

	var height_a := float(a["height_m"])
	var height_b := float(b["height_m"])
	var height_sum := height_a + height_b
	if height_sum <= EPSILON:
		return {}
	var relative_height_bias := clampf((height_a - height_b) / height_sum, -1.0, 1.0)
	var canopy_overlap := float(context["canopy_overlap"])
	var local_density := float(context["local_density"])
	var competition_intensity := canopy_overlap * local_density
	var sunlight := clampf(float(environment["sunlight"]), 0.0, 1.0)

	# CAL1-B does not change the accepted PH3 coefficient profile. It reuses the
	# accepted height-light gain only as the bounded size of the contested light
	# pool. The pair mechanism is zero-sum: it redistributes contested access
	# between overlapping canopies instead of inventing new energy.
	var contested_light_pool := float(profile["height_light_access_gain"]) * sunlight * competition_intensity
	var a_relative_access_share := 0.5 + 0.5 * relative_height_bias
	var b_relative_access_share := 1.0 - a_relative_access_share
	var a_light_delta := contested_light_pool * relative_height_bias
	var b_light_delta := -a_light_delta
	var conservation_error := a_light_delta + b_light_delta

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"environment_checksum": String(environment["checksum"]),
		"profile_checksum": String(profile["checksum"]),
		"context_checksum": String(context["checksum"]),
		"phenotype_a_hash": String(phenotype_a["phenotype_hash"]),
		"phenotype_b_hash": String(phenotype_b["phenotype_hash"]),
		"height_a_m": height_a,
		"height_b_m": height_b,
		"crown_a_m": float(a["crown_spread_m"]),
		"crown_b_m": float(b["crown_spread_m"]),
		"canopy_overlap": canopy_overlap,
		"local_density": local_density,
		"competition_intensity": competition_intensity,
		"sunlight": sunlight,
		"relative_height_bias": relative_height_bias,
		"contested_light_pool": contested_light_pool,
		"a_relative_access_share": a_relative_access_share,
		"b_relative_access_share": b_relative_access_share,
		"a_light_delta": a_light_delta,
		"b_light_delta": b_light_delta,
		"conservation_error": conservation_error,
	}
	result["result_hash"] = compute_result_hash(result)
	return result

static func compute_result_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		String(result.get("environment_checksum", "")),
		String(result.get("profile_checksum", "")),
		String(result.get("context_checksum", "")),
		String(result.get("phenotype_a_hash", "")),
		String(result.get("phenotype_b_hash", "")),
	])
	for name in [
		"height_a_m", "height_b_m", "crown_a_m", "crown_b_m",
		"canopy_overlap", "local_density", "competition_intensity", "sunlight",
		"relative_height_bias", "contested_light_pool",
		"a_relative_access_share", "b_relative_access_share",
		"a_light_delta", "b_light_delta", "conservation_error"
	]:
		tokens.append("%.12f" % float(result.get(name, 0.0)))
	return "|".join(tokens).sha256_text()

static func _phenotype_metrics(phenotype: Dictionary) -> Dictionary:
	if String(phenotype.get("phenotype_hash", "")).length() != 64:
		return {}
	var graph: Dictionary = phenotype.get("growth_graph", {})
	var metrics: Dictionary = graph.get("metrics", {})
	var realized: Dictionary = phenotype.get("realized_development_traits", {})
	if metrics.is_empty() or realized.is_empty():
		return {}
	var height := float(metrics.get("height_m", 0.0))
	var crown := float(realized.get("crown_spread_m", 0.0))
	if not is_finite(height) or not is_finite(crown) or height <= 0.0 or crown <= 0.0:
		return {}
	return {"height_m": height, "crown_spread_m": crown}

static func _context_checksum(context: Dictionary) -> String:
	return "|".join(PackedStringArray([
		CONTEXT_SCHEMA,
		VERSION,
		"%.12f" % float(context.get("canopy_overlap", 0.0)),
		"%.12f" % float(context.get("local_density", 0.0)),
		String(context.get("label", "")),
	])).sha256_text()

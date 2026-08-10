extends RefCounted

const GeoUtils = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const SemanticBundle = preload("res://scripts/simulation/procedural/contracts/semantic_field_bundle.gd")
const SemanticSample = preload("res://scripts/simulation/procedural/contracts/semantic_field_sample.gd")
const Registry = preload("res://scripts/simulation/procedural/semantic_fields/semantic_field_registry_v1.gd")
const Profile = preload("res://scripts/simulation/procedural/geomorphology/geomorphology_profile.gd")
const Deformation = preload("res://scripts/simulation/procedural/geomorphology/geomorphology_deformation_sample.gd")
const Valley = preload("res://scripts/simulation/procedural/geomorphology/valley_incision_baseline_v1.gd")

const GENERATOR_ID: String = "geomorphology/g8-2-river-channel-incision-v1"
const GENERATOR_VERSION: String = "1.0.0"
const EPSILON: float = 0.000000001
const INPUT_FIELDS: Array[String] = [
	Registry.SURFACE_HEIGHT_M,
	Registry.VALLEY_INFLUENCE,
	Registry.RIVER_DISTANCE_M,
	Registry.RIVER_WIDTH_M,
]


static func apply(semantic_bundle: Dictionary, profile: Dictionary) -> Dictionary:
	var bundle_validation: Dictionary = SemanticBundle.validate(semantic_bundle)
	if not bool(bundle_validation.get("success", false)):
		return GeoUtils.failure("INVALID_G8_2_SEMANTIC_BUNDLE", {"cause": bundle_validation.get("error_code", "")})
	var profile_validation: Dictionary = Profile.validate(profile)
	if not bool(profile_validation.get("success", false)):
		return GeoUtils.failure("INVALID_G8_2_GEOMORPHOLOGY_PROFILE", {"cause": profile_validation.get("error_code", "")})

	var samples: Dictionary = semantic_bundle["samples"]
	for field_id in INPUT_FIELDS:
		if not samples.has(field_id):
			return GeoUtils.failure("G8_2_REQUIRED_SEMANTIC_FIELD_MISSING", {"field_id": field_id})

	for field_id in INPUT_FIELDS:
		var validation: Dictionary = SemanticSample.validate_against_descriptor(samples[field_id], Registry.descriptor(field_id))
		if not bool(validation.get("success", false)):
			return GeoUtils.failure("INVALID_G8_2_SEMANTIC_SAMPLE", {"field_id": field_id, "cause": validation.get("error_code", "")})

	var river_distance_m: float = float(samples[Registry.RIVER_DISTANCE_M]["value"])
	var river_width_m: float = float(samples[Registry.RIVER_WIDTH_M]["value"])
	if not GeoUtils.is_non_negative_number(river_distance_m):
		return GeoUtils.failure("G8_2_RIVER_DISTANCE_MUST_BE_NON_NEGATIVE", {"value": river_distance_m})
	if not GeoUtils.is_positive_number(river_width_m):
		return GeoUtils.failure("G8_2_RIVER_WIDTH_MUST_BE_POSITIVE", {"value": river_width_m})

	var valley_result: Dictionary = Valley.apply(semantic_bundle, profile)
	if not bool(valley_result.get("success", false)):
		return GeoUtils.failure("G8_2_VALLEY_PARENT_FAILED", {"cause": valley_result.get("error_code", "")})
	var valley_deformation: Dictionary = valley_result["details"]["deformation"]

	var half_width_m: float = river_width_m * 0.5
	var normalized_distance: float = river_distance_m / half_width_m
	var channel_weight: float = _channel_weight(normalized_distance, float(profile["river_edge_softness_ratio"]))
	var max_depth_m: float = float(profile["river_max_depth_m"])
	var incision_depth_m: float = clampf(max_depth_m * channel_weight, 0.0, max_depth_m)
	var river_delta_m: float = 0.0 if incision_depth_m <= 0.0 else -incision_depth_m

	var components: Dictionary = Dictionary(valley_deformation["component_deltas_m"]).duplicate(true)
	components[Deformation.COMPONENT_RIVER_CHANNEL] = river_delta_m
	var query: Dictionary = semantic_bundle["query"]
	var deformation: Dictionary = Deformation.create(
		String(query["body_id"]),
		String(query["frame_id"]),
		Array(query["body_fixed_position_m"]),
		profile,
		String(semantic_bundle["checksum"]),
		float(valley_deformation["source_surface_height_m"]),
		components
	)
	var deformation_validation: Dictionary = Deformation.validate_against_profile(deformation, profile)
	if not bool(deformation_validation.get("success", false)):
		return GeoUtils.failure("INVALID_G8_2_RIVER_DEFORMATION", {"cause": deformation_validation.get("error_code", "")})

	return GeoUtils.success({
		"generator_id": GENERATOR_ID,
		"generator_version": GENERATOR_VERSION,
		"input_field_ids": INPUT_FIELDS.duplicate(),
		"river_distance_m": river_distance_m,
		"river_width_m": river_width_m,
		"half_width_m": half_width_m,
		"normalized_distance": normalized_distance,
		"channel_weight": channel_weight,
		"incision_depth_m": incision_depth_m,
		"valley_deformation_checksum": String(valley_deformation["checksum"]),
		"deformation": deformation,
	})


static func _channel_weight(normalized_distance: float, edge_softness_ratio: float) -> float:
	if normalized_distance >= 1.0:
		return 0.0
	if normalized_distance <= 0.0:
		return 1.0
	var softness: float = clampf(edge_softness_ratio, 0.0, 1.0)
	if softness <= EPSILON:
		return 1.0
	var core_ratio: float = 1.0 - softness
	if normalized_distance <= core_ratio:
		return 1.0
	var t: float = clampf((1.0 - normalized_distance) / softness, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

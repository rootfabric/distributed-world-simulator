extends RefCounted

const GeoUtils = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const SemanticBundle = preload("res://scripts/simulation/procedural/contracts/semantic_field_bundle.gd")
const SemanticSample = preload("res://scripts/simulation/procedural/contracts/semantic_field_sample.gd")
const Registry = preload("res://scripts/simulation/procedural/semantic_fields/semantic_field_registry_v1.gd")
const Profile = preload("res://scripts/simulation/procedural/geomorphology/geomorphology_profile.gd")
const Deformation = preload("res://scripts/simulation/procedural/geomorphology/geomorphology_deformation_sample.gd")
const BanksFloodplain = preload("res://scripts/simulation/procedural/geomorphology/banks_floodplain_shaping_v1.gd")

const GENERATOR_ID: String = "geomorphology/g8-4-erosion-deposition-baseline-v1"
const GENERATOR_VERSION: String = "1.0.0"

const EROSION_INNER_NORM: float = 1.0
const EROSION_PEAK_NORM: float = 1.35
const EROSION_OUTER_NORM: float = 2.0
const DEPOSITION_INNER_NORM: float = 2.0
const DEPOSITION_PEAK_NORM: float = 3.25
const DEPOSITION_OUTER_NORM: float = 5.5

const INPUT_FIELDS: Array[String] = [
	Registry.SURFACE_HEIGHT_M,
	Registry.VALLEY_INFLUENCE,
	Registry.RIVER_DISTANCE_M,
	Registry.RIVER_WIDTH_M,
]


static func apply(semantic_bundle: Dictionary, profile: Dictionary) -> Dictionary:
	var bundle_validation: Dictionary = SemanticBundle.validate(semantic_bundle)
	if not bool(bundle_validation.get("success", false)):
		return GeoUtils.failure("INVALID_G8_4_SEMANTIC_BUNDLE", {"cause": bundle_validation.get("error_code", "")})
	var profile_validation: Dictionary = Profile.validate(profile)
	if not bool(profile_validation.get("success", false)):
		return GeoUtils.failure("INVALID_G8_4_GEOMORPHOLOGY_PROFILE", {"cause": profile_validation.get("error_code", "")})

	var samples: Dictionary = semantic_bundle["samples"]
	for field_id in INPUT_FIELDS:
		if not samples.has(field_id):
			return GeoUtils.failure("G8_4_REQUIRED_SEMANTIC_FIELD_MISSING", {"field_id": field_id})
		var validation: Dictionary = SemanticSample.validate_against_descriptor(samples[field_id], Registry.descriptor(field_id))
		if not bool(validation.get("success", false)):
			return GeoUtils.failure("INVALID_G8_4_SEMANTIC_SAMPLE", {"field_id": field_id, "cause": validation.get("error_code", "")})

	var valley_influence: float = float(samples[Registry.VALLEY_INFLUENCE]["value"])
	var river_distance_m: float = float(samples[Registry.RIVER_DISTANCE_M]["value"])
	var river_width_m: float = float(samples[Registry.RIVER_WIDTH_M]["value"])
	if not GeoUtils.is_ratio(valley_influence):
		return GeoUtils.failure("G8_4_VALLEY_INFLUENCE_OUT_OF_RANGE", {"value": valley_influence})
	if not GeoUtils.is_non_negative_number(river_distance_m):
		return GeoUtils.failure("G8_4_RIVER_DISTANCE_MUST_BE_NON_NEGATIVE", {"value": river_distance_m})
	if not GeoUtils.is_positive_number(river_width_m):
		return GeoUtils.failure("G8_4_RIVER_WIDTH_MUST_BE_POSITIVE", {"value": river_width_m})

	var parent_result: Dictionary = BanksFloodplain.apply(semantic_bundle, profile)
	if not bool(parent_result.get("success", false)):
		return GeoUtils.failure("G8_4_BANKS_FLOODPLAIN_PARENT_FAILED", {"cause": parent_result.get("error_code", "")})
	var parent_deformation: Dictionary = parent_result["details"]["deformation"]

	var half_width_m: float = river_width_m * 0.5
	var normalized_distance: float = river_distance_m / half_width_m
	var erosion_weight: float = _lobe_weight(normalized_distance, EROSION_INNER_NORM, EROSION_PEAK_NORM, EROSION_OUTER_NORM)
	var deposition_weight: float = _lobe_weight(normalized_distance, DEPOSITION_INNER_NORM, DEPOSITION_PEAK_NORM, DEPOSITION_OUTER_NORM)
	var signed_weight: float = deposition_weight - erosion_weight
	var max_delta_m: float = float(profile["erosion_deposition_max_delta_m"])
	var erosion_deposition_delta_m: float = max_delta_m * signed_weight * valley_influence
	if absf(erosion_deposition_delta_m) <= 0.000000000001:
		erosion_deposition_delta_m = 0.0

	var components: Dictionary = Dictionary(parent_deformation["component_deltas_m"]).duplicate(true)
	components[Deformation.COMPONENT_EROSION_DEPOSITION] = erosion_deposition_delta_m

	var query: Dictionary = semantic_bundle["query"]
	var deformation: Dictionary = Deformation.create(
		String(query["body_id"]),
		String(query["frame_id"]),
		Array(query["body_fixed_position_m"]),
		profile,
		String(semantic_bundle["checksum"]),
		float(parent_deformation["source_surface_height_m"]),
		components
	)
	var deformation_validation: Dictionary = Deformation.validate_against_profile(deformation, profile)
	if not bool(deformation_validation.get("success", false)):
		return GeoUtils.failure("INVALID_G8_4_EROSION_DEPOSITION_DEFORMATION", {"cause": deformation_validation.get("error_code", "")})

	return GeoUtils.success({
		"generator_id": GENERATOR_ID,
		"generator_version": GENERATOR_VERSION,
		"input_field_ids": INPUT_FIELDS.duplicate(),
		"valley_influence": valley_influence,
		"river_distance_m": river_distance_m,
		"river_width_m": river_width_m,
		"half_width_m": half_width_m,
		"normalized_distance": normalized_distance,
		"erosion_weight": erosion_weight,
		"deposition_weight": deposition_weight,
		"signed_weight": signed_weight,
		"erosion_deposition_delta_m": erosion_deposition_delta_m,
		"banks_floodplain_deformation_checksum": String(parent_deformation["checksum"]),
		"deformation": deformation,
	})


static func _lobe_weight(value: float, inner: float, peak: float, outer: float) -> float:
	if value <= inner or value >= outer:
		return 0.0
	if value <= peak:
		return _smooth01((value - inner) / (peak - inner))
	return _smooth01((outer - value) / (outer - peak))


static func _smooth01(value: float) -> float:
	var t: float = clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

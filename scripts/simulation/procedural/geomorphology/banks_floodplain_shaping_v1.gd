extends RefCounted

const GeoUtils = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const SemanticBundle = preload("res://scripts/simulation/procedural/contracts/semantic_field_bundle.gd")
const SemanticSample = preload("res://scripts/simulation/procedural/contracts/semantic_field_sample.gd")
const Registry = preload("res://scripts/simulation/procedural/semantic_fields/semantic_field_registry_v1.gd")
const Profile = preload("res://scripts/simulation/procedural/geomorphology/geomorphology_profile.gd")
const Deformation = preload("res://scripts/simulation/procedural/geomorphology/geomorphology_deformation_sample.gd")
const River = preload("res://scripts/simulation/procedural/geomorphology/river_channel_incision_v1.gd")

const GENERATOR_ID: String = "geomorphology/g8-3-banks-floodplain-v1"
const GENERATOR_VERSION: String = "1.0.0"

const BANK_INNER_NORM: float = 1.0
const BANK_PEAK_NORM: float = 1.5
const BANK_OUTER_NORM: float = 2.0
const FLOODPLAIN_INNER_NORM: float = 2.0
const FLOODPLAIN_FULL_NORM: float = 2.5
const FLOODPLAIN_CORE_END_NORM: float = 4.5
const FLOODPLAIN_OUTER_NORM: float = 6.0

const INPUT_FIELDS: Array[String] = [
	Registry.SURFACE_HEIGHT_M,
	Registry.VALLEY_INFLUENCE,
	Registry.RIVER_DISTANCE_M,
	Registry.RIVER_WIDTH_M,
]


static func apply(semantic_bundle: Dictionary, profile: Dictionary) -> Dictionary:
	var bundle_validation: Dictionary = SemanticBundle.validate(semantic_bundle)
	if not bool(bundle_validation.get("success", false)):
		return GeoUtils.failure("INVALID_G8_3_SEMANTIC_BUNDLE", {"cause": bundle_validation.get("error_code", "")})
	var profile_validation: Dictionary = Profile.validate(profile)
	if not bool(profile_validation.get("success", false)):
		return GeoUtils.failure("INVALID_G8_3_GEOMORPHOLOGY_PROFILE", {"cause": profile_validation.get("error_code", "")})

	var samples: Dictionary = semantic_bundle["samples"]
	for field_id in INPUT_FIELDS:
		if not samples.has(field_id):
			return GeoUtils.failure("G8_3_REQUIRED_SEMANTIC_FIELD_MISSING", {"field_id": field_id})
		var validation: Dictionary = SemanticSample.validate_against_descriptor(samples[field_id], Registry.descriptor(field_id))
		if not bool(validation.get("success", false)):
			return GeoUtils.failure("INVALID_G8_3_SEMANTIC_SAMPLE", {"field_id": field_id, "cause": validation.get("error_code", "")})

	var valley_influence: float = float(samples[Registry.VALLEY_INFLUENCE]["value"])
	var river_distance_m: float = float(samples[Registry.RIVER_DISTANCE_M]["value"])
	var river_width_m: float = float(samples[Registry.RIVER_WIDTH_M]["value"])
	if not GeoUtils.is_ratio(valley_influence):
		return GeoUtils.failure("G8_3_VALLEY_INFLUENCE_OUT_OF_RANGE", {"value": valley_influence})
	if not GeoUtils.is_non_negative_number(river_distance_m):
		return GeoUtils.failure("G8_3_RIVER_DISTANCE_MUST_BE_NON_NEGATIVE", {"value": river_distance_m})
	if not GeoUtils.is_positive_number(river_width_m):
		return GeoUtils.failure("G8_3_RIVER_WIDTH_MUST_BE_POSITIVE", {"value": river_width_m})

	var river_result: Dictionary = River.apply(semantic_bundle, profile)
	if not bool(river_result.get("success", false)):
		return GeoUtils.failure("G8_3_RIVER_PARENT_FAILED", {"cause": river_result.get("error_code", "")})
	var river_deformation: Dictionary = river_result["details"]["deformation"]

	var half_width_m: float = river_width_m * 0.5
	var normalized_distance: float = river_distance_m / half_width_m
	var bank_weight: float = _bank_weight(normalized_distance)
	var floodplain_weight: float = _floodplain_weight(normalized_distance)
	var bank_delta_m: float = float(profile["bank_max_delta_m"]) * bank_weight * valley_influence
	var floodplain_delta_m: float = -float(profile["floodplain_max_delta_m"]) * floodplain_weight * valley_influence
	if absf(bank_delta_m) <= 0.000000000001:
		bank_delta_m = 0.0
	if absf(floodplain_delta_m) <= 0.000000000001:
		floodplain_delta_m = 0.0

	var components: Dictionary = Dictionary(river_deformation["component_deltas_m"]).duplicate(true)
	components[Deformation.COMPONENT_BANK] = bank_delta_m
	components[Deformation.COMPONENT_FLOODPLAIN] = floodplain_delta_m

	var query: Dictionary = semantic_bundle["query"]
	var deformation: Dictionary = Deformation.create(
		String(query["body_id"]),
		String(query["frame_id"]),
		Array(query["body_fixed_position_m"]),
		profile,
		String(semantic_bundle["checksum"]),
		float(river_deformation["source_surface_height_m"]),
		components
	)
	var deformation_validation: Dictionary = Deformation.validate_against_profile(deformation, profile)
	if not bool(deformation_validation.get("success", false)):
		return GeoUtils.failure("INVALID_G8_3_BANK_FLOODPLAIN_DEFORMATION", {"cause": deformation_validation.get("error_code", "")})

	return GeoUtils.success({
		"generator_id": GENERATOR_ID,
		"generator_version": GENERATOR_VERSION,
		"input_field_ids": INPUT_FIELDS.duplicate(),
		"valley_influence": valley_influence,
		"river_distance_m": river_distance_m,
		"river_width_m": river_width_m,
		"half_width_m": half_width_m,
		"normalized_distance": normalized_distance,
		"bank_weight": bank_weight,
		"floodplain_weight": floodplain_weight,
		"bank_delta_m": bank_delta_m,
		"floodplain_delta_m": floodplain_delta_m,
		"river_deformation_checksum": String(river_deformation["checksum"]),
		"deformation": deformation,
	})


static func _bank_weight(normalized_distance: float) -> float:
	if normalized_distance <= BANK_INNER_NORM or normalized_distance >= BANK_OUTER_NORM:
		return 0.0
	if normalized_distance <= BANK_PEAK_NORM:
		return _smooth01((normalized_distance - BANK_INNER_NORM) / (BANK_PEAK_NORM - BANK_INNER_NORM))
	return _smooth01((BANK_OUTER_NORM - normalized_distance) / (BANK_OUTER_NORM - BANK_PEAK_NORM))


static func _floodplain_weight(normalized_distance: float) -> float:
	if normalized_distance <= FLOODPLAIN_INNER_NORM or normalized_distance >= FLOODPLAIN_OUTER_NORM:
		return 0.0
	if normalized_distance < FLOODPLAIN_FULL_NORM:
		return _smooth01((normalized_distance - FLOODPLAIN_INNER_NORM) / (FLOODPLAIN_FULL_NORM - FLOODPLAIN_INNER_NORM))
	if normalized_distance <= FLOODPLAIN_CORE_END_NORM:
		return 1.0
	return _smooth01((FLOODPLAIN_OUTER_NORM - normalized_distance) / (FLOODPLAIN_OUTER_NORM - FLOODPLAIN_CORE_END_NORM))


static func _smooth01(value: float) -> float:
	var t: float = clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

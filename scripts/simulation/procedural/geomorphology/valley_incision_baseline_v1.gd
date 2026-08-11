extends RefCounted

const GeoUtils = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const SemanticBundle = preload("res://scripts/simulation/procedural/contracts/semantic_field_bundle.gd")
const SemanticSample = preload("res://scripts/simulation/procedural/contracts/semantic_field_sample.gd")
const Registry = preload("res://scripts/simulation/procedural/semantic_fields/semantic_field_registry_v1.gd")
const Profile = preload("res://scripts/simulation/procedural/geomorphology/geomorphology_profile.gd")
const Deformation = preload("res://scripts/simulation/procedural/geomorphology/geomorphology_deformation_sample.gd")

const GENERATOR_ID: String = "geomorphology/g8-1-valley-incision-v1"
const GENERATOR_VERSION: String = "1.0.0"
const INPUT_FIELDS: Array[String] = [Registry.SURFACE_HEIGHT_M, Registry.VALLEY_INFLUENCE]


static func apply(semantic_bundle: Dictionary, profile: Dictionary) -> Dictionary:
	var bundle_validation: Dictionary = SemanticBundle.validate(semantic_bundle)
	if not bool(bundle_validation.get("success", false)):
		return GeoUtils.failure("INVALID_G8_1_SEMANTIC_BUNDLE", {"cause": bundle_validation.get("error_code", "")})
	var profile_validation: Dictionary = Profile.validate(profile)
	if not bool(profile_validation.get("success", false)):
		return GeoUtils.failure("INVALID_G8_1_GEOMORPHOLOGY_PROFILE", {"cause": profile_validation.get("error_code", "")})

	var samples: Dictionary = semantic_bundle["samples"]
	for field_id in INPUT_FIELDS:
		if not samples.has(field_id):
			return GeoUtils.failure("G8_1_REQUIRED_SEMANTIC_FIELD_MISSING", {"field_id": field_id})

	var surface_sample: Dictionary = samples[Registry.SURFACE_HEIGHT_M]
	var valley_sample: Dictionary = samples[Registry.VALLEY_INFLUENCE]
	var surface_validation: Dictionary = SemanticSample.validate_against_descriptor(surface_sample, Registry.descriptor(Registry.SURFACE_HEIGHT_M))
	if not bool(surface_validation.get("success", false)):
		return GeoUtils.failure("INVALID_G8_1_SURFACE_HEIGHT_SAMPLE", {"cause": surface_validation.get("error_code", "")})
	var valley_validation: Dictionary = SemanticSample.validate_against_descriptor(valley_sample, Registry.descriptor(Registry.VALLEY_INFLUENCE))
	if not bool(valley_validation.get("success", false)):
		return GeoUtils.failure("INVALID_G8_1_VALLEY_INFLUENCE_SAMPLE", {"cause": valley_validation.get("error_code", "")})

	var source_height_m: float = float(surface_sample["value"])
	var valley_influence: float = float(valley_sample["value"])
	if not GeoUtils.is_ratio(valley_influence):
		return GeoUtils.failure("G8_1_VALLEY_INFLUENCE_OUT_OF_RANGE", {"value": valley_influence})

	var max_depth_m: float = float(profile["valley_max_depth_m"])
	var exponent: float = float(profile["valley_exponent"])
	var incision_depth_m: float = max_depth_m * pow(valley_influence, exponent)
	incision_depth_m = clampf(incision_depth_m, 0.0, max_depth_m)
	var valley_delta_m: float = 0.0 if incision_depth_m <= 0.0 else -incision_depth_m

	var components: Dictionary = Deformation.zero_components()
	components[Deformation.COMPONENT_VALLEY] = valley_delta_m
	var query: Dictionary = semantic_bundle["query"]
	var deformation: Dictionary = Deformation.create(
		String(query["body_id"]),
		String(query["frame_id"]),
		Array(query["body_fixed_position_m"]),
		profile,
		String(semantic_bundle["checksum"]),
		source_height_m,
		components
	)
	var deformation_validation: Dictionary = Deformation.validate_against_profile(deformation, profile)
	if not bool(deformation_validation.get("success", false)):
		return GeoUtils.failure("INVALID_G8_1_VALLEY_DEFORMATION", {"cause": deformation_validation.get("error_code", "")})

	return GeoUtils.success({
		"generator_id": GENERATOR_ID,
		"generator_version": GENERATOR_VERSION,
		"input_field_ids": INPUT_FIELDS.duplicate(),
		"valley_influence": valley_influence,
		"incision_depth_m": incision_depth_m,
		"deformation": deformation,
	})

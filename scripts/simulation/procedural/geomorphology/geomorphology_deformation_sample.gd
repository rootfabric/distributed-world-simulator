extends RefCounted

const GeoUtils = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const Profile = preload("res://scripts/simulation/procedural/geomorphology/geomorphology_profile.gd")

const SCHEMA: String = "planet_simulator.geomorphology_deformation_sample.v1"

const COMPONENT_VALLEY: String = "valley_delta_m"
const COMPONENT_RIVER_CHANNEL: String = "river_channel_delta_m"
const COMPONENT_BANK: String = "bank_delta_m"
const COMPONENT_FLOODPLAIN: String = "floodplain_delta_m"
const COMPONENT_EROSION_DEPOSITION: String = "erosion_deposition_delta_m"
const COMPONENT_FIELDS: Array[String] = [
	COMPONENT_VALLEY,
	COMPONENT_RIVER_CHANNEL,
	COMPONENT_BANK,
	COMPONENT_FLOODPLAIN,
	COMPONENT_EROSION_DEPOSITION,
]

const FIELDS: Array[String] = [
	"schema",
	"body_id",
	"frame_id",
	"body_fixed_position_m",
	"profile_id",
	"profile_version",
	"profile_checksum",
	"source_semantic_bundle_checksum",
	"source_surface_height_m",
	"component_deltas_m",
	"total_delta_height_m",
	"resolved_surface_height_m",
	"checksum",
]


static func create(
	body_id: String,
	frame_id: String,
	body_fixed_position_m: Array,
	profile: Dictionary,
	source_semantic_bundle_checksum: String,
	source_surface_height_m: float,
	component_deltas_m: Dictionary
) -> Dictionary:
	var normalized_components: Dictionary = {}
	for key in COMPONENT_FIELDS:
		normalized_components[key] = float(component_deltas_m.get(key, 0.0))
	var total_delta_height_m: float = _component_sum(normalized_components)
	var result: Dictionary = {
		"schema": SCHEMA,
		"body_id": body_id,
		"frame_id": frame_id,
		"body_fixed_position_m": body_fixed_position_m.duplicate(true),
		"profile_id": String(profile.get("profile_id", "")),
		"profile_version": String(profile.get("version", "")),
		"profile_checksum": String(profile.get("checksum", "")),
		"source_semantic_bundle_checksum": source_semantic_bundle_checksum,
		"source_surface_height_m": source_surface_height_m,
		"component_deltas_m": normalized_components,
		"total_delta_height_m": total_delta_height_m,
		"resolved_surface_height_m": source_surface_height_m + total_delta_height_m,
	}
	result["checksum"] = GeoUtils.compute_checksum(result)
	return result


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtils.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if String(value.get("schema", "")) != SCHEMA:
		return GeoUtils.failure("INVALID_G8_0_DEFORMATION_SCHEMA")
	if not GeoUtils.is_canonical_id(value.get("body_id"), 2):
		return GeoUtils.failure("INVALID_G8_0_DEFORMATION_BODY_ID")
	if not GeoUtils.is_canonical_id(value.get("frame_id"), 2):
		return GeoUtils.failure("INVALID_G8_0_DEFORMATION_FRAME_ID")
	if not GeoUtils.is_vector3_array(value.get("body_fixed_position_m")):
		return GeoUtils.failure("INVALID_G8_0_DEFORMATION_POSITION")
	if not GeoUtils.is_canonical_id(value.get("profile_id"), 2):
		return GeoUtils.failure("INVALID_G8_0_DEFORMATION_PROFILE_ID")
	if not GeoUtils.is_semantic_version(value.get("profile_version")):
		return GeoUtils.failure("INVALID_G8_0_DEFORMATION_PROFILE_VERSION")
	if not GeoUtils.is_lower_hex_64(value.get("profile_checksum")):
		return GeoUtils.failure("INVALID_G8_0_DEFORMATION_PROFILE_CHECKSUM")
	if not GeoUtils.is_lower_hex_64(value.get("source_semantic_bundle_checksum")):
		return GeoUtils.failure("INVALID_G8_0_DEFORMATION_SOURCE_BUNDLE_CHECKSUM")
	if not GeoUtils.is_finite_number(value.get("source_surface_height_m")):
		return GeoUtils.failure("INVALID_G8_0_DEFORMATION_SOURCE_HEIGHT")
	if typeof(value.get("component_deltas_m")) != TYPE_DICTIONARY:
		return GeoUtils.failure("INVALID_G8_0_DEFORMATION_COMPONENTS")
	var components: Dictionary = value["component_deltas_m"]
	var component_exact: Dictionary = GeoUtils.validate_exact_fields(components, COMPONENT_FIELDS)
	if not bool(component_exact.get("success", false)):
		return GeoUtils.failure("INVALID_G8_0_DEFORMATION_COMPONENT_FIELDS", {"cause": component_exact.get("error_code", "")})
	for key in COMPONENT_FIELDS:
		if not GeoUtils.is_finite_number(components.get(key)):
			return GeoUtils.failure("INVALID_G8_0_DEFORMATION_COMPONENT_VALUE", {"field": key})
	if float(components[COMPONENT_VALLEY]) > 0.0:
		return GeoUtils.failure("G8_0_VALLEY_COMPONENT_MUST_NOT_RAISE_SURFACE")
	if float(components[COMPONENT_RIVER_CHANNEL]) > 0.0:
		return GeoUtils.failure("G8_0_RIVER_COMPONENT_MUST_NOT_RAISE_SURFACE")
	if not GeoUtils.is_finite_number(value.get("total_delta_height_m")):
		return GeoUtils.failure("INVALID_G8_0_DEFORMATION_TOTAL")
	if not GeoUtils.is_finite_number(value.get("resolved_surface_height_m")):
		return GeoUtils.failure("INVALID_G8_0_DEFORMATION_RESOLVED_HEIGHT")
	var expected_total: float = _component_sum(components)
	if not GeoUtils.approximately_equal(float(value["total_delta_height_m"]), expected_total):
		return GeoUtils.failure("G8_0_DEFORMATION_COMPONENT_SUM_MISMATCH")
	var expected_resolved: float = float(value["source_surface_height_m"]) + expected_total
	if not GeoUtils.approximately_equal(float(value["resolved_surface_height_m"]), expected_resolved):
		return GeoUtils.failure("G8_0_DEFORMATION_RESOLVED_HEIGHT_MISMATCH")
	var checksum_validation: Dictionary = GeoUtils.validate_checksum(value)
	if not bool(checksum_validation.get("success", false)):
		return checksum_validation
	return GeoUtils.success({
		"total_delta_height_m": expected_total,
		"resolved_surface_height_m": expected_resolved,
		"checksum": String(value["checksum"]),
	})


static func validate_against_profile(value: Dictionary, profile: Dictionary) -> Dictionary:
	var sample_validation: Dictionary = validate(value)
	if not bool(sample_validation.get("success", false)):
		return sample_validation
	var profile_validation: Dictionary = Profile.validate(profile)
	if not bool(profile_validation.get("success", false)):
		return GeoUtils.failure("INVALID_G8_0_DEFORMATION_PROFILE", {"cause": profile_validation.get("error_code", "")})
	if String(value["profile_id"]) != String(profile["profile_id"]):
		return GeoUtils.failure("G8_0_DEFORMATION_PROFILE_ID_MISMATCH")
	if String(value["profile_version"]) != String(profile["version"]):
		return GeoUtils.failure("G8_0_DEFORMATION_PROFILE_VERSION_MISMATCH")
	if String(value["profile_checksum"]) != String(profile["checksum"]):
		return GeoUtils.failure("G8_0_DEFORMATION_PROFILE_CHECKSUM_MISMATCH")
	var components: Dictionary = value["component_deltas_m"]
	if absf(float(components[COMPONENT_VALLEY])) > float(profile["valley_max_depth_m"]):
		return GeoUtils.failure("G8_0_VALLEY_DEPTH_EXCEEDS_PROFILE")
	if absf(float(components[COMPONENT_RIVER_CHANNEL])) > float(profile["river_max_depth_m"]):
		return GeoUtils.failure("G8_0_RIVER_DEPTH_EXCEEDS_PROFILE")
	if absf(float(components[COMPONENT_BANK])) > float(profile["bank_max_delta_m"]):
		return GeoUtils.failure("G8_0_BANK_DELTA_EXCEEDS_PROFILE")
	if absf(float(components[COMPONENT_FLOODPLAIN])) > float(profile["floodplain_max_delta_m"]):
		return GeoUtils.failure("G8_0_FLOODPLAIN_DELTA_EXCEEDS_PROFILE")
	if absf(float(components[COMPONENT_EROSION_DEPOSITION])) > float(profile["erosion_deposition_max_delta_m"]):
		return GeoUtils.failure("G8_0_EROSION_DEPOSITION_DELTA_EXCEEDS_PROFILE")
	return GeoUtils.success({"checksum": String(value["checksum"])})


static func zero_components() -> Dictionary:
	var result: Dictionary = {}
	for key in COMPONENT_FIELDS:
		result[key] = 0.0
	return result


static func _component_sum(components: Dictionary) -> float:
	var result: float = 0.0
	for key in COMPONENT_FIELDS:
		result += float(components.get(key, 0.0))
	return result

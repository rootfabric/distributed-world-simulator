extends RefCounted

const GeoUtils = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")

const SCHEMA: String = "planet_simulator.geomorphology_profile.v1"
const DEFAULT_VERSION: String = "1.0.0"

const FIELDS: Array[String] = [
	"schema",
	"profile_id",
	"version",
	"valley_max_depth_m",
	"river_max_depth_m",
	"bank_max_delta_m",
	"floodplain_max_delta_m",
	"erosion_deposition_max_delta_m",
	"valley_exponent",
	"river_edge_softness_ratio",
	"checksum",
]


static func create(
	profile_id: String,
	version: String = DEFAULT_VERSION,
	valley_max_depth_m: float = 180.0,
	river_max_depth_m: float = 35.0,
	bank_max_delta_m: float = 8.0,
	floodplain_max_delta_m: float = 12.0,
	erosion_deposition_max_delta_m: float = 6.0,
	valley_exponent: float = 1.5,
	river_edge_softness_ratio: float = 0.35
) -> Dictionary:
	var result: Dictionary = {
		"schema": SCHEMA,
		"profile_id": profile_id,
		"version": version,
		"valley_max_depth_m": valley_max_depth_m,
		"river_max_depth_m": river_max_depth_m,
		"bank_max_delta_m": bank_max_delta_m,
		"floodplain_max_delta_m": floodplain_max_delta_m,
		"erosion_deposition_max_delta_m": erosion_deposition_max_delta_m,
		"valley_exponent": valley_exponent,
		"river_edge_softness_ratio": river_edge_softness_ratio,
	}
	result["checksum"] = GeoUtils.compute_checksum(result)
	return result


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtils.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if String(value.get("schema", "")) != SCHEMA:
		return GeoUtils.failure("INVALID_G8_0_GEOMORPHOLOGY_PROFILE_SCHEMA")
	if not GeoUtils.is_canonical_id(value.get("profile_id"), 2):
		return GeoUtils.failure("INVALID_G8_0_GEOMORPHOLOGY_PROFILE_ID")
	if not GeoUtils.is_semantic_version(value.get("version")):
		return GeoUtils.failure("INVALID_G8_0_GEOMORPHOLOGY_PROFILE_VERSION")
	for key in [
		"valley_max_depth_m",
		"river_max_depth_m",
		"bank_max_delta_m",
		"floodplain_max_delta_m",
		"erosion_deposition_max_delta_m",
	]:
		if not GeoUtils.is_non_negative_number(value.get(key)):
			return GeoUtils.failure("INVALID_G8_0_GEOMORPHOLOGY_PROFILE_MAGNITUDE", {"field": key})
	if not GeoUtils.is_positive_number(value.get("valley_exponent")):
		return GeoUtils.failure("INVALID_G8_0_GEOMORPHOLOGY_VALLEY_EXPONENT")
	if not GeoUtils.is_ratio(value.get("river_edge_softness_ratio")):
		return GeoUtils.failure("INVALID_G8_0_GEOMORPHOLOGY_RIVER_EDGE_SOFTNESS")
	var checksum_validation: Dictionary = GeoUtils.validate_checksum(value)
	if not bool(checksum_validation.get("success", false)):
		return checksum_validation
	return GeoUtils.success({
		"profile_id": String(value["profile_id"]),
		"version": String(value["version"]),
		"checksum": String(value["checksum"]),
	})

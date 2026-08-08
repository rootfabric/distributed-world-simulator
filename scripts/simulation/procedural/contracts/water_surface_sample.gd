extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const FeatureIdScript = preload("res://scripts/simulation/procedural/contracts/feature_id.gd")
const FluidRegionIdScript = preload("res://scripts/simulation/procedural/contracts/fluid_region_id.gd")

const SCHEMA: String = "planet_simulator.water_surface_sample.v1"
const FIELDS: Array[String] = [
	"schema",
	"feature_id",
	"fluid_region_id",
	"body_id",
	"frame_id",
	"fluid_type_id",
	"query_position_m",
	"centerline_position_m",
	"surface_position_m",
	"surface_normal",
	"flow_vector_mps",
	"channel_width_m",
	"channel_depth_m",
	"distance_to_centerline_m",
	"normalized_distance",
	"inside_channel",
	"checksum",
]


static func create(
	feature_id: String,
	fluid_region_id: String,
	body_id: String,
	frame_id: String,
	fluid_type_id: String,
	query_position_m: Array,
	centerline_position_m: Array,
	surface_position_m: Array,
	surface_normal: Array,
	flow_vector_mps: Array,
	channel_width_m: float,
	channel_depth_m: float,
	distance_to_centerline_m: float,
	normalized_distance: float,
	inside_channel: bool
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"feature_id": feature_id,
		"fluid_region_id": fluid_region_id,
		"body_id": body_id,
		"frame_id": frame_id,
		"fluid_type_id": fluid_type_id,
		"query_position_m": query_position_m.duplicate(),
		"centerline_position_m": centerline_position_m.duplicate(),
		"surface_position_m": surface_position_m.duplicate(),
		"surface_normal": surface_normal.duplicate(),
		"flow_vector_mps": flow_vector_mps.duplicate(),
		"channel_width_m": channel_width_m,
		"channel_depth_m": channel_depth_m,
		"distance_to_centerline_m": distance_to_centerline_m,
		"normalized_distance": normalized_distance,
		"inside_channel": inside_channel,
		"checksum": "",
	}
	value["checksum"] = GeoUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if String(value.get("schema", "")) != SCHEMA:
		return GeoUtilsScript.failure("UNSUPPORTED_WATER_SURFACE_SAMPLE_SCHEMA")
	if not bool(FeatureIdScript.validate(value.get("feature_id")).get("success", false)):
		return GeoUtilsScript.failure("INVALID_WATER_SURFACE_FEATURE_ID")
	if not bool(FluidRegionIdScript.validate(value.get("fluid_region_id")).get("success", false)):
		return GeoUtilsScript.failure("INVALID_WATER_SURFACE_FLUID_REGION_ID")
	if not GeoUtilsScript.is_canonical_id(value.get("body_id"), 2) or not GeoUtilsScript.is_canonical_id(value.get("frame_id"), 2):
		return GeoUtilsScript.failure("INVALID_WATER_SURFACE_IDENTITY")
	if not GeoUtilsScript.is_canonical_id(value.get("fluid_type_id"), 2) or not String(value["fluid_type_id"]).begins_with(FluidRegionIdScript.FLUID_TYPE_PREFIX):
		return GeoUtilsScript.failure("INVALID_WATER_SURFACE_FLUID_TYPE")
	for field in ["query_position_m", "centerline_position_m", "surface_position_m", "surface_normal", "flow_vector_mps"]:
		if not GeoUtilsScript.is_vector3_array(value.get(field)):
			return GeoUtilsScript.failure("INVALID_WATER_SURFACE_VECTOR", {"field": field})
	if not GeoUtilsScript.is_positive_number(value.get("channel_width_m")) or not GeoUtilsScript.is_positive_number(value.get("channel_depth_m")):
		return GeoUtilsScript.failure("INVALID_WATER_SURFACE_CHANNEL_SIZE")
	if not GeoUtilsScript.is_non_negative_number(value.get("distance_to_centerline_m")):
		return GeoUtilsScript.failure("INVALID_WATER_SURFACE_DISTANCE")
	if not GeoUtilsScript.is_ratio(value.get("normalized_distance")):
		return GeoUtilsScript.failure("INVALID_WATER_SURFACE_NORMALIZED_DISTANCE")
	if typeof(value.get("inside_channel")) != TYPE_BOOL:
		return GeoUtilsScript.failure("INVALID_WATER_SURFACE_INSIDE_CHANNEL")
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.water_surface_sample")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)

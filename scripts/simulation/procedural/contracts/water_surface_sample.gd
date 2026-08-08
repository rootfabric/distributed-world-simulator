extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const FeatureIdScript = preload("res://scripts/simulation/procedural/contracts/feature_id.gd")
const FluidRegionIdScript = preload("res://scripts/simulation/procedural/contracts/fluid_region_id.gd")
const FluidTypeScript = preload("res://scripts/simulation/procedural/contracts/fluid_type.gd")

const SCHEMA: String = "planet_simulator.water_surface_sample.v1"
const FIELDS: Array[String] = [
	"schema",
	"source_feature_id",
	"fluid_region_id",
	"body_id",
	"frame_id",
	"fluid_type_id",
	"query_position_m",
	"centerline_position_m",
	"surface_position_m",
	"surface_normal",
	"flow_direction",
	"channel_width_m",
	"channel_depth_m",
	"bank_width_m",
	"distance_to_centerline_m",
	"distance_to_surface_m",
	"downstream_t",
	"inside_channel",
	"checksum",
]


static func create(
	source_feature_id: String,
	fluid_region_id: String,
	body_id: String,
	frame_id: String,
	fluid_type_id: String,
	query_position_m: Array,
	centerline_position_m: Array,
	surface_position_m: Array,
	surface_normal: Array,
	flow_direction: Array,
	channel_width_m: float,
	channel_depth_m: float,
	bank_width_m: float,
	distance_to_centerline_m: float,
	distance_to_surface_m: float,
	downstream_t: float,
	inside_channel: bool
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"source_feature_id": source_feature_id,
		"fluid_region_id": fluid_region_id,
		"body_id": body_id,
		"frame_id": frame_id,
		"fluid_type_id": fluid_type_id,
		"query_position_m": query_position_m.duplicate(),
		"centerline_position_m": centerline_position_m.duplicate(),
		"surface_position_m": surface_position_m.duplicate(),
		"surface_normal": surface_normal.duplicate(),
		"flow_direction": flow_direction.duplicate(),
		"channel_width_m": channel_width_m,
		"channel_depth_m": channel_depth_m,
		"bank_width_m": bank_width_m,
		"distance_to_centerline_m": distance_to_centerline_m,
		"distance_to_surface_m": distance_to_surface_m,
		"downstream_t": downstream_t,
		"inside_channel": inside_channel,
		"checksum": "",
	}
	value["checksum"] = GeoUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return GeoUtilsScript.failure("UNSUPPORTED_WATER_SURFACE_SAMPLE_SCHEMA")
	if not bool(FeatureIdScript.validate(value.get("source_feature_id")).get("success", false)):
		return GeoUtilsScript.failure("INVALID_WATER_SURFACE_SAMPLE_FEATURE_ID")
	if not bool(FluidRegionIdScript.validate(value.get("fluid_region_id")).get("success", false)):
		return GeoUtilsScript.failure("INVALID_WATER_SURFACE_SAMPLE_REGION_ID")
	if not GeoUtilsScript.is_canonical_id(value.get("body_id"), 2):
		return GeoUtilsScript.failure("INVALID_WATER_SURFACE_SAMPLE_BODY_ID")
	if not GeoUtilsScript.is_canonical_id(value.get("frame_id"), 2):
		return GeoUtilsScript.failure("INVALID_WATER_SURFACE_SAMPLE_FRAME_ID")
	if not bool(FluidTypeScript.validate(value.get("fluid_type_id")).get("success", false)):
		return GeoUtilsScript.failure("INVALID_WATER_SURFACE_SAMPLE_FLUID_TYPE")
	for field in ["query_position_m", "centerline_position_m", "surface_position_m", "surface_normal", "flow_direction"]:
		if not GeoUtilsScript.is_vector3_array(value.get(field)):
			return GeoUtilsScript.failure("INVALID_WATER_SURFACE_SAMPLE_VECTOR", {"field": field})
	if not _is_unit_vector(value["surface_normal"]):
		return GeoUtilsScript.failure("INVALID_WATER_SURFACE_SAMPLE_NORMAL")
	if not _is_unit_vector(value["flow_direction"]):
		return GeoUtilsScript.failure("INVALID_WATER_SURFACE_SAMPLE_FLOW_DIRECTION")
	if not GeoUtilsScript.is_positive_number(value.get("channel_width_m")):
		return GeoUtilsScript.failure("INVALID_WATER_SURFACE_SAMPLE_WIDTH")
	if not GeoUtilsScript.is_non_negative_number(value.get("channel_depth_m")):
		return GeoUtilsScript.failure("INVALID_WATER_SURFACE_SAMPLE_DEPTH")
	if not GeoUtilsScript.is_non_negative_number(value.get("bank_width_m")):
		return GeoUtilsScript.failure("INVALID_WATER_SURFACE_SAMPLE_BANK_WIDTH")
	if not GeoUtilsScript.is_non_negative_number(value.get("distance_to_centerline_m")):
		return GeoUtilsScript.failure("INVALID_WATER_SURFACE_SAMPLE_CENTERLINE_DISTANCE")
	if not GeoUtilsScript.is_non_negative_number(value.get("distance_to_surface_m")):
		return GeoUtilsScript.failure("INVALID_WATER_SURFACE_SAMPLE_SURFACE_DISTANCE")
	if not GeoUtilsScript.is_ratio(value.get("downstream_t")):
		return GeoUtilsScript.failure("INVALID_WATER_SURFACE_SAMPLE_DOWNSTREAM_T")
	if typeof(value.get("inside_channel")) != TYPE_BOOL:
		return GeoUtilsScript.failure("INVALID_WATER_SURFACE_SAMPLE_INSIDE_CHANNEL")
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.water_surface_sample")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return GeoUtilsScript.normalize(value, validate)


static func _is_unit_vector(value: Array) -> bool:
	var length_squared := float(value[0]) * float(value[0]) + float(value[1]) * float(value[1]) + float(value[2]) * float(value[2])
	return absf(length_squared - 1.0) <= 0.00001

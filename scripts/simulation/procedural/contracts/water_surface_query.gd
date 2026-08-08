extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const FluidRegionIdScript = preload("res://scripts/simulation/procedural/contracts/fluid_region_id.gd")

const SCHEMA: String = "planet_simulator.water_surface_query.v1"
const FIELDS: Array[String] = [
	"schema",
	"body_id",
	"frame_id",
	"position_m",
	"max_distance_m",
	"fluid_region_id",
	"checksum",
]


static func create(
	body_id: String,
	frame_id: String,
	position_m: Array,
	max_distance_m: float,
	fluid_region_id: String = ""
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"body_id": body_id,
		"frame_id": frame_id,
		"position_m": position_m.duplicate(),
		"max_distance_m": max_distance_m,
		"fluid_region_id": fluid_region_id,
		"checksum": "",
	}
	value["checksum"] = GeoUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return GeoUtilsScript.failure("UNSUPPORTED_WATER_SURFACE_QUERY_SCHEMA")
	if not GeoUtilsScript.is_canonical_id(value.get("body_id"), 2):
		return GeoUtilsScript.failure("INVALID_WATER_SURFACE_QUERY_BODY_ID")
	if not GeoUtilsScript.is_canonical_id(value.get("frame_id"), 2):
		return GeoUtilsScript.failure("INVALID_WATER_SURFACE_QUERY_FRAME_ID")
	if not GeoUtilsScript.is_vector3_array(value.get("position_m")):
		return GeoUtilsScript.failure("INVALID_WATER_SURFACE_QUERY_POSITION")
	if not GeoUtilsScript.is_non_negative_number(value.get("max_distance_m")):
		return GeoUtilsScript.failure("INVALID_WATER_SURFACE_QUERY_DISTANCE")
	if typeof(value.get("fluid_region_id")) != TYPE_STRING:
		return GeoUtilsScript.failure("INVALID_WATER_SURFACE_QUERY_REGION_FILTER")
	var region_id := String(value["fluid_region_id"])
	if not region_id.is_empty() and not bool(FluidRegionIdScript.validate(region_id).get("success", false)):
		return GeoUtilsScript.failure("INVALID_WATER_SURFACE_QUERY_REGION_FILTER")
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.water_surface_query")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)

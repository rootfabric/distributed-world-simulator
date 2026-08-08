extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const FluidTypeScript = preload("res://scripts/simulation/procedural/contracts/fluid_type.gd")

const SCHEMA: String = "planet_simulator.water_surface_query.v1"
const FIELDS: Array[String] = [
	"schema",
	"body_id",
	"frame_id",
	"position_m",
	"max_distance_m",
	"fluid_type_ids",
	"checksum",
]


static func create(
	body_id: String,
	frame_id: String,
	position_m: Array,
	max_distance_m: float = 0.0,
	fluid_type_ids: Array = []
) -> Dictionary:
	var requested_types: Array = fluid_type_ids.duplicate()
	if requested_types.is_empty():
		requested_types = [FluidTypeScript.WATER]
	var value: Dictionary = {
		"schema": SCHEMA,
		"body_id": body_id,
		"frame_id": frame_id,
		"position_m": position_m.duplicate(),
		"max_distance_m": max_distance_m,
		"fluid_type_ids": GeoUtilsScript.sorted_unique_ids(requested_types),
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
	if typeof(value.get("fluid_type_ids")) != TYPE_ARRAY or value["fluid_type_ids"].is_empty():
		return GeoUtilsScript.failure("INVALID_WATER_SURFACE_QUERY_FLUID_TYPES")
	var sorted_validation: Dictionary = GeoUtilsScript.validate_sorted_unique_ids(value["fluid_type_ids"], false)
	if not bool(sorted_validation.get("success", false)):
		return GeoUtilsScript.failure("WATER_SURFACE_QUERY_FLUID_TYPES_NOT_SORTED_UNIQUE")
	for fluid_type_id in value["fluid_type_ids"]:
		var type_validation: Dictionary = FluidTypeScript.validate(fluid_type_id)
		if not bool(type_validation.get("success", false)):
			return GeoUtilsScript.failure("INVALID_WATER_SURFACE_QUERY_FLUID_TYPE", {"fluid_type_id": fluid_type_id})
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.water_surface_query")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return GeoUtilsScript.normalize(value, validate)

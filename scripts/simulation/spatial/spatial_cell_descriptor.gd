extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SpatialUtilsScript = preload("res://scripts/simulation/spatial/spatial_contract_utils.gd")
const CellAddressScript = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")

const SCHEMA: String = "planet_simulator.spatial_cell_descriptor.v1"
const BOUNDS_FIELDS: Array[String] = ["minimum_m", "maximum_m"]
const FIELDS: Array[String] = [
	"schema",
	"address",
	"frame_id",
	"bounds_m",
	"parent_cell_id",
	"child_capacity",
	"descriptor_revision",
]


static func create(
	address: Dictionary,
	frame_id: String,
	minimum_m: Array,
	maximum_m: Array,
	child_capacity: int,
	descriptor_revision: int = 1
) -> Dictionary:
	var parent_address: Dictionary = CellAddressScript.parent(address)
	return {
		"schema": SCHEMA,
		"address": address.duplicate(true),
		"frame_id": frame_id.strip_edges().to_lower(),
		"bounds_m": {
			"minimum_m": minimum_m.duplicate(true),
			"maximum_m": maximum_m.duplicate(true),
		},
		"parent_cell_id": String(parent_address.get("cell_id", "")),
		"child_capacity": child_capacity,
		"descriptor_revision": descriptor_revision,
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return _failure("UNSUPPORTED_SPATIAL_CELL_DESCRIPTOR_SCHEMA")
	if typeof(value.get("address")) != TYPE_DICTIONARY or not bool(CellAddressScript.validate(value["address"]).get("success", false)):
		return _failure("INVALID_SPATIAL_CELL_ADDRESS")
	if not SpatialUtilsScript.is_canonical_id(value.get("frame_id"), 2):
		return _failure("INVALID_SPATIAL_CELL_FRAME")
	if typeof(value.get("bounds_m")) != TYPE_DICTIONARY:
		return _failure("INVALID_SPATIAL_CELL_BOUNDS")
	var bounds: Dictionary = value["bounds_m"]
	var bounds_exact: Dictionary = NetworkUtilsScript.validate_exact_fields(bounds, BOUNDS_FIELDS)
	if not bool(bounds_exact.get("success", false)):
		return _failure("INVALID_SPATIAL_CELL_BOUNDS")
	if not SpatialUtilsScript.is_vector3_array(bounds.get("minimum_m")) or not SpatialUtilsScript.is_vector3_array(bounds.get("maximum_m")):
		return _failure("INVALID_SPATIAL_CELL_BOUNDS")
	var has_extent: bool = false
	for index in range(3):
		var minimum: float = float(bounds["minimum_m"][index])
		var maximum: float = float(bounds["maximum_m"][index])
		if minimum > maximum:
			return _failure("INVALID_SPATIAL_CELL_BOUNDS")
		if maximum > minimum:
			has_extent = true
	if not has_extent:
		return _failure("EMPTY_SPATIAL_CELL_BOUNDS")
	if typeof(value.get("parent_cell_id")) != TYPE_STRING:
		return _failure("INVALID_PARENT_CELL_ID")
	var address: Dictionary = value["address"]
	var expected_parent: Dictionary = CellAddressScript.parent(address)
	var expected_parent_id: String = String(expected_parent.get("cell_id", ""))
	if String(value["parent_cell_id"]) != expected_parent_id:
		return _failure("PARENT_CELL_ID_MISMATCH")
	for field in ["child_capacity", "descriptor_revision"]:
		if not NetworkUtilsScript.is_json_integer(value.get(field)):
			return _failure("INVALID_SPATIAL_CELL_INTEGER", {"field": field})
	if int(value["child_capacity"]) < 1 or int(value["child_capacity"]) > SpatialUtilsScript.MAX_CHILD_INDEX + 1:
		return _failure("INVALID_SPATIAL_CELL_CHILD_CAPACITY")
	if int(value["descriptor_revision"]) < 1:
		return _failure("INVALID_SPATIAL_CELL_DESCRIPTOR_REVISION")
	return NetworkUtilsScript.validation_success()


static func cell_id(value: Dictionary) -> String:
	return String(value.get("address", {}).get("cell_id", ""))


static func normalize(value: Dictionary) -> Dictionary:
	if not bool(validate(value).get("success", false)):
		return {}
	var round_trip: Dictionary = NetworkUtilsScript.json_round_trip(value)
	return Dictionary(round_trip.get("value", {})) if bool(round_trip.get("success", false)) else {}


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}

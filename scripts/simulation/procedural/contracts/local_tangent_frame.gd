extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")

const SCHEMA: String = "planet_simulator.local_tangent_frame.v1"
const FIELDS: Array[String] = [
	"schema",
	"body_id",
	"anchor_body_fixed_position_m",
	"east",
	"north",
	"up",
	"checksum",
]
const ORTHONORMAL_TOLERANCE: float = 0.00000001


static func create(
	body_id: String,
	anchor_body_fixed_position_m: Array,
	east: Array,
	north: Array,
	up: Array
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"body_id": body_id,
		"anchor_body_fixed_position_m": anchor_body_fixed_position_m.duplicate(true),
		"east": east.duplicate(true),
		"north": north.duplicate(true),
		"up": up.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = GeoUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return GeoUtilsScript.failure("UNSUPPORTED_LOCAL_TANGENT_FRAME_SCHEMA")
	if not GeoUtilsScript.is_canonical_id(value.get("body_id"), 2):
		return GeoUtilsScript.failure("INVALID_LOCAL_TANGENT_FRAME_BODY_ID")
	for field in ["anchor_body_fixed_position_m", "east", "north", "up"]:
		if not GeoUtilsScript.is_vector3_array(value.get(field)):
			return GeoUtilsScript.failure("INVALID_LOCAL_TANGENT_FRAME_VECTOR", {"field": field})
	var east: Vector3 = _vector3(Array(value["east"]))
	var north: Vector3 = _vector3(Array(value["north"]))
	var up: Vector3 = _vector3(Array(value["up"]))
	for pair in [["east", east], ["north", north], ["up", up]]:
		if absf(Vector3(pair[1]).length() - 1.0) > ORTHONORMAL_TOLERANCE:
			return GeoUtilsScript.failure("LOCAL_TANGENT_FRAME_AXIS_NOT_UNIT", {"axis": String(pair[0])})
	if absf(east.dot(north)) > ORTHONORMAL_TOLERANCE or absf(east.dot(up)) > ORTHONORMAL_TOLERANCE or absf(north.dot(up)) > ORTHONORMAL_TOLERANCE:
		return GeoUtilsScript.failure("LOCAL_TANGENT_FRAME_NOT_ORTHOGONAL")
	var expected_north: Vector3 = east.cross(up)
	if expected_north.length_squared() <= 0.0 or expected_north.normalized().dot(north) < 1.0 - ORTHONORMAL_TOLERANCE:
		return GeoUtilsScript.failure("LOCAL_TANGENT_FRAME_HANDEDNESS_MISMATCH")
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.local_tangent_frame")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return GeoUtilsScript.normalize(value, validate)


static func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

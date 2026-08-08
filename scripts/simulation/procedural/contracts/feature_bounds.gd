extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")

const SCHEMA: String = "planet_simulator.feature_bounds.v1"
const KIND_SPHERE: String = "SPHERE"
const KIND_AABB: String = "AABB"
const KINDS: Array[String] = [KIND_SPHERE, KIND_AABB]
const FIELDS: Array[String] = [
	"schema",
	"frame_id",
	"kind",
	"center_m",
	"radius_m",
	"half_extents_m",
	"checksum",
]


static func sphere(frame_id: String, center_m: Array, radius_m: float) -> Dictionary:
	return create(frame_id, KIND_SPHERE, center_m, radius_m, [0.0, 0.0, 0.0])


static func aabb(frame_id: String, center_m: Array, half_extents_m: Array) -> Dictionary:
	return create(frame_id, KIND_AABB, center_m, 0.0, half_extents_m)


static func create(frame_id: String, kind: String, center_m: Array, radius_m: float, half_extents_m: Array) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"frame_id": frame_id,
		"kind": kind.to_upper(),
		"center_m": center_m.duplicate(),
		"radius_m": radius_m,
		"half_extents_m": half_extents_m.duplicate(),
		"checksum": "",
	}
	value["checksum"] = GeoUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return GeoUtilsScript.failure("UNSUPPORTED_FEATURE_BOUNDS_SCHEMA")
	if not GeoUtilsScript.is_canonical_id(value.get("frame_id"), 2):
		return GeoUtilsScript.failure("INVALID_FEATURE_BOUNDS_FRAME_ID")
	if typeof(value.get("kind")) != TYPE_STRING or not KINDS.has(String(value["kind"])):
		return GeoUtilsScript.failure("INVALID_FEATURE_BOUNDS_KIND")
	if not GeoUtilsScript.is_vector3_array(value.get("center_m")):
		return GeoUtilsScript.failure("INVALID_FEATURE_BOUNDS_CENTER")
	if not GeoUtilsScript.is_non_negative_number(value.get("radius_m")):
		return GeoUtilsScript.failure("INVALID_FEATURE_BOUNDS_RADIUS")
	if not GeoUtilsScript.is_vector3_array(value.get("half_extents_m")):
		return GeoUtilsScript.failure("INVALID_FEATURE_BOUNDS_HALF_EXTENTS")
	for component in value["half_extents_m"]:
		if float(component) < 0.0:
			return GeoUtilsScript.failure("INVALID_FEATURE_BOUNDS_HALF_EXTENTS")
	if String(value["kind"]) == KIND_SPHERE:
		if float(value["radius_m"]) <= 0.0:
			return GeoUtilsScript.failure("FEATURE_SPHERE_RADIUS_NOT_POSITIVE")
		for component in value["half_extents_m"]:
			if float(component) != 0.0:
				return GeoUtilsScript.failure("FEATURE_SPHERE_HAS_AABB_EXTENTS")
	else:
		if float(value["radius_m"]) != 0.0:
			return GeoUtilsScript.failure("FEATURE_AABB_HAS_SPHERE_RADIUS")
		for component in value["half_extents_m"]:
			if float(component) <= 0.0:
				return GeoUtilsScript.failure("FEATURE_AABB_EXTENT_NOT_POSITIVE")
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.feature_bounds")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)


static func contains_point(value: Dictionary, point_m: Array) -> bool:
	if not bool(validate(value).get("success", false)) or not GeoUtilsScript.is_vector3_array(point_m):
		return false
	var center := _vector3(value["center_m"])
	var point := _vector3(point_m)
	if String(value["kind"]) == KIND_SPHERE:
		var radius: float = float(value["radius_m"])
		return center.distance_squared_to(point) <= radius * radius
	var extents := _vector3(value["half_extents_m"])
	var delta := point - center
	return absf(delta.x) <= extents.x and absf(delta.y) <= extents.y and absf(delta.z) <= extents.z


static func intersects_sphere(value: Dictionary, center_m: Array, radius_m: float) -> bool:
	if not bool(validate(value).get("success", false)):
		return false
	if not GeoUtilsScript.is_vector3_array(center_m) or not GeoUtilsScript.is_non_negative_number(radius_m):
		return false
	var bounds_center := _vector3(value["center_m"])
	var query_center := _vector3(center_m)
	var query_radius: float = float(radius_m)
	if String(value["kind"]) == KIND_SPHERE:
		var combined: float = float(value["radius_m"]) + query_radius
		return bounds_center.distance_squared_to(query_center) <= combined * combined
	var extents := _vector3(value["half_extents_m"])
	var closest := Vector3(
		clampf(query_center.x, bounds_center.x - extents.x, bounds_center.x + extents.x),
		clampf(query_center.y, bounds_center.y - extents.y, bounds_center.y + extents.y),
		clampf(query_center.z, bounds_center.z - extents.z, bounds_center.z + extents.z)
	)
	return closest.distance_squared_to(query_center) <= query_radius * query_radius


static func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

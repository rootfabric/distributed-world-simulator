extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const FluidRegionIdScript = preload("res://scripts/simulation/procedural/contracts/fluid_region_id.gd")

const SCHEMA: String = "planet_simulator.river_spline.v1"
const PREFIX: String = "river-spline/"
const STABLE_KEY_PREFIX: String = "river-spline-key/"
const FIELDS: Array[String] = [
	"schema",
	"spline_id",
	"fluid_region_id",
	"stable_key",
	"frame_id",
	"points_m",
	"checksum",
]


static func create(fluid_region_id: String, stable_key: String, frame_id: String, points_m: Array) -> Dictionary:
	var canonical_points: Array = []
	for raw_point in points_m:
		if raw_point is Array:
			canonical_points.append(Array(raw_point).duplicate())
		else:
			canonical_points.append(raw_point)
	var value: Dictionary = {
		"schema": SCHEMA,
		"spline_id": _derive_id(fluid_region_id, stable_key),
		"fluid_region_id": fluid_region_id,
		"stable_key": stable_key,
		"frame_id": frame_id,
		"points_m": canonical_points,
		"checksum": "",
	}
	value["checksum"] = GeoUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return GeoUtilsScript.failure("UNSUPPORTED_RIVER_SPLINE_SCHEMA")
	var region_validation: Dictionary = FluidRegionIdScript.validate(value.get("fluid_region_id"))
	if not bool(region_validation.get("success", false)):
		return region_validation
	if not GeoUtilsScript.is_canonical_id(value.get("stable_key"), 2) or not String(value["stable_key"]).begins_with(STABLE_KEY_PREFIX):
		return GeoUtilsScript.failure("INVALID_RIVER_SPLINE_STABLE_KEY")
	if not GeoUtilsScript.is_canonical_id(value.get("frame_id"), 2):
		return GeoUtilsScript.failure("INVALID_RIVER_SPLINE_FRAME_ID")
	if typeof(value.get("spline_id")) != TYPE_STRING or String(value["spline_id"]) != _derive_id(String(value["fluid_region_id"]), String(value["stable_key"])):
		return GeoUtilsScript.failure("RIVER_SPLINE_IDENTITY_MISMATCH")
	if typeof(value.get("points_m")) != TYPE_ARRAY or value["points_m"].size() < 2:
		return GeoUtilsScript.failure("INVALID_RIVER_SPLINE_POINTS")
	var previous: Array = []
	for index in range(value["points_m"].size()):
		var point = value["points_m"][index]
		if not GeoUtilsScript.is_vector3_array(point):
			return GeoUtilsScript.failure("INVALID_RIVER_SPLINE_POINT", {"index": index})
		if index > 0 and _distance_squared(previous, point) <= GeoUtilsScript.DEFAULT_FLOAT_TOLERANCE:
			return GeoUtilsScript.failure("DEGENERATE_RIVER_SPLINE_SEGMENT", {"index": index - 1})
		previous = point
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.river_spline")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return GeoUtilsScript.normalize(value, validate)


static func _derive_id(fluid_region_id: String, stable_key: String) -> String:
	if not bool(FluidRegionIdScript.validate(fluid_region_id).get("success", false)):
		return ""
	if not GeoUtilsScript.is_canonical_id(stable_key, 2) or not stable_key.begins_with(STABLE_KEY_PREFIX):
		return ""
	return "%s%s" % [PREFIX, GeoUtilsScript.payload_hash({"fluid_region_id": fluid_region_id, "stable_key": stable_key})]


static func _distance_squared(a: Array, b: Array) -> float:
	var dx: float = float(a[0]) - float(b[0])
	var dy: float = float(a[1]) - float(b[1])
	var dz: float = float(a[2]) - float(b[2])
	return dx * dx + dy * dy + dz * dz

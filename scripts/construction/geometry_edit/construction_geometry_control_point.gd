extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")

const SCHEMA := "planet_simulator.construction_geometry_control_point.v1"
const FIELDS: Array[String] = ["schema", "point_id", "ordinal", "position_m"]

static func create(point_id: String, ordinal: int, position_m: Array) -> Dictionary:
	return {
		"schema": SCHEMA,
		"point_id": point_id,
		"ordinal": ordinal,
		"position_m": _metric_vector(position_m),
	}

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return ParametricUtils.failure("UNSUPPORTED_CONSTRUCTION_GEOMETRY_CONTROL_POINT_SCHEMA")
	if not ParametricUtils.path_id(String(value.get("point_id", "")), "geometry-point/"):
		return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_CONTROL_POINT_ID")
	if not UtilsScript.is_json_integer(value.get("ordinal")) or int(value["ordinal"]) < 0:
		return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_CONTROL_POINT_ORDINAL")
	if not _valid_vector(value.get("position_m")):
		return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_CONTROL_POINT_POSITION")
	if not bool(UtilsScript.canonicalize(value).get("success", false)):
		return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_CONTROL_POINT_NOT_JSON_SAFE")
	return ParametricUtils.success()

static func _valid_vector(value) -> bool:
	if typeof(value) != TYPE_ARRAY or Array(value).size() != 3:
		return false
	for component in value:
		if typeof(component) not in [TYPE_INT, TYPE_FLOAT] or is_nan(float(component)) or is_inf(float(component)):
			return false
	return true

static func _metric_vector(value: Array) -> Array:
	if value.size() != 3:
		return value.duplicate(true)
	return [ParametricUtils.metric(float(value[0])), ParametricUtils.metric(float(value[1])), ParametricUtils.metric(float(value[2]))]

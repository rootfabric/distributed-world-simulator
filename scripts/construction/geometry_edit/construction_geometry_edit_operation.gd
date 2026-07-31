extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const PointScript = preload("res://scripts/construction/geometry_edit/construction_geometry_control_point.gd")

const SCHEMA := "planet_simulator.construction_geometry_edit_operation.v1"
const FIELDS: Array[String] = ["schema", "operation_id", "sequence", "operation_kind", "target_id", "payload", "checksum"]
const KINDS: Array[String] = ["SET_PARAMETER", "MOVE_CONTROL_POINT", "INSERT_CONTROL_POINT", "REMOVE_CONTROL_POINT"]

static func create(operation_id: String, sequence: int, operation_kind: String, target_id: String, payload: Dictionary = {}) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"operation_id": operation_id,
		"sequence": sequence,
		"operation_kind": operation_kind,
		"target_id": target_id,
		"payload": payload.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return ParametricUtils.failure("UNSUPPORTED_CONSTRUCTION_GEOMETRY_EDIT_OPERATION_SCHEMA")
	if not ParametricUtils.path_id(String(value.get("operation_id", "")), "geometry-operation/"):
		return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_OPERATION_ID")
	if not UtilsScript.is_json_integer(value.get("sequence")) or int(value["sequence"]) < 0:
		return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_OPERATION_SEQUENCE")
	var kind := String(value.get("operation_kind", ""))
	if not KINDS.has(kind): return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_OPERATION_KIND")
	if typeof(value.get("target_id")) != TYPE_STRING or typeof(value.get("payload")) != TYPE_DICTIONARY:
		return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_OPERATION_PAYLOAD")
	var target := String(value["target_id"])
	var payload: Dictionary = value["payload"]
	match kind:
		"SET_PARAMETER":
			if not target.begins_with("parameter/") or target.length() <= 10: return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_OPERATION_TARGET")
			var checked := UtilsScript.validate_exact_fields(payload, ["value"]); if not bool(checked.get("success", false)): return checked
			if not ParametricUtils.positive_number(payload.get("value")): return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_PARAMETER_VALUE")
		"MOVE_CONTROL_POINT":
			if not ParametricUtils.path_id(target, "geometry-point/"): return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_OPERATION_TARGET")
			var checked := UtilsScript.validate_exact_fields(payload, ["position_m"]); if not bool(checked.get("success", false)): return checked
			if not PointScript._valid_vector(payload.get("position_m")): return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_POINT_POSITION")
		"INSERT_CONTROL_POINT":
			if not ParametricUtils.path_id(target, "geometry-point/"): return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_OPERATION_TARGET")
			var checked := UtilsScript.validate_exact_fields(payload, ["after_point_id", "position_m"]); if not bool(checked.get("success", false)): return checked
			if not ParametricUtils.path_id(String(payload.get("after_point_id", "")), "geometry-point/") or not PointScript._valid_vector(payload.get("position_m")): return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_INSERT_PAYLOAD")
		"REMOVE_CONTROL_POINT":
			if not ParametricUtils.path_id(target, "geometry-point/"): return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_OPERATION_TARGET")
			var checked := UtilsScript.validate_exact_fields(payload, []); if not bool(checked.get("success", false)): return checked
	if String(value.get("checksum", "")) != compute_checksum(value): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_OPERATION_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_OPERATION_NOT_JSON_SAFE")
	return ParametricUtils.success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)

extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")

const SCHEMA := "planet_simulator.construction_geometry_edit_constraint.v1"
const FIELDS: Array[String] = ["schema", "constraint_id", "constraint_kind", "target", "parameters", "checksum"]
const KINDS: Array[String] = ["GRID_SNAP", "LOCK_PARAMETER", "LOCK_CONTROL_POINT", "LOCK_AXES", "MIN_SEGMENT_LENGTH", "MAX_TOTAL_LENGTH", "ORTHOGONAL_PATH"]
const AXES: Array[String] = ["X", "Y", "Z"]

static func create(constraint_id: String, constraint_kind: String, target: String, parameters: Dictionary = {}) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"constraint_id": constraint_id,
		"constraint_kind": constraint_kind,
		"target": target,
		"parameters": parameters.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return ParametricUtils.failure("UNSUPPORTED_CONSTRUCTION_GEOMETRY_EDIT_CONSTRAINT_SCHEMA")
	if not ParametricUtils.path_id(String(value.get("constraint_id", "")), "geometry-constraint/"):
		return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_CONSTRAINT_ID")
	var kind := String(value.get("constraint_kind", ""))
	if not KINDS.has(kind):
		return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_CONSTRAINT_KIND")
	if typeof(value.get("target")) != TYPE_STRING or String(value["target"]).is_empty():
		return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_CONSTRAINT_TARGET")
	if typeof(value.get("parameters")) != TYPE_DICTIONARY:
		return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_CONSTRAINT_PARAMETERS")
	var parameters: Dictionary = value["parameters"]
	match kind:
		"GRID_SNAP":
			if String(value["target"]) != "PATH": return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_CONSTRAINT_TARGET")
			var checked := UtilsScript.validate_exact_fields(parameters, ["step_m"]); if not bool(checked.get("success", false)): return checked
			if not ParametricUtils.positive_number(parameters.get("step_m")): return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_GRID_STEP")
		"LOCK_PARAMETER":
			if not String(value["target"]).begins_with("parameter/") or String(value["target"]).length() <= 10: return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_CONSTRAINT_TARGET")
			var checked := UtilsScript.validate_exact_fields(parameters, []); if not bool(checked.get("success", false)): return checked
		"LOCK_CONTROL_POINT":
			if not ParametricUtils.path_id(String(value["target"]), "geometry-point/"): return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_CONSTRAINT_TARGET")
			var checked := UtilsScript.validate_exact_fields(parameters, []); if not bool(checked.get("success", false)): return checked
		"LOCK_AXES":
			if not ParametricUtils.path_id(String(value["target"]), "geometry-point/"): return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_CONSTRAINT_TARGET")
			var checked := UtilsScript.validate_exact_fields(parameters, ["axes"]); if not bool(checked.get("success", false)): return checked
			if typeof(parameters.get("axes")) != TYPE_ARRAY or Array(parameters["axes"]).is_empty(): return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_LOCK_AXES")
			var axes: Array = parameters["axes"]
			var sorted := axes.duplicate(); sorted.sort()
			if axes != sorted: return ParametricUtils.failure("NON_CANONICAL_CONSTRUCTION_GEOMETRY_LOCK_AXES")
			var seen := {}
			for axis in axes:
				if typeof(axis) != TYPE_STRING or not AXES.has(String(axis)) or seen.has(String(axis)): return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_LOCK_AXES")
				seen[String(axis)] = true
		"MIN_SEGMENT_LENGTH":
			if String(value["target"]) != "PATH": return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_CONSTRAINT_TARGET")
			var checked := UtilsScript.validate_exact_fields(parameters, ["minimum_m"]); if not bool(checked.get("success", false)): return checked
			if not ParametricUtils.positive_number(parameters.get("minimum_m")): return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_MIN_SEGMENT_LENGTH")
		"MAX_TOTAL_LENGTH":
			if String(value["target"]) != "PATH": return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_CONSTRAINT_TARGET")
			var checked := UtilsScript.validate_exact_fields(parameters, ["maximum_m"]); if not bool(checked.get("success", false)): return checked
			if not ParametricUtils.positive_number(parameters.get("maximum_m")): return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_MAX_TOTAL_LENGTH")
		"ORTHOGONAL_PATH":
			if String(value["target"]) != "PATH": return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_CONSTRAINT_TARGET")
			var checked := UtilsScript.validate_exact_fields(parameters, []); if not bool(checked.get("success", false)): return checked
	if String(value.get("checksum", "")) != compute_checksum(value):
		return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_CONSTRAINT_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)):
		return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_CONSTRAINT_NOT_JSON_SAFE")
	return ParametricUtils.success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)

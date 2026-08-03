extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const DefinitionScript = preload("res://scripts/construction/parametric/construction_parametric_member_definition.gd")
const InstanceScript = preload("res://scripts/construction/parametric/construction_parametric_member_instance.gd")
const CompilerScript = preload("res://scripts/construction/parametric/construction_parametric_compiler.gd")
const RequestScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_request.gd")
const StateScript = preload("res://scripts/construction/geometry_edit/construction_local_geometry_state.gd")
const PointScript = preload("res://scripts/construction/geometry_edit/construction_geometry_control_point.gd")
const ConstraintScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_constraint.gd")

static func compile(current_instance: Dictionary, definition: Dictionary, materials: Array, request: Dictionary) -> Dictionary:
	var checked := InstanceScript.validate(current_instance); if not bool(checked.get("success", false)): return checked
	checked = DefinitionScript.validate(definition); if not bool(checked.get("success", false)): return checked
	checked = RequestScript.validate(request); if not bool(checked.get("success", false)): return checked
	if String(current_instance["member_instance_id"]) != String(request["member_instance_id"]) or String(current_instance["item_instance_id"]) != String(request["item_instance_id"]): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_MEMBER_IDENTITY_MISMATCH")
	if String(current_instance["checksum"]) != String(request["expected_member_checksum"]): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_MEMBER_PRECONDITION_MISMATCH")
	if String(definition["member_definition_id"]) != String(current_instance["member_definition_id"]) or int(definition["definition_version"]) != int(current_instance["definition_version"]) or String(definition["checksum"]) != String(current_instance["definition_checksum"]): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_DEFINITION_PRECONDITION_MISMATCH")
	var state_result := _current_state(current_instance)
	if not bool(state_result.get("success", false)): return state_result
	var before_state: Dictionary = state_result["state"]
	if int(before_state["edit_revision"]) != int(request["expected_edit_revision"]): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_REVISION_PRECONDITION_MISMATCH")
	var constraints: Array = Array(request["constraints"]).duplicate(true) if not Array(request["constraints"]).is_empty() else Array(before_state["constraints"]).duplicate(true)
	for constraint in constraints:
		checked = ConstraintScript.validate(constraint); if not bool(checked.get("success", false)): return checked
	var points: Array = Array(before_state["control_points"]).duplicate(true)
	var parameters: Dictionary = Dictionary(current_instance["parameter_values"]).duplicate(true)
	for operation in request["operations"]:
		var applied := _apply_operation(points, parameters, operation, constraints)
		if not bool(applied.get("success", false)): return applied
		points = applied["points"]; parameters = applied["parameters"]
	points = _snap_points(points, constraints)
	points = StateScript._normalize_points(points)
	var constraint_validation := _validate_path_constraints(points, constraints)
	if not bool(constraint_validation.get("success", false)): return constraint_validation
	var path_length := StateScript.path_length(points)
	if not parameters.has("length_m"): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_MEMBER_HAS_NO_LENGTH_PARAMETER")
	parameters["length_m"] = ParametricUtils.metric(path_length)
	var after_state := StateScript.create(String(current_instance["member_instance_id"]), String(current_instance["item_instance_id"]), int(before_state["edit_revision"]) + 1, points, constraints, String(request["edit_id"]), String(current_instance["checksum"]))
	checked = StateScript.validate(after_state); if not bool(checked.get("success", false)): return checked
	var provenance: Dictionary = Dictionary(current_instance["provenance"]).duplicate(true)
	provenance["local_geometry_edit_state"] = after_state.duplicate(true)
	provenance["last_geometry_edit_request_checksum"] = String(request["checksum"])
	var compiled := CompilerScript.compile(definition, materials, parameters, String(current_instance["member_instance_id"]), String(current_instance["item_instance_id"]), provenance)
	if not bool(compiled.get("success", false)): return compiled
	var updated_instance: Dictionary = compiled["instance"]
	if String(updated_instance["checksum"]) == String(current_instance["checksum"]): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_DID_NOT_CHANGE_MEMBER")
	return ParametricUtils.success({
		"before_state": before_state,
		"after_state": after_state,
		"updated_instance": updated_instance,
		"material_deltas": _material_deltas(current_instance["material_usage"], updated_instance["material_usage"]),
	})

static func _current_state(instance: Dictionary) -> Dictionary:
	var provenance: Dictionary = instance.get("provenance", {})
	var raw = provenance.get("local_geometry_edit_state", {})
	if raw is Dictionary and not Dictionary(raw).is_empty():
		var checked := StateScript.validate(raw); if not bool(checked.get("success", false)): return checked
		if String(raw["member_instance_id"]) != String(instance["member_instance_id"]) or String(raw["item_instance_id"]) != String(instance["item_instance_id"]): return ParametricUtils.failure("CONSTRUCTION_LOCAL_GEOMETRY_STATE_IDENTITY_MISMATCH")
		return ParametricUtils.success({"state": Dictionary(raw).duplicate(true)})
	var state := StateScript.bootstrap(instance)
	var checked := StateScript.validate(state); if not bool(checked.get("success", false)): return checked
	return ParametricUtils.success({"state": state})

static func _apply_operation(points: Array, parameters: Dictionary, operation: Dictionary, constraints: Array) -> Dictionary:
	var next_points := points.duplicate(true); var next_parameters := parameters.duplicate(true)
	var kind := String(operation["operation_kind"]); var target := String(operation["target_id"]); var payload: Dictionary = operation["payload"]
	match kind:
		"SET_PARAMETER":
			var parameter := target.trim_prefix("parameter/")
			if not next_parameters.has(parameter): return ParametricUtils.failure("UNKNOWN_CONSTRUCTION_GEOMETRY_EDIT_PARAMETER")
			if _has_constraint(constraints, "LOCK_PARAMETER", target): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_PARAMETER_LOCKED")
			var value := ParametricUtils.metric(float(payload["value"]))
			if parameter == "length_m":
				var current_length := StateScript.path_length(next_points)
				if current_length <= 0.0: return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_ZERO_LENGTH_PATH")
				var origin: Array = next_points[0]["position_m"]
				var ratio := value / current_length
				for index in range(1, next_points.size()):
					var position: Array = next_points[index]["position_m"]
					next_points[index] = PointScript.create(String(next_points[index]["point_id"]), index, [float(origin[0]) + (float(position[0]) - float(origin[0])) * ratio, float(origin[1]) + (float(position[1]) - float(origin[1])) * ratio, float(origin[2]) + (float(position[2]) - float(origin[2])) * ratio])
			else:
				next_parameters[parameter] = value
		"MOVE_CONTROL_POINT":
			var index := _point_index(next_points, target); if index < 0: return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_CONTROL_POINT_NOT_FOUND")
			if _has_constraint(constraints, "LOCK_CONTROL_POINT", target): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_CONTROL_POINT_LOCKED")
			var old_position: Array = next_points[index]["position_m"]; var new_position: Array = _metric_vector(payload["position_m"])
			var axis_check := _validate_locked_axes(target, old_position, new_position, constraints); if not bool(axis_check.get("success", false)): return axis_check
			next_points[index] = PointScript.create(target, index, new_position)
		"INSERT_CONTROL_POINT":
			if _point_index(next_points, target) >= 0: return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_CONTROL_POINT_ALREADY_EXISTS")
			var after_index := _point_index(next_points, String(payload["after_point_id"])); if after_index < 0: return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_INSERT_ANCHOR_NOT_FOUND")
			next_points.insert(after_index + 1, PointScript.create(target, after_index + 1, _metric_vector(payload["position_m"])))
			next_points = StateScript._normalize_points(next_points)
		"REMOVE_CONTROL_POINT":
			var index := _point_index(next_points, target); if index < 0: return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_CONTROL_POINT_NOT_FOUND")
			if next_points.size() <= 2: return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_MINIMUM_CONTROL_POINTS")
			if index == 0 or index == next_points.size() - 1: return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_ENDPOINT_REMOVAL_FORBIDDEN")
			if _has_constraint(constraints, "LOCK_CONTROL_POINT", target): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_CONTROL_POINT_LOCKED")
			next_points.remove_at(index); next_points = StateScript._normalize_points(next_points)
		_:
			return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_OPERATION_KIND")
	return ParametricUtils.success({"points": next_points, "parameters": next_parameters})

static func _snap_points(points: Array, constraints: Array) -> Array:
	var step := 0.0
	for constraint in constraints:
		if String(constraint["constraint_kind"]) == "GRID_SNAP": step = float(constraint["parameters"]["step_m"])
	if step <= 0.0: return points
	var output: Array = []
	for point in points:
		var position: Array = point["position_m"]
		output.append(PointScript.create(String(point["point_id"]), int(point["ordinal"]), [round(float(position[0]) / step) * step, round(float(position[1]) / step) * step, round(float(position[2]) / step) * step]))
	return output

static func _validate_path_constraints(points: Array, constraints: Array) -> Dictionary:
	for index in range(1, points.size()):
		var length := _segment_length(points[index - 1]["position_m"], points[index]["position_m"])
		if length <= ParametricUtils.EPSILON: return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_ZERO_LENGTH_SEGMENT")
		for constraint in constraints:
			var kind := String(constraint["constraint_kind"])
			if kind == "MIN_SEGMENT_LENGTH" and length < float(constraint["parameters"]["minimum_m"]): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_MIN_SEGMENT_LENGTH_VIOLATED")
			if kind == "ORTHOGONAL_PATH" and not _orthogonal_segment(points[index - 1]["position_m"], points[index]["position_m"]): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_ORTHOGONAL_PATH_VIOLATED")
	var total := StateScript.path_length(points)
	for constraint in constraints:
		if String(constraint["constraint_kind"]) == "MAX_TOTAL_LENGTH" and total > float(constraint["parameters"]["maximum_m"]): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_MAX_TOTAL_LENGTH_VIOLATED")
	return ParametricUtils.success()

static func _validate_locked_axes(point_id: String, before: Array, after: Array, constraints: Array) -> Dictionary:
	for constraint in constraints:
		if String(constraint["constraint_kind"]) != "LOCK_AXES" or String(constraint["target"]) != point_id: continue
		for axis in constraint["parameters"]["axes"]:
			var index: int = int({"X": 0, "Y": 1, "Z": 2}[String(axis)])
			if not ParametricUtils.nearly_equal(float(before[index]), float(after[index])): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_LOCKED_AXIS_CHANGED", {"axis": axis})
	return ParametricUtils.success()

static func _has_constraint(constraints: Array, kind: String, target: String) -> bool:
	for constraint in constraints:
		if String(constraint["constraint_kind"]) == kind and String(constraint["target"]) == target: return true
	return false
static func _point_index(points: Array, point_id: String) -> int:
	for index in range(points.size()):
		if String(points[index]["point_id"]) == point_id: return index
	return -1
static func _metric_vector(value: Array) -> Array:
	return [ParametricUtils.metric(float(value[0])), ParametricUtils.metric(float(value[1])), ParametricUtils.metric(float(value[2]))]
static func _segment_length(left: Array, right: Array) -> float:
	var dx := float(right[0]) - float(left[0]); var dy := float(right[1]) - float(left[1]); var dz := float(right[2]) - float(left[2]); return sqrt(dx*dx + dy*dy + dz*dz)
static func _orthogonal_segment(left: Array, right: Array) -> bool:
	var changed := 0
	for axis in range(3):
		if not ParametricUtils.nearly_equal(float(left[axis]), float(right[axis])): changed += 1
	return changed == 1
static func _material_deltas(before_usage: Array, after_usage: Array) -> Array:
	var before := {}
	var after := {}
	var ids: Array = []
	for usage in before_usage:
		var material_id := String(usage["material_id"])
		before[material_id] = float(usage["mass_kg"])
		if not ids.has(material_id):
			ids.append(material_id)
	for usage in after_usage:
		var material_id := String(usage["material_id"])
		after[material_id] = float(usage["mass_kg"])
		if not ids.has(material_id):
			ids.append(material_id)
	ids.sort()
	var output: Array = []
	for material_id in ids:
		var before_mass := ParametricUtils.metric(float(before.get(material_id, 0.0)))
		var after_mass := ParametricUtils.metric(float(after.get(material_id, 0.0)))
		output.append({"material_id": material_id, "before_mass_kg": before_mass, "after_mass_kg": after_mass, "delta_mass_kg": ParametricUtils.metric(after_mass - before_mass)})
	return output

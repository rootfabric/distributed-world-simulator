extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const PointScript = preload("res://scripts/construction/geometry_edit/construction_geometry_control_point.gd")
const ConstraintScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_constraint.gd")

const SCHEMA := "planet_simulator.construction_local_geometry_state.v1"
const FIELDS: Array[String] = ["schema", "member_instance_id", "item_instance_id", "edit_revision", "geometry_mode", "control_points", "path_length_m", "bounding_box_m", "constraints", "last_edit_id", "source_member_checksum", "checksum"]
const MODE_POLYLINE := "POLYLINE"

static func create(member_instance_id: String, item_instance_id: String, edit_revision: int, control_points: Array, constraints: Array, last_edit_id: String, source_member_checksum: String) -> Dictionary:
	var normalized := _normalize_points(control_points)
	var value := {
		"schema": SCHEMA,
		"member_instance_id": member_instance_id,
		"item_instance_id": item_instance_id,
		"edit_revision": edit_revision,
		"geometry_mode": MODE_POLYLINE,
		"control_points": normalized,
		"path_length_m": ParametricUtils.metric(path_length(normalized)),
		"bounding_box_m": bounding_box(normalized),
		"constraints": _sorted_constraints(constraints),
		"last_edit_id": last_edit_id,
		"source_member_checksum": source_member_checksum,
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value

static func bootstrap(instance: Dictionary, constraints: Array = []) -> Dictionary:
	var length_m := float(instance.get("geometry", {}).get("length_m", 0.0))
	return create(
		String(instance.get("member_instance_id", "")),
		String(instance.get("item_instance_id", "")),
		0,
		[
			PointScript.create("geometry-point/start", 0, [0.0, 0.0, 0.0]),
			PointScript.create("geometry-point/end", 1, [length_m, 0.0, 0.0]),
		],
		constraints,
		"geometry-edit/bootstrap",
		String(instance.get("checksum", ""))
	)

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return ParametricUtils.failure("UNSUPPORTED_CONSTRUCTION_LOCAL_GEOMETRY_STATE_SCHEMA")
	if not ParametricUtils.path_id(String(value.get("member_instance_id", "")), "parametric-member/"): return ParametricUtils.failure("INVALID_CONSTRUCTION_LOCAL_GEOMETRY_MEMBER_ID")
	if not ParametricUtils.path_id(String(value.get("item_instance_id", "")), "item/"): return ParametricUtils.failure("INVALID_CONSTRUCTION_LOCAL_GEOMETRY_ITEM_ID")
	if not UtilsScript.is_json_integer(value.get("edit_revision")) or int(value["edit_revision"]) < 0: return ParametricUtils.failure("INVALID_CONSTRUCTION_LOCAL_GEOMETRY_EDIT_REVISION")
	if value.get("geometry_mode") != MODE_POLYLINE: return ParametricUtils.failure("INVALID_CONSTRUCTION_LOCAL_GEOMETRY_MODE")
	if typeof(value.get("control_points")) != TYPE_ARRAY or Array(value["control_points"]).size() < 2: return ParametricUtils.failure("CONSTRUCTION_LOCAL_GEOMETRY_CONTROL_POINTS_REQUIRED")
	var seen := {}; var expected_ordinal := 0
	for point in value["control_points"]:
		if typeof(point) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_LOCAL_GEOMETRY_CONTROL_POINT")
		var checked := PointScript.validate(point); if not bool(checked.get("success", false)): return checked
		if int(point["ordinal"]) != expected_ordinal: return ParametricUtils.failure("NON_CANONICAL_CONSTRUCTION_LOCAL_GEOMETRY_POINT_ORDER")
		var point_id := String(point["point_id"]); if seen.has(point_id): return ParametricUtils.failure("DUPLICATE_CONSTRUCTION_LOCAL_GEOMETRY_CONTROL_POINT")
		seen[point_id] = true; expected_ordinal += 1
	if not ParametricUtils.positive_number(value.get("path_length_m")) or not ParametricUtils.nearly_equal(float(value["path_length_m"]), path_length(value["control_points"])): return ParametricUtils.failure("CONSTRUCTION_LOCAL_GEOMETRY_PATH_LENGTH_MISMATCH")
	if typeof(value.get("bounding_box_m")) != TYPE_ARRAY or Array(value["bounding_box_m"]).size() != 3: return ParametricUtils.failure("INVALID_CONSTRUCTION_LOCAL_GEOMETRY_BOUNDING_BOX")
	for component in value["bounding_box_m"]:
		if not ParametricUtils.non_negative_number(component): return ParametricUtils.failure("INVALID_CONSTRUCTION_LOCAL_GEOMETRY_BOUNDING_BOX")
	if not _canonical_equal(value["bounding_box_m"], bounding_box(value["control_points"])): return ParametricUtils.failure("CONSTRUCTION_LOCAL_GEOMETRY_BOUNDING_BOX_MISMATCH")
	if typeof(value.get("constraints")) != TYPE_ARRAY or value["constraints"] != _sorted_constraints(value["constraints"]): return ParametricUtils.failure("NON_CANONICAL_CONSTRUCTION_LOCAL_GEOMETRY_CONSTRAINTS")
	var constraint_ids := {}
	for constraint in value["constraints"]:
		if typeof(constraint) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_LOCAL_GEOMETRY_CONSTRAINT")
		var checked := ConstraintScript.validate(constraint); if not bool(checked.get("success", false)): return checked
		var cid := String(constraint["constraint_id"]); if constraint_ids.has(cid): return ParametricUtils.failure("DUPLICATE_CONSTRUCTION_LOCAL_GEOMETRY_CONSTRAINT")
		constraint_ids[cid] = true
	if not ParametricUtils.path_id(String(value.get("last_edit_id", "")), "geometry-edit/"): return ParametricUtils.failure("INVALID_CONSTRUCTION_LOCAL_GEOMETRY_LAST_EDIT_ID")
	if typeof(value.get("source_member_checksum")) != TYPE_STRING or String(value["source_member_checksum"]).length() != 64: return ParametricUtils.failure("INVALID_CONSTRUCTION_LOCAL_GEOMETRY_SOURCE_CHECKSUM")
	if String(value.get("checksum", "")) != compute_checksum(value): return ParametricUtils.failure("CONSTRUCTION_LOCAL_GEOMETRY_STATE_CHECKSUM_MISMATCH")
	return ParametricUtils.success()

static func path_length(points: Array) -> float:
	var total := 0.0
	for index in range(1, points.size()):
		var left: Array = points[index - 1]["position_m"]
		var right: Array = points[index]["position_m"]
		var dx := float(right[0]) - float(left[0]); var dy := float(right[1]) - float(left[1]); var dz := float(right[2]) - float(left[2])
		total += sqrt(dx * dx + dy * dy + dz * dz)
	return ParametricUtils.metric(total)

static func bounding_box(points: Array) -> Array:
	if points.is_empty(): return []
	var first: Array = points[0]["position_m"]
	var minimum := [float(first[0]), float(first[1]), float(first[2])]
	var maximum := minimum.duplicate()
	for point in points:
		var position: Array = point["position_m"]
		for axis in range(3):
			minimum[axis] = minf(float(minimum[axis]), float(position[axis]))
			maximum[axis] = maxf(float(maximum[axis]), float(position[axis]))
	return [ParametricUtils.metric(float(maximum[0]) - float(minimum[0])), ParametricUtils.metric(float(maximum[1]) - float(minimum[1])), ParametricUtils.metric(float(maximum[2]) - float(minimum[2]))]

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)

static func _normalize_points(points: Array) -> Array:
	var output: Array = []
	for index in range(points.size()):
		var point: Dictionary = points[index]
		output.append(PointScript.create(String(point.get("point_id", "")), index, Array(point.get("position_m", [])).duplicate(true)))
	return output

static func _sorted_constraints(values: Array) -> Array:
	var output := values.duplicate(true); output.sort_custom(func(a, b): return String(a.get("constraint_id", "")) < String(b.get("constraint_id", ""))); return output

static func _canonical_equal(left, right) -> bool:
	var left_json := UtilsScript.canonical_json(left); return not left_json.is_empty() and left_json == UtilsScript.canonical_json(right)

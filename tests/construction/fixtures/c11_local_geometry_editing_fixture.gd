extends RefCounted

const C10Fixture = preload("res://tests/construction/fixtures/c10_parametric_members_fixture.gd")
const CatalogScript = preload("res://scripts/construction/parametric/construction_parametric_catalog.gd")
const ProjectionFactoryScript = preload("res://scripts/construction/parametric/construction_parametric_projection_factory.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const ItemPlannerScript = preload("res://scripts/construction/item_graph/construction_item_transaction_planner.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const PointScript = preload("res://scripts/construction/geometry_edit/construction_geometry_control_point.gd")
const ConstraintScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_constraint.gd")
const OperationScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_operation.gd")
const RequestScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_request.gd")

static func catalog():
	var value = CatalogScript.new()
	for material in C10Fixture.materials():
		value.publish_material(material)
	for definition in C10Fixture.all_definitions():
		value.publish_definition(definition)
	return value

static func beam_instance(instance_key: String = "a", length_m: float = 4.0) -> Dictionary:
	return C10Fixture.beam_instance("c11-%s" % instance_key, length_m)

static func graph(instance_key: String = "a", length_m: float = 4.0) -> Dictionary:
	var instance := beam_instance(instance_key, length_m)
	var construct_id := "construct/geometry-edit/%s" % instance_key
	var root_item_id := "item/geometry-edit/%s/root" % instance_key
	var part_id := "part/geometry-edit/%s/member" % instance_key
	var projection_result := ProjectionFactoryScript.create_projection(instance, "Editable beam", ProjectionScript.attachment_relation(construct_id, root_item_id, part_id), 0)
	var part_result := ProjectionFactoryScript.create_part_record(instance, part_id, "member", [0.0, 0.0, 0.0])
	var snapshot := SnapshotScript.create(construct_id, root_item_id, 0, "OPERATIONAL", [part_result["part"]], [], {"operational": true, "capabilities": []})
	var root := ItemPlannerScript.create_root_projection(root_item_id, construct_id, "Geometry edit root")
	return {"instance": instance, "projection": projection_result["projection"], "snapshot": snapshot, "root": root, "part_id": part_id}

static func grid(step_m: float = 0.5) -> Dictionary:
	return ConstraintScript.create("geometry-constraint/grid", "GRID_SNAP", "PATH", {"step_m": step_m})

static func min_segment(minimum_m: float = 0.25) -> Dictionary:
	return ConstraintScript.create("geometry-constraint/min-segment", "MIN_SEGMENT_LENGTH", "PATH", {"minimum_m": minimum_m})

static func max_length(maximum_m: float = 20.0) -> Dictionary:
	return ConstraintScript.create("geometry-constraint/max-length", "MAX_TOTAL_LENGTH", "PATH", {"maximum_m": maximum_m})

static func orthogonal() -> Dictionary:
	return ConstraintScript.create("geometry-constraint/orthogonal", "ORTHOGONAL_PATH", "PATH", {})

static func lock_width() -> Dictionary:
	return ConstraintScript.create("geometry-constraint/lock-width", "LOCK_PARAMETER", "parameter/width_m", {})

static func lock_start() -> Dictionary:
	return ConstraintScript.create("geometry-constraint/lock-start", "LOCK_CONTROL_POINT", "geometry-point/start", {})

static func lock_end_yz() -> Dictionary:
	return ConstraintScript.create("geometry-constraint/lock-end-yz", "LOCK_AXES", "geometry-point/end", {"axes": ["Y", "Z"]})

static func move_end(sequence: int, position_m: Array) -> Dictionary:
	return OperationScript.create("geometry-operation/move-end-%d" % sequence, sequence, "MOVE_CONTROL_POINT", "geometry-point/end", {"position_m": position_m})

static func set_parameter(sequence: int, parameter: String, value: float) -> Dictionary:
	return OperationScript.create("geometry-operation/set-%s-%d" % [parameter, sequence], sequence, "SET_PARAMETER", "parameter/%s" % parameter, {"value": value})

static func insert_mid(sequence: int, point_id: String, after_point_id: String, position_m: Array) -> Dictionary:
	return OperationScript.create("geometry-operation/insert-%d" % sequence, sequence, "INSERT_CONTROL_POINT", point_id, {"after_point_id": after_point_id, "position_m": position_m})

static func remove_point(sequence: int, point_id: String) -> Dictionary:
	return OperationScript.create("geometry-operation/remove-%d" % sequence, sequence, "REMOVE_CONTROL_POINT", point_id, {})

static func request(instance_key: String = "a", graph_value: Dictionary = {}, operations: Array = [], constraints: Array = [], edit_index: int = 1) -> Dictionary:
	var source := graph(instance_key) if graph_value.is_empty() else graph_value
	var instance: Dictionary = source["instance"]
	var projection: Dictionary = source["projection"]
	var snapshot: Dictionary = source["snapshot"]
	return RequestScript.create(
		"geometry-edit/%s/%d" % [instance_key, edit_index],
		"operation/geometry-edit/%s/%d" % [instance_key, edit_index],
		String(instance["member_instance_id"]),
		String(instance["item_instance_id"]),
		String(snapshot["construct_id"]),
		String(source["part_id"]),
		String(instance["checksum"]),
		int(projection["revision"]),
		String(snapshot["checksum"]),
		0,
		operations if not operations.is_empty() else [move_end(0, [6.0, 0.0, 0.0])],
		constraints,
		{"actor": "agent/c11/test"}
	)

static func point(point_id: String, ordinal: int, position_m: Array) -> Dictionary:
	return PointScript.create(point_id, ordinal, position_m)

class_name FabricConstruct0Editor
extends RefCounted

const AggregateScript = preload("res://scripts/construction/domain/construct_aggregate.gd")
const PartScript = preload("res://scripts/construction/contracts/construction_part_record.gd")
const BondScript = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const ProjectionRequestScript = preload("res://scripts/construction/runtime_projection/construction_runtime_projection_request.gd")
const ProjectionCompilerScript = preload("res://scripts/construction/runtime_projection/construction_runtime_projection_compiler.gd")

const EDITABLE_KINDS: Array[String] = ["BLOCK", "PLATE", "BEAM"]

var _aggregate
var _operation_counter := 0
var _part_counter := 0
var _bond_counter := 0

func setup() -> Dictionary:
	_aggregate = AggregateScript.new()
	var checked: Dictionary = _aggregate.setup(
		"construct/construct0/editor",
		"item/construct0/editor/root"
	)
	if not bool(checked.get("success", false)):
		return checked
	return _success({"snapshot": _aggregate.export_snapshot()})

func load_snapshot(snapshot: Dictionary) -> Dictionary:
	var checked := SnapshotScript.validate(snapshot)
	if not bool(checked.get("success", false)):
		return checked
	_aggregate = AggregateScript.new()
	checked = _aggregate.load_snapshot(snapshot)
	if not bool(checked.get("success", false)):
		return checked
	_part_counter = Array(snapshot["parts"]).size()
	_bond_counter = Array(snapshot["bonds"]).size()
	return _success({"snapshot": _aggregate.export_snapshot()})

func add_part(kind: String, position: Vector3 = Vector3.ZERO) -> Dictionary:
	if _aggregate == null:
		var ready := setup()
		if not bool(ready.get("success", false)):
			return ready
	if not EDITABLE_KINDS.has(kind):
		return _failure("CONSTRUCT0_EDITOR_UNSUPPORTED_PART_KIND")
	var index := _part_counter
	_part_counter += 1
	var id_suffix := "%s-%03d" % [kind.to_lower(), index]
	var part_id := "part/construct0/editor/%s" % id_suffix
	var item_id := "item/construct0/editor/%s" % id_suffix
	var defaults := _defaults(kind)
	var part := PartScript.create(
		part_id,
		item_id,
		kind,
		"structure",
		float(defaults["mass_kg"]),
		[position.x, position.y, position.z],
		{
			"geometry": {"bounding_box_m": Array(defaults["size"]).duplicate(true)},
			"local_rotation_quaternion": [0.0, 0.0, 0.0, 1.0],
			"construct0_editor": true,
		}
	)
	var result: Dictionary = _aggregate.add_part(
		_operation("add-part"),
		_aggregate.state_revision,
		part
	)
	if not bool(result.get("success", false)):
		return result
	return _success({
		"part_id": part_id,
		"snapshot": _aggregate.export_snapshot(),
		"state_revision": _aggregate.state_revision,
	})

func move_part(part_id: String, delta: Vector3) -> Dictionary:
	var part := _find_part(part_id)
	if part.is_empty():
		return _failure("CONSTRUCT0_EDITOR_PART_NOT_FOUND")
	var p: Array = part["local_position_m"]
	var target := Vector3(float(p[0]), float(p[1]), float(p[2])) + delta
	var rotation: Array = Dictionary(part.get("metadata", {})).get(
		"local_rotation_quaternion",
		[0.0, 0.0, 0.0, 1.0]
	)
	return _update_pose(part_id, target, rotation)

func rotate_part_y(part_id: String, delta_rad: float) -> Dictionary:
	if not is_finite(delta_rad):
		return _failure("CONSTRUCT0_EDITOR_ROTATION_NONFINITE")
	var part := _find_part(part_id)
	if part.is_empty():
		return _failure("CONSTRUCT0_EDITOR_PART_NOT_FOUND")
	var p: Array = part["local_position_m"]
	var q: Array = Dictionary(part.get("metadata", {})).get(
		"local_rotation_quaternion",
		[0.0, 0.0, 0.0, 1.0]
	)
	var current := Quaternion(float(q[0]), float(q[1]), float(q[2]), float(q[3]))
	var updated := (Quaternion(Vector3.UP, delta_rad) * current).normalized()
	return _update_pose(
		part_id,
		Vector3(float(p[0]), float(p[1]), float(p[2])),
		[updated.x, updated.y, updated.z, updated.w]
	)

func add_rigid_bond(part_a_id: String, part_b_id: String) -> Dictionary:
	if part_a_id == part_b_id:
		return _failure("CONSTRUCT0_EDITOR_SELF_BOND")
	if _find_part(part_a_id).is_empty() or _find_part(part_b_id).is_empty():
		return _failure("CONSTRUCT0_EDITOR_BOND_PART_NOT_FOUND")
	var bond_id := "bond/construct0/editor/%03d" % _bond_counter
	_bond_counter += 1
	var bond := BondScript.create(
		bond_id,
		part_a_id,
		part_b_id,
		"RIGID",
		1000000.0,
		"INTACT",
		{"construct0_editor": true}
	)
	var result: Dictionary = _aggregate.add_bond(
		_operation("add-bond"),
		_aggregate.state_revision,
		bond
	)
	if not bool(result.get("success", false)):
		return result
	return _success({
		"bond_id": bond_id,
		"snapshot": _aggregate.export_snapshot(),
		"state_revision": _aggregate.state_revision,
	})

func break_bond(bond_id: String) -> Dictionary:
	if _find_bond(bond_id).is_empty():
		return _failure("CONSTRUCT0_EDITOR_BOND_NOT_FOUND")
	var result: Dictionary = _aggregate.break_bond(
		_operation("break-bond"),
		_aggregate.state_revision,
		bond_id
	)
	if not bool(result.get("success", false)):
		return result
	return _success({
		"bond_id": bond_id,
		"snapshot": _aggregate.export_snapshot(),
		"state_revision": _aggregate.state_revision,
	})

func get_snapshot() -> Dictionary:
	if _aggregate == null:
		return {}
	return _aggregate.export_snapshot()

func get_part_ids() -> Array:
	var snapshot := get_snapshot()
	if snapshot.is_empty():
		return []
	var ids: Array = []
	for part_any in snapshot["parts"]:
		ids.append(String(Dictionary(part_any)["part_id"]))
	ids.sort()
	return ids

func get_bond_ids(include_broken: bool = true) -> Array:
	var snapshot := get_snapshot()
	if snapshot.is_empty():
		return []
	var ids: Array = []
	for bond_any in snapshot["bonds"]:
		var bond: Dictionary = bond_any
		if include_broken or String(bond["state"]) != "BROKEN":
			ids.append(String(bond["bond_id"]))
	ids.sort()
	return ids

func compile_runtime_descriptor() -> Dictionary:
	var snapshot := get_snapshot()
	if snapshot.is_empty():
		return _failure("CONSTRUCT0_EDITOR_NOT_INITIALIZED")
	var checked := SnapshotScript.validate(snapshot)
	if not bool(checked.get("success", false)):
		return checked
	var request := ProjectionRequestScript.create(
		snapshot,
		[],
		{},
		{},
		[0.0, 0.0, 0.0],
		[0.0, 0.0, 0.0, 1.0],
		1,
		1
	)
	var compiled := ProjectionCompilerScript.compile(request)
	if not bool(compiled.get("success", false)):
		return compiled
	return _success({"descriptor": compiled["descriptor"], "snapshot": snapshot})

func _update_pose(part_id: String, position: Vector3, rotation: Array) -> Dictionary:
	var result: Dictionary = _aggregate.update_part_pose(
		_operation("pose"),
		_aggregate.state_revision,
		part_id,
		[position.x, position.y, position.z],
		rotation
	)
	if not bool(result.get("success", false)):
		return result
	return _success({
		"part_id": part_id,
		"snapshot": _aggregate.export_snapshot(),
		"state_revision": _aggregate.state_revision,
	})

func _find_part(part_id: String) -> Dictionary:
	var snapshot := get_snapshot()
	if snapshot.is_empty():
		return {}
	for part_any in snapshot["parts"]:
		var part: Dictionary = part_any
		if String(part["part_id"]) == part_id:
			return part.duplicate(true)
	return {}

func _find_bond(bond_id: String) -> Dictionary:
	var snapshot := get_snapshot()
	if snapshot.is_empty():
		return {}
	for bond_any in snapshot["bonds"]:
		var bond: Dictionary = bond_any
		if String(bond["bond_id"]) == bond_id:
			return bond.duplicate(true)
	return {}

func _defaults(kind: String) -> Dictionary:
	match kind:
		"PLATE":
			return {"size": [2.0, 0.18, 1.2], "mass_kg": 12.0}
		"BEAM":
			return {"size": [2.0, 0.22, 0.22], "mass_kg": 8.0}
		_:
			return {"size": [0.7, 0.7, 0.7], "mass_kg": 10.0}

func _operation(kind: String) -> String:
	var value := "construct0/editor/%s/%06d" % [kind, _operation_counter]
	_operation_counter += 1
	return value

func _success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result

func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": code}

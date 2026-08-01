extends Node3D

const DescriptorScript = preload("res://scripts/construction/runtime_projection/construction_runtime_construct_descriptor.gd")

var _descriptor: Dictionary = {}
var _body: PhysicsBody3D = null
var _part_visuals: Dictionary = {}
var _part_checksums: Dictionary = {}
var _part_collisions: Dictionary = {}
var _part_base_transforms: Dictionary = {}
var _opening_nodes: Dictionary = {}
var _rebuild_count := 0

func apply_descriptor(descriptor: Dictionary) -> Dictionary:
	var checked := DescriptorScript.validate(descriptor)
	if not bool(checked.get("success", false)): return checked
	var body_replaced := _ensure_body(String(descriptor["body_kind"]))
	name = _node_name(String(descriptor["construct_id"]))
	set_meta("construct_id", String(descriptor["construct_id"]))
	set_meta("construct_checksum", String(descriptor["construct_checksum"]))
	set_meta("runtime_descriptor_checksum", String(descriptor["checksum"]))
	position = _vector3(descriptor["world_origin_m"])
	quaternion = _quaternion(descriptor["world_rotation_quaternion"])
	_body.collision_layer = int(descriptor["collision_layer"])
	_body.collision_mask = int(descriptor["collision_mask"])
	if _body is RigidBody3D:
		var rigid := _body as RigidBody3D
		rigid.mass = maxf(float(descriptor["total_mass_kg"]), 0.001)
		rigid.freeze = bool(descriptor["frozen"])
	var incoming_ids := {}
	var rebuilt: Array = []
	var unchanged: Array = []
	for part_descriptor in descriptor["part_descriptors"]:
		var part_id := String(part_descriptor["part_id"]); incoming_ids[part_id] = true
		if not body_replaced and _part_checksums.get(part_id, "") == String(part_descriptor["source_checksum"]) and _part_visuals.has(part_id):
			unchanged.append(part_id)
			continue
		_remove_part(part_id)
		_build_part(part_descriptor)
		rebuilt.append(part_id)
	var removed: Array = []
	for raw_id in _part_visuals.keys().duplicate():
		var part_id := String(raw_id)
		if not incoming_ids.has(part_id):
			_remove_part(part_id); removed.append(part_id)
	_apply_openings(descriptor["opening_descriptors"])
	_descriptor = descriptor.duplicate(true)
	return _success({"rebuilt_part_ids": rebuilt, "unchanged_part_ids": unchanged, "removed_part_ids": removed, "body_replaced": body_replaced})

func get_descriptor() -> Dictionary: return _descriptor.duplicate(true)
func get_body() -> PhysicsBody3D: return _body
func get_part_node(part_id: String) -> Node3D: return _part_visuals.get(part_id, null)
func get_part_collision_nodes(part_id: String) -> Array:
	var output: Array = []
	for entry in _part_collisions.get(part_id, []):
		var node = entry.get("node")
		if is_instance_valid(node): output.append(node)
	return output
func get_part_ids() -> Array:
	var ids: Array = _part_visuals.keys(); ids.sort(); return ids
func get_opening_node(opening_id: String): return _opening_nodes.get(opening_id, null)
func get_opening_ids() -> Array:
	var ids: Array = _opening_nodes.keys(); ids.sort(); return ids
func get_rebuild_count() -> int: return _rebuild_count
func get_descriptor_checksum() -> String: return String(_descriptor.get("checksum", ""))

func _ensure_body(body_kind: String) -> bool:
	var correct := (_body is StaticBody3D and body_kind == "STATIC") or (_body is RigidBody3D and body_kind == "RIGID")
	if correct: return false
	if is_instance_valid(_body):
		remove_child(_body); _body.free()
	_body = RigidBody3D.new() if body_kind == "RIGID" else StaticBody3D.new()
	_body.name = "PhysicsBody"
	add_child(_body)
	_part_visuals.clear(); _part_checksums.clear(); _part_collisions.clear(); _part_base_transforms.clear(); _opening_nodes.clear()
	return true

func _build_part(descriptor: Dictionary) -> void:
	var part_id := String(descriptor["part_id"])
	var visual := Node3D.new()
	visual.name = _node_name(part_id)
	visual.position = _vector3(descriptor["local_position_m"])
	visual.quaternion = _quaternion(descriptor["local_rotation_quaternion"])
	visual.visible = bool(descriptor["visible"])
	visual.set_meta("part_id", part_id)
	visual.set_meta("item_instance_id", String(descriptor["item_instance_id"]))
	visual.set_meta("source_checksum", String(descriptor["source_checksum"]))
	visual.set_meta("condition", String(descriptor["condition"]))
	_body.add_child(visual)
	_part_visuals[part_id] = visual
	_part_checksums[part_id] = String(descriptor["source_checksum"])
	_part_collisions[part_id] = []
	_part_base_transforms[part_id] = visual.transform
	match String(descriptor["geometry_kind"]):
		"BOX": _build_box(visual, descriptor, Transform3D.IDENTITY)
		"CYLINDER":
			var local := Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3.ZERO)
			_build_cylinder(visual, descriptor, local)
		"PATH_BOXES": _build_path(visual, descriptor)
	_rebuild_count += 1

func _build_box(visual: Node3D, descriptor: Dictionary, local_transform: Transform3D) -> void:
	var size := _vector3(descriptor["dimensions_m"])
	var mesh_instance := MeshInstance3D.new(); mesh_instance.name = "Mesh"
	var mesh := BoxMesh.new(); mesh.size = size; mesh_instance.mesh = mesh; mesh_instance.transform = local_transform
	visual.add_child(mesh_instance)
	if bool(descriptor["collision_enabled"]):
		var shape := BoxShape3D.new(); shape.size = size
		_add_collision(String(descriptor["part_id"]), shape, visual.transform * local_transform)

func _build_cylinder(visual: Node3D, descriptor: Dictionary, local_transform: Transform3D) -> void:
	var dimensions := _vector3(descriptor["dimensions_m"])
	var mesh_instance := MeshInstance3D.new(); mesh_instance.name = "Mesh"
	var mesh := CylinderMesh.new(); mesh.height = dimensions.x; mesh.top_radius = dimensions.y * 0.5; mesh.bottom_radius = dimensions.y * 0.5; mesh.radial_segments = 12
	mesh_instance.mesh = mesh; mesh_instance.transform = local_transform; visual.add_child(mesh_instance)
	if bool(descriptor["collision_enabled"]):
		var shape := CylinderShape3D.new(); shape.height = dimensions.x; shape.radius = dimensions.y * 0.5
		_add_collision(String(descriptor["part_id"]), shape, visual.transform * local_transform)

func _build_path(visual: Node3D, descriptor: Dictionary) -> void:
	var points: Array = descriptor["path_points_m"]
	var thickness := _vector3(descriptor["dimensions_m"])
	for index in range(1, points.size()):
		var from := _vector3(points[index - 1]); var to := _vector3(points[index]); var delta := to - from; var length := delta.length()
		var segment := Node3D.new(); segment.name = "Segment%03d" % (index - 1); segment.position = (from + to) * 0.5
		segment.quaternion = Quaternion(Vector3.RIGHT, delta.normalized())
		visual.add_child(segment)
		var size := Vector3(length, thickness.y, thickness.z)
		var mesh_instance := MeshInstance3D.new(); mesh_instance.name = "Mesh"; var mesh := BoxMesh.new(); mesh.size = size; mesh_instance.mesh = mesh; segment.add_child(mesh_instance)
		if bool(descriptor["collision_enabled"]):
			var shape := BoxShape3D.new(); shape.size = size
			_add_collision(String(descriptor["part_id"]), shape, visual.transform * segment.transform)

func _add_collision(part_id: String, shape: Shape3D, base_transform: Transform3D) -> void:
	var collision := CollisionShape3D.new(); collision.name = "Collision_%s_%03d" % [_short_name(part_id), Array(_part_collisions[part_id]).size()]; collision.shape = shape; collision.transform = base_transform
	_body.add_child(collision)
	_part_collisions[part_id].append({"node": collision, "base_transform": base_transform})

func _apply_openings(openings: Array) -> void:
	var incoming := {}
	for opening in openings:
		var opening_id := String(opening["opening_id"]); incoming[opening_id] = true
		var part_id := String(opening["closure_part_id"])
		if part_id.is_empty() or not _part_visuals.has(part_id): continue
		var visual: Node3D = _part_visuals[part_id]
		var base: Transform3D = _part_base_transforms[part_id]
		var hinge_rotation := Basis(Vector3.UP, float(opening["target_angle_rad"]))
		visual.transform = Transform3D(base.basis * hinge_rotation, base.origin)
		visual.set_meta("opening_id", opening_id)
		visual.set_meta("opening_status", String(opening["status"]))
		visual.set_meta("opening_target_angle_rad", float(opening["target_angle_rad"]))
		for entry in _part_collisions.get(part_id, []):
			var collision: CollisionShape3D = entry["node"]
			var collision_base: Transform3D = entry["base_transform"]
			collision.transform = Transform3D(collision_base.basis * hinge_rotation, collision_base.origin)
			collision.disabled = not bool(opening["collision_enabled"])
		var runtime = _opening_nodes.get(opening_id, null)
		if runtime == null or not is_instance_valid(runtime):
			runtime = NavigationLink3D.new(); runtime.name = _node_name(opening_id); _body.add_child(runtime); _opening_nodes[opening_id] = runtime
			var anchor := Marker3D.new(); anchor.name = "InteractionAnchor"; anchor.set_meta("interaction_kind", "OPENING"); runtime.add_child(anchor)
		runtime.position = base.origin
		runtime.start_position = Vector3(0.0, 0.0, -0.75)
		runtime.end_position = Vector3(0.0, 0.0, 0.75)
		runtime.bidirectional = true
		runtime.enabled = String(opening["status"]) == "OPEN"
		runtime.set_meta("opening_id", opening_id)
		runtime.set_meta("opening_status", String(opening["status"]))
		runtime.set_meta("closure_part_id", part_id)
		runtime.set_meta("interactive", true)
	for raw_id in _opening_nodes.keys().duplicate():
		var opening_id := String(raw_id)
		if incoming.has(opening_id): continue
		var runtime = _opening_nodes[opening_id]
		if is_instance_valid(runtime): _body.remove_child(runtime); runtime.free()
		_opening_nodes.erase(opening_id)

func _remove_part(part_id: String) -> void:
	if _part_visuals.has(part_id):
		var visual = _part_visuals[part_id]
		if is_instance_valid(visual): _body.remove_child(visual); visual.free()
	for entry in _part_collisions.get(part_id, []):
		var collision = entry.get("node")
		if is_instance_valid(collision): _body.remove_child(collision); collision.free()
	_part_visuals.erase(part_id); _part_checksums.erase(part_id); _part_collisions.erase(part_id); _part_base_transforms.erase(part_id)

func _vector3(value: Array) -> Vector3: return Vector3(float(value[0]), float(value[1]), float(value[2]))
func _quaternion(value: Array) -> Quaternion: return Quaternion(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
func _node_name(value: String) -> String: return value.replace("/", "__")
func _short_name(value: String) -> String: return value.get_file().replace("-", "_")
func _success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": "", "details": details.duplicate(true)}
	for key in details: result[key] = details[key]
	return result

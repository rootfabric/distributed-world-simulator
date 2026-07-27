extends Node

var body: RigidBody3D
var gravity_field
var frame_id: String = ""
var reference_body_id: String = ""
var coordinate_root: Node3D


func setup(
	body_reference: RigidBody3D,
	gravity_field_reference,
	frame_id_value: String,
	reference_body_id_value: String = "",
	coordinate_root_reference: Node3D = null
) -> void:
	body = body_reference
	gravity_field = gravity_field_reference
	frame_id = frame_id_value
	reference_body_id = reference_body_id_value
	coordinate_root = coordinate_root_reference
	set_physics_process(body != null and gravity_field != null)
	apply_now()


func apply_now() -> Vector3:
	if body == null or not is_instance_valid(body):
		return Vector3.ZERO
	body.gravity_scale = 0.0
	if gravity_field == null:
		body.constant_force = Vector3.ZERO
		body.set_meta("gravity_acceleration_mps2", Vector3.ZERO)
		body.set_meta("gravity_acceleration_frame_mps2", Vector3.ZERO)
		return Vector3.ZERO
	var frame_position_m: Vector3 = _body_position_in_frame()
	var acceleration_frame_mps2: Vector3 = gravity_field.get_acceleration_at_position(
		frame_position_m,
		frame_id,
		INF,
		reference_body_id
	)
	var acceleration_scene_mps2: Vector3 = _frame_direction_to_scene(
		acceleration_frame_mps2
	)
	body.constant_force = acceleration_scene_mps2 * body.mass
	body.set_meta("gravity_acceleration_mps2", acceleration_scene_mps2)
	body.set_meta("gravity_acceleration_frame_mps2", acceleration_frame_mps2)
	body.set_meta(
		"gravity_dominant_source_id",
		gravity_field.get_dominant_source_id_at_position(
			frame_position_m,
			frame_id,
			INF,
			reference_body_id
		)
	)
	return acceleration_scene_mps2


func _physics_process(_delta: float) -> void:
	apply_now()


func _body_position_in_frame() -> Vector3:
	if coordinate_root == null or not is_instance_valid(coordinate_root):
		return body.position
	# The common item case is a direct child of the frame root. Reading the
	# local transform is both exact and valid before either node enters a tree.
	if body.get_parent() == coordinate_root:
		return body.position
	var body_scene_transform: Transform3D = _resolved_scene_transform(body)
	var root_scene_transform: Transform3D = _resolved_scene_transform(coordinate_root)
	return root_scene_transform.affine_inverse() * body_scene_transform.origin


func _frame_direction_to_scene(direction_frame: Vector3) -> Vector3:
	if coordinate_root == null or not is_instance_valid(coordinate_root):
		return direction_frame
	return (
		_resolved_scene_transform(coordinate_root).basis.orthonormalized()
		* direction_frame
	)


func _resolved_scene_transform(node: Node3D) -> Transform3D:
	if node.is_inside_tree():
		return node.global_transform
	# global_transform is unavailable before SceneTree attachment. Compose the
	# local Node3D chain manually so setup/apply_now remain deterministic during
	# construction, headless tests and pooled-object activation.
	var resolved: Transform3D = node.transform
	var parent: Node = node.get_parent()
	while parent != null:
		if parent is Node3D:
			resolved = (parent as Node3D).transform * resolved
		parent = parent.get_parent()
	return resolved

extends "res://scripts/world/testing/playground_runtime.gd"

# Network-playground specialization that keeps local camera input independent
# from the authoritative avatar-facing yaw. The shared movement kernel consumes
# an absolute world-space yaw, so derive it from the active camera's real view
# basis instead of reusing an accumulated local camera_yaw value.


func _create_m7_movement_intent(
	delta_seconds: float,
	input_override: Vector2 = Vector2(INF, INF),
	jump_override: int = -1,
	sprint_override: int = -1
) -> Dictionary:
	var input_vector := input_override
	if is_inf(input_vector.x) or is_inf(input_vector.y):
		input_vector = Input.get_vector(
			"move_left", "move_right", "move_forward", "move_back"
		)
	if input_vector.length_squared() > 1.0:
		input_vector = input_vector.normalized()
	return {
		"move_x": input_vector.x,
		"move_z": -input_vector.y,
		"look_yaw": _network_view_yaw(),
		"look_pitch": clampf(player.camera_pitch, -1.45, 1.45),
		"jump_pressed": (
			Input.is_action_pressed("jump") if jump_override < 0 else jump_override > 0
		),
		"sprint": (
			Input.is_action_pressed("boost") if sprint_override < 0 else sprint_override > 0
		),
		"delta_seconds": clampf(delta_seconds, 0.000001, 0.25),
	}


func _network_view_yaw() -> float:
	if player == null:
		return 0.0
	var view_basis: Basis = player.get_view_basis()
	var camera_forward: Vector3 = (-view_basis.z).slide(Vector3.UP)
	if camera_forward.length_squared() < 0.000001:
		return wrapf(float(player.camera_yaw), -PI, PI)
	camera_forward = camera_forward.normalized()
	return atan2(-camera_forward.x, -camera_forward.z)


func _apply_m7_prediction_presentation(state: Dictionary) -> void:
	if state.is_empty() or player == null:
		return
	var position: Dictionary = Dictionary(state.get("position", {}))
	var velocity: Dictionary = Dictionary(state.get("velocity", {}))
	player.set_world_position(Vector3(
		float(position.get("x", 0.0)),
		float(position.get("y", 0.0)),
		float(position.get("z", 0.0))
	))
	player.velocity = Vector3(
		float(velocity.get("x", 0.0)),
		float(velocity.get("y", 0.0)),
		float(velocity.get("z", 0.0))
	)
	var yaw: float = float(state.get("orientation_yaw", 0.0))
	# Rotate only the visible astronaut. Rotating the CharacterBody root would
	# rotate CameraAnchor as well and apply yaw twice for the local player.
	if player.visual_root != null:
		player.visual_root.rotation.y = yaw

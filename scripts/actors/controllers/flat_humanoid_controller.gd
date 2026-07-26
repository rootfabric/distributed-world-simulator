extends "res://scripts/actors/controllers/base_movement_controller.gd"


func physics_step(delta: float) -> void:
	if not enabled or actor == null:
		return
	var movement: Dictionary = _movement_config()
	var up := Vector3.UP
	actor.up_direction = up
	actor.floor_snap_length = float(movement.get("floor_snap_length", 0.45))
	actor.floor_max_angle = deg_to_rad(float(movement.get("floor_max_angle_deg", 55.0)))

	var input_vector := Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back"
	)
	var view_basis: Basis = actor.get_view_basis()
	var camera_forward: Vector3 = (-view_basis.z).slide(up)
	var camera_right: Vector3 = view_basis.x.slide(up)
	if camera_forward.length_squared() < 0.000001:
		camera_forward = Vector3.FORWARD
	if camera_right.length_squared() < 0.000001:
		camera_right = Vector3.RIGHT
	camera_forward = camera_forward.normalized()
	camera_right = camera_right.normalized()
	var desired_direction: Vector3 = (
		camera_right * input_vector.x + camera_forward * -input_vector.y
	)
	if desired_direction.length_squared() > 1.0:
		desired_direction = desired_direction.normalized()

	var target_speed: float = (
		float(movement.get("run_speed", 9.0))
		if Input.is_action_pressed("boost")
		else float(movement.get("walk_speed", 5.5))
	)
	var acceleration: float = (
		float(movement.get("ground_acceleration", 24.0))
		if actor.is_on_floor()
		else float(movement.get("air_acceleration", 5.0))
	)
	var horizontal_velocity := Vector3(actor.velocity.x, 0.0, actor.velocity.z)
	horizontal_velocity = horizontal_velocity.move_toward(
		desired_direction * target_speed,
		acceleration * delta
	)
	var vertical_speed: float = actor.velocity.y
	if actor.is_on_floor():
		vertical_speed = 0.0
		if Input.is_action_just_pressed("jump"):
			vertical_speed = float(movement.get("jump_speed", 5.2))
	else:
		vertical_speed -= float(movement.get("gravity_m_s2", 9.81)) * delta
	actor.velocity = horizontal_velocity + Vector3.UP * vertical_speed
	actor.move_and_slide()
	if actor.global_position.y < -20.0 and world != null and world.has_method("recover_actor"):
		world.recover_actor(actor)

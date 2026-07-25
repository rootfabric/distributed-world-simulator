extends "res://scripts/actors/controllers/base_movement_controller.gd"


func physics_step(delta: float) -> void:
	if not enabled or actor == null or world == null:
		return
	var absolute_position: Vector3 = actor.get_world_position()
	var distance_from_center: float = absolute_position.length()
	if distance_from_center < 1.0:
		return

	var movement: Dictionary = _movement_config()
	var up: Vector3 = absolute_position / distance_from_center
	actor.up_direction = up
	actor.align_body_to_up(up)
	actor.floor_snap_length = float(movement.get("floor_snap_length", 0.75))
	actor.floor_max_angle = deg_to_rad(float(movement.get("floor_max_angle_deg", 55.0)))

	var input_vector := Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back"
	)
	var view_basis: Basis = actor.get_view_basis()
	var camera_forward: Vector3 = (-view_basis.z).slide(up)
	var camera_right: Vector3 = view_basis.x.slide(up)
	if camera_forward.length_squared() < 0.000001:
		camera_forward = (-actor.global_transform.basis.z).slide(up)
	if camera_right.length_squared() < 0.000001:
		camera_right = actor.global_transform.basis.x.slide(up)
	camera_forward = camera_forward.normalized()
	camera_right = camera_right.normalized()
	var desired_direction: Vector3 = (
		camera_right * input_vector.x + camera_forward * -input_vector.y
	)
	if desired_direction.length_squared() > 1.0:
		desired_direction = desired_direction.normalized()

	var radial_speed: float = actor.velocity.dot(up)
	var horizontal_velocity: Vector3 = actor.velocity - up * radial_speed
	var target_speed: float = (
		float(movement.get("run_speed", 11.0))
		if Input.is_action_pressed("boost")
		else float(movement.get("walk_speed", 6.0))
	)
	var acceleration: float = (
		float(movement.get("ground_acceleration", 20.0))
		if actor.is_on_floor()
		else float(movement.get("air_acceleration", 3.0))
	)
	horizontal_velocity = horizontal_velocity.move_toward(
		desired_direction * target_speed,
		acceleration * delta
	)

	if actor.is_on_floor():
		radial_speed = 0.0
		if Input.is_action_just_pressed("jump"):
			radial_speed = float(movement.get("jump_speed", 3.3))
	else:
		var gravity_scale: float = float(movement.get("gravity_scale", 1.0))
		radial_speed -= (
			world.get_gravity_at_distance(distance_from_center)
			* gravity_scale
			* delta
		)

	actor.velocity = horizontal_velocity + up * radial_speed
	actor.move_and_slide()
	world.recenter_player(actor)
	actor.recover_if_below_surface()

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
	actor.floor_snap_length = float(movement.get("floor_snap_length", 0.15))
	actor.floor_max_angle = deg_to_rad(float(movement.get("floor_max_angle_deg", 65.0)))

	var input_vector := Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back"
	)
	var vertical_input: float = (
		Input.get_action_strength("move_up")
		- Input.get_action_strength("move_down")
	)
	var view_basis: Basis = actor.get_view_basis()
	var forward: Vector3 = (-view_basis.z).slide(up)
	var right: Vector3 = view_basis.x.slide(up)
	if forward.length_squared() < 0.000001:
		forward = (-actor.global_transform.basis.z).slide(up)
	if right.length_squared() < 0.000001:
		right = actor.global_transform.basis.x.slide(up)
	forward = forward.normalized()
	right = right.normalized()

	var boost: bool = Input.is_action_pressed("boost")
	var horizontal_speed: float = float(
		movement.get("boost_speed", 65.0) if boost else movement.get("flight_speed", 18.0)
	)
	var vertical_speed: float = float(
		movement.get("vertical_boost_speed", 38.0)
		if boost
		else movement.get("vertical_speed", 14.0)
	)
	var horizontal_input: Vector3 = right * input_vector.x + forward * -input_vector.y
	if horizontal_input.length_squared() > 1.0:
		horizontal_input = horizontal_input.normalized()
	var desired_velocity: Vector3 = (
		horizontal_input * horizontal_speed + up * vertical_input * vertical_speed
	)
	var acceleration: float = float(movement.get("flight_acceleration", 22.0))
	actor.velocity = actor.velocity.move_toward(desired_velocity, acceleration * delta)

	if not bool(movement.get("auto_hover", true)):
		actor.velocity -= (
			up
			* world.get_gravity_at_distance(distance_from_center)
			* float(movement.get("gravity_scale", 1.0))
			* delta
		)
	elif actor.is_on_floor() and vertical_input <= 0.0:
		var radial_speed: float = actor.velocity.dot(up)
		if radial_speed < 0.0:
			actor.velocity -= up * radial_speed

	actor.move_and_slide()
	world.recenter_player(actor)
	actor.recover_if_below_surface()

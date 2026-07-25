extends Node3D

const MOUSE_SENSITIVITY: float = 0.00110
const ROLL_SPEED: float = 1.35
const MIN_SPEED: float = 1.0
const MAX_SPEED: float = 8_000_000.0

var moon_world
var camera: Camera3D
var active: bool = false
var movement_speed: float = 1200.0
var orientation := Basis.IDENTITY
var world_position: Vector3 = Vector3.ZERO


func setup(moon_reference) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	moon_world = moon_reference
	camera = Camera3D.new()
	camera.name = "SpectatorCamera"
	camera.current = false
	camera.near = 0.25
	camera.far = 4_000_000.0
	camera.fov = 72.0
	add_child(camera)
	set_process(false)
	set_process_unhandled_input(false)


func activate(source_world_transform: Transform3D) -> void:
	active = true
	world_position = source_world_transform.origin
	orientation = source_world_transform.basis.orthonormalized()
	global_transform = Transform3D(orientation, Vector3.ZERO)
	camera.current = true
	set_process(true)
	set_process_unhandled_input(true)
	_update_camera_clipping()


func deactivate() -> void:
	active = false
	camera.current = false
	set_process(false)
	set_process_unhandled_input(false)


func _process(delta: float) -> void:
	if not active:
		return

	var input_vector := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)
	var vertical: float = (
		Input.get_action_strength("move_up")
		- Input.get_action_strength("move_down")
	)
	var direction := (
		orientation.x * input_vector.x
		+ (-orientation.z) * -input_vector.y
		+ orientation.y * vertical
	)
	if direction.length_squared() > 1.0:
		direction = direction.normalized()

	var actual_speed: float = movement_speed
	if Input.is_action_pressed("boost"):
		actual_speed *= 12.0
	world_position += direction * actual_speed * delta

	var roll_input: float = (
		Input.get_action_strength("roll_right")
		- Input.get_action_strength("roll_left")
	)
	if absf(roll_input) > 0.001:
		var forward_axis: Vector3 = (-orientation.z).normalized()
		orientation = (
			Basis(forward_axis, -roll_input * ROLL_SPEED * delta)
			* orientation
		).orthonormalized()

	if Input.is_action_just_pressed("level_horizon"):
		_level_to_lunar_horizon()

	global_transform = Transform3D(orientation, Vector3.ZERO)
	_update_camera_clipping()


func _update_camera_clipping() -> void:
	if camera == null or moon_world == null:
		return
	var altitude: float = maxf(0.0, moon_world.get_altitude(world_position))
	if altitude < 5_000.0:
		camera.near = 0.20
		camera.far = 900_000.0
	elif altitude < 150_000.0:
		camera.near = clampf(altitude * 0.00015, 0.5, 22.0)
		camera.far = 4_500_000.0
	else:
		camera.near = clampf(altitude * 0.00035, 25.0, 12_000.0)
		camera.far = maxf(
			8_000_000.0,
			world_position.length() + moon_world.get_moon_radius() * 2.5
		)


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var yaw_delta: float = -event.relative.x * MOUSE_SENSITIVITY
		var pitch_delta: float = -event.relative.y * MOUSE_SENSITIVITY
		orientation = Basis(orientation.y.normalized(), yaw_delta) * orientation
		orientation = Basis(orientation.x.normalized(), pitch_delta) * orientation
		orientation = orientation.orthonormalized()
		global_transform = Transform3D(orientation, Vector3.ZERO)

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			movement_speed = clampf(movement_speed * 2.0, MIN_SPEED, MAX_SPEED)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			movement_speed = clampf(movement_speed * 0.5, MIN_SPEED, MAX_SPEED)
			get_viewport().set_input_as_handled()


func _level_to_lunar_horizon() -> void:
	if world_position.length_squared() < 1.0:
		return

	var radial_up: Vector3 = world_position.normalized()
	var forward: Vector3 = (-orientation.z).normalized()
	var right: Vector3 = forward.cross(radial_up)

	# When looking almost exactly up or down, the horizon is undefined.
	# Preserve the current right axis in that edge case.
	if right.length_squared() < 0.000001:
		right = orientation.x.slide(forward)
	if right.length_squared() < 0.000001:
		return

	right = right.normalized()
	var corrected_up: Vector3 = right.cross(forward).normalized()
	orientation = Basis(right, corrected_up, -forward).orthonormalized()


func get_world_position() -> Vector3:
	return world_position


func get_movement_speed() -> float:
	return movement_speed

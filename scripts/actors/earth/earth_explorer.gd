extends Node3D

const SpatialRefScript = preload(
	"res://scripts/simulation/spatial/spatial_ref.gd"
)

const MOUSE_SENSITIVITY: float = 0.00110
const ROLL_SPEED: float = 1.35
const MIN_SPEED: float = 1.0
const MAX_SPEED: float = 250_000_000.0
const SPACE_CAMERA_FAR_M: float = 900_000_000.0

var earth_world
var celestial_system
var moon_world
var camera: Camera3D
var active: bool = false
var movement_speed: float = 900.0
# Canonical state is expressed in reference_frame_id. The Node itself always
# stays at the local render origin and only carries observer-frame orientation.
var reference_frame_id: String = "sol.barycentric"
var frame_position: Vector3 = Vector3.ZERO
var orientation := Basis.IDENTITY
var linear_velocity_mps: Vector3 = Vector3.ZERO
var angular_velocity_rps: Vector3 = Vector3.ZERO
var network_replica_mode: bool = false


func setup(
	earth_reference,
	celestial_reference = null,
	moon_reference = null
) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	earth_world = earth_reference
	celestial_system = celestial_reference
	moon_world = moon_reference
	if celestial_system != null:
		reference_frame_id = celestial_system.get_root_frame_id()
	camera = Camera3D.new()
	camera.name = "SharedSpaceSpectatorCamera"
	camera.current = false
	camera.near = 0.20
	camera.far = SPACE_CAMERA_FAR_M
	camera.fov = 72.0
	add_child(camera)
	set_physics_process(false)
	set_process_unhandled_input(false)


func activate(direction: Vector3, altitude_m: float = 450.0) -> void:
	active = true
	teleport_to_direction(direction, altitude_m)
	camera.current = true
	set_physics_process(true)
	set_process_unhandled_input(true)
	_update_camera_clipping()


func activate_at_space_position(
	space_position: Vector3,
	basis_value: Basis = Basis.IDENTITY
) -> void:
	if celestial_system == null:
		return
	activate_at_spatial_ref(celestial_system.create_spatial_ref(
		celestial_system.get_root_frame_id(),
		space_position,
		basis_value
	))


func activate_at_spatial_ref(spatial_ref: Dictionary) -> void:
	if celestial_system == null or not SpatialRefScript.is_valid(spatial_ref):
		return
	var frame_id: String = String(spatial_ref.get("frame_id", ""))
	if not celestial_system.has_frame(frame_id):
		return
	active = true
	reference_frame_id = frame_id
	frame_position = SpatialRefScript.get_position(spatial_ref)
	orientation = SpatialRefScript.get_basis(spatial_ref).orthonormalized()
	linear_velocity_mps = SpatialRefScript.get_linear_velocity(spatial_ref)
	angular_velocity_rps = SpatialRefScript.get_angular_velocity(spatial_ref)
	global_transform = Transform3D(orientation, Vector3.ZERO)
	camera.current = true
	set_physics_process(true)
	set_process_unhandled_input(true)
	reset_physics_interpolation()
	_update_camera_clipping()


func deactivate() -> void:
	active = false
	camera.current = false
	set_physics_process(false)
	set_process_unhandled_input(false)


func set_network_replica_mode(enabled: bool) -> void:
	network_replica_mode = enabled
	# Network snapshots own the spectator pose while attached.  The camera stays
	# active so a graphical client remains a usable observer.
	set_physics_process(active and not enabled)
	set_process_unhandled_input(active and not enabled)


func is_network_replica_mode() -> bool:
	return network_replica_mode


func teleport_to_direction(direction_value: Vector3, altitude_m: float = 450.0) -> void:
	teleport_to_body_surface("earth", direction_value, altitude_m)


func teleport_to_body_surface(
	body_id: String,
	direction_value: Vector3,
	altitude_m: float = 450.0
) -> void:
	if celestial_system == null:
		return
	var direction: Vector3 = direction_value.normalized()
	var body_local_surface: Vector3
	if body_id == "earth" and earth_world != null:
		earth_world.prepare_surface_region(direction, false)
		body_local_surface = earth_world.get_surface_point(direction)
	elif body_id == "moon" and moon_world != null:
		moon_world.prepare_surface_region(direction, false)
		body_local_surface = moon_world.get_surface_point(direction)
	else:
		body_local_surface = direction * celestial_system.get_body_radius(body_id)
	reference_frame_id = celestial_system.get_body_fixed_frame_id(body_id)
	frame_position = body_local_surface + direction * altitude_m
	orientation = _surface_orientation(direction)
	linear_velocity_mps = Vector3.ZERO
	angular_velocity_rps = Vector3.ZERO
	global_transform = Transform3D(orientation, Vector3.ZERO)
	reset_physics_interpolation()
	_update_camera_clipping()


func apply_network_replica_pose(
	direction_value: Vector3,
	altitude_m: float
) -> void:
	if celestial_system == null or earth_world == null:
		return
	# Replica snapshots arrive at the normal M3 cadence.  Do not use the
	# teleport path here: it eagerly rebuilds a terrain region and would turn
	# every snapshot into a multi-second render stall.  EarthWorld's ordinary
	# update_for_view path owns streaming and recentering.
	var direction: Vector3 = direction_value.normalized()
	reference_frame_id = celestial_system.get_body_fixed_frame_id("earth")
	frame_position = earth_world.get_surface_point(direction) + direction * altitude_m
	orientation = _surface_orientation(direction)
	linear_velocity_mps = Vector3.ZERO
	angular_velocity_rps = Vector3.ZERO
	global_transform = Transform3D(orientation, Vector3.ZERO)
	reset_physics_interpolation()
	_update_camera_clipping()
	set_network_replica_mode(true)


func set_reference_frame(target_frame_id: String, preserve_world_state: bool = true) -> bool:
	if celestial_system == null or not celestial_system.has_frame(target_frame_id):
		return false
	if target_frame_id == reference_frame_id:
		return true
	if preserve_world_state:
		var converted: Dictionary = celestial_system.transform_spatial_ref(
			get_spatial_ref(),
			target_frame_id
		)
		if converted.is_empty():
			return false
		frame_position = SpatialRefScript.get_position(converted)
		orientation = SpatialRefScript.get_basis(converted).orthonormalized()
		linear_velocity_mps = SpatialRefScript.get_linear_velocity(converted)
		angular_velocity_rps = SpatialRefScript.get_angular_velocity(converted)
	reference_frame_id = target_frame_id
	global_transform = Transform3D(orientation, Vector3.ZERO)
	reset_physics_interpolation()
	return true


func _physics_process(delta: float) -> void:
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
	linear_velocity_mps = direction * actual_speed
	frame_position += linear_velocity_mps * delta

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
		level_to_horizon()
	global_transform = Transform3D(orientation, Vector3.ZERO)
	_update_camera_clipping()


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


func level_to_horizon() -> void:
	if celestial_system == null:
		return
	var nearest_body_id: String = get_nearest_body_id()
	if nearest_body_id.is_empty():
		return
	var body_center_in_frame: Vector3 = celestial_system.transform_point(
		Vector3.ZERO,
		celestial_system.get_body_fixed_frame_id(nearest_body_id),
		reference_frame_id
	)
	var radial: Vector3 = frame_position - body_center_in_frame
	if radial.length_squared() < 1.0:
		return
	var radial_up: Vector3 = radial.normalized()
	var forward: Vector3 = (-orientation.z).normalized()
	var right: Vector3 = forward.cross(radial_up)
	if right.length_squared() < 0.000001:
		right = orientation.x.slide(forward)
	if right.length_squared() < 0.000001:
		return
	right = right.normalized()
	var corrected_up: Vector3 = right.cross(forward).normalized()
	orientation = Basis(right, corrected_up, -forward).orthonormalized()


func look_at_body(body_id: String) -> void:
	if celestial_system == null:
		return
	var target_in_frame: Vector3 = celestial_system.transform_point(
		Vector3.ZERO,
		celestial_system.get_body_fixed_frame_id(body_id),
		reference_frame_id
	)
	var forward: Vector3 = target_in_frame - frame_position
	if forward.length_squared() < 1.0:
		return
	forward = forward.normalized()
	var up_hint: Vector3 = orientation.y.normalized()
	var right: Vector3 = forward.cross(up_hint)
	if right.length_squared() < 0.000001:
		right = forward.cross(Vector3.UP)
	if right.length_squared() < 0.000001:
		right = forward.cross(Vector3.RIGHT)
	right = right.normalized()
	var corrected_up: Vector3 = right.cross(forward).normalized()
	orientation = Basis(right, corrected_up, -forward).orthonormalized()
	global_transform = Transform3D(orientation, Vector3.ZERO)


func get_orientation_in_frame(target_frame_id: String) -> Basis:
	if target_frame_id == reference_frame_id or celestial_system == null:
		return orientation
	return (
		celestial_system.get_relative_basis(reference_frame_id, target_frame_id)
		* orientation
	).orthonormalized()


func _surface_orientation(direction: Vector3) -> Basis:
	var east: Vector3 = Vector3.UP.cross(direction)
	if east.length_squared() < 0.000001:
		east = Vector3.RIGHT.cross(direction)
	east = east.normalized()
	var forward: Vector3 = direction.cross(east).normalized()
	return Basis(east, direction, -forward).orthonormalized()


func _update_camera_clipping() -> void:
	if camera == null:
		return
	var nearest_surface_distance: float = INF
	if celestial_system != null:
		var root_position: Vector3 = get_world_position()
		for body_id in celestial_system.get_body_ids():
			nearest_surface_distance = minf(
				nearest_surface_distance,
				absf(celestial_system.get_surface_distance(body_id, root_position))
			)
	if nearest_surface_distance < 10_000.0:
		camera.near = 0.18
	elif nearest_surface_distance < 1_000_000.0:
		camera.near = clampf(nearest_surface_distance * 0.00012, 0.5, 120.0)
	else:
		camera.near = clampf(nearest_surface_distance * 0.00002, 120.0, 20_000.0)
	camera.far = SPACE_CAMERA_FAR_M


func get_nearest_body_id() -> String:
	if celestial_system == null:
		return ""
	return celestial_system.get_nearest_body_id(get_world_position())


func get_world_position() -> Vector3:
	if celestial_system == null:
		return frame_position
	return celestial_system.transform_point(
		frame_position,
		reference_frame_id,
		celestial_system.get_root_frame_id()
	)


func get_spatial_ref() -> Dictionary:
	if celestial_system == null:
		return SpatialRefScript.create(
			reference_frame_id,
			frame_position,
			orientation,
			linear_velocity_mps,
			angular_velocity_rps
		)
	return celestial_system.create_spatial_ref(
		reference_frame_id,
		frame_position,
		orientation,
		linear_velocity_mps,
		angular_velocity_rps
	)


func get_reference_frame_id() -> String:
	return reference_frame_id


func get_frame_position() -> Vector3:
	return frame_position


func get_movement_speed() -> float:
	return movement_speed


func get_camera() -> Camera3D:
	return camera

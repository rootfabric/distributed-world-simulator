extends CharacterBody3D

const WALK_SPEED: float = 6.0
const RUN_SPEED: float = 11.0
const GROUND_ACCELERATION: float = 20.0
const AIR_ACCELERATION: float = 3.0
const JUMP_SPEED: float = 3.3
const MOUSE_SENSITIVITY: float = 0.00135

var moon_world
var control_enabled: bool = true
var stored_world_position: Vector3 = Vector3.ZERO

var camera_rig: Node3D
var camera_pivot: Node3D
var camera: Camera3D
var visual_root: Node3D

var camera_yaw: float = 0.0
var camera_pitch: float = -0.20


func setup(moon_reference) -> void:
	moon_world = moon_reference
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.75
	safe_margin = 0.025
	floor_max_angle = deg_to_rad(55.0)
	floor_stop_on_slope = true

	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = 1.85
	collision.shape = capsule
	collision.position.y = 0.93
	add_child(collision)

	visual_root = Node3D.new()
	visual_root.name = "AstronautVisual"
	add_child(visual_root)
	_build_astronaut_visual()

	camera_rig = Node3D.new()
	camera_rig.name = "CameraRig"
	camera_rig.position.y = 1.35
	add_child(camera_rig)

	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	camera_rig.add_child(camera_pivot)

	camera = Camera3D.new()
	camera.name = "PlayerCamera"
	camera.current = true
	camera.near = 0.18
	camera.far = 650_000.0
	camera.fov = 68.0
	camera.position = Vector3(0.0, 1.15, 5.8)
	camera_pivot.add_child(camera)
	_update_camera_rotation()


func _physics_process(delta: float) -> void:
	if moon_world == null or not control_enabled:
		return

	var absolute_position: Vector3 = get_world_position()
	var distance_from_center: float = absolute_position.length()
	if distance_from_center < 1.0:
		return

	var up := absolute_position / distance_from_center
	up_direction = up
	_align_body_to_up(up)

	var input_vector := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)
	var camera_forward := -camera_rig.global_transform.basis.z
	camera_forward = camera_forward.slide(up).normalized()
	var camera_right := camera_rig.global_transform.basis.x
	camera_right = camera_right.slide(up).normalized()
	var desired_direction := (
		camera_right * input_vector.x
		+ camera_forward * -input_vector.y
	)
	if desired_direction.length_squared() > 1.0:
		desired_direction = desired_direction.normalized()

	var radial_speed: float = velocity.dot(up)
	var horizontal_velocity := velocity - up * radial_speed
	var target_speed: float = RUN_SPEED if Input.is_action_pressed("boost") else WALK_SPEED
	var acceleration: float = GROUND_ACCELERATION if is_on_floor() else AIR_ACCELERATION
	horizontal_velocity = horizontal_velocity.move_toward(
		desired_direction * target_speed,
		acceleration * delta
	)

	if is_on_floor():
		radial_speed = 0.0
		if Input.is_action_just_pressed("jump"):
			radial_speed = JUMP_SPEED
	else:
		radial_speed -= moon_world.get_gravity_at_distance(distance_from_center) * delta

	velocity = horizontal_velocity + up * radial_speed
	move_and_slide()
	moon_world.recenter_player(self)

	if moon_world.get_altitude(get_world_position()) < -120.0:
		teleport_to_surface(get_world_position().normalized())


func _unhandled_input(event: InputEvent) -> void:
	if not control_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_yaw -= event.relative.x * MOUSE_SENSITIVITY
		camera_pitch -= event.relative.y * MOUSE_SENSITIVITY
		camera_pitch = clampf(camera_pitch, -1.18, 0.48)
		_update_camera_rotation()


func teleport_to_surface(direction_value: Vector3) -> void:
	if moon_world == null:
		return
	var direction := direction_value.normalized()
	var world_position: Vector3 = moon_world.get_surface_point(direction) + direction * 1.15
	global_position = moon_world.world_to_render(world_position)
	velocity = Vector3.ZERO
	_align_body_to_up(direction)
	camera_yaw = 0.0
	camera_pitch = -0.20
	_update_camera_rotation()
	reset_physics_interpolation()


func get_world_position() -> Vector3:
	if moon_world == null:
		return global_position
	return moon_world.render_to_world(global_position)


func set_world_position(world_position: Vector3) -> void:
	global_position = moon_world.world_to_render(world_position)


func freeze_for_spectator() -> void:
	stored_world_position = get_world_position()
	control_enabled = false
	set_physics_process(false)
	camera.current = false
	visual_root.visible = false
	velocity = Vector3.ZERO


func restore_from_spectator() -> void:
	set_world_position(stored_world_position)
	control_enabled = true
	set_physics_process(true)
	camera.current = true
	visual_root.visible = true
	reset_physics_interpolation()


func set_control_enabled(enabled_value: bool) -> void:
	if enabled_value:
		restore_from_spectator()
	else:
		freeze_for_spectator()


func activate_after_spawn() -> void:
	control_enabled = true
	set_physics_process(true)
	camera.current = true
	visual_root.visible = true
	reset_physics_interpolation()


func get_active_camera_world_transform() -> Transform3D:
	return Transform3D(
		camera.global_transform.basis,
		moon_world.render_to_world(camera.global_position)
	)


func get_stored_world_position() -> Vector3:
	return stored_world_position


func _align_body_to_up(up: Vector3) -> void:
	var current_forward := -global_transform.basis.z
	current_forward = current_forward.slide(up)
	if current_forward.length_squared() < 0.0001:
		current_forward = Vector3.FORWARD.slide(up)
	if current_forward.length_squared() < 0.0001:
		current_forward = Vector3.RIGHT.slide(up)
	current_forward = current_forward.normalized()
	var right := current_forward.cross(up).normalized()
	var basis := Basis(right, up, -current_forward).orthonormalized()
	global_transform = Transform3D(basis, global_position)


func _update_camera_rotation() -> void:
	if camera_rig == null or camera_pivot == null:
		return
	camera_rig.rotation = Vector3(0.0, camera_yaw, 0.0)
	camera_pivot.rotation = Vector3(camera_pitch, 0.0, 0.0)


func _make_unshaded_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _add_visual_mesh(
	mesh: Mesh,
	material: Material,
	position_value: Vector3,
	scale_value: Vector3 = Vector3.ONE
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position_value
	instance.scale = scale_value
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual_root.add_child(instance)
	return instance


func _build_astronaut_visual() -> void:
	var suit_material := _make_unshaded_material(Color(0.73, 0.76, 0.80))
	var dark_material := _make_unshaded_material(Color(0.035, 0.045, 0.065))
	var accent_material := _make_unshaded_material(Color(0.72, 0.18, 0.07))

	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.39
	body_mesh.height = 1.15
	body_mesh.radial_segments = 16
	body_mesh.rings = 7
	_add_visual_mesh(body_mesh, suit_material, Vector3(0.0, 1.05, 0.0))

	var helmet_mesh := SphereMesh.new()
	helmet_mesh.radius = 0.34
	helmet_mesh.height = 0.68
	helmet_mesh.radial_segments = 20
	helmet_mesh.rings = 10
	_add_visual_mesh(helmet_mesh, suit_material, Vector3(0.0, 1.78, 0.0))

	var visor_mesh := SphereMesh.new()
	visor_mesh.radius = 0.285
	visor_mesh.height = 0.39
	visor_mesh.radial_segments = 20
	visor_mesh.rings = 10
	_add_visual_mesh(
		visor_mesh,
		dark_material,
		Vector3(0.0, 1.80, -0.18),
		Vector3(1.0, 0.76, 0.46)
	)

	var backpack_mesh := BoxMesh.new()
	backpack_mesh.size = Vector3(0.58, 0.82, 0.30)
	_add_visual_mesh(backpack_mesh, suit_material, Vector3(0.0, 1.15, 0.36))

	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(0.44, 0.12, 0.04)
	_add_visual_mesh(stripe_mesh, accent_material, Vector3(0.0, 1.18, -0.39))

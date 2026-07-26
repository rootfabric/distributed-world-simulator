extends CharacterBody3D

signal controller_changed(previous_id: String, current_id: String)
signal camera_mode_changed(mode: String)

const ControllerHostScript = preload(
	"res://scripts/actors/controllers/controller_host.gd"
)

const CAMERA_FIRST_PERSON: String = "first_person"
const CAMERA_THIRD_PERSON: String = "third_person"

var moon_world
var logger
var control_enabled: bool = true
var stored_world_position: Vector3 = Vector3.ZERO

var controller_host
var camera_anchor: Node3D
var camera_yaw_node: Node3D
var camera_pitch_node: Node3D
var first_person_camera: Camera3D
var third_person_arm: SpringArm3D
var third_person_camera: Camera3D
var visual_root: Node3D

var camera_mode: String = CAMERA_FIRST_PERSON
var camera_yaw: float = 0.0
var camera_pitch: float = deg_to_rad(-8.0)
var camera_pitch_min: float = deg_to_rad(-82.0)
var camera_pitch_max: float = deg_to_rad(72.0)
var default_camera_pitch: float = deg_to_rad(-8.0)


func setup(
	moon_reference,
	logger_reference = null,
	default_controller_id: String = "lunar_humanoid"
) -> void:
	moon_world = moon_reference
	logger = logger_reference
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
	_build_camera_system()

	controller_host = ControllerHostScript.new()
	controller_host.name = "ControllerHost"
	add_child(controller_host)
	controller_host.controller_changed.connect(_on_controller_changed)
	controller_host.setup(self, moon_world, logger, default_controller_id)
	_update_camera_rotation()
	set_camera_mode(camera_mode)


func _build_camera_system() -> void:
	camera_anchor = Node3D.new()
	camera_anchor.name = "CameraAnchor"
	camera_anchor.position.y = 1.62
	add_child(camera_anchor)

	camera_yaw_node = Node3D.new()
	camera_yaw_node.name = "CameraYaw"
	camera_anchor.add_child(camera_yaw_node)

	camera_pitch_node = Node3D.new()
	camera_pitch_node.name = "CameraPitch"
	camera_yaw_node.add_child(camera_pitch_node)

	first_person_camera = Camera3D.new()
	first_person_camera.name = "FirstPersonCamera"
	first_person_camera.near = 0.06
	first_person_camera.far = 650_000.0
	first_person_camera.fov = 75.0
	camera_pitch_node.add_child(first_person_camera)

	third_person_arm = SpringArm3D.new()
	third_person_arm.name = "ThirdPersonSpringArm"
	third_person_arm.spring_length = 5.8
	third_person_arm.margin = 0.25
	third_person_arm.collision_mask = 1
	camera_pitch_node.add_child(third_person_arm)
	third_person_arm.add_excluded_object(get_rid())

	third_person_camera = Camera3D.new()
	third_person_camera.name = "ThirdPersonCamera"
	third_person_camera.position.y = 0.72
	third_person_camera.near = 0.18
	third_person_camera.far = 650_000.0
	third_person_camera.fov = 68.0
	third_person_arm.add_child(third_person_camera)


func _physics_process(delta: float) -> void:
	if control_enabled and controller_host != null:
		controller_host.physics_step(delta)


func _unhandled_input(event: InputEvent) -> void:
	if control_enabled and controller_host != null:
		controller_host.handle_input(event)


func apply_camera_profile(camera_config: Dictionary, apply_default_mode: bool = false) -> void:
	camera_anchor.position.y = float(camera_config.get("eye_height", 1.62))
	camera_pitch_min = deg_to_rad(float(camera_config.get("pitch_min_deg", -82.0)))
	camera_pitch_max = deg_to_rad(float(camera_config.get("pitch_max_deg", 72.0)))
	default_camera_pitch = deg_to_rad(float(camera_config.get("default_pitch_deg", -8.0)))
	first_person_camera.fov = float(camera_config.get("first_person_fov", 75.0))
	first_person_camera.near = float(camera_config.get("first_person_near", 0.06))
	third_person_camera.fov = float(camera_config.get("third_person_fov", 68.0))
	third_person_camera.near = float(camera_config.get("third_person_near", 0.18))
	third_person_camera.position.y = float(camera_config.get("third_person_height_offset", 0.72))
	third_person_arm.spring_length = float(camera_config.get("third_person_distance", 5.8))
	camera_pitch = clampf(camera_pitch, camera_pitch_min, camera_pitch_max)
	if apply_default_mode:
		camera_pitch = default_camera_pitch
		set_camera_mode(String(camera_config.get("default_mode", CAMERA_FIRST_PERSON)))
	_update_camera_rotation()


func adjust_view(yaw_delta: float, pitch_delta: float) -> void:
	camera_yaw += yaw_delta
	camera_pitch = clampf(camera_pitch + pitch_delta, camera_pitch_min, camera_pitch_max)
	_update_camera_rotation()


func _update_camera_rotation() -> void:
	if camera_yaw_node == null or camera_pitch_node == null:
		return
	camera_yaw_node.rotation = Vector3(0.0, camera_yaw, 0.0)
	camera_pitch_node.rotation = Vector3(camera_pitch, 0.0, 0.0)


func set_camera_mode(mode: String) -> void:
	var normalized: String = (
		CAMERA_THIRD_PERSON if mode == CAMERA_THIRD_PERSON else CAMERA_FIRST_PERSON
	)
	var changed: bool = normalized != camera_mode
	camera_mode = normalized
	if first_person_camera != null:
		first_person_camera.current = control_enabled and camera_mode == CAMERA_FIRST_PERSON
	if third_person_camera != null:
		third_person_camera.current = control_enabled and camera_mode == CAMERA_THIRD_PERSON
	if visual_root != null:
		visual_root.visible = control_enabled and camera_mode == CAMERA_THIRD_PERSON
	if changed:
		camera_mode_changed.emit(camera_mode)


func toggle_camera_mode() -> String:
	set_camera_mode(
		CAMERA_THIRD_PERSON
		if camera_mode == CAMERA_FIRST_PERSON
		else CAMERA_FIRST_PERSON
	)
	return camera_mode


func get_camera_mode() -> String:
	return camera_mode


func get_camera_mode_display_name() -> String:
	return "Первое лицо" if camera_mode == CAMERA_FIRST_PERSON else "Третье лицо"


func get_active_camera() -> Camera3D:
	return first_person_camera if camera_mode == CAMERA_FIRST_PERSON else third_person_camera


func get_view_basis() -> Basis:
	var active_camera: Camera3D = get_active_camera()
	return active_camera.global_transform.basis if active_camera != null else global_transform.basis


func activate_controller(profile_id: String) -> bool:
	return controller_host != null and controller_host.activate_controller(profile_id, true)


func get_controller_id() -> String:
	return controller_host.get_current_profile_id() if controller_host != null else ""


func get_controller_display_name() -> String:
	return controller_host.get_current_display_name() if controller_host != null else "Не выбран"


func get_controller_snapshot() -> Dictionary:
	return controller_host.create_snapshot() if controller_host != null else {}


func get_available_controller_ids() -> Array[String]:
	return controller_host.get_available_profile_ids() if controller_host != null else []


func teleport_to_surface(direction_value: Vector3) -> void:
	if moon_world == null:
		return
	var direction := direction_value.normalized()
	var world_position: Vector3 = moon_world.get_surface_point(direction) + direction * 1.15
	global_position = moon_world.world_to_render(world_position)
	velocity = Vector3.ZERO
	align_body_to_up(direction)
	camera_yaw = 0.0
	camera_pitch = default_camera_pitch
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
	if controller_host != null:
		controller_host.set_enabled(false)
	first_person_camera.current = false
	third_person_camera.current = false
	visual_root.visible = false
	velocity = Vector3.ZERO


func restore_from_spectator() -> void:
	set_world_position(stored_world_position)
	control_enabled = true
	set_physics_process(true)
	if controller_host != null:
		controller_host.set_enabled(true)
	set_camera_mode(camera_mode)
	reset_physics_interpolation()


func set_control_enabled(enabled_value: bool) -> void:
	if enabled_value:
		restore_from_spectator()
	else:
		freeze_for_spectator()


func activate_after_spawn() -> void:
	control_enabled = true
	set_physics_process(true)
	if controller_host != null:
		controller_host.set_enabled(true)
	set_camera_mode(camera_mode)
	reset_physics_interpolation()


func get_active_camera_world_transform() -> Transform3D:
	var active_camera: Camera3D = get_active_camera()
	return Transform3D(
		active_camera.global_transform.basis,
		moon_world.render_to_world(active_camera.global_position)
	)


func get_stored_world_position() -> Vector3:
	return stored_world_position


func align_body_to_up(up: Vector3) -> void:
	var current_forward: Vector3 = -global_transform.basis.z
	current_forward = current_forward.slide(up)
	if current_forward.length_squared() < 0.0001:
		current_forward = Vector3.FORWARD.slide(up)
	if current_forward.length_squared() < 0.0001:
		current_forward = Vector3.RIGHT.slide(up)
	current_forward = current_forward.normalized()
	var right: Vector3 = current_forward.cross(up).normalized()
	var basis := Basis(right, up, -current_forward).orthonormalized()
	global_transform = Transform3D(basis, global_position)


func recover_if_below_surface() -> void:
	if moon_world.get_altitude(get_world_position()) < -120.0:
		teleport_to_surface(get_world_position().normalized())


func _on_controller_changed(previous_id: String, current_id: String) -> void:
	controller_changed.emit(previous_id, current_id)


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

class_name QuaterniusCharacterLab
extends Node3D

const AvatarPresenter = preload("res://scripts/characters/presentation/quaternius_avatar_presenter.gd")
const FirstPersonAdapter = preload("res://scripts/characters/presentation/full_body_first_person_adapter.gd")
const PresentationProfile = preload("res://scripts/characters/presentation/controllable_presentation_profile.gd")

const WALK_SPEED := 3.5
const RUN_SPEED := 7.5
const ACCELERATION := 24.0
const GRAVITY := 18.0
const JUMP_SPEED := 6.0
const FIRST_PERSON_EYE_HEIGHT := 1.62
const CAMERA_PITCH_MIN := -1.25
const CAMERA_PITCH_MAX := 1.15

var player: CharacterBody3D
var avatar
var first_person_adapter
var presentation_profile
var camera_pivot: Node3D
var camera_yaw: Node3D
var camera_pitch: Node3D
var camera: Camera3D
var first_person_camera: Camera3D
var third_person_arm: SpringArm3D
var third_person_camera: Camera3D
var status_label: Label
var yaw_offset_deg := 0.0
var first_person_mode := false


func _ready() -> void:
	_build_environment()
	_build_player()
	_build_ui()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	var input_vector := Input.get_vector("ch4_left", "ch4_right", "ch4_forward", "ch4_back")
	var forward := -camera_yaw.global_transform.basis.z
	var right := camera_yaw.global_transform.basis.x
	forward.y = 0.0
	right.y = 0.0
	forward = forward.normalized()
	right = right.normalized()
	var desired := right * input_vector.x + forward * -input_vector.y
	if desired.length_squared() > 1.0:
		desired = desired.normalized()
	var target_speed := RUN_SPEED if Input.is_action_pressed("ch4_run") else WALK_SPEED
	var target_horizontal := desired * target_speed
	player.velocity.x = move_toward(player.velocity.x, target_horizontal.x, ACCELERATION * delta)
	player.velocity.z = move_toward(player.velocity.z, target_horizontal.z, ACCELERATION * delta)
	if player.is_on_floor():
		if Input.is_action_just_pressed("ch4_jump"):
			player.velocity.y = JUMP_SPEED
		else:
			player.velocity.y = -0.1
	else:
		player.velocity.y -= GRAVITY * delta
	player.move_and_slide()

	var avatar_facing := desired
	if first_person_mode:
		avatar_facing = forward
	avatar.apply_motion(player.velocity, Vector3.UP, avatar_facing)
	_refresh_status()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_yaw.rotation.y -= event.relative.x * 0.0025
		camera_pitch.rotation.x = clampf(
			camera_pitch.rotation.x - event.relative.y * 0.0025,
			CAMERA_PITCH_MIN,
			CAMERA_PITCH_MAX
		)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_V:
			yaw_offset_deg = 180.0 if is_zero_approx(yaw_offset_deg) else 0.0
			avatar.set_model_yaw_offset_degrees(yaw_offset_deg)
		elif event.keycode == KEY_C:
			set_first_person_mode(not first_person_mode)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func set_first_person_mode(enabled: bool) -> void:
	first_person_mode = enabled
	if first_person_camera != null:
		first_person_camera.current = first_person_mode
	if third_person_camera != null:
		third_person_camera.current = not first_person_mode
	camera = first_person_camera if first_person_mode else third_person_camera
	if first_person_adapter != null:
		first_person_adapter.set_first_person_enabled(first_person_mode)
	_refresh_status()


func _build_environment() -> void:
	_ensure_input_actions()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	light.light_energy = 1.5
	light.shadow_enabled = true
	add_child(light)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.09, 0.12, 0.18)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.7, 0.75, 0.85)
	environment.ambient_light_energy = 0.7
	world_environment.environment = environment
	add_child(world_environment)
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	add_child(floor_body)
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(30.0, 0.4, 30.0)
	floor_collision.shape = floor_shape
	floor_collision.position.y = -0.2
	floor_body.add_child(floor_collision)
	var floor_mesh_instance := MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(30.0, 0.4, 30.0)
	floor_mesh_instance.mesh = floor_mesh
	floor_mesh_instance.position.y = -0.2
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.18, 0.22, 0.28)
	floor_material.roughness = 0.9
	floor_mesh_instance.material_override = floor_material
	floor_body.add_child(floor_mesh_instance)


func _build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "CH6ControllableBody"
	player.position = Vector3(0.0, 0.05, 0.0)
	player.floor_snap_length = 0.35
	add_child(player)

	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = 1.85
	collision.shape = capsule
	collision.position.y = 0.93
	player.add_child(collision)

	avatar = AvatarPresenter.new()
	avatar.name = "AvatarPresentation"
	player.add_child(avatar)
	avatar.setup({
		"run_threshold_mps": (WALK_SPEED + RUN_SPEED) * 0.5,
		"model_yaw_offset_deg": yaw_offset_deg,
	})

	presentation_profile = PresentationProfile.new()
	presentation_profile.profile_id = &"quaternius_humanoid"
	presentation_profile.entity_kind = &"humanoid"
	presentation_profile.first_person_policy = PresentationProfile.FirstPersonPolicy.HIDE_WORLD_MODEL
	presentation_profile.world_render_layer_index = 20
	presentation_profile.viewmodel_render_layer_index = 19
	presentation_profile.keep_world_animation_active = true
	presentation_profile.allow_shadow_from_hidden_world_model = true

	first_person_adapter = FirstPersonAdapter.new()
	first_person_adapter.name = "ControllableFirstPersonAdapter"
	player.add_child(first_person_adapter)
	first_person_adapter.bind_avatar(avatar, presentation_profile)

	camera_yaw = Node3D.new()
	camera_yaw.name = "CameraYaw"
	camera_yaw.position = Vector3(0.0, FIRST_PERSON_EYE_HEIGHT, 0.0)
	player.add_child(camera_yaw)
	camera_pivot = camera_yaw

	camera_pitch = Node3D.new()
	camera_pitch.name = "CameraPitch"
	camera_yaw.add_child(camera_pitch)

	first_person_camera = Camera3D.new()
	first_person_camera.name = "FirstPersonCamera"
	first_person_camera.near = 0.03
	first_person_camera.fov = 75.0
	camera_pitch.add_child(first_person_camera)

	third_person_arm = SpringArm3D.new()
	third_person_arm.name = "ThirdPersonSpringArm"
	third_person_arm.spring_length = 5.0
	third_person_arm.margin = 0.2
	camera_pitch.add_child(third_person_arm)
	third_person_arm.add_excluded_object(player.get_rid())

	third_person_camera = Camera3D.new()
	third_person_camera.name = "ThirdPersonCamera"
	third_person_camera.near = 0.12
	third_person_camera.fov = 70.0
	third_person_arm.add_child(third_person_camera)

	first_person_adapter.bind_cameras(first_person_camera, third_person_camera)
	set_first_person_mode(false)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	status_label = Label.new()
	status_label.position = Vector2(20.0, 20.0)
	status_label.add_theme_font_size_override("font_size", 18)
	layer.add_child(status_label)
	_refresh_status()


func _refresh_status() -> void:
	if status_label == null or avatar == null:
		return
	var report: Dictionary = avatar.create_report()
	var fp_report: Dictionary = first_person_adapter.create_report() if first_person_adapter != null else {}
	status_label.text = (
		"CH5 fix1 / CH6 Controllable Presentation Lab\n"
		+ "WASD — ходьба | Shift — бег | Space — прыжок | мышь — камера | C — 1/3 лицо | V — развернуть модель\n"
		+ "view: %s\nentity: %s\npolicy: %s\nself body: %s\nasset: %s\nsemantic: %s\nanimation: %s\nmodel: %s\nmatched bones: %d"
		% [
			"FIRST_PERSON" if first_person_mode else "THIRD_PERSON",
			String(fp_report.get("entity_kind", "")),
			String(fp_report.get("first_person_policy", "")),
			"HIDDEN_FROM_FP_CAMERA" if bool(fp_report.get("world_hidden_from_first_person", false)) else "VISIBLE_TO_FP_CAMERA",
			String(report.get("asset_mode", "")),
			String(report.get("current_semantic", "")),
			String(report.get("current_animation", "")),
			String(report.get("model_path", "")),
			int(report.get("matched_bones", 0)),
		]
	)


func _ensure_input_actions() -> void:
	_add_key_action("ch4_forward", KEY_W)
	_add_key_action("ch4_back", KEY_S)
	_add_key_action("ch4_left", KEY_A)
	_add_key_action("ch4_right", KEY_D)
	_add_key_action("ch4_run", KEY_SHIFT)
	_add_key_action("ch4_jump", KEY_SPACE)


func _add_key_action(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	for existing in InputMap.action_get_events(action):
		if existing is InputEventKey and existing.physical_keycode == keycode:
			return
	InputMap.action_add_event(action, event)

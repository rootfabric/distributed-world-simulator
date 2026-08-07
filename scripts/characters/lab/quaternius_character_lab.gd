class_name QuaterniusCharacterLab
extends Node3D

const AvatarPresenter = preload("res://scripts/characters/presentation/quaternius_avatar_presenter.gd")

const WALK_SPEED := 3.5
const RUN_SPEED := 7.5
const ACCELERATION := 24.0
const GRAVITY := 18.0
const JUMP_SPEED := 6.0

var player: CharacterBody3D
var avatar
var camera_pivot: Node3D
var camera: Camera3D
var status_label: Label
var yaw_offset_deg := 0.0


func _ready() -> void:
	_build_environment()
	_build_player()
	_build_ui()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	var input_vector := Input.get_vector("ch4_left", "ch4_right", "ch4_forward", "ch4_back")
	var forward := -camera_pivot.global_transform.basis.z
	var right := camera_pivot.global_transform.basis.x
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
	avatar.apply_motion(player.velocity, Vector3.UP, desired)
	_refresh_status()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_pivot.rotation.y -= event.relative.x * 0.0025
		camera_pivot.rotation.x = clampf(camera_pivot.rotation.x - event.relative.y * 0.0025, -0.55, 0.35)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_V:
			yaw_offset_deg = 180.0 if is_zero_approx(yaw_offset_deg) else 0.0
			avatar.set_model_yaw_offset_degrees(yaw_offset_deg)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
	player.name = "CH4CharacterBody"
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
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	camera_pivot.position = Vector3(0.0, 1.45, 0.0)
	player.add_child(camera_pivot)
	var arm := SpringArm3D.new()
	arm.spring_length = 5.0
	arm.margin = 0.2
	camera_pivot.add_child(arm)
	arm.add_excluded_object(player.get_rid())
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 70.0
	arm.add_child(camera)


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
	status_label.text = (
		"CH4 Quaternius Character Lab\n"
		+ "WASD — ходьба | Shift — бег | Space — прыжок | мышь — камера | V — развернуть модель\n"
		+ "asset: %s\nsemantic: %s\nanimation: %s\nmodel: %s\nmatched bones: %d"
		% [
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

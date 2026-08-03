class_name CharacterLabController
extends CharacterBody3D

const CatalogLoader = preload("res://scripts/characters/registry/character_catalog_loader.gd")
const PresentationHost = preload("res://scripts/characters/presentation/player_presentation_host.gd")
const MotionState = preload("res://scripts/characters/contracts/character_motion_state.gd")
const ActionState = preload("res://scripts/characters/contracts/character_action_state.gd")

const CATALOG_PATH := "res://config/characters/procedural-humanoid-catalog.v1.json"
const WALK_SPEED := 3.0
const RUN_SPEED := 6.0
const ACCELERATION := 18.0
const AIR_ACCELERATION := 6.0
const JUMP_VELOCITY := 6.4
const GRAVITY := 18.0

var presentation_host
var character_registry
var character_ids: Array[String] = []
var character_index := 0
var first_person_mode := false
var action_sequence := 0
var motion_revision := 0
var control_enabled := true
var _test_input_enabled := false
var _test_move := Vector2.ZERO
var _test_run := false
var _test_jump_edge := false
var _test_action_edge := false
var _camera: Camera3D
var _action_until_ms := 0
var _last_grounded := true

func _ready() -> void:
	_ensure_input_actions()
	name = "CharacterLabPlayer"
	_build_collision()
	_build_camera()
	var loaded: Dictionary = CatalogLoader.new().load_registry(CATALOG_PATH)
	if not loaded.success:
		push_error("Character lab catalog failed: %s" % loaded)
		set_physics_process(false)
		return
	character_registry = loaded.details.registry
	character_ids = character_registry.get_character_ids()
	presentation_host = PresentationHost.new()
	presentation_host.name = "PlayerPresentationHost"
	add_child(presentation_host)
	var setup_result: Dictionary = presentation_host.setup(character_registry)
	if not setup_result.success:
		push_error("Character host setup failed: %s" % setup_result)
		set_physics_process(false)
		return
	select_character_by_index(0)

func _ensure_input_actions() -> void:
	_ensure_key_action("move_forward", KEY_W)
	_ensure_key_action("move_back", KEY_S)
	_ensure_key_action("move_left", KEY_A)
	_ensure_key_action("move_right", KEY_D)
	_ensure_key_action("run", KEY_SHIFT)
	_ensure_key_action("jump", KEY_SPACE)
	_ensure_key_action("character_action", KEY_E)
	_ensure_key_action("character_cycle", KEY_TAB)
	_ensure_key_action("first_person_toggle", KEY_F)

func _ensure_key_action(action_name: StringName, physical_keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name, 0.2)
	if not InputMap.action_get_events(action_name).is_empty():
		return
	var event := InputEventKey.new()
	event.physical_keycode = physical_keycode
	InputMap.action_add_event(action_name, event)

func _build_collision() -> void:
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)

func _build_camera() -> void:
	var pivot := Node3D.new()
	pivot.name = "CameraPivot"
	pivot.position = Vector3(0.0, 1.3, 0.0)
	add_child(pivot)
	_camera = Camera3D.new()
	_camera.name = "CharacterLabCamera"
	_camera.position = Vector3(0.0, 1.1, 5.2)
	_camera.rotation.x = -0.12
	_camera.current = true
	pivot.add_child(_camera)

func _physics_process(delta: float) -> void:
	if presentation_host == null:
		return
	var move_input := _test_move if _test_input_enabled else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var running := _test_run if _test_input_enabled else Input.is_action_pressed("run")
	var jump_edge := _consume_test_jump() if _test_input_enabled else Input.is_action_just_pressed("jump")
	var action_edge := _consume_test_action() if _test_input_enabled else Input.is_action_just_pressed("character_action")
	if control_enabled and not _test_input_enabled:
		if Input.is_action_just_pressed("character_cycle"):
			select_character_by_index(character_index + 1)
		if Input.is_action_just_pressed("first_person_toggle"):
			set_first_person_mode(not first_person_mode)
	var desired_direction := Vector3(move_input.x, 0.0, move_input.y)
	if desired_direction.length_squared() > 1.0:
		desired_direction = desired_direction.normalized()
	var speed := RUN_SPEED if running else WALK_SPEED
	var target_velocity := desired_direction * speed
	var horizontal := Vector2(velocity.x, velocity.z)
	var target_horizontal := Vector2(target_velocity.x, target_velocity.z)
	var accel := ACCELERATION if is_on_floor() else AIR_ACCELERATION
	horizontal = horizontal.move_toward(target_horizontal, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif jump_edge:
		velocity.y = JUMP_VELOCITY
	if desired_direction.length_squared() > 0.001:
		rotation.y = lerp_angle(rotation.y, atan2(desired_direction.x, desired_direction.z), minf(1.0, delta * 12.0))
	move_and_slide()
	if action_edge:
		trigger_action("action/pickup", 700)
	_update_presentation()

func _update_presentation() -> void:
	motion_revision += 1
	var grounded := is_on_floor()
	var motion := MotionState.new()
	var motion_result: Dictionary = motion.setup({
		"velocity": {"x": velocity.x, "y": velocity.y, "z": velocity.z},
		"grounded": grounded,
		"stance": "stand",
		"locomotion_mode": "grounded" if grounded else "airborne",
		"facing_yaw": rotation.y,
		"aim_yaw": rotation.y,
		"aim_pitch": 0.0,
		"state_revision": motion_revision,
	})
	if motion_result.success:
		presentation_host.apply_motion_state(motion)
	var action := ActionState.new()
	var action_result: Dictionary = action.setup({
		"action_id": "action/pickup" if Time.get_ticks_msec() < _action_until_ms else "action/none",
		"action_sequence": action_sequence,
		"action_started_tick": motion_revision,
		"equipment_pose": "pose/empty",
		"active": Time.get_ticks_msec() < _action_until_ms,
	})
	if action_result.success:
		presentation_host.apply_action_state(action)
	_last_grounded = grounded

func select_character_by_index(index: int) -> Dictionary:
	if character_ids.is_empty() or presentation_host == null:
		return {"success": false, "error_code": "CHARACTER_LAB_NOT_READY", "details": {}}
	character_index = posmod(index, character_ids.size())
	return presentation_host.select_character(character_ids[character_index], null, true)

func select_character(character_id: StringName) -> Dictionary:
	if presentation_host == null:
		return {"success": false, "error_code": "CHARACTER_LAB_NOT_READY", "details": {}}
	var result: Dictionary = presentation_host.select_character(character_id, null, true)
	if result.success:
		character_index = maxi(0, character_ids.find(String(result.details.character_id)))
	return result

func trigger_action(action_id: String = "action/pickup", duration_ms: int = 700) -> void:
	action_sequence += 1
	_action_until_ms = Time.get_ticks_msec() + maxi(duration_ms, 1)
	var action := ActionState.new()
	var result: Dictionary = action.setup({"action_id": action_id, "action_sequence": action_sequence, "action_started_tick": motion_revision, "equipment_pose": "pose/empty", "active": true})
	if result.success and presentation_host != null:
		presentation_host.apply_action_state(action)

func set_first_person_mode(enabled: bool) -> void:
	first_person_mode = enabled
	if _camera != null:
		_camera.position = Vector3(0.0, 0.32, 0.0) if enabled else Vector3(0.0, 1.1, 5.2)
		_camera.rotation.x = 0.0 if enabled else -0.12
	if presentation_host != null:
		presentation_host.set_first_person_mode(enabled)

func set_test_input(move: Vector2, running: bool = false, jump_edge: bool = false, action_edge: bool = false) -> void:
	_test_input_enabled = true
	_test_move = move
	_test_run = running
	_test_jump_edge = _test_jump_edge or jump_edge
	_test_action_edge = _test_action_edge or action_edge

func clear_test_input() -> void:
	_test_input_enabled = false
	_test_move = Vector2.ZERO
	_test_run = false
	_test_jump_edge = false
	_test_action_edge = false

func _consume_test_jump() -> bool:
	var value := _test_jump_edge
	_test_jump_edge = false
	return value

func _consume_test_action() -> bool:
	var value := _test_action_edge
	_test_action_edge = false
	return value

func create_report() -> Dictionary:
	return {
		"schema": "planet_simulator.character_lab_controller.v1",
		"position": [position.x, position.y, position.z],
		"velocity": [velocity.x, velocity.y, velocity.z],
		"character_ids": character_ids.duplicate(),
		"character_index": character_index,
		"first_person_mode": first_person_mode,
		"action_sequence": action_sequence,
		"host": presentation_host.create_report() if presentation_host != null else {},
	}

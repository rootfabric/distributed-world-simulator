extends SceneTree

const CatalogLoader = preload("res://scripts/characters/registry/character_catalog_loader.gd")
const Host = preload("res://scripts/characters/presentation/player_presentation_host.gd")
const MotionState = preload("res://scripts/characters/contracts/character_motion_state.gd")
const ActionState = preload("res://scripts/characters/contracts/character_action_state.gd")
const Driver = preload("res://scripts/characters/presentation/semantic_animation_driver.gd")

var assertions := 0
var failures := 0

func _init() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("CH3 ASSERTION FAILED: %s" % message)

func _motion(velocity_value: Vector3, grounded_value: bool, revision: int) -> Object:
	var state := MotionState.new()
	var result: Dictionary = state.setup({"velocity":{"x":velocity_value.x,"y":velocity_value.y,"z":velocity_value.z},"grounded":grounded_value,"stance":"stand","locomotion_mode":"grounded" if grounded_value else "airborne","facing_yaw":0.0,"aim_yaw":0.0,"aim_pitch":0.0,"state_revision":revision})
	_check(bool(result.get("success", false)), "motion fixture %d" % revision)
	return state

func _action(action_id: String, sequence: int, active: bool) -> Object:
	var state := ActionState.new()
	var result: Dictionary = state.setup({"action_id":action_id,"action_sequence":sequence,"action_started_tick":sequence,"equipment_pose":"pose/empty","active":active})
	_check(bool(result.get("success", false)), "action fixture %d" % sequence)
	return state

func _run() -> void:
	var loaded: Dictionary = CatalogLoader.new().load_registry("res://config/characters/procedural-humanoid-catalog.v1.json")
	_check(bool(loaded.get("success", false)), "registry loads")
	var registry = loaded.details.registry
	var host := Host.new()
	host.name = "LocalHost"
	get_root().add_child(host)
	_check(bool(host.setup(registry).get("success", false)), "host setup")
	_check(bool(host.select_character(&"human/procedural/standard", null, true).get("success", false)), "standard selected")
	_check(host.create_report().get("active_character_id", "") == "human/procedural/standard", "active id")
	_check(bool(host.create_report().get("adapter", {}).get("model_loaded", false)), "model loaded")
	_check(host.get_socket(&"hand_right") != null, "hand socket")
	_check(host.get_socket(&"head") != null, "head socket")
	var idle = _motion(Vector3.ZERO, true, 1)
	_check(bool(host.apply_motion_state(idle).get("success", false)), "idle applied")
	_check(host.create_report().adapter.current_semantic == "locomotion/idle", "idle semantic")
	var walk = _motion(Vector3(0, 0, -2.5), true, 2)
	host.apply_motion_state(walk)
	_check(host.create_report().adapter.current_semantic == "locomotion/walk", "walk semantic")
	var run = _motion(Vector3(0, 0, -6.0), true, 3)
	host.apply_motion_state(run)
	_check(host.create_report().adapter.current_semantic == "locomotion/run", "run semantic")
	var strafe = _motion(Vector3(3.0, 0, 0), true, 4)
	host.apply_motion_state(strafe)
	_check(host.create_report().adapter.current_semantic == "locomotion/strafe_right", "strafe semantic")
	var jump = _motion(Vector3(0, 3.0, 0), false, 5)
	host.apply_motion_state(jump)
	_check(host.create_report().adapter.current_semantic == "locomotion/jump_start", "jump semantic")
	var fall = _motion(Vector3(0, -2.0, 0), false, 6)
	host.apply_motion_state(fall)
	_check(host.create_report().adapter.current_semantic == "locomotion/fall", "fall semantic")
	var landed = _motion(Vector3.ZERO, true, 7)
	host.apply_motion_state(landed)
	_check(host.create_report().adapter.current_semantic == "locomotion/land", "land semantic")
	var pickup = _action("action/pickup", 1, true)
	host.apply_action_state(pickup)
	_check(host.create_report().adapter.current_semantic == "action/pickup", "action semantic")
	var previous_animation: String = host.create_report().adapter.current_animation
	host.apply_action_state(pickup)
	_check(host.create_report().adapter.current_animation == previous_animation, "same action sequence not replayed")
	var pickup2 = _action("action/pickup", 2, true)
	host.apply_action_state(pickup2)
	_check(host.create_report().adapter.current_semantic == "action/pickup", "new action sequence replays")
	host.set_first_person_mode(true)
	_check(bool(host.create_report().adapter.first_person_mode), "first person set")
	var head_mesh := host.active_adapter.model_root.get_node_or_null("VisualRoot/Head/Mesh") as GeometryInstance3D
	_check(head_mesh != null and not head_mesh.visible, "head hidden")
	host.set_first_person_mode(false)
	_check(head_mesh.visible, "head restored")
	_check(bool(host.select_character(&"human/procedural/slim", null, true).get("success", false)), "slim selected")
	_check(host.create_report().active_character_id == "human/procedural/slim", "slim active")
	_check(bool(host.select_character(&"unknown/model", null, true).get("success", false)), "unknown model falls back")
	_check(host.create_report().active_character_id == "human/procedural/standard", "fallback active")

	var remote_host := Host.new()
	remote_host.name = "RemoteFixtureHost"
	get_root().add_child(remote_host)
	_check(bool(remote_host.setup(registry).get("success", false)), "remote host setup")
	_check(bool(remote_host.select_character(&"human/test_dummy", null, false).get("success", false)), "remote dummy selected")
	remote_host.apply_motion_state(walk)
	_check(not bool(remote_host.create_report().get("local_player", true)), "remote local flag false")
	_check(remote_host.create_report().adapter.current_semantic == "locomotion/walk", "same motion contract remote")

	var driver := Driver.new()
	_check(driver.resolve_motion(idle) == &"locomotion/idle", "driver idle deterministic")
	_check(driver.resolve_motion(run) == &"locomotion/run", "driver run deterministic")
	_check(driver.resolve_action(pickup) == &"action/pickup", "driver first action")
	_check(driver.resolve_action(pickup) == &"", "driver sequence dedupe")

	var lab_scene = load("res://scenes/labs/character/character_presentation_lab.tscn")
	_check(lab_scene is PackedScene, "lab scene loads")
	var lab = (lab_scene as PackedScene).instantiate()
	get_root().add_child(lab)
	await physics_frame
	await physics_frame
	var player = lab.get_player()
	_check(player != null, "lab player created")
	_check(player.presentation_host != null, "lab host created")
	var start_position: Vector3 = player.position
	player.set_test_input(Vector2(0.0, -1.0), false)
	for frame in range(50):
		await physics_frame
	_check(player.position.distance_to(start_position) > 1.0, "visual lab character moves")
	_check(player.presentation_host.create_report().adapter.current_semantic in ["locomotion/walk", "locomotion/run"], "movement drives animation")
	player.set_test_input(Vector2(0.0, -1.0), true)
	for frame in range(20): await physics_frame
	_check(Vector2(player.velocity.x, player.velocity.z).length() > 4.0, "run input accelerates")
	player.set_test_input(Vector2.ZERO, false, true)
	for frame in range(4): await physics_frame
	_check(player.velocity.y > 0.0 and not player.is_on_floor(), "jump moves body")
	for frame in range(100): await physics_frame
	_check(player.is_on_floor(), "player lands")
	player.set_test_input(Vector2.ZERO, false, false, true)
	await physics_frame
	_check(player.action_sequence > 0, "lab action triggered")
	var before_cycle: String = player.presentation_host.create_report().active_character_id
	player.select_character_by_index(player.character_index + 1)
	_check(player.presentation_host.create_report().active_character_id != before_cycle, "lab model cycle")
	player.set_first_person_mode(true)
	_check(player.first_person_mode, "lab first person")
	player.set_first_person_mode(false)
	_check(not player.first_person_mode, "lab third person")
	for index in range(12):
		player.select_character_by_index(index)
	await process_frame
	_check(player.presentation_host.get_child_count() == 1, "model swaps leave one adapter")
	_check(player.create_report().host.character_swaps >= 13, "swap telemetry")

	host.queue_free(); remote_host.queue_free(); lab.queue_free()
	await process_frame
	print("CH3 PASS: %d assertions" % assertions if failures == 0 else "CH3 FAIL: %d/%d" % [failures, assertions])
	quit(0 if failures == 0 else 1)

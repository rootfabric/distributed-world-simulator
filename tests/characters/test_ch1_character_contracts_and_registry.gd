extends SceneTree

const Utils = preload("res://scripts/characters/contracts/character_contract_utils.gd")
const Definition = preload("res://scripts/characters/contracts/character_definition.gd")
const MotionState = preload("res://scripts/characters/contracts/character_motion_state.gd")
const ActionState = preload("res://scripts/characters/contracts/character_action_state.gd")
const Registry = preload("res://scripts/characters/registry/character_registry.gd")
const Adapter = preload("res://scripts/characters/presentation/character_presentation_adapter.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

func _definition_data(character_id: String, display_name: String = "Test Human") -> Dictionary:
	return {"character_id": character_id, "display_name": display_name, "presentation_scene_path": "res://scenes/labs/character/procedural_humanoid.tscn", "asset_revision": 1, "body_profile": {"body_profile_id": "body/human_standard", "standing_height": 1.8, "crouching_height": 1.15, "capsule_radius": 0.35, "eye_height": 1.62, "step_height": 0.35, "mass": 80.0, "movement_profile_id": "movement/humanoid_standard"}, "animation_profile": {"animation_profile_id": "animation/procedural_humanoid", "fallback_semantic": "locomotion/idle", "semantic_map": {"locomotion/idle": "idle", "locomotion/walk": "walk", "locomotion/run": "run", "locomotion/strafe_left": "strafe_left", "locomotion/strafe_right": "strafe_right", "locomotion/jump_start": "jump_start", "locomotion/fall": "fall", "locomotion/land": "land", "action/pickup": "pickup", "action/use": "use"}}, "socket_profile": {"socket_profile_id": "socket/procedural_humanoid", "socket_paths": {"head": "VisualRoot/Sockets/Head", "hand_left": "VisualRoot/Sockets/HandLeft", "hand_right": "VisualRoot/Sockets/HandRight", "back": "VisualRoot/Sockets/Back", "flashlight": "VisualRoot/Sockets/HandRight"}}, "default_appearance": {"appearance_id": "appearance/default", "appearance_revision": 1, "parameters": {"body_color": [0.25, 0.55, 0.9, 1.0]}}}

func _run() -> void:
	_check(Utils.is_valid_id("human/procedural/standard"), "valid ID rejected")
	_check(not Utils.is_valid_id("Human With Spaces"), "unsafe ID accepted")
	_check(Utils.is_json_safe({"a": [1, true, "ok"]}), "JSON-safe value rejected")
	var unsafe_node := Node.new()
	_check(not Utils.is_json_safe({"node": unsafe_node}), "Object accepted as JSON-safe")
	unsafe_node.free()
	var definition := Definition.new()
	var setup_result: Dictionary = definition.setup(_definition_data("human/procedural/standard"))
	_check(setup_result.success, "valid definition rejected: %s" % setup_result)
	_check(definition.to_dict().character_id == "human/procedural/standard", "definition roundtrip lost ID")
	_check(Utils.is_json_safe(definition.to_dict()), "definition serialization is not JSON-safe")
	_check(definition.animation_profile.resolve("unknown/semantic") == &"idle", "animation fallback failed")
	var invalid_path := _definition_data("human/unsafe")
	invalid_path.presentation_scene_path = "res://../unsafe.tscn"
	_check(not Definition.new().setup(invalid_path).success, "unsafe resource path accepted")
	var incomplete_animation := _definition_data("human/incomplete")
	incomplete_animation.animation_profile.semantic_map.erase("locomotion/fall")
	_check(not Definition.new().setup(incomplete_animation).success, "missing required animation accepted")
	var motion := MotionState.new()
	_check(motion.setup({"velocity": {"x": 3.0, "y": 0.0, "z": -2.0}, "grounded": true, "stance": "stand", "locomotion_mode": "grounded", "facing_yaw": 0.2, "aim_yaw": 0.1, "aim_pitch": -0.2, "state_revision": 3}).success, "valid motion rejected")
	_check(absf(motion.horizontal_speed() - sqrt(13.0)) < 0.0001, "horizontal speed incorrect")
	_check(Utils.is_json_safe(motion.to_dict()), "motion serialization not JSON-safe")
	_check(not MotionState.new().setup({"velocity": {"x": 2001.0, "y": 0.0, "z": 0.0}}).success, "unbounded velocity accepted")
	var action := ActionState.new()
	_check(action.setup({"action_id": "action/pickup", "action_sequence": 7, "action_started_tick": 120, "equipment_pose": "pose/tool", "active": true}).success, "valid action rejected")
	_check(action.to_dict().action_sequence == 7, "action sequence lost")
	var registry := Registry.new()
	_check(registry.register_definition(definition, true).success, "definition registration failed")
	_check(not registry.register_definition(definition).success, "duplicate definition accepted")
	var alternate := Definition.new()
	_check(alternate.setup(_definition_data("human/procedural/slim", "Procedural Slim")).success, "alternate setup failed")
	_check(registry.register_definition(alternate).success, "alternate registration failed")
	_check(registry.get_definition("human/procedural/slim") == alternate, "registered definition lookup failed")
	_check(registry.get_definition("human/missing") == definition, "fallback lookup failed")
	_check(registry.seal().success, "registry seal failed")
	_check(not registry.register_definition(Definition.new()).success, "sealed registry accepted registration")
	_check(registry.create_report().definition_count == 2, "registry report count incorrect")
	var adapter := Adapter.new()
	_check(not adapter.apply_motion_state(motion).success, "unconfigured adapter accepted motion")
	_check(adapter.configure(definition, definition.default_appearance, true).success, "adapter configuration failed")
	_check(adapter.apply_motion_state(motion).success, "adapter motion application failed")
	_check(adapter.apply_action_state(action).success, "adapter action application failed")
	_check(adapter.create_report().local_player, "adapter local-player flag lost")
	adapter.free()
	if failures.is_empty():
		print("[CH1] PASS — %d assertions" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error("[CH1] %s" % failure)
		print("[CH1] FAIL — %d failures / %d assertions" % [failures.size(), assertions])
		quit(1)

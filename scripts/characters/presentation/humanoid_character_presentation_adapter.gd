class_name HumanoidCharacterPresentationAdapter
extends "res://scripts/characters/presentation/character_presentation_adapter.gd"

const Driver = preload("res://scripts/characters/presentation/semantic_animation_driver.gd")

var model_root: Node3D
var animation_player: AnimationPlayer
var semantic_driver
var current_semantic := ""
var current_animation := ""
var first_person_mode := false
var _last_motion_state
var _action_locked := false

func configure(definition, appearance, is_local_player: bool) -> Dictionary:
	var base_result: Dictionary = super.configure(definition, appearance, is_local_player)
	if not base_result.success:
		return base_result
	var packed = load(definition.presentation_scene_path)
	if not packed is PackedScene:
		configured = false
		return Utils.failure("CHARACTER_PRESENTATION_SCENE_LOAD_FAILED")
	var instance = (packed as PackedScene).instantiate()
	if not instance is Node3D:
		instance.free()
		configured = false
		return Utils.failure("CHARACTER_PRESENTATION_ROOT_INVALID")
	model_root = instance as Node3D
	model_root.name = "CharacterModel"
	add_child(model_root)
	if model_root.has_method("build_now"):
		model_root.call("build_now")
	if model_root.has_method("apply_appearance"):
		model_root.call("apply_appearance", appearance.parameters)
	animation_player = _find_first(model_root, "AnimationPlayer") as AnimationPlayer
	if animation_player == null:
		model_root.queue_free()
		model_root = null
		configured = false
		return Utils.failure("CHARACTER_ANIMATION_PLAYER_MISSING")
	semantic_driver = Driver.new()
	animation_player.animation_finished.connect(_on_animation_finished)
	_play_semantic(&"locomotion/idle", 0.0)
	return Utils.success({"character_id": definition.character_id})

func apply_motion_state(state) -> Dictionary:
	var base_result: Dictionary = super.apply_motion_state(state)
	if not base_result.success:
		return base_result
	_last_motion_state = state
	rotation.y = state.facing_yaw
	if not _action_locked:
		_play_semantic(semantic_driver.resolve_motion(state), 0.12)
	return Utils.success({"semantic": current_semantic, "animation": current_animation})

func apply_action_state(state) -> Dictionary:
	var base_result: Dictionary = super.apply_action_state(state)
	if not base_result.success:
		return base_result
	var semantic: StringName = semantic_driver.resolve_action(state)
	if semantic != &"":
		_action_locked = true
		_play_semantic(semantic, 0.08, true)
	return Utils.success({"semantic": current_semantic, "animation": current_animation})

func get_socket(socket_id: StringName) -> Node3D:
	if not configured or model_root == null:
		return null
	var path: NodePath = character_definition.socket_profile.resolve_path(socket_id)
	if path.is_empty():
		return null
	return model_root.get_node_or_null(path) as Node3D

func set_first_person_mode(enabled: bool) -> void:
	first_person_mode = enabled
	if model_root == null:
		return
	for node_path in [NodePath("VisualRoot/Head/Mesh"), NodePath("VisualRoot/Visor/Mesh")]:
		var visual := model_root.get_node_or_null(node_path) as GeometryInstance3D
		if visual != null:
			visual.visible = not enabled

func _play_semantic(semantic: StringName, blend: float, force_restart: bool = false) -> void:
	if animation_player == null or character_definition == null:
		return
	var animation_name: StringName = character_definition.animation_profile.resolve(semantic)
	if animation_name == &"" or not animation_player.has_animation(animation_name):
		animation_name = character_definition.animation_profile.resolve(&"locomotion/idle")
		semantic = &"locomotion/idle"
	if not force_restart and current_animation == String(animation_name) and animation_player.is_playing():
		return
	current_semantic = String(semantic)
	current_animation = String(animation_name)
	animation_player.play(animation_name, blend)

func _on_animation_finished(animation_name: StringName) -> void:
	if not _action_locked or String(animation_name) != current_animation:
		return
	_action_locked = false
	if _last_motion_state != null:
		_play_semantic(semantic_driver.resolve_motion(_last_motion_state), 0.1, true)
	else:
		_play_semantic(&"locomotion/idle", 0.1, true)

func _find_first(root: Node, class_name_value: String) -> Node:
	if root.is_class(class_name_value):
		return root
	for child in root.get_children():
		var found := _find_first(child, class_name_value)
		if found != null:
			return found
	return null

func create_report() -> Dictionary:
	var report: Dictionary = super.create_report()
	report["schema"] = "planet_simulator.humanoid_character_presentation_adapter.v1"
	report["current_semantic"] = current_semantic
	report["current_animation"] = current_animation
	report["first_person_mode"] = first_person_mode
	report["action_locked"] = _action_locked
	report["model_loaded"] = model_root != null
	return report

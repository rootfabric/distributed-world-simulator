class_name ProceduralHumanoidAvatarPresenter
extends "res://scripts/characters/avatar/avatar_presenter.gd"

const Contract = preload("res://scripts/characters/avatar/avatar_contract.gd")
const Model = preload(
	"res://scripts/characters/providers/procedural_humanoid_model.gd"
)

const IDLE_SPEED := 0.08
const JUMP_SPEED := 0.35

var _model
var _animation_player: AnimationPlayer
var _current_semantic := "locomotion/idle"
var _current_animation := ""
var _motion_semantic := "locomotion/idle"
var _action_locked := false
var _last_action_sequence := -1
var _run_threshold := 4.5

func configure(
	definition_value: Dictionary,
	appearance_value: Dictionary,
	is_local_player: bool
) -> Dictionary:
	var base := super.configure(
		definition_value,
		appearance_value,
		is_local_player
	)
	if not bool(base.get("success", false)):
		return base
	_run_threshold = maxf(
		0.5,
		float(definition.get("provider_options", {}).get("run_threshold_mps", 4.5))
	)
	_model = Model.new()
	_model.name = "ProceduralHumanoidModel"
	add_child(_model)
	_model.build_now()
	_animation_player = _model.get_animation_player()
	if _animation_player == null:
		return Contract.failure("PROCEDURAL_AVATAR_ANIMATION_PLAYER_MISSING")
	_animation_player.animation_finished.connect(_on_animation_finished)
	_model.apply_appearance(appearance.get("parameters", {}))
	_play_semantic("locomotion/idle", true)
	return Contract.success(create_report())

func apply_motion_state(state: Dictionary) -> Dictionary:
	var base := super.apply_motion_state(state)
	if not bool(base.get("success", false)):
		return base
	var velocity_data: Dictionary = state.get("velocity", {})
	var velocity := Vector3(
		float(velocity_data.get("x", 0.0)),
		float(velocity_data.get("y", 0.0)),
		float(velocity_data.get("z", 0.0))
	)
	rotation.y = float(state.get("facing_yaw", 0.0))
	var grounded := bool(state.get("grounded", true))
	if not grounded:
		_motion_semantic = (
			"locomotion/jump_start"
			if velocity.y > JUMP_SPEED
			else "locomotion/fall"
		)
	else:
		var speed := Vector2(velocity.x, velocity.z).length()
		if speed <= IDLE_SPEED:
			_motion_semantic = "locomotion/idle"
		elif speed >= _run_threshold:
			_motion_semantic = "locomotion/run"
		else:
			_motion_semantic = "locomotion/walk"
	if not _action_locked:
		_play_semantic(_motion_semantic)
	return Contract.success({
		"semantic": _current_semantic,
		"animation": _current_animation,
	})

func apply_action_state(state: Dictionary) -> Dictionary:
	var base := super.apply_action_state(state)
	if not bool(base.get("success", false)):
		return base
	var sequence := int(state.get("action_sequence", 0))
	var action_id := Contract.normalized_id(
		state.get("action_id", "action/none")
	)
	if bool(state.get("active", false)) and sequence != _last_action_sequence:
		_last_action_sequence = sequence
		var semantic_map: Dictionary = definition.get("animation_semantics", {})
		if semantic_map.has(action_id):
			_action_locked = true
			_play_semantic(action_id, true)
	return Contract.success({
		"semantic": _current_semantic,
		"animation": _current_animation,
	})

func apply_appearance(value: Dictionary) -> Dictionary:
	var base := super.apply_appearance(value)
	if bool(base.get("success", false)) and _model != null:
		_model.apply_appearance(value.get("parameters", {}))
	return base

func set_first_person_mode(enabled: bool) -> void:
	super.set_first_person_mode(enabled)
	if _model == null:
		return
	for path in [
		NodePath("VisualRoot/Head/Mesh"),
		NodePath("VisualRoot/Visor/Mesh"),
	]:
		var visual := _model.get_node_or_null(path) as GeometryInstance3D
		if visual != null:
			visual.visible = not enabled

func get_socket(socket_id: StringName) -> Node3D:
	if _model == null:
		return null
	var sockets: Dictionary = definition.get("sockets", {})
	var path := String(
		sockets.get(Contract.normalized_id(socket_id), "")
	)
	if path.is_empty():
		return null
	return _model.get_node_or_null(NodePath(path)) as Node3D

func _play_semantic(
	semantic: String,
	force_restart: bool = false
) -> void:
	if _animation_player == null:
		return
	var semantic_map: Dictionary = definition.get("animation_semantics", {})
	var animation_name := String(
		semantic_map.get(
			semantic,
			semantic_map.get("locomotion/idle", "idle")
		)
	)
	if not _animation_player.has_animation(StringName(animation_name)):
		animation_name = String(
			semantic_map.get("locomotion/idle", "idle")
		)
		semantic = "locomotion/idle"
	if (
		not force_restart
		and _current_animation == animation_name
		and _animation_player.is_playing()
	):
		return
	_current_semantic = semantic
	_current_animation = animation_name
	_animation_player.play(StringName(animation_name), 0.12)

func _on_animation_finished(animation_name: StringName) -> void:
	if not _action_locked or String(animation_name) != _current_animation:
		return
	_action_locked = false
	_play_semantic(_motion_semantic, true)

func create_report() -> Dictionary:
	var report := super.create_report()
	report["schema"] = (
		"planet_simulator.procedural_humanoid_avatar_presenter.v1"
	)
	report["asset_mode"] = "BUILTIN_PROCEDURAL"
	report["current_semantic"] = _current_semantic
	report["current_animation"] = _current_animation
	report["action_locked"] = _action_locked
	report["model"] = _model.create_report() if _model != null else {}
	return report

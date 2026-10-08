class_name QuaterniusAvatarAdapter
extends "res://scripts/characters/avatar/avatar_presenter.gd"

const Contract = preload("res://scripts/characters/avatar/avatar_contract.gd")
const Engine = preload(
	"res://scripts/characters/providers/quaternius_avatar_engine.gd"
)

var _engine
var _last_action_sequence := -1

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
	_engine = Engine.new()
	_engine.name = "QuaterniusAvatarEngine"
	add_child(_engine)
	var options: Dictionary = definition.get(
		"provider_options",
		{}
	).duplicate(true)
	var setup_result: Dictionary = _engine.setup(options)
	if not bool(setup_result.get("success", false)):
		return setup_result
	_apply_first_person_visibility()
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
	var yaw := float(state.get("facing_yaw", 0.0))
	var facing := Vector3(sin(yaw), 0.0, cos(yaw))
	return _engine.apply_motion(velocity, Vector3.UP, facing)

func apply_action_state(state: Dictionary) -> Dictionary:
	var base := super.apply_action_state(state)
	if bool(base.get("success", false)):
		_last_action_sequence = int(
			state.get("action_sequence", _last_action_sequence)
		)
	return base

func set_first_person_mode(enabled: bool) -> void:
	super.set_first_person_mode(enabled)
	_apply_first_person_visibility()

func get_socket(_socket_id: StringName) -> Node3D:
	return null

func _apply_first_person_visibility() -> void:
	if _engine == null:
		return
	_set_visual_visibility(_engine, false)

func _set_visual_visibility(
	node: Node,
	inherited_head: bool
) -> void:
	var token := String(node.name).to_lower()
	var head_branch := (
		inherited_head
		or token.contains("head")
		or token.contains("hair")
		or token.contains("face")
		or token.contains("visor")
	)
	if node is GeometryInstance3D and head_branch:
		(node as GeometryInstance3D).visible = not first_person_mode
	for child in node.get_children():
		_set_visual_visibility(child, head_branch)

func create_report() -> Dictionary:
	var report := super.create_report()
	report["schema"] = "planet_simulator.quaternius_avatar_adapter.v1"
	report["engine"] = _engine.create_report() if _engine != null else {}
	report["action_sequence"] = _last_action_sequence
	return report

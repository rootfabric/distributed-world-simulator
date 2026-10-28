class_name AvatarPresenter
extends Node3D

const Contract = preload("res://scripts/characters/avatar/avatar_contract.gd")

var definition: Dictionary = {}
var appearance: Dictionary = {}
var local_player := false
var configured := false
var first_person_mode := false
var last_motion_state: Dictionary = {}
var last_action_state: Dictionary = {}

func configure(definition_value: Dictionary, appearance_value: Dictionary, is_local_player: bool) -> Dictionary:
	var definition_check := Contract.validate_definition(definition_value)
	if not bool(definition_check.get("success", false)):
		return definition_check
	var appearance_check := Contract.validate_appearance(appearance_value)
	if not bool(appearance_check.get("success", false)):
		return appearance_check
	definition = definition_value.duplicate(true)
	appearance = appearance_value.duplicate(true)
	local_player = is_local_player
	configured = true
	return Contract.success()

func apply_motion_state(state: Dictionary) -> Dictionary:
	if not configured:
		return Contract.failure("AVATAR_PRESENTER_NOT_CONFIGURED")
	var check := Contract.validate_motion(state)
	if not bool(check.get("success", false)):
		return check
	last_motion_state = state.duplicate(true)
	return Contract.success()

func apply_action_state(state: Dictionary) -> Dictionary:
	if not configured:
		return Contract.failure("AVATAR_PRESENTER_NOT_CONFIGURED")
	var check := Contract.validate_action(state)
	if not bool(check.get("success", false)):
		return check
	last_action_state = state.duplicate(true)
	return Contract.success()

func apply_appearance(value: Dictionary) -> Dictionary:
	var check := Contract.validate_appearance(value)
	if not bool(check.get("success", false)):
		return check
	appearance = value.duplicate(true)
	return Contract.success()

func set_first_person_mode(enabled: bool) -> void:
	first_person_mode = enabled

func get_socket(_socket_id: StringName) -> Node3D:
	return null

func shutdown() -> void:
	pass

func create_report() -> Dictionary:
	return {
		"schema": "planet_simulator.avatar_presenter.v1",
		"configured": configured,
		"character_id": String(definition.get("character_id", "")),
		"provider_id": String(definition.get("provider_id", "")),
		"local_player": local_player,
		"first_person_mode": first_person_mode,
		"has_motion_state": not last_motion_state.is_empty(),
		"has_action_state": not last_action_state.is_empty(),
	}

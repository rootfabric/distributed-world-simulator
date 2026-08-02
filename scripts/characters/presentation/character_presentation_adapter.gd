class_name CharacterPresentationAdapter
extends Node3D

const Utils = preload("res://scripts/characters/contracts/character_contract_utils.gd")
const SCHEMA := "planet_simulator.character_presentation_adapter.v1"

var character_definition
var character_appearance
var local_player := false
var configured := false
var last_motion_state
var last_action_state

func configure(definition, appearance, is_local_player: bool) -> Dictionary:
	if definition == null or appearance == null:
		return Utils.failure("MISSING_CHARACTER_PRESENTATION_CONFIGURATION")
	var definition_result: Dictionary = definition.validate()
	if not definition_result.success:
		return definition_result
	var appearance_result: Dictionary = appearance.validate()
	if not appearance_result.success:
		return appearance_result
	character_definition = definition
	character_appearance = appearance
	local_player = is_local_player
	configured = true
	return Utils.success()

func apply_motion_state(state) -> Dictionary:
	if not configured:
		return Utils.failure("CHARACTER_PRESENTATION_NOT_CONFIGURED")
	if state == null:
		return Utils.failure("MISSING_CHARACTER_MOTION_STATE")
	var result: Dictionary = state.validate()
	if not result.success:
		return result
	last_motion_state = state
	return Utils.success()

func apply_action_state(state) -> Dictionary:
	if not configured:
		return Utils.failure("CHARACTER_PRESENTATION_NOT_CONFIGURED")
	if state == null:
		return Utils.failure("MISSING_CHARACTER_ACTION_STATE")
	var result: Dictionary = state.validate()
	if not result.success:
		return result
	last_action_state = state
	return Utils.success()

func get_socket(_socket_id: StringName) -> Node3D:
	return null

func set_first_person_mode(_enabled: bool) -> void:
	pass

func create_report() -> Dictionary:
	return {"schema": SCHEMA, "configured": configured, "character_id": character_definition.character_id if character_definition != null else "", "local_player": local_player, "has_motion_state": last_motion_state != null, "has_action_state": last_action_state != null}

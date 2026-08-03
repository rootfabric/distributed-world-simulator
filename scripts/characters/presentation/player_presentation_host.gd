class_name PlayerPresentationHost
extends Node3D

const Utils = preload("res://scripts/characters/contracts/character_contract_utils.gd")
const HumanoidAdapter = preload("res://scripts/characters/presentation/humanoid_character_presentation_adapter.gd")

var registry
var active_adapter
var active_character_id := ""
var local_player := false
var configured := false
var character_swaps := 0

func setup(character_registry) -> Dictionary:
	if character_registry == null:
		return Utils.failure("MISSING_CHARACTER_REGISTRY")
	var report: Dictionary = character_registry.create_report()
	if not bool(report.get("sealed", false)) or int(report.get("definition_count", 0)) < 1:
		return Utils.failure("CHARACTER_REGISTRY_NOT_READY")
	registry = character_registry
	configured = true
	return Utils.success(report)

func select_character(character_id: StringName, appearance = null, is_local_player: bool = false) -> Dictionary:
	if not configured:
		return Utils.failure("PLAYER_PRESENTATION_HOST_NOT_CONFIGURED")
	var definition = registry.get_definition(character_id)
	if definition == null:
		return Utils.failure("CHARACTER_DEFINITION_UNAVAILABLE")
	var selected_appearance = appearance if appearance != null else definition.default_appearance
	var candidate := HumanoidAdapter.new()
	candidate.name = "CharacterPresentationCandidate"
	add_child(candidate)
	var result: Dictionary = candidate.configure(definition, selected_appearance, is_local_player)
	if not result.success:
		candidate.queue_free()
		return result
	if active_adapter != null:
		active_adapter.queue_free()
	active_adapter = candidate
	active_adapter.name = "ActiveCharacterPresentation"
	active_character_id = definition.character_id
	local_player = is_local_player
	character_swaps += 1
	return Utils.success({"character_id": active_character_id, "fallback_used": active_character_id != String(character_id)})

func apply_motion_state(state) -> Dictionary:
	if active_adapter == null:
		return Utils.failure("NO_ACTIVE_CHARACTER_PRESENTATION")
	return active_adapter.apply_motion_state(state)

func apply_action_state(state) -> Dictionary:
	if active_adapter == null:
		return Utils.failure("NO_ACTIVE_CHARACTER_PRESENTATION")
	return active_adapter.apply_action_state(state)

func get_socket(socket_id: StringName) -> Node3D:
	return active_adapter.get_socket(socket_id) if active_adapter != null else null

func set_first_person_mode(enabled: bool) -> void:
	if active_adapter != null:
		active_adapter.set_first_person_mode(enabled)

func create_report() -> Dictionary:
	return {
		"schema": "planet_simulator.player_presentation_host.v1",
		"configured": configured,
		"active_character_id": active_character_id,
		"local_player": local_player,
		"character_swaps": character_swaps,
		"has_active_adapter": active_adapter != null,
		"adapter": active_adapter.create_report() if active_adapter != null else {},
	}

class_name PlayerAvatarHost
extends Node3D

const Contract = preload("res://scripts/characters/avatar/avatar_contract.gd")

var _catalog
var _providers
var _active_presenter
var _active_character_id := ""
var _local_player := false
var _first_person_mode := false
var _appearance: Dictionary = {}
var _last_motion: Dictionary = {}
var _last_action: Dictionary = {}
var _swap_count := 0

func setup(catalog, providers, initial_character_id: String = "", local_player: bool = false) -> Dictionary:
	if catalog == null or providers == null:
		return Contract.failure("AVATAR_HOST_DEPENDENCY_MISSING")
	_catalog = catalog
	_providers = providers
	_local_player = local_player
	var character_id := initial_character_id.strip_edges().to_lower()
	if character_id.is_empty():
		character_id = _catalog.get_fallback_character_id()
	return switch_avatar(character_id)

func switch_avatar(character_id: String, appearance_override: Dictionary = {}) -> Dictionary:
	if _catalog == null or _providers == null:
		return Contract.failure("AVATAR_HOST_NOT_CONFIGURED")
	var normalized := Contract.normalized_id(character_id)
	if not _catalog.has_definition(normalized):
		return Contract.failure("AVATAR_CHARACTER_UNKNOWN", {"character_id": normalized})
	var definition: Dictionary = _catalog.get_definition_exact(normalized)
	var appearance_value: Dictionary = Dictionary(definition.get("default_appearance", {})).duplicate(true)
	if not appearance_override.is_empty():
		appearance_value = appearance_override.duplicate(true)
	var created: Dictionary = _providers.create_presenter(definition, appearance_value, _local_player)
	if not bool(created.get("success", false)):
		return created
	var presenter = created.get("details", {}).get("presenter")
	presenter.name = "Avatar_%s" % normalized.replace("/", "_")
	add_child(presenter)
	presenter.set_first_person_mode(_first_person_mode)
	if not _last_motion.is_empty():
		var motion_result: Dictionary = presenter.apply_motion_state(_last_motion)
		if not bool(motion_result.get("success", false)):
			presenter.queue_free()
			return motion_result
	if not _last_action.is_empty():
		var action_result: Dictionary = presenter.apply_action_state(_last_action)
		if not bool(action_result.get("success", false)):
			presenter.queue_free()
			return action_result
	var previous = _active_presenter
	_active_presenter = presenter
	_active_character_id = normalized
	_appearance = appearance_value
	_swap_count += 1
	if previous != null and is_instance_valid(previous):
		previous.shutdown()
		previous.queue_free()
	return Contract.success({
		"character_id": _active_character_id,
		"provider_id": String(definition.get("provider_id", "")),
		"swap_count": _swap_count,
	})

func apply_motion_state(state: Dictionary) -> Dictionary:
	var check := Contract.validate_motion(state)
	if not bool(check.get("success", false)):
		return check
	_last_motion = state.duplicate(true)
	if _active_presenter == null:
		return Contract.failure("AVATAR_HOST_NO_ACTIVE_PRESENTER")
	return _active_presenter.apply_motion_state(state)

func apply_action_state(state: Dictionary) -> Dictionary:
	var check := Contract.validate_action(state)
	if not bool(check.get("success", false)):
		return check
	_last_action = state.duplicate(true)
	if _active_presenter == null:
		return Contract.failure("AVATAR_HOST_NO_ACTIVE_PRESENTER")
	return _active_presenter.apply_action_state(state)

func apply_appearance(value: Dictionary) -> Dictionary:
	var check := Contract.validate_appearance(value)
	if not bool(check.get("success", false)):
		return check
	_appearance = value.duplicate(true)
	if _active_presenter == null:
		return Contract.failure("AVATAR_HOST_NO_ACTIVE_PRESENTER")
	return _active_presenter.apply_appearance(value)

func set_first_person_mode(enabled: bool) -> void:
	_first_person_mode = enabled
	if _active_presenter != null:
		_active_presenter.set_first_person_mode(enabled)

func get_socket(socket_id: StringName) -> Node3D:
	return _active_presenter.get_socket(socket_id) if _active_presenter != null else null

func get_active_definition() -> Dictionary:
	if _catalog == null or _active_character_id.is_empty():
		return {}
	return _catalog.get_definition_exact(_active_character_id)

func get_active_character_id() -> String:
	return _active_character_id

func shutdown() -> void:
	if _active_presenter != null and is_instance_valid(_active_presenter):
		_active_presenter.shutdown()

func create_report() -> Dictionary:
	return {
		"schema": "planet_simulator.player_avatar_host.v1",
		"active_character_id": _active_character_id,
		"local_player": _local_player,
		"first_person_mode": _first_person_mode,
		"swap_count": _swap_count,
		"catalog": _catalog.create_report() if _catalog != null else {},
		"providers": _providers.create_report() if _providers != null else {},
		"presenter": _active_presenter.create_report() if _active_presenter != null else {},
	}

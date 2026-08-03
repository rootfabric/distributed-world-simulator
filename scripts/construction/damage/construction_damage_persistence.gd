extends RefCounted

const StoreScript = preload("res://scripts/construction/damage/construction_damage_history_store.gd")

var _history
var _state_store
var _state_key := "construction-damage-c9"

func setup(history_store, state_store, state_key: String = "construction-damage-c9") -> Dictionary:
	if history_store == null or not history_store.has_method("to_dict") or not history_store.has_method("load_dict"):
		return _failure("CONSTRUCTION_DAMAGE_HISTORY_STORE_REQUIRED")
	if state_store == null or not state_store.has_method("save_state") or not state_store.has_method("load_state"):
		return _failure("CONSTRUCTION_DAMAGE_PERSISTENCE_STORE_REQUIRED")
	_history = history_store
	_state_store = state_store
	_state_key = state_key
	return _success()

func save() -> Dictionary:
	var state: Dictionary = _history.to_dict()
	var saved: Dictionary = _state_store.save_state(_state_key, state)
	if not bool(saved.get("success", false)): return saved
	return _success({"checksum": String(state["checksum"]), "state": state})

func load() -> Dictionary:
	var loaded: Dictionary = _state_store.load_state(_state_key)
	if not bool(loaded.get("success", false)): return loaded
	var state = loaded.get("state", {})
	if typeof(state) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_DAMAGE_PERSISTED_STATE")
	var validation := StoreScript.validate_state(state)
	if not bool(validation.get("success", false)): return validation
	var candidate = StoreScript.new()
	candidate.setup()
	var candidate_load := candidate.load_dict(state)
	if not bool(candidate_load.get("success", false)): return candidate_load
	return _history.load_dict(candidate.to_dict())

static func _success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result

static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": code}

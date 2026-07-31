extends RefCounted

const StateScript = preload("res://scripts/construction/authoritative/construction_authoritative_state.gd")

var _adapter
var _store
var _state_key: String = "construction-authoritative-state"
var _configured: bool = false


func setup(adapter, store, state_key: String = "construction-authoritative-state") -> Dictionary:
	if adapter == null or not adapter.has_method("export_state") or not adapter.has_method("load_state"):
		return _failure("AUTHORITATIVE_CONSTRUCTION_ADAPTER_REQUIRED")
	if store == null or not store.has_method("save_state") or not store.has_method("load_state"):
		return _failure("AUTHORITATIVE_CONSTRUCTION_STATE_STORE_REQUIRED")
	if state_key.strip_edges().is_empty():
		return _failure("AUTHORITATIVE_CONSTRUCTION_STATE_KEY_REQUIRED")
	_adapter = adapter
	_store = store
	_state_key = state_key
	_configured = true
	return _success()


func save() -> Dictionary:
	if not _configured:
		return _failure("AUTHORITATIVE_CONSTRUCTION_PERSISTENCE_NOT_CONFIGURED")
	var state: Dictionary = _adapter.export_state()
	var validation: Dictionary = StateScript.validate(state)
	if not bool(validation.get("success", false)):
		return validation
	var saved: Dictionary = _store.save_state(_state_key, state)
	if not bool(saved.get("success", false)):
		return saved
	var result: Dictionary = _success({
		"state_key": _state_key,
		"checksum": String(state["checksum"]),
	})
	for key in saved:
		if not result.has(key):
			result[key] = saved[key]
	return result


func load() -> Dictionary:
	if not _configured:
		return _failure("AUTHORITATIVE_CONSTRUCTION_PERSISTENCE_NOT_CONFIGURED")
	var loaded: Dictionary = _store.load_state(_state_key)
	if not bool(loaded.get("success", false)):
		return loaded
	var state_value = loaded.get("state", {})
	if not state_value is Dictionary:
		return _failure("INVALID_AUTHORITATIVE_CONSTRUCTION_PERSISTED_STATE")
	var state: Dictionary = state_value
	var validation: Dictionary = StateScript.validate(state)
	if not bool(validation.get("success", false)):
		return validation
	var applied: Dictionary = _adapter.load_state(state)
	if not bool(applied.get("success", false)):
		return applied
	return _success({
		"state_key": _state_key,
		"checksum": String(state["checksum"]),
	})


func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result


func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": false, "error_code": code, "message": code}
	for key in details:
		result[key] = details[key]
	return result

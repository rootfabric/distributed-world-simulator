extends RefCounted

const StoreScript = preload("res://scripts/construction/mobile/construction_mobile_profile_store.gd")

var _profile_store
var _state_store
var _state_key: String = "construction-mobile-profiles"
var _configured: bool = false


func setup(profile_store, state_store, state_key: String = "construction-mobile-profiles") -> Dictionary:
	if profile_store == null or not profile_store.has_method("to_dict") or not profile_store.has_method("load_dict"):
		return _failure("CONSTRUCTION_MOBILE_PROFILE_STORE_REQUIRED")
	if state_store == null or not state_store.has_method("save_state") or not state_store.has_method("load_state"):
		return _failure("CONSTRUCTION_MOBILE_STATE_STORE_REQUIRED")
	if state_key.strip_edges().is_empty():
		return _failure("CONSTRUCTION_MOBILE_STATE_KEY_REQUIRED")
	_profile_store = profile_store
	_state_store = state_store
	_state_key = state_key
	_configured = true
	return _success()


func save() -> Dictionary:
	if not _configured:
		return _failure("CONSTRUCTION_MOBILE_PERSISTENCE_NOT_CONFIGURED")
	var state: Dictionary = _profile_store.to_dict()
	var validation: Dictionary = StoreScript.validate_state(state)
	if not bool(validation.get("success", false)):
		return validation
	var saved: Dictionary = _state_store.save_state(_state_key, state)
	if not bool(saved.get("success", false)):
		return saved
	return _success({"checksum": String(state["checksum"]), "generation": int(state["generation"])})


func load() -> Dictionary:
	if not _configured:
		return _failure("CONSTRUCTION_MOBILE_PERSISTENCE_NOT_CONFIGURED")
	var loaded: Dictionary = _state_store.load_state(_state_key)
	if not bool(loaded.get("success", false)):
		return loaded
	var state_value = loaded.get("state", {})
	if not state_value is Dictionary:
		return _failure("INVALID_CONSTRUCTION_MOBILE_PERSISTED_STATE")
	return _profile_store.load_dict(Dictionary(state_value))


func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result


func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": code}

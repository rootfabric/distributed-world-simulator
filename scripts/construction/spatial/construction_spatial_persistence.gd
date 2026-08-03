extends RefCounted

const StoreScript = preload("res://scripts/construction/spatial/construction_spatial_profile_store.gd")
var _profile_store
var _state_store
var _state_key: String = "construction-spatial-profile-store"

func setup(profile_store, state_store, state_key: String = "construction-spatial-profile-store") -> Dictionary:
	if profile_store == null or not profile_store.has_method("to_dict") or not profile_store.has_method("load_dict"):
		return _failure("CONSTRUCTION_SPATIAL_PROFILE_STORE_REQUIRED")
	if state_store == null or not state_store.has_method("save_state") or not state_store.has_method("load_state"):
		return _failure("CONSTRUCTION_SPATIAL_STATE_STORE_REQUIRED")
	if state_key.strip_edges().is_empty():
		return _failure("CONSTRUCTION_SPATIAL_STATE_KEY_REQUIRED")
	_profile_store = profile_store
	_state_store = state_store
	_state_key = state_key
	return _success()

func save() -> Dictionary:
	var state: Dictionary = _profile_store.to_dict()
	var result: Dictionary = _state_store.save_state(_state_key, state)
	if not bool(result.get("success", false)):
		return result
	return _success({"checksum": String(state["checksum"]), "generation": int(state["generation"])})

func load() -> Dictionary:
	var loaded: Dictionary = _state_store.load_state(_state_key)
	if not bool(loaded.get("success", false)):
		return loaded
	if typeof(loaded.get("state")) != TYPE_DICTIONARY:
		return _failure("INVALID_CONSTRUCTION_SPATIAL_PERSISTED_STATE")
	return _profile_store.load_dict(loaded["state"])

static func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result
static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}

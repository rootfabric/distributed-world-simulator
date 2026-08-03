extends RefCounted

const State = preload("res://scripts/construction/acceptance/construction_scale_state.gd")

static func save(store, key: String, state: Dictionary) -> Dictionary:
	var sealed := State.seal(state)
	var validation := State.validate(sealed)
	if not bool(validation.get("success", false)):
		return _failure("CONSTRUCTION_SCALE_PERSISTENCE_STATE_INVALID", {"cause": validation})
	if store == null or not store.has_method("write"):
		return _failure("CONSTRUCTION_SCALE_PERSISTENCE_STORE_INVALID")
	return store.write(key, sealed)

static func load(store, key: String) -> Dictionary:
	if store == null or not store.has_method("read"):
		return _failure("CONSTRUCTION_SCALE_PERSISTENCE_STORE_INVALID")
	var result: Dictionary = store.read(key)
	if not bool(result.get("success", false)):
		return result
	var state := Dictionary(result.get("value", {})).duplicate(true)
	var validation := State.validate(state)
	if not bool(validation.get("success", false)):
		return _failure("CONSTRUCTION_SCALE_PERSISTENCE_STATE_INVALID", {"cause": validation})
	return _success({"state": state})

static func _success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": ""}
	result.merge(details, true)
	return result

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}

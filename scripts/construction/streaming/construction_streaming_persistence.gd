extends RefCounted

const KEY := "construction/streaming/v1"

static func save(storage, controller) -> Dictionary:
	if storage == null or not storage.has_method("save_state") or controller == null or not controller.has_method("export_state"):
		return _failure("CONSTRUCTION_STREAMING_PERSISTENCE_DEPENDENCY_REQUIRED")
	return storage.save_state(KEY, controller.export_state())

static func load(storage, controller) -> Dictionary:
	if storage == null or not storage.has_method("load_state") or controller == null or not controller.has_method("load_state"):
		return _failure("CONSTRUCTION_STREAMING_PERSISTENCE_DEPENDENCY_REQUIRED")
	var loaded: Dictionary = storage.load_state(KEY)
	if not bool(loaded.get("success", false)): return loaded
	if typeof(loaded.get("state")) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_STREAMING_PERSISTED_STATE")
	return controller.load_state(loaded["state"])

static func _failure(code: String) -> Dictionary: return {"success": false, "error_code": code, "message": code}

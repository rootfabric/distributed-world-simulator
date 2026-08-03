extends RefCounted

const StoreScript = preload("res://scripts/construction/runtime_projection/construction_runtime_projection_store.gd")
const KEY := "construction/runtime-projection-store"

static func save(storage, store) -> Dictionary:
	if storage == null or not storage.has_method("put"): return _failure("CONSTRUCTION_RUNTIME_PERSISTENCE_STORAGE_INVALID")
	return storage.put(KEY, store.export_state())

static func load(storage, store) -> Dictionary:
	if storage == null or not storage.has_method("get_value"): return _failure("CONSTRUCTION_RUNTIME_PERSISTENCE_STORAGE_INVALID")
	var loaded: Dictionary = storage.get_value(KEY)
	if not bool(loaded.get("success", false)): return loaded
	return store.load_state(loaded.get("value", {}))

static func _failure(code: String) -> Dictionary: return {"success": false, "error_code": code, "message": code, "details": {}}

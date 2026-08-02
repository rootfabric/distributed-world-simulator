extends RefCounted

const C = preload("res://scripts/construction/proxies/construction_proxy_contract_utils.gd")
const KEY := "construction/proxies/c22"

static func save(storage, controller) -> Dictionary:
	if storage == null or not storage.has_method("save_state"): return C.failure("INVALID_CONSTRUCTION_PROXY_PERSISTENCE_STORAGE")
	return storage.save_state(KEY, controller.export_state())

static func load(storage, controller) -> Dictionary:
	if storage == null or not storage.has_method("load_state"): return C.failure("INVALID_CONSTRUCTION_PROXY_PERSISTENCE_STORAGE")
	var loaded: Dictionary = storage.load_state(KEY)
	if not bool(loaded.get("success", false)): return loaded
	return controller.load_state(loaded["state"])

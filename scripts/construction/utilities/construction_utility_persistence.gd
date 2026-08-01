extends RefCounted
const ContractUtils = preload("res://scripts/construction/utilities/construction_utility_contract_utils.gd")
const KEY := "construction/executable-utility-profile-store"
static func save(storage, store) -> Dictionary:
	if storage == null or not storage.has_method("put"): return ContractUtils.failure("CONSTRUCTION_UTILITY_PERSISTENCE_STORAGE_INVALID")
	return storage.put(KEY, store.export_state())
static func load(storage, store) -> Dictionary:
	if storage == null or not storage.has_method("get_value"): return ContractUtils.failure("CONSTRUCTION_UTILITY_PERSISTENCE_STORAGE_INVALID")
	var loaded: Dictionary = storage.get_value(KEY); if not bool(loaded.get("success", false)): return loaded
	return store.load_state(loaded.get("value", {}))

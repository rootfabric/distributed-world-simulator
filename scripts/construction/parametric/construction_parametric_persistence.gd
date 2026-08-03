extends RefCounted

const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")

const CATALOG_KEY := "construction/parametric/catalog/v1"
const MEMBER_STORE_KEY := "construction/parametric/members/v1"

static func save_catalog(storage, catalog) -> Dictionary:
	if storage == null or not storage.has_method("save_state") or catalog == null or not catalog.has_method("export_state"): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_PERSISTENCE_DEPENDENCY_REQUIRED")
	return storage.save_state(CATALOG_KEY, catalog.export_state())

static func load_catalog(storage, catalog) -> Dictionary:
	if storage == null or not storage.has_method("load_state") or catalog == null or not catalog.has_method("load_state"): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_PERSISTENCE_DEPENDENCY_REQUIRED")
	var loaded: Dictionary = storage.load_state(CATALOG_KEY)
	if not bool(loaded.get("success", false)): return loaded
	return catalog.load_state(Dictionary(loaded.get("state", {})))

static func save_member_store(storage, member_store) -> Dictionary:
	if storage == null or not storage.has_method("save_state") or member_store == null or not member_store.has_method("export_state"): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_PERSISTENCE_DEPENDENCY_REQUIRED")
	return storage.save_state(MEMBER_STORE_KEY, member_store.export_state())

static func load_member_store(storage, member_store) -> Dictionary:
	if storage == null or not storage.has_method("load_state") or member_store == null or not member_store.has_method("load_state"): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_PERSISTENCE_DEPENDENCY_REQUIRED")
	var loaded: Dictionary = storage.load_state(MEMBER_STORE_KEY)
	if not bool(loaded.get("success", false)): return loaded
	return member_store.load_state(Dictionary(loaded.get("state", {})))

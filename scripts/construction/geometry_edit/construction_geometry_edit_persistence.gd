extends RefCounted

const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const HistoryScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_history_store.gd")

const STORAGE_KEY := "construction/geometry-edit-history/v1"

static func save(storage, history) -> Dictionary:
	if storage == null or not storage.has_method("save_state") or history == null or not history.has_method("export_state"): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_PERSISTENCE_DEPENDENCY_REQUIRED")
	return storage.save_state(STORAGE_KEY, history.export_state())

static func load(storage, history) -> Dictionary:
	if storage == null or not storage.has_method("load_state") or history == null or not history.has_method("load_state"): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_PERSISTENCE_DEPENDENCY_REQUIRED")
	var loaded: Dictionary = storage.load_state(STORAGE_KEY); if not bool(loaded.get("success", false)): return loaded
	var state = loaded.get("state", {}); if typeof(state) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_PERSISTED_STATE")
	var checked := HistoryScript.validate_state(state); if not bool(checked.get("success", false)): return checked
	return history.load_state(state)

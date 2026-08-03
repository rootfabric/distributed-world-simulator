extends RefCounted

const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const GatewayScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_gateway.gd")

const STORAGE_KEY := "construction/multiplayer-acceptance/v1"

static func save(storage, gateway) -> Dictionary:
	if storage == null or not storage.has_method("save_state") or gateway == null or not gateway.has_method("export_state"):
		return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_PERSISTENCE_DEPENDENCY_REQUIRED")
	return storage.save_state(STORAGE_KEY, gateway.export_state())

static func load(storage, gateway) -> Dictionary:
	if storage == null or not storage.has_method("load_state") or gateway == null or not gateway.has_method("load_state"):
		return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_PERSISTENCE_DEPENDENCY_REQUIRED")
	var loaded: Dictionary = storage.load_state(STORAGE_KEY)
	if not bool(loaded.get("success", false)): return loaded
	var state = loaded.get("state", {})
	if typeof(state) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_PERSISTED_STATE")
	var checked := GatewayScript.validate_state(state)
	if not bool(checked.get("success", false)): return checked
	return gateway.load_state(state)

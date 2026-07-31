extends RefCounted

const RegistryScript = preload("res://scripts/construction/composites/construction_composite_registry.gd")

var _registry
var _state_store
var _state_key: String = "construction-composite-registry"
var _configured: bool = false


func setup(registry, state_store, state_key: String = "construction-composite-registry") -> Dictionary:
	if registry == null or not registry.has_method("to_dict") or not registry.has_method("load_dict"):
		return _failure("CONSTRUCTION_COMPOSITE_REGISTRY_REQUIRED")
	if state_store == null or not state_store.has_method("save_state") or not state_store.has_method("load_state"):
		return _failure("CONSTRUCTION_COMPOSITE_STATE_STORE_REQUIRED")
	if state_key.strip_edges().is_empty():
		return _failure("CONSTRUCTION_COMPOSITE_STATE_KEY_REQUIRED")
	_registry = registry
	_state_store = state_store
	_state_key = state_key
	_configured = true
	return _success()


func save() -> Dictionary:
	if not _configured:
		return _failure("CONSTRUCTION_COMPOSITE_PERSISTENCE_NOT_CONFIGURED")
	var state: Dictionary = _registry.to_dict()
	var validation: Dictionary = RegistryScript.validate_state(state)
	if not bool(validation.get("success", false)):
		return validation
	return _state_store.save_state(_state_key, state)


func load() -> Dictionary:
	if not _configured:
		return _failure("CONSTRUCTION_COMPOSITE_PERSISTENCE_NOT_CONFIGURED")
	var loaded: Dictionary = _state_store.load_state(_state_key)
	if not bool(loaded.get("success", false)):
		return loaded
	if not loaded.get("state", {}) is Dictionary:
		return _failure("INVALID_CONSTRUCTION_COMPOSITE_PERSISTED_STATE")
	return _registry.load_dict(Dictionary(loaded["state"]))


func _success() -> Dictionary:
	return {"success": true, "error_code": "", "message": ""}


func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": code}

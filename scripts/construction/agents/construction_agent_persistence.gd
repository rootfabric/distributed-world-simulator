extends RefCounted
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const Api=preload("res://scripts/construction/agents/construction_agent_automation_api.gd")
const KEY="construction-agent-automation/v1"
static func save(storage,api)->Dictionary:
 if storage==null or not storage.has_method("save_state") or api==null or not api.has_method("export_state"):return P.failure("CONSTRUCTION_AGENT_PERSISTENCE_DEPENDENCY_REQUIRED")
 return storage.save_state(KEY,api.export_state())
static func load(storage,api)->Dictionary:
 if storage==null or not storage.has_method("load_state") or api==null or not api.has_method("load_state"):return P.failure("CONSTRUCTION_AGENT_PERSISTENCE_DEPENDENCY_REQUIRED")
 var loaded=storage.load_state(KEY);if not bool(loaded.get("success",false)):return loaded
 var state=Dictionary(loaded.get("state",{}));var checked=Api.validate_state(state);if not bool(checked.success):return checked
 return api.load_state(state)

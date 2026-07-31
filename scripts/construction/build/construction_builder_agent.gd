extends RefCounted

const GhostScript = preload("res://scripts/construction/build/construction_ghost_state.gd")

var _process
var _actor_id: String = ""
var _capabilities: Array = []
var _configured: bool = false


func setup(build_process, actor_id: String, capabilities: Array = []) -> Dictionary:
	if build_process == null or not build_process.has_method("advance_stage") or not build_process.has_method("get_store"):
		return _failure("CONSTRUCTION_BUILD_PROCESS_REQUIRED")
	if not _is_actor_id(actor_id):
		return _failure("INVALID_CONSTRUCTION_BUILDER_ACTOR_ID")
	var resolved_capabilities: Array[String] = []
	var seen: Dictionary = {}
	for raw in capabilities:
		if typeof(raw) != TYPE_STRING:
			return _failure("INVALID_CONSTRUCTION_BUILDER_CAPABILITY")
		var capability: String = String(raw)
		if capability.is_empty() or capability != capability.to_upper() or seen.has(capability):
			return _failure("INVALID_CONSTRUCTION_BUILDER_CAPABILITY")
		seen[capability] = true
		resolved_capabilities.append(capability)
	resolved_capabilities.sort()
	_process = build_process
	_actor_id = actor_id
	_capabilities = resolved_capabilities
	_configured = true
	return _success()


func execute_next_stage(build_plan_id: String, options: Dictionary = {}) -> Dictionary:
	if not _configured:
		return _failure("CONSTRUCTION_BUILDER_AGENT_NOT_CONFIGURED")
	var store = _process.get_store()
	var ghost: Dictionary = store.get_ghost(build_plan_id)
	if ghost.is_empty():
		return _failure("CONSTRUCTION_BUILD_PLAN_NOT_FOUND")
	if String(ghost["status"]) == GhostScript.STATUS_COMPLETE:
		return _success({"complete": true, "replay": true, "ghost": ghost})
	if String(ghost["status"]) == GhostScript.STATUS_CANCELLED:
		return _failure("CONSTRUCTION_GHOST_CANCELLED")
	var stage_index: int = int(ghost["next_stage_index"])
	var operation_id: String = "operation/builder/%s/%s/stage-%d" % [
		_actor_id.trim_prefix("actor/").replace("/", ":"),
		build_plan_id.trim_prefix("build-plan/").replace("/", ":"),
		stage_index,
	]
	return _process.advance_stage(build_plan_id, stage_index, operation_id, _capabilities, options)


func run_until_complete(build_plan_id: String, maximum_stages: int = 64) -> Dictionary:
	if not _configured:
		return _failure("CONSTRUCTION_BUILDER_AGENT_NOT_CONFIGURED")
	if maximum_stages < 1:
		return _failure("INVALID_CONSTRUCTION_BUILDER_STAGE_LIMIT")
	var results: Array = []
	for _index in range(maximum_stages):
		var ghost: Dictionary = _process.get_store().get_ghost(build_plan_id)
		if ghost.is_empty():
			return _failure("CONSTRUCTION_BUILD_PLAN_NOT_FOUND")
		if String(ghost["status"]) == GhostScript.STATUS_COMPLETE:
			return _success({"complete": true, "stage_results": results, "ghost": ghost})
		var result: Dictionary = execute_next_stage(build_plan_id)
		results.append(result.duplicate(true))
		if not bool(result.get("success", false)):
			return _failure("CONSTRUCTION_BUILDER_BLOCKED", {"cause": result, "stage_results": results})
	return _failure("CONSTRUCTION_BUILDER_STAGE_LIMIT_EXCEEDED", {"stage_results": results})


func _is_actor_id(value: String) -> bool:
	if not value.begins_with("actor/") or value.length() <= 6 or value != value.strip_edges().to_lower():
		return false
	for character in value:
		if not String(character) in [
			"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
			"n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
			"0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "-", "_", ".", "/", ":",
		]:
			return false
	return true


func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result


func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": false, "error_code": code, "message": code}
	for key in details:
		result[key] = details[key]
	return result

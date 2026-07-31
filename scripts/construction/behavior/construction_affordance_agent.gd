extends RefCounted

const QueryScript = preload("res://scripts/construction/behavior/construction_affordance_query.gd")
const ResolverScript = preload("res://scripts/construction/behavior/construction_affordance_resolver.gd")

var _profile_store
var _actor_id: String = ""
var _actor_capabilities: Array = []
var _configured: bool = false


func setup(profile_store, actor_id: String, actor_capabilities: Array = []) -> Dictionary:
	if profile_store == null or not profile_store.has_method("list_profiles"):
		return _failure("CONSTRUCTION_AFFORDANCE_PROFILE_STORE_REQUIRED")
	if not _is_path_id(actor_id, "actor/"):
		return _failure("INVALID_CONSTRUCTION_AFFORDANCE_ACTOR_ID")
	var seen: Dictionary = {}
	var capabilities: Array = []
	for raw in actor_capabilities:
		var capability: String = String(raw)
		if not _is_upper_kind(capability) or seen.has(capability):
			return _failure("INVALID_CONSTRUCTION_AFFORDANCE_ACTOR_CAPABILITY")
		seen[capability] = true
		capabilities.append(capability)
	capabilities.sort()
	_profile_store = profile_store
	_actor_id = actor_id
	_actor_capabilities = capabilities
	_configured = true
	return _success()


func find_actions(
	query_id: String,
	action_kinds: Array,
	options: Dictionary = {}
) -> Dictionary:
	if not _configured:
		return _failure("CONSTRUCTION_AFFORDANCE_AGENT_NOT_CONFIGURED")
	var query: Dictionary = QueryScript.create(
		query_id,
		action_kinds,
		_actor_capabilities,
		Array(options.get("construct_ids", [])),
		Dictionary(options.get("minimum_properties", {})),
		Dictionary(options.get("exact_properties", {})),
		bool(options.get("require_port_target", false)),
		int(options.get("limit", 16))
	)
	var resolved: Dictionary = ResolverScript.resolve(query, _profile_store.list_profiles())
	if not bool(resolved.get("success", false)):
		return resolved
	resolved["actor_id"] = _actor_id
	return resolved


func choose_action(
	query_id: String,
	action_kind: String,
	options: Dictionary = {}
) -> Dictionary:
	var result: Dictionary = find_actions(query_id, [action_kind], options)
	if not bool(result.get("success", false)):
		return result
	if result["candidates"].is_empty():
		return _failure("CONSTRUCTION_AFFORDANCE_NOT_FOUND", {
			"actor_id": _actor_id,
			"action_kind": action_kind,
		})
	return _success({
		"actor_id": _actor_id,
		"query_id": query_id,
		"candidate_count": int(result["candidate_count"]),
		"selected": Dictionary(result["candidates"][0]).duplicate(true),
	})


func _is_path_id(value: String, prefix: String) -> bool:
	if not value.begins_with(prefix) or value.length() <= prefix.length() or value != value.to_lower() or value.contains("//"):
		return false
	for segment in value.split("/", true):
		if segment.is_empty():
			return false
		for character in segment:
			if not String(character) in "abcdefghijklmnopqrstuvwxyz0123456789-_":
				return false
	return true


func _is_upper_kind(value: String) -> bool:
	if value.is_empty() or value != value.to_upper():
		return false
	for character in value:
		if not String(character) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_":
			return false
	return true


func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result


func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}

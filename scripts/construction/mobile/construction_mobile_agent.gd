extends RefCounted

const CommandScript = preload("res://scripts/construction/mobile/construction_mobile_command.gd")
const AuthorizerScript = preload("res://scripts/construction/mobile/construction_mobile_command_authorizer.gd")

var _profile_store
var _actor_id: String = ""
var _actor_capabilities: Array = []
var _configured: bool = false


func setup(profile_store, actor_id: String, actor_capabilities: Array) -> Dictionary:
	if profile_store == null or not profile_store.has_method("get_profile"):
		return _failure("CONSTRUCTION_MOBILE_AGENT_PROFILE_STORE_REQUIRED")
	if actor_id.strip_edges().is_empty():
		return _failure("CONSTRUCTION_MOBILE_AGENT_ID_REQUIRED")
	_profile_store = profile_store
	_actor_id = actor_id
	_actor_capabilities = actor_capabilities.duplicate(true)
	_configured = true
	return _success()


func issue_command(
	command_id: String,
	construct_id: String,
	action_kind: String,
	parameters: Dictionary = {}
) -> Dictionary:
	if not _configured:
		return _failure("CONSTRUCTION_MOBILE_AGENT_NOT_CONFIGURED")
	var profile: Dictionary = _profile_store.get_profile(construct_id)
	if profile.is_empty():
		return _failure("CONSTRUCTION_MOBILE_PROFILE_NOT_FOUND")
	var command: Dictionary = CommandScript.create(
		command_id,
		construct_id,
		action_kind,
		_actor_capabilities,
		parameters,
		String(profile["checksum"])
	)
	var authorized: Dictionary = AuthorizerScript.authorize(command, profile)
	if not bool(authorized.get("success", false)):
		return authorized
	authorized["actor_id"] = _actor_id
	authorized["command"] = command
	return authorized


func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result


func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": code}

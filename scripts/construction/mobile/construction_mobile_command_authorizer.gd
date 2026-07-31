extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ProfileScript = preload("res://scripts/construction/mobile/construction_mobile_profile.gd")
const CommandScript = preload("res://scripts/construction/mobile/construction_mobile_command.gd")


static func authorize(command: Dictionary, profile: Dictionary) -> Dictionary:
	var command_validation: Dictionary = CommandScript.validate(command)
	if not bool(command_validation.get("success", false)):
		return command_validation
	var profile_validation: Dictionary = ProfileScript.validate(profile)
	if not bool(profile_validation.get("success", false)):
		return profile_validation
	if String(command["construct_id"]) != String(profile["construct_id"]):
		return _failure("CONSTRUCTION_MOBILE_COMMAND_CONSTRUCT_MISMATCH")
	if String(command["expected_profile_checksum"]) != String(profile["checksum"]):
		return _failure("CONSTRUCTION_MOBILE_COMMAND_PROFILE_PRECONDITION_MISMATCH")
	var actor_set: Dictionary = {}
	for raw in command["actor_capabilities"]:
		actor_set[String(raw)] = true
	var candidates: Array = []
	for raw in profile["affordances"]:
		var affordance: Dictionary = raw
		if String(affordance["action_kind"]) != String(command["action_kind"]):
			continue
		if not _requirements_satisfied(Array(affordance["actor_requirements"]), actor_set):
			continue
		candidates.append(Dictionary(affordance).duplicate(true))
	candidates.sort_custom(func(left, right):
		if int(left["priority"]) != int(right["priority"]):
			return int(left["priority"]) > int(right["priority"])
		return String(left["affordance_id"]) < String(right["affordance_id"])
	)
	if candidates.is_empty():
		return _failure("CONSTRUCTION_MOBILE_COMMAND_NOT_AUTHORIZED")
	var selected: Dictionary = candidates[0]
	var resolved_parameters: Dictionary = Dictionary(selected["parameters"]).duplicate(true)
	for key in command["parameters"].keys():
		resolved_parameters[key] = command["parameters"][key]
	if not bool(UtilsScript.canonicalize(resolved_parameters).get("success", false)):
		return _failure("CONSTRUCTION_MOBILE_COMMAND_RESOLVED_PARAMETERS_NOT_JSON_SAFE")
	return _success({
		"command_id": String(command["command_id"]),
		"command_checksum": String(command["checksum"]),
		"profile_checksum": String(profile["checksum"]),
		"mobility_state": String(profile["mobility_state"]),
		"affordance": selected,
		"resolved_parameters": resolved_parameters,
	})


static func _requirements_satisfied(requirements: Array, actor_set: Dictionary) -> bool:
	for raw in requirements:
		if not actor_set.has(String(raw)):
			return false
	return true


static func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}

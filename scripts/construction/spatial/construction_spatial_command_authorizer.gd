extends RefCounted

const CommandScript = preload("res://scripts/construction/spatial/construction_spatial_command.gd")
const ProfileScript = preload("res://scripts/construction/spatial/construction_spatial_profile.gd")

static func authorize(command: Dictionary, profile: Dictionary) -> Dictionary:
	var command_validation := CommandScript.validate(command)
	if not bool(command_validation.get("success", false)):
		return command_validation
	var profile_validation := ProfileScript.validate(profile)
	if not bool(profile_validation.get("success", false)):
		return profile_validation
	if String(command["construct_id"]) != String(profile["construct_id"]):
		return _failure("CONSTRUCTION_SPATIAL_COMMAND_CONSTRUCT_MISMATCH")
	if String(command["expected_profile_checksum"]) != String(profile["checksum"]):
		return _failure("CONSTRUCTION_SPATIAL_COMMAND_PROFILE_PRECONDITION_MISMATCH")
	var matches: Array = []
	for affordance in profile["affordances"]:
		if String(affordance["action_kind"]) == String(command["action_kind"]):
			matches.append(affordance)
	if matches.is_empty():
		return _failure("CONSTRUCTION_SPATIAL_COMMAND_ACTION_UNAVAILABLE")
	matches.sort_custom(func(left, right): return int(left["priority"]) > int(right["priority"]) if int(left["priority"]) != int(right["priority"]) else String(left["affordance_id"]) < String(right["affordance_id"]))
	var actor: Dictionary = {}
	for raw in command["actor_capabilities"]:
		actor[String(raw)] = true
	for affordance in matches:
		var authorized := true
		for requirement in affordance["actor_requirements"]:
			if not actor.has(String(requirement)):
				authorized = false
				break
		if authorized:
			var resolved_parameters: Dictionary = Dictionary(affordance["parameters"]).duplicate(true)
			for key in command["parameters"]:
				resolved_parameters[key] = command["parameters"][key]
			return _success({"command": command.duplicate(true), "profile": profile.duplicate(true), "affordance": Dictionary(affordance).duplicate(true), "resolved_parameters": resolved_parameters})
	return _failure("CONSTRUCTION_SPATIAL_COMMAND_NOT_AUTHORIZED")

static func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result
static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}

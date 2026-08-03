extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const QueryScript = preload("res://scripts/construction/behavior/construction_affordance_query.gd")
const ProfileScript = preload("res://scripts/construction/behavior/construction_behavior_profile.gd")


static func resolve(query: Dictionary, profiles: Array) -> Dictionary:
	var query_validation: Dictionary = QueryScript.validate(query)
	if not bool(query_validation.get("success", false)):
		return query_validation
	var action_set: Dictionary = _set_from_array(query["action_kinds"])
	var actor_set: Dictionary = _set_from_array(query["actor_capabilities"])
	var construct_set: Dictionary = _set_from_array(query["construct_ids"])
	var candidates: Array = []
	for raw in profiles:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("INVALID_CONSTRUCTION_AFFORDANCE_PROFILE_INPUT")
		var profile: Dictionary = raw
		var profile_validation: Dictionary = ProfileScript.validate(profile)
		if not bool(profile_validation.get("success", false)):
			return profile_validation
		if not bool(profile["operational"]):
			continue
		var construct_id: String = String(profile["construct_id"])
		if not construct_set.is_empty() and not construct_set.has(construct_id):
			continue
		var capability_by_id: Dictionary = {}
		for capability in profile["capabilities"]:
			capability_by_id[String(capability["capability_id"])] = capability
		for affordance in profile["affordances"]:
			if not action_set.has(String(affordance["action_kind"])):
				continue
			if not _requirements_satisfied(Array(affordance["actor_requirements"]), actor_set):
				continue
			if bool(query["require_port_target"]) and String(affordance["target_port_id"]).is_empty():
				continue
			if not _properties_match(Dictionary(affordance["parameters"]), query):
				continue
			candidates.append({
				"construct_id": construct_id,
				"profile_checksum": String(profile["checksum"]),
				"construct_checksum": String(profile["construct_checksum"]),
				"capability": Dictionary(capability_by_id[String(affordance["capability_id"])]).duplicate(true),
				"affordance": Dictionary(affordance).duplicate(true),
			})
	candidates.sort_custom(func(left, right):
		var left_priority: int = int(left["affordance"]["priority"])
		var right_priority: int = int(right["affordance"]["priority"])
		if left_priority != right_priority:
			return left_priority > right_priority
		if String(left["construct_id"]) != String(right["construct_id"]):
			return String(left["construct_id"]) < String(right["construct_id"])
		return String(left["affordance"]["affordance_id"]) < String(right["affordance"]["affordance_id"])
	)
	if candidates.size() > int(query["limit"]):
		candidates.resize(int(query["limit"]))
	return _success({
		"query_id": String(query["query_id"]),
		"query_checksum": String(query["checksum"]),
		"candidate_count": candidates.size(),
		"candidates": candidates,
	})


static func _requirements_satisfied(requirements: Array, actor_set: Dictionary) -> bool:
	for raw in requirements:
		if not actor_set.has(String(raw)):
			return false
	return true


static func _properties_match(properties: Dictionary, query: Dictionary) -> bool:
	for raw_key in query["minimum_properties"].keys():
		var key: String = String(raw_key)
		if not properties.has(key) or typeof(properties[key]) not in [TYPE_INT, TYPE_FLOAT]:
			return false
		if float(properties[key]) < float(query["minimum_properties"][key]):
			return false
	for raw_key in query["exact_properties"].keys():
		var key: String = String(raw_key)
		if not properties.has(key):
			return false
		if UtilsScript.canonical_json(properties[key]) != UtilsScript.canonical_json(query["exact_properties"][key]):
			return false
	return true


static func _set_from_array(values: Array) -> Dictionary:
	var result: Dictionary = {}
	for value in values:
		result[String(value)] = true
	return result


static func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}

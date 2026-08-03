extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.construction_affordance_descriptor.v1"
const FIELDS: Array[String] = [
	"schema",
	"affordance_id",
	"action_kind",
	"capability_id",
	"target_part_id",
	"target_port_id",
	"actor_requirements",
	"parameters",
	"priority",
	"checksum",
]


static func create(
	affordance_id: String,
	action_kind: String,
	capability_id: String,
	target_part_id: String,
	target_port_id: String = "",
	actor_requirements: Array = [],
	parameters: Dictionary = {},
	priority: int = 100
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"affordance_id": affordance_id,
		"action_kind": action_kind,
		"capability_id": capability_id,
		"target_part_id": target_part_id,
		"target_port_id": target_port_id,
		"actor_requirements": _sorted_strings(actor_requirements),
		"parameters": parameters.duplicate(true),
		"priority": priority,
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_CONSTRUCTION_AFFORDANCE_DESCRIPTOR_SCHEMA")
	if not _is_path_id(String(value.get("affordance_id", "")), "affordance/"):
		return _failure("INVALID_CONSTRUCTION_AFFORDANCE_ID")
	if not _is_upper_kind(String(value.get("action_kind", ""))):
		return _failure("INVALID_CONSTRUCTION_AFFORDANCE_ACTION_KIND")
	if not _is_path_id(String(value.get("capability_id", "")), "capability/"):
		return _failure("INVALID_CONSTRUCTION_AFFORDANCE_CAPABILITY_ID")
	if not _is_path_id(String(value.get("target_part_id", "")), "part/"):
		return _failure("INVALID_CONSTRUCTION_AFFORDANCE_TARGET_PART")
	var target_port_id: String = String(value.get("target_port_id", ""))
	if not target_port_id.is_empty() and not _is_path_id(target_port_id, "port/"):
		return _failure("INVALID_CONSTRUCTION_AFFORDANCE_TARGET_PORT")
	var requirements: Dictionary = _validate_actor_requirements(value.get("actor_requirements"))
	if not bool(requirements.get("success", false)):
		return requirements
	if typeof(value.get("parameters")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value["parameters"]).get("success", false)):
		return _failure("INVALID_CONSTRUCTION_AFFORDANCE_PARAMETERS")
	if not UtilsScript.is_json_integer(value.get("priority")) or int(value["priority"]) < 0 or int(value["priority"]) > 1000:
		return _failure("INVALID_CONSTRUCTION_AFFORDANCE_PRIORITY")
	if typeof(value.get("checksum")) != TYPE_STRING or String(value["checksum"]) != compute_checksum(value):
		return _failure("CONSTRUCTION_AFFORDANCE_DESCRIPTOR_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)):
		return _failure("CONSTRUCTION_AFFORDANCE_DESCRIPTOR_NOT_JSON_SAFE")
	return _success()


static func compute_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)


static func _validate_actor_requirements(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _failure("INVALID_CONSTRUCTION_AFFORDANCE_ACTOR_REQUIREMENTS")
	var seen: Dictionary = {}
	var previous: String = ""
	for raw in value:
		if typeof(raw) != TYPE_STRING:
			return _failure("INVALID_CONSTRUCTION_AFFORDANCE_ACTOR_REQUIREMENT")
		var requirement: String = String(raw)
		if not _is_upper_kind(requirement) or seen.has(requirement):
			return _failure("INVALID_CONSTRUCTION_AFFORDANCE_ACTOR_REQUIREMENT")
		if not previous.is_empty() and requirement < previous:
			return _failure("CONSTRUCTION_AFFORDANCE_ACTOR_REQUIREMENTS_NOT_SORTED")
		seen[requirement] = true
		previous = requirement
	return _success()


static func _sorted_strings(values: Array) -> Array:
	var result: Array = []
	for value in values:
		result.append(String(value))
	result.sort()
	return result


static func _is_path_id(value: String, prefix: String) -> bool:
	if not value.begins_with(prefix) or value.length() <= prefix.length() or value != value.to_lower() or value.contains("//"):
		return false
	for segment in value.split("/", true):
		if segment.is_empty():
			return false
		for character in segment:
			if not String(character) in "abcdefghijklmnopqrstuvwxyz0123456789-_":
				return false
	return true


static func _is_upper_kind(value: String) -> bool:
	if value.is_empty() or value != value.to_upper():
		return false
	for character in value:
		if not String(character) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_":
			return false
	return true


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "message": "", "details": details.duplicate(true)}


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}

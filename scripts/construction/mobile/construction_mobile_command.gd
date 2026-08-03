extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.construction_mobile_command.v1"
const FIELDS: Array[String] = [
	"schema",
	"command_id",
	"construct_id",
	"action_kind",
	"actor_capabilities",
	"parameters",
	"expected_profile_checksum",
	"checksum",
]


static func create(
	command_id: String,
	construct_id: String,
	action_kind: String,
	actor_capabilities: Array,
	parameters: Dictionary,
	expected_profile_checksum: String
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"command_id": command_id,
		"construct_id": construct_id,
		"action_kind": action_kind,
		"actor_capabilities": _sorted_strings(actor_capabilities),
		"parameters": parameters.duplicate(true),
		"expected_profile_checksum": expected_profile_checksum,
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_CONSTRUCTION_MOBILE_COMMAND_SCHEMA")
	if not _is_path_id(String(value.get("command_id", "")), "mobile-command/"):
		return _failure("INVALID_CONSTRUCTION_MOBILE_COMMAND_ID")
	if not _is_path_id(String(value.get("construct_id", "")), "construct/"):
		return _failure("INVALID_CONSTRUCTION_MOBILE_COMMAND_CONSTRUCT_ID")
	if not _is_upper_kind(String(value.get("action_kind", ""))):
		return _failure("INVALID_CONSTRUCTION_MOBILE_COMMAND_ACTION_KIND")
	var actor_validation: Dictionary = _validate_sorted_upper(value.get("actor_capabilities"))
	if not bool(actor_validation.get("success", false)):
		return actor_validation
	if typeof(value.get("parameters")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value["parameters"]).get("success", false)):
		return _failure("INVALID_CONSTRUCTION_MOBILE_COMMAND_PARAMETERS")
	if not _is_lower_hex_64(String(value.get("expected_profile_checksum", ""))):
		return _failure("INVALID_CONSTRUCTION_MOBILE_COMMAND_PROFILE_CHECKSUM")
	if typeof(value.get("checksum")) != TYPE_STRING or String(value["checksum"]) != compute_checksum(value):
		return _failure("CONSTRUCTION_MOBILE_COMMAND_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)):
		return _failure("CONSTRUCTION_MOBILE_COMMAND_NOT_JSON_SAFE")
	return _success()


static func compute_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)


static func _validate_sorted_upper(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _failure("INVALID_CONSTRUCTION_MOBILE_COMMAND_ACTOR_CAPABILITIES")
	var previous: String = ""
	var seen: Dictionary = {}
	for raw in value:
		if typeof(raw) != TYPE_STRING:
			return _failure("INVALID_CONSTRUCTION_MOBILE_COMMAND_ACTOR_CAPABILITY")
		var item: String = String(raw)
		if not _is_upper_kind(item) or seen.has(item):
			return _failure("INVALID_CONSTRUCTION_MOBILE_COMMAND_ACTOR_CAPABILITY")
		if not previous.is_empty() and item < previous:
			return _failure("CONSTRUCTION_MOBILE_COMMAND_ACTOR_CAPABILITIES_NOT_SORTED")
		seen[item] = true
		previous = item
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


static func _is_lower_hex_64(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for character in value:
		if not String(character) in "0123456789abcdef":
			return false
	return true


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "message": "", "details": details.duplicate(true)}


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}

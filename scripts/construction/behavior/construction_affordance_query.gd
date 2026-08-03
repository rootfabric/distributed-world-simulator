extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.construction_affordance_query.v1"
const FIELDS: Array[String] = [
	"schema",
	"query_id",
	"action_kinds",
	"actor_capabilities",
	"construct_ids",
	"minimum_properties",
	"exact_properties",
	"require_port_target",
	"limit",
	"checksum",
]


static func create(
	query_id: String,
	action_kinds: Array,
	actor_capabilities: Array,
	construct_ids: Array = [],
	minimum_properties: Dictionary = {},
	exact_properties: Dictionary = {},
	require_port_target: bool = false,
	limit: int = 16
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"query_id": query_id,
		"action_kinds": _sorted_strings(action_kinds),
		"actor_capabilities": _sorted_strings(actor_capabilities),
		"construct_ids": _sorted_strings(construct_ids),
		"minimum_properties": minimum_properties.duplicate(true),
		"exact_properties": exact_properties.duplicate(true),
		"require_port_target": require_port_target,
		"limit": limit,
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_CONSTRUCTION_AFFORDANCE_QUERY_SCHEMA")
	if not _is_path_id(String(value.get("query_id", "")), "affordance-query/"):
		return _failure("INVALID_CONSTRUCTION_AFFORDANCE_QUERY_ID")
	var actions: Dictionary = _validate_sorted_upper(value.get("action_kinds"), false)
	if not bool(actions.get("success", false)):
		return actions
	if Array(value["action_kinds"]).is_empty():
		return _failure("CONSTRUCTION_AFFORDANCE_QUERY_ACTION_REQUIRED")
	var actor: Dictionary = _validate_sorted_upper(value.get("actor_capabilities"), true)
	if not bool(actor.get("success", false)):
		return actor
	var constructs: Dictionary = _validate_sorted_paths(value.get("construct_ids"), "construct/")
	if not bool(constructs.get("success", false)):
		return constructs
	if typeof(value.get("minimum_properties")) != TYPE_DICTIONARY:
		return _failure("INVALID_CONSTRUCTION_AFFORDANCE_MINIMUM_PROPERTIES")
	for key in value["minimum_properties"].keys():
		var threshold = value["minimum_properties"][key]
		if typeof(key) != TYPE_STRING or String(key).is_empty() or typeof(threshold) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(threshold)):
			return _failure("INVALID_CONSTRUCTION_AFFORDANCE_MINIMUM_PROPERTY")
	if typeof(value.get("exact_properties")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value["exact_properties"]).get("success", false)):
		return _failure("INVALID_CONSTRUCTION_AFFORDANCE_EXACT_PROPERTIES")
	if typeof(value.get("require_port_target")) != TYPE_BOOL:
		return _failure("INVALID_CONSTRUCTION_AFFORDANCE_PORT_REQUIREMENT")
	if not UtilsScript.is_json_integer(value.get("limit")) or int(value["limit"]) < 1 or int(value["limit"]) > 1000:
		return _failure("INVALID_CONSTRUCTION_AFFORDANCE_QUERY_LIMIT")
	if typeof(value.get("checksum")) != TYPE_STRING or String(value["checksum"]) != compute_checksum(value):
		return _failure("CONSTRUCTION_AFFORDANCE_QUERY_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)):
		return _failure("CONSTRUCTION_AFFORDANCE_QUERY_NOT_JSON_SAFE")
	return _success()


static func compute_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)


static func _validate_sorted_upper(value, allow_empty: bool) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _failure("INVALID_CONSTRUCTION_AFFORDANCE_QUERY_UPPER_COLLECTION")
	if not allow_empty and Array(value).is_empty():
		return _failure("CONSTRUCTION_AFFORDANCE_QUERY_UPPER_COLLECTION_REQUIRED")
	var seen: Dictionary = {}
	var previous: String = ""
	for raw in value:
		if typeof(raw) != TYPE_STRING:
			return _failure("INVALID_CONSTRUCTION_AFFORDANCE_QUERY_UPPER_VALUE")
		var item: String = String(raw)
		if not _is_upper_kind(item) or seen.has(item):
			return _failure("INVALID_CONSTRUCTION_AFFORDANCE_QUERY_UPPER_VALUE")
		if not previous.is_empty() and item < previous:
			return _failure("CONSTRUCTION_AFFORDANCE_QUERY_VALUES_NOT_SORTED")
		seen[item] = true
		previous = item
	return _success()


static func _validate_sorted_paths(value, prefix: String) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _failure("INVALID_CONSTRUCTION_AFFORDANCE_QUERY_PATH_COLLECTION")
	var seen: Dictionary = {}
	var previous: String = ""
	for raw in value:
		if typeof(raw) != TYPE_STRING:
			return _failure("INVALID_CONSTRUCTION_AFFORDANCE_QUERY_PATH")
		var item: String = String(raw)
		if not _is_path_id(item, prefix) or seen.has(item):
			return _failure("INVALID_CONSTRUCTION_AFFORDANCE_QUERY_PATH")
		if not previous.is_empty() and item < previous:
			return _failure("CONSTRUCTION_AFFORDANCE_QUERY_PATHS_NOT_SORTED")
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


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "message": "", "details": details.duplicate(true)}


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}

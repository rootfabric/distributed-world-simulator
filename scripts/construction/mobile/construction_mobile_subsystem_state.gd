extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const DefinitionScript = preload("res://scripts/construction/mobile/construction_mobile_subsystem_definition.gd")

const SCHEMA: String = "planet_simulator.construction_mobile_subsystem_state.v1"
const FIELDS: Array[String] = [
	"schema",
	"subsystem_id",
	"subsystem_kind",
	"status",
	"provider_part_ids",
	"online_provider_part_ids",
	"degraded_provider_part_ids",
	"offline_provider_part_ids",
	"dependency_subsystem_ids",
	"properties",
	"diagnostics",
	"checksum",
]
const VALID_STATUSES: Array[String] = ["ONLINE", "DEGRADED", "OFFLINE"]


static func create(
	definition: Dictionary,
	status: String,
	online_provider_part_ids: Array,
	degraded_provider_part_ids: Array,
	offline_provider_part_ids: Array,
	properties: Dictionary,
	diagnostics: Dictionary = {}
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"subsystem_id": String(definition.get("subsystem_id", "")),
		"subsystem_kind": String(definition.get("subsystem_kind", "")),
		"status": status,
		"provider_part_ids": Array(definition.get("provider_part_ids", [])).duplicate(true),
		"online_provider_part_ids": _sorted_strings(online_provider_part_ids),
		"degraded_provider_part_ids": _sorted_strings(degraded_provider_part_ids),
		"offline_provider_part_ids": _sorted_strings(offline_provider_part_ids),
		"dependency_subsystem_ids": Array(definition.get("dependency_subsystem_ids", [])).duplicate(true),
		"properties": properties.duplicate(true),
		"diagnostics": diagnostics.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_CONSTRUCTION_MOBILE_SUBSYSTEM_STATE_SCHEMA")
	if not _is_path_id(String(value.get("subsystem_id", "")), "mobile-subsystem/"):
		return _failure("INVALID_CONSTRUCTION_MOBILE_SUBSYSTEM_STATE_ID")
	if typeof(value.get("subsystem_kind")) != TYPE_STRING or not DefinitionScript.VALID_KINDS.has(String(value["subsystem_kind"])):
		return _failure("INVALID_CONSTRUCTION_MOBILE_SUBSYSTEM_STATE_KIND")
	if typeof(value.get("status")) != TYPE_STRING or not VALID_STATUSES.has(String(value["status"])):
		return _failure("INVALID_CONSTRUCTION_MOBILE_SUBSYSTEM_STATUS")
	for field in ["provider_part_ids", "online_provider_part_ids", "degraded_provider_part_ids", "offline_provider_part_ids"]:
		var validation: Dictionary = _validate_sorted_paths(value.get(field), "part/", field != "provider_part_ids")
		if not bool(validation.get("success", false)):
			return validation
	var dependencies: Dictionary = _validate_sorted_paths(value.get("dependency_subsystem_ids"), "mobile-subsystem/", true)
	if not bool(dependencies.get("success", false)):
		return dependencies
	var providers: Dictionary = _string_set(Array(value["provider_part_ids"]))
	var classified: Dictionary = {}
	for field in ["online_provider_part_ids", "degraded_provider_part_ids", "offline_provider_part_ids"]:
		for raw in value[field]:
			var part_id: String = String(raw)
			if not providers.has(part_id) or classified.has(part_id):
				return _failure("CONSTRUCTION_MOBILE_SUBSYSTEM_PROVIDER_PARTITION_MISMATCH")
			classified[part_id] = true
	if classified.size() != providers.size():
		return _failure("CONSTRUCTION_MOBILE_SUBSYSTEM_PROVIDER_PARTITION_MISMATCH")
	if typeof(value.get("properties")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value["properties"]).get("success", false)):
		return _failure("INVALID_CONSTRUCTION_MOBILE_SUBSYSTEM_STATE_PROPERTIES")
	if typeof(value.get("diagnostics")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value["diagnostics"]).get("success", false)):
		return _failure("INVALID_CONSTRUCTION_MOBILE_SUBSYSTEM_DIAGNOSTICS")
	if typeof(value.get("checksum")) != TYPE_STRING or String(value["checksum"]) != compute_checksum(value):
		return _failure("CONSTRUCTION_MOBILE_SUBSYSTEM_STATE_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)):
		return _failure("CONSTRUCTION_MOBILE_SUBSYSTEM_STATE_NOT_JSON_SAFE")
	return _success()


static func compute_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)


static func _string_set(values: Array) -> Dictionary:
	var result: Dictionary = {}
	for value in values:
		result[String(value)] = true
	return result


static func _validate_sorted_paths(value, prefix: String, allow_empty: bool) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _failure("INVALID_CONSTRUCTION_MOBILE_SUBSYSTEM_STATE_REFERENCE_COLLECTION")
	if not allow_empty and Array(value).is_empty():
		return _failure("CONSTRUCTION_MOBILE_SUBSYSTEM_STATE_PROVIDER_REQUIRED")
	var previous: String = ""
	var seen: Dictionary = {}
	for raw in value:
		if typeof(raw) != TYPE_STRING:
			return _failure("INVALID_CONSTRUCTION_MOBILE_SUBSYSTEM_STATE_REFERENCE")
		var identifier: String = String(raw)
		if not _is_path_id(identifier, prefix) or seen.has(identifier):
			return _failure("INVALID_CONSTRUCTION_MOBILE_SUBSYSTEM_STATE_REFERENCE")
		if not previous.is_empty() and identifier < previous:
			return _failure("CONSTRUCTION_MOBILE_SUBSYSTEM_STATE_REFERENCES_NOT_SORTED")
		seen[identifier] = true
		previous = identifier
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


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "message": "", "details": details.duplicate(true)}


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}

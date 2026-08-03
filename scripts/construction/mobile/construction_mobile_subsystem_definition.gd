extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.construction_mobile_subsystem_definition.v1"
const FIELDS: Array[String] = [
	"schema",
	"subsystem_id",
	"subsystem_kind",
	"provider_part_ids",
	"required_bond_ids",
	"dependency_subsystem_ids",
	"minimum_online_providers",
	"properties",
	"checksum",
]
const VALID_KINDS: Array[String] = ["POWER", "CONTROL", "DRIVE", "SENSOR", "COMMUNICATION"]


static func create(
	subsystem_id: String,
	subsystem_kind: String,
	provider_part_ids: Array,
	required_bond_ids: Array = [],
	dependency_subsystem_ids: Array = [],
	minimum_online_providers: int = 1,
	properties: Dictionary = {}
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"subsystem_id": subsystem_id,
		"subsystem_kind": subsystem_kind,
		"provider_part_ids": _sorted_strings(provider_part_ids),
		"required_bond_ids": _sorted_strings(required_bond_ids),
		"dependency_subsystem_ids": _sorted_strings(dependency_subsystem_ids),
		"minimum_online_providers": minimum_online_providers,
		"properties": properties.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_CONSTRUCTION_MOBILE_SUBSYSTEM_DEFINITION_SCHEMA")
	if not _is_path_id(String(value.get("subsystem_id", "")), "mobile-subsystem/"):
		return _failure("INVALID_CONSTRUCTION_MOBILE_SUBSYSTEM_ID")
	if typeof(value.get("subsystem_kind")) != TYPE_STRING or not VALID_KINDS.has(String(value["subsystem_kind"])):
		return _failure("INVALID_CONSTRUCTION_MOBILE_SUBSYSTEM_KIND")
	var providers: Dictionary = _validate_sorted_paths(value.get("provider_part_ids"), "part/", false)
	if not bool(providers.get("success", false)):
		return providers
	var bonds: Dictionary = _validate_sorted_paths(value.get("required_bond_ids"), "bond/", true)
	if not bool(bonds.get("success", false)):
		return bonds
	var dependencies: Dictionary = _validate_sorted_paths(value.get("dependency_subsystem_ids"), "mobile-subsystem/", true)
	if not bool(dependencies.get("success", false)):
		return dependencies
	if Array(value["dependency_subsystem_ids"]).has(String(value["subsystem_id"])):
		return _failure("CONSTRUCTION_MOBILE_SUBSYSTEM_SELF_DEPENDENCY")
	if not UtilsScript.is_json_integer(value.get("minimum_online_providers")):
		return _failure("INVALID_CONSTRUCTION_MOBILE_MINIMUM_ONLINE_PROVIDERS")
	var minimum: int = int(value["minimum_online_providers"])
	if minimum < 1 or minimum > Array(value["provider_part_ids"]).size():
		return _failure("INVALID_CONSTRUCTION_MOBILE_MINIMUM_ONLINE_PROVIDERS")
	if typeof(value.get("properties")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value["properties"]).get("success", false)):
		return _failure("INVALID_CONSTRUCTION_MOBILE_SUBSYSTEM_PROPERTIES")
	if typeof(value.get("checksum")) != TYPE_STRING or String(value["checksum"]) != compute_checksum(value):
		return _failure("CONSTRUCTION_MOBILE_SUBSYSTEM_DEFINITION_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)):
		return _failure("CONSTRUCTION_MOBILE_SUBSYSTEM_DEFINITION_NOT_JSON_SAFE")
	return _success()


static func compute_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)


static func _validate_sorted_paths(value, prefix: String, allow_empty: bool) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _failure("INVALID_CONSTRUCTION_MOBILE_SUBSYSTEM_REFERENCE_COLLECTION")
	if not allow_empty and Array(value).is_empty():
		return _failure("CONSTRUCTION_MOBILE_SUBSYSTEM_PROVIDER_REQUIRED")
	var previous: String = ""
	var seen: Dictionary = {}
	for raw in value:
		if typeof(raw) != TYPE_STRING:
			return _failure("INVALID_CONSTRUCTION_MOBILE_SUBSYSTEM_REFERENCE")
		var identifier: String = String(raw)
		if not _is_path_id(identifier, prefix) or seen.has(identifier):
			return _failure("INVALID_CONSTRUCTION_MOBILE_SUBSYSTEM_REFERENCE")
		if not previous.is_empty() and identifier < previous:
			return _failure("CONSTRUCTION_MOBILE_SUBSYSTEM_REFERENCES_NOT_SORTED")
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

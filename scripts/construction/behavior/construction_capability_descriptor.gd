extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.construction_capability_descriptor.v1"
const FIELDS: Array[String] = [
	"schema",
	"capability_id",
	"capability_kind",
	"provider_part_ids",
	"source_port_ids",
	"properties",
	"checksum",
]


static func create(
	capability_id: String,
	capability_kind: String,
	provider_part_ids: Array,
	source_port_ids: Array = [],
	properties: Dictionary = {}
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"capability_id": capability_id,
		"capability_kind": capability_kind,
		"provider_part_ids": _sorted_strings(provider_part_ids),
		"source_port_ids": _sorted_strings(source_port_ids),
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
		return _failure("UNSUPPORTED_CONSTRUCTION_CAPABILITY_DESCRIPTOR_SCHEMA")
	if not _is_path_id(String(value.get("capability_id", "")), "capability/"):
		return _failure("INVALID_CONSTRUCTION_CAPABILITY_ID")
	if not _is_upper_kind(String(value.get("capability_kind", ""))):
		return _failure("INVALID_CONSTRUCTION_CAPABILITY_KIND")
	var providers: Dictionary = _validate_sorted_ids(value.get("provider_part_ids"), "part/")
	if not bool(providers.get("success", false)):
		return providers
	if Array(value["provider_part_ids"]).is_empty():
		return _failure("CONSTRUCTION_CAPABILITY_PROVIDER_REQUIRED")
	var ports: Dictionary = _validate_sorted_ids(value.get("source_port_ids"), "port/")
	if not bool(ports.get("success", false)):
		return ports
	if typeof(value.get("properties")) != TYPE_DICTIONARY:
		return _failure("INVALID_CONSTRUCTION_CAPABILITY_PROPERTIES")
	if not bool(UtilsScript.canonicalize(value["properties"]).get("success", false)):
		return _failure("CONSTRUCTION_CAPABILITY_PROPERTIES_NOT_JSON_SAFE")
	if typeof(value.get("checksum")) != TYPE_STRING or String(value["checksum"]) != compute_checksum(value):
		return _failure("CONSTRUCTION_CAPABILITY_DESCRIPTOR_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)):
		return _failure("CONSTRUCTION_CAPABILITY_DESCRIPTOR_NOT_JSON_SAFE")
	return _success()


static func compute_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)


static func _validate_sorted_ids(value, prefix: String) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _failure("INVALID_CONSTRUCTION_CAPABILITY_ID_COLLECTION")
	var previous: String = ""
	var seen: Dictionary = {}
	for raw in value:
		if typeof(raw) != TYPE_STRING:
			return _failure("INVALID_CONSTRUCTION_CAPABILITY_REFERENCE_ID")
		var identifier: String = String(raw)
		if not _is_path_id(identifier, prefix) or seen.has(identifier):
			return _failure("INVALID_CONSTRUCTION_CAPABILITY_REFERENCE_ID")
		if not previous.is_empty() and identifier < previous:
			return _failure("CONSTRUCTION_CAPABILITY_REFERENCE_IDS_NOT_SORTED")
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

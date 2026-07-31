extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.composite_exposed_port.v1"
const FIELDS: Array[String] = ["schema", "port_id", "slot_id", "port_kind", "local_position_m", "metadata"]


static func create(
	port_id: String,
	slot_id: String,
	port_kind: String,
	local_position_m: Array,
	metadata: Dictionary = {}
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"port_id": port_id,
		"slot_id": slot_id,
		"port_kind": port_kind,
		"local_position_m": local_position_m.duplicate(true),
		"metadata": metadata.duplicate(true),
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_COMPOSITE_EXPOSED_PORT_SCHEMA")
	if not _is_path_id(String(value.get("port_id", "")), "port/"):
		return _failure("INVALID_COMPOSITE_EXPOSED_PORT_ID")
	if not _is_path_id(String(value.get("slot_id", "")), "slot/"):
		return _failure("INVALID_COMPOSITE_EXPOSED_PORT_SLOT")
	if not _is_upper_kind(String(value.get("port_kind", ""))):
		return _failure("INVALID_COMPOSITE_EXPOSED_PORT_KIND")
	if typeof(value.get("local_position_m")) != TYPE_ARRAY or value["local_position_m"].size() != 3:
		return _failure("INVALID_COMPOSITE_EXPOSED_PORT_POSITION")
	for component in value["local_position_m"]:
		if typeof(component) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(component)):
			return _failure("INVALID_COMPOSITE_EXPOSED_PORT_POSITION")
	if typeof(value.get("metadata")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value["metadata"]).get("success", false)):
		return _failure("INVALID_COMPOSITE_EXPOSED_PORT_METADATA")
	if not bool(UtilsScript.canonicalize(value).get("success", false)):
		return _failure("COMPOSITE_EXPOSED_PORT_NOT_JSON_SAFE")
	return _success()


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


static func _success() -> Dictionary:
	return {"success": true, "error_code": "", "message": ""}


static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": code}

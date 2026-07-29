extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const BusUtilsScript = preload("res://scripts/network/bus/message_bus_contract_utils.gd")

const SCHEMA := "planet_simulator.bulk_object_descriptor.v1"
const PROTOCOL_VERSION := 1
const FIELDS: Array[String] = ["schema", "protocol_version", "object_id", "content_schema", "content_hash", "size_bytes"]


static func create(object_id: String, content_schema: String, content_hash: String, size_bytes: int) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"object_id": object_id,
		"content_schema": content_schema,
		"content_hash": content_hash,
		"size_bytes": size_bytes,
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA or not NetworkUtilsScript.is_json_integer(value.get("protocol_version")) or int(value["protocol_version"]) != PROTOCOL_VERSION:
		return NetworkUtilsScript.validation_failure("INVALID_SCHEMA", "Bulk object descriptor schema/version mismatch")
	if not BusUtilsScript.is_canonical_id(value.get("object_id"), "object"):
		return NetworkUtilsScript.validation_failure("INVALID_OBJECT_ID", "object_id is not canonical")
	if not BusUtilsScript.is_payload_schema(value.get("content_schema")):
		return NetworkUtilsScript.validation_failure("INVALID_CONTENT_SCHEMA", "content_schema is not canonical")
	if typeof(value.get("content_hash")) != TYPE_STRING or String(value["content_hash"]).length() != 64:
		return NetworkUtilsScript.validation_failure("INVALID_CONTENT_HASH", "content_hash must be lowercase SHA-256")
	for character in String(value["content_hash"]):
		if not ((character >= "0" and character <= "9") or (character >= "a" and character <= "f")):
			return NetworkUtilsScript.validation_failure("INVALID_CONTENT_HASH", "content_hash must be lowercase SHA-256")
	if not NetworkUtilsScript.is_json_integer(value.get("size_bytes")) or int(value["size_bytes"]) < 0 or int(value["size_bytes"]) > 1073741824:
		return NetworkUtilsScript.validation_failure("INVALID_SIZE", "size_bytes is out of range")
	return NetworkUtilsScript.validation_success()

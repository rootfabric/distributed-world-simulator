extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.construction_runtime_subject_state.v1"
const FIELDS: Array[String] = [
	"schema",
	"runtime_id",
	"construct_id",
	"item_instance_id",
	"capability_id",
	"revision",
	"state",
	"checksum",
]


static func create(
	runtime_id: String,
	construct_id: String,
	item_instance_id: String,
	capability_id: String,
	revision: int,
	state: Dictionary
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"runtime_id": runtime_id,
		"construct_id": construct_id,
		"item_instance_id": item_instance_id,
		"capability_id": capability_id,
		"revision": revision,
		"state": state.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_CONSTRUCTION_RUNTIME_SUBJECT_SCHEMA")
	if not _is_path(String(value.get("runtime_id", "")), "runtime/"):
		return _failure("INVALID_CONSTRUCTION_RUNTIME_ID")
	if not _is_path(String(value.get("construct_id", "")), "construct/"):
		return _failure("INVALID_CONSTRUCTION_RUNTIME_CONSTRUCT_ID")
	if not _is_path(String(value.get("item_instance_id", "")), "item/"):
		return _failure("INVALID_CONSTRUCTION_RUNTIME_ITEM_ID")
	if not _is_path(String(value.get("capability_id", "")), "capability/"):
		return _failure("INVALID_CONSTRUCTION_RUNTIME_CAPABILITY_ID")
	if not UtilsScript.is_json_integer(value.get("revision")) or int(value["revision"]) < 0:
		return _failure("INVALID_CONSTRUCTION_RUNTIME_REVISION")
	if typeof(value.get("state")) != TYPE_DICTIONARY:
		return _failure("INVALID_CONSTRUCTION_RUNTIME_STATE")
	var canonical: Dictionary = UtilsScript.canonicalize(value["state"])
	if not bool(canonical.get("success", false)):
		return _failure("CONSTRUCTION_RUNTIME_STATE_NOT_JSON_SAFE")
	if String(value.get("checksum", "")) != compute_checksum(value):
		return _failure("CONSTRUCTION_RUNTIME_SUBJECT_CHECKSUM_MISMATCH")
	return _success()


static func compute_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)


static func _is_path(value: String, prefix: String) -> bool:
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
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}

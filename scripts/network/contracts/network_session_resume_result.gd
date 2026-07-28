extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.network_session_resume_result.v1"
const PROTOCOL_VERSION: int = 1
const FIELDS: Array[String] = [
	"schema", "protocol_version", "resume_id", "accepted", "logical_session_id",
	"transport_session_id", "operation_id", "result_revision", "server_tick", "error_code", "checksum",
]


static func create(
	resume_id: String,
	accepted: bool,
	logical_session_id: String,
	transport_session_id: String,
	operation_id: String,
	result_revision: int,
	server_tick: int,
	error_code: String = ""
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"resume_id": resume_id,
		"accepted": accepted,
		"logical_session_id": logical_session_id,
		"transport_session_id": transport_session_id,
		"operation_id": operation_id,
		"result_revision": result_revision,
		"server_tick": server_tick,
		"error_code": error_code,
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var check: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(check.get("success", false)):
		return check
	for field in ["schema", "resume_id", "logical_session_id", "transport_session_id", "operation_id", "error_code", "checksum"]:
		check = UtilsScript.require_string(value, field, field == "error_code")
		if not bool(check.get("success", false)):
			return check
	if String(value["schema"]) != SCHEMA:
		return UtilsScript.validation_failure("UNSUPPORTED_SCHEMA", "Unexpected session resume result schema")
	check = UtilsScript.require_json_integer(value, "protocol_version")
	if not bool(check.get("success", false)) or int(value["protocol_version"]) != PROTOCOL_VERSION:
		return UtilsScript.validation_failure("UNSUPPORTED_PROTOCOL", "Unsupported session resume result protocol")
	check = UtilsScript.require_boolean(value, "accepted")
	if not bool(check.get("success", false)):
		return check
	for field in ["result_revision", "server_tick"]:
		check = UtilsScript.require_json_integer(value, field)
		if not bool(check.get("success", false)):
			return check
	if int(value["result_revision"]) < -1 or int(value["server_tick"]) < 0:
		return UtilsScript.validation_failure("INVALID_RESULT_STATE", "Invalid resume result revision/tick")
	for field in ["resume_id", "logical_session_id", "transport_session_id", "operation_id"]:
		if not _is_canonical_id(String(value[field])):
			return UtilsScript.validation_failure("INVALID_IDENTIFIER", "%s is not canonical" % field)
	if bool(value["accepted"]) and not String(value["error_code"]).is_empty():
		return UtilsScript.validation_failure("INVALID_ERROR_CODE", "Accepted resume cannot contain error_code")
	if not bool(value["accepted"]) and String(value["error_code"]).is_empty():
		return UtilsScript.validation_failure("ERROR_CODE_REQUIRED", "Rejected resume requires error_code")
	if not _is_sha256(String(value["checksum"])) or String(value["checksum"]) != compute_checksum(value):
		return UtilsScript.validation_failure("CHECKSUM_MISMATCH", "Session resume result checksum mismatch")
	return UtilsScript.validation_success()


static func compute_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload.erase("checksum")
	return UtilsScript.payload_hash(payload)


static func _is_canonical_id(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges().to_lower():
		return false
	for character in value:
		if not ((character >= "a" and character <= "z") or (character >= "0" and character <= "9") or character in ["/", "_", ".", "-"]):
			return false
	return true


static func _is_sha256(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for character in value:
		if not ((character >= "a" and character <= "f") or (character >= "0" and character <= "9")):
			return false
	return true

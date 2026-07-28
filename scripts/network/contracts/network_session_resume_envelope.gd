extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const TicketScript = preload("res://scripts/network/contracts/network_resume_ticket.gd")

const SCHEMA: String = "planet_simulator.network_session_resume.v1"
const PROTOCOL_VERSION: int = 1
const FIELDS: Array[String] = [
	"schema", "protocol_version", "resume_id", "ticket", "transport_session_id",
	"operation_id", "command_fingerprint", "last_snapshot_checksum", "checksum",
]


static func create(
	resume_id: String,
	ticket: Dictionary,
	transport_session_id: String,
	operation_id: String,
	command_fingerprint: String,
	last_snapshot_checksum: String
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"resume_id": resume_id,
		"ticket": ticket.duplicate(true),
		"transport_session_id": transport_session_id,
		"operation_id": operation_id,
		"command_fingerprint": command_fingerprint,
		"last_snapshot_checksum": last_snapshot_checksum,
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var check: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(check.get("success", false)):
		return check
	for field in ["schema", "resume_id", "transport_session_id", "operation_id", "command_fingerprint", "last_snapshot_checksum", "checksum"]:
		check = UtilsScript.require_string(value, field)
		if not bool(check.get("success", false)):
			return check
	if String(value["schema"]) != SCHEMA:
		return UtilsScript.validation_failure("UNSUPPORTED_SCHEMA", "Unexpected session resume schema")
	check = UtilsScript.require_json_integer(value, "protocol_version")
	if not bool(check.get("success", false)) or int(value["protocol_version"]) != PROTOCOL_VERSION:
		return UtilsScript.validation_failure("UNSUPPORTED_PROTOCOL", "Unsupported session resume protocol")
	check = UtilsScript.require_dictionary(value, "ticket")
	if not bool(check.get("success", false)):
		return check
	check = TicketScript.validate(value["ticket"])
	if not bool(check.get("success", false)):
		return UtilsScript.validation_failure(String(check.get("error_code", "INVALID_TICKET")), "Invalid resume ticket")
	for field in ["resume_id", "transport_session_id", "operation_id"]:
		if not _is_canonical_id(String(value[field])):
			return UtilsScript.validation_failure("INVALID_IDENTIFIER", "%s is not canonical" % field)
	for field in ["command_fingerprint", "last_snapshot_checksum", "checksum"]:
		if not _is_sha256(String(value[field])):
			return UtilsScript.validation_failure("INVALID_HASH", "%s must be lowercase SHA-256 hex" % field)
	if String(value["checksum"]) != compute_checksum(value):
		return UtilsScript.validation_failure("CHECKSUM_MISMATCH", "Session resume checksum mismatch")
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

extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.network_resume_ticket.v1"
const PROTOCOL_VERSION: int = 1
const FIELDS: Array[String] = [
	"schema", "protocol_version", "ticket_id", "logical_session_id", "client_node_id",
	"issued_tick", "expires_tick", "resume_token", "checksum",
]


static func create(
	ticket_id: String,
	logical_session_id: String,
	client_node_id: String,
	issued_tick: int,
	expires_tick: int,
	resume_token: String
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"ticket_id": ticket_id,
		"logical_session_id": logical_session_id,
		"client_node_id": client_node_id,
		"issued_tick": issued_tick,
		"expires_tick": expires_tick,
		"resume_token": resume_token,
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var check: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(check.get("success", false)):
		return check
	for field in ["schema", "ticket_id", "logical_session_id", "client_node_id", "resume_token", "checksum"]:
		check = UtilsScript.require_string(value, field)
		if not bool(check.get("success", false)):
			return check
	if String(value["schema"]) != SCHEMA:
		return UtilsScript.validation_failure("UNSUPPORTED_SCHEMA", "Unexpected resume ticket schema")
	check = UtilsScript.require_json_integer(value, "protocol_version")
	if not bool(check.get("success", false)) or int(value["protocol_version"]) != PROTOCOL_VERSION:
		return UtilsScript.validation_failure("UNSUPPORTED_PROTOCOL", "Unsupported resume ticket protocol")
	for field in ["issued_tick", "expires_tick"]:
		check = UtilsScript.require_json_integer(value, field)
		if not bool(check.get("success", false)):
			return check
	if int(value["issued_tick"]) < 0 or int(value["expires_tick"]) <= int(value["issued_tick"]):
		return UtilsScript.validation_failure("INVALID_TICKET_WINDOW", "Resume ticket expiry must be after issue tick")
	for field in ["ticket_id", "logical_session_id", "client_node_id"]:
		if not _is_canonical_id(String(value[field])):
			return UtilsScript.validation_failure("INVALID_IDENTIFIER", "%s is not canonical" % field)
	if not _is_sha256(String(value["resume_token"])):
		return UtilsScript.validation_failure("INVALID_RESUME_TOKEN", "resume_token must be lowercase SHA-256 hex")
	if not _is_sha256(String(value["checksum"])) or String(value["checksum"]) != compute_checksum(value):
		return UtilsScript.validation_failure("CHECKSUM_MISMATCH", "Resume ticket checksum mismatch")
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

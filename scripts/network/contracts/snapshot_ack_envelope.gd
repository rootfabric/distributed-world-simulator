extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.snapshot_ack_envelope.v1"
const PROTOCOL_VERSION: int = 1
const FIELDS: Array[String] = [
	"schema", "protocol_version", "session_id", "snapshot_id", "entity_id",
	"snapshot_checksum", "accepted", "error_code", "client_tick", "ack_checksum",
]


static func create(
	session_id: String,
	snapshot_id: String,
	entity_id: String,
	snapshot_checksum: String,
	accepted: bool,
	error_code: String,
	client_tick: int
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"session_id": session_id,
		"snapshot_id": snapshot_id,
		"entity_id": entity_id,
		"snapshot_checksum": snapshot_checksum,
		"accepted": accepted,
		"error_code": error_code,
		"client_tick": client_tick,
		"ack_checksum": "",
	}
	value["ack_checksum"] = compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var check: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(check.get("success", false)):
		return check
	for field in ["schema", "session_id", "snapshot_id", "entity_id", "snapshot_checksum", "error_code", "ack_checksum"]:
		check = UtilsScript.require_string(value, field, field == "error_code")
		if not bool(check.get("success", false)):
			return check
	if String(value["schema"]) != SCHEMA:
		return UtilsScript.validation_failure("UNSUPPORTED_SCHEMA", "Unexpected snapshot ack schema")
	check = UtilsScript.require_json_integer(value, "protocol_version")
	if not bool(check.get("success", false)) or int(value["protocol_version"]) != PROTOCOL_VERSION:
		return UtilsScript.validation_failure("UNSUPPORTED_PROTOCOL", "Unsupported snapshot ack protocol")
	check = UtilsScript.require_boolean(value, "accepted")
	if not bool(check.get("success", false)):
		return check
	check = UtilsScript.require_json_integer(value, "client_tick")
	if not bool(check.get("success", false)) or int(value["client_tick"]) < 0:
		return UtilsScript.validation_failure("INVALID_FIELD_VALUE", "client_tick must be non-negative")
	if bool(value["accepted"]) == (not String(value["error_code"]).is_empty()):
		return UtilsScript.validation_failure("INVALID_ACK_RESULT", "accepted and error_code are inconsistent")
	if not _is_lower_hex_64(String(value["snapshot_checksum"])):
		return UtilsScript.validation_failure("INVALID_CHECKSUM", "snapshot_checksum must be lowercase SHA-256 hex")
	if not _is_lower_hex_64(String(value["ack_checksum"])):
		return UtilsScript.validation_failure("INVALID_CHECKSUM", "ack_checksum must be lowercase SHA-256 hex")
	if String(value["ack_checksum"]) != compute_checksum(value):
		return UtilsScript.validation_failure("CHECKSUM_MISMATCH", "Snapshot ack checksum mismatch")
	var safe: Dictionary = UtilsScript.canonicalize(value)
	if not bool(safe.get("success", false)):
		return UtilsScript.validation_failure("NON_CANONICAL_PAYLOAD", String(safe.get("error", "")))
	return UtilsScript.validation_success()


static func compute_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload.erase("ack_checksum")
	return UtilsScript.payload_hash(payload)


static func _is_lower_hex_64(value: String) -> bool:
	if value.length() != 64:
		return false
	for character in value:
		if not ((character >= "0" and character <= "9") or (character >= "a" and character <= "f")):
			return false
	return true

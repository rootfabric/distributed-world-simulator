extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.authority_lease.v1"
const PROTOCOL_VERSION: int = 1
const SUBJECT_TYPES: Array[String] = ["ENTITY", "REGION"]
const STATUSES: Array[String] = ["ACTIVE", "RELEASED", "EXPIRED", "REVOKED"]
const FIELDS: Array[String] = [
	"schema", "protocol_version", "lease_id", "subject_type", "subject_id",
	"owner_node_id", "authority_epoch", "issued_at_tick", "expires_at_tick",
	"renew_after_tick", "state_revision_at_acquire", "lease_token_hash", "status",
]


static func create(
	lease_id: String,
	subject_type: String,
	subject_id: String,
	owner_node_id: String,
	authority_epoch: int,
	issued_at_tick: int,
	renew_after_tick: int,
	expires_at_tick: int,
	state_revision_at_acquire: int,
	lease_token_hash: String,
	status: String = "ACTIVE"
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"lease_id": lease_id,
		"subject_type": subject_type,
		"subject_id": subject_id,
		"owner_node_id": owner_node_id,
		"authority_epoch": authority_epoch,
		"issued_at_tick": issued_at_tick,
		"expires_at_tick": expires_at_tick,
		"renew_after_tick": renew_after_tick,
		"state_revision_at_acquire": state_revision_at_acquire,
		"lease_token_hash": lease_token_hash,
		"status": status,
	}


static func validate(value: Dictionary) -> Dictionary:
	var check: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(check.get("success", false)):
		return check
	check = UtilsScript.require_string(value, "schema")
	if not bool(check.get("success", false)):
		return check
	if String(value["schema"]) != SCHEMA:
		return UtilsScript.validation_failure("UNSUPPORTED_SCHEMA", "Unexpected authority lease schema")
	check = UtilsScript.require_json_integer(value, "protocol_version")
	if not bool(check.get("success", false)) or int(value["protocol_version"]) != PROTOCOL_VERSION:
		return UtilsScript.validation_failure("UNSUPPORTED_PROTOCOL", "Unsupported protocol version")
	for field in ["lease_id", "subject_type", "subject_id", "owner_node_id", "lease_token_hash", "status"]:
		check = UtilsScript.require_string(value, field)
		if not bool(check.get("success", false)):
			return check
	if not SUBJECT_TYPES.has(String(value["subject_type"])):
		return UtilsScript.validation_failure("INVALID_SUBJECT_TYPE", "Unknown lease subject type")
	if not STATUSES.has(String(value["status"])):
		return UtilsScript.validation_failure("INVALID_STATUS", "Unknown lease status")
	for field in ["authority_epoch", "issued_at_tick", "renew_after_tick", "expires_at_tick", "state_revision_at_acquire"]:
		check = UtilsScript.require_json_integer(value, field)
		if not bool(check.get("success", false)):
			return check
	if int(value["authority_epoch"]) < 1 or int(value["state_revision_at_acquire"]) < 0:
		return UtilsScript.validation_failure("INVALID_COUNTER", "Invalid authority epoch or state revision")
	if int(value["issued_at_tick"]) < 0 or int(value["issued_at_tick"]) > int(value["renew_after_tick"]) or int(value["renew_after_tick"]) >= int(value["expires_at_tick"]):
		return UtilsScript.validation_failure("INVALID_LEASE_WINDOW", "Lease ticks must satisfy issued <= renew < expires")
	if not _is_lower_hex_64(String(value["lease_token_hash"])):
		return UtilsScript.validation_failure("INVALID_TOKEN_HASH", "lease_token_hash must be lowercase SHA-256")
	var safe: Dictionary = UtilsScript.canonicalize(value)
	if not bool(safe.get("success", false)):
		return UtilsScript.validation_failure("NON_CANONICAL_PAYLOAD", String(safe.get("error", "")))
	return UtilsScript.validation_success()


static func normalize(value: Dictionary) -> Dictionary:
	if not bool(validate(value).get("success", false)):
		return {}
	var round_trip: Dictionary = UtilsScript.json_round_trip(value)
	return round_trip.get("value", {}) if bool(round_trip.get("success", false)) else {}


static func is_active_at_tick(value: Dictionary, tick: int) -> bool:
	return bool(validate(value).get("success", false)) and String(value["status"]) == "ACTIVE" and tick >= int(value["issued_at_tick"]) and tick < int(value["expires_at_tick"])


static func can_renew_at_tick(value: Dictionary, tick: int) -> bool:
	return is_active_at_tick(value, tick) and tick >= int(value["renew_after_tick"])


static func _is_lower_hex_64(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for character in value:
		if not String(character) in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]:
			return false
	return true

extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.network_command.v1"
const PROTOCOL_VERSION: int = 1
const FIELDS: Array[String] = [
	"schema",
	"protocol_version",
	"message_id",
	"operation_id",
	"entity_id",
	"command_type",
	"payload",
	"expected_revision",
	"authority_epoch",
	"client_tick",
	"sent_at_monotonic_ms",
]


static func create(
	message_id: String,
	operation_id: String,
	entity_id: String,
	command_type: String,
	payload: Dictionary,
	expected_revision: int,
	authority_epoch: int,
	client_tick: int = 0,
	sent_at_monotonic_ms: int = 0
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"message_id": message_id,
		"operation_id": operation_id,
		"entity_id": entity_id,
		"command_type": command_type,
		"payload": payload.duplicate(true),
		"expected_revision": expected_revision,
		"authority_epoch": authority_epoch,
		"client_tick": client_tick,
		"sent_at_monotonic_ms": sent_at_monotonic_ms,
	}


static func validate(value: Dictionary) -> Dictionary:
	var fields_validation: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(fields_validation.get("success", false)):
		return fields_validation
	var check: Dictionary = UtilsScript.require_string(value, "schema")
	if not bool(check.get("success", false)):
		return check
	if value["schema"] != SCHEMA:
		return _failure("UNSUPPORTED_SCHEMA", "Unexpected network command schema")
	check = UtilsScript.require_json_integer(value, "protocol_version")
	if not bool(check.get("success", false)):
		return check
	if int(value["protocol_version"]) != PROTOCOL_VERSION:
		return _failure("UNSUPPORTED_PROTOCOL", "Unsupported protocol version")
	for key in ["message_id", "operation_id", "entity_id", "command_type"]:
		check = UtilsScript.require_string(value, key)
		if not bool(check.get("success", false)):
			return check
	check = UtilsScript.require_dictionary(value, "payload")
	if not bool(check.get("success", false)):
		return _failure("INVALID_PAYLOAD", String(check.get("message", "Command payload must be a Dictionary")))
	for integer_field in ["expected_revision", "authority_epoch", "client_tick", "sent_at_monotonic_ms"]:
		check = UtilsScript.require_json_integer(value, integer_field)
		if not bool(check.get("success", false)):
			return check
	if int(value["expected_revision"]) < -1:
		return _failure("INVALID_REVISION", "expected_revision must be -1 or greater")
	if int(value["authority_epoch"]) < 1:
		return _failure("INVALID_AUTHORITY_EPOCH", "authority_epoch must be positive")
	if int(value["client_tick"]) < 0:
		return _failure("INVALID_CLIENT_TICK", "client_tick cannot be negative")
	if int(value["sent_at_monotonic_ms"]) < 0:
		return _failure("INVALID_SENT_TIME", "sent_at_monotonic_ms cannot be negative")
	var safe: Dictionary = UtilsScript.canonicalize(value)
	if not bool(safe.get("success", false)):
		return _failure("NON_CANONICAL_PAYLOAD", String(safe.get("error", "")))
	return UtilsScript.validation_success()


static func normalize(value: Dictionary) -> Dictionary:
	if not bool(validate(value).get("success", false)):
		return {}
	var round_trip: Dictionary = UtilsScript.json_round_trip(value)
	return round_trip.get("value", {}) if bool(round_trip.get("success", false)) else {}


static func canonical_json(value: Dictionary) -> String:
	return UtilsScript.canonical_json(normalize(value))


static func command_fingerprint(value: Dictionary) -> String:
	if not bool(validate(value).get("success", false)):
		return ""
	return UtilsScript.payload_hash({
		"operation_id": value["operation_id"],
		"entity_id": value["entity_id"],
		"command_type": value["command_type"],
		"payload": value["payload"],
		"expected_revision": int(value["expected_revision"]),
		"authority_epoch": int(value["authority_epoch"]),
	})


static func _failure(error_code: String, message: String) -> Dictionary:
	return UtilsScript.validation_failure(error_code, message)

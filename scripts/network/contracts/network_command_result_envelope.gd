extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.network_command_result.v1"
const PROTOCOL_VERSION: int = 1
const ALLOWED_STATUSES: Array[String] = ["SUCCEEDED", "REJECTED", "RETRYABLE"]
const FIELDS: Array[String] = [
	"schema",
	"protocol_version",
	"message_id",
	"operation_id",
	"status",
	"error_code",
	"result_revision",
	"authority_epoch",
	"payload",
]


static func create(
	message_id: String,
	operation_id: String,
	status: String,
	error_code: String,
	result_revision: int,
	authority_epoch: int,
	payload: Dictionary = {}
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"message_id": message_id,
		"operation_id": operation_id,
		"status": status,
		"error_code": error_code,
		"result_revision": result_revision,
		"authority_epoch": authority_epoch,
		"payload": payload.duplicate(true),
	}


static func validate(value: Dictionary) -> Dictionary:
	var fields_validation: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(fields_validation.get("success", false)):
		return fields_validation
	var check: Dictionary = UtilsScript.require_string(value, "schema")
	if not bool(check.get("success", false)):
		return check
	if value["schema"] != SCHEMA:
		return _failure("UNSUPPORTED_SCHEMA", "Unexpected command result schema")
	check = UtilsScript.require_json_integer(value, "protocol_version")
	if not bool(check.get("success", false)):
		return check
	if int(value["protocol_version"]) != PROTOCOL_VERSION:
		return _failure("UNSUPPORTED_PROTOCOL", "Unsupported protocol version")
	for key in ["message_id", "operation_id", "status"]:
		check = UtilsScript.require_string(value, key)
		if not bool(check.get("success", false)):
			return check
	check = UtilsScript.require_string(value, "error_code", true)
	if not bool(check.get("success", false)):
		return check
	if not ALLOWED_STATUSES.has(value["status"]):
		return _failure("INVALID_STATUS", "Unknown command result status")
	for integer_field in ["result_revision", "authority_epoch"]:
		check = UtilsScript.require_json_integer(value, integer_field)
		if not bool(check.get("success", false)):
			return check
	if int(value["result_revision"]) < -1:
		return _failure("INVALID_REVISION", "result_revision must be -1 or greater")
	if int(value["authority_epoch"]) < 1:
		return _failure("INVALID_AUTHORITY_EPOCH", "authority_epoch must be positive")
	check = UtilsScript.require_dictionary(value, "payload")
	if not bool(check.get("success", false)):
		return _failure("INVALID_PAYLOAD", String(check.get("message", "Result payload must be a Dictionary")))
	var safe: Dictionary = UtilsScript.canonicalize(value)
	if not bool(safe.get("success", false)):
		return _failure("NON_CANONICAL_PAYLOAD", String(safe.get("error", "")))
	return UtilsScript.validation_success()


static func normalize(value: Dictionary) -> Dictionary:
	if not bool(validate(value).get("success", false)):
		return {}
	var round_trip: Dictionary = UtilsScript.json_round_trip(value)
	return round_trip.get("value", {}) if bool(round_trip.get("success", false)) else {}


static func _failure(error_code: String, message: String) -> Dictionary:
	return UtilsScript.validation_failure(error_code, message)

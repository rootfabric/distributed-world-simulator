extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA := "planet_simulator.bus_operation_result.v1"
const PROTOCOL_VERSION := 1
const SUCCESS_OUTCOMES: Array[String] = ["ACCEPTED", "ACKNOWLEDGED", "AVAILABLE", "COMPLETED", "DELIVERED", "EMPTY"]
const FAILURE_OUTCOMES: Array[String] = ["BACKPRESSURE", "FAILED", "NOT_FOUND", "REJECTED", "TIMEOUT"]
const FIELDS: Array[String] = ["schema", "protocol_version", "success", "outcome", "error_code", "retryable", "details"]


static func success(outcome: String = "COMPLETED", details: Dictionary = {}) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"success": true,
		"outcome": outcome,
		"error_code": "",
		"retryable": false,
		"details": details.duplicate(true),
	}


static func failure(outcome: String, error_code: String, retryable: bool, details: Dictionary = {}) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"success": false,
		"outcome": outcome,
		"error_code": error_code,
		"retryable": retryable,
		"details": details.duplicate(true),
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA or not NetworkUtilsScript.is_json_integer(value.get("protocol_version")) or int(value["protocol_version"]) != PROTOCOL_VERSION:
		return NetworkUtilsScript.validation_failure("INVALID_SCHEMA", "Bus operation result schema/version mismatch")
	if typeof(value.get("success")) != TYPE_BOOL or typeof(value.get("retryable")) != TYPE_BOOL:
		return NetworkUtilsScript.validation_failure("INVALID_FIELD_TYPE", "success and retryable must be Boolean")
	if typeof(value.get("outcome")) != TYPE_STRING or typeof(value.get("error_code")) != TYPE_STRING or typeof(value.get("details")) != TYPE_DICTIONARY:
		return NetworkUtilsScript.validation_failure("INVALID_FIELD_TYPE", "outcome, error_code or details has an invalid type")
	var canonical: Dictionary = NetworkUtilsScript.canonicalize(value.get("details"))
	if not bool(canonical.get("success", false)):
		return NetworkUtilsScript.validation_failure("NON_CANONICAL_DETAILS", String(canonical.get("error", "details are not JSON-safe")))
	var is_success: bool = bool(value["success"])
	var outcome: String = String(value["outcome"])
	var error_code: String = String(value["error_code"])
	if is_success:
		if not SUCCESS_OUTCOMES.has(outcome) or not error_code.is_empty() or bool(value["retryable"]):
			return NetworkUtilsScript.validation_failure("INCONSISTENT_RESULT", "Successful result fields are inconsistent")
	else:
		if not FAILURE_OUTCOMES.has(outcome) or error_code.strip_edges().is_empty():
			return NetworkUtilsScript.validation_failure("INCONSISTENT_RESULT", "Failure result fields are inconsistent")
	return NetworkUtilsScript.validation_success()

extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const BusUtilsScript = preload("res://scripts/network/bus/message_bus_contract_utils.gd")

const SCHEMA := "planet_simulator.service_request_envelope.v1"
const PROTOCOL_VERSION := 1
const FIELDS: Array[String] = ["schema", "protocol_version", "request_id", "service_id", "operation", "payload_schema", "payload", "timeout_ms"]


static func create(request_id: String, service_id: String, operation: String, payload_schema: String, payload: Dictionary, timeout_ms: int) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"request_id": request_id,
		"service_id": service_id,
		"operation": operation,
		"payload_schema": payload_schema,
		"payload": payload.duplicate(true),
		"timeout_ms": timeout_ms,
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA or not NetworkUtilsScript.is_json_integer(value.get("protocol_version")) or int(value["protocol_version"]) != PROTOCOL_VERSION:
		return NetworkUtilsScript.validation_failure("INVALID_SCHEMA", "Service request schema/version mismatch")
	if not BusUtilsScript.is_canonical_id(value.get("request_id"), "request"):
		return NetworkUtilsScript.validation_failure("INVALID_REQUEST_ID", "request_id is not canonical")
	if not BusUtilsScript.is_canonical_id(value.get("service_id"), "service"):
		return NetworkUtilsScript.validation_failure("INVALID_SERVICE_ID", "service_id is not canonical")
	if not BusUtilsScript.is_semantic_name(value.get("operation"), true):
		return NetworkUtilsScript.validation_failure("INVALID_OPERATION", "operation is not canonical")
	if not BusUtilsScript.is_payload_schema(value.get("payload_schema")):
		return NetworkUtilsScript.validation_failure("INVALID_PAYLOAD_SCHEMA", "payload_schema is not canonical")
	var payload_check: Dictionary = BusUtilsScript.validate_payload(value.get("payload"))
	if not bool(payload_check.get("success", false)):
		return payload_check
	if not NetworkUtilsScript.is_json_integer(value.get("timeout_ms")) or int(value["timeout_ms"]) < 1 or int(value["timeout_ms"]) > 3600000:
		return NetworkUtilsScript.validation_failure("INVALID_TIMEOUT", "timeout_ms must be within 1..3600000")
	return NetworkUtilsScript.validation_success()

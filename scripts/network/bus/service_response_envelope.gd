extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const BusUtilsScript = preload("res://scripts/network/bus/message_bus_contract_utils.gd")

const SCHEMA := "planet_simulator.service_response_envelope.v1"
const PROTOCOL_VERSION := 1
const FIELDS: Array[String] = ["schema", "protocol_version", "response_id", "request_id", "success", "payload_schema", "payload", "error_code"]


static func create_success(response_id: String, request_id: String, payload_schema: String, payload: Dictionary) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"response_id": response_id,
		"request_id": request_id,
		"success": true,
		"payload_schema": payload_schema,
		"payload": payload.duplicate(true),
		"error_code": "",
	}


static func create_failure(response_id: String, request_id: String, error_code: String, payload_schema: String = "planet_simulator.empty.v1", payload: Dictionary = {}) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"response_id": response_id,
		"request_id": request_id,
		"success": false,
		"payload_schema": payload_schema,
		"payload": payload.duplicate(true),
		"error_code": error_code,
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA or not NetworkUtilsScript.is_json_integer(value.get("protocol_version")) or int(value["protocol_version"]) != PROTOCOL_VERSION:
		return NetworkUtilsScript.validation_failure("INVALID_SCHEMA", "Service response schema/version mismatch")
	if not BusUtilsScript.is_canonical_id(value.get("response_id"), "response"):
		return NetworkUtilsScript.validation_failure("INVALID_RESPONSE_ID", "response_id is not canonical")
	if not BusUtilsScript.is_canonical_id(value.get("request_id"), "request"):
		return NetworkUtilsScript.validation_failure("INVALID_REQUEST_ID", "request_id is not canonical")
	if typeof(value.get("success")) != TYPE_BOOL or typeof(value.get("error_code")) != TYPE_STRING:
		return NetworkUtilsScript.validation_failure("INVALID_FIELD_TYPE", "success/error_code has invalid type")
	if not BusUtilsScript.is_payload_schema(value.get("payload_schema")):
		return NetworkUtilsScript.validation_failure("INVALID_PAYLOAD_SCHEMA", "payload_schema is not canonical")
	var payload_check: Dictionary = BusUtilsScript.validate_payload(value.get("payload"))
	if not bool(payload_check.get("success", false)):
		return payload_check
	if bool(value["success"]) and not String(value["error_code"]).is_empty():
		return NetworkUtilsScript.validation_failure("INCONSISTENT_RESPONSE", "Successful response cannot contain error_code")
	if not bool(value["success"]) and String(value["error_code"]).strip_edges().is_empty():
		return NetworkUtilsScript.validation_failure("INCONSISTENT_RESPONSE", "Failed response requires error_code")
	return NetworkUtilsScript.validation_success()

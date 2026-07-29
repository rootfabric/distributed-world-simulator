extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const BusUtilsScript = preload("res://scripts/network/bus/message_bus_contract_utils.gd")

const SCHEMA := "planet_simulator.job_envelope.v1"
const PROTOCOL_VERSION := 1
const FIELDS: Array[String] = ["schema", "protocol_version", "job_id", "queue_id", "job_type", "payload_schema", "payload", "max_attempts", "visibility_timeout_ms"]


static func create(job_id: String, queue_id: String, job_type: String, payload_schema: String, payload: Dictionary, max_attempts: int = 3, visibility_timeout_ms: int = 30000) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"job_id": job_id,
		"queue_id": queue_id,
		"job_type": job_type,
		"payload_schema": payload_schema,
		"payload": payload.duplicate(true),
		"max_attempts": max_attempts,
		"visibility_timeout_ms": visibility_timeout_ms,
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA or not NetworkUtilsScript.is_json_integer(value.get("protocol_version")) or int(value["protocol_version"]) != PROTOCOL_VERSION:
		return NetworkUtilsScript.validation_failure("INVALID_SCHEMA", "Job schema/version mismatch")
	if not BusUtilsScript.is_canonical_id(value.get("job_id"), "job") or not BusUtilsScript.is_canonical_id(value.get("queue_id"), "queue"):
		return NetworkUtilsScript.validation_failure("INVALID_JOB_IDENTITY", "job_id/queue_id is not canonical")
	if not BusUtilsScript.is_semantic_name(value.get("job_type"), true):
		return NetworkUtilsScript.validation_failure("INVALID_JOB_TYPE", "job_type is not canonical")
	if not BusUtilsScript.is_payload_schema(value.get("payload_schema")):
		return NetworkUtilsScript.validation_failure("INVALID_PAYLOAD_SCHEMA", "payload_schema is not canonical")
	var payload_check: Dictionary = BusUtilsScript.validate_payload(value.get("payload"))
	if not bool(payload_check.get("success", false)):
		return payload_check
	if not NetworkUtilsScript.is_json_integer(value.get("max_attempts")) or int(value["max_attempts"]) < 1 or int(value["max_attempts"]) > 100:
		return NetworkUtilsScript.validation_failure("INVALID_MAX_ATTEMPTS", "max_attempts must be within 1..100")
	if not NetworkUtilsScript.is_json_integer(value.get("visibility_timeout_ms")) or int(value["visibility_timeout_ms"]) < 1 or int(value["visibility_timeout_ms"]) > 86400000:
		return NetworkUtilsScript.validation_failure("INVALID_VISIBILITY_TIMEOUT", "visibility_timeout_ms is out of range")
	return NetworkUtilsScript.validation_success()

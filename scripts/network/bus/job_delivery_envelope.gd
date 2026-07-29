extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const BusUtilsScript = preload("res://scripts/network/bus/message_bus_contract_utils.gd")
const JobScript = preload("res://scripts/network/bus/job_envelope.gd")

const SCHEMA := "planet_simulator.job_delivery_envelope.v1"
const PROTOCOL_VERSION := 1
const FIELDS: Array[String] = ["schema", "protocol_version", "delivery_id", "worker_id", "attempt", "job"]


static func create(delivery_id: String, worker_id: String, attempt: int, job: Dictionary) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"delivery_id": delivery_id,
		"worker_id": worker_id,
		"attempt": attempt,
		"job": job.duplicate(true),
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA or not NetworkUtilsScript.is_json_integer(value.get("protocol_version")) or int(value["protocol_version"]) != PROTOCOL_VERSION:
		return NetworkUtilsScript.validation_failure("INVALID_SCHEMA", "Job delivery schema/version mismatch")
	if not BusUtilsScript.is_canonical_id(value.get("delivery_id"), "delivery") or not BusUtilsScript.is_canonical_id(value.get("worker_id"), "worker"):
		return NetworkUtilsScript.validation_failure("INVALID_DELIVERY_IDENTITY", "delivery_id/worker_id is not canonical")
	if not NetworkUtilsScript.is_json_integer(value.get("attempt")) or int(value["attempt"]) < 1:
		return NetworkUtilsScript.validation_failure("INVALID_ATTEMPT", "attempt must be positive")
	if typeof(value.get("job")) != TYPE_DICTIONARY:
		return NetworkUtilsScript.validation_failure("INVALID_JOB", "job must be a Dictionary")
	var job_check: Dictionary = JobScript.validate(value["job"])
	if not bool(job_check.get("success", false)):
		return job_check
	if int(value["attempt"]) > int(value["job"].get("max_attempts", 0)):
		return NetworkUtilsScript.validation_failure("ATTEMPT_LIMIT_EXCEEDED", "attempt exceeds job max_attempts")
	return NetworkUtilsScript.validation_success()

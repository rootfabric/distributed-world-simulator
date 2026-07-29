extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ComputeUtilsScript = preload("res://scripts/simulation/compute/compute_contract_utils.gd")
const ProposalScript = preload("res://scripts/simulation/compute/mutation_proposal.gd")

const SCHEMA := "planet_simulator.simulation_job_result_envelope.v1"
const PROTOCOL_VERSION := 1
const FIELDS: Array[String] = [
	"schema", "protocol_version", "result_id", "job_id", "job_attempt", "worker_id",
	"success", "error_code", "retryable", "proposal", "result_hash", "checksum",
]


static func success_result(result_id: String, proposal: Dictionary) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"result_id": result_id,
		"job_id": String(proposal.get("job_id", "")),
		"job_attempt": int(proposal.get("job_attempt", 0)),
		"worker_id": String(proposal.get("worker_id", "")),
		"success": true,
		"error_code": "",
		"retryable": false,
		"proposal": proposal.duplicate(true),
		"result_hash": "",
		"checksum": "",
	}
	value["result_hash"] = compute_result_hash(value)
	value["checksum"] = compute_checksum(value)
	return value


static func failure_result(result_id: String, job_id: String, job_attempt: int, worker_id: String, error_code: String, retryable: bool) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"result_id": result_id,
		"job_id": job_id,
		"job_attempt": job_attempt,
		"worker_id": worker_id,
		"success": false,
		"error_code": error_code,
		"retryable": retryable,
		"proposal": {},
		"result_hash": "",
		"checksum": "",
	}
	value["result_hash"] = compute_result_hash(value)
	value["checksum"] = compute_checksum(value)
	return value


static func compute_result_hash(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload.erase("result_hash")
	payload.erase("checksum")
	return NetworkUtilsScript.payload_hash(payload)


static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload.erase("checksum")
	return NetworkUtilsScript.payload_hash(payload)


static func validate(value: Dictionary) -> Dictionary:
	var exact := NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA or not NetworkUtilsScript.is_json_integer(value.get("protocol_version")) or int(value["protocol_version"]) != PROTOCOL_VERSION:
		return ComputeUtilsScript.failure("UNSUPPORTED_SIMULATION_JOB_RESULT_SCHEMA")
	if not ComputeUtilsScript.is_identifier(String(value.get("result_id", "")), "result/") or not ComputeUtilsScript.is_identifier(String(value.get("job_id", "")), "job/") or not ComputeUtilsScript.is_identifier(String(value.get("worker_id", "")), "worker/"):
		return ComputeUtilsScript.failure("INVALID_SIMULATION_JOB_RESULT_IDENTITY")
	if not NetworkUtilsScript.is_json_integer(value.get("job_attempt")) or int(value["job_attempt"]) < 1 or typeof(value.get("success")) != TYPE_BOOL or typeof(value.get("retryable")) != TYPE_BOOL or typeof(value.get("error_code")) != TYPE_STRING or typeof(value.get("proposal")) != TYPE_DICTIONARY:
		return ComputeUtilsScript.failure("INVALID_SIMULATION_JOB_RESULT_FIELDS")
	if bool(value["success"]):
		if not String(value["error_code"]).is_empty() or bool(value["retryable"]):
			return ComputeUtilsScript.failure("INVALID_SUCCESSFUL_SIMULATION_JOB_RESULT")
		var proposal_check := ProposalScript.validate(value["proposal"])
		if not bool(proposal_check.get("success", false)):
			return proposal_check
		if String(value["proposal"]["job_id"]) != String(value["job_id"]) or int(value["proposal"]["job_attempt"]) != int(value["job_attempt"]) or String(value["proposal"]["worker_id"]) != String(value["worker_id"]):
			return ComputeUtilsScript.failure("SIMULATION_JOB_RESULT_PROPOSAL_MISMATCH")
	else:
		if String(value["error_code"]).is_empty() or not value["proposal"].is_empty():
			return ComputeUtilsScript.failure("INVALID_FAILED_SIMULATION_JOB_RESULT")
	for field in ["result_hash", "checksum"]:
		if not ComputeUtilsScript.is_lower_hex_64(String(value.get(field, ""))):
			return ComputeUtilsScript.failure("INVALID_SIMULATION_JOB_RESULT_HASH", {"field": field})
	if String(value["result_hash"]) != compute_result_hash(value) or String(value["checksum"]) != compute_checksum(value):
		return ComputeUtilsScript.failure("SIMULATION_JOB_RESULT_CHECKSUM_MISMATCH")
	return ComputeUtilsScript.success()

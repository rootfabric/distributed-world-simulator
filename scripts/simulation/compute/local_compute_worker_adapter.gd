extends RefCounted

const ComputeUtilsScript = preload("res://scripts/simulation/compute/compute_contract_utils.gd")
const JobScript = preload("res://scripts/simulation/compute/simulation_job_envelope.gd")
const CapabilityScript = preload("res://scripts/simulation/compute/compute_capability_descriptor.gd")
const WorkerScript = preload("res://scripts/simulation/compute/compute_worker_descriptor.gd")
const ProposalOperationScript = preload("res://scripts/simulation/compute/mutation_proposal_operation.gd")
const ProposalScript = preload("res://scripts/simulation/compute/mutation_proposal.gd")
const ResultScript = preload("res://scripts/simulation/compute/simulation_job_result_envelope.gd")
const WriteSetScript = preload("res://scripts/simulation/compute/mutation_write_set.gd")

var _descriptor: Dictionary = {}
var _handler
var _configured := false


func configure(descriptor: Dictionary, handler) -> Dictionary:
	var descriptor_check := WorkerScript.validate(descriptor)
	if not bool(descriptor_check.get("success", false)):
		return descriptor_check
	if handler == null or not handler.has_method("execute_simulation_job"):
		return ComputeUtilsScript.failure("COMPUTE_HANDLER_REQUIRED")
	_descriptor = descriptor.duplicate(true)
	_handler = handler
	_configured = true
	return ComputeUtilsScript.success()


func get_descriptor() -> Dictionary:
	return _descriptor.duplicate(true)


func execute(job: Dictionary) -> Dictionary:
	if not _configured:
		return ComputeUtilsScript.failure("LOCAL_COMPUTE_WORKER_NOT_CONFIGURED")
	var job_check := JobScript.validate(job)
	if not bool(job_check.get("success", false)):
		return job_check
	var capability := WorkerScript.find_capability(_descriptor, String(job["required_capability_id"]))
	if capability.is_empty():
		return _failure_result(job, "WORKER_CAPABILITY_NOT_FOUND", false)
	if not CapabilityScript.supports(capability, String(job["job_type"]), String(job["rule_package_hash"]), job["execution_budget"]):
		return _failure_result(job, "WORKER_CAPABILITY_REJECTED_JOB", false)
	var copied := ComputeUtilsScript.canonical_copy(job)
	if not bool(copied.get("success", false)):
		return copied
	var handler_result = _handler.execute_simulation_job(copied["details"]["value"])
	if typeof(handler_result) != TYPE_DICTIONARY:
		return _failure_result(job, "COMPUTE_HANDLER_INVALID_RESULT", false)
	if not bool(handler_result.get("success", false)):
		return _failure_result(job, String(handler_result.get("error_code", "COMPUTE_HANDLER_FAILED")), bool(handler_result.get("retryable", false)))
	if typeof(handler_result.get("operations")) != TYPE_ARRAY or typeof(handler_result.get("instruction_units")) != TYPE_INT or int(handler_result.get("instruction_units", -1)) < 0:
		return _failure_result(job, "COMPUTE_HANDLER_INVALID_OUTPUT", false)
	var operations: Array = handler_result["operations"].duplicate(true)
	for operation in operations:
		if typeof(operation) != TYPE_DICTIONARY:
			return _failure_result(job, "COMPUTE_HANDLER_INVALID_OPERATION", false)
		var operation_check := ProposalOperationScript.validate(operation)
		if not bool(operation_check.get("success", false)):
			return _failure_result(job, String(operation_check.get("error_code", "INVALID_PROPOSAL_OPERATION")), false)
		var write_check := _validate_operation_against_write_set(job["write_set"], operation)
		if not bool(write_check.get("success", false)):
			return _failure_result(job, String(write_check.get("error_code", "UNDECLARED_COMPUTE_WRITE")), false)
	var proposal_id := "proposal/%s/attempt-%d/%s" % [String(job["job_id"]).trim_prefix("job/"), int(job["job_attempt"]), String(_descriptor["worker_id"]).trim_prefix("worker/")]
	var proposal := ProposalScript.create(
		proposal_id,
		String(job["job_id"]),
		int(job["job_attempt"]),
		String(job["checksum"]),
		String(_descriptor["worker_id"]),
		String(job["required_capability_id"]),
		String(job["determinism_fingerprint"]["fingerprint"]),
		String(job["rule_package_hash"]),
		operations,
		int(handler_result["instruction_units"])
	)
	var proposal_check := ProposalScript.validate(proposal)
	if not bool(proposal_check.get("success", false)):
		return _failure_result(job, String(proposal_check.get("error_code", "INVALID_MUTATION_PROPOSAL")), false)
	var budget: Dictionary = job["execution_budget"]
	if int(proposal["operation_count"]) > int(budget["maximum_operations"]):
		return _failure_result(job, "COMPUTE_OPERATION_BUDGET_EXCEEDED", false)
	if int(proposal["output_bytes"]) > int(budget["maximum_output_bytes"]):
		return _failure_result(job, "COMPUTE_OUTPUT_BUDGET_EXCEEDED", false)
	if int(proposal["instruction_units"]) > int(budget["maximum_instruction_units"]):
		return _failure_result(job, "COMPUTE_INSTRUCTION_BUDGET_EXCEEDED", false)
	var result_id := "result/%s/attempt-%d/%s" % [String(job["job_id"]).trim_prefix("job/"), int(job["job_attempt"]), String(_descriptor["worker_id"]).trim_prefix("worker/")]
	return ComputeUtilsScript.success({"result": ResultScript.success_result(result_id, proposal)})


func _validate_operation_against_write_set(write_set: Dictionary, operation: Dictionary) -> Dictionary:
	var aggregate_id: String = String(operation["aggregate_id"])
	if not WriteSetScript.allows_operation(write_set, aggregate_id, String(operation["operation_kind"])):
		return ComputeUtilsScript.failure("UNDECLARED_COMPUTE_OPERATION")
	var entry := WriteSetScript.entry_for(write_set, aggregate_id)
	if String(entry.get("aggregate_kind", "")) != String(operation["aggregate_kind"]) or String(entry.get("state_schema", "")) != String(operation["state_schema"]):
		return ComputeUtilsScript.failure("COMPUTE_WRITE_IDENTITY_MISMATCH")
	for path_value in operation["changed_fields"].keys():
		if not WriteSetScript.allows_path(write_set, aggregate_id, String(path_value)):
			return ComputeUtilsScript.failure("UNDECLARED_COMPUTE_WRITE", {"path": path_value})
	for path_value in operation["removed_fields"]:
		if not WriteSetScript.allows_path(write_set, aggregate_id, String(path_value)):
			return ComputeUtilsScript.failure("UNDECLARED_COMPUTE_WRITE", {"path": path_value})
	return ComputeUtilsScript.success()


func _failure_result(job: Dictionary, error_code: String, retryable: bool) -> Dictionary:
	var result_id := "result/%s/attempt-%d/%s" % [String(job.get("job_id", "job/invalid")).trim_prefix("job/"), int(job.get("job_attempt", 1)), String(_descriptor.get("worker_id", "worker/invalid")).trim_prefix("worker/")]
	return ComputeUtilsScript.success({"result": ResultScript.failure_result(result_id, String(job.get("job_id", "job/invalid")), int(job.get("job_attempt", 1)), String(job.get("checksum", "")), String(_descriptor.get("worker_id", "worker/invalid")), error_code, retryable)})

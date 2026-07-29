extends RefCounted

const SnapshotScript = preload("res://scripts/network/contracts/aggregate_snapshot_envelope.gd")
const ComputeUtilsScript = preload("res://scripts/simulation/compute/compute_contract_utils.gd")
const JobScript = preload("res://scripts/simulation/compute/simulation_job_envelope.gd")
const ResultScript = preload("res://scripts/simulation/compute/simulation_job_result_envelope.gd")
const WorkerScript = preload("res://scripts/simulation/compute/compute_worker_descriptor.gd")
const CapabilityScript = preload("res://scripts/simulation/compute/compute_capability_descriptor.gd")
const WriteSetScript = preload("res://scripts/simulation/compute/mutation_write_set.gd")
const ProposalOperationScript = preload("res://scripts/simulation/compute/mutation_proposal_operation.gd")
const PreconditionScript = preload("res://scripts/simulation/transactions/aggregate_precondition.gd")
const OperationScript = preload("res://scripts/simulation/transactions/aggregate_mutation_operation.gd")
const BatchScript = preload("res://scripts/simulation/transactions/mutation_batch.gd")
const OutboxIntentScript = preload("res://scripts/simulation/transactions/outbox_intent.gd")

var _transaction_coordinator
var _adapter_registry
var _worker_registry
var _configured := false
var _issued_jobs_by_attempt: Dictionary = {}
var _accepted_results_by_job_attempt: Dictionary = {}


func configure(transaction_coordinator, adapter_registry, worker_registry) -> Dictionary:
	if transaction_coordinator == null or not transaction_coordinator.has_method("get_snapshot") or not transaction_coordinator.has_method("execute_batch"):
		return ComputeUtilsScript.failure("COMPUTE_AUTHORITY_TRANSACTION_COORDINATOR_REQUIRED")
	if adapter_registry == null or not adapter_registry.has_method("validate_snapshot"):
		return ComputeUtilsScript.failure("COMPUTE_AUTHORITY_ADAPTER_REGISTRY_REQUIRED")
	if worker_registry == null or not worker_registry.has_method("get_worker"):
		return ComputeUtilsScript.failure("COMPUTE_AUTHORITY_WORKER_REGISTRY_REQUIRED")
	_transaction_coordinator = transaction_coordinator
	_adapter_registry = adapter_registry
	_worker_registry = worker_registry
	_configured = true
	return ComputeUtilsScript.success()


func register_issued_job(job: Dictionary) -> Dictionary:
	if not _configured:
		return ComputeUtilsScript.failure("DISTRIBUTED_COMPUTE_AUTHORITY_NOT_CONFIGURED")
	var job_check := JobScript.validate(job)
	if not bool(job_check.get("success", false)):
		return job_check
	var copied := ComputeUtilsScript.canonical_copy(job)
	if not bool(copied.get("success", false)):
		return copied
	var canonical_job: Dictionary = copied["details"]["value"]
	var key := _job_attempt_key(String(canonical_job["job_id"]), int(canonical_job["job_attempt"]))
	if _issued_jobs_by_attempt.has(key):
		var issued: Dictionary = _issued_jobs_by_attempt[key]
		if String(issued["checksum"]) != String(canonical_job["checksum"]):
			return ComputeUtilsScript.failure("COMPUTE_JOB_CONFLICT", {"job_id": canonical_job["job_id"], "job_attempt": canonical_job["job_attempt"]})
		return ComputeUtilsScript.success({"job": issued["job"].duplicate(true), "replay": true})
	_issued_jobs_by_attempt[key] = {"checksum": canonical_job["checksum"], "job": canonical_job.duplicate(true)}
	return ComputeUtilsScript.success({"job": canonical_job.duplicate(true), "replay": false})


func get_issued_job(job_id: String, job_attempt: int) -> Dictionary:
	if not _configured:
		return ComputeUtilsScript.failure("DISTRIBUTED_COMPUTE_AUTHORITY_NOT_CONFIGURED")
	var key := _job_attempt_key(job_id, job_attempt)
	if not _issued_jobs_by_attempt.has(key):
		return ComputeUtilsScript.failure("COMPUTE_JOB_NOT_ISSUED", {"job_id": job_id, "job_attempt": job_attempt})
	return ComputeUtilsScript.success({"job": _issued_jobs_by_attempt[key]["job"].duplicate(true)})


func accept_result(result: Dictionary) -> Dictionary:
	if not _configured:
		return ComputeUtilsScript.failure("DISTRIBUTED_COMPUTE_AUTHORITY_NOT_CONFIGURED")
	var result_check := ResultScript.validate(result)
	if not bool(result_check.get("success", false)):
		return result_check
	var issued_result := get_issued_job(String(result["job_id"]), int(result["job_attempt"]))
	if not bool(issued_result.get("success", false)):
		return issued_result
	var job: Dictionary = issued_result["details"]["job"]
	if String(result["job_checksum"]) != String(job["checksum"]):
		return ComputeUtilsScript.failure("COMPUTE_JOB_CHECKSUM_MISMATCH")
	if not bool(result["success"]):
		return ComputeUtilsScript.failure("COMPUTE_RESULT_FAILED", {"worker_error_code": result["error_code"], "retryable": result["retryable"]})
	var replay_key := _job_attempt_key(String(job["job_id"]), int(job["job_attempt"]))
	if _accepted_results_by_job_attempt.has(replay_key):
		var accepted: Dictionary = _accepted_results_by_job_attempt[replay_key]
		if String(accepted["result_checksum"]) != String(result["checksum"]):
			return ComputeUtilsScript.failure("COMPUTE_RESULT_CONFLICT")
		var replay_response: Dictionary = accepted["response"].duplicate(true)
		replay_response["details"]["replay"] = true
		return replay_response
	var proposal: Dictionary = result["proposal"]
	if String(proposal["job_checksum"]) != String(job["checksum"]):
		return ComputeUtilsScript.failure("COMPUTE_JOB_CHECKSUM_MISMATCH")
	if String(proposal["determinism_fingerprint"]) != String(job["determinism_fingerprint"]["fingerprint"]) or String(proposal["rule_package_hash"]) != String(job["rule_package_hash"]) or String(proposal["capability_id"]) != String(job["required_capability_id"]):
		return ComputeUtilsScript.failure("COMPUTE_RESULT_DETERMINISM_MISMATCH")
	var worker_result: Dictionary = _worker_registry.get_worker(String(result["worker_id"]))
	if not bool(worker_result.get("success", false)):
		return worker_result
	var worker: Dictionary = worker_result["details"]["worker"]
	var capability := WorkerScript.find_capability(worker, String(job["required_capability_id"]))
	if capability.is_empty() or not CapabilityScript.supports(capability, String(job["job_type"]), String(job["rule_package_hash"]), job["execution_budget"]):
		return ComputeUtilsScript.failure("COMPUTE_WORKER_CAPABILITY_MISMATCH")
	var budget: Dictionary = job["execution_budget"]
	if int(proposal["operation_count"]) > int(budget["maximum_operations"]) or int(proposal["output_bytes"]) > int(budget["maximum_output_bytes"]) or int(proposal["instruction_units"]) > int(budget["maximum_instruction_units"]):
		return ComputeUtilsScript.failure("COMPUTE_PROPOSAL_BUDGET_EXCEEDED")
	var current_by_id: Dictionary = {}
	for input_reference in job["input_references"]:
		var aggregate_id: String = String(input_reference["aggregate_id"])
		var current_result: Dictionary = _transaction_coordinator.get_snapshot(aggregate_id)
		if not bool(current_result.get("success", false)):
			return ComputeUtilsScript.failure("COMPUTE_INPUT_NOT_FOUND", {"aggregate_id": aggregate_id})
		var current: Dictionary = current_result["details"]["snapshot"]
		var identity: Dictionary = current["descriptor"]["identity"]
		var authority: Dictionary = current["descriptor"]["authority"]
		if String(identity["aggregate_kind"]) != String(input_reference["aggregate_kind"]) or String(identity["state_schema"]) != String(input_reference["state_schema"]):
			return ComputeUtilsScript.failure("STALE_COMPUTE_INPUT_IDENTITY", {"aggregate_id": aggregate_id})
		if String(current["checksum"]) != String(input_reference["snapshot_checksum"]):
			return ComputeUtilsScript.failure("STALE_COMPUTE_INPUT_CHECKSUM", {"aggregate_id": aggregate_id})
		if String(authority["authority_owner_id"]) != String(input_reference["authority_owner_id"]) or int(authority["authority_epoch"]) != int(input_reference["authority_epoch"]):
			return ComputeUtilsScript.failure("STALE_COMPUTE_INPUT_AUTHORITY", {"aggregate_id": aggregate_id})
		if int(authority["state_revision"]) != int(input_reference["state_revision"]):
			return ComputeUtilsScript.failure("STALE_COMPUTE_INPUT_REVISION", {"aggregate_id": aggregate_id})
		if int(authority["server_tick"]) != int(input_reference["server_tick"]):
			return ComputeUtilsScript.failure("STALE_COMPUTE_INPUT_TICK", {"aggregate_id": aggregate_id})
		current_by_id[aggregate_id] = current
	var preconditions: Array = []
	var operations: Array = []
	for proposal_operation in proposal["operations"]:
		var validate_write := _validate_proposal_operation(job["write_set"], proposal_operation)
		if not bool(validate_write.get("success", false)):
			return validate_write
		var aggregate_id: String = String(proposal_operation["aggregate_id"])
		if not current_by_id.has(aggregate_id):
			return ComputeUtilsScript.failure("COMPUTE_WRITE_INPUT_NOT_FOUND", {"aggregate_id": aggregate_id})
		var current: Dictionary = current_by_id[aggregate_id]
		var authoritative_identity := _validate_authoritative_write_identity(job["write_set"], proposal_operation, current)
		if not bool(authoritative_identity.get("success", false)):
			return authoritative_identity
		var result_snapshot := current.duplicate(true)
		for path_value in proposal_operation["removed_fields"]:
			var erase_result := ComputeUtilsScript.remove_state_path(result_snapshot["state"], String(path_value))
			if not bool(erase_result.get("success", false)):
				return erase_result
		for path_value in proposal_operation["changed_fields"].keys():
			var set_result := ComputeUtilsScript.write_state_path(result_snapshot["state"], String(path_value), proposal_operation["changed_fields"][path_value])
			if not bool(set_result.get("success", false)):
				return set_result
		result_snapshot["descriptor"]["authority"]["state_revision"] = int(current["descriptor"]["authority"]["state_revision"]) + 1
		result_snapshot["descriptor"]["authority"]["server_tick"] = int(job["to_tick"])
		result_snapshot["snapshot_id"] = "snapshot/%s/r%d" % [aggregate_id.trim_prefix("aggregate/"), int(result_snapshot["descriptor"]["authority"]["state_revision"])]
		result_snapshot["checksum"] = SnapshotScript.compute_checksum(result_snapshot)
		var snapshot_check: Dictionary = _adapter_registry.validate_snapshot(result_snapshot)
		if not bool(snapshot_check.get("success", false)):
			return ComputeUtilsScript.failure("COMPUTE_RESULT_SNAPSHOT_REJECTED", {"aggregate_id": aggregate_id, "cause": snapshot_check})
		var identity: Dictionary = current["descriptor"]["identity"]
		var authority: Dictionary = current["descriptor"]["authority"]
		preconditions.append(PreconditionScript.create(aggregate_id, String(identity["aggregate_kind"]), String(identity["state_schema"]), true, String(authority["authority_owner_id"]), int(authority["authority_epoch"]), int(authority["state_revision"])))
		operations.append(OperationScript.create(OperationScript.OP_UPDATE, aggregate_id, String(identity["aggregate_kind"]), String(identity["state_schema"]), result_snapshot))
	preconditions.sort_custom(func(a, b): return String(a["aggregate_id"]) < String(b["aggregate_id"]))
	operations.sort_custom(func(a, b): return String(a["aggregate_id"]) < String(b["aggregate_id"]))
	var suffix := String(job["job_id"]).trim_prefix("job/")
	var outbox := OutboxIntentScript.create("outbox-intent/simulation/%s/attempt-%d" % [suffix, int(job["job_attempt"])], "stream/domain-events", "planet_simulator.simulation_job_committed.v1", {
		"job_id": job["job_id"],
		"job_attempt": job["job_attempt"],
		"job_checksum": job["checksum"],
		"result_id": result["result_id"],
		"result_hash": result["result_hash"],
		"proposal_id": proposal["proposal_id"],
		"proposal_hash": proposal["proposal_hash"],
		"worker_id": result["worker_id"],
	})
	var batch := BatchScript.create("batch/simulation/%s/attempt-%d" % [suffix, int(job["job_attempt"])], "operation/simulation/%s/attempt-%d" % [suffix, int(job["job_attempt"])], String(job["authority_owner_id"]), int(job["authority_epoch"]), int(job["to_tick"]), preconditions, operations, [outbox])
	var committed: Dictionary = _transaction_coordinator.execute_batch(batch)
	if not bool(committed.get("success", false)):
		return committed
	var response := ComputeUtilsScript.success({"replay": bool(committed["details"].get("replay", false)), "transaction_result": committed["details"]["result"], "proposal_id": proposal["proposal_id"], "result_id": result["result_id"]})
	_accepted_results_by_job_attempt[replay_key] = {"result_checksum": result["checksum"], "response": response.duplicate(true)}
	return response


func _validate_proposal_operation(write_set: Dictionary, operation: Dictionary) -> Dictionary:
	var operation_check := ProposalOperationScript.validate(operation)
	if not bool(operation_check.get("success", false)):
		return operation_check
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


func _validate_authoritative_write_identity(write_set: Dictionary, operation: Dictionary, current: Dictionary) -> Dictionary:
	var aggregate_id := String(operation["aggregate_id"])
	var write_entry := WriteSetScript.entry_for(write_set, aggregate_id)
	var identity: Dictionary = current["descriptor"]["identity"]
	if String(write_entry.get("aggregate_kind", "")) != String(identity["aggregate_kind"]) or String(write_entry.get("state_schema", "")) != String(identity["state_schema"]) or String(operation["aggregate_kind"]) != String(identity["aggregate_kind"]) or String(operation["state_schema"]) != String(identity["state_schema"]):
		return ComputeUtilsScript.failure("COMPUTE_WRITE_AUTHORITY_IDENTITY_MISMATCH", {"aggregate_id": aggregate_id})
	return ComputeUtilsScript.success()


func _job_attempt_key(job_id: String, job_attempt: int) -> String:
	return "%s#%d" % [job_id, job_attempt]

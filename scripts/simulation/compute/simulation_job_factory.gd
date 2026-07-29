extends RefCounted

const ComputeUtilsScript = preload("res://scripts/simulation/compute/compute_contract_utils.gd")
const ReadSetScript = preload("res://scripts/simulation/compute/mutation_read_set.gd")
const WriteSetScript = preload("res://scripts/simulation/compute/mutation_write_set.gd")
const InputScript = preload("res://scripts/simulation/compute/simulation_job_input_reference.gd")
const JobScript = preload("res://scripts/simulation/compute/simulation_job_envelope.gd")

var _transaction_coordinator
var _configured := false


func configure(transaction_coordinator) -> Dictionary:
	if transaction_coordinator == null or not transaction_coordinator.has_method("get_snapshot"):
		return ComputeUtilsScript.failure("SIMULATION_JOB_FACTORY_TRANSACTION_COORDINATOR_REQUIRED")
	_transaction_coordinator = transaction_coordinator
	_configured = true
	return ComputeUtilsScript.success()


func create_job(
	job_id: String,
	job_type: String,
	job_attempt: int,
	required_capability_id: String,
	authority_owner_id: String,
	authority_epoch: int,
	from_tick: int,
	to_tick: int,
	read_set: Dictionary,
	write_set: Dictionary,
	rule_package_hash: String,
	algorithm_version: String,
	deterministic_seed: int,
	execution_budget: Dictionary
) -> Dictionary:
	if not _configured:
		return ComputeUtilsScript.failure("SIMULATION_JOB_FACTORY_NOT_CONFIGURED")
	var read_check := ReadSetScript.validate(read_set)
	if not bool(read_check.get("success", false)):
		return read_check
	var write_check := WriteSetScript.validate(write_set)
	if not bool(write_check.get("success", false)):
		return write_check
	var read_ids: Array[String] = []
	for entry in read_set["entries"]:
		read_ids.append(String(entry["aggregate_id"]))
	for entry in write_set["entries"]:
		if not read_ids.has(String(entry["aggregate_id"])):
			return ComputeUtilsScript.failure("SIMULATION_JOB_WRITE_INPUT_MISSING", {"aggregate_id": entry["aggregate_id"]})
	var inputs: Array = []
	for entry in read_set["entries"]:
		var aggregate_id: String = String(entry["aggregate_id"])
		var snapshot_result: Dictionary = _transaction_coordinator.get_snapshot(aggregate_id)
		if not bool(snapshot_result.get("success", false)):
			return ComputeUtilsScript.failure("SIMULATION_JOB_INPUT_NOT_FOUND", {"aggregate_id": aggregate_id, "cause": snapshot_result})
		var snapshot: Dictionary = snapshot_result["details"]["snapshot"]
		var identity: Dictionary = snapshot["descriptor"]["identity"]
		var authority: Dictionary = snapshot["descriptor"]["authority"]
		if String(identity["aggregate_kind"]) != String(entry["aggregate_kind"]) or String(identity["state_schema"]) != String(entry["state_schema"]):
			return ComputeUtilsScript.failure("SIMULATION_JOB_INPUT_IDENTITY_MISMATCH", {"aggregate_id": aggregate_id})
		if String(authority["authority_owner_id"]) != authority_owner_id or int(authority["authority_epoch"]) != authority_epoch:
			return ComputeUtilsScript.failure("SIMULATION_JOB_INPUT_AUTHORITY_MISMATCH", {"aggregate_id": aggregate_id})
		if int(authority["server_tick"]) > from_tick:
			return ComputeUtilsScript.failure("SIMULATION_JOB_INPUT_TICK_AHEAD", {"aggregate_id": aggregate_id})
		var projected_state: Dictionary = {}
		for path_value in entry["paths"]:
			var read_value := ComputeUtilsScript.read_state_path(snapshot["state"], String(path_value))
			if not bool(read_value.get("success", false)):
				return ComputeUtilsScript.failure("SIMULATION_JOB_READ_PATH_NOT_FOUND", {"aggregate_id": aggregate_id, "path": path_value})
			var set_result := ComputeUtilsScript.write_state_path(projected_state, String(path_value), read_value["details"]["value"])
			if not bool(set_result.get("success", false)):
				return set_result
		inputs.append(InputScript.create(snapshot, projected_state))
	var job := JobScript.create(job_id, job_type, job_attempt, required_capability_id, authority_owner_id, authority_epoch, from_tick, to_tick, inputs, read_set, write_set, rule_package_hash, algorithm_version, deterministic_seed, execution_budget)
	var job_check := JobScript.validate(job)
	if not bool(job_check.get("success", false)):
		return job_check
	return ComputeUtilsScript.success({"job": job})

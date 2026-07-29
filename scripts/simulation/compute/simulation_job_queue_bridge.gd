extends RefCounted

const ComputeUtilsScript = preload("res://scripts/simulation/compute/compute_contract_utils.gd")
const SimulationJobScript = preload("res://scripts/simulation/compute/simulation_job_envelope.gd")
const JobEnvelopeScript = preload("res://scripts/network/bus/job_envelope.gd")

const QUEUE_ID := "queue/simulation-jobs"

var _job_queue_port
var _configured := false


func configure(job_queue_port) -> Dictionary:
	if job_queue_port == null or not job_queue_port.has_method("submit") or not job_queue_port.has_method("claim") or not job_queue_port.has_method("acknowledge") or not job_queue_port.has_method("reject"):
		return ComputeUtilsScript.failure("SIMULATION_JOB_QUEUE_PORT_REQUIRED")
	_job_queue_port = job_queue_port
	_configured = true
	return ComputeUtilsScript.success()


func submit(job: Dictionary, max_attempts: int = 3, visibility_timeout_ms: int = 30000) -> Dictionary:
	if not _configured:
		return ComputeUtilsScript.failure("SIMULATION_JOB_QUEUE_BRIDGE_NOT_CONFIGURED")
	var check := SimulationJobScript.validate(job)
	if not bool(check.get("success", false)):
		return check
	var bus_job := JobEnvelopeScript.create(String(job["job_id"]), QUEUE_ID, "simulation.compute", SimulationJobScript.SCHEMA, job, max_attempts, visibility_timeout_ms)
	return _job_queue_port.submit(bus_job)


func claim(worker_id: String) -> Dictionary:
	if not _configured:
		return ComputeUtilsScript.failure("SIMULATION_JOB_QUEUE_BRIDGE_NOT_CONFIGURED")
	var claimed: Dictionary = _job_queue_port.claim(QUEUE_ID, worker_id)
	if not bool(claimed.get("success", false)):
		return claimed
	if String(claimed.get("outcome", "")) == "EMPTY":
		return claimed
	var delivery: Dictionary = claimed.get("details", {}).get("delivery", {})
	var bus_job: Dictionary = delivery.get("job", {})
	if String(bus_job.get("payload_schema", "")) != SimulationJobScript.SCHEMA or typeof(bus_job.get("payload")) != TYPE_DICTIONARY:
		return ComputeUtilsScript.failure("SIMULATION_JOB_QUEUE_PAYLOAD_MISMATCH")
	var job_check := SimulationJobScript.validate(bus_job["payload"])
	if not bool(job_check.get("success", false)):
		return job_check
	return ComputeUtilsScript.success({"delivery_id": delivery["delivery_id"], "worker_id": delivery["worker_id"], "attempt": delivery["attempt"], "job": bus_job["payload"].duplicate(true)})


func acknowledge(delivery_id: String, worker_id: String) -> Dictionary:
	if not _configured:
		return ComputeUtilsScript.failure("SIMULATION_JOB_QUEUE_BRIDGE_NOT_CONFIGURED")
	return _job_queue_port.acknowledge(delivery_id, worker_id)


func reject(delivery_id: String, worker_id: String, retryable: bool) -> Dictionary:
	if not _configured:
		return ComputeUtilsScript.failure("SIMULATION_JOB_QUEUE_BRIDGE_NOT_CONFIGURED")
	return _job_queue_port.reject(delivery_id, worker_id, retryable)

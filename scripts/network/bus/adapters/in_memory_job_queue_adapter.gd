extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const BusUtilsScript = preload("res://scripts/network/bus/message_bus_contract_utils.gd")
const ResultScript = preload("res://scripts/network/bus/bus_operation_result.gd")
const DescriptorScript = preload("res://scripts/network/bus/semantic_port_descriptor.gd")
const JobScript = preload("res://scripts/network/bus/job_envelope.gd")
const DeliveryScript = preload("res://scripts/network/bus/job_delivery_envelope.gd")

var _adapter_id: String
var _max_pending_per_queue: int
var _queues: Dictionary = {}
var _job_records: Dictionary = {}
var _deliveries: Dictionary = {}
var _delivery_sequence: int = 0


func _init(adapter_id: String = "adapter/in-memory-job-queue", max_pending_per_queue: int = 128) -> void:
	_adapter_id = adapter_id
	_max_pending_per_queue = maxi(1, max_pending_per_queue)


func get_descriptor() -> Dictionary:
	return DescriptorScript.create("JOB_QUEUE", _adapter_id, ["acknowledgement", "bounded_queue", "idempotent_job_id", "retry"])


func submit(job_value: Dictionary) -> Dictionary:
	var check: Dictionary = JobScript.validate(job_value)
	if not bool(check.get("success", false)):
		return ResultScript.failure("REJECTED", String(check.get("error_code", "INVALID_JOB")), false)
	var job_id: String = String(job_value["job_id"])
	var fingerprint: String = NetworkUtilsScript.payload_hash(job_value)
	if _job_records.has(job_id):
		var existing: Dictionary = _job_records[job_id]
		if String(existing.get("fingerprint", "")) == fingerprint:
			return ResultScript.success("ACCEPTED", {"duplicate": true, "state": existing.get("state", "")})
		return ResultScript.failure("REJECTED", "JOB_ID_CONFLICT", false)
	var queue_id: String = String(job_value["queue_id"])
	var queue: Array = _queues.get(queue_id, [])
	if queue.size() >= _max_pending_per_queue:
		return ResultScript.failure("BACKPRESSURE", "JOB_QUEUE_CAPACITY", true, {"queue_id": queue_id})
	var copied: Dictionary = BusUtilsScript.deep_copy_json(job_value)
	if not bool(copied.get("success", false)):
		return ResultScript.failure("REJECTED", "NON_CANONICAL_JOB", false)
	queue.append(job_id)
	_queues[queue_id] = queue
	_job_records[job_id] = {
		"fingerprint": fingerprint,
		"job": copied.get("value"),
		"attempt": 0,
		"state": "QUEUED",
	}
	return ResultScript.success("ACCEPTED", {"duplicate": false})


func claim(queue_id: String, worker_id: String) -> Dictionary:
	if not BusUtilsScript.is_canonical_id(queue_id, "queue") or not BusUtilsScript.is_canonical_id(worker_id, "worker"):
		return ResultScript.failure("REJECTED", "INVALID_CLAIM_IDENTITY", false)
	var queue: Array = _queues.get(queue_id, [])
	if queue.is_empty():
		return ResultScript.success("EMPTY", {"delivery": {}})
	var job_id: String = String(queue.pop_front())
	_queues[queue_id] = queue
	var record: Dictionary = _job_records[job_id]
	var attempt: int = int(record.get("attempt", 0)) + 1
	if attempt > int(record.get("job", {}).get("max_attempts", 0)):
		record["state"] = "FAILED"
		_job_records[job_id] = record
		return ResultScript.failure("FAILED", "JOB_ATTEMPT_LIMIT", false, {"job_id": job_id})
	_delivery_sequence += 1
	var delivery_id := "delivery/in-memory/%d" % _delivery_sequence
	var delivery: Dictionary = DeliveryScript.create(delivery_id, worker_id, attempt, record["job"])
	var delivery_check: Dictionary = DeliveryScript.validate(delivery)
	if not bool(delivery_check.get("success", false)):
		return ResultScript.failure("FAILED", String(delivery_check.get("error_code", "INVALID_DELIVERY")), false)
	record["attempt"] = attempt
	record["state"] = "IN_FLIGHT"
	_job_records[job_id] = record
	_deliveries[delivery_id] = {"job_id": job_id, "worker_id": worker_id, "queue_id": queue_id}
	return ResultScript.success("AVAILABLE", {"delivery": delivery})


func acknowledge(delivery_id: String, worker_id: String) -> Dictionary:
	var delivery_check: Dictionary = _get_delivery(delivery_id, worker_id)
	if not bool(delivery_check.get("success", false)):
		return delivery_check
	var info: Dictionary = _deliveries[delivery_id]
	var job_id: String = String(info["job_id"])
	var record: Dictionary = _job_records[job_id]
	record["state"] = "COMPLETED"
	_job_records[job_id] = record
	_deliveries.erase(delivery_id)
	return ResultScript.success("ACKNOWLEDGED", {"job_id": job_id})


func reject(delivery_id: String, worker_id: String, retryable: bool) -> Dictionary:
	var delivery_check: Dictionary = _get_delivery(delivery_id, worker_id)
	if not bool(delivery_check.get("success", false)):
		return delivery_check
	var info: Dictionary = _deliveries[delivery_id]
	var job_id: String = String(info["job_id"])
	var queue_id: String = String(info["queue_id"])
	var record: Dictionary = _job_records[job_id]
	_deliveries.erase(delivery_id)
	if retryable and int(record.get("attempt", 0)) < int(record.get("job", {}).get("max_attempts", 0)):
		var queue: Array = _queues.get(queue_id, [])
		if queue.size() >= _max_pending_per_queue:
			record["state"] = "IN_FLIGHT"
			_job_records[job_id] = record
			_deliveries[delivery_id] = info
			return ResultScript.failure("BACKPRESSURE", "JOB_QUEUE_CAPACITY", true, {"queue_id": queue_id})
		queue.append(job_id)
		_queues[queue_id] = queue
		record["state"] = "QUEUED"
		_job_records[job_id] = record
		return ResultScript.success("ACCEPTED", {"job_id": job_id, "requeued": true})
	record["state"] = "FAILED"
	_job_records[job_id] = record
	return ResultScript.success("COMPLETED", {"job_id": job_id, "requeued": false})


func _get_delivery(delivery_id: String, worker_id: String) -> Dictionary:
	if not BusUtilsScript.is_canonical_id(delivery_id, "delivery") or not BusUtilsScript.is_canonical_id(worker_id, "worker"):
		return ResultScript.failure("REJECTED", "INVALID_DELIVERY_IDENTITY", false)
	if not _deliveries.has(delivery_id):
		return ResultScript.failure("NOT_FOUND", "DELIVERY_NOT_FOUND", false)
	if String(_deliveries[delivery_id].get("worker_id", "")) != worker_id:
		return ResultScript.failure("REJECTED", "DELIVERY_WORKER_MISMATCH", false)
	return ResultScript.success()

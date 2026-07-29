extends RefCounted

const ResultScript = preload("res://scripts/network/bus/bus_operation_result.gd")
const DescriptorScript = preload("res://scripts/network/bus/semantic_port_descriptor.gd")

const SCHEMA := "planet_simulator.message_bus_composition.v1"

var _service_port
var _event_port
var _job_port
var _replication_port
var _bulk_port
var _configured: bool = false


func configure(service_port, event_port, job_port, replication_port, bulk_port) -> Dictionary:
	if _configured:
		return ResultScript.failure("REJECTED", "ALREADY_CONFIGURED", false)
	var checks: Array[Dictionary] = [
		_validate_port(service_port, "SERVICE_REQUEST_REPLY", ["request"]),
		_validate_port(event_port, "EVENT_STREAM", ["publish", "read"]),
		_validate_port(job_port, "JOB_QUEUE", ["submit", "claim", "acknowledge", "reject"]),
		_validate_port(replication_port, "REPLICATION_TRANSPORT", ["send", "poll"]),
		_validate_port(bulk_port, "BULK_TRANSFER", ["store", "fetch", "remove"]),
	]
	for check in checks:
		if not bool(check.get("success", false)):
			return check
	_service_port = service_port
	_event_port = event_port
	_job_port = job_port
	_replication_port = replication_port
	_bulk_port = bulk_port
	_configured = true
	return ResultScript.success("COMPLETED", {"composition": snapshot()})


func request_service(request: Dictionary) -> Dictionary:
	return _service_port.request(request) if _configured else _not_configured()


func publish_event(event: Dictionary) -> Dictionary:
	return _event_port.publish(event) if _configured else _not_configured()


func read_events(stream_id: String, after_sequence: int = 0, max_count: int = 64) -> Dictionary:
	return _event_port.read(stream_id, after_sequence, max_count) if _configured else _not_configured()


func submit_job(job: Dictionary) -> Dictionary:
	return _job_port.submit(job) if _configured else _not_configured()


func claim_job(queue_id: String, worker_id: String) -> Dictionary:
	return _job_port.claim(queue_id, worker_id) if _configured else _not_configured()


func acknowledge_job(delivery_id: String, worker_id: String) -> Dictionary:
	return _job_port.acknowledge(delivery_id, worker_id) if _configured else _not_configured()


func reject_job(delivery_id: String, worker_id: String, retryable: bool) -> Dictionary:
	return _job_port.reject(delivery_id, worker_id, retryable) if _configured else _not_configured()


func send_replication(message: Dictionary) -> Dictionary:
	return _replication_port.send(message) if _configured else _not_configured()


func poll_replication(target_peer_id: String, max_count: int = 64) -> Dictionary:
	return _replication_port.poll(target_peer_id, max_count) if _configured else _not_configured()


func store_bulk(descriptor: Dictionary, content_base64: String) -> Dictionary:
	return _bulk_port.store(descriptor, content_base64) if _configured else _not_configured()


func fetch_bulk(object_id: String) -> Dictionary:
	return _bulk_port.fetch(object_id) if _configured else _not_configured()


func remove_bulk(object_id: String) -> Dictionary:
	return _bulk_port.remove(object_id) if _configured else _not_configured()


func snapshot() -> Dictionary:
	return {
		"schema": SCHEMA,
		"configured": _configured,
		"port_kinds": [
			"SERVICE_REQUEST_REPLY",
			"EVENT_STREAM",
			"JOB_QUEUE",
			"REPLICATION_TRANSPORT",
			"BULK_TRANSFER",
		] if _configured else [],
	}


func _validate_port(port, expected_kind: String, methods: Array[String]) -> Dictionary:
	if port == null or not port.has_method("get_descriptor"):
		return ResultScript.failure("REJECTED", "INVALID_PORT", false, {"expected_kind": expected_kind})
	var descriptor = port.get_descriptor()
	if typeof(descriptor) != TYPE_DICTIONARY:
		return ResultScript.failure("REJECTED", "INVALID_PORT_DESCRIPTOR", false, {"expected_kind": expected_kind})
	var descriptor_check: Dictionary = DescriptorScript.validate(descriptor)
	if not bool(descriptor_check.get("success", false)):
		return ResultScript.failure("REJECTED", String(descriptor_check.get("error_code", "INVALID_PORT_DESCRIPTOR")), false, {"expected_kind": expected_kind})
	if String(descriptor.get("port_kind", "")) != expected_kind:
		return ResultScript.failure("REJECTED", "PORT_KIND_MISMATCH", false, {"expected_kind": expected_kind, "actual_kind": descriptor.get("port_kind", "")})
	for method_name in methods:
		if not port.has_method(method_name):
			return ResultScript.failure("REJECTED", "INVALID_PORT_METHODS", false, {"expected_kind": expected_kind, "missing_method": method_name})
	return ResultScript.success()


func _not_configured() -> Dictionary:
	return ResultScript.failure("REJECTED", "NOT_CONFIGURED", false)

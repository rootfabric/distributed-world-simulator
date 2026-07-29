extends SceneTree

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const BusUtilsScript = preload("res://scripts/network/bus/message_bus_contract_utils.gd")
const ResultScript = preload("res://scripts/network/bus/bus_operation_result.gd")
const RequestScript = preload("res://scripts/network/bus/service_request_envelope.gd")
const ResponseScript = preload("res://scripts/network/bus/service_response_envelope.gd")
const EventScript = preload("res://scripts/network/bus/event_envelope.gd")
const JobScript = preload("res://scripts/network/bus/job_envelope.gd")
const ReplicationScript = preload("res://scripts/network/bus/replication_envelope.gd")
const BulkDescriptorScript = preload("res://scripts/network/bus/bulk_object_descriptor.gd")
const CompositionScript = preload("res://scripts/network/bus/message_bus_composition_root.gd")
const DirectServiceScript = preload("res://scripts/network/bus/adapters/in_memory_service_request_reply_adapter.gd")
const RoutedServiceScript = preload("res://scripts/network/bus/adapters/routed_in_memory_service_request_reply_adapter.gd")
const DirectEventScript = preload("res://scripts/network/bus/adapters/in_memory_event_stream_adapter.gd")
const BufferedEventScript = preload("res://scripts/network/bus/adapters/buffered_in_memory_event_stream_adapter.gd")
const JobAdapterScript = preload("res://scripts/network/bus/adapters/in_memory_job_queue_adapter.gd")
const ReplicationAdapterScript = preload("res://scripts/network/bus/adapters/in_memory_replication_transport_adapter.gd")
const BulkAdapterScript = preload("res://scripts/network/bus/adapters/in_memory_bulk_transfer_adapter.gd")

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_transport_independent_workflow()
	_test_service_request_replay()
	_test_timeout_and_result_semantics()
	_test_event_idempotency_and_buffering()
	_test_job_ack_retry_semantics()
	_test_replication_backpressure_isolation()
	_test_bulk_transfer_integrity()
	_test_semantic_non_interchangeability()
	_test_deep_copy_boundaries()
	_finish()


func _test_transport_independent_workflow() -> void:
	var handler_a := _EchoHandler.new()
	var service_a = DirectServiceScript.new("adapter/in-memory-service-a")
	_assert_ok_result(service_a.register_handler("service/test/echo", handler_a, 1), "Direct service handler registration failed")
	var event_a = DirectEventScript.new("adapter/in-memory-event-a", 16)
	var result_a: Dictionary = _run_application_workflow(service_a, event_a)
	var handler_b := _EchoHandler.new()
	var service_b = RoutedServiceScript.new("adapter/in-memory-service-b")
	_assert_ok_result(service_b.add_route("service/test/echo", "service/backend/echo"), "Service route registration failed")
	_assert_ok_result(service_b.register_handler("service/backend/echo", handler_b, 1), "Routed service handler registration failed")
	var event_b = BufferedEventScript.new("adapter/in-memory-event-b", 16)
	var result_b: Dictionary = _run_application_workflow(service_b, event_b)
	_assert(String(result_a.get("response_json", "")) == String(result_b.get("response_json", "")), "Application response changed across adapters")
	_assert(String(result_a.get("event_json", "")) == String(result_b.get("event_json", "")), "Application event changed across adapters")
	_assert(handler_a.calls == 1 and handler_b.calls == 1, "Application workflow did not invoke each implementation exactly once")


func _run_application_workflow(service_port, event_port) -> Dictionary:
	var composition = _composition(service_port, event_port, JobAdapterScript.new(), ReplicationAdapterScript.new(), BulkAdapterScript.new())
	var request: Dictionary = RequestScript.create("request/workflow/1", "service/test/echo", "echo", "planet_simulator.echo_request.v1", {"value": 42, "nested": {"stable": true}}, 100)
	var request_result: Dictionary = composition.request_service(request)
	_assert_ok_result(request_result, "Application request failed")
	var response: Dictionary = request_result.get("details", {}).get("response", {})
	_assert_ok(ResponseScript.validate(response), "Application received invalid response")
	var event: Dictionary = EventScript.create("event/workflow/1", "stream/workflow/domain", "workflow.completed", 1, "producer/workflow/app", "planet_simulator.workflow_completed.v1", {"request_id": request["request_id"], "value": 42})
	_assert_ok_result(composition.publish_event(event), "Application event publish failed")
	var read_result: Dictionary = composition.read_events("stream/workflow/domain", 0, 4)
	_assert_ok_result(read_result, "Application event read failed")
	var events: Array = read_result.get("details", {}).get("events", [])
	_assert(events.size() == 1, "Application did not read exactly one event")
	return {
		"response_json": NetworkUtilsScript.canonical_json(response),
		"event_json": NetworkUtilsScript.canonical_json(events[0] if not events.is_empty() else {}),
	}


func _test_service_request_replay() -> void:
	var handler := _EchoHandler.new()
	var service = DirectServiceScript.new("adapter/service-replay")
	_assert_ok_result(service.register_handler("service/test/echo", handler), "Replay service registration failed")
	var request: Dictionary = RequestScript.create("request/replay/1", "service/test/echo", "echo", "planet_simulator.echo_request.v1", {"value": 5}, 100)
	var first: Dictionary = service.request(request)
	_assert_ok_result(first, "Initial service request failed")
	var replay: Dictionary = service.request(request)
	_assert_ok_result(replay, "Exact service request replay failed")
	_assert(bool(replay.get("details", {}).get("duplicate", false)), "Exact service request replay was not marked duplicate")
	_assert(handler.calls == 1, "Exact service request replay invoked handler twice")
	_assert(NetworkUtilsScript.canonical_json(first.get("details", {}).get("response", {})) == NetworkUtilsScript.canonical_json(replay.get("details", {}).get("response", {})), "Replayed service response changed")
	var conflict: Dictionary = request.duplicate(true)
	conflict["payload"] = {"value": 6}
	_assert_error_result(service.request(conflict), "REQUEST_ID_CONFLICT", "Conflicting service request ID accepted")


func _test_timeout_and_result_semantics() -> void:
	var service = DirectServiceScript.new()
	_assert_ok_result(service.register_handler("service/test/slow", _EchoHandler.new(), 50), "Slow service registration failed")
	var request: Dictionary = RequestScript.create("request/timeout/1", "service/test/slow", "echo", "planet_simulator.echo_request.v1", {"value": 1}, 50)
	var result: Dictionary = service.request(request)
	_assert_ok(ResultScript.validate(result), "Timeout result envelope is invalid")
	_assert(not bool(result.get("success", true)), "Timed out request reported success")
	_assert(String(result.get("outcome", "")) == "TIMEOUT" and bool(result.get("retryable", false)), "Timeout semantics are not explicit/retryable")
	_assert(String(result.get("error_code", "")) == "REQUEST_TIMEOUT", "Timeout error code mismatch")


func _test_event_idempotency_and_buffering() -> void:
	var adapter = BufferedEventScript.new("adapter/event-buffer-test", 1)
	var event1: Dictionary = EventScript.create("event/buffer/1", "stream/buffer/1", "test.created", 1, "producer/test/1", "planet_simulator.test_event.v1", {"value": 1})
	_assert_ok_result(adapter.publish(event1), "Buffered event publish failed")
	var duplicate: Dictionary = adapter.publish(event1)
	_assert_ok_result(duplicate, "Exact event replay failed")
	_assert(bool(duplicate.get("details", {}).get("duplicate", false)), "Exact event replay was not marked duplicate")
	var event2: Dictionary = EventScript.create("event/buffer/2", "stream/buffer/1", "test.updated", 2, "producer/test/1", "planet_simulator.test_event.v1", {"value": 2})
	_assert_error_result(adapter.publish(event2), "EVENT_PENDING_CAPACITY", "Buffered event backpressure did not trigger")
	var read1: Dictionary = adapter.read("stream/buffer/1", 0, 8)
	_assert_ok_result(read1, "Buffered event read/flush failed")
	_assert(read1.get("details", {}).get("events", []).size() == 1, "Buffered event was not flushed")
	_assert_ok_result(adapter.publish(event2), "Event publish did not recover after flush")
	var conflict: Dictionary = event1.duplicate(true)
	conflict["payload"] = {"value": 99}
	_assert_error_result(adapter.publish(conflict), "EVENT_ID_CONFLICT", "Conflicting event replay accepted")


func _test_job_ack_retry_semantics() -> void:
	var adapter = JobAdapterScript.new("adapter/job-test", 2)
	var job: Dictionary = JobScript.create("job/work/1", "queue/work/1", "work.compute", "planet_simulator.work_job.v1", {"input": 5}, 2, 1000)
	_assert_ok_result(adapter.submit(job), "Job submit failed")
	var duplicate: Dictionary = adapter.submit(job)
	_assert_ok_result(duplicate, "Exact job replay failed")
	_assert(bool(duplicate.get("details", {}).get("duplicate", false)), "Exact job replay was not marked duplicate")
	var claim1: Dictionary = adapter.claim("queue/work/1", "worker/test/a")
	_assert_ok_result(claim1, "Job claim failed")
	var delivery1: Dictionary = claim1.get("details", {}).get("delivery", {})
	_assert(int(delivery1.get("attempt", 0)) == 1, "First job attempt mismatch")
	_assert_ok_result(adapter.reject(String(delivery1.get("delivery_id", "")), "worker/test/a", true), "Retryable job reject failed")
	var claim2: Dictionary = adapter.claim("queue/work/1", "worker/test/b")
	_assert_ok_result(claim2, "Retried job claim failed")
	var delivery2: Dictionary = claim2.get("details", {}).get("delivery", {})
	_assert(int(delivery2.get("attempt", 0)) == 2, "Retried job attempt mismatch")
	_assert_error_result(adapter.acknowledge(String(delivery2.get("delivery_id", "")), "worker/test/a"), "DELIVERY_WORKER_MISMATCH", "Wrong worker acknowledged job")
	_assert_ok_result(adapter.acknowledge(String(delivery2.get("delivery_id", "")), "worker/test/b"), "Correct job acknowledgement failed")
	var empty: Dictionary = adapter.claim("queue/work/1", "worker/test/c")
	_assert_ok_result(empty, "Empty job queue claim failed")
	_assert(String(empty.get("outcome", "")) == "EMPTY", "Empty job queue did not return EMPTY outcome")


func _test_replication_backpressure_isolation() -> void:
	var adapter = ReplicationAdapterScript.new("adapter/replication-test", 1)
	var a1: Dictionary = _replication("replication/a/1", "peer/client/a", 1)
	var a2: Dictionary = _replication("replication/a/2", "peer/client/a", 2)
	var b1: Dictionary = _replication("replication/b/1", "peer/client/b", 1)
	_assert_ok_result(adapter.send(a1), "Peer A first replication failed")
	var backpressure: Dictionary = adapter.send(a2)
	_assert_error_result(backpressure, "REPLICATION_PEER_CAPACITY", "Peer A backpressure did not trigger")
	_assert(String(backpressure.get("outcome", "")) == "BACKPRESSURE" and bool(backpressure.get("retryable", false)), "Replication backpressure semantics are not explicit")
	_assert_ok_result(adapter.send(b1), "Peer B was blocked by peer A capacity")
	var poll_b: Dictionary = adapter.poll("peer/client/b", 8)
	_assert_ok_result(poll_b, "Peer B poll failed")
	_assert(poll_b.get("details", {}).get("messages", []).size() == 1, "Peer B targeted queue mismatch")
	var poll_a: Dictionary = adapter.poll("peer/client/a", 8)
	_assert_ok_result(poll_a, "Peer A poll failed")
	_assert(poll_a.get("details", {}).get("messages", []).size() == 1, "Peer A targeted queue mismatch")
	_assert_ok_result(adapter.send(a2), "Peer A did not recover after queue drain")


func _test_bulk_transfer_integrity() -> void:
	var bytes: PackedByteArray = "transport-independent-bulk".to_utf8_buffer()
	var content_base64: String = Marshalls.raw_to_base64(bytes)
	var descriptor: Dictionary = BulkDescriptorScript.create("object/test/bulk/1", "planet_simulator.test_blob.v1", BusUtilsScript.content_hash_from_bytes(bytes), bytes.size())
	var adapter = BulkAdapterScript.new("adapter/bulk-test", bytes.size())
	_assert_ok_result(adapter.store(descriptor, content_base64), "Bulk store failed")
	var fetched: Dictionary = adapter.fetch("object/test/bulk/1")
	_assert_ok_result(fetched, "Bulk fetch failed")
	_assert(String(fetched.get("details", {}).get("content_base64", "")) == content_base64, "Bulk content changed during round-trip")
	var duplicate: Dictionary = adapter.store(descriptor, content_base64)
	_assert_ok_result(duplicate, "Exact bulk replay failed")
	_assert(bool(duplicate.get("details", {}).get("duplicate", false)), "Exact bulk replay was not marked duplicate")
	var conflicting_descriptor: Dictionary = descriptor.duplicate(true)
	conflicting_descriptor["content_schema"] = "planet_simulator.other_blob.v1"
	_assert_error_result(adapter.store(conflicting_descriptor, content_base64), "BULK_OBJECT_CONFLICT", "Same object ID with changed descriptor accepted")
	_assert_error_result(adapter.store(descriptor, content_base64 + "="), "NON_CANONICAL_BASE64", "Non-canonical base64 accepted")
	var other_bytes: PackedByteArray = "x".to_utf8_buffer()
	var other_descriptor: Dictionary = BulkDescriptorScript.create("object/test/bulk/2", "planet_simulator.test_blob.v1", BusUtilsScript.content_hash_from_bytes(other_bytes), other_bytes.size())
	_assert_error_result(adapter.store(other_descriptor, Marshalls.raw_to_base64(other_bytes)), "BULK_CAPACITY", "Bulk capacity backpressure did not trigger")
	_assert_ok_result(adapter.remove("object/test/bulk/1"), "Bulk remove failed")
	_assert_error_result(adapter.fetch("object/test/bulk/1"), "BULK_OBJECT_NOT_FOUND", "Removed bulk object remained available")


func _test_semantic_non_interchangeability() -> void:
	var job_adapter = JobAdapterScript.new()
	var event: Dictionary = EventScript.create("event/wrong/1", "stream/wrong/1", "wrong.event", 1, "producer/wrong/1", "planet_simulator.wrong.v1", {})
	_assert_error_result(job_adapter.submit(event), "MISSING_FIELD", "Event envelope was accepted as a job")
	var replication_adapter = ReplicationAdapterScript.new()
	var job: Dictionary = JobScript.create("job/wrong/1", "queue/wrong/1", "wrong.job", "planet_simulator.wrong.v1", {}, 1, 100)
	_assert_error_result(replication_adapter.send(job), "MISSING_FIELD", "Job envelope was accepted as replication")
	var composition = CompositionScript.new()
	var wrong = composition.configure(DirectEventScript.new(), DirectServiceScript.new(), job_adapter, replication_adapter, BulkAdapterScript.new())
	_assert_error_result(wrong, "PORT_KIND_MISMATCH", "Composition accepted swapped semantic ports")


func _test_deep_copy_boundaries() -> void:
	var handler := _EchoHandler.new()
	var service = DirectServiceScript.new()
	_assert_ok_result(service.register_handler("service/test/echo", handler), "Deep-copy handler registration failed")
	var request: Dictionary = RequestScript.create("request/copy/1", "service/test/echo", "echo", "planet_simulator.echo_request.v1", {"nested": {"value": 1}}, 100)
	var result: Dictionary = service.request(request)
	request["payload"]["nested"]["value"] = 999
	var response: Dictionary = result.get("details", {}).get("response", {})
	_assert(int(response.get("payload", {}).get("nested", {}).get("value", 0)) == 1, "Service response aliases caller request payload")
	response["payload"]["nested"]["value"] = 777
	var second: Dictionary = service.request(RequestScript.create("request/copy/2", "service/test/echo", "echo", "planet_simulator.echo_request.v1", {"nested": {"value": 2}}, 100))
	_assert(int(second.get("details", {}).get("response", {}).get("payload", {}).get("nested", {}).get("value", 0)) == 2, "Caller mutation contaminated adapter state")
	var composition = _composition(service, DirectEventScript.new(), JobAdapterScript.new(), ReplicationAdapterScript.new(), BulkAdapterScript.new())
	var snapshot_json: String = NetworkUtilsScript.canonical_json(composition.snapshot())
	_assert(not snapshot_json.contains("subject") and not snapshot_json.contains("channel") and not snapshot_json.contains("broker"), "Composition state leaked adapter routing metadata")


func _composition(service, event, job, replication, bulk):
	var composition = CompositionScript.new()
	_assert_ok_result(composition.configure(service, event, job, replication, bulk), "Composition configuration failed")
	return composition


func _replication(replication_id: String, peer_id: String, sequence: int) -> Dictionary:
	return ReplicationScript.create(replication_id, "source/test/server", peer_id, "DELTA", sequence, "planet_simulator.test_delta.v1", {"revision": sequence})


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert_ok_result(result: Dictionary, message: String) -> void:
	_assert_ok(ResultScript.validate(result), "%s result envelope invalid" % message)
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert_error_result(result: Dictionary, error_code: String, message: String) -> void:
	_assert_ok(ResultScript.validate(result), "%s result envelope invalid" % message)
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == error_code, "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("B0 message bus integration: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("B0 message bus integration: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)


class _EchoHandler:
	extends RefCounted
	var calls: int = 0
	func handle_service_request(request: Dictionary) -> Dictionary:
		calls += 1
		return ResponseScript.create_success(
			"response/%s" % String(request.get("request_id", "request/unknown")).trim_prefix("request/"),
			String(request.get("request_id", "")),
			"planet_simulator.echo_response.v1",
			request.get("payload", {}).duplicate(true)
		)

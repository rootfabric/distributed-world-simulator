extends SceneTree

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const BusUtilsScript = preload("res://scripts/network/bus/message_bus_contract_utils.gd")
const ResultScript = preload("res://scripts/network/bus/bus_operation_result.gd")
const DescriptorScript = preload("res://scripts/network/bus/semantic_port_descriptor.gd")
const RequestScript = preload("res://scripts/network/bus/service_request_envelope.gd")
const ResponseScript = preload("res://scripts/network/bus/service_response_envelope.gd")
const EventScript = preload("res://scripts/network/bus/event_envelope.gd")
const JobScript = preload("res://scripts/network/bus/job_envelope.gd")
const DeliveryScript = preload("res://scripts/network/bus/job_delivery_envelope.gd")
const ReplicationScript = preload("res://scripts/network/bus/replication_envelope.gd")
const BulkDescriptorScript = preload("res://scripts/network/bus/bulk_object_descriptor.gd")
const CompositionScript = preload("res://scripts/network/bus/message_bus_composition_root.gd")
const DirectServiceScript = preload("res://scripts/network/bus/adapters/in_memory_service_request_reply_adapter.gd")
const DirectEventScript = preload("res://scripts/network/bus/adapters/in_memory_event_stream_adapter.gd")
const JobAdapterScript = preload("res://scripts/network/bus/adapters/in_memory_job_queue_adapter.gd")
const ReplicationAdapterScript = preload("res://scripts/network/bus/adapters/in_memory_replication_transport_adapter.gd")
const BulkAdapterScript = preload("res://scripts/network/bus/adapters/in_memory_bulk_transfer_adapter.gd")

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_result_contract()
	_test_semantic_port_descriptor()
	_test_service_contracts()
	_test_event_contract()
	_test_job_contracts()
	_test_replication_contract()
	_test_bulk_contract()
	_test_composition_separation()
	_test_project_wiring()
	_finish()


func _test_result_contract() -> void:
	var delivered: Dictionary = ResultScript.success("DELIVERED", {"count": 1})
	_assert_ok(ResultScript.validate(delivered), "Valid delivered result rejected")
	var timeout: Dictionary = ResultScript.failure("TIMEOUT", "REQUEST_TIMEOUT", true, {"elapsed_ms": 20})
	_assert_ok(ResultScript.validate(timeout), "Valid timeout result rejected")
	_assert(bool(timeout.get("retryable", false)), "Timeout result lost retryable semantics")
	var backpressure: Dictionary = ResultScript.failure("BACKPRESSURE", "QUEUE_CAPACITY", true)
	_assert_ok(ResultScript.validate(backpressure), "Valid backpressure result rejected")
	var inconsistent_success: Dictionary = delivered.duplicate(true)
	inconsistent_success["retryable"] = true
	_assert_fail(ResultScript.validate(inconsistent_success), "Successful retryable result accepted")
	var inconsistent_failure: Dictionary = timeout.duplicate(true)
	inconsistent_failure["error_code"] = ""
	_assert_fail(ResultScript.validate(inconsistent_failure), "Failure without error_code accepted")
	var unknown_outcome: Dictionary = timeout.duplicate(true)
	unknown_outcome["outcome"] = "RETRY_LATER"
	_assert_fail(ResultScript.validate(unknown_outcome), "Unknown result outcome accepted")
	var extra: Dictionary = delivered.duplicate(true)
	extra["subject"] = "forbidden"
	_assert_fail(ResultScript.validate(extra), "Unexpected result field accepted")


func _test_semantic_port_descriptor() -> void:
	for kind in DescriptorScript.PORT_KINDS:
		var descriptor: Dictionary = DescriptorScript.create(kind, "adapter/test-%s" % String(kind).to_lower(), ["canonical", "strict"])
		_assert_ok(DescriptorScript.validate(descriptor), "Valid descriptor rejected for %s" % kind)
	var unsorted: Dictionary = DescriptorScript.create("EVENT_STREAM", "adapter/test-event", ["zeta", "alpha"])
	unsorted["capabilities"] = ["zeta", "alpha"]
	_assert_fail(DescriptorScript.validate(unsorted), "Unsorted capabilities accepted")
	var duplicate: Dictionary = DescriptorScript.create("EVENT_STREAM", "adapter/test-event", ["alpha", "alpha"])
	_assert_fail(DescriptorScript.validate(duplicate), "Duplicate capabilities accepted")
	var bad_adapter: Dictionary = DescriptorScript.create("EVENT_STREAM", "nats://events", [])
	_assert_fail(DescriptorScript.validate(bad_adapter), "Adapter-specific route accepted as adapter identity")


func _test_service_contracts() -> void:
	var request: Dictionary = _valid_request()
	_assert_ok(RequestScript.validate(request), "Valid service request rejected")
	var round_trip: Dictionary = NetworkUtilsScript.json_round_trip(request)
	_assert(bool(round_trip.get("success", false)) and NetworkUtilsScript.canonical_json(round_trip.get("value")) == NetworkUtilsScript.canonical_json(request), "Service request did not survive exact JSON round-trip")
	var forbidden: Dictionary = request.duplicate(true)
	forbidden["payload"] = {"nested": {"nats_subject": "ps.world.request"}}
	_assert_error(RequestScript.validate(forbidden), "ADAPTER_METADATA_FORBIDDEN", "NATS subject leaked into service payload")
	var runtime_payload: Dictionary = request.duplicate(true)
	var runtime_node := Node.new()
	runtime_payload["payload"] = {"node": runtime_node}
	_assert_error(RequestScript.validate(runtime_payload), "NON_CANONICAL_PAYLOAD", "Runtime object accepted in service payload")
	runtime_node.free()
	var no_timeout: Dictionary = request.duplicate(true)
	no_timeout["timeout_ms"] = 0
	_assert_error(RequestScript.validate(no_timeout), "INVALID_TIMEOUT", "Zero request timeout accepted")
	var unexpected: Dictionary = request.duplicate(true)
	unexpected["broker_id"] = "broker/a"
	_assert_fail(RequestScript.validate(unexpected), "Unexpected request field accepted")
	var response: Dictionary = ResponseScript.create_success("response/echo/1", String(request["request_id"]), "planet_simulator.echo_response.v1", {"value": 7})
	_assert_ok(ResponseScript.validate(response), "Valid service response rejected")
	var bad_response: Dictionary = response.duplicate(true)
	bad_response["success"] = false
	_assert_fail(ResponseScript.validate(bad_response), "Failed response without error_code accepted")


func _test_event_contract() -> void:
	var event: Dictionary = _valid_event()
	_assert_ok(EventScript.validate(event), "Valid event rejected")
	var zero_sequence: Dictionary = event.duplicate(true)
	zero_sequence["sequence"] = 0
	_assert_error(EventScript.validate(zero_sequence), "INVALID_SEQUENCE", "Zero event sequence accepted")
	var adapter_field: Dictionary = event.duplicate(true)
	adapter_field["payload"] = {"broker_message_id": "123"}
	_assert_error(EventScript.validate(adapter_field), "ADAPTER_METADATA_FORBIDDEN", "Broker message ID accepted in event payload")
	var wrong_schema: Dictionary = event.duplicate(true)
	wrong_schema["payload_schema"] = "event.payload"
	_assert_error(EventScript.validate(wrong_schema), "INVALID_PAYLOAD_SCHEMA", "Non-versioned event payload schema accepted")


func _test_job_contracts() -> void:
	var job: Dictionary = _valid_job()
	_assert_ok(JobScript.validate(job), "Valid job rejected")
	var delivery: Dictionary = DeliveryScript.create("delivery/test/1", "worker/test/1", 1, job)
	_assert_ok(DeliveryScript.validate(delivery), "Valid job delivery rejected")
	var exhausted: Dictionary = delivery.duplicate(true)
	exhausted["attempt"] = 4
	_assert_error(DeliveryScript.validate(exhausted), "ATTEMPT_LIMIT_EXCEEDED", "Delivery beyond max attempts accepted")
	var invalid_queue: Dictionary = job.duplicate(true)
	invalid_queue["queue_id"] = "stream/jobs"
	_assert_error(JobScript.validate(invalid_queue), "INVALID_JOB_IDENTITY", "Event stream identity accepted as job queue")
	var huge_attempts: Dictionary = job.duplicate(true)
	huge_attempts["max_attempts"] = 101
	_assert_error(JobScript.validate(huge_attempts), "INVALID_MAX_ATTEMPTS", "Unbounded job attempts accepted")


func _test_replication_contract() -> void:
	var message: Dictionary = _valid_replication("replication/test/1", "peer/client/a", 1)
	_assert_ok(ReplicationScript.validate(message), "Valid replication message rejected")
	var job_kind: Dictionary = message.duplicate(true)
	job_kind["replication_kind"] = "JOB"
	_assert_error(ReplicationScript.validate(job_kind), "INVALID_REPLICATION_KIND", "Job traffic accepted as replication")
	var transport_session: Dictionary = message.duplicate(true)
	transport_session["payload"] = {"transport_session_id": "transport-session/1"}
	_assert_error(ReplicationScript.validate(transport_session), "ADAPTER_METADATA_FORBIDDEN", "Transport session leaked into replication payload")


func _test_bulk_contract() -> void:
	var descriptor: Dictionary = BulkDescriptorScript.create("object/test/checkpoint", "planet_simulator.checkpoint_blob.v1", "a".repeat(64), 1024)
	_assert_ok(BulkDescriptorScript.validate(descriptor), "Valid bulk descriptor rejected")
	var upper_hash: Dictionary = descriptor.duplicate(true)
	upper_hash["content_hash"] = "A".repeat(64)
	_assert_error(BulkDescriptorScript.validate(upper_hash), "INVALID_CONTENT_HASH", "Uppercase bulk hash accepted")
	var negative_size: Dictionary = descriptor.duplicate(true)
	negative_size["size_bytes"] = -1
	_assert_error(BulkDescriptorScript.validate(negative_size), "INVALID_SIZE", "Negative bulk size accepted")


func _test_composition_separation() -> void:
	var service = DirectServiceScript.new()
	var event = DirectEventScript.new()
	var job = JobAdapterScript.new()
	var replication = ReplicationAdapterScript.new()
	var bulk = BulkAdapterScript.new()
	var composition = CompositionScript.new()
	_assert_ok_result(composition.configure(service, event, job, replication, bulk), "Valid semantic composition rejected")
	_assert(composition.snapshot().get("port_kinds", []).size() == 5, "Composition did not expose five semantic port kinds")
	var swapped = CompositionScript.new()
	_assert_error_result(swapped.configure(event, service, job, replication, bulk), "PORT_KIND_MISMATCH", "Service and event ports were interchangeable")
	var unconfigured = CompositionScript.new()
	_assert_error_result(unconfigured.publish_event(_valid_event()), "NOT_CONFIGURED", "Unconfigured composition accepted event")


func _test_project_wiring() -> void:
	var runner: String = FileAccess.get_file_as_string("res://RUN_B0_MESSAGE_BUS_TESTS.ps1")
	var network_runner: String = FileAccess.get_file_as_string("res://RUN_NETWORK_CONTRACT_TESTS.ps1")
	var world_runner: String = FileAccess.get_file_as_string("res://RUN_WORLD_REGRESSION_TESTS.ps1")
	var architecture: String = FileAccess.get_file_as_string("res://docs/architecture/B0_TRANSPORT_INDEPENDENT_MESSAGE_BUS_RU.md")
	var roadmap_text: String = FileAccess.get_file_as_string("res://config/network/network-roadmap.v1.json")
	_assert(not runner.is_empty(), "B0 PowerShell runner is missing")
	_assert(runner.contains("function Write-JsonFileAtomically") and runner.contains("$Stream.Flush($true)"), "B0 runner lacks atomic summary publishing")
	_assert(runner.contains("PSNativeCommandUseErrorActionPreference"), "B0 runner is not stderr-safe")
	_assert(network_runner.contains("test_b0_message_bus_contracts.gd") and network_runner.contains("test_b0_message_bus_integration.gd"), "Network runner does not include B0 suites")
	_assert(world_runner.contains("test_b0_message_bus_contracts.gd") and world_runner.contains("test_b0_message_bus_integration.gd"), "World runner does not include B0 suites")
	_assert(architecture.contains("ServiceRequestReplyPort") and architecture.contains("BulkTransferPort"), "B0 architecture does not document all semantic families")
	var roadmap = JSON.parse_string(roadmap_text)
	_assert(roadmap is Dictionary, "Network roadmap JSON is invalid")
	if roadmap is Dictionary:
		_assert(String(roadmap.get("project_checkpoint", "")) == "v16.10.0-runtime-m1-unified-networked-gameplay-core", "Network roadmap checkpoint is stale")
		var statuses: Dictionary = {}
		for phase in roadmap.get("phases", []):
			statuses[String(phase.get("id", ""))] = String(phase.get("status", ""))
		_assert(String(statuses.get("T1", "")) == "accepted" and String(statuses.get("B0", "")) == "accepted" and String(statuses.get("M0", "")) == "accepted" and String(statuses.get("S1", "")) == "accepted", "Foundation phase statuses are inconsistent")
	var bus_sources: Array[String] = [
		"res://scripts/network/bus/message_bus_composition_root.gd",
		"res://scripts/network/bus/adapters/in_memory_service_request_reply_adapter.gd",
		"res://scripts/network/bus/adapters/in_memory_event_stream_adapter.gd",
	]
	for source_path in bus_sources:
		var source: String = FileAccess.get_file_as_string(source_path).to_lower()
		_assert(not source.contains("nats.connect") and not source.contains("enetmultiplayerpeer") and not source.contains("jetstream"), "B0 source depends on concrete transport SDK: %s" % source_path)


func _valid_request() -> Dictionary:
	return RequestScript.create("request/test/echo/1", "service/test/echo", "echo", "planet_simulator.echo_request.v1", {"value": 7}, 100)


func _valid_event() -> Dictionary:
	return EventScript.create("event/test/1", "stream/test/domain", "entity.updated", 1, "producer/test/authority", "planet_simulator.entity_updated.v1", {"entity_id": "entity/test/1"})


func _valid_job() -> Dictionary:
	return JobScript.create("job/test/1", "queue/test/simulation", "simulation.advance", "planet_simulator.test_job.v1", {"target_id": "aggregate/test/1"}, 3, 1000)


func _valid_replication(replication_id: String, peer_id: String, sequence: int) -> Dictionary:
	return ReplicationScript.create(replication_id, "source/test/server", peer_id, "DELTA", sequence, "planet_simulator.test_delta.v1", {"revision": sequence})


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert_fail(result: Dictionary, message: String) -> void:
	_assert(not bool(result.get("success", false)), message)


func _assert_error(result: Dictionary, error_code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == error_code, "%s: %s" % [message, result])


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
		print("B0 message bus contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("B0 message bus contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)

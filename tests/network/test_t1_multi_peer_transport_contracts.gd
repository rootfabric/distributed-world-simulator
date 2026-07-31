extends SceneTree

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const FrameScript = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")
const EventScript = preload("res://scripts/network/transports/v2/network_transport_event.gd")
const SessionScript = preload("res://scripts/network/transports/v2/network_peer_session.gd")
const BoundaryScript = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const LoopbackScript = preload("res://scripts/network/transports/v2/loopback_multi_peer_transport_port.gd")
const CompatibilityScript = preload("res://scripts/network/transports/v2/single_peer_transport_compatibility_adapter.gd")
const LegacyLoopbackScript = preload("res://scripts/network/transports/loopback_transport_port.gd")

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	_test_protocol_frame()
	_test_transport_event()
	_test_peer_session()
	_test_multi_peer_boundary()
	_test_single_peer_compatibility()
	_test_project_wiring()
	_finish()


func _test_protocol_frame() -> void:
	var frame: Dictionary = FrameScript.create(
		"frame/test/a/1", "transport-session/test/a", 1, "CONTROL", "RELIABLE_ORDERED",
		"planet_simulator.t1.probe.v1", {"probe": "a"}
	)
	_assert(_ok(FrameScript.validate(frame)), "Valid protocol frame was rejected")
	var encoded: Dictionary = FrameScript.encode(frame)
	_assert(_ok(encoded), "Valid protocol frame did not encode")
	var decoded: Dictionary = FrameScript.decode(encoded.get("details", {}).get("packet", PackedByteArray()))
	_assert(_ok(decoded), "Valid protocol frame did not decode")
	_assert(UtilsScript.canonical_json(decoded.get("details", {}).get("frame", {})) == UtilsScript.canonical_json(frame), "Protocol frame changed across encoding")
	var bad_channel: Dictionary = frame.duplicate(true)
	bad_channel["channel"] = "UNKNOWN"
	_assert(_error(FrameScript.validate(bad_channel)) == "INVALID_CHANNEL", "Unknown protocol channel was accepted")
	var bad_session: Dictionary = frame.duplicate(true)
	bad_session["session_id"] = "session/a"
	_assert(_error(FrameScript.validate(bad_session)) == "INVALID_SESSION_ID", "Invalid transport session ID was accepted")
	var bad_sequence: Dictionary = frame.duplicate(true)
	bad_sequence["sequence"] = 0
	_assert(_error(FrameScript.validate(bad_sequence)) == "INVALID_SEQUENCE", "Zero frame sequence was accepted")
	var bad_hash: Dictionary = frame.duplicate(true)
	bad_hash["payload"]["probe"] = "mutated"
	_assert(_error(FrameScript.validate(bad_hash)) == "PAYLOAD_CHECKSUM_MISMATCH", "Payload mutation with stale checksum was accepted")
	var extra: Dictionary = frame.duplicate(true)
	extra["subject"] = "nats.subject.must.not.be.domain"
	_assert(_error(FrameScript.validate(extra)) == "UNEXPECTED_FIELD", "Unexpected transport-specific frame field was accepted")
	var forbidden := Node.new()
	var unsafe: Dictionary = FrameScript.create(
		"frame/test/a/2", "transport-session/test/a", 2, "STATE", "RELIABLE_ORDERED",
		"planet_simulator.t1.probe.v1", {"node": forbidden}
	)
	_assert(_error(FrameScript.validate(unsafe)) == "EMPTY_FIELD", "Runtime object payload was accepted")
	forbidden.free()


func _test_transport_event() -> void:
	var frame: Dictionary = FrameScript.create(
		"frame/test/event/1", "transport-session/test/event", 1, "STATE", "RELIABLE_ORDERED",
		"planet_simulator.t1.probe.v1", {"value": 1}
	)
	var event: Dictionary = EventScript.create(
		"transport-event/test/1", "MESSAGE_RECEIVED", "peer/test/a", "transport-session/test/event", 1, frame
	)
	_assert(_ok(EventScript.validate(event)), "Valid transport event was rejected")
	var no_peer: Dictionary = event.duplicate(true)
	no_peer["peer_id"] = ""
	_assert(_error(EventScript.validate(no_peer)) == "INVALID_PEER_ID", "Peer event without peer ID was accepted")
	var mismatch: Dictionary = event.duplicate(true)
	mismatch["session_id"] = "transport-session/test/other"
	_assert(_error(EventScript.validate(mismatch)) == "EVENT_SESSION_MISMATCH", "Event/frame session mismatch was accepted")
	var unknown: Dictionary = event.duplicate(true)
	unknown["event_type"] = "BROKER_MESSAGE"
	_assert(_error(EventScript.validate(unknown)) == "INVALID_EVENT_TYPE", "Adapter-specific event type was accepted")


func _test_peer_session() -> void:
	var session = SessionScript.new()
	_assert(_ok(session.configure("peer/test/a", "transport-session/test/a", "route/test/a", 1, 2, 128)), "Peer session configuration failed")
	_assert(_error(session.transition(SessionScript.STATE_READY)) == "INVALID_PEER_STATE_TRANSITION", "CONNECTING transitioned directly to READY")
	_assert(_ok(session.transition(SessionScript.STATE_TRANSPORT_CONNECTED)), "Peer did not enter TRANSPORT_CONNECTED")
	_assert(_ok(session.transition(SessionScript.STATE_HANDSHAKING)), "Peer did not enter HANDSHAKING")
	_assert(_ok(session.transition(SessionScript.STATE_SYNCHRONIZING)), "Peer did not enter SYNCHRONIZING")
	_assert(_ok(session.transition(SessionScript.STATE_READY)), "Peer did not enter READY")
	_assert(_ok(session.update_route("route/test/a", 1)), "Exact route replay failed")
	_assert(_error(session.update_route("route/test/b", 1)) == "ROUTE_CHANGED_WITHOUT_GENERATION", "Route changed without generation increase")
	_assert(_ok(session.update_route("route/test/b", 2)), "Route change with generation increase failed")
	_assert(_error(session.update_route("route/test/a", 1)) == "STALE_ROUTE_GENERATION", "Route generation rollback was accepted")
	_assert(session.peek_next_outgoing_sequence() == 1, "First outgoing sequence preview is incorrect")
	_assert(_ok(session.commit_outgoing_sequence(1)), "First outgoing sequence commit failed")
	_assert(session.peek_next_outgoing_sequence() == 2, "Second outgoing sequence preview is incorrect")
	_assert(_error(session.commit_outgoing_sequence(1)) == "STALE_OR_DUPLICATE_OUTGOING_FRAME", "Duplicate outgoing sequence was accepted")
	_assert(_error(session.commit_outgoing_sequence(3)) == "OUTGOING_FRAME_SEQUENCE_GAP", "Outgoing sequence gap was accepted")
	_assert(_ok(session.commit_outgoing_sequence(2)), "Second outgoing sequence commit failed")
	_assert(_ok(session.accept_incoming_sequence(1)), "First incoming sequence was rejected")
	_assert(_error(session.accept_incoming_sequence(1)) == "STALE_OR_DUPLICATE_FRAME", "Duplicate incoming sequence was accepted")
	_assert(_error(session.accept_incoming_sequence(3)) == "FRAME_SEQUENCE_GAP", "Incoming sequence gap was accepted")
	_assert(_ok(session.reserve_queue(64)), "First queue reservation failed")
	_assert(_ok(session.reserve_queue(64)), "Second queue reservation failed")
	_assert(_error(session.reserve_queue(1)) == "PEER_QUEUE_MESSAGE_LIMIT", "Per-peer message limit was not enforced")
	session.release_queue(64)
	session.release_queue(64)
	_assert(int(session.snapshot()["queued_messages"]) == 0, "Peer queue message metric did not recover")
	_assert(int(session.snapshot()["queued_bytes"]) == 0, "Peer queue byte metric did not recover")


func _test_multi_peer_boundary() -> void:
	var port = LoopbackScript.new()
	var boundary = BoundaryScript.new()
	_assert(_ok(boundary.configure(port, 2048, 2, 4096)), "T1 boundary configuration failed")
	_assert(_ok(boundary.start_server({"transport": "LOOPBACK", "name": "t1"})), "T1 listener start failed")
	_assert(String(boundary.get_snapshot()["state"]) == BoundaryScript.STATE_LISTENING, "Listener did not enter LISTENING")
	_assert(_ok(port.attach_peer("peer/test/a", "transport-session/test/a", "route/test/a", 1)), "Peer A attach failed")
	_assert(_ok(port.attach_peer("peer/test/b", "transport-session/test/b", "route/test/b", 1)), "Peer B attach failed")
	var events: Dictionary = boundary.poll_events(8)
	_assert(_ok(events), "Peer connect event polling failed")
	_assert(boundary.get_connected_peers() == ["peer/test/a", "peer/test/b"], "Connected peer list is incorrect")
	_assert(String(boundary.get_snapshot()["state"]) == BoundaryScript.STATE_LISTENING, "Peer connections changed listener lifecycle")
	for peer_id in boundary.get_connected_peers():
		_assert(_ok(boundary.mark_peer_handshaking(peer_id)), "Peer did not enter HANDSHAKING: %s" % peer_id)
		_assert(_ok(boundary.mark_peer_synchronizing(peer_id)), "Peer did not enter SYNCHRONIZING: %s" % peer_id)
		_assert(_ok(boundary.mark_peer_ready(peer_id)), "Peer did not enter READY: %s" % peer_id)
	var a_frame_result: Dictionary = boundary.create_frame_for_peer(
		"peer/test/a", "STATE", "planet_simulator.t1.targeted.v1", {"target": "a", "ordinal": 1}
	)
	_assert(_ok(a_frame_result), "Peer A frame creation failed")
	_assert(_ok(boundary.send_to_peer("peer/test/a", a_frame_result.get("details", {}).get("frame", {}))), "First queued send to peer A failed")
	_assert(port.get_messages_for_peer("peer/test/a").is_empty(), "Boundary bypassed the outbound queue for peer A")
	_assert(int(boundary.get_peer_snapshot("peer/test/a")["queued_messages"]) == 1, "Peer A queue did not retain its first pending frame")
	var a_frame_two: Dictionary = boundary.create_frame_for_peer(
		"peer/test/a", "STATE", "planet_simulator.t1.targeted.v1", {"target": "a", "ordinal": 2}
	)
	_assert(_ok(boundary.send_to_peer("peer/test/a", a_frame_two.get("details", {}).get("frame", {}))), "Second queued send to peer A failed")
	_assert(int(boundary.get_peer_snapshot("peer/test/a")["queued_messages"]) == 2, "Peer A queue did not reach its configured message limit")
	var a_overflow_frame: Dictionary = boundary.create_frame_for_peer(
		"peer/test/a", "STATE", "planet_simulator.t1.targeted.v1", {"target": "a", "ordinal": 3}
	)
	_assert(_error(boundary.send_to_peer("peer/test/a", a_overflow_frame.get("details", {}).get("frame", {}))) == "PEER_QUEUE_MESSAGE_LIMIT", "Peer A queue overflow was not rejected")
	_assert(int(boundary.get_peer_snapshot("peer/test/a")["outgoing_sequence"]) == 2, "Rejected peer A frame consumed an outgoing sequence")
	var b_frame_result: Dictionary = boundary.create_frame_for_peer(
		"peer/test/b", "COMMAND", "planet_simulator.t1.targeted.v1", {"target": "b"}
	)
	_assert(_ok(boundary.send_to_peer("peer/test/b", b_frame_result.get("details", {}).get("frame", {}))), "Peer B was blocked by peer A backpressure")
	_assert(int(boundary.get_peer_snapshot("peer/test/b")["queued_messages"]) == 1, "Peer B queue did not retain its pending frame")
	_assert(int(boundary.get_snapshot()["outbound_pending_messages"]) == 3, "Global pending queue metric is incorrect")
	var flush_b: Dictionary = boundary.flush_outbound(1, "peer/test/b")
	_assert(_ok(flush_b) and int(flush_b.get("details", {}).get("dispatched", 0)) == 1, "Peer B queue did not dispatch independently")
	_assert(port.get_messages_for_peer("peer/test/b").size() == 1, "Peer B did not receive its targeted message")
	_assert(port.get_messages_for_peer("peer/test/a").is_empty(), "Flushing peer B also dispatched peer A")
	_assert(int(boundary.get_peer_snapshot("peer/test/a")["queued_messages"]) == 2, "Peer A queue was changed by peer B dispatch")
	var flush_a_one: Dictionary = boundary.flush_outbound(1, "peer/test/a")
	_assert(_ok(flush_a_one) and int(flush_a_one.get("details", {}).get("dispatched", 0)) == 1, "First peer A dispatch failed")
	_assert(port.get_messages_for_peer("peer/test/a").size() == 1, "Peer A first queued message was not delivered")
	_assert(int(boundary.get_peer_snapshot("peer/test/a")["queued_messages"]) == 1, "Peer A queue metric did not decrease after dispatch")
	var flush_a_rest: Dictionary = boundary.flush_outbound(8, "peer/test/a")
	_assert(_ok(flush_a_rest) and int(flush_a_rest.get("details", {}).get("dispatched", 0)) == 1, "Remaining peer A dispatch failed")
	_assert(port.get_messages_for_peer("peer/test/a").size() == 2, "Peer A queued messages were not fully delivered")
	_assert(int(boundary.get_peer_snapshot("peer/test/a")["queued_messages"]) == 0, "Peer A queue metric did not return to zero")
	_assert(int(boundary.get_snapshot()["outbound_pending_messages"]) == 0, "Global pending message metric did not return to zero")
	_assert(_error(boundary.send_to_peer("peer/test/a", a_frame_result.get("details", {}).get("frame", {}))) == "STALE_OR_DUPLICATE_OUTGOING_FRAME", "Duplicate outgoing frame was accepted")
	_assert(_error(boundary.update_peer_route("peer/test/a", "route/test/a2", 1)) == "ROUTE_CHANGED_WITHOUT_GENERATION", "Route changed without route generation")
	_assert(_ok(boundary.update_peer_route("peer/test/a", "route/test/a2", 2)), "Route change with generation 2 failed")
	_assert(int(boundary.get_peer_snapshot("peer/test/a")["route_generation"]) == 2, "Route generation was not retained")
	_assert(_ok(port.attach_peer("peer/test/a", "transport-session/test/a2", "route/test/a3", 2)), "Reattach event creation failed")
	_assert(_error(boundary.poll_events(4)) == "STALE_TRANSPORT_SESSION", "New session with non-increasing route generation was accepted")
	_assert(String(boundary.get_snapshot()["state"]) != BoundaryScript.STATE_FAILED, "Peer-scoped stale session failed the entire listener")
	_assert(_ok(port.attach_peer("peer/test/a", "transport-session/test/a3", "route/test/a3", 3)), "Higher-generation reattach failed")
	_assert(_ok(boundary.poll_events(4)), "Higher-generation session event failed")
	_assert(String(boundary.get_peer_snapshot("peer/test/a")["session_id"]) == "transport-session/test/a3", "New transport session was not installed")
	_assert(String(boundary.get_peer_snapshot("peer/test/b")["state"]) == SessionScript.STATE_READY, "Peer B was affected by peer A reconnect")
	_assert(_ok(boundary.mark_peer_ready("peer/test/a")), "Reconnected peer A did not become READY")
	var stale_frame: Dictionary = FrameScript.create(
		"frame/test/stale/1", "transport-session/test/a", 1, "STATE", "RELIABLE_ORDERED",
		"planet_simulator.t1.targeted.v1", {"stale": true}
	)
	_assert(_error(boundary.send_to_peer("peer/test/a", stale_frame)) == "SESSION_MISMATCH", "Old transport session sent after reconnect")
	_assert(_ok(boundary.disconnect_peer("peer/test/a")), "Peer A disconnect failed")
	_assert(String(boundary.get_snapshot()["state"]) == BoundaryScript.STATE_LISTENING, "Peer disconnect stopped listener")
	_assert(boundary.get_connected_peers() == ["peer/test/b"], "Peer B did not remain connected")
	_assert(_ok(boundary.drain()), "Listener drain failed")
	_assert(String(boundary.get_snapshot()["state"]) == BoundaryScript.STATE_DRAINING, "Listener did not enter DRAINING")
	_assert(_ok(boundary.stop()), "Listener stop failed")


func _test_single_peer_compatibility() -> void:
	var legacy = LegacyLoopbackScript.new()
	var adapter = CompatibilityScript.new()
	_assert(_ok(adapter.setup(legacy)), "Legacy compatibility adapter setup failed")
	var compatibility_descriptor: Dictionary = adapter.get_descriptor()
	_assert(bool(compatibility_descriptor.get("multi_peer", false)), "Compatibility adapter did not expose the v2 peer-addressed API")
	_assert(int(compatibility_descriptor.get("max_peers", 0)) == 1, "Single-peer compatibility adapter max peer count mismatch")
	var boundary = BoundaryScript.new()
	_assert(_ok(boundary.configure(adapter)), "Compatibility boundary configuration failed")
	_assert(_ok(boundary.connect_client(
		{"transport": "LOOPBACK"}, "peer/compat/server", "transport-session/compat/1", "route/compat/1", 1
	)), "Legacy client connect through compatibility adapter failed")
	_assert(_ok(boundary.poll_events(4)), "Legacy connect event mapping failed")
	_assert(_ok(boundary.mark_peer_ready("peer/compat/server")), "Legacy peer did not enter READY")
	var frame_result: Dictionary = boundary.create_frame_for_peer(
		"peer/compat/server", "COMMAND", "planet_simulator.compat.command.v1", {"operation_id": "operation/compat/1"}
	)
	_assert(_ok(boundary.send_to_peer("peer/compat/server", frame_result.get("details", {}).get("frame", {}))), "Legacy send through compatibility adapter failed")
	_assert(legacy.get_messages().is_empty(), "Compatibility adapter bypassed the v2 outbound queue")
	_assert(_ok(boundary.flush_outbound(1, "peer/compat/server")), "Legacy compatibility queue dispatch failed")
	var legacy_messages: Array[Dictionary] = legacy.get_messages()
	_assert(legacy_messages.size() == 1, "Legacy port did not receive compatibility message")
	if not legacy_messages.is_empty():
		_assert(String(legacy_messages[0].get("message_type", "")) == "COMMAND", "Compatibility adapter leaked payload schema into legacy message type")
	var unsupported_frame: Dictionary = FrameScript.create(
		"frame/test/compat/job", "transport-session/compat/1", 2, "JOB", "RELIABLE_ORDERED",
		"planet_simulator.compat.job.v1", {"job_id": "job/compat/1"}
	)
	_assert(_error(adapter.send_to_peer("peer/compat/server", unsupported_frame)) == "UNSUPPORTED_LEGACY_CHANNEL", "Compatibility adapter accepted unsupported legacy channel")
	_assert(_ok(boundary.stop()), "Compatibility boundary stop failed")


func _test_project_wiring() -> void:
	var runner: String = FileAccess.get_file_as_string("res://RUN_T1_MULTI_PEER_TRANSPORT_TESTS.ps1")
	var network_runner: String = FileAccess.get_file_as_string("res://RUN_NETWORK_CONTRACT_TESTS.ps1")
	var world_runner: String = FileAccess.get_file_as_string("res://RUN_WORLD_REGRESSION_TESTS.ps1")
	var architecture: String = FileAccess.get_file_as_string("res://docs/architecture/T1_MULTI_PEER_TRANSPORT_V2_RU.md")
	var roadmap_text: String = FileAccess.get_file_as_string("res://config/network/network-roadmap.v1.json")
	var process_server: String = FileAccess.get_file_as_string("res://tools/network/t1_multi_peer_server.gd")
	_assert(not runner.is_empty(), "T1 PowerShell runner is missing")
	_assert(runner.contains("function Write-JsonFileAtomically") and runner.contains("$Stream.Flush($true)"), "T1 runner lacks atomic summary publishing")
	_assert(runner.contains("PSNativeCommandUseErrorActionPreference"), "T1 runner is not stderr-safe")
	_assert(runner.contains("test_t1_multi_peer_transport_contracts.gd") and runner.contains("test_t1_multi_peer_transport_processes.gd"), "T1 runner omits T1 tests")
	_assert(network_runner.contains("test_t1_multi_peer_transport_contracts.gd") and network_runner.contains("test_t1_multi_peer_transport_processes.gd"), "Network runner omits T1 tests")
	_assert(world_runner.contains("test_t1_multi_peer_transport_contracts.gd") and world_runner.contains("test_t1_multi_peer_transport_processes.gd"), "World runner omits T1 tests")
	_assert(architecture.contains("route_id + route_generation") and architecture.contains("authority_owner_id + authority_epoch"), "T1 documentation does not separate route freshness from authority fencing")
	_assert(architecture.contains("queued → dispatched") and architecture.contains("peer A") and architecture.contains("peer B"), "T1 documentation does not define real per-peer outbound backpressure")
	_assert(process_server.contains("_replies_sent") and process_server.contains("PEER_OVERLAP_NOT_OBSERVED"), "T1 process gate does not hold both clients until simultaneous peer overlap is proven")
	_assert(process_server.contains("active_peer_count < int(_options[\"expected_clients\"]"), "T1 process gate lacks an explicit simultaneous peer-count fence")
	var roadmap = JSON.parse_string(roadmap_text)
	_assert(roadmap is Dictionary, "Network roadmap is not valid JSON")
	if roadmap is Dictionary:
		_assert(String(roadmap.get("project_checkpoint", "")) == "v16.10.5-persistence-m6-dedicated-recovery", "Network roadmap checkpoint is stale")
		var statuses: Dictionary = {}
		for phase in roadmap.get("phases", []):
			statuses[String(phase.get("id", ""))] = String(phase.get("status", ""))
		_assert(String(statuses.get("S0", "")) == "accepted" and String(statuses.get("T1", "")) == "accepted" and String(statuses.get("B0", "")) == "accepted", "Foundation phase statuses are inconsistent")
	var legacy_boundary: String = FileAccess.get_file_as_string("res://scripts/network/transports/network_transport_boundary.gd")
	var legacy_port: String = FileAccess.get_file_as_string("res://scripts/network/transports/network_transport_port.gd")
	_assert(legacy_boundary.contains("planet_simulator.network_transport_boundary.v1") and legacy_port.contains("planet_simulator.network_transport_port.v1"), "T1 replaced accepted N1 transport contracts")


func _ok(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _error(result: Dictionary) -> String:
	return String(result.get("error_code", ""))


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("T1 multi-peer transport contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("T1 multi-peer transport contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)

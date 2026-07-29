extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const TransportUtilsScript = preload("res://scripts/network/transports/v2/transport_contract_utils.gd")
const PortScript = preload("res://scripts/network/transports/v2/network_transport_port_v2.gd")
const EventScript = preload("res://scripts/network/transports/v2/network_transport_event.gd")
const FrameScript = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")
const SessionScript = preload("res://scripts/network/transports/v2/network_peer_session.gd")

const SCHEMA := "planet_simulator.network_transport_boundary.v2"
const STATE_STOPPED := "STOPPED"
const STATE_STARTING := "STARTING"
const STATE_LISTENING := "LISTENING"
const STATE_ACTIVE := "ACTIVE"
const STATE_DRAINING := "DRAINING"
const STATE_FAILED := "FAILED"

var _port
var _state: String = STATE_STOPPED
var _mode: String = ""
var _failure_code: String = ""
var _sessions: Dictionary = {}
var _outbound_queues: Dictionary = {}
var _max_payload_bytes: int = 1048576
var _max_pending_messages_per_peer: int = 128
var _max_pending_bytes_per_peer: int = 2097152
var _frame_sequence: int = 0


func configure(port_reference, max_payload_bytes: int = 1048576, max_pending_messages_per_peer: int = 128, max_pending_bytes_per_peer: int = 2097152) -> Dictionary:
	if _state != STATE_STOPPED:
		return TransportUtilsScript.failure("BOUNDARY_NOT_STOPPED")
	if not _is_port(port_reference):
		return TransportUtilsScript.failure("INVALID_TRANSPORT_PORT")
	var descriptor_check: Dictionary = _validate_port_descriptor(port_reference.get_descriptor())
	if not bool(descriptor_check.get("success", false)):
		return descriptor_check
	if max_payload_bytes < 1 or max_pending_messages_per_peer < 1 or max_pending_bytes_per_peer < 1:
		return TransportUtilsScript.failure("INVALID_LIMIT")
	_port = port_reference
	_max_payload_bytes = max_payload_bytes
	_max_pending_messages_per_peer = max_pending_messages_per_peer
	_max_pending_bytes_per_peer = max_pending_bytes_per_peer
	_sessions.clear()
	_outbound_queues.clear()
	_failure_code = ""
	_mode = ""
	return TransportUtilsScript.success()


func start_server(endpoint: Dictionary) -> Dictionary:
	if _port == null:
		return TransportUtilsScript.failure("NOT_CONFIGURED")
	if _state != STATE_STOPPED:
		return TransportUtilsScript.failure("INVALID_STATE")
	_state = STATE_STARTING
	_mode = "SERVER"
	var result: Dictionary = _normalize_result(_port.start_server(endpoint))
	if not bool(result.get("success", false)):
		return _enter_failed(String(result.get("error_code", "START_SERVER_FAILED")))
	_state = STATE_LISTENING
	return TransportUtilsScript.success({"state": _state})


func connect_client(endpoint: Dictionary, peer_id: String, session_id: String, route_id: String, route_generation: int = 1) -> Dictionary:
	if _port == null:
		return TransportUtilsScript.failure("NOT_CONFIGURED")
	if _state != STATE_STOPPED:
		return TransportUtilsScript.failure("INVALID_STATE")
	_state = STATE_STARTING
	_mode = "CLIENT"
	var session_result: Dictionary = _register_peer(peer_id, session_id, route_id, route_generation, SessionScript.STATE_CONNECTING)
	if not bool(session_result.get("success", false)):
		_state = STATE_STOPPED
		_mode = ""
		return session_result
	var result: Dictionary = _normalize_result(_port.connect_client(endpoint, peer_id, session_id, route_id, route_generation))
	if not bool(result.get("success", false)):
		return _enter_failed(String(result.get("error_code", "CONNECT_FAILED")))
	_state = STATE_ACTIVE
	return TransportUtilsScript.success({"state": _state, "peer_id": peer_id})


func poll_events(max_events: int = 64) -> Dictionary:
	if _port == null:
		return TransportUtilsScript.failure("NOT_CONFIGURED")
	if max_events < 1:
		return TransportUtilsScript.failure("INVALID_EVENT_LIMIT")
	if _state in [STATE_STOPPED, STATE_FAILED]:
		return TransportUtilsScript.failure("INVALID_STATE")
	var dispatch_result: Dictionary = flush_outbound(max_events)
	if not bool(dispatch_result.get("success", false)):
		return dispatch_result
	var raw_events = _port.poll_events(max_events)
	if not raw_events is Array or raw_events.size() > max_events:
		return _enter_failed("INVALID_EVENT_BATCH")
	var accepted: Array[Dictionary] = []
	for raw_event in raw_events:
		if not raw_event is Dictionary:
			return _enter_failed("INVALID_EVENT")
		var validation: Dictionary = EventScript.validate(raw_event)
		if not bool(validation.get("success", false)):
			return _enter_failed(String(validation.get("error_code", "INVALID_EVENT")))
		var applied: Dictionary = _apply_event(raw_event)
		if not bool(applied.get("success", false)):
			return applied
		accepted.append(raw_event.duplicate(true))
	return TransportUtilsScript.success({"events": accepted, "outbound": dispatch_result.get("details", {}).duplicate(true)})


func mark_peer_handshaking(peer_id: String) -> Dictionary:
	return _transition_peer(peer_id, SessionScript.STATE_HANDSHAKING)


func mark_peer_synchronizing(peer_id: String) -> Dictionary:
	return _transition_peer(peer_id, SessionScript.STATE_SYNCHRONIZING)


func mark_peer_ready(peer_id: String) -> Dictionary:
	return _transition_peer(peer_id, SessionScript.STATE_READY)


func update_peer_route(peer_id: String, route_id: String, route_generation: int) -> Dictionary:
	var session = _sessions.get(peer_id)
	if session == null:
		return TransportUtilsScript.failure("UNKNOWN_PEER")
	return session.update_route(route_id, route_generation)


func create_frame_for_peer(peer_id: String, channel: String, payload_schema: String, payload: Dictionary, delivery_mode: String = "RELIABLE_ORDERED") -> Dictionary:
	var session = _sessions.get(peer_id)
	if session == null:
		return TransportUtilsScript.failure("UNKNOWN_PEER")
	var snapshot: Dictionary = session.snapshot()
	var sequence: int = session.peek_next_outgoing_sequence()
	_frame_sequence += 1
	var frame: Dictionary = FrameScript.create(
		"frame/%s/%d" % [peer_id.trim_prefix("peer/"), _frame_sequence],
		String(snapshot["session_id"]),
		sequence,
		channel,
		delivery_mode,
		payload_schema,
		payload
	)
	var check: Dictionary = FrameScript.validate(frame)
	if not bool(check.get("success", false)):
		return TransportUtilsScript.failure(String(check.get("error_code", "INVALID_FRAME")))
	return TransportUtilsScript.success({"frame": frame})


func send_to_peer(peer_id: String, frame: Dictionary) -> Dictionary:
	var session = _sessions.get(peer_id)
	if session == null:
		return TransportUtilsScript.failure("UNKNOWN_PEER")
	var session_snapshot: Dictionary = session.snapshot()
	if String(session_snapshot.get("state", "")) != SessionScript.STATE_READY:
		return TransportUtilsScript.failure("PEER_NOT_READY")
	var check: Dictionary = FrameScript.validate(frame)
	if not bool(check.get("success", false)):
		return TransportUtilsScript.failure(String(check.get("error_code", "INVALID_FRAME")))
	if String(frame.get("session_id", "")) != String(session_snapshot.get("session_id", "")):
		return TransportUtilsScript.failure("SESSION_MISMATCH")
	var expected_sequence: int = session.peek_next_outgoing_sequence()
	if int(frame.get("sequence", 0)) < expected_sequence:
		return TransportUtilsScript.failure("STALE_OR_DUPLICATE_OUTGOING_FRAME")
	if int(frame.get("sequence", 0)) > expected_sequence:
		return TransportUtilsScript.failure("OUTGOING_FRAME_SEQUENCE_GAP", {"expected": expected_sequence})
	var encoded: String = NetworkUtilsScript.canonical_json(frame)
	if encoded.is_empty():
		return TransportUtilsScript.failure("SERIALIZATION_FAILED")
	var byte_count: int = encoded.to_utf8_buffer().size()
	if byte_count > _max_payload_bytes:
		return TransportUtilsScript.failure("PAYLOAD_TOO_LARGE", {"payload_bytes": byte_count})
	var reserved: Dictionary = session.reserve_queue(byte_count)
	if not bool(reserved.get("success", false)):
		return reserved
	var queue: Array = _outbound_queues.get(peer_id, [])
	queue.append({
		"frame": frame.duplicate(true),
		"payload_bytes": byte_count,
		"attempts": 0,
	})
	_outbound_queues[peer_id] = queue
	var committed: Dictionary = session.commit_outgoing_sequence(int(frame["sequence"]))
	if not bool(committed.get("success", false)):
		queue.pop_back()
		session.release_queue(byte_count)
		return committed
	var queued_snapshot: Dictionary = session.snapshot()
	return TransportUtilsScript.success({
		"peer_id": peer_id,
		"payload_bytes": byte_count,
		"queued": true,
		"queued_messages": int(queued_snapshot.get("queued_messages", 0)),
		"queued_bytes": int(queued_snapshot.get("queued_bytes", 0)),
	})


func flush_outbound(max_frames: int = 64, peer_id: String = "") -> Dictionary:
	if _port == null:
		return TransportUtilsScript.failure("NOT_CONFIGURED")
	if max_frames < 1:
		return TransportUtilsScript.failure("INVALID_FLUSH_LIMIT")
	if _state in [STATE_STOPPED, STATE_FAILED]:
		return TransportUtilsScript.failure("INVALID_STATE")
	if not peer_id.is_empty() and not _sessions.has(peer_id):
		return TransportUtilsScript.failure("UNKNOWN_PEER")
	var peer_ids: Array[String] = []
	if peer_id.is_empty():
		for queued_peer_id in _outbound_queues.keys():
			peer_ids.append(String(queued_peer_id))
		peer_ids.sort()
	else:
		peer_ids.append(peer_id)
	var blocked_peers: Dictionary = {}
	var dispatched: int = 0
	var attempted: int = 0
	var failures: Array[Dictionary] = []
	while attempted < max_frames:
		var made_progress: bool = false
		for queued_peer_id in peer_ids:
			if attempted >= max_frames:
				break
			if blocked_peers.has(queued_peer_id):
				continue
			var queue: Array = _outbound_queues.get(queued_peer_id, [])
			if queue.is_empty():
				continue
			var session = _sessions.get(queued_peer_id)
			if session == null:
				_clear_outbound_queue(queued_peer_id)
				continue
			var item: Dictionary = queue[0]
			item["attempts"] = int(item.get("attempts", 0)) + 1
			queue[0] = item
			attempted += 1
			var result: Dictionary = _normalize_result(_port.send_to_peer(queued_peer_id, item.get("frame", {}).duplicate(true)))
			if not bool(result.get("success", false)):
				blocked_peers[queued_peer_id] = true
				failures.append({
					"peer_id": queued_peer_id,
					"error_code": String(result.get("error_code", "SEND_FAILED")),
					"attempts": int(item.get("attempts", 0)),
				})
				continue
			queue.pop_front()
			session.release_queue(int(item.get("payload_bytes", 0)))
			dispatched += 1
			made_progress = true
			if queue.is_empty():
				_outbound_queues.erase(queued_peer_id)
			else:
				_outbound_queues[queued_peer_id] = queue
		if not made_progress:
			break
	return TransportUtilsScript.success({
		"attempted": attempted,
		"dispatched": dispatched,
		"failed": failures,
		"pending_messages": _pending_message_count(),
		"pending_bytes": _pending_byte_count(),
	})


func disconnect_peer(peer_id: String) -> Dictionary:
	var session = _sessions.get(peer_id)
	if session == null:
		return TransportUtilsScript.success({"replay": true})
	var snapshot: Dictionary = session.snapshot()
	var result: Dictionary = _normalize_result(_port.disconnect_peer(peer_id, String(snapshot["session_id"])))
	if not bool(result.get("success", false)):
		return result
	_clear_outbound_queue(peer_id)
	session.transition(SessionScript.STATE_CLOSED)
	return TransportUtilsScript.success({"replay": false})


func drain() -> Dictionary:
	if _state == STATE_DRAINING:
		return TransportUtilsScript.success({"replay": true})
	if _state in [STATE_STOPPED, STATE_FAILED]:
		return TransportUtilsScript.failure("INVALID_STATE")
	_state = STATE_DRAINING
	for peer_id in _sessions.keys():
		var session = _sessions[peer_id]
		var state: String = String(session.snapshot().get("state", ""))
		if state not in [SessionScript.STATE_CLOSED, SessionScript.STATE_FAILED, SessionScript.STATE_DRAINING]:
			session.transition(SessionScript.STATE_DRAINING)
	var result: Dictionary = _normalize_result(_port.drain())
	if not bool(result.get("success", false)):
		return _enter_failed(String(result.get("error_code", "DRAIN_FAILED")))
	return TransportUtilsScript.success({"replay": false})


func stop() -> Dictionary:
	if _state == STATE_STOPPED:
		return TransportUtilsScript.success({"replay": true})
	var result: Dictionary = _normalize_result(_port.stop()) if _port != null else TransportUtilsScript.success()
	if not bool(result.get("success", false)):
		return _enter_failed(String(result.get("error_code", "STOP_FAILED")))
	_state = STATE_STOPPED
	_mode = ""
	_failure_code = ""
	_sessions.clear()
	_outbound_queues.clear()
	return TransportUtilsScript.success({"replay": false})


func get_peer_snapshot(peer_id: String) -> Dictionary:
	var session = _sessions.get(peer_id)
	return session.snapshot().duplicate(true) if session != null else {}


func get_connected_peers() -> Array[String]:
	var result: Array[String] = []
	for peer_id in _sessions.keys():
		var state: String = String(_sessions[peer_id].snapshot().get("state", ""))
		if state not in [SessionScript.STATE_CLOSED, SessionScript.STATE_FAILED]:
			result.append(String(peer_id))
	result.sort()
	return result


func get_snapshot() -> Dictionary:
	var peer_snapshots: Dictionary = {}
	for peer_id in _sessions.keys():
		peer_snapshots[peer_id] = _sessions[peer_id].snapshot()
	return {
		"schema": SCHEMA,
		"state": _state,
		"mode": _mode,
		"failure_code": _failure_code,
		"peer_count": get_connected_peers().size(),
		"outbound_pending_messages": _pending_message_count(),
		"outbound_pending_bytes": _pending_byte_count(),
		"peers": peer_snapshots,
		"port_descriptor": _port.get_descriptor().duplicate(true) if _port != null else {},
	}


func _apply_event(event: Dictionary) -> Dictionary:
	var event_type: String = String(event["event_type"])
	var peer_id: String = String(event["peer_id"])
	var session_id: String = String(event["session_id"])
	match event_type:
		"PEER_CONNECTED":
			var details: Dictionary = event.get("details", {})
			var route_id: String = String(details.get("route_id", "route/%s/default" % peer_id.trim_prefix("peer/")))
			var route_generation: int = int(details.get("route_generation", 1))
			var registered: Dictionary = _register_peer(peer_id, session_id, route_id, route_generation, SessionScript.STATE_TRANSPORT_CONNECTED)
			if not bool(registered.get("success", false)):
				return registered
		"MESSAGE_RECEIVED":
			var session = _sessions.get(peer_id)
			if session == null:
				return TransportUtilsScript.failure("UNKNOWN_PEER_EVENT")
			if String(session.snapshot().get("session_id", "")) != session_id:
				return TransportUtilsScript.failure("STALE_TRANSPORT_SESSION")
			var incoming: Dictionary = session.accept_incoming_sequence(int(event["sequence"]))
			if not bool(incoming.get("success", false)):
				return incoming
		"PEER_DISCONNECTED":
			var session = _sessions.get(peer_id)
			if session != null and String(session.snapshot().get("session_id", "")) == session_id:
				_clear_outbound_queue(peer_id)
				session.transition(SessionScript.STATE_CLOSED)
		"TRANSPORT_ERROR":
			return _enter_failed(String(event.get("error_code", "TRANSPORT_ERROR")))
	return TransportUtilsScript.success()


func _register_peer(peer_id: String, session_id: String, route_id: String, route_generation: int, initial_state: String) -> Dictionary:
	var existing = _sessions.get(peer_id)
	if existing != null:
		var existing_snapshot: Dictionary = existing.snapshot()
		if String(existing_snapshot.get("session_id", "")) == session_id:
			var route_result: Dictionary = existing.update_route(route_id, route_generation)
			if not bool(route_result.get("success", false)):
				return route_result
			if initial_state != String(existing_snapshot.get("state", "")):
				return existing.transition(initial_state)
			return TransportUtilsScript.success({"replay": true})
		if route_generation <= int(existing_snapshot.get("route_generation", 0)):
			return TransportUtilsScript.failure("STALE_TRANSPORT_SESSION")
		_clear_outbound_queue(peer_id)
		existing.transition(SessionScript.STATE_CLOSED)
	var session = SessionScript.new()
	var configured: Dictionary = session.configure(peer_id, session_id, route_id, route_generation, _max_pending_messages_per_peer, _max_pending_bytes_per_peer)
	if not bool(configured.get("success", false)):
		return configured
	if initial_state != SessionScript.STATE_CONNECTING:
		var transitioned: Dictionary = session.transition(initial_state)
		if not bool(transitioned.get("success", false)):
			return transitioned
	_sessions[peer_id] = session
	return TransportUtilsScript.success({"replay": false})


func _transition_peer(peer_id: String, target_state: String) -> Dictionary:
	var session = _sessions.get(peer_id)
	if session == null:
		return TransportUtilsScript.failure("UNKNOWN_PEER")
	return session.transition(target_state)


func _clear_outbound_queue(peer_id: String) -> void:
	var queue: Array = _outbound_queues.get(peer_id, [])
	var session = _sessions.get(peer_id)
	if session != null:
		for item in queue:
			if item is Dictionary:
				session.release_queue(int(item.get("payload_bytes", 0)))
	_outbound_queues.erase(peer_id)


func _pending_message_count() -> int:
	var count: int = 0
	for queue in _outbound_queues.values():
		if queue is Array:
			count += queue.size()
	return count


func _pending_byte_count() -> int:
	var total: int = 0
	for peer_id in _sessions.keys():
		total += int(_sessions[peer_id].snapshot().get("queued_bytes", 0))
	return total


func _is_port(value) -> bool:
	if value == null or not value is RefCounted:
		return false
	var script = value.get_script()
	while script != null:
		if script == PortScript:
			return true
		script = script.get_base_script()
	return false


func _validate_port_descriptor(descriptor) -> Dictionary:
	if not descriptor is Dictionary:
		return TransportUtilsScript.failure("INVALID_PORT_DESCRIPTOR")
	var fields: Array[String] = ["schema", "transport_kind", "supports_server", "supports_client", "synchronous_delivery", "multi_peer", "max_peers"]
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(descriptor, fields)
	if not bool(exact.get("success", false)):
		return TransportUtilsScript.failure("INVALID_PORT_DESCRIPTOR")
	if String(descriptor.get("schema", "")) != PortScript.SCHEMA:
		return TransportUtilsScript.failure("INVALID_PORT_SCHEMA")
	if typeof(descriptor.get("supports_server")) != TYPE_BOOL or typeof(descriptor.get("supports_client")) != TYPE_BOOL or typeof(descriptor.get("synchronous_delivery")) != TYPE_BOOL or typeof(descriptor.get("multi_peer")) != TYPE_BOOL:
		return TransportUtilsScript.failure("INVALID_PORT_DESCRIPTOR")
	if not bool(descriptor.get("multi_peer", false)) or not NetworkUtilsScript.is_json_integer(descriptor.get("max_peers")) or int(descriptor.get("max_peers", 0)) < 1:
		return TransportUtilsScript.failure("PORT_NOT_MULTI_PEER")
	return TransportUtilsScript.success()


func _normalize_result(value) -> Dictionary:
	if not value is Dictionary or typeof(value.get("success")) != TYPE_BOOL or typeof(value.get("error_code")) != TYPE_STRING or not value.get("details", {}) is Dictionary:
		return TransportUtilsScript.failure("INVALID_PORT_RESULT")
	return {"success": bool(value["success"]), "error_code": String(value["error_code"]), "details": value.get("details", {}).duplicate(true)}


func _enter_failed(error_code: String) -> Dictionary:
	_state = STATE_FAILED
	_failure_code = error_code if not error_code.is_empty() else "TRANSPORT_FAILURE"
	return TransportUtilsScript.failure(_failure_code, {"state": _state})

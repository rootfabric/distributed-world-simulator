extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const TransportUtilsScript = preload("res://scripts/network/transports/v2/transport_contract_utils.gd")
const PortScript = preload("res://scripts/network/transports/v2/network_transport_port_v2.gd")
const EventScript = preload("res://scripts/network/transports/v2/network_transport_event.gd")
const FrameScript = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")
const SessionScript = preload("res://scripts/network/transports/v2/network_peer_session.gd")
const ChannelPolicyScript = preload("res://scripts/network/realtime/realtime_channel_policy.gd")

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
var _telemetry


func configure(
	port_reference,
	max_payload_bytes: int = 1048576,
	max_pending_messages_per_peer: int = 128,
	max_pending_bytes_per_peer: int = 2097152,
	telemetry_collector = null
) -> Dictionary:
	if _state != STATE_STOPPED:
		return TransportUtilsScript.failure("BOUNDARY_NOT_STOPPED")
	if not _is_port(port_reference):
		return TransportUtilsScript.failure("INVALID_TRANSPORT_PORT")
	var descriptor_check: Dictionary = _validate_port_descriptor(port_reference.get_descriptor())
	if not bool(descriptor_check.get("success", false)):
		return descriptor_check
	if max_payload_bytes < 1 or max_pending_messages_per_peer < 1 or max_pending_bytes_per_peer < 1:
		return TransportUtilsScript.failure("INVALID_LIMIT")
	if telemetry_collector != null and not _is_telemetry_collector(telemetry_collector):
		return TransportUtilsScript.failure("INVALID_TELEMETRY_COLLECTOR")
	_port = port_reference
	_telemetry = telemetry_collector
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
	_telemetry_increment("transport_server_starts")
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
	_telemetry_increment("transport_client_connects")
	return TransportUtilsScript.success({"state": _state, "peer_id": peer_id})


func poll_events(max_events: int = 64) -> Dictionary:
	if _port == null:
		return TransportUtilsScript.failure("NOT_CONFIGURED")
	if max_events < 1:
		return TransportUtilsScript.failure("INVALID_EVENT_LIMIT")
	if _state in [STATE_STOPPED, STATE_FAILED]:
		return TransportUtilsScript.failure("INVALID_STATE")
	var poll_started_us: int = Time.get_ticks_usec()
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
		if bool(applied.get("details", {}).get("deliver_event", true)):
			accepted.append(raw_event.duplicate(true))
			_record_received_event(raw_event)
	_update_queue_telemetry()
	_telemetry_observe("transport_poll_duration_ms", float(Time.get_ticks_usec() - poll_started_us) / 1000.0)
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
	var check: Dictionary = FrameScript.validate(frame)
	if not bool(check.get("success", false)):
		return TransportUtilsScript.failure(String(check.get("error_code", "INVALID_FRAME")))
	var delivery_check: Dictionary = ChannelPolicyScript.validate_delivery(
		String(frame.get("channel", "")), String(frame.get("delivery_mode", ""))
	)
	if not bool(delivery_check.get("success", false)):
		return delivery_check
	var session_state: String = String(session_snapshot.get("state", ""))
	var pre_ready_control: bool = (
		String(frame.get("channel", "")) == ChannelPolicyScript.CONTROL
		and session_state in [
			SessionScript.STATE_TRANSPORT_CONNECTED,
			SessionScript.STATE_HANDSHAKING,
			SessionScript.STATE_SYNCHRONIZING,
		]
	)
	if session_state != SessionScript.STATE_READY and not pre_ready_control:
		return TransportUtilsScript.failure("PEER_NOT_READY")
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
	var stream_key: String = ChannelPolicyScript.outbound_stream_key(frame)
	var peer_streams: Dictionary = _outbound_queues.get(peer_id, {})
	var queue: Array = peer_streams.get(stream_key, [])
	var coalesced_messages: int = 0
	var coalesced_bytes: int = 0
	var coalesced_items: Array = []
	if ChannelPolicyScript.coalesces_latest(
		String(frame.get("channel", "")), String(frame.get("delivery_mode", ""))
	):
		for item_value in queue:
			if item_value is Dictionary:
				coalesced_items.append(Dictionary(item_value).duplicate(true))
				coalesced_messages += 1
				coalesced_bytes += int(item_value.get("payload_bytes", 0))
				session.release_queue(int(item_value.get("payload_bytes", 0)))
	var reserved: Dictionary = session.reserve_queue(byte_count)
	if not bool(reserved.get("success", false)):
		var rollback_failed: bool = false
		for item_value in coalesced_items:
			var restored: Dictionary = session.reserve_queue(int(item_value.get("payload_bytes", 0)))
			if not bool(restored.get("success", false)):
				rollback_failed = true
				break
		if rollback_failed:
			return _enter_failed("QUEUE_RESERVATION_ROLLBACK_FAILED")
		return reserved
	if coalesced_messages > 0:
		queue.clear()
	queue.append({
		"frame": frame.duplicate(true),
		"payload_bytes": byte_count,
		"attempts": 0,
		"stream_key": stream_key,
	})
	peer_streams[stream_key] = queue
	_outbound_queues[peer_id] = peer_streams
	var committed: Dictionary = session.commit_outgoing_sequence(int(frame["sequence"]))
	if not bool(committed.get("success", false)):
		queue.pop_back()
		session.release_queue(byte_count)
		if queue.is_empty():
			peer_streams.erase(stream_key)
		if peer_streams.is_empty():
			_outbound_queues.erase(peer_id)
		else:
			_outbound_queues[peer_id] = peer_streams
		return committed
	if coalesced_messages > 0:
		_telemetry_increment("transport_realtime_frames_coalesced", coalesced_messages)
		_telemetry_increment("transport_realtime_bytes_coalesced", coalesced_bytes)
	var queued_snapshot: Dictionary = session.snapshot()
	_telemetry_increment("transport_frames_queued")
	_update_queue_telemetry()
	return TransportUtilsScript.success({
		"peer_id": peer_id,
		"payload_bytes": byte_count,
		"queued": true,
		"stream_key": stream_key,
		"coalesced_messages": coalesced_messages,
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
	var blocked_streams: Dictionary = {}
	var dispatched: int = 0
	var attempted: int = 0
	var failures: Array[Dictionary] = []
	while attempted < max_frames:
		var made_progress: bool = false
		for queued_peer_id in peer_ids:
			if attempted >= max_frames:
				break
			var session = _sessions.get(queued_peer_id)
			if session == null:
				_clear_outbound_queue(queued_peer_id)
				continue
			var peer_streams: Dictionary = _outbound_queues.get(queued_peer_id, {})
			var stream_keys: Array = peer_streams.keys()
			stream_keys.sort()
			for stream_key_value in stream_keys:
				if attempted >= max_frames:
					break
				var stream_key: String = String(stream_key_value)
				var blocked_key: String = "%s|%s" % [queued_peer_id, stream_key]
				if blocked_streams.has(blocked_key):
					continue
				var queue: Array = peer_streams.get(stream_key, [])
				if queue.is_empty():
					peer_streams.erase(stream_key)
					continue
				var item: Dictionary = queue[0]
				item["attempts"] = int(item.get("attempts", 0)) + 1
				queue[0] = item
				peer_streams[stream_key] = queue
				attempted += 1
				var result: Dictionary = _normalize_result(
					_port.send_to_peer(queued_peer_id, item.get("frame", {}).duplicate(true))
				)
				if not bool(result.get("success", false)):
					_telemetry_increment("transport_send_failures")
					blocked_streams[blocked_key] = true
					failures.append({
						"peer_id": queued_peer_id,
						"stream_key": stream_key,
						"error_code": String(result.get("error_code", "SEND_FAILED")),
						"attempts": int(item.get("attempts", 0)),
					})
					continue
				queue.pop_front()
				session.release_queue(int(item.get("payload_bytes", 0)))
				var sent_frame: Dictionary = item.get("frame", {})
				var sent_bytes: int = int(
					result.get("details", {}).get("packet_bytes", item.get("payload_bytes", 0))
				)
				_telemetry_record_transport(
					String(sent_frame.get("channel", "unknown")).to_lower(), "sent", sent_bytes
				)
				_telemetry_increment("transport_frames_dispatched")
				dispatched += 1
				made_progress = true
				if queue.is_empty():
					peer_streams.erase(stream_key)
				else:
					peer_streams[stream_key] = queue
			if peer_streams.is_empty():
				_outbound_queues.erase(queued_peer_id)
			else:
				_outbound_queues[queued_peer_id] = peer_streams
		if not made_progress:
			break
	_update_queue_telemetry()
	return TransportUtilsScript.success({
		"attempted": attempted,
		"dispatched": dispatched,
		"failed": failures,
		"blocked_stream_count": blocked_streams.size(),
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
		"outbound_streams": _outbound_stream_snapshot(),
		"peers": peer_snapshots,
		"port_descriptor": _port.get_descriptor().duplicate(true) if _port != null else {},
		"port_runtime": (
			_port.get_runtime_snapshot().duplicate(true)
			if _port != null and _port.has_method("get_runtime_snapshot") else {}
		),
		"telemetry_attached": _telemetry != null,
	}


func _apply_event(event: Dictionary) -> Dictionary:
	var event_type: String = String(event["event_type"])
	var peer_id: String = String(event["peer_id"])
	var session_id: String = String(event["session_id"])
	match event_type:
		"PEER_CONNECTED":
			_telemetry_increment("transport_peer_connected_events")
			var details: Dictionary = event.get("details", {})
			var route_id: String = String(details.get("route_id", "route/%s/default" % peer_id.trim_prefix("peer/")))
			var route_generation: int = int(details.get("route_generation", 1))
			var registered: Dictionary = _register_peer(peer_id, session_id, route_id, route_generation, SessionScript.STATE_TRANSPORT_CONNECTED)
			if not bool(registered.get("success", false)):
				return registered
		"MESSAGE_RECEIVED":
			_telemetry_increment("transport_message_events")
			var session = _sessions.get(peer_id)
			if session == null:
				return TransportUtilsScript.failure("UNKNOWN_PEER_EVENT")
			if String(session.snapshot().get("session_id", "")) != session_id:
				return TransportUtilsScript.failure("STALE_TRANSPORT_SESSION")
			var frame: Dictionary = event.get("frame", {})
			var delivery_mode: String = String(frame.get("delivery_mode", ""))
			var unreliable_sequenced: bool = delivery_mode == "UNRELIABLE_SEQUENCED"
			var sequence_stream: String = _incoming_sequence_stream(frame)
			var incoming: Dictionary = session.accept_incoming_sequence(
				int(event["sequence"]),
				unreliable_sequenced,
				sequence_stream,
				false
			)
			if not bool(incoming.get("success", false)):
				return incoming
			if not bool(incoming.get("details", {}).get("accepted", true)):
				_telemetry_increment("transport_unreliable_stale_frames_suppressed")
				return TransportUtilsScript.success({"deliver_event": false})
			var gap: int = int(incoming.get("details", {}).get("gap", 0))
			if gap > 0:
				_telemetry_increment("transport_unreliable_sequence_gaps", gap)
		"PEER_DISCONNECTED":
			_telemetry_increment("transport_peer_disconnected_events")
			var peer_error_code: String = String(event.get("error_code", ""))
			var protocol_violation: bool = bool(event.get("details", {}).get("protocol_violation", false))
			if protocol_violation:
				_telemetry_increment("transport_peer_protocol_violations")
			var session = _sessions.get(peer_id)
			if session != null and String(session.snapshot().get("session_id", "")) == session_id:
				_clear_outbound_queue(peer_id)
				if protocol_violation:
					session.transition(SessionScript.STATE_FAILED, peer_error_code)
				else:
					session.transition(SessionScript.STATE_CLOSED)
		"TRANSPORT_ERROR":
			_telemetry_increment("transport_error_events")
			return _enter_failed(String(event.get("error_code", "TRANSPORT_ERROR")))
	return TransportUtilsScript.success()


func _incoming_sequence_stream(frame: Dictionary) -> String:
	return ChannelPolicyScript.sequence_stream(frame)

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
	var peer_streams: Dictionary = _outbound_queues.get(peer_id, {})
	var session = _sessions.get(peer_id)
	if session != null:
		for queue_value in peer_streams.values():
			if not queue_value is Array:
				continue
			for item_value in queue_value:
				if item_value is Dictionary:
					session.release_queue(int(item_value.get("payload_bytes", 0)))
	_outbound_queues.erase(peer_id)

func _pending_message_count() -> int:
	var count: int = 0
	for peer_streams_value in _outbound_queues.values():
		if not peer_streams_value is Dictionary:
			continue
		for queue_value in Dictionary(peer_streams_value).values():
			if queue_value is Array:
				count += queue_value.size()
	return count

func _pending_byte_count() -> int:
	var total: int = 0
	for peer_id in _sessions.keys():
		total += int(_sessions[peer_id].snapshot().get("queued_bytes", 0))
	return total


func _pending_reliable_queue() -> Dictionary:
	var messages: int = 0
	var bytes: int = 0
	for peer_streams_value in _outbound_queues.values():
		if not peer_streams_value is Dictionary:
			continue
		for queue_value in Dictionary(peer_streams_value).values():
			if not queue_value is Array:
				continue
			for item_value in queue_value:
				if not item_value is Dictionary:
					continue
				var item: Dictionary = item_value
				var frame: Dictionary = item.get("frame", {})
				if not String(frame.get("delivery_mode", "")).begins_with("RELIABLE"):
					continue
				messages += 1
				bytes += int(item.get("payload_bytes", 0))
	return {"messages": messages, "bytes": bytes}

func _outbound_stream_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for peer_id_value in _outbound_queues.keys():
		var peer_id: String = String(peer_id_value)
		var peer_streams_value = _outbound_queues[peer_id]
		if not peer_streams_value is Dictionary:
			continue
		var streams: Dictionary = {}
		for stream_key_value in Dictionary(peer_streams_value).keys():
			var stream_key: String = String(stream_key_value)
			var queue: Array = Dictionary(peer_streams_value).get(stream_key, [])
			var stream_bytes: int = 0
			for item_value in queue:
				if item_value is Dictionary:
					stream_bytes += int(item_value.get("payload_bytes", 0))
			streams[stream_key] = {"messages": queue.size(), "bytes": stream_bytes}
		result[peer_id] = streams
	return result


func _update_queue_telemetry() -> void:
	_telemetry_set_gauge("transport_outbound_pending_messages", float(_pending_message_count()))
	_telemetry_set_gauge("transport_outbound_pending_bytes", float(_pending_byte_count()))
	var reliable: Dictionary = _pending_reliable_queue()
	_telemetry_set_gauge("reliable_queue_depth_messages", float(reliable.get("messages", 0)))
	_telemetry_set_gauge("reliable_queue_depth_bytes", float(reliable.get("bytes", 0)))


func _record_received_event(event: Dictionary) -> void:
	if String(event.get("event_type", "")) != "MESSAGE_RECEIVED":
		return
	var frame: Dictionary = event.get("frame", {})
	var packet_bytes: int = int(event.get("details", {}).get("packet_bytes", 0))
	if packet_bytes < 1:
		packet_bytes = NetworkUtilsScript.canonical_json(frame).to_utf8_buffer().size()
	_telemetry_record_transport(String(frame.get("channel", "unknown")).to_lower(), "received", packet_bytes)


func _is_telemetry_collector(value) -> bool:
	if value == null or not value is RefCounted:
		return false
	for method_name in ["increment", "set_gauge", "observe", "record_transport"]:
		if not value.has_method(method_name):
			return false
	return true


func _telemetry_increment(name: String, amount: int = 1) -> void:
	if _telemetry != null:
		_telemetry.increment(name, amount)


func _telemetry_set_gauge(name: String, value: float) -> void:
	if _telemetry != null:
		_telemetry.set_gauge(name, value)


func _telemetry_observe(name: String, value: float) -> void:
	if _telemetry != null:
		_telemetry.observe(name, value)


func _telemetry_record_transport(channel: String, direction: String, packet_bytes: int) -> void:
	if _telemetry != null:
		_telemetry.record_transport(channel, direction, maxi(packet_bytes, 0))


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

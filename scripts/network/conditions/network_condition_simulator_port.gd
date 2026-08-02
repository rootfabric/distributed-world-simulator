extends "res://scripts/network/transports/v2/network_transport_port_v2.gd"

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const BasePortScript = preload("res://scripts/network/transports/v2/network_transport_port_v2.gd")
const EventScript = preload("res://scripts/network/transports/v2/network_transport_event.gd")
const ChannelPolicyScript = preload("res://scripts/network/realtime/realtime_channel_policy.gd")
const FrameScript = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")
const ProfileScript = preload("res://scripts/network/conditions/network_condition_profile.gd")
const RngScript = preload("res://scripts/network/conditions/deterministic_network_rng.gd")

const SIMULATOR_SCHEMA: String = "planet_simulator.network_condition_simulator_port.v1"
const CLOCK_REAL: String = "REAL"
const CLOCK_MANUAL: String = "MANUAL"
const OUTGOING: String = "OUTGOING"
const INCOMING: String = "INCOMING"
const DIRECTIONS: Array[String] = [OUTGOING, INCOMING]
const LAG_SPIKE_INTERVAL_PACKETS: int = 16
const DISCONNECT_INTERVAL_PACKETS: int = 64
const RELIABLE_RETRANSMISSION_MIN_MS: int = 50
const SEND_RETRY_MS: int = 10
const MAX_DELEGATE_POLL_MULTIPLIER: int = 8

var _delegate
var _profile: Dictionary = {}
var _telemetry
var _configured: bool = false
var _started: bool = false
var _mode: String = ""
var _clock_mode: String = CLOCK_REAL
var _manual_now_ms: int = 0
var _profile_generation: int = 0
var _passthrough: bool = false
var _order_sequence: int = 0
var _outgoing_queue: Array[Dictionary] = []
var _incoming_queue: Array[Dictionary] = []
var _ready_events: Array[Dictionary] = []
var _queued_bytes: Dictionary = {OUTGOING: 0, INCOMING: 0}
var _bandwidth_available_at_ms: Dictionary = {OUTGOING: 0, INCOMING: 0}
var _burst_until_ms: Dictionary = {}
var _manual_spike_until_ms: Dictionary = {OUTGOING: 0, INCOMING: 0}
var _blackout_until_ms: Dictionary = {OUTGOING: 0, INCOMING: 0}
var _packet_counts: Dictionary = {}
var _stream_rngs: Dictionary = {}
var _counters: Dictionary = {}


func setup(
	delegate_port,
	profile: Dictionary,
	telemetry_collector = null,
	manual_clock: bool = false,
	initial_time_ms: int = 0
) -> Dictionary:
	if _configured:
		return TransportUtilsScript.failure("SIMULATOR_ALREADY_CONFIGURED")
	if not _is_port(delegate_port):
		return TransportUtilsScript.failure("INVALID_DELEGATE_PORT")
	var profile_check: Dictionary = ProfileScript.validate(profile)
	if not bool(profile_check.get("success", false)):
		return TransportUtilsScript.failure("INVALID_NETWORK_CONDITION_PROFILE", {"cause": profile_check})
	if telemetry_collector != null and not _is_telemetry_collector(telemetry_collector):
		return TransportUtilsScript.failure("INVALID_TELEMETRY_COLLECTOR")
	if initial_time_ms < 0:
		return TransportUtilsScript.failure("INVALID_INITIAL_TIME")
	_delegate = delegate_port
	_telemetry = telemetry_collector
	_clock_mode = CLOCK_MANUAL if manual_clock else CLOCK_REAL
	_manual_now_ms = initial_time_ms
	_configured = true
	var switched: Dictionary = set_profile(profile)
	if not bool(switched.get("success", false)):
		_configured = false
		_delegate = null
		return switched
	_update_telemetry()
	return TransportUtilsScript.success({
		"clock_mode": _clock_mode,
		"profile_id": String(_profile.get("profile_id", "")),
	})


func get_descriptor() -> Dictionary:
	var delegate_descriptor: Dictionary = _delegate.get_descriptor() if _delegate != null else {}
	return {
		"schema": SCHEMA,
		"transport_kind": "NETWORK_CONDITION_SIMULATOR",
		"supports_server": bool(delegate_descriptor.get("supports_server", false)),
		"supports_client": bool(delegate_descriptor.get("supports_client", false)),
		"synchronous_delivery": bool(delegate_descriptor.get("synchronous_delivery", false)) and _passthrough,
		"multi_peer": bool(delegate_descriptor.get("multi_peer", true)),
		"max_peers": int(delegate_descriptor.get("max_peers", 1)),
	}


func start_server(endpoint: Dictionary) -> Dictionary:
	if not _configured:
		return TransportUtilsScript.failure("SIMULATOR_NOT_CONFIGURED")
	if _started:
		return TransportUtilsScript.failure("ALREADY_STARTED")
	var result: Dictionary = _normalize_result(_delegate.start_server(endpoint))
	if bool(result.get("success", false)):
		_started = true
		_mode = "SERVER"
		_increment("network_simulator_server_starts")
	return result


func connect_client(endpoint: Dictionary, peer_id: String, session_id: String, route_id: String, route_generation: int) -> Dictionary:
	if not _configured:
		return TransportUtilsScript.failure("SIMULATOR_NOT_CONFIGURED")
	if _started:
		return TransportUtilsScript.failure("ALREADY_STARTED")
	var result: Dictionary = _normalize_result(
		_delegate.connect_client(endpoint, peer_id, session_id, route_id, route_generation)
	)
	if bool(result.get("success", false)):
		_started = true
		_mode = "CLIENT"
		_increment("network_simulator_client_connects")
	return result


func disconnect_peer(peer_id: String, session_id: String) -> Dictionary:
	_clear_peer_queues(peer_id)
	var result: Dictionary = _normalize_result(_delegate.disconnect_peer(peer_id, session_id))
	_update_telemetry()
	return result


func send_to_peer(peer_id: String, frame: Dictionary) -> Dictionary:
	if not _configured or not _started:
		return TransportUtilsScript.failure("SIMULATOR_NOT_STARTED")
	var frame_check: Dictionary = FrameScript.validate(frame)
	if not bool(frame_check.get("success", false)):
		return TransportUtilsScript.failure(String(frame_check.get("error_code", "INVALID_FRAME")))
	var packet_bytes: int = NetworkUtilsScript.canonical_json(frame).to_utf8_buffer().size()
	if _passthrough and not _has_active_manual_condition(OUTGOING):
		var direct: Dictionary = _normalize_result(_delegate.send_to_peer(peer_id, frame))
		if bool(direct.get("success", false)):
			_increment("network_simulator_packets_passthrough")
		return _with_simulator_details(direct, packet_bytes, false, false, _now_ms())
	var plan: Dictionary = _plan_packet(OUTGOING, peer_id, frame, packet_bytes)
	if bool(plan.get("drop", false)):
		_increment("network_simulator_unreliable_packets_dropped")
		_update_telemetry()
		return TransportUtilsScript.success({
			"enqueued": true,
			"simulated": true,
			"dropped": true,
			"packet_bytes": packet_bytes,
			"profile_id": String(_profile.get("profile_id", "")),
		})
	if not _can_queue(OUTGOING, packet_bytes):
		if _is_reliable(frame):
			_increment("network_simulator_reliable_queue_backpressure")
			_update_telemetry()
			return TransportUtilsScript.failure("NETWORK_SIMULATOR_QUEUE_LIMIT", {
				"direction": OUTGOING,
				"packet_bytes": packet_bytes,
			})
		_increment("network_simulator_unreliable_queue_drops")
		_update_telemetry()
		return TransportUtilsScript.success({
			"enqueued": true,
			"simulated": true,
			"dropped": true,
			"queue_limit": true,
			"packet_bytes": packet_bytes,
		})
	_enqueue_outgoing(peer_id, frame, packet_bytes, plan, false)
	if bool(plan.get("duplicate", false)):
		if _can_queue(OUTGOING, packet_bytes):
			var duplicate_plan: Dictionary = plan.duplicate(true)
			duplicate_plan["due_ms"] = int(plan.get("due_ms", _now_ms())) + 1
			_enqueue_outgoing(peer_id, frame, packet_bytes, duplicate_plan, true)
			_increment("network_simulator_datagrams_duplicated")
		else:
			_increment("network_simulator_duplicate_queue_suppressed")
	_update_telemetry()
	return TransportUtilsScript.success({
		"enqueued": true,
		"simulated": true,
		"dropped": false,
		"packet_bytes": packet_bytes,
		"scheduled_at_ms": int(plan.get("due_ms", _now_ms())),
		"profile_id": String(_profile.get("profile_id", "")),
	})


func poll_events(max_events: int) -> Array[Dictionary]:
	if not _configured or not _started or max_events < 1:
		return []
	_dispatch_due_outgoing(maxi(max_events * MAX_DELEGATE_POLL_MULTIPLIER, 64))
	var delegate_limit: int = maxi(max_events * MAX_DELEGATE_POLL_MULTIPLIER, 64)
	var raw_events = _delegate.poll_events(delegate_limit)
	if raw_events is Array:
		for event_value in raw_events:
			if event_value is Dictionary:
				_ingest_delegate_event(Dictionary(event_value))
	_release_due_incoming(maxi(max_events * MAX_DELEGATE_POLL_MULTIPLIER, 64))
	var result: Array[Dictionary] = _take_ready_events(max_events)
	_update_telemetry()
	return result


func drain() -> Dictionary:
	if not _configured or not _started:
		return TransportUtilsScript.failure("SIMULATOR_NOT_STARTED")
	_dispatch_due_outgoing(4096)
	return _normalize_result(_delegate.drain())


func stop() -> Dictionary:
	var result: Dictionary = (
		_normalize_result(_delegate.stop())
		if _delegate != null else TransportUtilsScript.success()
	)
	_started = false
	_mode = ""
	_outgoing_queue.clear()
	_incoming_queue.clear()
	_ready_events.clear()
	_queued_bytes = {OUTGOING: 0, INCOMING: 0}
	_bandwidth_available_at_ms = {OUTGOING: 0, INCOMING: 0}
	_burst_until_ms.clear()
	_manual_spike_until_ms = {OUTGOING: 0, INCOMING: 0}
	_blackout_until_ms = {OUTGOING: 0, INCOMING: 0}
	_update_telemetry()
	return result


func set_profile(profile: Dictionary) -> Dictionary:
	if not _configured:
		return TransportUtilsScript.failure("SIMULATOR_NOT_CONFIGURED")
	var profile_check: Dictionary = ProfileScript.validate(profile)
	if not bool(profile_check.get("success", false)):
		return TransportUtilsScript.failure("INVALID_NETWORK_CONDITION_PROFILE", {"cause": profile_check})
	_profile = profile.duplicate(true)
	_profile_generation += 1
	_passthrough = ProfileScript.is_passthrough(_profile)
	_stream_rngs.clear()
	_packet_counts.clear()
	_burst_until_ms.clear()
	_bandwidth_available_at_ms = {OUTGOING: _now_ms(), INCOMING: _now_ms()}
	_increment("network_simulator_profile_switches")
	_set_gauge("network_simulator_profile_generation", float(_profile_generation))
	_update_telemetry()
	return TransportUtilsScript.success({
		"profile_id": String(_profile.get("profile_id", "")),
		"profile_generation": _profile_generation,
		"queued_packets_retained": _outgoing_queue.size() + _incoming_queue.size(),
	})


func advance_time_ms(delta_ms: int) -> Dictionary:
	if _clock_mode != CLOCK_MANUAL:
		return TransportUtilsScript.failure("MANUAL_CLOCK_NOT_ENABLED")
	if delta_ms < 0:
		return TransportUtilsScript.failure("NEGATIVE_TIME_ADVANCE")
	_manual_now_ms += delta_ms
	return TransportUtilsScript.success({"now_ms": _manual_now_ms})


func set_manual_time_ms(value_ms: int) -> Dictionary:
	if _clock_mode != CLOCK_MANUAL:
		return TransportUtilsScript.failure("MANUAL_CLOCK_NOT_ENABLED")
	if value_ms < _manual_now_ms:
		return TransportUtilsScript.failure("CLOCK_CANNOT_MOVE_BACKWARDS")
	_manual_now_ms = value_ms
	return TransportUtilsScript.success({"now_ms": _manual_now_ms})


func trigger_lag_spike(direction: String = "BOTH", duration_ms: int = -1) -> Dictionary:
	var targets: Array = _normalize_directions(direction)
	if targets.is_empty():
		return TransportUtilsScript.failure("INVALID_SIMULATOR_DIRECTION")
	var effective_duration: int = duration_ms
	if effective_duration < 0:
		effective_duration = int(_profile.get("lag_spike_ms", 0))
	if effective_duration < 1:
		return TransportUtilsScript.failure("INVALID_LAG_SPIKE_DURATION")
	var until_ms: int = _now_ms() + effective_duration
	for target in targets:
		var target_until_ms: int = maxi(int(_manual_spike_until_ms.get(target, 0)), until_ms)
		_manual_spike_until_ms[target] = target_until_ms
		_defer_queued_packets_until(target, target_until_ms, "lag_spike")
	_increment("network_simulator_manual_lag_spikes")
	_update_telemetry()
	return TransportUtilsScript.success({"directions": targets, "until_ms": until_ms})


func trigger_disconnect_blackout(direction: String = "BOTH", duration_ms: int = -1) -> Dictionary:
	var targets: Array = _normalize_directions(direction)
	if targets.is_empty():
		return TransportUtilsScript.failure("INVALID_SIMULATOR_DIRECTION")
	var effective_duration: int = duration_ms
	if effective_duration < 0:
		effective_duration = int(_profile.get("disconnect_duration_ms", 0))
	if effective_duration < 1:
		return TransportUtilsScript.failure("INVALID_DISCONNECT_DURATION")
	var until_ms: int = _now_ms() + effective_duration
	for target in targets:
		var target_until_ms: int = maxi(int(_blackout_until_ms.get(target, 0)), until_ms)
		_blackout_until_ms[target] = target_until_ms
		_defer_queued_packets_until(target, target_until_ms, "blackout")
	_increment("network_simulator_disconnect_blackouts")
	_update_telemetry()
	return TransportUtilsScript.success({"directions": targets, "until_ms": until_ms})


func get_runtime_snapshot() -> Dictionary:
	return {
		"schema": SIMULATOR_SCHEMA,
		"configured": _configured,
		"started": _started,
		"mode": _mode,
		"clock_mode": _clock_mode,
		"now_ms": _now_ms(),
		"profile": _profile.duplicate(true),
		"profile_generation": _profile_generation,
		"passthrough": _passthrough,
		"outgoing_queue_messages": _outgoing_queue.size(),
		"outgoing_queue_bytes": int(_queued_bytes.get(OUTGOING, 0)),
		"incoming_queue_messages": _incoming_queue.size(),
		"incoming_queue_bytes": int(_queued_bytes.get(INCOMING, 0)),
		"ready_events": _ready_events.size(),
		"ready_message_events": _ready_message_event_count(),
		"ready_message_events_blocked": (
			_ready_message_event_count()
			if _now_ms() < _delivery_blocked_until_ms(INCOMING) else 0
		),
		"blackout_until_ms": _blackout_until_ms.duplicate(true),
		"manual_spike_until_ms": _manual_spike_until_ms.duplicate(true),
		"counters": _counters.duplicate(true),
		"delegate": (
			_delegate.get_runtime_snapshot().duplicate(true)
			if _delegate != null and _delegate.has_method("get_runtime_snapshot") else {}
		),
	}


func _plan_packet(direction: String, peer_id: String, frame: Dictionary, packet_bytes: int) -> Dictionary:
	var now_ms: int = _now_ms()
	var channel: String = String(frame.get("channel", "UNKNOWN"))
	var stream_key: String = "%s|%s" % [direction, channel]
	var packet_index: int = int(_packet_counts.get(stream_key, 0)) + 1
	_packet_counts[stream_key] = packet_index
	var reliable: bool = _is_reliable(frame)
	var blackout_until: int = int(_blackout_until_ms.get(direction, 0))
	if int(_profile.get("disconnect_duration_ms", 0)) > 0 and packet_index % DISCONNECT_INTERVAL_PACKETS == 0:
		blackout_until = maxi(blackout_until, now_ms + int(_profile["disconnect_duration_ms"]))
		_blackout_until_ms[direction] = blackout_until
		_increment("network_simulator_periodic_disconnect_blackouts")
	var in_blackout: bool = now_ms < blackout_until
	var burst_hit: bool = _burst_loss_hit(direction, channel, now_ms)
	var loss_hit: bool = in_blackout or burst_hit or _chance(
		"%s|%s|loss" % [direction, channel], float(_profile.get("packet_loss_percent", 0.0))
	)
	if loss_hit and not reliable:
		return {"drop": true, "due_ms": now_ms, "duplicate": false}
	var latency_ms: int = _latency_ms(direction, channel)
	var due_ms: int = now_ms + latency_ms
	if loss_hit and reliable:
		var retry_ms: int = maxi(RELIABLE_RETRANSMISSION_MIN_MS, latency_ms * 2 + 1)
		due_ms += retry_ms
		_increment("network_simulator_reliable_retransmissions_simulated")
		_observe("network_simulator_retransmission_delay_ms", float(retry_ms))
	if in_blackout:
		due_ms = maxi(due_ms, blackout_until)
	var spike_ms: int = 0
	if now_ms < int(_manual_spike_until_ms.get(direction, 0)):
		spike_ms = int(_manual_spike_until_ms[direction]) - now_ms
	elif int(_profile.get("lag_spike_ms", 0)) > 0 and packet_index % LAG_SPIKE_INTERVAL_PACKETS == 0:
		spike_ms = int(_profile["lag_spike_ms"])
		_increment("network_simulator_periodic_lag_spikes")
	if spike_ms > 0:
		due_ms += spike_ms
		_observe("network_simulator_lag_spike_delay_ms", float(spike_ms))
	var reorder_hit: bool = _chance(
		"%s|%s|reorder" % [direction, channel], float(_profile.get("reorder_percent", 0.0))
	)
	if reorder_hit and packet_index % 2 == 1:
		var reorder_delay: int = maxi(
			1,
			int(_profile.get("jitter_ms", 0))
			+ _latency_max_ms(direction)
			+ 1
		)
		due_ms += reorder_delay
		_increment("network_simulator_reorder_events")
		_observe("network_simulator_reorder_hold_ms", float(reorder_delay))
	due_ms = _apply_bandwidth(direction, due_ms, packet_bytes)
	var duplicate: bool = (
		not reliable
		and _chance("%s|%s|duplicate" % [direction, channel], float(_profile.get("duplicate_percent", 0.0)))
	)
	_observe("network_simulator_%s_scheduled_delay_ms" % direction.to_lower(), float(maxi(due_ms - now_ms, 0)))
	return {
		"drop": false,
		"due_ms": due_ms,
		"duplicate": duplicate,
		"reliable": reliable,
		"packet_index": packet_index,
		"peer_id": peer_id,
	}


func _latency_ms(direction: String, channel: String) -> int:
	var prefix: String = "outgoing" if direction == OUTGOING else "incoming"
	var minimum: int = int(_profile.get("%s_latency_min_ms" % prefix, 0))
	var maximum: int = int(_profile.get("%s_latency_max_ms" % prefix, 0))
	var base: int = _rng("%s|%s|latency" % [direction, channel]).next_int(minimum, maximum)
	var jitter: int = int(_profile.get("jitter_ms", 0))
	if jitter > 0:
		base += _rng("%s|%s|jitter" % [direction, channel]).next_int(-jitter, jitter)
	return maxi(base, 0)


func _latency_max_ms(direction: String) -> int:
	return int(_profile.get(
		"outgoing_latency_max_ms" if direction == OUTGOING else "incoming_latency_max_ms",
		0
	))


func _burst_loss_hit(direction: String, channel: String, now_ms: int) -> bool:
	var key: String = "%s|%s" % [direction, channel]
	var until_ms: int = int(_burst_until_ms.get(key, 0))
	if now_ms < until_ms:
		_increment("network_simulator_burst_loss_packets")
		return true
	var probability: float = float(_profile.get("burst_loss_probability_percent", 0.0))
	var duration_ms: int = int(_profile.get("burst_loss_duration_ms", 0))
	if duration_ms > 0 and _chance("%s|burst" % key, probability):
		_burst_until_ms[key] = now_ms + duration_ms
		_increment("network_simulator_burst_loss_windows")
		_increment("network_simulator_burst_loss_packets")
		return true
	return false


func _apply_bandwidth(direction: String, due_ms: int, packet_bytes: int) -> int:
	var limit_kbps: int = int(_profile.get("bandwidth_limit_kbps", 0))
	if limit_kbps < 1:
		return due_ms
	var available_ms: int = maxi(due_ms, int(_bandwidth_available_at_ms.get(direction, due_ms)))
	var serialization_ms: int = maxi(1, int(ceil(float(packet_bytes * 8) / float(limit_kbps))))
	_bandwidth_available_at_ms[direction] = available_ms + serialization_ms
	_observe("network_simulator_bandwidth_queue_delay_ms", float(maxi(available_ms - due_ms, 0)))
	_observe("network_simulator_serialization_delay_ms", float(serialization_ms))
	return available_ms


func _enqueue_outgoing(peer_id: String, frame: Dictionary, packet_bytes: int, plan: Dictionary, duplicate: bool) -> void:
	_order_sequence += 1
	_outgoing_queue.append({
		"direction": OUTGOING,
		"peer_id": peer_id,
		"frame": frame.duplicate(true),
		"packet_bytes": packet_bytes,
		"due_ms": int(plan.get("due_ms", _now_ms())),
		"enqueued_at_ms": _now_ms(),
		"order": _order_sequence,
		"attempts": 0,
		"duplicate": duplicate,
		"reliable": _is_reliable(frame),
	})
	_queued_bytes[OUTGOING] = int(_queued_bytes.get(OUTGOING, 0)) + packet_bytes
	_increment("network_simulator_outgoing_packets_queued")


func _enqueue_incoming(event: Dictionary, packet_bytes: int, plan: Dictionary, duplicate: bool) -> void:
	_order_sequence += 1
	_incoming_queue.append({
		"direction": INCOMING,
		"peer_id": String(event.get("peer_id", "")),
		"event": event.duplicate(true),
		"frame": Dictionary(event.get("frame", {})).duplicate(true),
		"packet_bytes": packet_bytes,
		"due_ms": int(plan.get("due_ms", _now_ms())),
		"enqueued_at_ms": _now_ms(),
		"order": _order_sequence,
		"duplicate": duplicate,
		"reliable": _is_reliable(event.get("frame", {})),
	})
	_queued_bytes[INCOMING] = int(_queued_bytes.get(INCOMING, 0)) + packet_bytes
	_increment("network_simulator_incoming_packets_queued")


func _dispatch_due_outgoing(limit: int) -> void:
	var dispatched: int = 0
	while dispatched < limit:
		var index: int = _next_due_index(_outgoing_queue, OUTGOING)
		if index < 0:
			break
		var item: Dictionary = _outgoing_queue[index]
		item["attempts"] = int(item.get("attempts", 0)) + 1
		var result: Dictionary = _normalize_result(
			_delegate.send_to_peer(String(item.get("peer_id", "")), Dictionary(item.get("frame", {})).duplicate(true))
		)
		if not bool(result.get("success", false)) and bool(item.get("reliable", false)):
			item["due_ms"] = _now_ms() + SEND_RETRY_MS
			_outgoing_queue[index] = item
			_increment("network_simulator_delegate_send_retries")
			break
		_outgoing_queue.remove_at(index)
		_queued_bytes[OUTGOING] = maxi(0, int(_queued_bytes.get(OUTGOING, 0)) - int(item.get("packet_bytes", 0)))
		if bool(result.get("success", false)):
			_increment("network_simulator_outgoing_packets_delivered")
			_observe("network_simulator_outgoing_actual_delay_ms", float(maxi(_now_ms() - int(item.get("enqueued_at_ms", _now_ms())), 0)))
		else:
			_increment("network_simulator_unreliable_delegate_send_drops")
		dispatched += 1


func _ingest_delegate_event(event: Dictionary) -> void:
	var event_type: String = String(event.get("event_type", ""))
	if event_type != "MESSAGE_RECEIVED":
		if event_type == "PEER_DISCONNECTED":
			_clear_peer_queues(String(event.get("peer_id", "")))
		_ready_events.append(event.duplicate(true))
		return
	var frame: Dictionary = event.get("frame", {})
	var packet_bytes: int = int(event.get("details", {}).get("packet_bytes", 0))
	if packet_bytes < 1:
		packet_bytes = NetworkUtilsScript.canonical_json(frame).to_utf8_buffer().size()
	if _passthrough and not _has_active_manual_condition(INCOMING):
		_increment("network_simulator_packets_passthrough")
		_ready_events.append(event.duplicate(true))
		return
	var plan: Dictionary = _plan_packet(INCOMING, String(event.get("peer_id", "")), frame, packet_bytes)
	if bool(plan.get("drop", false)):
		_increment("network_simulator_unreliable_packets_dropped")
		return
	if not _can_queue(INCOMING, packet_bytes):
		if _is_reliable(frame):
			_increment("network_simulator_reliable_queue_limit_bypasses")
		else:
			_increment("network_simulator_unreliable_queue_drops")
			return
	_enqueue_incoming(event, packet_bytes, plan, false)
	if bool(plan.get("duplicate", false)):
		if _can_queue(INCOMING, packet_bytes):
			var duplicate_plan: Dictionary = plan.duplicate(true)
			duplicate_plan["due_ms"] = int(plan.get("due_ms", _now_ms())) + 1
			_enqueue_incoming(event, packet_bytes, duplicate_plan, true)
			_increment("network_simulator_datagrams_duplicated")
		else:
			_increment("network_simulator_duplicate_queue_suppressed")


func _release_due_incoming(limit: int) -> void:
	var released: int = 0
	while released < limit:
		var index: int = _next_due_index(_incoming_queue, INCOMING)
		if index < 0:
			break
		var item: Dictionary = _incoming_queue[index]
		_incoming_queue.remove_at(index)
		_queued_bytes[INCOMING] = maxi(0, int(_queued_bytes.get(INCOMING, 0)) - int(item.get("packet_bytes", 0)))
		_ready_events.append(Dictionary(item.get("event", {})).duplicate(true))
		_increment("network_simulator_incoming_packets_delivered")
		_observe("network_simulator_incoming_actual_delay_ms", float(maxi(_now_ms() - int(item.get("enqueued_at_ms", _now_ms())), 0)))
		released += 1


func _take_ready_events(max_events: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if max_events < 1 or _ready_events.is_empty():
		return result
	if _now_ms() >= _delivery_blocked_until_ms(INCOMING):
		var count: int = mini(max_events, _ready_events.size())
		for _index in range(count):
			result.append(_ready_events.pop_front())
		return result
	var retained: Array[Dictionary] = []
	for event: Dictionary in _ready_events:
		if result.size() < max_events and String(event.get("event_type", "")) != "MESSAGE_RECEIVED":
			result.append(event)
		else:
			retained.append(event)
	_ready_events = retained
	if not result.is_empty():
		_increment("network_simulator_lifecycle_events_delivered_during_incoming_block", result.size())
	return result


func _ready_message_event_count() -> int:
	var count: int = 0
	for event: Dictionary in _ready_events:
		if String(event.get("event_type", "")) == "MESSAGE_RECEIVED":
			count += 1
	return count


func _next_due_index(queue: Array[Dictionary], direction: String) -> int:
	var now_ms: int = _now_ms()
	if now_ms < _delivery_blocked_until_ms(direction):
		return -1
	var best_index: int = -1
	var best_due: int = 0
	var best_order: int = 0
	for index in range(queue.size()):
		var item: Dictionary = queue[index]
		var due_ms: int = int(item.get("due_ms", 0))
		if due_ms > now_ms:
			continue
		if bool(item.get("reliable", false)) and _has_earlier_reliable_item(queue, index):
			continue
		var order: int = int(item.get("order", 0))
		if best_index < 0 or due_ms < best_due or (due_ms == best_due and order < best_order):
			best_index = index
			best_due = due_ms
			best_order = order
	return best_index


func _has_earlier_reliable_item(queue: Array[Dictionary], candidate_index: int) -> bool:
	var candidate: Dictionary = queue[candidate_index]
	var peer_id: String = String(candidate.get("peer_id", ""))
	var candidate_frame: Dictionary = candidate.get("frame", {})
	var candidate_stream: String = _transport_stream_key(peer_id, candidate_frame)
	var sequence: int = int(candidate_frame.get("sequence", 0))
	for index in range(queue.size()):
		if index == candidate_index:
			continue
		var other: Dictionary = queue[index]
		if not bool(other.get("reliable", false)) or String(other.get("peer_id", "")) != peer_id:
			continue
		var other_frame: Dictionary = other.get("frame", {})
		if _transport_stream_key(peer_id, other_frame) != candidate_stream:
			continue
		var other_sequence: int = int(other_frame.get("sequence", 0))
		if other_sequence < sequence:
			return true
		if other_sequence == sequence and int(other.get("order", 0)) < int(candidate.get("order", 0)):
			return true
	return false


func _defer_queued_packets_until(direction: String, until_ms: int, reason: String) -> void:
	var queue: Array[Dictionary] = _outgoing_queue if direction == OUTGOING else _incoming_queue
	var deferred: int = 0
	for index in range(queue.size()):
		var item: Dictionary = queue[index]
		if int(item.get("due_ms", 0)) >= until_ms:
			continue
		item["due_ms"] = until_ms
		queue[index] = item
		deferred += 1
	if deferred > 0:
		_increment("network_simulator_queued_packets_deferred_by_%s" % reason, deferred)


func _delivery_blocked_until_ms(direction: String) -> int:
	return maxi(
		int(_manual_spike_until_ms.get(direction, 0)),
		int(_blackout_until_ms.get(direction, 0))
	)


func _transport_stream_key(peer_id: String, frame: Dictionary) -> String:
	return "%s|%s" % [peer_id, ChannelPolicyScript.sequence_stream(frame)]


func _can_queue(direction: String, packet_bytes: int) -> bool:
	var limit_bytes: int = int(_profile.get("queue_limit_bytes", 0))
	return limit_bytes < 1 or int(_queued_bytes.get(direction, 0)) + packet_bytes <= limit_bytes


func _clear_peer_queues(peer_id: String) -> void:
	for queue_info in [[_outgoing_queue, OUTGOING], [_incoming_queue, INCOMING]]:
		var queue: Array = queue_info[0]
		var direction: String = String(queue_info[1])
		for index in range(queue.size() - 1, -1, -1):
			if String(queue[index].get("peer_id", "")) == peer_id:
				_queued_bytes[direction] = maxi(0, int(_queued_bytes.get(direction, 0)) - int(queue[index].get("packet_bytes", 0)))
				queue.remove_at(index)
	for index in range(_ready_events.size() - 1, -1, -1):
		if String(_ready_events[index].get("peer_id", "")) == peer_id and String(_ready_events[index].get("event_type", "")) == "MESSAGE_RECEIVED":
			_ready_events.remove_at(index)


func _is_reliable(frame: Dictionary) -> bool:
	return String(frame.get("delivery_mode", "")).begins_with("RELIABLE")


func _chance(stream_key: String, percent: float) -> bool:
	if percent <= 0.0:
		return false
	if percent >= 100.0:
		return true
	return _rng(stream_key).next_percent() < percent


func _rng(stream_key: String):
	if not _stream_rngs.has(stream_key):
		var rng = RngScript.new()
		var seed: int = RngScript.derive_seed(int(_profile.get("random_seed", 1)), stream_key)
		rng.configure(seed)
		_stream_rngs[stream_key] = rng
	return _stream_rngs[stream_key]


func _now_ms() -> int:
	return _manual_now_ms if _clock_mode == CLOCK_MANUAL else Time.get_ticks_msec()


func _has_active_manual_condition(direction: String) -> bool:
	var now_ms: int = _now_ms()
	return (
		now_ms < int(_manual_spike_until_ms.get(direction, 0))
		or now_ms < int(_blackout_until_ms.get(direction, 0))
	)


func _normalize_directions(direction: String) -> Array[String]:
	var normalized: String = direction.strip_edges().to_upper()
	if normalized == "BOTH":
		return DIRECTIONS.duplicate()
	return [normalized] if normalized in DIRECTIONS else []


func _update_telemetry() -> void:
	_set_gauge("network_simulator_outgoing_queue_messages", float(_outgoing_queue.size()))
	_set_gauge("network_simulator_outgoing_queue_bytes", float(_queued_bytes.get(OUTGOING, 0)))
	_set_gauge("network_simulator_incoming_queue_messages", float(_incoming_queue.size()))
	_set_gauge("network_simulator_incoming_queue_bytes", float(_queued_bytes.get(INCOMING, 0)))
	_set_gauge("network_simulator_ready_events", float(_ready_events.size()))
	_set_gauge("network_simulator_ready_message_events", float(_ready_message_event_count()))
	_set_gauge(
		"network_simulator_ready_message_events_blocked",
		float(_ready_message_event_count() if _now_ms() < _delivery_blocked_until_ms(INCOMING) else 0)
	)
	_set_gauge("network_simulator_profile_generation", float(_profile_generation))
	_set_gauge("network_simulator_outgoing_blackout_remaining_ms", float(maxi(int(_blackout_until_ms.get(OUTGOING, 0)) - _now_ms(), 0)))
	_set_gauge("network_simulator_incoming_blackout_remaining_ms", float(maxi(int(_blackout_until_ms.get(INCOMING, 0)) - _now_ms(), 0)))


func _increment(name: String, amount: int = 1) -> void:
	_counters[name] = int(_counters.get(name, 0)) + amount
	if _telemetry != null:
		_telemetry.increment(name, amount)


func _set_gauge(name: String, value: float) -> void:
	if _telemetry != null:
		_telemetry.set_gauge(name, value)


func _observe(name: String, value: float) -> void:
	if _telemetry != null:
		_telemetry.observe(name, value)


func _with_simulator_details(result: Dictionary, packet_bytes: int, simulated: bool, dropped: bool, scheduled_at_ms: int) -> Dictionary:
	if not bool(result.get("success", false)):
		return result
	var details: Dictionary = result.get("details", {}).duplicate(true)
	details["packet_bytes"] = int(details.get("packet_bytes", packet_bytes))
	details["simulated"] = simulated
	details["dropped"] = dropped
	details["scheduled_at_ms"] = scheduled_at_ms
	details["profile_id"] = String(_profile.get("profile_id", ""))
	return TransportUtilsScript.success(details)


func _is_port(value) -> bool:
	if value == null or not value is RefCounted:
		return false
	var script = value.get_script()
	while script != null:
		if script == BasePortScript:
			return true
		script = script.get_base_script()
	return false


func _is_telemetry_collector(value) -> bool:
	if value == null or not value is RefCounted:
		return false
	for method_name in ["increment", "set_gauge", "observe"]:
		if not value.has_method(method_name):
			return false
	return true


func _normalize_result(value) -> Dictionary:
	if not value is Dictionary or typeof(value.get("success")) != TYPE_BOOL:
		return TransportUtilsScript.failure("INVALID_DELEGATE_RESULT")
	return {
		"success": bool(value.get("success", false)),
		"error_code": String(value.get("error_code", "")),
		"details": Dictionary(value.get("details", {})).duplicate(true),
	}

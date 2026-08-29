extends "res://scripts/runtime/seamless/sm0/sm0_manual_client_node.gd"

# SM0-P3.1 branch-local client egress shaper. The manual client state machine is
# unchanged; only UDP delivery time is delayed.

const NetContracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")
const NETWORK_PROFILE := "p31-controlled-latency-v1"

var _net_profile := ""
var _net_base_latency_ms := 0
var _net_jitter_ms := 0
var _net_seed := 431
var _net_enabled := false
var _net_queue: Array[Dictionary] = []
var _net_last_due_ms := 0


func setup(config: Dictionary) -> Dictionary:
	_net_profile = String(config.get("network_profile", "")).strip_edges()
	_net_base_latency_ms = clampi(int(config.get("network_latency_ms", 0)), 0, 10000)
	_net_jitter_ms = clampi(int(config.get("network_jitter_ms", 0)), 0, 5000)
	_net_seed = int(config.get("network_seed", 431))
	_net_enabled = _net_profile == NETWORK_PROFILE and _net_base_latency_ms > 0
	if _net_jitter_ms > _net_base_latency_ms:
		return _failure("SM0_NET_JITTER_EXCEEDS_BASE_LATENCY")
	var result: Dictionary = super.setup(config)
	if not bool(result.get("success", false)):
		return result
	if _net_enabled:
		_event("SM0_NET_PROFILE_ENABLED", {
			"network_profile": _net_profile,
			"base_latency_ms": _net_base_latency_ms,
			"jitter_ms": _net_jitter_ms,
			"seed": _net_seed,
			"loss_percent": 0,
			"duplicate_percent": 0,
			"reorder_percent": 0,
			"scope": "client-egress",
		})
	return result


func _process(delta: float) -> void:
	super._process(delta)
	_net_flush_due()


func _send_message(message: Dictionary) -> void:
	if not _net_enabled:
		super._send_message(message)
		return
	_net_schedule(_server_host, _current_server_port, message)


func _send_message_to(host: String, port: int, message: Dictionary) -> void:
	if not _net_enabled:
		super._send_message_to(host, port, message)
		return
	_net_schedule(host, port, message)


func _net_schedule(host: String, port: int, message: Dictionary) -> void:
	if _socket == null or host.is_empty() or port < 1:
		return
	var message_type := String(message.get("type", ""))
	var request_id := String(message.get("request_id", ""))
	var now := Time.get_ticks_msec()
	var jitter_offset := _net_jitter_for(message_type, request_id, host, port)
	var requested_delay := maxi(0, _net_base_latency_ms + jitter_offset)
	var due_ms := maxi(now + requested_delay, _net_last_due_ms + 1)
	_net_last_due_ms = due_ms
	var scheduled_delay := maxi(0, due_ms - now)
	_net_queue.append({
		"due_ms": due_ms,
		"host": host,
		"port": port,
		"message": message.duplicate(true),
	})
	if _net_should_trace(message_type):
		_event("SM0_NET_DELAY_SCHEDULED", {
			"network_profile": _net_profile,
			"channel": "gameplay",
			"message_type": message_type,
			"request_id": request_id,
			"requested_delay_ms": requested_delay,
			"scheduled_delay_ms": scheduled_delay,
			"jitter_offset_ms": jitter_offset,
			"destination_port": port,
		})


func _net_flush_due() -> void:
	if not _net_enabled or _net_queue.is_empty() or _socket == null:
		return
	var now := Time.get_ticks_msec()
	var remaining: Array[Dictionary] = []
	for queued in _net_queue:
		if int(queued.get("due_ms", 0)) > now:
			remaining.append(queued)
			continue
		var host := String(queued.get("host", ""))
		var port := int(queued.get("port", 0))
		if host.is_empty() or port < 1:
			continue
		if _socket.set_dest_address(host, port) != OK:
			continue
		_socket.put_packet(NetContracts.encode_message(Dictionary(queued.get("message", {}))))
		_socket.set_dest_address(_server_host, _current_server_port)
	_net_queue = remaining


func _net_jitter_for(message_type: String, request_id: String, host: String, port: int) -> int:
	if _net_jitter_ms <= 0:
		return 0
	var key := "%d|client/a|%s|%s|%s|%d" % [_net_seed, message_type, request_id, host, port]
	var value := absi(_net_seed) % 2147483647
	for byte_value in key.to_utf8_buffer():
		value = (value * 131 + int(byte_value) + 17) % 2147483647
	var span := _net_jitter_ms * 2 + 1
	return int(value % span) - _net_jitter_ms


func _net_should_trace(message_type: String) -> bool:
	return message_type in ["CLIENT_REDIRECT_ACK", "CLIENT_ACTIVATE"]

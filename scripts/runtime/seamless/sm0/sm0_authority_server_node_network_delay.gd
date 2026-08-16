extends "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_p4_closure.gd"

# SM0-P3.1 branch-local transport shaper.
# It delays UDP egress only. Authority mutation/order remains inherited from the
# healthy server. No packet is intentionally lost, duplicated or reordered.

const NetContracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")
const NETWORK_PROFILE := "p31-controlled-latency-v1"

var _net_profile := ""
var _net_base_latency_ms := 0
var _net_jitter_ms := 0
var _net_seed := 431
var _net_enabled := false
var _net_queue: Array[Dictionary] = []
var _net_last_control_due_ms := 0
var _net_last_gameplay_due_ms := 0


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
			"scope": "authority-egress",
		})
	return result


func _process(delta: float) -> void:
	super._process(delta)
	_net_flush_due()


func _send_control(message_type: String, payload: Dictionary, request_id: String = "") -> void:
	if not _net_enabled:
		super._send_control(message_type, payload, request_id)
		return
	_net_schedule(
		"control",
		_peer_control_host,
		_peer_control_port,
		message_type,
		payload,
		request_id
	)


func _send_gameplay(host: String, port: int, message_type: String, payload: Dictionary, request_id: String = "") -> void:
	if not _net_enabled:
		super._send_gameplay(host, port, message_type, payload, request_id)
		return
	_net_schedule("gameplay", host, port, message_type, payload, request_id)


func _net_schedule(
	channel: String,
	host: String,
	port: int,
	message_type: String,
	payload: Dictionary,
	request_id: String
) -> void:
	if host.is_empty() or port < 1:
		return
	var now := Time.get_ticks_msec()
	var jitter_offset := _net_jitter_for(message_type, request_id, host, port)
	var requested_delay := maxi(0, _net_base_latency_ms + jitter_offset)
	var due_ms := now + requested_delay
	if channel == "control":
		due_ms = maxi(due_ms, _net_last_control_due_ms + 1)
		_net_last_control_due_ms = due_ms
	else:
		due_ms = maxi(due_ms, _net_last_gameplay_due_ms + 1)
		_net_last_gameplay_due_ms = due_ms
	var scheduled_delay := maxi(0, due_ms - now)
	_net_queue.append({
		"due_ms": due_ms,
		"channel": channel,
		"host": host,
		"port": port,
		"message_type": message_type,
		"payload": payload.duplicate(true),
		"request_id": request_id,
	})
	if _net_should_trace(message_type):
		_event("SM0_NET_DELAY_SCHEDULED", {
			"network_profile": _net_profile,
			"channel": channel,
			"message_type": message_type,
			"request_id": request_id,
			"requested_delay_ms": requested_delay,
			"scheduled_delay_ms": scheduled_delay,
			"jitter_offset_ms": jitter_offset,
			"destination_port": port,
		})


func _net_flush_due() -> void:
	if not _net_enabled or _net_queue.is_empty():
		return
	var now := Time.get_ticks_msec()
	var remaining: Array[Dictionary] = []
	for queued in _net_queue:
		if int(queued.get("due_ms", 0)) > now:
			remaining.append(queued)
			continue
		var channel := String(queued.get("channel", ""))
		var socket: PacketPeerUDP = _control_socket if channel == "control" else _gameplay_socket
		_net_send_direct(
			socket,
			String(queued.get("host", "")),
			int(queued.get("port", 0)),
			String(queued.get("message_type", "")),
			Dictionary(queued.get("payload", {})),
			String(queued.get("request_id", ""))
		)
	_net_queue = remaining


func _net_send_direct(
	socket: PacketPeerUDP,
	host: String,
	port: int,
	message_type: String,
	payload: Dictionary,
	request_id: String
) -> void:
	if socket == null or host.is_empty() or port < 1:
		return
	if socket.set_dest_address(host, port) != OK:
		return
	var message := NetContracts.create_message(message_type, payload, request_id)
	socket.put_packet(NetContracts.encode_message(message))


func _net_jitter_for(message_type: String, request_id: String, host: String, port: int) -> int:
	if _net_jitter_ms <= 0:
		return 0
	var sender := _authority_id
	var key := "%d|%s|%s|%s|%s|%d" % [_net_seed, sender, message_type, request_id, host, port]
	var value := absi(_net_seed) % 2147483647
	for byte_value in key.to_utf8_buffer():
		value = (value * 131 + int(byte_value) + 17) % 2147483647
	var span := _net_jitter_ms * 2 + 1
	return int(value % span) - _net_jitter_ms


func _net_should_trace(message_type: String) -> bool:
	return (
		message_type.begins_with("PLAYER_HANDOFF_")
		or message_type in ["HANDOFF_REDIRECT", "ACTIVATE_ACK"]
	)

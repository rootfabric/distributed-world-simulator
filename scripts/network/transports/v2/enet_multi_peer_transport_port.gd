extends "res://scripts/network/transports/v2/network_transport_port_v2.gd"

const EndpointScript = preload("res://scripts/network/contracts/network_endpoint.gd")
const EventScript = preload("res://scripts/network/transports/v2/network_transport_event.gd")
const FrameScript = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")
const ChannelPolicyScript = preload("res://scripts/network/realtime/realtime_channel_policy.gd")

const MAX_CLIENTS: int = 32
const MAX_CHANNELS: int = ChannelPolicyScript.ENET_CHANNEL_COUNT
const MAX_PACKET_BYTES: int = 1048576
const PHYSICAL_FRAME_BINDING_POLICY: String = "STRICT_CHANNEL_AND_TRANSFER_MODE_V1"
const PHYSICAL_MISMATCH_HANDLING_POLICY: String = "PEER_LOCAL_QUARANTINE_V1"

var _peer: ENetMultiplayerPeer
var _mode: String = ""
var _events: Array[Dictionary] = []
var _logical_to_numeric: Dictionary = {}
var _numeric_to_logical: Dictionary = {}
var _session_by_peer: Dictionary = {}
var _route_by_peer: Dictionary = {}
var _route_generation_by_peer: Dictionary = {}
var _packet_peer_by_peer: Dictionary = {}
var _event_sequence: int = 0
var _client_peer_id: String = ""
var _client_session_id: String = ""
var _client_route_id: String = ""
var _client_route_generation: int = 0
var _client_connected_emitted: bool = false
var _last_status: int = MultiplayerPeer.CONNECTION_DISCONNECTED


func get_descriptor() -> Dictionary:
	return {
		"schema": SCHEMA,
		"transport_kind": "ENET_MULTI_PEER",
		"supports_server": true,
		"supports_client": true,
		"synchronous_delivery": false,
		"multi_peer": true,
		"max_peers": MAX_CLIENTS,
	}


func start_server(endpoint: Dictionary) -> Dictionary:
	if _peer != null:
		return TransportUtilsScript.failure("ALREADY_STARTED")
	var check: Dictionary = _validate_endpoint(endpoint)
	if not bool(check.get("success", false)):
		return check
	_peer = ENetMultiplayerPeer.new()
	if String(endpoint["host"]) != "*":
		_peer.set_bind_ip(String(endpoint["host"]))
	var error: Error = _peer.create_server(int(endpoint["port"]), MAX_CLIENTS, MAX_CHANNELS)
	if error != OK:
		_peer = null
		return TransportUtilsScript.failure("ENET_SERVER_CREATE_FAILED", {"godot_error": int(error)})
	_mode = "SERVER"
	_last_status = _peer.get_connection_status()
	_append_event("LISTENER_STARTED", "", "", 0, {}, "", {"endpoint": endpoint.duplicate(true)})
	return TransportUtilsScript.success()


func connect_client(endpoint: Dictionary, peer_id: String, session_id: String, route_id: String, route_generation: int) -> Dictionary:
	if _peer != null:
		return TransportUtilsScript.failure("ALREADY_STARTED")
	var check: Dictionary = _validate_endpoint(endpoint)
	if not bool(check.get("success", false)):
		return check
	if not TransportUtilsScript.is_canonical_transport_id(peer_id, "peer") or not TransportUtilsScript.is_canonical_transport_id(session_id, "transport-session"):
		return TransportUtilsScript.failure("INVALID_CLIENT_SESSION")
	if not TransportUtilsScript.is_canonical_transport_id(route_id, "route") or route_generation < 1:
		return TransportUtilsScript.failure("INVALID_CLIENT_ROUTE")
	_peer = ENetMultiplayerPeer.new()
	var error: Error = _peer.create_client(String(endpoint["host"]), int(endpoint["port"]), MAX_CHANNELS)
	if error != OK:
		_peer = null
		return TransportUtilsScript.failure("ENET_CLIENT_CREATE_FAILED", {"godot_error": int(error)})
	_mode = "CLIENT"
	_client_peer_id = peer_id
	_client_session_id = session_id
	_client_route_id = route_id
	_client_route_generation = route_generation
	_logical_to_numeric[peer_id] = MultiplayerPeer.TARGET_PEER_SERVER
	_session_by_peer[peer_id] = session_id
	_route_by_peer[peer_id] = route_id
	_route_generation_by_peer[peer_id] = route_generation
	_last_status = _peer.get_connection_status()
	return TransportUtilsScript.success()


func disconnect_peer(peer_id: String, session_id: String) -> Dictionary:
	if _peer == null or not _session_by_peer.has(peer_id):
		return TransportUtilsScript.success({"replay": true})
	if String(_session_by_peer[peer_id]) != session_id:
		return TransportUtilsScript.failure("SESSION_MISMATCH")
	var numeric_id: int = int(_logical_to_numeric.get(peer_id, 0))
	if _mode == "SERVER" and numeric_id > 0:
		_peer.disconnect_peer(numeric_id, false)
	elif _mode == "CLIENT":
		_peer.close()
	_remove_peer(peer_id)
	_append_event("PEER_DISCONNECTED", peer_id, session_id)
	return TransportUtilsScript.success({"replay": false})


func send_to_peer(peer_id: String, frame: Dictionary) -> Dictionary:
	if _peer == null:
		return TransportUtilsScript.failure("ENET_NOT_STARTED")
	var check: Dictionary = FrameScript.validate(frame)
	if not bool(check.get("success", false)):
		return TransportUtilsScript.failure(String(check.get("error_code", "INVALID_FRAME")))
	if not _logical_to_numeric.has(peer_id):
		return TransportUtilsScript.failure("UNKNOWN_PEER")
	if _session_by_peer.has(peer_id) and String(_session_by_peer[peer_id]) != String(frame.get("session_id", "")):
		return TransportUtilsScript.failure("SESSION_MISMATCH")
	var encoded: Dictionary = FrameScript.encode(frame, MAX_PACKET_BYTES)
	if not bool(encoded.get("success", false)):
		return encoded
	var channel: int = _channel_index(String(frame["channel"]))
	_peer.transfer_channel = channel
	_peer.set_target_peer(int(_logical_to_numeric[peer_id]))
	var transfer_mode: int = _transfer_mode(String(frame["delivery_mode"]))
	_peer.transfer_mode = transfer_mode
	var error: Error = _peer.put_packet(encoded.get("details", {}).get("packet", PackedByteArray()))
	if error != OK:
		return TransportUtilsScript.failure("ENET_SEND_FAILED", {"godot_error": int(error)})
	return TransportUtilsScript.success({
		"enqueued": true,
		"packet_bytes": int(encoded.get("details", {}).get("packet_bytes", 0)),
		"channel_index": channel,
		"frame_channel": String(frame["channel"]),
		"delivery_mode": String(frame["delivery_mode"]),
		"transfer_mode": transfer_mode,
		"peer_statistics": _peer_statistics(peer_id),
	})


func poll_events(max_events: int) -> Array[Dictionary]:
	if max_events < 1:
		return []
	_poll_peer()
	var result: Array[Dictionary] = []
	var count: int = mini(max_events, _events.size())
	for _index in range(count):
		result.append(_events.pop_front())
	return result


func drain() -> Dictionary:
	if _peer != null and _mode == "SERVER":
		_peer.refuse_new_connections = true
	_append_event("LISTENER_DRAINING")
	return TransportUtilsScript.success()


func stop() -> Dictionary:
	if _peer != null:
		_peer.close()
	_peer = null
	_mode = ""
	_logical_to_numeric.clear()
	_numeric_to_logical.clear()
	_session_by_peer.clear()
	_route_by_peer.clear()
	_route_generation_by_peer.clear()
	_packet_peer_by_peer.clear()
	_client_peer_id = ""
	_client_session_id = ""
	_client_route_id = ""
	_client_route_generation = 0
	_client_connected_emitted = false
	_last_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	_append_event("LISTENER_STOPPED")
	return TransportUtilsScript.success()


func get_runtime_snapshot() -> Dictionary:
	return {
		"mode": _mode,
		"started": _peer != null,
		"peer_count": _logical_to_numeric.size(),
		"logical_to_numeric": _logical_to_numeric.duplicate(true),
		"queued_events": _events.size(),
		"peer_statistics": _all_peer_statistics(),
	}


func _poll_peer() -> void:
	if _peer == null:
		return
	var status_before: int = _peer.get_connection_status()
	if status_before != MultiplayerPeer.CONNECTION_DISCONNECTED or _mode == "SERVER":
		_peer.poll()
	var status_after: int = _peer.get_connection_status()
	if _mode == "CLIENT" and status_after == MultiplayerPeer.CONNECTION_CONNECTED and not _client_connected_emitted:
		_client_connected_emitted = true
		var server_packet_peer: ENetPacketPeer = _peer.get_peer(MultiplayerPeer.TARGET_PEER_SERVER)
		if server_packet_peer != null:
			_packet_peer_by_peer[_client_peer_id] = server_packet_peer
		_append_event("PEER_CONNECTED", _client_peer_id, _client_session_id, 0, {}, "", {
			"route_id": _client_route_id,
			"route_generation": _client_route_generation,
		})
	if _mode == "CLIENT" and status_after == MultiplayerPeer.CONNECTION_DISCONNECTED and _client_connected_emitted:
		_append_event("PEER_DISCONNECTED", _client_peer_id, _client_session_id)
		_client_connected_emitted = false
	while _peer != null and _peer.get_available_packet_count() > 0:
		var numeric_id: int = _peer.get_packet_peer()
		var packet_channel: int = _peer.get_packet_channel()
		var packet_mode: int = _peer.get_packet_mode()
		var packet: PackedByteArray = _peer.get_packet()
		var decoded: Dictionary = FrameScript.decode(packet, MAX_PACKET_BYTES)
		if not bool(decoded.get("success", false)):
			_append_event("TRANSPORT_ERROR", "", "", 0, {}, String(decoded.get("error_code", "INVALID_FRAME")), {"packet_bytes": packet.size()})
			continue
		var frame: Dictionary = decoded.get("details", {}).get("frame", {})
		var expected_channel: int = _channel_index(String(frame.get("channel", "")))
		var expected_mode: int = _transfer_mode(String(frame.get("delivery_mode", "")))
		if packet_channel != expected_channel:
			_quarantine_physical_mismatch(numeric_id, frame, "PHYSICAL_CHANNEL_MISMATCH", {
				"packet_channel": packet_channel,
				"expected_channel": expected_channel,
				"frame_channel": String(frame.get("channel", "")),
			})
			continue
		if packet_mode != expected_mode:
			_quarantine_physical_mismatch(numeric_id, frame, "PHYSICAL_DELIVERY_MODE_MISMATCH", {
				"packet_mode": packet_mode,
				"expected_mode": expected_mode,
				"delivery_mode": String(frame.get("delivery_mode", "")),
			})
			continue
		var logical_peer_id: String = _logical_peer_for_packet(numeric_id, frame)
		var session_id: String = String(frame.get("session_id", ""))
		if not _session_by_peer.has(logical_peer_id):
			_register_server_peer(logical_peer_id, numeric_id, session_id)
		elif String(_session_by_peer[logical_peer_id]) != session_id:
			var next_generation: int = int(_route_generation_by_peer.get(logical_peer_id, 1)) + 1
			_session_by_peer[logical_peer_id] = session_id
			_route_generation_by_peer[logical_peer_id] = next_generation
			_append_event("PEER_CONNECTED", logical_peer_id, session_id, 0, {}, "", {
				"route_id": String(_route_by_peer.get(logical_peer_id, "route/enet/%d" % numeric_id)),
				"route_generation": next_generation,
			})
		_append_event("MESSAGE_RECEIVED", logical_peer_id, session_id, int(frame["sequence"]), frame, "", {
			"packet_bytes": packet.size(),
			"channel_index": packet_channel,
			"packet_mode": packet_mode,
			"frame_channel": String(frame.get("channel", "")),
			"delivery_mode": String(frame.get("delivery_mode", "")),
			"peer_statistics": _peer_statistics(logical_peer_id),
		})
	if _mode == "SERVER":
		_detect_disconnected_server_peers()
	_last_status = status_after


func _quarantine_physical_mismatch(
	numeric_id: int,
	frame: Dictionary,
	error_code: String,
	details: Dictionary
) -> void:
	var peer_id: String = _logical_peer_for_packet(numeric_id, frame)
	var frame_session_id: String = String(frame.get("session_id", ""))
	var session_id: String = String(_session_by_peer.get(peer_id, frame_session_id))
	var quarantine_details: Dictionary = details.duplicate(true)
	quarantine_details["protocol_violation"] = true
	quarantine_details["quarantine_policy"] = PHYSICAL_MISMATCH_HANDLING_POLICY
	quarantine_details["numeric_peer_id"] = numeric_id
	quarantine_details["frame_session_id"] = frame_session_id

	if _peer != null:
		if _mode == "SERVER" and numeric_id > 0:
			_peer.disconnect_peer(numeric_id, true)
		elif _mode == "CLIENT":
			_peer.close()
			_client_connected_emitted = false

	if _session_by_peer.has(peer_id):
		_remove_peer(peer_id)
	_append_event(
		"PEER_DISCONNECTED",
		peer_id,
		session_id,
		int(frame.get("sequence", 0)),
		{},
		error_code,
		quarantine_details
	)


func _logical_peer_for_packet(numeric_id: int, frame: Dictionary) -> String:
	if _mode == "CLIENT":
		return _client_peer_id
	if _numeric_to_logical.has(numeric_id):
		return String(_numeric_to_logical[numeric_id])
	var session_id: String = String(frame.get("session_id", ""))
	var suffix: String = session_id.trim_prefix("transport-session/").replace("/", "-")
	return "peer/enet/%d/%s" % [numeric_id, suffix]


func _register_server_peer(peer_id: String, numeric_id: int, session_id: String) -> void:
	_logical_to_numeric[peer_id] = numeric_id
	_numeric_to_logical[numeric_id] = peer_id
	_session_by_peer[peer_id] = session_id
	_route_by_peer[peer_id] = "route/enet/%d" % numeric_id
	_route_generation_by_peer[peer_id] = 1
	var packet_peer: ENetPacketPeer = _peer.get_peer(numeric_id)
	if packet_peer != null:
		_packet_peer_by_peer[peer_id] = packet_peer
	_append_event("PEER_CONNECTED", peer_id, session_id, 0, {}, "", {
		"route_id": _route_by_peer[peer_id],
		"route_generation": 1,
	})


func _detect_disconnected_server_peers() -> void:
	for peer_id in _logical_to_numeric.keys().duplicate():
		var packet_peer: ENetPacketPeer = _packet_peer_by_peer.get(peer_id)
		if packet_peer == null or not packet_peer.is_active():
			var session_id: String = String(_session_by_peer.get(peer_id, ""))
			_remove_peer(String(peer_id))
			_append_event("PEER_DISCONNECTED", String(peer_id), session_id)


func _remove_peer(peer_id: String) -> void:
	var numeric_id: int = int(_logical_to_numeric.get(peer_id, 0))
	_logical_to_numeric.erase(peer_id)
	if numeric_id > 0:
		_numeric_to_logical.erase(numeric_id)
	_session_by_peer.erase(peer_id)
	_route_by_peer.erase(peer_id)
	_route_generation_by_peer.erase(peer_id)
	_packet_peer_by_peer.erase(peer_id)


func _all_peer_statistics() -> Dictionary:
	var result: Dictionary = {}
	for peer_id_value in _packet_peer_by_peer.keys():
		var peer_id: String = String(peer_id_value)
		result[peer_id] = _peer_statistics(peer_id)
	return result


func _peer_statistics(peer_id: String) -> Dictionary:
	var packet_peer: ENetPacketPeer = _packet_peer_by_peer.get(peer_id)
	if packet_peer == null or not packet_peer.is_active():
		return {}
	var packet_loss_scale: float = float(ENetPacketPeer.PACKET_LOSS_SCALE)
	return {
		"rtt_ms": int(packet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)),
		"rtt_variance_ms": int(packet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME_VARIANCE)),
		"packet_loss_raw": int(packet_peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS)),
		"packet_loss_percent": (
			float(packet_peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS))
			* 100.0 / packet_loss_scale
		),
	}


func _append_event(event_type: String, peer_id: String = "", session_id: String = "", sequence: int = 0, frame: Dictionary = {}, error_code: String = "", details: Dictionary = {}) -> void:
	_event_sequence += 1
	_events.append(EventScript.create(
		"transport-event/enet/%d/%d" % [OS.get_process_id(), _event_sequence],
		event_type, peer_id, session_id, sequence, frame, error_code, details
	))


func _channel_index(channel: String) -> int:
	return ChannelPolicyScript.channel_index(channel)


func _transfer_mode(delivery_mode: String) -> int:
	# Keep application-level latest-wins sequencing, but map the physical ENet
	# stream to ordered unreliable delivery so stale movement/snapshot packets
	# cannot overtake newer packets on the same realtime channel.
	return (
		MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
		if delivery_mode == "UNRELIABLE_SEQUENCED"
		else MultiplayerPeer.TRANSFER_MODE_RELIABLE
	)


func _validate_endpoint(endpoint: Dictionary) -> Dictionary:
	var check: Dictionary = EndpointScript.validate(endpoint)
	if not bool(check.get("success", false)):
		return TransportUtilsScript.failure(String(check.get("error_code", "INVALID_ENDPOINT")))
	if String(endpoint.get("transport", "")) != "ENET" or bool(endpoint.get("secure", false)):
		return TransportUtilsScript.failure("ENDPOINT_TRANSPORT_MISMATCH")
	return TransportUtilsScript.success()

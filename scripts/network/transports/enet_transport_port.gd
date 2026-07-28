extends "res://scripts/network/transports/network_transport_port.gd"

const EndpointScript = preload("res://scripts/network/contracts/network_endpoint.gd")
const WireFrameScript = preload("res://scripts/network/contracts/network_wire_frame.gd")

const MAX_WIRE_PACKET_BYTES: int = 65536
const MAX_CLIENTS: int = 1
const MAX_CHANNELS: int = 1

var _peer: ENetMultiplayerPeer
var _mode: String = ""
var _events: Array[Dictionary] = []
var _active_peer_id: int = 0
var _last_connection_status: int = MultiplayerPeer.CONNECTION_DISCONNECTED
var _connected_event_emitted: bool = false
var _disconnect_event_emitted: bool = false
var _message_sequence: int = 0
var _endpoint: Dictionary = {}


func get_descriptor() -> Dictionary:
	return {
		"schema": SCHEMA,
		"transport_kind": "ENET",
		"supports_server": true,
		"supports_client": true,
		"synchronous_delivery": false,
	}


func start_server(endpoint: Dictionary) -> Dictionary:
	if _peer != null:
		return _failure("ALREADY_STARTED")
	var validation: Dictionary = _validate_endpoint(endpoint)
	if not bool(validation.get("success", false)):
		return validation
	_peer = ENetMultiplayerPeer.new()
	var host: String = String(endpoint["host"])
	if host != "*":
		_peer.set_bind_ip(host)
	var error: Error = _peer.create_server(int(endpoint["port"]), MAX_CLIENTS, MAX_CHANNELS)
	if error != OK:
		_peer = null
		return _failure("ENET_SERVER_CREATE_FAILED", {"godot_error": int(error)})
	_mode = "SERVER"
	_endpoint = endpoint.duplicate(true)
	_last_connection_status = _peer.get_connection_status()
	_events.append({"type": "LISTENING", "endpoint": _endpoint.duplicate(true)})
	return _success({"endpoint": _endpoint.duplicate(true)})


func connect_client(endpoint: Dictionary) -> Dictionary:
	if _peer != null:
		return _failure("ALREADY_CONNECTED")
	var validation: Dictionary = _validate_endpoint(endpoint)
	if not bool(validation.get("success", false)):
		return validation
	_peer = ENetMultiplayerPeer.new()
	var error: Error = _peer.create_client(String(endpoint["host"]), int(endpoint["port"]), MAX_CHANNELS)
	if error != OK:
		_peer = null
		return _failure("ENET_CLIENT_CREATE_FAILED", {"godot_error": int(error)})
	_mode = "CLIENT"
	_endpoint = endpoint.duplicate(true)
	_last_connection_status = _peer.get_connection_status()
	return _success({"endpoint": _endpoint.duplicate(true)})


func disconnect_peer() -> Dictionary:
	if _peer == null:
		return _success({"replay": true})
	if _mode == "SERVER" and _active_peer_id > 0:
		var disconnected_id: int = _active_peer_id
		_peer.disconnect_peer(disconnected_id, false)
		_active_peer_id = 0
		_events.append({"type": "PEER_DISCONNECTED", "peer_id": disconnected_id, "local_request": true})
		return _success()
	_peer.close()
	_peer = null
	_mode = ""
	_active_peer_id = 0
	_last_connection_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	return _success()


func send_message(message_type: String, payload: Dictionary) -> Dictionary:
	if _peer == null:
		return _failure("ENET_NOT_STARTED")
	if _mode == "CLIENT":
		if _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			return _failure("ENET_NOT_CONNECTED")
		_peer.set_target_peer(MultiplayerPeer.TARGET_PEER_SERVER)
	elif _mode == "SERVER":
		if _active_peer_id <= 0:
			return _failure("NO_ACTIVE_PEER")
		_peer.set_target_peer(_active_peer_id)
	else:
		return _failure("INVALID_ENET_MODE")
	_message_sequence += 1
	var frame: Dictionary = WireFrameScript.create(
		"wire/%s/%d/%d" % [_mode.to_lower(), OS.get_process_id(), _message_sequence],
		message_type,
		payload
	)
	var encoded: Dictionary = WireFrameScript.encode(frame)
	if not bool(encoded.get("success", false)):
		return _failure(String(encoded.get("error_code", "WIRE_ENCODE_FAILED")))
	var packet: PackedByteArray = encoded["packet"]
	if packet.size() > MAX_WIRE_PACKET_BYTES:
		return _failure("PACKET_TOO_LARGE")
	_peer.transfer_channel = 0
	_peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	var error: Error = _peer.put_packet(packet)
	if error != OK:
		return _failure("ENET_SEND_FAILED", {"godot_error": int(error)})
	return _success({
		"message_id": String(frame["message_id"]),
		"payload_hash": String(frame["payload_hash"]),
		"packet_bytes": packet.size(),
	})


func poll_events(max_events: int) -> Array[Dictionary]:
	if max_events <= 0:
		return []
	_poll_peer()
	var result: Array[Dictionary] = []
	var count: int = mini(max_events, _events.size())
	for _index in range(count):
		result.append(_events.pop_front())
	return result


func drain() -> Dictionary:
	if _peer == null:
		return _success({"replay": true})
	if _mode == "SERVER":
		_peer.refuse_new_connections = true
	return _success()


func stop() -> Dictionary:
	if _peer != null:
		_peer.close()
	_peer = null
	_mode = ""
	_events.clear()
	_active_peer_id = 0
	_last_connection_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	_connected_event_emitted = false
	_disconnect_event_emitted = false
	_message_sequence = 0
	_endpoint.clear()
	return _success()


func get_runtime_snapshot() -> Dictionary:
	return {
		"mode": _mode,
		"started": _peer != null,
		"connection_status": _peer.get_connection_status() if _peer != null else MultiplayerPeer.CONNECTION_DISCONNECTED,
		"active_peer_id": _active_peer_id,
		"queued_events": _events.size(),
		"endpoint": _endpoint.duplicate(true),
	}


func _poll_peer() -> void:
	if _peer == null:
		return
	var status_before: int = _peer.get_connection_status()
	if status_before != MultiplayerPeer.CONNECTION_DISCONNECTED or _mode == "SERVER":
		_peer.poll()
	var status_after: int = _peer.get_connection_status()
	if _mode == "CLIENT":
		if status_after == MultiplayerPeer.CONNECTION_CONNECTED and not _connected_event_emitted:
			_connected_event_emitted = true
			_disconnect_event_emitted = false
			_events.append({"type": "CONNECTED", "peer_id": MultiplayerPeer.TARGET_PEER_SERVER})
		elif status_after == MultiplayerPeer.CONNECTION_DISCONNECTED and not _disconnect_event_emitted:
			if _last_connection_status == MultiplayerPeer.CONNECTION_CONNECTING:
				_events.append({"type": "CONNECTION_FAILED", "peer_id": MultiplayerPeer.TARGET_PEER_SERVER})
			elif _connected_event_emitted:
				_events.append({"type": "DISCONNECTED", "peer_id": MultiplayerPeer.TARGET_PEER_SERVER})
			_disconnect_event_emitted = true
	while _peer != null and _peer.get_available_packet_count() > 0:
		var source_peer_id: int = _peer.get_packet_peer()
		var packet: PackedByteArray = _peer.get_packet()
		if _mode == "SERVER":
			if _active_peer_id == 0:
				_active_peer_id = source_peer_id
				_events.append({"type": "PEER_CONNECTED", "peer_id": source_peer_id})
			elif source_peer_id != _active_peer_id:
				_peer.disconnect_peer(source_peer_id, true)
				_events.append({"type": "PEER_REJECTED", "peer_id": source_peer_id, "error_code": "SINGLE_CLIENT_LIMIT"})
				continue
		var decoded: Dictionary = WireFrameScript.decode(packet, MAX_WIRE_PACKET_BYTES)
		if not bool(decoded.get("success", false)):
			_events.append({
				"type": "MALFORMED_MESSAGE",
				"peer_id": source_peer_id,
				"error_code": String(decoded.get("error_code", "INVALID_WIRE_FRAME")),
				"packet_bytes": packet.size(),
			})
			continue
		var frame: Dictionary = decoded["frame"]
		_events.append({
			"type": "MESSAGE",
			"peer_id": source_peer_id,
			"message_id": String(frame["message_id"]),
			"message_type": String(frame["message_type"]),
			"payload": frame["payload"].duplicate(true),
			"payload_hash": String(frame["payload_hash"]),
		})
	if _mode == "SERVER" and _active_peer_id > 0:
		var active_peer = _peer.get_peer(_active_peer_id)
		if active_peer == null or not active_peer.is_active():
			var disconnected_id: int = _active_peer_id
			_active_peer_id = 0
			_events.append({"type": "PEER_DISCONNECTED", "peer_id": disconnected_id, "local_request": false})
	_last_connection_status = status_after


func _validate_endpoint(endpoint: Dictionary) -> Dictionary:
	var validation: Dictionary = EndpointScript.validate(endpoint)
	if not bool(validation.get("success", false)):
		return _failure(String(validation.get("error_code", "INVALID_ENDPOINT")))
	if String(endpoint["transport"]) != "ENET":
		return _failure("ENDPOINT_TRANSPORT_MISMATCH")
	if bool(endpoint["secure"]):
		return _failure("SECURE_ENET_NOT_SUPPORTED")
	return _success()

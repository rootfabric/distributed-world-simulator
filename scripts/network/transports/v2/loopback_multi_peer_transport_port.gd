extends "res://scripts/network/transports/v2/network_transport_port_v2.gd"

const EventScript = preload("res://scripts/network/transports/v2/network_transport_event.gd")
const FrameScript = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")

var _started: bool = false
var _mode: String = ""
var _events: Array[Dictionary] = []
var _peers: Dictionary = {}
var _messages_by_peer: Dictionary = {}
var _handler: Callable = Callable()
var _event_sequence: int = 0


func setup(message_handler: Callable = Callable()) -> void:
	_handler = message_handler


func get_descriptor() -> Dictionary:
	return {
		"schema": SCHEMA,
		"transport_kind": "LOOPBACK_MULTI_PEER",
		"supports_server": true,
		"supports_client": true,
		"synchronous_delivery": true,
		"multi_peer": true,
		"max_peers": 64,
	}


func start_server(endpoint: Dictionary) -> Dictionary:
	if _started:
		return TransportUtilsScript.failure("ALREADY_STARTED")
	if endpoint.is_empty():
		return TransportUtilsScript.failure("INVALID_ENDPOINT")
	_started = true
	_mode = "SERVER"
	_append_event("LISTENER_STARTED", "", "", 0, {}, "", {"endpoint": endpoint.duplicate(true)})
	return TransportUtilsScript.success()


func connect_client(endpoint: Dictionary, peer_id: String, session_id: String, route_id: String, route_generation: int) -> Dictionary:
	if _started:
		return TransportUtilsScript.failure("ALREADY_STARTED")
	if endpoint.is_empty():
		return TransportUtilsScript.failure("INVALID_ENDPOINT")
	_started = true
	_mode = "CLIENT"
	return attach_peer(peer_id, session_id, route_id, route_generation)


func attach_peer(peer_id: String, session_id: String, route_id: String, route_generation: int = 1) -> Dictionary:
	if not _started:
		return TransportUtilsScript.failure("NOT_STARTED")
	if not TransportUtilsScript.is_canonical_transport_id(peer_id, "peer"):
		return TransportUtilsScript.failure("INVALID_PEER_ID")
	if not TransportUtilsScript.is_canonical_transport_id(session_id, "transport-session"):
		return TransportUtilsScript.failure("INVALID_SESSION_ID")
	if not TransportUtilsScript.is_canonical_transport_id(route_id, "route") or route_generation < 1:
		return TransportUtilsScript.failure("INVALID_ROUTE")
	if _peers.has(peer_id):
		var existing: Dictionary = _peers[peer_id]
		if String(existing.get("session_id", "")) == session_id and int(existing.get("route_generation", 0)) == route_generation:
			return TransportUtilsScript.success({"replay": true})
	_peers[peer_id] = {
		"session_id": session_id,
		"route_id": route_id,
		"route_generation": route_generation,
	}
	if not _messages_by_peer.has(peer_id):
		_messages_by_peer[peer_id] = []
	_append_event("PEER_CONNECTED", peer_id, session_id, 0, {}, "", {
		"route_id": route_id,
		"route_generation": route_generation,
	})
	return TransportUtilsScript.success({"replay": false})


func disconnect_peer(peer_id: String, session_id: String) -> Dictionary:
	if not _peers.has(peer_id):
		return TransportUtilsScript.success({"replay": true})
	var peer: Dictionary = _peers[peer_id]
	if String(peer.get("session_id", "")) != session_id:
		return TransportUtilsScript.failure("SESSION_MISMATCH")
	_peers.erase(peer_id)
	_append_event("PEER_DISCONNECTED", peer_id, session_id)
	return TransportUtilsScript.success({"replay": false})


func send_to_peer(peer_id: String, frame: Dictionary) -> Dictionary:
	if not _peers.has(peer_id):
		return TransportUtilsScript.failure("UNKNOWN_PEER")
	var check: Dictionary = FrameScript.validate(frame)
	if not bool(check.get("success", false)):
		return TransportUtilsScript.failure(String(check.get("error_code", "INVALID_FRAME")))
	var peer: Dictionary = _peers[peer_id]
	if String(peer.get("session_id", "")) != String(frame.get("session_id", "")):
		return TransportUtilsScript.failure("SESSION_MISMATCH")
	var messages: Array = _messages_by_peer[peer_id]
	messages.append(frame.duplicate(true))
	_messages_by_peer[peer_id] = messages
	if _handler.is_valid():
		var handled = _handler.call(peer_id, frame.duplicate(true))
		if not handled is Dictionary:
			return TransportUtilsScript.failure("INVALID_HANDLER_RESULT")
		if not bool(handled.get("success", false)):
			return TransportUtilsScript.failure(String(handled.get("error_code", "HANDLER_REJECTED")), handled.get("details", {}))
	return TransportUtilsScript.success({"enqueued": true, "delivered": true})


func inject_received_frame(peer_id: String, frame: Dictionary) -> Dictionary:
	if not _peers.has(peer_id):
		return TransportUtilsScript.failure("UNKNOWN_PEER")
	var check: Dictionary = FrameScript.validate(frame)
	if not bool(check.get("success", false)):
		return TransportUtilsScript.failure(String(check.get("error_code", "INVALID_FRAME")))
	_append_event("MESSAGE_RECEIVED", peer_id, String(frame["session_id"]), int(frame["sequence"]), frame)
	return TransportUtilsScript.success()


func poll_events(max_events: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var count: int = mini(max_events, _events.size())
	for _index in range(count):
		result.append(_events.pop_front())
	return result


func drain() -> Dictionary:
	_append_event("LISTENER_DRAINING")
	return TransportUtilsScript.success()


func stop() -> Dictionary:
	for peer_id in _peers.keys():
		var session_id: String = String(_peers[peer_id].get("session_id", ""))
		_append_event("PEER_DISCONNECTED", String(peer_id), session_id)
	_peers.clear()
	_started = false
	_mode = ""
	_append_event("LISTENER_STOPPED")
	return TransportUtilsScript.success()


func get_messages_for_peer(peer_id: String) -> Array:
	return _messages_by_peer.get(peer_id, []).duplicate(true)


func _append_event(event_type: String, peer_id: String = "", session_id: String = "", sequence: int = 0, frame: Dictionary = {}, error_code: String = "", details: Dictionary = {}) -> void:
	_event_sequence += 1
	_events.append(EventScript.create(
		"transport-event/loopback/%d" % _event_sequence,
		event_type,
		peer_id,
		session_id,
		sequence,
		frame,
		error_code,
		details
	))

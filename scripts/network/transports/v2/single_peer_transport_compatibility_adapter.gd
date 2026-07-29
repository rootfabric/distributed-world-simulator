extends "res://scripts/network/transports/v2/network_transport_port_v2.gd"

const EventScript = preload("res://scripts/network/transports/v2/network_transport_event.gd")

var _legacy_port
var _peer_id: String = ""
var _session_id: String = ""
var _route_id: String = ""
var _route_generation: int = 0
var _event_sequence: int = 0


func setup(legacy_port) -> Dictionary:
	if legacy_port == null or not legacy_port is RefCounted:
		return TransportUtilsScript.failure("INVALID_LEGACY_PORT")
	_legacy_port = legacy_port
	return TransportUtilsScript.success()


func get_descriptor() -> Dictionary:
	var legacy_descriptor: Dictionary = _legacy_port.get_descriptor() if _legacy_port != null else {}
	var kind: String = "LEGACY_%s" % String(legacy_descriptor.get("transport_kind", "SINGLE_PEER"))
	return {
		"schema": SCHEMA,
		"transport_kind": kind,
		"supports_server": bool(legacy_descriptor.get("supports_server", false)),
		"supports_client": bool(legacy_descriptor.get("supports_client", false)),
		"synchronous_delivery": bool(legacy_descriptor.get("synchronous_delivery", false)),
		"multi_peer": true,
		"max_peers": 1,
	}


func start_server(endpoint: Dictionary) -> Dictionary:
	if _legacy_port == null:
		return TransportUtilsScript.failure("NOT_CONFIGURED")
	return _legacy_port.start_server(endpoint)


func connect_client(endpoint: Dictionary, peer_id: String, session_id: String, route_id: String, route_generation: int) -> Dictionary:
	if _legacy_port == null:
		return TransportUtilsScript.failure("NOT_CONFIGURED")
	var result: Dictionary = _legacy_port.connect_client(endpoint)
	if bool(result.get("success", false)):
		_peer_id = peer_id
		_session_id = session_id
		_route_id = route_id
		_route_generation = route_generation
	return result


func disconnect_peer(peer_id: String, session_id: String) -> Dictionary:
	if peer_id != _peer_id or session_id != _session_id:
		return TransportUtilsScript.failure("SESSION_MISMATCH")
	return _legacy_port.disconnect_peer()


func send_to_peer(peer_id: String, frame: Dictionary) -> Dictionary:
	if peer_id != _peer_id or String(frame.get("session_id", "")) != _session_id:
		return TransportUtilsScript.failure("SESSION_MISMATCH")
	var channel: String = String(frame.get("channel", ""))
	var legacy_message_type: String = {
		"CONTROL": "HANDSHAKE",
		"COMMAND": "COMMAND",
		"STATE": "SNAPSHOT",
		"EVENT": "DELTA",
	}.get(channel, "")
	if legacy_message_type.is_empty():
		return TransportUtilsScript.failure("UNSUPPORTED_LEGACY_CHANNEL", {"channel": channel})
	return _legacy_port.send_message(legacy_message_type, frame.get("payload", {}))


func poll_events(max_events: int) -> Array[Dictionary]:
	var legacy_events = _legacy_port.poll_events(max_events)
	var result: Array[Dictionary] = []
	for legacy_event in legacy_events:
		var event_type: String = String(legacy_event.get("type", ""))
		if event_type in ["CONNECTED", "PEER_CONNECTED"] and not _peer_id.is_empty():
			_event_sequence += 1
			result.append(EventScript.create(
				"transport-event/compat/%d" % _event_sequence,
				"PEER_CONNECTED", _peer_id, _session_id, 0, {}, "", {
					"route_id": _route_id,
					"route_generation": _route_generation,
				}
			))
		elif event_type in ["DISCONNECTED", "PEER_DISCONNECTED"] and not _peer_id.is_empty():
			_event_sequence += 1
			result.append(EventScript.create(
				"transport-event/compat/%d" % _event_sequence,
				"PEER_DISCONNECTED", _peer_id, _session_id
			))
	return result


func drain() -> Dictionary:
	return _legacy_port.drain() if _legacy_port != null else TransportUtilsScript.failure("NOT_CONFIGURED")


func stop() -> Dictionary:
	return _legacy_port.stop() if _legacy_port != null else TransportUtilsScript.success()

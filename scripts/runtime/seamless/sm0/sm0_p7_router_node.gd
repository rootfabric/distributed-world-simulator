extends Node

signal finished(exit_code: int)

const Topology = preload("res://scripts/runtime/seamless/sm0/sm0_p7_three_authority_topology.gd")
const RouteContract = preload("res://scripts/runtime/seamless/sm0/sm0_p7_route_contract.gd")

const STOP_POLL_INTERVAL_MS := 100

var _authority_id := ""
var _zone_id := ""
var _listen_host := "127.0.0.1"
var _listen_port := 0
var _neighbor_endpoints: Dictionary = {}
var _stop_file := ""
var _start_file := ""
var _auto_probe_destination := ""
var _auto_probe_sent := false
var _last_stop_poll_ms := 0
var _socket: PacketPeerUDP
var _route_ledger: Dictionary = {}
var _deliveries: Dictionary = {}
var _originated_count := 0
var _forwarded_count := 0
var _replay_count := 0
var _rejected_count := 0


func setup(config: Dictionary) -> Dictionary:
	_authority_id = String(config.get("authority_id", "")).strip_edges()
	_zone_id = String(config.get("zone_id", "")).strip_edges()
	_listen_host = String(config.get("listen_host", "127.0.0.1")).strip_edges()
	_listen_port = int(config.get("listen_port", 0))
	_neighbor_endpoints = Dictionary(config.get("neighbor_endpoints", {})).duplicate(true)
	_stop_file = String(config.get("stop_file", "")).strip_edges()
	_start_file = String(config.get("start_file", "")).strip_edges()
	_auto_probe_destination = String(config.get("auto_probe_destination", "")).strip_edges()
	if (
		_authority_id not in Topology.AUTHORITIES
		or _zone_id != Topology.zone_for_authority(_authority_id)
		or _listen_host.is_empty()
		or _listen_port < 1
	):
		return _failure("SM0_P7_ROUTER_CONFIGURATION_INVALID")
	if not _auto_probe_destination.is_empty() and _auto_probe_destination not in Topology.AUTHORITIES:
		return _failure("SM0_P7_AUTO_PROBE_DESTINATION_INVALID")
	for neighbor in Topology.neighbors(_authority_id):
		if not _neighbor_endpoints.has(neighbor):
			return _failure("SM0_P7_NEIGHBOR_ENDPOINT_REQUIRED", {"neighbor_authority_id": neighbor})
		var endpoint: Dictionary = Dictionary(_neighbor_endpoints[neighbor])
		if String(endpoint.get("host", "")).strip_edges().is_empty() or int(endpoint.get("port", 0)) < 1:
			return _failure("SM0_P7_NEIGHBOR_ENDPOINT_INVALID", {"neighbor_authority_id": neighbor})
	for configured in _neighbor_endpoints.keys():
		if String(configured) not in Topology.neighbors(_authority_id):
			return _failure("SM0_P7_NON_NEIGHBOR_ENDPOINT_FORBIDDEN", {"authority_id": String(configured)})
	_socket = PacketPeerUDP.new()
	var bind_result := _socket.bind(_listen_port, _listen_host)
	if bind_result != OK:
		return _failure("SM0_P7_ROUTER_BIND_FAILED", {"error": bind_result, "port": _listen_port})
	set_process(true)
	_event("SM0_P7_ROUTER_READY", {
		"listen_port": _listen_port,
		"neighbors": Topology.neighbors(_authority_id),
		"routing_only": true,
		"command_channel": false,
	})
	return _success()


func _process(_delta: float) -> void:
	_poll_socket()
	if not _auto_probe_sent and not _auto_probe_destination.is_empty() and not _start_file.is_empty() and FileAccess.file_exists(_start_file):
		_auto_probe_sent = true
		var route_id := "route/sm0/p7/%s-to-%s/%d" % [
			_authority_id.get_slice("/", 2),
			_auto_probe_destination.get_slice("/", 2),
			OS.get_process_id(),
		]
		var probe := originate_probe(_auto_probe_destination, route_id, 1, _default_payload())
		if not bool(probe.get("success", false)):
			_event("SM0_P7_AUTO_PROBE_FAILED", {"error_code": String(probe.get("error_code", "SM0_P7_AUTO_PROBE_FAILED"))})
	var now := Time.get_ticks_msec()
	if not _stop_file.is_empty() and now - _last_stop_poll_ms >= STOP_POLL_INTERVAL_MS:
		_last_stop_poll_ms = now
		if FileAccess.file_exists(_stop_file):
			shutdown(0, "stop-file")


func _poll_socket() -> void:
	if _socket == null:
		return
	while _socket.get_available_packet_count() > 0:
		var bytes := _socket.get_packet()
		var remote_ip := _socket.get_packet_ip()
		var remote_port := _socket.get_packet_port()
		var decoded = JSON.parse_string(bytes.get_string_from_utf8())
		if not decoded is Dictionary:
			_reject("SM0_P7_ROUTE_JSON_INVALID", {}, remote_ip, remote_port)
			continue
		var envelope: Dictionary = Dictionary(decoded)
		var previous_authority := RouteContract.previous_authority(envelope)
		_accept_envelope(envelope, previous_authority, remote_ip, remote_port, true)


func originate_probe(destination_authority_id: String, route_id: String, authority_epoch: int, payload: Dictionary) -> Dictionary:
	if destination_authority_id not in Topology.AUTHORITIES:
		return _failure("SM0_P7_ROUTE_DESTINATION_INVALID")
	if route_id.strip_edges().is_empty():
		return _failure("SM0_P7_ROUTE_ID_REQUIRED")
	var envelope := RouteContract.create_probe(route_id, _authority_id, destination_authority_id, authority_epoch, payload)
	var validation := RouteContract.validate(envelope)
	if not bool(validation.get("success", false)):
		return validation
	var replay := _record_route(envelope)
	if not bool(replay.get("success", false)):
		return replay
	_originated_count += 1
	_event("SM0_P7_ROUTE_ORIGINATED", {
		"route_id": route_id,
		"source_authority_id": _authority_id,
		"destination_authority_id": destination_authority_id,
		"route_path": envelope.get("route_path", []),
		"player_entity_id": String(payload.get("player_entity_id", "")),
	})
	if destination_authority_id == _authority_id:
		return _deliver(envelope)
	return _forward(envelope)


func accept_envelope_for_tests(envelope: Dictionary, previous_authority_id: String) -> Dictionary:
	return _accept_envelope(envelope, previous_authority_id, "127.0.0.1", 0, false)


func _accept_envelope(envelope: Dictionary, previous_authority_id: String, remote_ip: String, remote_port: int, verify_network_sender: bool) -> Dictionary:
	var validation := RouteContract.validate(envelope)
	if not bool(validation.get("success", false)):
		return _reject(String(validation.get("error_code", "SM0_P7_ROUTE_INVALID")), envelope, remote_ip, remote_port)
	if RouteContract.current_authority(envelope) != _authority_id:
		return _reject("SM0_P7_ROUTE_CURRENT_HOP_MISMATCH", envelope, remote_ip, remote_port)
	var expected_previous := RouteContract.previous_authority(envelope)
	if expected_previous.is_empty() or previous_authority_id != expected_previous:
		return _reject("SM0_P7_ROUTE_PREVIOUS_HOP_MISMATCH", envelope, remote_ip, remote_port)
	if not Topology.are_adjacent(expected_previous, _authority_id):
		return _reject("SM0_P7_ROUTE_PREVIOUS_HOP_NOT_ADJACENT", envelope, remote_ip, remote_port)
	if verify_network_sender:
		if not _neighbor_endpoints.has(expected_previous):
			return _reject("SM0_P7_ROUTE_SENDER_NOT_NEIGHBOR", envelope, remote_ip, remote_port)
		var endpoint: Dictionary = Dictionary(_neighbor_endpoints[expected_previous])
		if remote_port != int(endpoint.get("port", 0)):
			return _reject("SM0_P7_ROUTE_SENDER_PORT_MISMATCH", envelope, remote_ip, remote_port)
	var replay := _record_route(envelope)
	if not bool(replay.get("success", false)):
		return replay
	if bool(replay.get("details", {}).get("replay", false)):
		_replay_count += 1
		_event("SM0_P7_ROUTE_REPLAY", {"route_id": String(envelope.get("route_id", "")), "hop_index": int(envelope.get("hop_index", 0))})
	if String(envelope.get("destination_authority_id", "")) == _authority_id:
		return _deliver(envelope)
	return _forward(envelope)


func _record_route(envelope: Dictionary) -> Dictionary:
	var route_id := String(envelope.get("route_id", ""))
	var fingerprint := RouteContract.immutable_fingerprint(envelope)
	if _route_ledger.has(route_id):
		if String(_route_ledger[route_id]) != fingerprint:
			return _reject("SM0_P7_ROUTE_REPLAY_CONFLICT", envelope, "", 0)
		return _success({"replay": true})
	_route_ledger[route_id] = fingerprint
	return _success({"replay": false})


func _forward(envelope: Dictionary) -> Dictionary:
	var next_authority := RouteContract.next_authority(envelope)
	if next_authority.is_empty():
		return _reject("SM0_P7_ROUTE_NEXT_HOP_REQUIRED", envelope, "", 0)
	if not Topology.are_adjacent(_authority_id, next_authority):
		return _reject("SM0_P7_ROUTE_NEXT_HOP_NOT_ADJACENT", envelope, "", 0)
	if not _neighbor_endpoints.has(next_authority):
		return _reject("SM0_P7_ROUTE_NEXT_HOP_ENDPOINT_MISSING", envelope, "", 0)
	var advanced := RouteContract.advance(envelope)
	var validation := RouteContract.validate(advanced)
	if not bool(validation.get("success", false)):
		return _reject(String(validation.get("error_code", "SM0_P7_ROUTE_ADVANCE_INVALID")), advanced, "", 0)
	var sent := _send_envelope(next_authority, advanced)
	if not bool(sent.get("success", false)):
		return sent
	_forwarded_count += 1
	_event("SM0_P7_ROUTE_FORWARDED", {
		"route_id": String(envelope.get("route_id", "")),
		"source_authority_id": String(envelope.get("source_authority_id", "")),
		"destination_authority_id": String(envelope.get("destination_authority_id", "")),
		"current_authority_id": _authority_id,
		"next_authority_id": next_authority,
		"hop_index": int(envelope.get("hop_index", 0)),
		"route_path": envelope.get("route_path", []),
	})
	return _success({"forwarded": true, "next_authority_id": next_authority})


func _send_envelope(next_authority_id: String, envelope: Dictionary) -> Dictionary:
	if _socket == null:
		return _failure("SM0_P7_ROUTER_NOT_READY")
	var endpoint: Dictionary = Dictionary(_neighbor_endpoints.get(next_authority_id, {}))
	var host := String(endpoint.get("host", ""))
	var port := int(endpoint.get("port", 0))
	if host.is_empty() or port < 1:
		return _failure("SM0_P7_ROUTE_NEXT_HOP_ENDPOINT_INVALID")
	if _socket.set_dest_address(host, port) != OK:
		return _failure("SM0_P7_ROUTE_DESTINATION_SET_FAILED")
	var put_error := _socket.put_packet(JSON.stringify(envelope, "", false, true).to_utf8_buffer())
	if put_error != OK:
		return _failure("SM0_P7_ROUTE_SEND_FAILED", {"error": put_error})
	return _success()


func _deliver(envelope: Dictionary) -> Dictionary:
	var route_id := String(envelope.get("route_id", ""))
	if _deliveries.has(route_id):
		return _success({"replay": true, "delivery": Dictionary(_deliveries[route_id]).duplicate(true)})
	var payload: Dictionary = Dictionary(envelope.get("payload", {})).duplicate(true)
	var delivery := {
		"route_id": route_id,
		"source_authority_id": String(envelope.get("source_authority_id", "")),
		"destination_authority_id": String(envelope.get("destination_authority_id", "")),
		"route_path": Array(envelope.get("route_path", [])).duplicate(true),
		"hop_index": int(envelope.get("hop_index", 0)),
		"authority_epoch": int(envelope.get("authority_epoch", 0)),
		"payload": payload,
	}
	_deliveries[route_id] = delivery.duplicate(true)
	_event("SM0_P7_ROUTE_DELIVERED", {
		"route_id": route_id,
		"source_authority_id": String(envelope.get("source_authority_id", "")),
		"destination_authority_id": _authority_id,
		"route_path": envelope.get("route_path", []),
		"hop_index": int(envelope.get("hop_index", 0)),
		"logical_player_id": String(payload.get("logical_player_id", "")),
		"player_entity_id": String(payload.get("player_entity_id", "")),
		"state_revision": int(payload.get("state_revision", 0)),
	})
	return _success({"delivered": true, "delivery": delivery})


func _reject(error_code: String, envelope: Dictionary, remote_ip: String, remote_port: int) -> Dictionary:
	_rejected_count += 1
	_event("SM0_P7_ROUTE_REJECTED", {
		"error_code": error_code,
		"route_id": String(envelope.get("route_id", "")),
		"remote_ip": remote_ip,
		"remote_port": remote_port,
	})
	return _failure(error_code)


func status_for_tests() -> Dictionary:
	return {
		"authority_id": _authority_id,
		"zone_id": _zone_id,
		"writer_count": 0,
		"routing_only": true,
		"command_channel": false,
		"originated_count": _originated_count,
		"forwarded_count": _forwarded_count,
		"replay_count": _replay_count,
		"rejected_count": _rejected_count,
		"deliveries": _deliveries.duplicate(true),
	}


func shutdown(exit_code: int, reason: String) -> void:
	_event("SM0_P7_ROUTER_EXIT", {"exit_code": exit_code, "reason": reason})
	if _socket != null:
		_socket.close()
	set_process(false)
	finished.emit(exit_code)


func _default_payload() -> Dictionary:
	var x := -6.0 if _authority_id == Topology.AUTHORITY_A else 0.0 if _authority_id == Topology.AUTHORITY_B else 6.0
	return {
		"logical_player_id": "a",
		"player_entity_id": "player/a",
		"state_revision": 1,
		"position": {"x": x, "y": 0.0, "z": 0.0},
	}


func _event(event_name: String, details: Dictionary = {}) -> void:
	var event := {
		"schema": "distributed_world_simulator.sm0_event.v1",
		"event": event_name,
		"severity": "INFO",
		"process_role": "router-%s" % _authority_id.get_slice("/", 2),
		"process_id": OS.get_process_id(),
		"time_msec": Time.get_ticks_msec(),
		"authority_id": _authority_id,
		"zone_id": _zone_id,
		"writer_count": 0,
	}
	for key in details.keys():
		event[key] = details[key]
	print("[SM0_EVENT] %s" % JSON.stringify(event, "", false, true))


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}

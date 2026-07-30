extends Node

signal ready_for_clients(report: Dictionary)

const Boundary = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const Port = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
const Service = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
const Support = preload("res://scripts/runtime/networked_gameplay/m3/m3_process_support.gd")

const SCHEMA := "planet_simulator.m3_dedicated_server_runtime.v1"

var _boundary
var _service
var _configured := false
var _host := "127.0.0.1"
var _port := 0
var _result_file := ""
var _authority_owner_id := "simulation/m3/dedicated"
var _authority_epoch := 1
var _peer_to_player: Dictionary = {}
var _peer_to_session: Dictionary = {}
var _joins := 0
var _leaves := 0
var _moves := 0
var _presentation_updates := 0
var _rejections := 0
var _broadcasts := 0
var _messages_sent := 0
var _messages_received := 0
var _last_error_code := ""
var _last_two_connected_checksum := ""

func setup(config: Dictionary) -> Dictionary:
	if _configured:
		return _failure("M3_SERVER_ALREADY_CONFIGURED")
	_host = String(config.get("host", "127.0.0.1")).strip_edges()
	_port = int(config.get("port", 0))
	_result_file = String(config.get("result_file", "")).strip_edges()
	_authority_owner_id = String(config.get("authority_owner_id", _authority_owner_id)).strip_edges()
	_authority_epoch = int(config.get("authority_epoch", 1))
	if _host.is_empty() or _port < 1 or _port > 65535 or _authority_owner_id.is_empty() or _authority_epoch < 1:
		return _failure("INVALID_M3_SERVER_CONFIGURATION")
	_service = Service.new()
	var service_setup: Dictionary = _service.setup(_authority_owner_id, _authority_epoch, 0, {
		"profile": Service.PROFILE_MULTIPLAYER_CORE,
		"topology_adapter": "ENET",
		"region_id": "region/m3/single-server",
	})
	if not bool(service_setup.get("success", false)):
		return service_setup
	_boundary = Boundary.new()
	var configured: Dictionary = _boundary.configure(Port.new(), 524288, 64, 2097152)
	if not bool(configured.get("success", false)):
		return configured
	var started: Dictionary = _boundary.start_server(Support.endpoint(_host, _port, true))
	if not bool(started.get("success", false)):
		return started
	_configured = true
	set_process(true)
	_write_report("READY", false)
	ready_for_clients.emit(get_report())
	return _success({"host": _host, "port": _port})

func _process(_delta: float) -> void:
	if not _configured or _boundary == null:
		return
	var polled: Dictionary = _boundary.poll_events(128)
	if not bool(polled.get("success", false)):
		_last_error_code = String(polled.get("error_code", "M3_SERVER_POLL_FAILED"))
		_write_report("FAILED", false)
		return
	for event_value in polled.get("details", {}).get("events", []):
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value
		var event_type := String(event.get("event_type", ""))
		var peer_id := String(event.get("peer_id", ""))
		var session_id := String(event.get("session_id", ""))
		if event_type == "MESSAGE_RECEIVED":
			_messages_received += 1
			_handle_message(peer_id, session_id, event.get("frame", {}).get("payload", {}))
		elif event_type == "PEER_DISCONNECTED":
			_handle_disconnect(peer_id, session_id)

func _handle_message(peer_id: String, session_id: String, payload: Dictionary) -> void:
	match String(payload.get("type", "")):
		"JOIN": _handle_join(peer_id, session_id, payload)
		"MOVE": _handle_move(peer_id, session_id, payload)
		"PRESENTATION": _handle_presentation(peer_id, session_id, payload)
		"LEAVE": _handle_leave(peer_id, session_id, payload)
		_: _send_result(peer_id, String(payload.get("operation_id", "")), "UNKNOWN", _failure("UNKNOWN_M3_MESSAGE_TYPE"))

func _handle_join(peer_id: String, session_id: String, payload: Dictionary) -> void:
	var logical_id := String(payload.get("logical_player_id", "")).strip_edges().to_lower()
	var operation_id := String(payload.get("operation_id", "")).strip_edges()
	if logical_id.is_empty() or operation_id.is_empty():
		_send(peer_id, "JOIN_REJECTED", {"operation_id": operation_id, "error_code": "INVALID_JOIN_PAYLOAD"})
		return
	var result: Dictionary = _service.join(logical_id, session_id, operation_id)
	if not bool(result.get("success", false)):
		_rejections += 1
		_send(peer_id, "JOIN_REJECTED", {"operation_id": operation_id, "error_code": String(result.get("error_code", "JOIN_REJECTED"))})
		return
	_peer_to_player[peer_id] = logical_id
	_peer_to_session[peer_id] = session_id
	_joins += 1
	_send(peer_id, "JOIN_ACK", {
		"operation_id": operation_id,
		"player": result.get("details", {}).get("player", {}),
		"snapshot": result.get("details", {}).get("snapshot", {}),
	})
	_broadcast_delta(result.get("details", {}).get("delta", {}), peer_id)
	_broadcast_snapshot("PLAYER_JOINED")
	_capture_two_connected_checksum()
	_write_report("READY", false)

func _handle_move(peer_id: String, session_id: String, payload: Dictionary) -> void:
	if not _peer_to_player.has(peer_id) or String(_peer_to_session.get(peer_id, "")) != session_id:
		_send_result(peer_id, String(payload.get("operation_id", "")), "MOVE", _failure("STALE_TRANSPORT_SESSION"))
		return
	var logical_id := String(_peer_to_player.get(peer_id, ""))
	var operation_id := String(payload.get("operation_id", ""))
	var result: Dictionary = _service.move_player(
		logical_id,
		session_id,
		int(payload.get("ownership_epoch", 0)),
		int(payload.get("input_sequence", 0)),
		float(payload.get("delta_x", 0.0)),
		float(payload.get("delta_z", 0.0)),
		operation_id
	)
	_send_result(peer_id, operation_id, "MOVE", result)
	if bool(result.get("success", false)):
		_moves += 1
		_broadcast_delta(result.get("details", {}).get("delta", {}))
		_broadcast_snapshot("PLAYER_MOVED")
		_capture_two_connected_checksum()
	else:
		_rejections += 1
	_write_report("READY", false)


func _handle_presentation(peer_id: String, session_id: String, payload: Dictionary) -> void:
	if not _peer_to_player.has(peer_id) or String(_peer_to_session.get(peer_id, "")) != session_id:
		_send_result(peer_id, String(payload.get("operation_id", "")), "PRESENTATION", _failure("STALE_TRANSPORT_SESSION"))
		return
	var logical_id := String(_peer_to_player.get(peer_id, ""))
	var operation_id := String(payload.get("operation_id", ""))
	var result: Dictionary = _service.set_player_presentation(
		logical_id, session_id, int(payload.get("ownership_epoch", 0)),
		float(payload.get("orientation_yaw", 0.0)), bool(payload.get("flashlight_enabled", false)), operation_id
	)
	_send_result(peer_id, operation_id, "PRESENTATION", result)
	if bool(result.get("success", false)):
		_presentation_updates += 1
		_broadcast_delta(result.get("details", {}).get("delta", {}))
		_broadcast_snapshot("PLAYER_PRESENTATION_UPDATED")
		_capture_two_connected_checksum()
	else:
		_rejections += 1
	_write_report("READY", false)

func _handle_leave(peer_id: String, session_id: String, payload: Dictionary) -> void:
	var logical_id := String(_peer_to_player.get(peer_id, payload.get("logical_player_id", "")))
	var operation_id := String(payload.get("operation_id", "operation/m3/leave/%d" % Time.get_ticks_msec()))
	var result: Dictionary = _service.leave(logical_id, session_id, operation_id)
	if bool(result.get("success", false)):
		_leaves += 1
		_send(peer_id, "LEAVE_ACK", {"operation_id": operation_id, "logical_player_id": logical_id})
		_broadcast_delta(result.get("details", {}).get("delta", {}), peer_id)
	else:
		_rejections += 1
		_send(peer_id, "LEAVE_REJECTED", {"operation_id": operation_id, "error_code": String(result.get("error_code", "LEAVE_REJECTED"))})
	_peer_to_player.erase(peer_id)
	_peer_to_session.erase(peer_id)
	_broadcast_snapshot("PLAYER_LEFT")
	_write_report("READY", false)

func _handle_disconnect(peer_id: String, session_id: String) -> void:
	if _service != null and not session_id.is_empty():
		var result: Dictionary = _service.leave_transport_session(session_id, "operation/m3/disconnect/%s" % session_id.sha256_text().left(16))
		if bool(result.get("success", false)) and not bool(result.get("details", {}).get("replay", true)):
			_leaves += 1
			_broadcast_delta(result.get("details", {}).get("delta", {}), peer_id)
	_peer_to_player.erase(peer_id)
	_peer_to_session.erase(peer_id)
	_broadcast_snapshot("PEER_DISCONNECTED")
	_write_report("READY", false)

func _send_result(peer_id: String, operation_id: String, command_type: String, result: Dictionary) -> void:
	var wire: Dictionary = _service.create_targeted_command_result("message/m3/result/%s" % operation_id.sha256_text().left(12), operation_id, result)
	_send(peer_id, "COMMAND_RESULT", {
		"operation_id": operation_id,
		"command_type": command_type,
		"status": String(wire.get("status", "REJECTED")),
		"error_code": String(wire.get("error_code", "")),
		"details": wire.get("payload", {}),
		"checksum": String(wire.get("checksum", "")),
	})

func _broadcast_delta(delta: Dictionary, excluded_peer_id: String = "") -> void:
	if delta.is_empty(): return
	for peer_id_value in _peer_to_player.keys():
		var peer_id := String(peer_id_value)
		if peer_id == excluded_peer_id: continue
		if _send(peer_id, "GAMEPLAY_DELTA", {"delta": delta}): _broadcasts += 1

func _broadcast_snapshot(reason: String) -> void:
	var snapshot: Dictionary = _service.create_snapshot()
	for peer_id_value in _peer_to_player.keys():
		if _send(String(peer_id_value), "GAMEPLAY_SNAPSHOT", {"reason": reason, "snapshot": snapshot}): _broadcasts += 1

func _send(peer_id: String, message_type: String, data: Dictionary) -> bool:
	if _boundary == null or peer_id.is_empty(): return false
	if not _ensure_peer_ready(peer_id): return false
	var payload := data.duplicate(true); payload["type"] = message_type
	var frame_result: Dictionary = _boundary.create_frame_for_peer(peer_id, "STATE", Support.MESSAGE_SCHEMA, payload)
	if not bool(frame_result.get("success", false)):
		_last_error_code = String(frame_result.get("error_code", "FRAME_CREATE_FAILED")); return false
	var sent: Dictionary = _boundary.send_to_peer(peer_id, frame_result.get("details", {}).get("frame", {}))
	if not bool(sent.get("success", false)):
		_last_error_code = String(sent.get("error_code", "SEND_FAILED")); return false
	var flushed: Dictionary = _boundary.flush_outbound(32, peer_id)
	if not bool(flushed.get("success", false)):
		_last_error_code = String(flushed.get("error_code", "FLUSH_FAILED")); return false
	_messages_sent += 1
	return true

func _ensure_peer_ready(peer_id: String) -> bool:
	if String(_boundary.get_peer_snapshot(peer_id).get("state", "")) == "READY": return true
	for method_name in ["mark_peer_handshaking", "mark_peer_synchronizing", "mark_peer_ready"]:
		var result: Dictionary = _boundary.call(method_name, peer_id)
		if not bool(result.get("success", false)) and String(result.get("error_code", "")) != "INVALID_PEER_STATE_TRANSITION": return false
	return String(_boundary.get_peer_snapshot(peer_id).get("state", "")) == "READY"

func _capture_two_connected_checksum() -> void:
	if _peer_to_player.size() == 2 and _service != null:
		_last_two_connected_checksum = String(_service.create_snapshot().get("checksum", ""))

func get_world_entity_store_for_kernel():
	return null

func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"checkpoint": Support.CHECKPOINT,
		"build_id": Support.BUILD_ID,
		"configured": _configured,
		"host": _host,
		"port": _port,
		"connected_peer_count": _peer_to_player.size(),
		"peer_to_player": _peer_to_player.duplicate(true),
		"joins": _joins,
		"leaves": _leaves,
		"moves": _moves,
		"presentation_updates": _presentation_updates,
		"rejections": _rejections,
		"broadcasts": _broadcasts,
		"messages_sent": _messages_sent,
		"messages_received": _messages_received,
		"last_error_code": _last_error_code,
		"last_two_connected_checksum": _last_two_connected_checksum,
		"snapshot": _service.create_snapshot() if _service != null else {},
		"service": _service.get_report() if _service != null else {},
		"boundary": _boundary.get_snapshot() if _boundary != null else {},
		"resolved_user_data_dir": OS.get_user_data_dir(),
		"direct_client_authority_references": 0,
	}

func stop() -> Dictionary:
	set_process(false)
	_write_report("STOPPED", true)
	if _boundary != null: _boundary.stop()
	if _service != null: _service.shutdown()
	_boundary = null; _service = null; _configured = false
	return _success()

func _write_report(state: String, passed: bool) -> void:
	if _result_file.is_empty(): return
	var report := get_report(); report["state"] = state; report["passed"] = passed; report["process_id"] = OS.get_process_id()
	Support.write(_result_file, report)

func _exit_tree() -> void:
	if _configured: stop()

func _success(details: Dictionary = {}) -> Dictionary: return {"success": true, "error_code": "", "details": details.duplicate(true)}
func _failure(error_code: String, details: Dictionary = {}) -> Dictionary: return {"success": false, "error_code": error_code, "details": details.duplicate(true)}

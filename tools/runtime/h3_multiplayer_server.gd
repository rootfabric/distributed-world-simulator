extends SceneTree

const Support = preload("res://tools/runtime/h3_multiplayer_process_support.gd")
const Boundary = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const Port = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
const Authority = preload("res://scripts/runtime/host_client/multiplayer_gameplay_authority.gd")

var _options: Dictionary = {}
var _boundary
var _authority
var _started_ms := 0
var _finished := false
var _peer_by_player: Dictionary = {}
var _session_by_player: Dictionary = {}
var _movement_done: Dictionary = {}
var _pickup_attempts: Dictionary = {}
var _pickup_results: Dictionary = {}
var _b_continued := false
var _a_rejoined := false
var _a_first_entity := ""
var _a_first_epoch := 0
var _a_second_epoch := 0
var _scenario_complete_sent := false
var _completion_started_ms := 0
var _final_snapshot: Dictionary = {}
var _broadcast_deltas := 0
var _targeted_results := 0
var _disconnects := 0
var _reconnects := 0


func _initialize() -> void:
	var parsed := Support.parse(OS.get_cmdline_user_args())
	_options = parsed.get("options", {})
	if not bool(parsed.get("success", false)):
		_fail("INVALID_OPTIONS", {"errors": parsed.get("errors", [])})
		return
	_authority = Authority.new()
	var setup_result: Dictionary = _authority.setup("simulation/h3/dedicated", 3, 2000)
	if not bool(setup_result.get("success", false)):
		_fail(String(setup_result.get("error_code", "AUTHORITY_SETUP_FAILED")))
		return
	_boundary = Boundary.new()
	var configured: Dictionary = _boundary.configure(Port.new(), 524288, 64, 2097152)
	if not bool(configured.get("success", false)):
		_fail(String(configured.get("error_code", "BOUNDARY_CONFIGURATION_FAILED")))
		return
	var started: Dictionary = _boundary.start_server(Support.endpoint(_options, true))
	if not bool(started.get("success", false)):
		_fail(String(started.get("error_code", "SERVER_START_FAILED")))
		return
	_started_ms = Time.get_ticks_msec()
	Support.write(String(_options["result_file"]), {
		"schema": "planet_simulator.h3_multiplayer_server_state.v1",
		"state": "LISTENING",
		"passed": false,
		"port": int(_options["port"]),
	})
	print("H3_SERVER_LISTENING port=%d" % int(_options["port"]))


func _process(_delta: float) -> bool:
	if _finished or _boundary == null:
		return false
	var polled: Dictionary = _boundary.poll_events(128)
	if not bool(polled.get("success", false)):
		_fail(String(polled.get("error_code", "POLL_FAILED")), _boundary.get_snapshot())
		return false
	for event in polled.get("details", {}).get("events", []):
		var event_type := String(event.get("event_type", ""))
		var peer_id := String(event.get("peer_id", ""))
		var session_id := String(event.get("session_id", ""))
		if event_type == "MESSAGE_RECEIVED":
			_handle_message(peer_id, session_id, event.get("frame", {}).get("payload", {}))
		elif event_type == "PEER_DISCONNECTED" and not _scenario_complete_sent:
			_handle_disconnect(peer_id, session_id)
	if _scenario_complete_sent:
		if int(_boundary.get_snapshot().get("outbound_pending_messages", 0)) == 0 and Time.get_ticks_msec() - _completion_started_ms >= 500:
			_success()
			return false
	if Time.get_ticks_msec() - _started_ms > int(_options.get("timeout_ms", 30000)):
		_fail("SERVER_TIMEOUT", {"authority": _authority.get_report(), "boundary": _boundary.get_snapshot()})
	return false


func _handle_message(peer_id: String, session_id: String, payload: Dictionary) -> void:
	var message_type := String(payload.get("type", ""))
	match message_type:
		"JOIN": _handle_join(peer_id, session_id, payload)
		"MOVE": _handle_move(peer_id, session_id, payload)
		"PICKUP": _handle_pickup(peer_id, session_id, payload)
		"LEAVE": _handle_leave(peer_id, session_id, payload)
		_: _send_reject(peer_id, String(payload.get("operation_id", "")), "UNKNOWN_H3_MESSAGE_TYPE")


func _handle_join(peer_id: String, session_id: String, payload: Dictionary) -> void:
	var logical_player_id := String(payload.get("logical_player_id", "")).to_lower()
	if logical_player_id not in ["a", "b"]:
		_send_reject(peer_id, String(payload.get("operation_id", "")), "INVALID_LOGICAL_PLAYER_ID")
		return
	var result: Dictionary = _authority.join(logical_player_id, session_id, String(payload.get("operation_id", "")))
	if not bool(result.get("success", false)):
		_send_reject(peer_id, String(payload.get("operation_id", "")), String(result.get("error_code", "JOIN_REJECTED")))
		return
	var player: Dictionary = result.get("details", {}).get("player", {})
	if logical_player_id == "a":
		if _a_first_entity.is_empty():
			_a_first_entity = String(player.get("player_entity_id", ""))
			_a_first_epoch = int(player.get("ownership_epoch", 0))
		else:
			_a_rejoined = true
			_reconnects += 1
			_a_second_epoch = int(player.get("ownership_epoch", 0))
	_peer_by_player[logical_player_id] = peer_id
	_session_by_player[logical_player_id] = session_id
	_send(peer_id, "JOIN_ACK", {
		"logical_player_id": logical_player_id,
		"player": player,
		"snapshot": result.get("details", {}).get("snapshot", {}),
		"operation_id": String(payload.get("operation_id", "")),
	})
	_broadcast_delta(result.get("details", {}).get("delta", {}), peer_id)
	if _a_rejoined and _b_continued:
		_complete_scenario()
	elif _initial_players_ready():
		_send_stage("START_MOVEMENT")


func _handle_move(peer_id: String, session_id: String, payload: Dictionary) -> void:
	var logical_player_id := String(payload.get("logical_player_id", "")).to_lower()
	var operation_id := String(payload.get("operation_id", ""))
	var result: Dictionary = _authority.move_player(
		logical_player_id,
		session_id,
		int(payload.get("ownership_epoch", 0)),
		int(payload.get("input_sequence", 0)),
		float(payload.get("delta_x", 0.0)),
		float(payload.get("delta_z", 0.0)),
		operation_id
	)
	_send_command_result(peer_id, operation_id, "MOVE", result)
	if not bool(result.get("success", false)):
		return
	_broadcast_delta(result.get("details", {}).get("delta", {}))
	if logical_player_id == "b" and int(payload.get("input_sequence", 0)) == 2:
		_b_continued = true
		if _a_rejoined:
			_complete_scenario()
		return
	_movement_done[logical_player_id] = true
	if _movement_done.has("a") and _movement_done.has("b") and _pickup_attempts.is_empty():
		_send_stage("START_CONTENTION")


func _handle_pickup(peer_id: String, session_id: String, payload: Dictionary) -> void:
	var logical_player_id := String(payload.get("logical_player_id", "")).to_lower()
	var operation_id := String(payload.get("operation_id", ""))
	var result: Dictionary = _authority.pickup_shared_item(
		logical_player_id,
		session_id,
		int(payload.get("ownership_epoch", 0)),
		String(payload.get("item_id", "")),
		operation_id
	)
	_pickup_attempts[logical_player_id] = true
	_pickup_results[logical_player_id] = {
		"success": bool(result.get("success", false)),
		"error_code": String(result.get("error_code", "")),
	}
	_send_command_result(peer_id, operation_id, "PICKUP", result)
	if bool(result.get("success", false)):
		_broadcast_delta(result.get("details", {}).get("delta", {}))
	if _pickup_attempts.has("a") and _pickup_attempts.has("b"):
		_broadcast_snapshot("CONTENTION_COMPLETE")
		_send(String(_peer_by_player.get("a", "")), "DISCONNECT_AND_REJOIN", {
			"logical_player_id": "a",
			"snapshot": _authority.create_snapshot(),
		})


func _handle_leave(peer_id: String, session_id: String, payload: Dictionary) -> void:
	var logical_player_id := String(payload.get("logical_player_id", "")).to_lower()
	var operation_id := String(payload.get("operation_id", ""))
	var result: Dictionary = _authority.leave(logical_player_id, session_id, operation_id)
	if not bool(result.get("success", false)):
		_send_reject(peer_id, operation_id, String(result.get("error_code", "LEAVE_REJECTED")))
		return
	_send(peer_id, "LEAVE_ACK", {"logical_player_id": logical_player_id, "operation_id": operation_id})
	_broadcast_delta(result.get("details", {}).get("delta", {}), peer_id)
	_peer_by_player.erase(logical_player_id)
	_session_by_player.erase(logical_player_id)
	if logical_player_id == "a":
		_disconnects += 1
		_send(String(_peer_by_player.get("b", "")), "CONTINUE_AFTER_A_LEFT", {
			"logical_player_id": "b",
			"snapshot": result.get("details", {}).get("snapshot", {}),
		})


func _handle_disconnect(peer_id: String, session_id: String) -> void:
	var result: Dictionary = _authority.leave_transport_session(
		session_id,
		"operation/h3/disconnect/%s" % session_id.sha256_text().left(12)
	)
	if bool(result.get("success", false)) and not bool(result.get("details", {}).get("replay", true)):
		_broadcast_delta(result.get("details", {}).get("delta", {}), peer_id)
	for logical_player_id in _peer_by_player.keys().duplicate():
		if String(_peer_by_player[logical_player_id]) == peer_id:
			_peer_by_player.erase(logical_player_id)
			_session_by_player.erase(logical_player_id)


func _send_command_result(peer_id: String, operation_id: String, command_type: String, result: Dictionary) -> void:
	var wire_result: Dictionary = _authority.create_targeted_command_result(
		"message/h3/result/%s" % operation_id.sha256_text().left(12),
		operation_id,
		result
	)
	var payload := {
		"operation_id": operation_id,
		"command_type": command_type,
		"status": String(wire_result.get("status", "REJECTED")),
		"error_code": String(wire_result.get("error_code", "")),
		"details": wire_result.get("payload", {}).duplicate(true),
		"wire_result_checksum": String(wire_result.get("checksum", "")),
	}
	_send(peer_id, "COMMAND_RESULT", payload)
	_targeted_results += 1


func _send_reject(peer_id: String, operation_id: String, error_code: String) -> void:
	_send_command_result(peer_id, operation_id, "UNKNOWN", {
		"success": false,
		"error_code": error_code,
		"details": {},
	})


func _send_stage(stage: String) -> void:
	for logical_player_id in ["a", "b"]:
		var peer_id := String(_peer_by_player.get(logical_player_id, ""))
		if not peer_id.is_empty():
			_send(peer_id, stage, {"logical_player_id": logical_player_id, "snapshot": _authority.create_snapshot()})


func _broadcast_delta(delta: Dictionary, excluded_peer_id: String = "") -> void:
	if delta.is_empty():
		return
	for peer_id_value in _peer_by_player.values():
		var peer_id := String(peer_id_value)
		if peer_id.is_empty() or peer_id == excluded_peer_id:
			continue
		_send(peer_id, "GAMEPLAY_DELTA", {"delta": delta})
		_broadcast_deltas += 1


func _broadcast_snapshot(reason: String) -> void:
	var snapshot: Dictionary = _authority.create_snapshot()
	for peer_id_value in _peer_by_player.values():
		var peer_id := String(peer_id_value)
		if not peer_id.is_empty():
			_send(peer_id, "GAMEPLAY_SNAPSHOT", {"reason": reason, "snapshot": snapshot})


func _send(peer_id: String, message_type: String, data: Dictionary) -> void:
	if peer_id.is_empty() or _finished:
		return
	if not _ensure_peer_ready(peer_id):
		_fail("PEER_READY_FAILED", {"peer_id": peer_id, "message_type": message_type})
		return
	var payload := data.duplicate(true)
	payload["type"] = message_type
	var frame_result: Dictionary = _boundary.create_frame_for_peer(peer_id, "STATE", Support.MESSAGE_SCHEMA, payload)
	if not bool(frame_result.get("success", false)):
		_fail(String(frame_result.get("error_code", "FRAME_CREATE_FAILED")))
		return
	var sent: Dictionary = _boundary.send_to_peer(peer_id, frame_result.get("details", {}).get("frame", {}))
	if not bool(sent.get("success", false)):
		_fail(String(sent.get("error_code", "SEND_FAILED")), {"peer_id": peer_id, "message_type": message_type})


func _ensure_peer_ready(peer_id: String) -> bool:
	var state := String(_boundary.get_peer_snapshot(peer_id).get("state", ""))
	if state == "READY":
		return true
	for method_name in ["mark_peer_handshaking", "mark_peer_synchronizing", "mark_peer_ready"]:
		var result: Dictionary = _boundary.call(method_name, peer_id)
		if not bool(result.get("success", false)) and String(result.get("error_code", "")) != "INVALID_PEER_STATE_TRANSITION":
			return false
	return String(_boundary.get_peer_snapshot(peer_id).get("state", "")) == "READY"


func _initial_players_ready() -> bool:
	if _a_rejoined:
		return false
	return _peer_by_player.has("a") and _peer_by_player.has("b") and _movement_done.is_empty()


func _complete_scenario() -> void:
	if _scenario_complete_sent:
		return
	_final_snapshot = _authority.create_snapshot()
	for logical_player_id in ["a", "b"]:
		var peer_id := String(_peer_by_player.get(logical_player_id, ""))
		if not peer_id.is_empty():
			_send(peer_id, "SCENARIO_COMPLETE", {"snapshot": _final_snapshot})
	_scenario_complete_sent = true
	_completion_started_ms = Time.get_ticks_msec()


func _success() -> void:
	var winner := String(_authority.get_report().get("shared_item_owner", ""))
	var report := {
		"schema": "planet_simulator.h3_multiplayer_server_report.v1",
		"checkpoint": Support.CHECKPOINT,
		"build_id": Support.BUILD_ID,
		"state": "COMPLETE",
		"passed": true,
		"authority": _authority.get_report(),
		"final_snapshot": _final_snapshot,
		"pickup_results": _pickup_results.duplicate(true),
		"winner_player_entity_id": winner,
		"a_player_entity_id": _a_first_entity,
		"a_first_ownership_epoch": _a_first_epoch,
		"a_second_ownership_epoch": _a_second_epoch,
		"a_rejoined": _a_rejoined,
		"b_continued_after_a_left": _b_continued,
		"explicit_disconnects": _disconnects,
		"reconnects": _reconnects,
		"broadcast_deltas": _broadcast_deltas,
		"targeted_results": _targeted_results,
		"listener_state": String(_boundary.get_snapshot().get("state", "")),
		"process_id": OS.get_process_id(),
	}
	Support.write(String(_options["result_file"]), report)
	_finished = true
	print("H3_SERVER_RESULT %s" % JSON.stringify(report))
	quit(0)


func _fail(error_code: String, details: Dictionary = {}) -> void:
	if _finished:
		return
	var report := {
		"schema": "planet_simulator.h3_multiplayer_server_report.v1",
		"state": "FAILED",
		"passed": false,
		"failure_code": error_code,
		"details": details.duplicate(true),
		"process_id": OS.get_process_id(),
	}
	if not String(_options.get("result_file", "")).is_empty():
		Support.write(String(_options["result_file"]), report)
	_finished = true
	push_error("H3 server failed: %s" % error_code)
	quit(1)


func _finalize() -> void:
	if _boundary != null:
		_boundary.stop()

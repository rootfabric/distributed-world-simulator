extends Node

signal finished(exit_code: int)

const Contracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")

const MOVE_INTERVAL_MS := 50
const RETRY_INTERVAL_MS := 200

var _server_host := "127.0.0.1"
var _server_a_port := 24580
var _server_b_port := 24581
var _client_port := 24780
var _handoffs_requested := 4
var _timeout_ms := 60000
var _result_file := ""
var _post_handoff_settle_steps := 0

var _socket: PacketPeerUDP
var _state := "INIT"
var _current_authority_id := Contracts.AUTHORITY_A
var _current_zone_id := Contracts.ZONE_A
var _current_server_port := 24580
var _session_id := ""
var _logical_player_id := "a"
var _player_entity_id := ""
var _ownership_epoch := 0
var _directory_epoch := 1
var _directory_revision := 1
var _input_sequence := 0
var _handoffs_completed := 0
var _round_trips_completed := 0
var _started_ms := 0
var _last_move_ms := 0
var _settle_steps_remaining := 0
var _outstanding: Dictionary = {}
var _pending_transfer: Dictionary = {}
var _completed_transfers: Dictionary = {}
var _last_player: Dictionary = {}
var _identity_changes := 0
var _errors: Array[String] = []


func setup(config: Dictionary) -> Dictionary:
	_server_host = String(config.get("server_host", "127.0.0.1")).strip_edges()
	_server_a_port = int(config.get("server_a_port", 24580))
	_server_b_port = int(config.get("server_b_port", 24581))
	_client_port = int(config.get("client_port", 24780))
	_handoffs_requested = int(config.get("handoffs", 4))
	_timeout_ms = int(config.get("timeout_ms", 60000))
	_result_file = String(config.get("result_file", "")).strip_edges()
	_post_handoff_settle_steps = int(config.get("post_handoff_settle_steps", 0))
	if (
		_server_host.is_empty()
		or _server_a_port < 1
		or _server_b_port < 1
		or _client_port < 1
		or _handoffs_requested < 1
		or _timeout_ms < 1000
		or _post_handoff_settle_steps < 0
		or _post_handoff_settle_steps > 16
	):
		return _failure("SM0_INVALID_CLIENT_CONFIGURATION")

	_socket = PacketPeerUDP.new()
	var bind_result := _socket.bind(_client_port, "127.0.0.1")
	if bind_result != OK:
		return _failure("SM0_CLIENT_BIND_FAILED", {"error": bind_result, "client_port": _client_port})

	_started_ms = Time.get_ticks_msec()
	_current_server_port = _server_a_port
	_session_id = "transport-session/sm0/client/a/initial/%d" % OS.get_process_id()
	if not _select_server(_current_server_port):
		_socket.close()
		return _failure("SM0_CLIENT_SERVER_ROUTE_FAILED")
	_state = "JOINING"
	_send_join()
	set_process(true)
	_event("SM0_CLIENT_STARTED", {
		"handoffs_requested": _handoffs_requested,
		"server_a_port": _server_a_port,
		"server_b_port": _server_b_port,
		"client_port": _client_port,
		"post_handoff_settle_steps": _post_handoff_settle_steps,
	})
	return _success()


func _process(_delta: float) -> void:
	_poll_packets()
	var now := Time.get_ticks_msec()
	if now - _started_ms > _timeout_ms:
		_fail("SM0_CLIENT_ACCEPTANCE_TIMEOUT", {
			"state": _state,
			"handoffs_completed": _handoffs_completed,
		})
		return
	_retry_outstanding(now)
	if _state == "ACTIVE" and _outstanding.is_empty() and now - _last_move_ms >= MOVE_INTERVAL_MS:
		_last_move_ms = now
		_send_next_move()


func _select_server(port: int) -> bool:
	if _socket == null or port < 1:
		return false
	_current_server_port = port
	return _socket.set_dest_address(_server_host, port) == OK


func _poll_packets() -> void:
	if _socket == null:
		return
	while _socket.get_available_packet_count() > 0:
		var packet := _socket.get_packet()
		var remote_ip := _socket.get_packet_ip()
		var remote_port := _socket.get_packet_port()
		var message := Contracts.decode_message(packet)
		var validation := Contracts.validate_message(message)
		if not bool(validation.get("success", false)):
			_fail(String(validation.get("error_code", "SM0_CLIENT_INVALID_PACKET")), {})
			return
		_handle_message(message, remote_ip, remote_port)


func _handle_message(message: Dictionary, remote_ip: String, remote_port: int) -> void:
	var message_type := String(message.get("type", ""))
	var request_id := String(message.get("request_id", ""))
	var payload: Dictionary = Dictionary(message.get("payload", {}))
	match message_type:
		"JOIN_ACK":
			_handle_join_ack(request_id, payload)
		"MOVE_ACK":
			_handle_move_ack(request_id, payload)
		"HANDOFF_REDIRECT":
			_handle_redirect(payload, remote_ip, remote_port)
		"ACTIVATE_ACK":
			_handle_activate_ack(request_id, payload)
		"SM0_ERROR":
			_handle_error(request_id, payload)
		_:
			pass


func _handle_join_ack(request_id: String, payload: Dictionary) -> void:
	if _state != "JOINING" or not _matches_outstanding(request_id):
		return
	_clear_outstanding()
	_current_authority_id = String(payload.get("authority_id", ""))
	_current_zone_id = String(payload.get("zone_id", ""))
	var directory: Dictionary = Dictionary(payload.get("directory", {}))
	var directory_check := Contracts.validate_directory(directory)
	if not bool(directory_check.get("success", false)) or _current_authority_id != Contracts.AUTHORITY_A:
		_fail("SM0_CLIENT_INITIAL_DIRECTORY_INVALID", {"directory": directory})
		return
	_directory_epoch = int(directory.get("authority_epoch", 0))
	_directory_revision = int(directory.get("revision", 0))
	_session_id = String(payload.get("session_id", _session_id))
	_last_player = Dictionary(payload.get("player", {})).duplicate(true)
	if not _capture_identity(_last_player):
		return
	_ownership_epoch = int(_last_player.get("ownership_epoch", 0))
	_input_sequence = int(_last_player.get("last_input_sequence", 0))
	_state = "ACTIVE"
	_event("SM0_CLIENT_ROUTE_ACTIVE", {
		"authority_id": _current_authority_id,
		"zone_id": _current_zone_id,
		"directory": directory,
		"player": _last_player,
	})


func _send_join() -> void:
	var request_id := "join/%d" % OS.get_process_id()
	var message := Contracts.create_message("CLIENT_JOIN", {
		"logical_player_id": _logical_player_id,
		"session_id": _session_id,
	}, request_id)
	_set_outstanding("JOIN", request_id, message)
	_send_message(message)


func _send_next_move() -> void:
	_input_sequence += 1
	var delta_x := _next_delta_x()
	var request_id := "move/%d" % _input_sequence
	var message := Contracts.create_message("CLIENT_MOVE", {
		"logical_player_id": _logical_player_id,
		"session_id": _session_id,
		"ownership_epoch": _ownership_epoch,
		"input_sequence": _input_sequence,
		"delta_x": delta_x,
		"delta_z": 0.0,
	}, request_id)
	_set_outstanding("MOVE", request_id, message)
	_send_message(message)


func _next_delta_x() -> float:
	if _settle_steps_remaining > 0:
		return -0.5 if _current_authority_id == Contracts.AUTHORITY_A else 0.5
	return 0.5 if _current_authority_id == Contracts.AUTHORITY_A else -0.5


func _handle_move_ack(request_id: String, payload: Dictionary) -> void:
	if not _matches_outstanding(request_id):
		return
	_clear_outstanding()
	if not bool(payload.get("accepted", false)):
		var error_code := String(payload.get("error_code", "SM0_MOVE_REJECTED"))
		if error_code == "SM0_PLAYER_FROZEN_FOR_HANDOFF" and bool(payload.get("handoff_pending", false)):
			_state = "WAIT_HANDOFF"
			return
		_fail(error_code, payload)
		return
	_last_player = Dictionary(payload.get("player", {})).duplicate(true)
	if not _capture_identity(_last_player):
		return
	_ownership_epoch = int(_last_player.get("ownership_epoch", _ownership_epoch))
	if _settle_steps_remaining > 0:
		_settle_steps_remaining -= 1
		_event("SM0_CLIENT_SETTLE_STEP_COMPLETED", {
			"remaining": _settle_steps_remaining,
			"player": _last_player,
		})
	_state = "ACTIVE"


func _handle_redirect(payload: Dictionary, remote_ip: String, remote_port: int) -> void:
	var transfer_id := String(payload.get("transfer_id", ""))
	if transfer_id.is_empty():
		_fail("SM0_CLIENT_REDIRECT_TRANSFER_ID_REQUIRED", payload)
		return

	# A source may retry the redirect after the client has already activated the
	# target. Re-ACK that exact transfer without changing the active route.
	if _completed_transfers.has(transfer_id):
		_send_redirect_ack(remote_ip, remote_port, transfer_id)
		return
	if (
		_state == "ACTIVATING"
		and transfer_id == String(_pending_transfer.get("transfer_id", ""))
	):
		_send_redirect_ack(remote_ip, remote_port, transfer_id)
		return

	var target_authority := String(payload.get("target_authority_id", ""))
	var expected_target := Contracts.peer_authority(_current_authority_id)
	if target_authority != expected_target:
		_fail("SM0_CLIENT_REDIRECT_TARGET_MISMATCH", payload)
		return
	var target_epoch := int(payload.get("authority_epoch", 0))
	if target_epoch != _directory_epoch + 1:
		_fail("SM0_CLIENT_REDIRECT_EPOCH_MISMATCH", payload)
		return
	var player_entity_id := String(payload.get("player_entity_id", ""))
	if not _player_entity_id.is_empty() and player_entity_id != _player_entity_id:
		_identity_changes += 1
		_fail("SM0_CLIENT_REDIRECT_PLAYER_ID_CHANGED", payload)
		return

	_send_redirect_ack(remote_ip, remote_port, transfer_id)
	_pending_transfer = {
		"transfer_id": transfer_id,
		"source_ip": remote_ip,
		"source_port": remote_port,
		"target_authority_id": target_authority,
		"target_zone_id": String(payload.get("target_zone_id", "")),
		"authority_epoch": target_epoch,
		"target_port": int(payload.get("target_port", 0)),
	}
	_clear_outstanding()
	_state = "ACTIVATING"
	if not _select_server(int(_pending_transfer.get("target_port", 0))):
		_fail("SM0_CLIENT_TARGET_ROUTE_FAILED", _pending_transfer)
		return
	_event("SM0_CLIENT_ROUTE_SWITCHING", _pending_transfer)
	_send_activate()


func _send_redirect_ack(host: String, port: int, transfer_id: String) -> void:
	var ack := Contracts.create_message(
		"CLIENT_REDIRECT_ACK",
		{"transfer_id": transfer_id},
		"redirect-ack/%s" % transfer_id.sha256_text().left(12)
	)
	_send_message_to(host, port, ack)


func _send_activate() -> void:
	var transfer_id := String(_pending_transfer.get("transfer_id", ""))
	var request_id := "activate/%s" % transfer_id.sha256_text().left(12)
	var message := Contracts.create_message("CLIENT_ACTIVATE", {
		"transfer_id": transfer_id,
		"logical_player_id": _logical_player_id,
		"player_entity_id": _player_entity_id,
		"authority_epoch": int(_pending_transfer.get("authority_epoch", 0)),
	}, request_id)
	_set_outstanding("ACTIVATE", request_id, message)
	_send_message(message)


func _handle_activate_ack(request_id: String, payload: Dictionary) -> void:
	if _state != "ACTIVATING" or not _matches_outstanding(request_id):
		return
	var transfer_id := String(payload.get("transfer_id", ""))
	if transfer_id != String(_pending_transfer.get("transfer_id", "")):
		_fail("SM0_CLIENT_ACTIVATE_TRANSFER_MISMATCH", payload)
		return
	var directory: Dictionary = Dictionary(payload.get("directory", {}))
	var directory_check := Contracts.validate_directory(directory)
	if not bool(directory_check.get("success", false)):
		_fail(String(directory_check.get("error_code", "SM0_CLIENT_TARGET_DIRECTORY_INVALID")), payload)
		return
	if int(directory.get("authority_epoch", 0)) != int(_pending_transfer.get("authority_epoch", 0)):
		_fail("SM0_CLIENT_TARGET_EPOCH_MISMATCH", payload)
		return
	_clear_outstanding()
	_current_authority_id = String(payload.get("authority_id", ""))
	_current_zone_id = String(payload.get("zone_id", ""))
	_session_id = String(payload.get("session_id", ""))
	_directory_epoch = int(directory.get("authority_epoch", 0))
	_directory_revision = int(directory.get("revision", 0))
	_last_player = Dictionary(payload.get("player", {})).duplicate(true)
	if not _capture_identity(_last_player):
		return
	_ownership_epoch = int(_last_player.get("ownership_epoch", 0))
	_input_sequence = maxi(_input_sequence, int(_last_player.get("last_input_sequence", 0)))
	_handoffs_completed += 1
	if _handoffs_completed % 2 == 0:
		_round_trips_completed += 1
	_completed_transfers[transfer_id] = true
	_event("SM0_CROSSING_COMPLETED", {
		"handoff_index": _handoffs_completed,
		"transfer_id": transfer_id,
		"authority_id": _current_authority_id,
		"zone_id": _current_zone_id,
		"directory": directory,
		"player": _last_player,
	})
	_pending_transfer.clear()
	if _handoffs_completed >= _handoffs_requested:
		_finish_pass()
		return
	_settle_steps_remaining = _post_handoff_settle_steps
	_state = "ACTIVE"


func _handle_error(request_id: String, payload: Dictionary) -> void:
	# Old-source errors may arrive after a route switch. Only the response to the
	# currently outstanding request can fail the current client state.
	if not _matches_outstanding(request_id):
		return
	var error_code := String(payload.get("error_code", "SM0_REMOTE_ERROR"))
	if _state == "ACTIVATING" and error_code == "SM0_TARGET_NOT_COMMITTED":
		_outstanding["last_send_ms"] = 0
		return
	_fail(error_code, payload)


func _retry_outstanding(now: int) -> void:
	if _outstanding.is_empty():
		return
	var last_send := int(_outstanding.get("last_send_ms", 0))
	if last_send > 0 and now - last_send < RETRY_INTERVAL_MS:
		return
	_outstanding["last_send_ms"] = now
	_outstanding["retries"] = int(_outstanding.get("retries", 0)) + 1
	_send_message(Dictionary(_outstanding.get("message", {})))


func _set_outstanding(kind: String, request_id: String, message: Dictionary) -> void:
	_outstanding = {
		"kind": kind,
		"request_id": request_id,
		"message": message.duplicate(true),
		"last_send_ms": Time.get_ticks_msec(),
		"retries": 0,
	}


func _matches_outstanding(request_id: String) -> bool:
	return not _outstanding.is_empty() and String(_outstanding.get("request_id", "")) == request_id


func _clear_outstanding() -> void:
	_outstanding.clear()


func _send_message(message: Dictionary) -> void:
	if _socket == null:
		return
	_socket.put_packet(Contracts.encode_message(message))


func _send_message_to(host: String, port: int, message: Dictionary) -> void:
	if _socket == null or host.is_empty() or port < 1:
		return
	var restore_port := _current_server_port
	if _socket.set_dest_address(host, port) != OK:
		return
	_socket.put_packet(Contracts.encode_message(message))
	_socket.set_dest_address(_server_host, restore_port)


func _capture_identity(player: Dictionary) -> bool:
	var logical_id := String(player.get("logical_player_id", ""))
	var entity_id := String(player.get("player_entity_id", ""))
	if logical_id != _logical_player_id or entity_id.is_empty():
		_fail("SM0_CLIENT_PLAYER_IDENTITY_INVALID", {"player": player})
		return false
	if _player_entity_id.is_empty():
		_player_entity_id = entity_id
	elif entity_id != _player_entity_id:
		_identity_changes += 1
		_fail("SM0_CLIENT_PLAYER_ENTITY_CHANGED", {
			"expected": _player_entity_id,
			"actual": entity_id,
		})
		return false
	return true


func _finish_pass() -> void:
	_state = "DONE"
	var summary := {
		"schema": "distributed_world_simulator.sm0_client_result.v1",
		"result": "PASS",
		"handoffs_requested": _handoffs_requested,
		"handoffs_completed": _handoffs_completed,
		"round_trips_completed": _round_trips_completed,
		"logical_player_id": _logical_player_id,
		"player_entity_id": _player_entity_id,
		"identity_changes": _identity_changes,
		"authority_epoch_start": 1,
		"authority_epoch_end": _directory_epoch,
		"directory_revision_end": _directory_revision,
		"final_authority_id": _current_authority_id,
		"final_zone_id": _current_zone_id,
		"final_input_sequence": _input_sequence,
		"process_id": OS.get_process_id(),
		"client_port": _client_port,
		"errors": _errors.duplicate(),
	}
	_write_result(summary)
	_event("SM0_ACCEPTANCE_RESULT", summary)
	set_process(false)
	if _socket != null:
		_socket.close()
	finished.emit(0)


func _fail(error_code: String, details: Dictionary) -> void:
	if _state == "FAILED" or _state == "DONE":
		return
	_state = "FAILED"
	_errors.append(error_code)
	_event("SM0_INVARIANT_VIOLATION", {
		"error_code": error_code,
		"details": details,
	})
	var summary := {
		"schema": "distributed_world_simulator.sm0_client_result.v1",
		"result": "FAIL",
		"error_code": error_code,
		"handoffs_requested": _handoffs_requested,
		"handoffs_completed": _handoffs_completed,
		"round_trips_completed": _round_trips_completed,
		"logical_player_id": _logical_player_id,
		"player_entity_id": _player_entity_id,
		"identity_changes": _identity_changes,
		"authority_epoch_end": _directory_epoch,
		"final_authority_id": _current_authority_id,
		"final_input_sequence": _input_sequence,
		"process_id": OS.get_process_id(),
		"client_port": _client_port,
		"errors": _errors.duplicate(),
	}
	_write_result(summary)
	_event("SM0_ACCEPTANCE_RESULT", summary)
	set_process(false)
	if _socket != null:
		_socket.close()
	finished.emit(1)


func _write_result(summary: Dictionary) -> void:
	if _result_file.is_empty():
		return
	var file := FileAccess.open(_result_file, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(summary, "  ", false, true))
	file.close()


func _event(event_name: String, details: Dictionary = {}) -> void:
	var event := {
		"schema": "distributed_world_simulator.sm0_event.v1",
		"event": event_name,
		"severity": "INFO",
		"process_role": "client-driver",
		"process_id": OS.get_process_id(),
		"time_msec": Time.get_ticks_msec(),
		"state": _state,
		"authority_id": _current_authority_id,
		"zone_id": _current_zone_id,
		"authority_epoch": _directory_epoch,
		"input_sequence": _input_sequence,
	}
	for key in details.keys():
		event[key] = details[key]
	print("[SM0_EVENT] %s" % JSON.stringify(event, "", false, true))


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}

extends Node

signal session_ready(runtime)
signal replica_updated(snapshot: Dictionary)
signal item_graph_updated(snapshot: Dictionary)
signal connection_failed(error_code: String, details: Dictionary)
signal server_disconnected(report: Dictionary)

const Boundary = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const Port = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
const Replica = preload("res://scripts/runtime/host_client/multiplayer_gameplay_replica_store.gd")
const Support = preload("res://scripts/runtime/networked_gameplay/m3/m3_process_support.gd")

const SCHEMA := "planet_simulator.m3_graphical_client_runtime.v1"
const SERVER_PEER_ID := "peer/enet/m3-dedicated-server"
const M7_CHECKPOINT := "v16.10.6.1-testing-m7-playable-networked-playground"
const M7_BUILD_ID := "m7-playable-networked-playground"

var _boundary
var _replica
var _configured := false
var _joined := false
var _join_sent := false
var _join_operation_id := ""
var _host := "127.0.0.1"
var _port := 0
var _logical_player_id := "a"
var _transport_session_id := ""
var _player_entity_id := ""
var _ownership_epoch := 0
var _input_sequence := 0
var _result_file := ""
var _connect_timeout_ms := 30000
var _command_timeout_ms := 8000
var _started_ms := 0
var _message_sequence := 0
var _messages_sent := 0
var _messages_received := 0
var _snapshot_updates := 0
var _delta_updates := 0
var _command_results: Dictionary = {}
var _leave_acknowledged := false
var _last_error_code := ""
var _server_disconnects := 0
var _automated_acceptance := false
var _item_graph_snapshot: Dictionary = {}
var _item_snapshot_updates := 0
var _playable_sandbox := false

func setup(config: Dictionary) -> Dictionary:
	if _configured: return _failure("M3_CLIENT_ALREADY_CONFIGURED")
	_host = String(config.get("host", "127.0.0.1")).strip_edges()
	_port = int(config.get("port", 0))
	_logical_player_id = String(config.get("logical_player_id", "a")).strip_edges().to_lower()
	_result_file = String(config.get("result_file", "")).strip_edges()
	_connect_timeout_ms = int(config.get("connect_timeout_ms", 30000))
	_command_timeout_ms = int(config.get("command_timeout_ms", 8000))
	_automated_acceptance = bool(config.get("automated_acceptance", false))
	_playable_sandbox = bool(config.get("playable_sandbox", false))
	_join_operation_id = ""
	if _host.is_empty() or _port < 1 or _port > 65535 or _logical_player_id.is_empty():
		return _failure("INVALID_M3_CLIENT_CONFIGURATION")
	_replica = Replica.new()
	_boundary = Boundary.new()
	var configured: Dictionary = _boundary.configure(Port.new(), 524288, 32, 1048576)
	if not bool(configured.get("success", false)): return configured
	_transport_session_id = "transport-session/m3/%s/%d/%d" % [_logical_player_id, OS.get_process_id(), Time.get_ticks_msec()]
	var connected: Dictionary = _boundary.connect_client(
		Support.endpoint(_host, _port, false), SERVER_PEER_ID, _transport_session_id,
		"route/m3/server/%s" % _logical_player_id, 1
	)
	if not bool(connected.get("success", false)): return connected
	_started_ms = Time.get_ticks_msec(); _configured = true; set_process(true)
	_write_report("CONNECTING", false)
	return _success()

func _process(_delta: float) -> void:
	if not _configured or _boundary == null: return
	var polled: Dictionary = _boundary.poll_events(128)
	if not bool(polled.get("success", false)):
		_fail_connection(String(polled.get("error_code", "M3_CLIENT_POLL_FAILED"))); return
	if not _join_sent and String(_boundary.get_peer_snapshot(SERVER_PEER_ID).get("state", "")) == "TRANSPORT_CONNECTED":
		if not _mark_peer_ready(): _fail_connection("M3_PEER_READY_FAILED"); return
		_join_operation_id = Support.transport_bound_operation_id(_logical_player_id, "join", _transport_session_id)
		if _join_operation_id.is_empty():
			_fail_connection("INVALID_M3_JOIN_OPERATION_ID")
			return
		if not _send("JOIN", {"logical_player_id": _logical_player_id, "operation_id": _join_operation_id}):
			_fail_connection("M3_JOIN_SEND_FAILED")
			return
		_join_sent = true
	for event_value in polled.get("details", {}).get("events", []):
		if not event_value is Dictionary: continue
		var event: Dictionary = event_value
		if String(event.get("event_type", "")) == "MESSAGE_RECEIVED":
			_messages_received += 1
			_handle_message(event.get("frame", {}).get("payload", {}))
		elif String(event.get("event_type", "")) == "PEER_DISCONNECTED":
			_server_disconnects += 1; _joined = false; _write_report("DISCONNECTED", false); server_disconnected.emit(get_report())
	if not _joined and Time.get_ticks_msec() - _started_ms > _connect_timeout_ms:
		_fail_connection("M3_CLIENT_CONNECT_TIMEOUT")

func _handle_message(payload: Dictionary) -> void:
	match String(payload.get("type", "")):
		"JOIN_ACK": _handle_join_ack(payload)
		"JOIN_REJECTED": _fail_connection(String(payload.get("error_code", "JOIN_REJECTED")), payload)
		"GAMEPLAY_DELTA": _accept_delta(payload.get("delta", {}))
		"GAMEPLAY_SNAPSHOT": _accept_snapshot(payload.get("snapshot", {}))
		"ITEM_GRAPH_SNAPSHOT": _accept_item_snapshot(payload.get("snapshot", {}))
		"COMMAND_RESULT":
			var item_snapshot_value = payload.get("item_graph_snapshot", {})
			if item_snapshot_value is Dictionary and not Dictionary(item_snapshot_value).is_empty():
				_accept_item_snapshot(Dictionary(item_snapshot_value))
			var operation_id := String(payload.get("operation_id", ""))
			if not operation_id.is_empty(): _command_results[operation_id] = payload.duplicate(true)
		"LEAVE_ACK": _leave_acknowledged = true; _joined = false; _write_report("LEFT", true)
		"LEAVE_REJECTED": _last_error_code = String(payload.get("error_code", "LEAVE_REJECTED"))
		_: _last_error_code = "UNKNOWN_M3_SERVER_MESSAGE"

func _handle_join_ack(payload: Dictionary) -> void:
	var player_value = payload.get("player", {})
	if not player_value is Dictionary:
		_fail_connection("INVALID_M3_JOIN_ACK"); return
	var player: Dictionary = player_value
	_player_entity_id = String(player.get("player_entity_id", ""))
	_ownership_epoch = int(player.get("ownership_epoch", 0))
	_input_sequence = maxi(_input_sequence, int(player.get("last_input_sequence", 0)))
	if _player_entity_id != "player/%s" % _logical_player_id or _ownership_epoch < 1:
		_fail_connection("INVALID_M3_JOIN_IDENTITY", {"player": player}); return
	var accepted: Dictionary = _replica.accept_snapshot(payload.get("snapshot", {}))
	if not bool(accepted.get("success", false)):
		_fail_connection(String(accepted.get("error_code", "M3_JOIN_SNAPSHOT_REJECTED"))); return
	_snapshot_updates += 1
	_accept_item_snapshot(payload.get("item_graph_snapshot", {}))
	_joined = true; _last_error_code = ""; _write_report("READY", false)
	replica_updated.emit(_replica.get_snapshot()); session_ready.emit(self)

func _accept_snapshot(snapshot: Dictionary) -> void:
	var accepted: Dictionary = _replica.accept_snapshot(snapshot)
	if not bool(accepted.get("success", false)):
		_last_error_code = String(accepted.get("error_code", "M3_SNAPSHOT_REJECTED")); return
	if not bool(accepted.get("details", {}).get("replay", false)): _snapshot_updates += 1
	replica_updated.emit(_replica.get_snapshot())

func _accept_delta(delta: Dictionary) -> void:
	var accepted: Dictionary = _replica.accept_delta(delta)
	if not bool(accepted.get("success", false)):
		_last_error_code = String(accepted.get("error_code", "M3_DELTA_REJECTED")); return
	if not bool(accepted.get("details", {}).get("replay", false)): _delta_updates += 1
	replica_updated.emit(_replica.get_snapshot())

func move_nonblocking(delta_x: float, delta_z: float) -> Dictionary:
	if not is_ready(): return _failure("M3_CLIENT_NOT_READY")
	_input_sequence += 1
	var operation_id := "operation/m3/%s/move/%d/%d" % [_logical_player_id, OS.get_process_id(), _input_sequence]
	var sent := _send("MOVE", {
		"logical_player_id": _logical_player_id,
		"ownership_epoch": _ownership_epoch,
		"input_sequence": _input_sequence,
		"delta_x": delta_x,
		"delta_z": delta_z,
		"operation_id": operation_id,
	})
	return _success({"operation_id": operation_id, "input_sequence": _input_sequence}) if sent else _failure("M3_MOVE_SEND_FAILED")


func move_blocking(delta_x: float, delta_z: float) -> Dictionary:
	if not is_ready(): return _failure("M3_CLIENT_NOT_READY")
	_input_sequence += 1
	var operation_id := "operation/m3/%s/move/%d/%d" % [_logical_player_id, OS.get_process_id(), _input_sequence]
	_command_results.erase(operation_id)
	if not _send("MOVE", {
		"logical_player_id": _logical_player_id,
		"ownership_epoch": _ownership_epoch,
		"input_sequence": _input_sequence,
		"delta_x": delta_x,
		"delta_z": delta_z,
		"operation_id": operation_id,
	}): return _failure("M3_MOVE_SEND_FAILED")
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= _command_timeout_ms:
		_poll_blocking_once()
		if _command_results.has(operation_id):
			var result: Dictionary = _command_results[operation_id]; _command_results.erase(operation_id)
			if String(result.get("status", "")) != "SUCCEEDED": return _failure(String(result.get("error_code", "M3_MOVE_REJECTED")), result)
			return _success({"operation_id": operation_id, "result": result})
		OS.delay_msec(2)
	return _failure("M3_MOVE_TIMEOUT")


func submit_movement_intent_nonblocking(intent: Dictionary) -> Dictionary:
	if not is_ready():
		return _failure("M7_CLIENT_NOT_READY")
	_input_sequence += 1
	var operation_id := "operation/m7/%s/input/%d/%d" % [_logical_player_id, OS.get_process_id(), _input_sequence]
	var sent := _send("PLAYER_INPUT", {
		"logical_player_id": _logical_player_id,
		"ownership_epoch": _ownership_epoch,
		"input_sequence": _input_sequence,
		"intent": intent.duplicate(true),
		"operation_id": operation_id,
	})
	return _success({"operation_id": operation_id, "input_sequence": _input_sequence}) if sent else _failure("M7_PLAYER_INPUT_SEND_FAILED")

func submit_movement_intent_blocking(intent: Dictionary) -> Dictionary:
	if not is_ready():
		return _failure("M7_CLIENT_NOT_READY")
	_input_sequence += 1
	var operation_id := "operation/m7/%s/input/%d/%d" % [_logical_player_id, OS.get_process_id(), _input_sequence]
	_command_results.erase(operation_id)
	if not _send("PLAYER_INPUT", {
		"logical_player_id": _logical_player_id,
		"ownership_epoch": _ownership_epoch,
		"input_sequence": _input_sequence,
		"intent": intent.duplicate(true),
		"operation_id": operation_id,
	}):
		return _failure("M7_PLAYER_INPUT_SEND_FAILED")
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= _command_timeout_ms:
		_poll_blocking_once()
		if _command_results.has(operation_id):
			var result: Dictionary = _command_results[operation_id]
			_command_results.erase(operation_id)
			if String(result.get("status", "")) != "SUCCEEDED":
				return _failure(String(result.get("error_code", "M7_PLAYER_INPUT_REJECTED")), result)
			return _success({"operation_id": operation_id, "input_sequence": _input_sequence, "result": result})
		OS.delay_msec(2)
	return _failure("M7_PLAYER_INPUT_TIMEOUT")

func submit_player_state_nonblocking(_player_state: Dictionary, _delta_seconds: float) -> Dictionary:
	return _failure("M7_CLIENT_AUTHORITATIVE_STATE_FORBIDDEN")

func submit_player_state_blocking(_player_state: Dictionary, _delta_seconds: float) -> Dictionary:
	return _failure("M7_CLIENT_AUTHORITATIVE_STATE_FORBIDDEN")


func set_presentation_blocking(orientation_yaw: float, flashlight_enabled: bool) -> Dictionary:
	if not is_ready(): return _failure("M3_CLIENT_NOT_READY")
	var operation_id := "operation/m3/%s/presentation/%d/%d" % [_logical_player_id, OS.get_process_id(), Time.get_ticks_msec()]
	_command_results.erase(operation_id)
	if not _send("PRESENTATION", {
		"logical_player_id": _logical_player_id,
		"ownership_epoch": _ownership_epoch,
		"orientation_yaw": orientation_yaw,
		"flashlight_enabled": flashlight_enabled,
		"operation_id": operation_id,
	}): return _failure("M3_PRESENTATION_SEND_FAILED")
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= _command_timeout_ms:
		_poll_blocking_once()
		if _command_results.has(operation_id):
			var result: Dictionary = _command_results[operation_id]; _command_results.erase(operation_id)
			if String(result.get("status", "")) != "SUCCEEDED": return _failure(String(result.get("error_code", "M3_PRESENTATION_REJECTED")), result)
			return _success({"operation_id": operation_id, "result": result})
		OS.delay_msec(2)
	return _failure("M3_PRESENTATION_TIMEOUT")

func _accept_item_snapshot(snapshot: Dictionary) -> void:
	if snapshot.is_empty(): return
	_item_graph_snapshot = snapshot.duplicate(true)
	_item_snapshot_updates += 1
	item_graph_updated.emit(_item_graph_snapshot.duplicate(true))

func execute_item_command_blocking(
	command_type: String,
	payload: Dictionary,
	operation_id: String = "",
	ownership_epoch_override: int = 0
) -> Dictionary:
	if not is_ready(): return _failure("M4_CLIENT_NOT_READY")
	var command_epoch := ownership_epoch_override if ownership_epoch_override > 0 else _ownership_epoch
	var op := operation_id if not operation_id.is_empty() else "operation/m4/%s/%s/%d/%d" % [_logical_player_id, command_type.replace(".", "-"), OS.get_process_id(), Time.get_ticks_msec()]
	_command_results.erase(op)
	if not _send("ITEM_COMMAND", {"logical_player_id":_logical_player_id,"ownership_epoch":command_epoch,"operation_id":op,"command_type":command_type,"payload":payload.duplicate(true)}): return _failure("M4_ITEM_COMMAND_SEND_FAILED")
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= _command_timeout_ms:
		_poll_blocking_once()
		if _command_results.has(op):
			var result: Dictionary = _command_results[op]; _command_results.erase(op)
			if String(result.get("status", "")) != "SUCCEEDED": return _failure(String(result.get("error_code", "M4_ITEM_COMMAND_REJECTED")), result)
			return _success({"operation_id":op,"result":result})
		OS.delay_msec(2)
	return _failure("M4_ITEM_COMMAND_TIMEOUT")

func get_item_graph_snapshot() -> Dictionary: return _item_graph_snapshot.duplicate(true)

func request_graceful_leave(timeout_ms: int = 2500) -> Dictionary:
	if not _joined: return _success({"already_left": true})
	_leave_acknowledged = false
	var operation_id := Support.transport_bound_operation_id(_logical_player_id, "leave", _transport_session_id)
	if operation_id.is_empty():
		return _failure("INVALID_M3_LEAVE_OPERATION_ID")
	_send("LEAVE", {"logical_player_id": _logical_player_id, "operation_id": operation_id})
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= timeout_ms:
		_poll_blocking_once()
		if _leave_acknowledged: return _success({"operation_id": operation_id})
		OS.delay_msec(2)
	return _failure("M3_LEAVE_TIMEOUT")

func _poll_blocking_once() -> void:
	if _boundary == null: return
	var polled: Dictionary = _boundary.poll_events(128)
	if not bool(polled.get("success", false)): return
	for event_value in polled.get("details", {}).get("events", []):
		if event_value is Dictionary and String(event_value.get("event_type", "")) == "MESSAGE_RECEIVED":
			_messages_received += 1; _handle_message(event_value.get("frame", {}).get("payload", {}))

func _send(message_type: String, data: Dictionary) -> bool:
	if _boundary == null: return false
	var payload := data.duplicate(true); payload["type"] = message_type; _message_sequence += 1; payload["client_message_sequence"] = _message_sequence
	var frame_result: Dictionary = _boundary.create_frame_for_peer(SERVER_PEER_ID, "COMMAND", Support.MESSAGE_SCHEMA, payload)
	if not bool(frame_result.get("success", false)): return false
	var sent: Dictionary = _boundary.send_to_peer(SERVER_PEER_ID, frame_result.get("details", {}).get("frame", {}))
	if not bool(sent.get("success", false)): return false
	var flushed: Dictionary = _boundary.flush_outbound(16, SERVER_PEER_ID)
	if not bool(flushed.get("success", false)): return false
	_messages_sent += 1; return true

func _mark_peer_ready() -> bool:
	for method_name in ["mark_peer_handshaking", "mark_peer_synchronizing", "mark_peer_ready"]:
		var result: Dictionary = _boundary.call(method_name, SERVER_PEER_ID)
		if not bool(result.get("success", false)): return false
	return true

func get_player(logical_player_id: String) -> Dictionary:
	return _replica.get_player(logical_player_id) if _replica != null else {}
func get_snapshot() -> Dictionary: return _replica.get_snapshot() if _replica != null else {}
func get_local_player_id() -> String: return _logical_player_id
func get_local_player_record() -> Dictionary: return get_player(_logical_player_id)
func get_remote_player_ids() -> Array[String]:
	var ids: Array[String] = []
	for player in get_snapshot().get("players", []):
		var logical_id := String(player.get("logical_player_id", ""))
		if logical_id != _logical_player_id and bool(player.get("connected", false)): ids.append(logical_id)
	return ids
func is_ready() -> bool: return _joined and _replica != null and not _replica.get_snapshot().is_empty()
func is_automated_acceptance() -> bool: return _automated_acceptance

func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"checkpoint": M7_CHECKPOINT if _playable_sandbox else Support.CHECKPOINT,
		"build_id": M7_BUILD_ID if _playable_sandbox else Support.BUILD_ID,
		"configured": _configured, "joined": _joined, "logical_player_id": _logical_player_id,
		"player_entity_id": _player_entity_id, "ownership_epoch": _ownership_epoch,
		"transport_session_id": _transport_session_id, "join_operation_id": _join_operation_id, "input_sequence": _input_sequence,
		"messages_sent": _messages_sent, "messages_received": _messages_received,
		"snapshot_updates": _snapshot_updates, "delta_updates": _delta_updates,
		"server_disconnects": _server_disconnects, "last_error_code": _last_error_code,
		"display_server": DisplayServer.get_name(), "replica": _replica.get_report() if _replica != null else {},
		"snapshot_checksum": String(get_snapshot().get("checksum", "")),
		"item_graph_checksum": String(_item_graph_snapshot.get("checksum", "")),
		"item_snapshot_updates": _item_snapshot_updates,
		"direct_authority_references": 0, "direct_domain_references": 0,
		"resolved_user_data_dir": OS.get_user_data_dir(),
		"automated_acceptance": _automated_acceptance,
		"playable_sandbox": _playable_sandbox,
	}

func stop() -> Dictionary:
	set_process(false)
	var leave_result := request_graceful_leave(1000) if _joined else _success()
	if _boundary != null: _boundary.stop()
	_boundary = null; _joined = false; _configured = false; _write_report("STOPPED", bool(leave_result.get("success", false)))
	return leave_result

func _fail_connection(error_code: String, details: Dictionary = {}) -> void:
	_last_error_code = error_code; _write_report("FAILED", false, details); connection_failed.emit(error_code, details.duplicate(true)); set_process(false)

func _write_report(state: String, passed: bool, details: Dictionary = {}) -> void:
	if _result_file.is_empty(): return
	var report := get_report(); report["state"] = state; report["passed"] = passed; report["details"] = details.duplicate(true); report["process_id"] = OS.get_process_id()
	Support.write(_result_file, report)

func _exit_tree() -> void:
	if _configured: stop()
func _success(details: Dictionary = {}) -> Dictionary: return {"success": true, "error_code": "", "details": details.duplicate(true)}
func _failure(error_code: String, details: Dictionary = {}) -> Dictionary: return {"success": false, "error_code": error_code, "details": details.duplicate(true)}

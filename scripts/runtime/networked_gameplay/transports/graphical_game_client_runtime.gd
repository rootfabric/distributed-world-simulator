extends Node

signal session_ready(session)
signal connection_failed(error_code: String, details: Dictionary)
signal server_disconnected(report: Dictionary)

const Boundary = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const Port = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
const ClientRuntime = preload("res://scripts/runtime/listen_host/client_runtime.gd")
const PlayableClientSession = preload("res://scripts/runtime/listen_host/playable_client_session.gd")
const ItemBridge = preload("res://scripts/runtime/listen_host/playable_item_command_bridge.gd")
const CommandTransport = preload("res://scripts/runtime/networked_gameplay/transports/enet_command_transport_adapter.gd")
const Support = preload("res://scripts/runtime/networked_gameplay/transports/m2_process_support.gd")

const SCHEMA: String = "planet_simulator.graphical_game_client_runtime.v1"
const SERVER_PEER_ID: String = "peer/enet/m2-dedicated-server"
const PLAYER_ENTITY_ID: String = "player/local-astronaut"
const ITEM_GRAPH_ENTITY_ID: String = "item-graph/player/local-astronaut"

var _boundary
var _client_runtime
var _command_transport
var _item_bridge
var _client_session
var _configured: bool = false
var _joined: bool = false
var _join_sent: bool = false
var _host: String = "127.0.0.1"
var _port: int = 0
var _logical_player_id: String = "local-astronaut"
var _transport_session_id: String = ""
var _gameplay_session_id: String = ""
var _result_file: String = ""
var _connect_timeout_ms: int = 15000
var _command_timeout_ms: int = 5000
var _started_ms: int = 0
var _message_sequence: int = 0
var _ownership_epoch: int = 0
var _player_entity_id: String = ""
var _initial_snapshots: int = 0
var _messages_sent: int = 0
var _messages_received: int = 0
var _commands_sent: int = 0
var _command_results: Dictionary = {}
var _leave_acknowledged: bool = false
var _last_error_code: String = ""
var _server_disconnects: int = 0
var _connection_attempts: int = 0
var _last_connect_attempt_ms: int = 0
var _connect_retry_interval_ms: int = 4000


func setup(config: Dictionary) -> Dictionary:
	if _configured:
		return _failure("GRAPHICAL_GAME_CLIENT_ALREADY_CONFIGURED")
	_host = String(config.get("host", "127.0.0.1")).strip_edges()
	_port = int(config.get("port", 0))
	_logical_player_id = String(config.get("logical_player_id", "local-astronaut")).strip_edges().to_lower()
	_result_file = String(config.get("result_file", "")).strip_edges()
	_connect_timeout_ms = int(config.get("connect_timeout_ms", 15000))
	_command_timeout_ms = int(config.get("command_timeout_ms", 5000))
	if _host.is_empty() or _port < 1 or _port > 65535:
		return _failure("INVALID_GAME_CLIENT_ENDPOINT")
	if _logical_player_id.is_empty() or _connect_timeout_ms < 1000 or _command_timeout_ms < 250:
		return _failure("INVALID_GAME_CLIENT_CONFIGURATION")
	_boundary = Boundary.new()
	var configured: Dictionary = _boundary.configure(Port.new(), 524288, 32, 1048576)
	if not bool(configured.get("success", false)):
		return configured
	_connection_attempts = 1
	_transport_session_id = _create_transport_session_id(_connection_attempts)
	var connected: Dictionary = _boundary.connect_client(
		Support.endpoint(_host, _port, false),
		SERVER_PEER_ID,
		_transport_session_id,
		"route/m2/server/%s" % _logical_player_id,
		1
	)
	if not bool(connected.get("success", false)):
		return connected
	_started_ms = Time.get_ticks_msec()
	_last_connect_attempt_ms = _started_ms
	_configured = true
	set_process(true)
	_write_report("CONNECTING", false)
	return _success({"host": _host, "port": _port})


func _process(_delta: float) -> void:
	if not _configured or _boundary == null:
		return
	_poll_once()
	var peer_state: String = String(_boundary.get_peer_snapshot(SERVER_PEER_ID).get("state", ""))
	if not _join_sent and peer_state == "CONNECTING" and Time.get_ticks_msec() - _last_connect_attempt_ms >= _connect_retry_interval_ms:
		var retried: Dictionary = _retry_connection()
		if not bool(retried.get("success", false)):
			_last_error_code = String(retried.get("error_code", "GAME_CLIENT_RECONNECT_FAILED"))
		return
	if not _join_sent and peer_state == "TRANSPORT_CONNECTED":
		if not _mark_peer_ready():
			_fail_connection("PEER_READY_FAILED")
			return
		_send("JOIN", {
			"logical_player_id": _logical_player_id,
			"operation_id": "operation/m2/%s/join/%d" % [
				_logical_player_id,
				Time.get_ticks_msec(),
			],
		})
		_join_sent = true
	if not _joined and Time.get_ticks_msec() - _started_ms > _connect_timeout_ms:
		_fail_connection("GAME_CLIENT_CONNECT_TIMEOUT")


func _create_transport_session_id(attempt: int) -> String:
	return "transport-session/m2/%s/%d/%d/%d" % [
		_logical_player_id,
		OS.get_process_id(),
		Time.get_ticks_msec(),
		attempt,
	]


func _retry_connection() -> Dictionary:
	if _boundary != null:
		_boundary.stop()
	_boundary = Boundary.new()
	var configured: Dictionary = _boundary.configure(Port.new(), 524288, 32, 1048576)
	if not bool(configured.get("success", false)):
		return configured
	_connection_attempts += 1
	_transport_session_id = _create_transport_session_id(_connection_attempts)
	_join_sent = false
	_last_connect_attempt_ms = Time.get_ticks_msec()
	return _boundary.connect_client(
		Support.endpoint(_host, _port, false),
		SERVER_PEER_ID,
		_transport_session_id,
		"route/m2/server/%s" % _logical_player_id,
		1
	)


func _poll_once() -> Dictionary:
	if _boundary == null:
		return _failure("GAME_CLIENT_BOUNDARY_MISSING")
	var polled: Dictionary = _boundary.poll_events(128)
	if not bool(polled.get("success", false)):
		_last_error_code = String(polled.get("error_code", "GAME_CLIENT_POLL_FAILED"))
		return polled
	for event_value in polled.get("details", {}).get("events", []):
		if not event_value is Dictionary:
			continue
		var event: Dictionary = Dictionary(event_value)
		var event_type: String = String(event.get("event_type", ""))
		if event_type == "MESSAGE_RECEIVED":
			_messages_received += 1
			_handle_message(Dictionary(event.get("frame", {}).get("payload", {})))
		elif event_type == "PEER_DISCONNECTED":
			_server_disconnects += 1
			_joined = false
			_write_report("DISCONNECTED", false)
			server_disconnected.emit(get_report())
	return polled


func _handle_message(payload: Dictionary) -> void:
	match String(payload.get("type", "")):
		"JOIN_ACK":
			_handle_join_ack(payload)
		"JOIN_REJECTED":
			_fail_connection(String(payload.get("error_code", "JOIN_REJECTED")), payload)
		"PLAYABLE_COMMAND_RESULT":
			var operation_id: String = String(payload.get("operation_id", ""))
			if not operation_id.is_empty():
				_command_results[operation_id] = payload.duplicate(true)
		"LEAVE_ACK":
			_leave_acknowledged = true
			_joined = false
			_write_report("LEFT", true)
		"LEAVE_REJECTED":
			_last_error_code = String(payload.get("error_code", "LEAVE_REJECTED"))
		"PROTOCOL_ERROR":
			_last_error_code = String(payload.get("error_code", "PROTOCOL_ERROR"))


func _handle_join_ack(payload: Dictionary) -> void:
	_gameplay_session_id = String(payload.get("gameplay_session_id", "")).strip_edges()
	var player_value = payload.get("player", {})
	var snapshots_value = payload.get("entity_snapshots", [])
	if _gameplay_session_id.is_empty() or not player_value is Dictionary or not snapshots_value is Array:
		_fail_connection("INVALID_JOIN_ACK", payload)
		return
	var player: Dictionary = Dictionary(player_value)
	_player_entity_id = String(player.get("player_entity_id", ""))
	_ownership_epoch = int(player.get("ownership_epoch", 0))
	if _player_entity_id != PLAYER_ENTITY_ID or _ownership_epoch < 1:
		_fail_connection("INVALID_JOINED_PLAYER_IDENTITY", {"player": player})
		return
	_command_transport = CommandTransport.new()
	var transport_setup: Dictionary = _command_transport.setup(self)
	if not bool(transport_setup.get("success", false)):
		_fail_connection(String(transport_setup.get("error_code", "COMMAND_TRANSPORT_SETUP_FAILED")))
		return
	_client_runtime = ClientRuntime.new()
	var runtime_setup: Dictionary = _client_runtime.setup(_command_transport, _gameplay_session_id)
	if not bool(runtime_setup.get("success", false)):
		_fail_connection(String(runtime_setup.get("error_code", "CLIENT_RUNTIME_SETUP_FAILED")))
		return
	_initial_snapshots = 0
	for snapshot_value in Array(snapshots_value):
		if not snapshot_value is Dictionary:
			continue
		var accepted: Dictionary = _client_runtime.accept_snapshot(Dictionary(snapshot_value))
		if not bool(accepted.get("success", false)):
			_fail_connection(String(accepted.get("error_code", "INITIAL_SNAPSHOT_REJECTED")))
			return
		_initial_snapshots += 1
	if _client_runtime.get_snapshot(PLAYER_ENTITY_ID).is_empty() or _client_runtime.get_snapshot(ITEM_GRAPH_ENTITY_ID).is_empty():
		_fail_connection("REQUIRED_INITIAL_REPLICA_MISSING")
		return
	_item_bridge = ItemBridge.new()
	var bridge_setup: Dictionary = _item_bridge.setup(
		_client_runtime,
		ITEM_GRAPH_ENTITY_ID,
		_gameplay_session_id
	)
	if not bool(bridge_setup.get("success", false)):
		_fail_connection(String(bridge_setup.get("error_code", "ITEM_BRIDGE_SETUP_FAILED")))
		return
	_client_session = PlayableClientSession.new()
	var session_setup: Dictionary = _client_session.setup(
		_client_runtime,
		_item_bridge,
		_gameplay_session_id
	)
	if not bool(session_setup.get("success", false)):
		_fail_connection(String(session_setup.get("error_code", "PLAYABLE_SESSION_SETUP_FAILED")))
		return
	_joined = true
	_last_error_code = ""
	_write_report("READY", false)
	session_ready.emit(_client_session)


func send_command_blocking(command: Dictionary) -> Dictionary:
	if not _configured or not _joined or _boundary == null:
		return _failure("GAME_CLIENT_NOT_READY")
	var operation_id: String = String(command.get("operation_id", "")).strip_edges()
	if operation_id.is_empty():
		return _failure("COMMAND_OPERATION_ID_REQUIRED")
	_command_results.erase(operation_id)
	_commands_sent += 1
	if not _send("PLAYABLE_COMMAND", {
		"operation_id": operation_id,
		"command": command.duplicate(true),
	}):
		return _failure("PLAYABLE_COMMAND_SEND_FAILED")
	var started_ms: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_ms <= _command_timeout_ms:
		_poll_once()
		if _command_results.has(operation_id):
			var payload: Dictionary = Dictionary(_command_results[operation_id]).duplicate(true)
			_command_results.erase(operation_id)
			if not bool(payload.get("transport_success", false)):
				return _failure(String(payload.get("error_code", "REMOTE_COMMAND_FAILED")))
			var result_value = payload.get("result", {})
			if not result_value is Dictionary:
				return _failure("INVALID_REMOTE_COMMAND_RESULT")
			_write_report("READY", false)
			return {"success": true, "error_code": "", "result": Dictionary(result_value).duplicate(true)}
		OS.delay_msec(2)
	return _failure("REMOTE_COMMAND_TIMEOUT", {"operation_id": operation_id})


func request_graceful_leave(timeout_ms: int = 2000) -> Dictionary:
	if not _configured or _boundary == null:
		return _success({"already_stopped": true})
	if not _joined:
		return _success({"already_left": true})
	_leave_acknowledged = false
	var operation_id := "operation/m2/%s/leave/%d" % [_logical_player_id, Time.get_ticks_msec()]
	_send("LEAVE", {
		"logical_player_id": _logical_player_id,
		"operation_id": operation_id,
	})
	var started_ms: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_ms <= timeout_ms:
		_poll_once()
		if _leave_acknowledged:
			return _success({"operation_id": operation_id})
		OS.delay_msec(2)
	return _failure("LEAVE_ACK_TIMEOUT", {"operation_id": operation_id})


func get_playable_client_session():
	return _client_session


func get_snapshot(entity_id: String) -> Dictionary:
	return _client_runtime.get_snapshot(entity_id) if _client_runtime != null else {}


func is_ready() -> bool:
	return _joined and _client_session != null


func _send(message_type: String, data: Dictionary) -> bool:
	if _boundary == null:
		return false
	var payload: Dictionary = data.duplicate(true)
	payload["type"] = message_type
	_message_sequence += 1
	payload["client_message_sequence"] = _message_sequence
	var frame_result: Dictionary = _boundary.create_frame_for_peer(
		SERVER_PEER_ID,
		"COMMAND",
		Support.MESSAGE_SCHEMA,
		payload
	)
	if not bool(frame_result.get("success", false)):
		_last_error_code = String(frame_result.get("error_code", "FRAME_CREATE_FAILED"))
		return false
	var sent: Dictionary = _boundary.send_to_peer(
		SERVER_PEER_ID,
		Dictionary(frame_result.get("details", {}).get("frame", {}))
	)
	if not bool(sent.get("success", false)):
		_last_error_code = String(sent.get("error_code", "SEND_FAILED"))
		return false
	var flushed: Dictionary = _boundary.flush_outbound(16, SERVER_PEER_ID)
	if not bool(flushed.get("success", false)):
		_last_error_code = String(flushed.get("error_code", "SEND_FLUSH_FAILED"))
		return false
	if int(flushed.get("details", {}).get("dispatched", 0)) < 1:
		_last_error_code = "SEND_NOT_DISPATCHED"
		return false
	_messages_sent += 1
	return true


func _mark_peer_ready() -> bool:
	for method_name in ["mark_peer_handshaking", "mark_peer_synchronizing", "mark_peer_ready"]:
		var result: Dictionary = _boundary.call(method_name, SERVER_PEER_ID)
		if not bool(result.get("success", false)):
			return false
	return true


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"checkpoint": Support.CHECKPOINT,
		"build_id": Support.BUILD_ID,
		"configured": _configured,
		"joined": _joined,
		"host": _host,
		"port": _port,
		"logical_player_id": _logical_player_id,
		"transport_session_id": _transport_session_id,
		"gameplay_session_id": _gameplay_session_id,
		"player_entity_id": _player_entity_id,
		"ownership_epoch": _ownership_epoch,
		"initial_snapshots": _initial_snapshots,
		"messages_sent": _messages_sent,
		"messages_received": _messages_received,
		"commands_sent": _commands_sent,
		"server_disconnects": _server_disconnects,
		"connection_attempts": _connection_attempts,
		"last_error_code": _last_error_code,
		"display_server": DisplayServer.get_name(),
		"client_runtime": _client_runtime.get_report() if _client_runtime != null else {},
		"command_transport": _command_transport.get_report() if _command_transport != null else {},
		"client_session": _client_session.get_report() if _client_session != null else {},
		"boundary": _boundary.get_snapshot() if _boundary != null else {},
		"direct_authority_references": 0,
		"direct_domain_references": 0,
	}


func stop() -> Dictionary:
	set_process(false)
	var leave_result: Dictionary = request_graceful_leave(1000) if _joined else _success()
	if _boundary != null:
		_boundary.stop()
	if _command_transport != null:
		_command_transport.invalidate()
	if _client_session != null:
		_client_session.invalidate()
	if _item_bridge != null:
		_item_bridge.invalidate()
	_joined = false
	_configured = false
	_write_report("STOPPED", bool(leave_result.get("success", false)))
	_boundary = null
	return leave_result


func _fail_connection(error_code: String, details: Dictionary = {}) -> void:
	if not _configured:
		return
	_last_error_code = error_code
	_write_report("FAILED", false, details)
	connection_failed.emit(error_code, details.duplicate(true))
	set_process(false)


func _write_report(state: String, passed: bool, details: Dictionary = {}) -> void:
	if _result_file.is_empty():
		return
	var report: Dictionary = get_report()
	report["state"] = state
	report["passed"] = passed
	report["details"] = details.duplicate(true)
	report["process_id"] = OS.get_process_id()
	Support.write(_result_file, report)


func _exit_tree() -> void:
	if _configured:
		stop()


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}

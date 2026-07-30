extends Node

signal ready_for_clients(report: Dictionary)
signal client_joined(player: Dictionary)
signal client_left(player: Dictionary)

const Boundary = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const Port = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
const GameplayService = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
const Support = preload("res://scripts/runtime/networked_gameplay/transports/m2_process_support.gd")

const SCHEMA: String = "planet_simulator.dedicated_gameplay_server_runtime.v1"

var _boundary
var _service
var _configured: bool = false
var _world_attached: bool = false
var _host: String = "127.0.0.1"
var _port: int = 0
var _result_file: String = ""
var _authority_owner_id: String = ""
var _authority_epoch: int = 1
var _gameplay_session_id: String = "session/m2/player/local-astronaut"
var _peer_to_player: Dictionary = {}
var _peer_to_session: Dictionary = {}
var _messages_received: int = 0
var _messages_sent: int = 0
var _joins: int = 0
var _leaves: int = 0
var _command_count: int = 0
var _command_rejections: int = 0
var _last_error_code: String = ""
var _last_service_report: Dictionary = {}
var _last_player: Dictionary = {}
var _last_player_snapshot: Dictionary = {}
var _last_item_graph_snapshot: Dictionary = {}
var _last_boundary_snapshot: Dictionary = {}
var _last_command: Dictionary = {}
var _last_command_result: Dictionary = {}


func setup(config: Dictionary) -> Dictionary:
	if _configured:
		return _failure("DEDICATED_GAMEPLAY_SERVER_ALREADY_CONFIGURED")
	_host = String(config.get("host", "127.0.0.1")).strip_edges()
	_port = int(config.get("port", 0))
	_result_file = String(config.get("result_file", "")).strip_edges()
	_authority_owner_id = String(config.get("authority_owner_id", "dedicated-server")).strip_edges()
	_authority_epoch = int(config.get("authority_epoch", 1))
	_gameplay_session_id = String(
		config.get("gameplay_session_id", "session/m2/player/local-astronaut")
	).strip_edges()
	if _host.is_empty() or _port < 1 or _port > 65535:
		return _failure("INVALID_DEDICATED_SERVER_ENDPOINT")
	if _authority_owner_id.is_empty() or _authority_epoch < 1 or _gameplay_session_id.is_empty():
		return _failure("INVALID_DEDICATED_SERVER_IDENTITY")
	_boundary = Boundary.new()
	var configured: Dictionary = _boundary.configure(Port.new(), 524288, 64, 2097152)
	if not bool(configured.get("success", false)):
		return configured
	var started: Dictionary = _boundary.start_server(Support.endpoint(_host, _port, true))
	if not bool(started.get("success", false)):
		return started
	_configured = true
	set_process(true)
	_write_report("LISTENING", false)
	return _success({"host": _host, "port": _port})


func attach_playable_world(config: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("DEDICATED_GAMEPLAY_SERVER_NOT_CONFIGURED")
	if _world_attached:
		return _failure("DEDICATED_PLAYABLE_WORLD_ALREADY_ATTACHED")
	var playable_config: Dictionary = config.duplicate(true)
	playable_config["authority_owner_id"] = _authority_owner_id
	playable_config["authority_epoch"] = _authority_epoch
	playable_config["session_id"] = _gameplay_session_id
	playable_config["topology_adapter"] = "ENET"
	playable_config["region_id"] = "region/m2/single-server"
	_service = GameplayService.new()
	var setup_result: Dictionary = _service.setup_playable(playable_config)
	if not bool(setup_result.get("success", false)):
		_service = null
		_last_error_code = String(setup_result.get("error_code", "PLAYABLE_SERVICE_SETUP_FAILED"))
		_write_report("FAILED", false)
		return setup_result
	_world_attached = true
	_write_report("READY", false)
	ready_for_clients.emit(get_report())
	return _success({
		"service": _service.get_report(),
		"initial_snapshots": _service.create_initial_entity_snapshots(),
	})


func detach_playable_world() -> Dictionary:
	if _service != null:
		_service.shutdown()
	_service = null
	_world_attached = false
	_peer_to_player.clear()
	_peer_to_session.clear()
	_write_report("LISTENING", false)
	return _success()


func _process(_delta: float) -> void:
	if not _configured or _boundary == null:
		return
	var polled: Dictionary = _boundary.poll_events(128)
	if not bool(polled.get("success", false)):
		_last_error_code = String(polled.get("error_code", "SERVER_POLL_FAILED"))
		_write_report("FAILED", false)
		return
	for event_value in polled.get("details", {}).get("events", []):
		if not event_value is Dictionary:
			continue
		var event: Dictionary = Dictionary(event_value)
		var event_type: String = String(event.get("event_type", ""))
		var peer_id: String = String(event.get("peer_id", ""))
		var transport_session_id: String = String(event.get("session_id", ""))
		match event_type:
			"MESSAGE_RECEIVED":
				_messages_received += 1
				_handle_message(
					peer_id,
					transport_session_id,
					Dictionary(event.get("frame", {}).get("payload", {}))
				)
			"PEER_DISCONNECTED":
				_handle_disconnect(peer_id, transport_session_id)


func _handle_message(peer_id: String, transport_session_id: String, payload: Dictionary) -> void:
	match String(payload.get("type", "")):
		"JOIN":
			_handle_join(peer_id, transport_session_id, payload)
		"LEAVE":
			_handle_leave(peer_id, transport_session_id, payload)
		"PLAYABLE_COMMAND":
			_handle_playable_command(peer_id, transport_session_id, payload)
		_:
			_send(peer_id, "PROTOCOL_ERROR", {
				"error_code": "UNKNOWN_M2_MESSAGE_TYPE",
				"operation_id": String(payload.get("operation_id", "")),
			})


func _handle_join(peer_id: String, transport_session_id: String, payload: Dictionary) -> void:
	if not _world_attached or _service == null:
		_send(peer_id, "JOIN_REJECTED", {"error_code": "PLAYABLE_WORLD_NOT_READY"})
		return
	var logical_player_id: String = String(payload.get("logical_player_id", "")).strip_edges().to_lower()
	var operation_id: String = String(payload.get("operation_id", "")).strip_edges()
	if logical_player_id.is_empty() or operation_id.is_empty():
		_send(peer_id, "JOIN_REJECTED", {"error_code": "INVALID_JOIN_PAYLOAD"})
		return
	var result: Dictionary = _service.join(logical_player_id, transport_session_id, operation_id)
	if not bool(result.get("success", false)):
		_send(peer_id, "JOIN_REJECTED", {
			"error_code": String(result.get("error_code", "JOIN_REJECTED")),
			"operation_id": operation_id,
		})
		return
	var player: Dictionary = Dictionary(result.get("details", {}).get("player", {})).duplicate(true)
	_peer_to_player[peer_id] = logical_player_id
	_peer_to_session[peer_id] = transport_session_id
	_joins += 1
	_send(peer_id, "JOIN_ACK", {
		"operation_id": operation_id,
		"logical_player_id": logical_player_id,
		"player": player,
		"gameplay_session_id": _gameplay_session_id,
		"entity_snapshots": _service.create_initial_entity_snapshots(),
		"ownership_snapshot": result.get("details", {}).get("snapshot", {}),
	})
	_write_report("CLIENT_CONNECTED", false)
	client_joined.emit(player)


func _handle_leave(peer_id: String, transport_session_id: String, payload: Dictionary) -> void:
	if _service == null:
		return
	var logical_player_id: String = String(_peer_to_player.get(peer_id, payload.get("logical_player_id", "")))
	var operation_id: String = String(payload.get("operation_id", "operation/m2/leave/%d" % Time.get_ticks_msec()))
	var result: Dictionary = _service.leave(logical_player_id, transport_session_id, operation_id)
	if bool(result.get("success", false)):
		_leaves += 1
		_send(peer_id, "LEAVE_ACK", {
			"operation_id": operation_id,
			"logical_player_id": logical_player_id,
		})
		var player: Dictionary = Dictionary(result.get("details", {}).get("player", {})).duplicate(true)
		client_left.emit(player)
	else:
		_send(peer_id, "LEAVE_REJECTED", {
			"operation_id": operation_id,
			"error_code": String(result.get("error_code", "LEAVE_REJECTED")),
		})
	_peer_to_player.erase(peer_id)
	_peer_to_session.erase(peer_id)
	_write_report("READY", false)


func _handle_disconnect(peer_id: String, transport_session_id: String) -> void:
	if _service != null and not transport_session_id.is_empty():
		var result: Dictionary = _service.leave_transport_session(
			transport_session_id,
			"operation/m2/disconnect/%s" % transport_session_id.sha256_text().left(16)
		)
		if bool(result.get("success", false)) and not bool(result.get("details", {}).get("replay", true)):
			_leaves += 1
	_peer_to_player.erase(peer_id)
	_peer_to_session.erase(peer_id)
	_write_report("READY", false)


func _handle_playable_command(peer_id: String, transport_session_id: String, payload: Dictionary) -> void:
	if _service == null or not _peer_to_player.has(peer_id):
		_send(peer_id, "PLAYABLE_COMMAND_RESULT", {
			"operation_id": String(payload.get("operation_id", "")),
			"transport_success": false,
			"error_code": "CLIENT_NOT_JOINED",
			"result": {},
		})
		return
	if String(_peer_to_session.get(peer_id, "")) != transport_session_id:
		_send(peer_id, "PLAYABLE_COMMAND_RESULT", {
			"operation_id": String(payload.get("operation_id", "")),
			"transport_success": false,
			"error_code": "STALE_TRANSPORT_SESSION",
			"result": {},
		})
		return
	var command_value = payload.get("command", {})
	if not command_value is Dictionary:
		_send(peer_id, "PLAYABLE_COMMAND_RESULT", {
			"operation_id": String(payload.get("operation_id", "")),
			"transport_success": false,
			"error_code": "INVALID_PLAYABLE_COMMAND",
			"result": {},
		})
		return
	_command_count += 1
	_last_command = Dictionary(command_value).duplicate(true)
	var result: Dictionary = _service.handle_network_command(Dictionary(command_value))
	_last_command_result = result.duplicate(true)
	if String(result.get("status", "")) != "SUCCEEDED":
		_command_rejections += 1
	_send(peer_id, "PLAYABLE_COMMAND_RESULT", {
		"operation_id": String(Dictionary(command_value).get("operation_id", "")),
		"transport_success": true,
		"error_code": "",
		"result": result,
	})
	_write_report("CLIENT_CONNECTED", false)


func _send(peer_id: String, message_type: String, data: Dictionary) -> bool:
	if _boundary == null or peer_id.is_empty():
		return false
	if not _ensure_peer_ready(peer_id):
		_last_error_code = "PEER_NOT_READY"
		return false
	var payload: Dictionary = data.duplicate(true)
	payload["type"] = message_type
	var frame_result: Dictionary = _boundary.create_frame_for_peer(
		peer_id,
		"COMMAND",
		Support.MESSAGE_SCHEMA,
		payload
	)
	if not bool(frame_result.get("success", false)):
		_last_error_code = String(frame_result.get("error_code", "FRAME_CREATE_FAILED"))
		return false
	var sent: Dictionary = _boundary.send_to_peer(
		peer_id,
		Dictionary(frame_result.get("details", {}).get("frame", {}))
	)
	if not bool(sent.get("success", false)):
		_last_error_code = String(sent.get("error_code", "SEND_FAILED"))
		return false
	var flushed: Dictionary = _boundary.flush_outbound(16, peer_id)
	if not bool(flushed.get("success", false)):
		_last_error_code = String(flushed.get("error_code", "SEND_FLUSH_FAILED"))
		return false
	if int(flushed.get("details", {}).get("dispatched", 0)) < 1:
		_last_error_code = "SEND_NOT_DISPATCHED"
		return false
	_messages_sent += 1
	return true


func _ensure_peer_ready(peer_id: String) -> bool:
	var state: String = String(_boundary.get_peer_snapshot(peer_id).get("state", ""))
	if state == "READY":
		return true
	for method_name in ["mark_peer_handshaking", "mark_peer_synchronizing", "mark_peer_ready"]:
		var result: Dictionary = _boundary.call(method_name, peer_id)
		if (
			not bool(result.get("success", false))
			and String(result.get("error_code", "")) != "INVALID_PEER_STATE_TRANSITION"
		):
			return false
	return String(_boundary.get_peer_snapshot(peer_id).get("state", "")) == "READY"


func get_world_entity_store_for_kernel():
	return _service.get_world_entity_store_for_kernel() if _service != null else null


func get_service():
	# Server composition root access only. Never handed to graphical clients.
	return _service


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"checkpoint": Support.CHECKPOINT,
		"build_id": Support.BUILD_ID,
		"configured": _configured,
		"world_attached": _world_attached,
		"host": _host,
		"port": _port,
		"authority_owner_id": _authority_owner_id,
		"authority_epoch": _authority_epoch,
		"gameplay_session_id": _gameplay_session_id,
		"connected_peer_count": _peer_to_player.size(),
		"peer_to_player": _peer_to_player.duplicate(true),
		"joins": _joins,
		"leaves": _leaves,
		"command_count": _command_count,
		"command_rejections": _command_rejections,
		"messages_received": _messages_received,
		"messages_sent": _messages_sent,
		"last_error_code": _last_error_code,
		"last_command": _last_command.duplicate(true),
		"last_command_result": _last_command_result.duplicate(true),
		"service": _service.get_report() if _service != null else _last_service_report.duplicate(true),
		"player": _service.get_player("local-astronaut") if _service != null else _last_player.duplicate(true),
		"player_snapshot": (
			_service.create_entity_snapshot("player/local-astronaut")
			if _service != null
			else _last_player_snapshot.duplicate(true)
		),
		"item_graph_snapshot": (
			_service.create_entity_snapshot("item-graph/player/local-astronaut")
			if _service != null
			else _last_item_graph_snapshot.duplicate(true)
		),
		"boundary": _boundary.get_snapshot() if _boundary != null else _last_boundary_snapshot.duplicate(true),
		"direct_client_authority_references": 0,
		"resolved_user_data_dir": OS.get_user_data_dir(),
	}


func stop() -> Dictionary:
	set_process(false)
	_capture_final_state()
	if _boundary != null:
		_boundary.stop()
	if _service != null:
		_service.shutdown()
	_boundary = null
	_service = null
	_write_report("STOPPED", true)
	_configured = false
	_world_attached = false
	return _success()


func _capture_final_state() -> void:
	if _service != null:
		_last_service_report = _service.get_report().duplicate(true)
		_last_player = _service.get_player("local-astronaut").duplicate(true)
		_last_player_snapshot = _service.create_entity_snapshot("player/local-astronaut").duplicate(true)
		_last_item_graph_snapshot = _service.create_entity_snapshot("item-graph/player/local-astronaut").duplicate(true)
	if _boundary != null:
		_last_boundary_snapshot = _boundary.get_snapshot().duplicate(true)


func _write_report(state: String, passed: bool) -> void:
	if _result_file.is_empty():
		return
	var report: Dictionary = get_report()
	report["state"] = state
	report["passed"] = passed
	report["process_id"] = OS.get_process_id()
	Support.write(_result_file, report)


func _exit_tree() -> void:
	if _configured:
		stop()


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}

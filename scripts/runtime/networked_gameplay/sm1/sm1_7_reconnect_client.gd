extends SceneTree

const Support = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")

const OPTION_SPEC := {
	"client-id": {"kind": "string", "default": "", "required": true},
	"host": {"kind": "string", "default": "127.0.0.1"},
	"port": {"kind": "int", "default": 0, "required": true},
	"result-file": {"kind": "string", "default": "", "required": true},
	"timeout-ms": {"kind": "int", "default": 120000},
}

const COMMANDS := [
	{"request_id": "reconnect/request/cross-a-b", "operation_id": "operation/sm1/reconnect/1", "input_sequence": 1, "command_kind": "MOVE", "delta_x": 11.0},
	{"request_id": "reconnect/request/post-resume-action", "operation_id": "operation/sm1/reconnect/2", "input_sequence": 2, "command_kind": "ACTION", "delta_x": 0.0},
	{"request_id": "reconnect/request/cross-b-a", "operation_id": "operation/sm1/reconnect/3", "input_sequence": 3, "command_kind": "MOVE", "delta_x": -11.0},
	{"request_id": "reconnect/request/final", "operation_id": "operation/sm1/graphical/5", "input_sequence": 4, "command_kind": "ACTION", "delta_x": 0.0},
]

var _options: Dictionary = {}
var _boundary = null
var _peer_id := "peer/enet/sm1/gateway"
var _client_id := ""
var _started_ms := 0
var _hello_sent := false
var _start_received := false
var _finished := false
var _command_index := 0
var _command_results := 0
var _connect_count := 0
var _reconnect_count := 0
var _respawn_count := 0
var _connection_generation := 0
var _transport_session_ids: Array[String] = []
var _gateway_endpoint_id := ""
var _epochs: Array = []
var _revisions: Array = []
var _route_history: Array = []
var _last_authority := ""
var _identity_failures: Array[String] = []
var _last_state: Dictionary = {}
var _disconnect_requested := false
var _reconnect_due_ms := -1
var _resume_received := false
var _resume_authority_id := ""
var _resume_epoch := 0
var _resume_revision := 0
var _resume_checksum := ""
var _pre_disconnect_checksum := ""


func _initialize() -> void:
	var parsed: Dictionary = Support.parse_options(OS.get_cmdline_user_args(), OPTION_SPEC)
	if not bool(parsed.get("success", false)):
		_finish_failure("INVALID_OPTIONS", {"errors": parsed.get("errors", [])})
		return
	_options = parsed["options"]
	_client_id = String(_options["client-id"])
	if _client_id not in ["a", "b"]:
		_finish_failure("CLIENT_ID_INVALID", {})
		return
	if DisplayServer.get_name().to_lower() in ["", "headless", "dummy"]:
		_finish_failure("GRAPHICAL_DISPLAY_REQUIRED", {"display_server": DisplayServer.get_name()})
		return
	_started_ms = Time.get_ticks_msec()
	_connect(false)
	Support.write_state(String(_options["result-file"]), "CONNECTING", {
		"client_id": _client_id,
		"display_server": DisplayServer.get_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
	})


func _connect(reconnect: bool) -> void:
	if reconnect:
		_connection_generation += 1
		_reconnect_count += 1
	if _boundary != null:
		_boundary.stop()
	_boundary = Support.make_boundary()
	if _boundary == null:
		_finish_failure("BOUNDARY_CONFIGURE_FAILED", {})
		return
	var session_id := "transport-session/sm1/reconnect-client-%s/%d" % [_client_id, _connection_generation]
	var connected: Dictionary = _boundary.connect_client(
		Support.endpoint(String(_options["host"]), int(_options["port"])),
		_peer_id,
		session_id,
		"route/sm1/reconnect-client-%s/%d" % [_client_id, _connection_generation],
		_connection_generation + 1)
	if not bool(connected.get("success", false)):
		_finish_failure(String(connected.get("error_code", "CONNECT_FAILED")), {})
		return
	_transport_session_ids.append(session_id)
	_connect_count += 1
	_hello_sent = false


func _process(_delta: float) -> bool:
	if _finished:
		return false
	if _reconnect_due_ms > 0 and Time.get_ticks_msec() >= _reconnect_due_ms:
		_reconnect_due_ms = -1
		_connect(true)
	if _boundary != null:
		var polled: Dictionary = _boundary.poll_events(128)
		if not bool(polled.get("success", false)):
			_finish_failure(String(polled.get("error_code", "CLIENT_POLL_FAILED")), {})
			return false
		for raw in polled.get("details", {}).get("events", []):
			var event: Dictionary = Dictionary(raw)
			var event_type := String(event.get("event_type", ""))
			if event_type == "PEER_CONNECTED":
				if not Support.mark_ready(_boundary, _peer_id):
					_finish_failure("GATEWAY_PEER_NOT_READY", {})
					return false
			elif event_type == "PEER_DISCONNECTED" and not _disconnect_requested:
				_finish_failure("UNEXPECTED_GATEWAY_DISCONNECT", {})
				return false
			elif event_type == "MESSAGE_RECEIVED":
				var payload := Support.payload_from_event(event)
				if not payload.is_empty():
					_handle(payload)
		if _boundary == null or _finished:
			return false
		if not _hello_sent and String(_boundary.get_peer_snapshot(_peer_id).get("state", "")) == "READY":
			_send_hello()
		if _boundary != null and not _finished:
			_boundary.flush_outbound(128)
	if Time.get_ticks_msec() - _started_ms > int(_options.get("timeout-ms", 120000)):
		_finish_failure("CLIENT_TIMEOUT", {})
	return false


func _handle(payload: Dictionary) -> void:
	match String(payload.get("type", "")):
		"START":
			_handle_start(payload)
		"RESUME":
			_handle_resume(payload)
		"STATE":
			_handle_state(payload)
		"COMMAND_RESULT":
			_handle_command_result(payload)
		"COMPLETE":
			_finish_success(payload)
		"ERROR":
			_finish_failure(String(payload.get("error_code", "GATEWAY_ERROR")), {"payload": payload})


func _handle_start(payload: Dictionary) -> void:
	if _start_received:
		_finish_failure("DUPLICATE_START", {})
		return
	_start_received = true
	_gateway_endpoint_id = String(payload.get("gateway_endpoint_id", ""))
	if _gateway_endpoint_id != Support.GATEWAY_ENDPOINT_ID:
		_finish_failure("GATEWAY_ENDPOINT_CHANGED", {"gateway_endpoint_id": _gateway_endpoint_id})
		return
	_record_route(String(payload.get("active_authority_id", "")), int(payload.get("authority_epoch", 0)))
	if _client_id == "a":
		_send_next_command()


func _handle_resume(payload: Dictionary) -> void:
	if _client_id != "a" or _resume_received or _reconnect_count != 1:
		_finish_failure("UNEXPECTED_RESUME", {"payload": payload})
		return
	if String(payload.get("client_id", "")) != _client_id:
		_finish_failure("RESUME_CLIENT_ID_DIVERGED", {"payload": payload})
		return
	if String(payload.get("gateway_endpoint_id", "")) != Support.GATEWAY_ENDPOINT_ID or String(payload.get("product_session_id", "")) != Support.PRODUCT_SESSION_ID:
		_finish_failure("RESUME_SESSION_OR_ENDPOINT_DIVERGED", {"payload": payload})
		return
	var state_value = payload.get("shared_state", {})
	if not state_value is Dictionary:
		_finish_failure("RESUME_STATE_REQUIRED", {"payload": payload})
		return
	var state: Dictionary = Dictionary(state_value).duplicate(true)
	_validate_state(state)
	var checksum := Support.checksum(state)
	if checksum != String(payload.get("state_checksum", "")) or checksum != _pre_disconnect_checksum:
		_finish_failure("RESUME_STATE_CHECKSUM_DIVERGED", {"payload": payload, "computed": checksum, "before": _pre_disconnect_checksum})
		return
	_resume_received = true
	_resume_authority_id = String(payload.get("active_authority_id", ""))
	_resume_epoch = int(payload.get("authority_epoch", 0))
	_resume_revision = int(state.get("world_revision", 0))
	_resume_checksum = checksum
	_last_state = state
	_record_state(payload, state)
	_disconnect_requested = false
	_send_next_command()


func _handle_state(payload: Dictionary) -> void:
	if String(payload.get("gateway_endpoint_id", "")) != Support.GATEWAY_ENDPOINT_ID:
		_identity_failures.append("gateway_endpoint")
	var state_value = payload.get("shared_state", {})
	if not state_value is Dictionary:
		_identity_failures.append("shared_state")
		return
	var state: Dictionary = Dictionary(state_value).duplicate(true)
	_validate_state(state)
	_last_state = state
	_record_state(payload, state)


func _validate_state(state: Dictionary) -> void:
	if String(state.get("product_session_id", "")) != Support.PRODUCT_SESSION_ID:
		_identity_failures.append("product_session_id")
	if String(state.get("logical_player_id", "")) != Support.LOGICAL_PLAYER_ID:
		_identity_failures.append("logical_player_id")
	if String(state.get("player_entity_id", "")) != Support.PLAYER_ENTITY_ID:
		_identity_failures.append("player_entity_id")
	if int(state.get("spawn_generation", 0)) != 1:
		_identity_failures.append("spawn_generation")


func _record_state(payload: Dictionary, state: Dictionary) -> void:
	var epoch := int(payload.get("authority_epoch", 0))
	var revision := int(state.get("world_revision", 0))
	if epoch > 0 and not _epochs.has(epoch):
		_epochs.append(epoch)
	if revision > 0 and not _revisions.has(revision):
		_revisions.append(revision)
	_record_route(String(payload.get("active_authority_id", "")), epoch)


func _record_route(authority_id: String, epoch: int) -> void:
	if epoch > 0 and not _epochs.has(epoch):
		_epochs.append(epoch)
	if not authority_id.is_empty() and authority_id != _last_authority:
		_last_authority = authority_id
		_route_history.append(authority_id)


func _handle_command_result(payload: Dictionary) -> void:
	if _client_id != "a":
		_finish_failure("OBSERVER_RECEIVED_COMMAND_RESULT", {})
		return
	if not bool(payload.get("success", false)):
		_finish_failure(String(payload.get("error_code", "COMMAND_REJECTED")), {"payload": payload})
		return
	var expected: Dictionary = Dictionary(COMMANDS[_command_index])
	if String(payload.get("request_id", "")) != String(expected["request_id"]):
		_finish_failure("COMMAND_RESULT_REQUEST_ID_DIVERGED", {"payload": payload})
		return
	_command_results += 1
	_command_index += 1
	if _command_index == 1:
		if not bool(payload.get("handoff_complete", false)) or String(payload.get("active_authority_id", "")) != Support.AUTHORITY_B or int(payload.get("authority_epoch", 0)) != 2:
			_finish_failure("FIRST_HANDOFF_RESULT_INVALID", {"payload": payload})
			return
		_pre_disconnect_checksum = Support.checksum(_last_state)
		_disconnect_after_handoff()
		return
	if _command_index < COMMANDS.size():
		_send_next_command()


func _disconnect_after_handoff() -> void:
	if _boundary == null or _disconnect_requested:
		_finish_failure("DISCONNECT_STATE_INVALID", {})
		return
	_disconnect_requested = true
	_boundary.stop()
	_boundary = null
	_reconnect_due_ms = Time.get_ticks_msec() + 300


func _send_hello() -> void:
	var sent := Support.send(_boundary, _peer_id, {"type": "HELLO", "client_id": _client_id})
	if not bool(sent.get("success", false)):
		_finish_failure(String(sent.get("error_code", "HELLO_SEND_FAILED")), {})
		return
	_hello_sent = true


func _send_next_command() -> void:
	if _client_id != "a" or _command_index >= COMMANDS.size():
		return
	var command: Dictionary = Dictionary(COMMANDS[_command_index])
	var sent := Support.send(_boundary, _peer_id, {
		"type": "EXECUTE",
		"request_id": String(command["request_id"]),
		"operation_id": String(command["operation_id"]),
		"input_sequence": int(command["input_sequence"]),
		"command_kind": String(command["command_kind"]),
		"delta_x": float(command["delta_x"]),
	})
	if not bool(sent.get("success", false)):
		_finish_failure(String(sent.get("error_code", "COMMAND_SEND_FAILED")), {"command_index": _command_index})


func _finish_success(payload: Dictionary) -> void:
	if _finished:
		return
	var expected_epochs := [1, 2, 3]
	var expected_revisions := [1, 2, 3, 4]
	var expected_routes := [Support.AUTHORITY_A, Support.AUTHORITY_B, Support.AUTHORITY_A]
	var passed := _gateway_endpoint_id == Support.GATEWAY_ENDPOINT_ID 		and _identity_failures.is_empty() 		and _epochs == expected_epochs 		and _revisions == expected_revisions 		and _route_history == expected_routes 		and String(payload.get("active_authority_id", "")) == Support.AUTHORITY_A 		and int(payload.get("authority_epoch", 0)) == 3 		and int(payload.get("world_revision", 0)) == 4
	if _client_id == "a":
		passed = passed 			and _connect_count == 2 			and _reconnect_count == 1 			and _respawn_count == 0 			and _transport_session_ids.size() == 2 			and _transport_session_ids[0] != _transport_session_ids[1] 			and _resume_received 			and _resume_authority_id == Support.AUTHORITY_B 			and _resume_epoch == 2 			and _resume_revision == 1 			and not _resume_checksum.is_empty() 			and _command_index == COMMANDS.size() 			and _command_results == COMMANDS.size()
	else:
		passed = passed and _connect_count == 1 and _reconnect_count == 0 and _respawn_count == 0 and _command_index == 0 and _command_results == 0
	var report := {
		"schema": "planet_simulator.sm1_reconnect_client_report.v1",
		"state": "COMPLETE" if passed else "FAILED",
		"passed": passed,
		"process_id": OS.get_process_id(),
		"client_id": _client_id,
		"display_server": DisplayServer.get_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"gateway_endpoint_id": _gateway_endpoint_id,
		"connect_count": _connect_count,
		"reconnect_count": _reconnect_count,
		"respawn_count": _respawn_count,
		"transport_session_ids": _transport_session_ids.duplicate(),
		"logical_player_id": String(_last_state.get("logical_player_id", "")),
		"player_entity_id": String(_last_state.get("player_entity_id", "")),
		"spawn_generation": int(_last_state.get("spawn_generation", 0)),
		"epochs": _epochs.duplicate(),
		"revisions": _revisions.duplicate(),
		"route_history": _route_history.duplicate(),
		"commands_sent": _command_index,
		"command_results": _command_results,
		"resume_received": _resume_received,
		"resume_authority_id": _resume_authority_id,
		"resume_epoch": _resume_epoch,
		"resume_revision": _resume_revision,
		"resume_checksum": _resume_checksum,
		"pre_disconnect_checksum": _pre_disconnect_checksum,
		"identity_failures": _identity_failures.duplicate(),
		"shared_state": _last_state.duplicate(true),
	}
	Support.write_json(String(_options["result-file"]), report)
	_finished = true
	if _boundary != null:
		_boundary.stop()
	print("SM1_7_RECONNECT_CLIENT_COMPLETE id=%s passed=%s" % [_client_id, str(passed)])
	quit(0 if passed else 1)


func _finish_failure(error_code: String, details: Dictionary) -> void:
	if _finished:
		return
	_finished = true
	Support.write_json(String(_options.get("result-file", "")), {
		"schema": "planet_simulator.sm1_reconnect_client_report.v1",
		"state": "FAILED", "passed": false, "process_id": OS.get_process_id(),
		"client_id": _client_id, "failure_code": error_code, "details": details,
		"display_server": DisplayServer.get_name(),
		"connect_count": _connect_count, "reconnect_count": _reconnect_count, "respawn_count": _respawn_count,
		"resume_received": _resume_received,
	})
	if _boundary != null:
		_boundary.stop()
	push_error("SM1.7 reconnect client failed: %s" % error_code)
	quit(1)

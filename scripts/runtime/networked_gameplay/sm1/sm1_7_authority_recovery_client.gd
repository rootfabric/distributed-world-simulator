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
	{"request_id": "authority-recovery/request/cross-a-b", "operation_id": "operation/sm1/authority-recovery/1", "input_sequence": 1, "command_kind": "MOVE", "delta_x": 11.0},
	{"request_id": "authority-recovery/request/post-active-recovery-action", "operation_id": "operation/sm1/authority-recovery/2", "input_sequence": 2, "command_kind": "ACTION", "delta_x": 0.0},
	{"request_id": "authority-recovery/request/cross-b-a", "operation_id": "operation/sm1/authority-recovery/3", "input_sequence": 3, "command_kind": "MOVE", "delta_x": -11.0},
	{"request_id": "authority-recovery/request/final", "operation_id": "operation/sm1/graphical/5", "input_sequence": 4, "command_kind": "ACTION", "delta_x": 0.0},
]

var _options: Dictionary = {}
var _boundary = null
var _peer_id := "peer/enet/sm1/gateway"
var _client_id := ""
var _started_ms := 0
var _finished := false
var _hello_sent := false
var _gateway_endpoint_id := ""
var _connect_count := 0
var _reconnect_count := 0
var _respawn_count := 0
var _command_index := 0
var _command_results := 0
var _last_state: Dictionary = {}
var _epochs: Array[int] = []
var _revisions: Array[int] = []
var _route_history: Array[String] = []
var _last_authority := ""
var _identity_failures: Array[String] = []
var _recovery_pending_events := 0
var _recovery_complete_events := 0
var _standby_recovered := false
var _active_recovered := false


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
	_boundary = Support.make_boundary()
	if _boundary == null:
		_finish_failure("BOUNDARY_CONFIGURE_FAILED", {})
		return
	var connected: Dictionary = _boundary.connect_client(
		Support.endpoint(String(_options["host"]), int(_options["port"])),
		_peer_id,
		"transport-session/sm1/authority-recovery-client-%s" % _client_id,
		"route/sm1/authority-recovery-client-%s" % _client_id,
		1)
	if not bool(connected.get("success", false)):
		_finish_failure(String(connected.get("error_code", "CONNECT_FAILED")), {})
		return
	_started_ms = Time.get_ticks_msec()
	Support.write_state(String(_options["result-file"]), "CONNECTING", {
		"process_id": OS.get_process_id(),
		"client_id": _client_id,
		"display_server": DisplayServer.get_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
	})


func _process(_delta: float) -> bool:
	if _finished or _boundary == null:
		return false
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
			_connect_count += 1
		elif event_type == "PEER_DISCONNECTED":
			_finish_failure("GATEWAY_DISCONNECTED_DURING_AUTHORITY_RECOVERY", {})
			return false
		elif event_type == "MESSAGE_RECEIVED":
			var payload := Support.payload_from_event(event)
			if not payload.is_empty():
				_handle(payload)
	if not _hello_sent and String(_boundary.get_peer_snapshot(_peer_id).get("state", "")) == "READY":
		_send_hello()
	_boundary.flush_outbound(128)
	if Time.get_ticks_msec() - _started_ms > int(_options.get("timeout-ms", 120000)):
		_finish_failure("CLIENT_TIMEOUT", {})
	return false


func _handle(payload: Dictionary) -> void:
	match String(payload.get("type", "")):
		"START":
			_handle_start(payload)
		"STATE":
			_handle_state(payload)
		"COMMAND_RESULT":
			_handle_command_result(payload)
		"AUTHORITY_RECOVERY_PENDING":
			_handle_recovery_pending(payload)
		"AUTHORITY_RECOVERY_COMPLETE":
			_handle_recovery_complete(payload)
		"COMPLETE":
			_finish_success(payload)
		"ERROR":
			_finish_failure(String(payload.get("error_code", "GATEWAY_ERROR")), {"payload": payload})


func _handle_start(payload: Dictionary) -> void:
	_gateway_endpoint_id = String(payload.get("gateway_endpoint_id", ""))
	if _gateway_endpoint_id != Support.GATEWAY_ENDPOINT_ID or String(payload.get("product_session_id", "")) != Support.PRODUCT_SESSION_ID:
		_finish_failure("START_IDENTITY_DIVERGED", {"payload": payload})
		return
	_record_route(String(payload.get("active_authority_id", "")), int(payload.get("authority_epoch", 0)))
	if _client_id == "a":
		_send_next_command()


func _handle_state(payload: Dictionary) -> void:
	if String(payload.get("gateway_endpoint_id", "")) != Support.GATEWAY_ENDPOINT_ID or String(payload.get("product_session_id", "")) != Support.PRODUCT_SESSION_ID:
		_identity_failures.append("gateway_or_session")
	var state_value = payload.get("shared_state", {})
	if not state_value is Dictionary:
		_identity_failures.append("shared_state")
		return
	var state: Dictionary = Dictionary(state_value).duplicate(true)
	_validate_identity(state)
	_last_state = state
	var epoch := int(payload.get("authority_epoch", 0))
	var revision := int(state.get("world_revision", 0))
	if epoch > 0 and not _epochs.has(epoch):
		_epochs.append(epoch)
	if revision > 0 and not _revisions.has(revision):
		_revisions.append(revision)
	_record_route(String(payload.get("active_authority_id", "")), epoch)
	if String(payload.get("active_authority_id", "")) == Support.AUTHORITY_B and epoch == 2 and revision == 1 and not _standby_recovered:
		Support.write_state(String(_options["result-file"]), "WAITING_FOR_STANDBY_FAILURE", {
			"process_id": OS.get_process_id(),
			"client_id": _client_id,
			"active_authority_id": Support.AUTHORITY_B,
			"authority_epoch": 2,
			"world_revision": 1,
			"state_checksum": Support.checksum(state),
		})


func _handle_command_result(payload: Dictionary) -> void:
	if _client_id != "a":
		_finish_failure("OBSERVER_RECEIVED_COMMAND_RESULT", {"payload": payload})
		return
	if not bool(payload.get("success", false)):
		_finish_failure(String(payload.get("error_code", "COMMAND_REJECTED")), {"payload": payload})
		return
	if _command_index >= COMMANDS.size():
		_finish_failure("UNEXPECTED_COMMAND_RESULT", {"payload": payload})
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
	if _command_index < COMMANDS.size():
		_send_next_command()


func _handle_recovery_pending(payload: Dictionary) -> void:
	if String(payload.get("gateway_endpoint_id", "")) != Support.GATEWAY_ENDPOINT_ID:
		_finish_failure("RECOVERY_PENDING_ENDPOINT_DIVERGED", {"payload": payload})
		return
	_recovery_pending_events += 1


func _handle_recovery_complete(payload: Dictionary) -> void:
	if String(payload.get("gateway_endpoint_id", "")) != Support.GATEWAY_ENDPOINT_ID or String(payload.get("product_session_id", "")) != Support.PRODUCT_SESSION_ID:
		_finish_failure("RECOVERY_COMPLETE_IDENTITY_DIVERGED", {"payload": payload})
		return
	if int(payload.get("world_revision", -1)) != int(_last_state.get("world_revision", -2)) or String(payload.get("state_checksum", "")) != Support.checksum(_last_state):
		_finish_failure("RECOVERY_COMPLETE_OBSERVED_STATE_DIVERGED", {"payload": payload})
		return
	var recovered := String(payload.get("recovered_authority_id", ""))
	var restored_active := bool(payload.get("restored_active", false))
	_recovery_complete_events += 1
	if recovered == Support.AUTHORITY_A and not restored_active and not _standby_recovered:
		_standby_recovered = true
		Support.write_state(String(_options["result-file"]), "STANDBY_RECOVERED", {
			"process_id": OS.get_process_id(),
			"client_id": _client_id,
			"recovered_authority_id": recovered,
			"active_authority_id": String(payload.get("active_authority_id", "")),
			"authority_epoch": int(payload.get("authority_epoch", 0)),
			"world_revision": int(payload.get("world_revision", 0)),
		})
		return
	if recovered == Support.AUTHORITY_B and restored_active and _standby_recovered and not _active_recovered:
		_active_recovered = true
		if String(payload.get("active_authority_id", "")) != Support.AUTHORITY_B or int(payload.get("authority_epoch", 0)) != 2:
			_finish_failure("ACTIVE_RECOVERY_TUPLE_DIVERGED", {"payload": payload})
			return
		if _client_id == "a" and _command_index == 1:
			_send_next_command()
		return
	_finish_failure("UNEXPECTED_AUTHORITY_RECOVERY_COMPLETE", {"payload": payload})


func _send_hello() -> void:
	var sent := Support.send(_boundary, _peer_id, {"type": "HELLO", "client_id": _client_id})
	if not bool(sent.get("success", false)):
		_finish_failure(String(sent.get("error_code", "HELLO_SEND_FAILED")), {})
		return
	_hello_sent = true


func _send_next_command() -> void:
	if _client_id != "a" or _command_index >= COMMANDS.size():
		return
	if _command_index == 1 and not _active_recovered:
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


func _validate_identity(state: Dictionary) -> void:
	if String(state.get("product_session_id", "")) != Support.PRODUCT_SESSION_ID:
		_identity_failures.append("product_session_id")
	if String(state.get("logical_player_id", "")) != Support.LOGICAL_PLAYER_ID:
		_identity_failures.append("logical_player_id")
	if String(state.get("player_entity_id", "")) != Support.PLAYER_ENTITY_ID:
		_identity_failures.append("player_entity_id")
	if int(state.get("spawn_generation", 0)) != 1:
		_identity_failures.append("spawn_generation")


func _record_route(authority_id: String, epoch: int) -> void:
	if epoch > 0 and not _epochs.has(epoch):
		_epochs.append(epoch)
	if not authority_id.is_empty() and authority_id != _last_authority:
		_last_authority = authority_id
		_route_history.append(authority_id)


func _finish_success(payload: Dictionary) -> void:
	if _finished:
		return
	var passed := _connect_count == 1 \
		and _reconnect_count == 0 \
		and _respawn_count == 0 \
		and _gateway_endpoint_id == Support.GATEWAY_ENDPOINT_ID \
		and _identity_failures.is_empty() \
		and _standby_recovered \
		and _active_recovered \
		and _recovery_pending_events == 2 \
		and _recovery_complete_events == 2 \
		and _epochs == [1, 2, 3] \
		and _revisions == [1, 2, 3, 4] \
		and _route_history == [Support.AUTHORITY_A, Support.AUTHORITY_B, Support.AUTHORITY_A] \
		and String(payload.get("active_authority_id", "")) == Support.AUTHORITY_A \
		and int(payload.get("authority_epoch", 0)) == 3 \
		and int(payload.get("world_revision", 0)) == 4
	if _client_id == "a":
		passed = passed and _command_index == COMMANDS.size() and _command_results == COMMANDS.size()
	else:
		passed = passed and _command_index == 0 and _command_results == 0
	var report := {
		"schema": "planet_simulator.sm1_authority_recovery_client_report.v1",
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
		"recovery_pending_events": _recovery_pending_events,
		"recovery_complete_events": _recovery_complete_events,
		"standby_recovered": _standby_recovered,
		"active_recovered": _active_recovered,
		"logical_player_id": String(_last_state.get("logical_player_id", "")),
		"player_entity_id": String(_last_state.get("player_entity_id", "")),
		"spawn_generation": int(_last_state.get("spawn_generation", 0)),
		"epochs": _epochs.duplicate(),
		"revisions": _revisions.duplicate(),
		"route_history": _route_history.duplicate(),
		"commands_sent": _command_index,
		"command_results": _command_results,
		"shared_state": _last_state.duplicate(true),
	}
	Support.write_json(String(_options["result-file"]), report)
	_finished = true
	_boundary.stop()
	print("SM1_7_AUTHORITY_RECOVERY_CLIENT_COMPLETE id=%s passed=%s" % [_client_id, str(passed)])
	quit(0 if passed else 1)


func _finish_failure(error_code: String, details: Dictionary) -> void:
	if _finished:
		return
	_finished = true
	Support.write_json(String(_options.get("result-file", "")), {
		"schema": "planet_simulator.sm1_authority_recovery_client_report.v1",
		"state": "FAILED", "passed": false, "process_id": OS.get_process_id(),
		"client_id": _client_id, "failure_code": error_code, "details": details,
		"connect_count": _connect_count, "reconnect_count": _reconnect_count, "respawn_count": _respawn_count,
	})
	if _boundary != null:
		_boundary.stop()
	push_error("SM1.7 Authority recovery client failed: %s" % error_code)
	quit(1)

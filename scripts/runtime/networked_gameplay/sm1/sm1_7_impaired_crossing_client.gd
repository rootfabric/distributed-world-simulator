extends SceneTree

const Support = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")

const OPTION_SPEC := {
	"client-id": {"kind": "string", "default": "", "required": true},
	"host": {"kind": "string", "default": "127.0.0.1"},
	"port": {"kind": "int", "default": 0, "required": true},
	"result-file": {"kind": "string", "default": "", "required": true},
	"timeout-ms": {"kind": "int", "default": 180000},
}

const CROSSINGS := 8

var _options: Dictionary = {}
var _boundary = null
var _peer_id := "peer/enet/sm1/gateway"
var _client_id := ""
var _started_ms := 0
var _finished := false
var _hello_sent := false
var _start_received := false
var _connect_count := 0
var _reconnect_count := 0
var _respawn_count := 0
var _gateway_endpoint_id := ""
var _command_index := 0
var _command_results := 0
var _state_updates := 0
var _epochs: Array[int] = []
var _revisions: Array[int] = []
var _route_history: Array[String] = []
var _last_authority := ""
var _last_state: Dictionary = {}
var _identity_failures: Array[String] = []


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
		"transport-session/sm1/impaired-%s" % _client_id,
		"route/sm1/impaired-%s" % _client_id,
		1)
	if not bool(connected.get("success", false)):
		_finish_failure(String(connected.get("error_code", "CONNECT_FAILED")), {})
		return
	_started_ms = Time.get_ticks_msec()
	Support.write_state(String(_options["result-file"]), "CONNECTING", {
		"client_id": _client_id,
		"display_server": DisplayServer.get_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
	})


func _process(_delta: float) -> bool:
	if _finished or _boundary == null:
		return false
	var polled: Dictionary = _boundary.poll_events(256)
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
		elif event_type == "PEER_DISCONNECTED" and not _finished:
			_finish_failure("GATEWAY_DISCONNECTED_BEFORE_COMPLETE", {})
			return false
		elif event_type == "MESSAGE_RECEIVED":
			var payload := Support.payload_from_event(event)
			if not payload.is_empty():
				_handle(payload)
	if not _hello_sent and String(_boundary.get_peer_snapshot(_peer_id).get("state", "")) == "READY":
		_send_hello()
	_boundary.flush_outbound(256)
	if Time.get_ticks_msec() - _started_ms > int(_options.get("timeout-ms", 180000)):
		_finish_failure("CLIENT_TIMEOUT", {"command_index": _command_index, "state_updates": _state_updates})
	return false


func _handle(payload: Dictionary) -> void:
	match String(payload.get("type", "")):
		"START":
			_handle_start(payload)
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
		_send_next()


func _handle_state(payload: Dictionary) -> void:
	if String(payload.get("gateway_endpoint_id", "")) != Support.GATEWAY_ENDPOINT_ID:
		_identity_failures.append("gateway_endpoint")
	var state_value = payload.get("shared_state", {})
	if not state_value is Dictionary:
		_identity_failures.append("shared_state")
		return
	var state: Dictionary = Dictionary(state_value).duplicate(true)
	if String(state.get("product_session_id", "")) != Support.PRODUCT_SESSION_ID:
		_identity_failures.append("product_session_id")
	if String(state.get("logical_player_id", "")) != Support.LOGICAL_PLAYER_ID:
		_identity_failures.append("logical_player_id")
	if String(state.get("player_entity_id", "")) != Support.PLAYER_ENTITY_ID:
		_identity_failures.append("player_entity_id")
	if int(state.get("spawn_generation", 0)) != 1:
		_identity_failures.append("spawn_generation")
	var checksum := Support.checksum(state)
	if checksum != String(payload.get("state_checksum", "")):
		_identity_failures.append("state_checksum")
	_last_state = state
	_state_updates += 1
	var revision := int(state.get("world_revision", 0))
	if not _revisions.has(revision):
		_revisions.append(revision)
	_record_route(String(payload.get("active_authority_id", "")), int(payload.get("authority_epoch", 0)))


func _handle_command_result(payload: Dictionary) -> void:
	if _client_id != "a":
		_finish_failure("OBSERVER_RECEIVED_COMMAND_RESULT", {"payload": payload})
		return
	if not bool(payload.get("success", false)):
		_finish_failure(String(payload.get("error_code", "COMMAND_REJECTED")), {"payload": payload})
		return
	var expected_request := _request_id(_command_index)
	if String(payload.get("request_id", "")) != expected_request:
		_finish_failure("COMMAND_RESULT_CORRELATION_FAILED", {"expected": expected_request, "payload": payload})
		return
	_command_results += 1
	if _command_index < CROSSINGS:
		var expected_authority := Support.AUTHORITY_B if _command_index % 2 == 0 else Support.AUTHORITY_A
		var expected_epoch := _command_index + 2
		if not bool(payload.get("handoff_complete", false)) \
				or String(payload.get("active_authority_id", "")) != expected_authority \
				or int(payload.get("authority_epoch", 0)) != expected_epoch:
			_finish_failure("CROSSING_RESULT_INVALID", {"index": _command_index, "payload": payload})
			return
	else:
		if bool(payload.get("handoff_complete", true)) \
				or String(payload.get("active_authority_id", "")) != Support.AUTHORITY_A \
				or int(payload.get("authority_epoch", 0)) != CROSSINGS + 1:
			_finish_failure("FINAL_RESULT_INVALID", {"payload": payload})
			return
	_command_index += 1
	if _command_index <= CROSSINGS:
		_send_next()


func _send_next() -> void:
	var crossing := _command_index < CROSSINGS
	var delta := 11.0 if _command_index % 2 == 0 else -11.0
	var payload := {
		"type": "EXECUTE",
		"request_id": _request_id(_command_index),
		"operation_id": _operation_id(_command_index),
		"input_sequence": _command_index + 1,
		"command_kind": "MOVE" if crossing else "ACTION",
		"delta_x": delta if crossing else 0.0,
	}
	var sent := Support.send(_boundary, _peer_id, payload)
	if not bool(sent.get("success", false)):
		_finish_failure(String(sent.get("error_code", "COMMAND_SEND_FAILED")), {"command_index": _command_index})


func _request_id(index: int) -> String:
	return "impaired/request/%02d" % (index + 1)


func _operation_id(index: int) -> String:
	if index == CROSSINGS:
		return "operation/sm1/graphical/5"
	return "operation/sm1/impaired/%02d" % (index + 1)


func _send_hello() -> void:
	var sent := Support.send(_boundary, _peer_id, {"type": "HELLO", "client_id": _client_id})
	if not bool(sent.get("success", false)):
		_finish_failure(String(sent.get("error_code", "HELLO_SEND_FAILED")), {})
		return
	_hello_sent = true


func _record_route(authority_id: String, epoch: int) -> void:
	if epoch > 0 and not _epochs.has(epoch):
		_epochs.append(epoch)
	if not authority_id.is_empty() and authority_id != _last_authority:
		_last_authority = authority_id
		_route_history.append(authority_id)


func _finish_success(payload: Dictionary) -> void:
	if _finished:
		return
	var expected_epochs: Array[int] = []
	var expected_revisions: Array[int] = []
	var expected_routes: Array[String] = []
	for value in range(1, CROSSINGS + 2):
		expected_epochs.append(value)
	for value in range(1, CROSSINGS + 2):
		expected_revisions.append(value)
	for index in range(CROSSINGS + 1):
		expected_routes.append(Support.AUTHORITY_A if index % 2 == 0 else Support.AUTHORITY_B)
	var passed := _connect_count == 1 \
		and _reconnect_count == 0 \
		and _respawn_count == 0 \
		and _gateway_endpoint_id == Support.GATEWAY_ENDPOINT_ID \
		and _identity_failures.is_empty() \
		and _epochs == expected_epochs \
		and _revisions == expected_revisions \
		and _route_history == expected_routes \
		and String(payload.get("active_authority_id", "")) == Support.AUTHORITY_A \
		and int(payload.get("authority_epoch", 0)) == CROSSINGS + 1 \
		and int(payload.get("world_revision", 0)) == CROSSINGS + 1
	if _client_id == "a":
		passed = passed and _command_index == CROSSINGS + 1 and _command_results == CROSSINGS + 1
	else:
		passed = passed and _command_index == 0 and _command_results == 0
	var report := {
		"schema": "planet_simulator.sm1_impaired_crossing_client_report.v1",
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
		"state_updates": _state_updates,
		"command_results": _command_results,
		"logical_player_id": String(_last_state.get("logical_player_id", "")),
		"player_entity_id": String(_last_state.get("player_entity_id", "")),
		"spawn_generation": int(_last_state.get("spawn_generation", 0)),
		"epochs": _epochs.duplicate(),
		"revisions": _revisions.duplicate(),
		"route_history": _route_history.duplicate(),
		"identity_failures": _identity_failures.duplicate(),
		"shared_state": _last_state.duplicate(true),
	}
	Support.write_json(String(_options["result-file"]), report)
	_finished = true
	_boundary.stop()
	print("SM1_7_IMPAIRED_CLIENT_COMPLETE id=%s passed=%s" % [_client_id, str(passed)])
	quit(0 if passed else 1)


func _finish_failure(error_code: String, details: Dictionary) -> void:
	if _finished:
		return
	_finished = true
	Support.write_json(String(_options.get("result-file", "")), {
		"schema": "planet_simulator.sm1_impaired_crossing_client_report.v1",
		"state": "FAILED", "passed": false, "process_id": OS.get_process_id(),
		"client_id": _client_id, "failure_code": error_code, "details": details,
		"connect_count": _connect_count, "reconnect_count": _reconnect_count, "respawn_count": _respawn_count,
		"command_index": _command_index, "state_updates": _state_updates,
	})
	if _boundary != null:
		_boundary.stop()
	push_error("SM1.7 impaired client failed: %s" % error_code)
	quit(1)

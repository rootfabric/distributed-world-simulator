extends SceneTree

const Support = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")

const OPTION_SPEC := {
	"client-id": {"kind": "string", "default": "", "required": true},
	"host": {"kind": "string", "default": "127.0.0.1"},
	"port": {"kind": "int", "default": 0, "required": true},
	"result-file": {"kind": "string", "default": "", "required": true},
	"timeout-ms": {"kind": "int", "default": 120000},
}

const RACE_A := {
	"request_id": "concurrent/request/a-to-b",
	"operation_id": "operation/sm1/concurrent/a-to-b",
	"input_sequence": 1,
	"command_kind": "MOVE",
	"delta_x": 11.0,
}
const RACE_B := {
	"request_id": "concurrent/request/b-to-a",
	"operation_id": "operation/sm1/concurrent/b-to-a",
	"input_sequence": 2,
	"command_kind": "MOVE",
	"delta_x": -11.0,
}
const FINAL := {
	"request_id": "concurrent/request/final",
	"operation_id": "operation/sm1/graphical/5",
	"input_sequence": 3,
	"command_kind": "ACTION",
	"delta_x": 0.0,
}

var _options: Dictionary = {}
var _boundary = null
var _peer_id := "peer/enet/sm1/gateway"
var _client_id := ""
var _started_ms := 0
var _hello_sent := false
var _start_received := false
var _finished := false
var _connect_count := 0
var _reconnect_count := 0
var _respawn_count := 0
var _gateway_endpoint_id := ""
var _epochs: Array = []
var _revisions: Array = []
var _route_history: Array = []
var _last_authority := ""
var _identity_failures: Array[String] = []
var _last_state: Dictionary = {}
var _race_batch_sent := false
var _initial_responses := 0
var _busy_rejections := 0
var _busy_request_ids: Array[String] = []
var _successful_results := 0
var _execute_frames_sent := 0
var _retry_count := 0
var _first_success := false
var _second_busy := false
var _second_success := false
var _final_sent := false
var _final_success := false


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
		"transport-session/sm1/concurrent-client-%s" % _client_id,
		"route/sm1/concurrent-client-%s" % _client_id,
		1)
	if not bool(connected.get("success", false)):
		_finish_failure(String(connected.get("error_code", "CONNECT_FAILED")), {})
		return
	_connect_count = 1
	_started_ms = Time.get_ticks_msec()
	Support.write_state(String(_options["result-file"]), "CONNECTING", {
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
		elif event_type == "PEER_DISCONNECTED" and not _finished:
			_finish_failure("GATEWAY_DISCONNECTED_BEFORE_COMPLETE", {})
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
		# Both crossing intents enter the reliable ordered transport before any
		# response can be observed. Gateway must serialize them fail-closed.
		_send_execute(RACE_A)
		_send_execute(RACE_B)
		_race_batch_sent = true


func _handle_state(payload: Dictionary) -> void:
	if String(payload.get("gateway_endpoint_id", "")) != Support.GATEWAY_ENDPOINT_ID:
		_identity_failures.append("gateway_endpoint")
	var state_value = payload.get("shared_state", {})
	if not state_value is Dictionary:
		_identity_failures.append("shared_state")
		return
	var state: Dictionary = Dictionary(state_value).duplicate(true)
	_last_state = state
	if String(state.get("product_session_id", "")) != Support.PRODUCT_SESSION_ID:
		_identity_failures.append("product_session_id")
	if String(state.get("logical_player_id", "")) != Support.LOGICAL_PLAYER_ID:
		_identity_failures.append("logical_player_id")
	if String(state.get("player_entity_id", "")) != Support.PLAYER_ENTITY_ID:
		_identity_failures.append("player_entity_id")
	if int(state.get("spawn_generation", 0)) != 1:
		_identity_failures.append("spawn_generation")
	var revision := int(state.get("world_revision", 0))
	if not _revisions.has(revision):
		_revisions.append(revision)
	_record_route(String(payload.get("active_authority_id", "")), int(payload.get("authority_epoch", 0)))


func _record_route(authority_id: String, epoch: int) -> void:
	if epoch > 0 and not _epochs.has(epoch):
		_epochs.append(epoch)
	if not authority_id.is_empty() and authority_id != _last_authority:
		_last_authority = authority_id
		_route_history.append(authority_id)


func _handle_command_result(payload: Dictionary) -> void:
	if _client_id != "a":
		_finish_failure("OBSERVER_RECEIVED_COMMAND_RESULT", {"payload": payload})
		return
	_initial_responses += 1
	var request_id := String(payload.get("request_id", ""))
	if not bool(payload.get("success", false)):
		if String(payload.get("error_code", "")) != "SM1_GATEWAY_COMMAND_BUSY":
			_finish_failure(String(payload.get("error_code", "COMMAND_REJECTED")), {"payload": payload})
			return
		_busy_rejections += 1
		_busy_request_ids.append(request_id)
		if request_id != String(RACE_B["request_id"]):
			_finish_failure("BUSY_REQUEST_ID_NOT_SECOND_CROSSING", {"payload": payload})
			return
		_second_busy = true
		_maybe_retry_second()
		return
	_successful_results += 1
	if request_id == String(RACE_A["request_id"]):
		if not bool(payload.get("handoff_complete", false)) or String(payload.get("active_authority_id", "")) != Support.AUTHORITY_B or int(payload.get("authority_epoch", 0)) != 2:
			_finish_failure("FIRST_CROSSING_RESULT_INVALID", {"payload": payload})
			return
		_first_success = true
		_maybe_retry_second()
	elif request_id == String(RACE_B["request_id"]):
		if _retry_count != 1 or not bool(payload.get("handoff_complete", false)) or String(payload.get("active_authority_id", "")) != Support.AUTHORITY_A or int(payload.get("authority_epoch", 0)) != 3:
			_finish_failure("SECOND_CROSSING_RESULT_INVALID", {"payload": payload})
			return
		_second_success = true
		_send_final()
	elif request_id == String(FINAL["request_id"]):
		if bool(payload.get("handoff_complete", true)) or String(payload.get("active_authority_id", "")) != Support.AUTHORITY_A or int(payload.get("authority_epoch", 0)) != 3:
			_finish_failure("FINAL_RESULT_INVALID", {"payload": payload})
			return
		_final_success = true
	else:
		_finish_failure("UNEXPECTED_COMMAND_RESULT", {"payload": payload})


func _maybe_retry_second() -> void:
	if not _first_success or not _second_busy or _retry_count > 0:
		return
	_retry_count = 1
	_send_execute(RACE_B)


func _send_final() -> void:
	if _final_sent:
		return
	_final_sent = true
	_send_execute(FINAL)


func _send_execute(command: Dictionary) -> void:
	var sent := Support.send(_boundary, _peer_id, {
		"type": "EXECUTE",
		"request_id": String(command["request_id"]),
		"operation_id": String(command["operation_id"]),
		"input_sequence": int(command["input_sequence"]),
		"command_kind": String(command["command_kind"]),
		"delta_x": float(command["delta_x"]),
	})
	if not bool(sent.get("success", false)):
		_finish_failure(String(sent.get("error_code", "COMMAND_SEND_FAILED")), {"request_id": String(command["request_id"])})
		return
	_execute_frames_sent += 1


func _send_hello() -> void:
	var sent := Support.send(_boundary, _peer_id, {"type": "HELLO", "client_id": _client_id})
	if not bool(sent.get("success", false)):
		_finish_failure(String(sent.get("error_code", "HELLO_SEND_FAILED")), {})
		return
	_hello_sent = true


func _finish_success(payload: Dictionary) -> void:
	if _finished:
		return
	var expected_epochs := [1, 2, 3]
	var expected_revisions := [1, 2, 3]
	var expected_routes := [Support.AUTHORITY_A, Support.AUTHORITY_B, Support.AUTHORITY_A]
	var passed := _connect_count == 1 \
		and _reconnect_count == 0 \
		and _respawn_count == 0 \
		and _gateway_endpoint_id == Support.GATEWAY_ENDPOINT_ID \
		and _identity_failures.is_empty() \
		and _epochs == expected_epochs \
		and _revisions == expected_revisions \
		and _route_history == expected_routes \
		and String(payload.get("active_authority_id", "")) == Support.AUTHORITY_A \
		and int(payload.get("authority_epoch", 0)) == 3 \
		and int(payload.get("world_revision", 0)) == 3
	if _client_id == "a":
		passed = passed \
			and _race_batch_sent \
			and _busy_rejections == 1 \
			and _busy_request_ids == [String(RACE_B["request_id"])] \
			and _retry_count == 1 \
			and _first_success and _second_success and _final_success \
			and _execute_frames_sent == 4 \
			and _successful_results == 3
	else:
		passed = passed and not _race_batch_sent and _execute_frames_sent == 0 and _successful_results == 0 and _busy_rejections == 0
	var report := {
		"schema": "planet_simulator.sm1_concurrent_client_report.v1",
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
		"logical_player_id": String(_last_state.get("logical_player_id", "")),
		"player_entity_id": String(_last_state.get("player_entity_id", "")),
		"spawn_generation": int(_last_state.get("spawn_generation", 0)),
		"epochs": _epochs.duplicate(),
		"revisions": _revisions.duplicate(),
		"route_history": _route_history.duplicate(),
		"race_batch_sent": _race_batch_sent,
		"initial_responses": _initial_responses,
		"busy_rejections": _busy_rejections,
		"busy_request_ids": _busy_request_ids.duplicate(),
		"retry_count": _retry_count,
		"execute_frames_sent": _execute_frames_sent,
		"successful_results": _successful_results,
		"identity_failures": _identity_failures.duplicate(),
		"shared_state": _last_state.duplicate(true),
	}
	Support.write_json(String(_options["result-file"]), report)
	_finished = true
	_boundary.stop()
	print("SM1_7_CONCURRENT_CLIENT_COMPLETE id=%s passed=%s" % [_client_id, str(passed)])
	quit(0 if passed else 1)


func _finish_failure(error_code: String, details: Dictionary) -> void:
	if _finished:
		return
	_finished = true
	Support.write_json(String(_options.get("result-file", "")), {
		"schema": "planet_simulator.sm1_concurrent_client_report.v1",
		"state": "FAILED", "passed": false, "process_id": OS.get_process_id(),
		"client_id": _client_id, "failure_code": error_code, "details": details,
		"display_server": DisplayServer.get_name(),
		"connect_count": _connect_count, "reconnect_count": _reconnect_count, "respawn_count": _respawn_count,
		"race_batch_sent": _race_batch_sent, "busy_rejections": _busy_rejections, "retry_count": _retry_count,
	})
	if _boundary != null:
		_boundary.stop()
	push_error("SM1.7 concurrent client failed: %s" % error_code)
	quit(1)

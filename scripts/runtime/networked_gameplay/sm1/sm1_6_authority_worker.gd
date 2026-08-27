extends SceneTree

const Support = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")

const OPTION_SPEC := {
	"authority-id": {"kind": "string", "default": "", "required": true},
	"host": {"kind": "string", "default": "127.0.0.1"},
	"port": {"kind": "int", "default": 0, "required": true},
	"initial-active": {"kind": "bool", "default": false},
	"initial-epoch": {"kind": "int", "default": 1},
	"result-file": {"kind": "string", "default": "", "required": true},
	"timeout-ms": {"kind": "int", "default": 120000},
}

var _options: Dictionary = {}
var _boundary = null
var _gateway_peer_id := ""
var _authority_id := ""
var _authority_epoch := 0
var _active := false
var _warm := false
var _state: Dictionary = {}
var _started_ms := 0
var _finished := false
var _counters := {
	"execute_requests": 0,
	"executed": 0,
	"replays": 0,
	"write_rejections": 0,
	"freezes": 0,
	"warm_loads": 0,
	"activations": 0,
	"retires": 0,
	"state_queries": 0,
	"status_queries": 0,
}


func _initialize() -> void:
	var parsed: Dictionary = Support.parse_options(OS.get_cmdline_user_args(), OPTION_SPEC)
	if not bool(parsed.get("success", false)):
		_finish_failure("INVALID_OPTIONS", {"errors": parsed.get("errors", [])})
		return
	_options = parsed["options"]
	_authority_id = String(_options["authority-id"])
	if _authority_id not in [Support.AUTHORITY_A, Support.AUTHORITY_B]:
		_finish_failure("INVALID_AUTHORITY_ID", {})
		return
	_authority_epoch = int(_options["initial-epoch"])
	_active = bool(_options["initial-active"])
	_state = Support.canonical_state() if _active else {}
	_boundary = Support.make_boundary()
	if _boundary == null:
		_finish_failure("BOUNDARY_CONFIGURE_FAILED", {})
		return
	var started: Dictionary = _boundary.start_server(Support.endpoint(String(_options["host"]), int(_options["port"])))
	if not bool(started.get("success", false)):
		_finish_failure(String(started.get("error_code", "AUTHORITY_LISTEN_FAILED")), {})
		return
	_started_ms = Time.get_ticks_msec()
	Support.write_state(String(_options["result-file"]), "LISTENING", {
		"authority_id": _authority_id,
		"authority_epoch": _authority_epoch,
		"active": _active,
		"warm": _warm,
		"port": int(_options["port"]),
	})
	print("SM1_6_AUTHORITY_LISTENING id=%s port=%d active=%s" % [_authority_id, int(_options["port"]), str(_active)])


func _process(_delta: float) -> bool:
	if _finished or _boundary == null:
		return false
	var polled: Dictionary = _boundary.poll_events(128)
	if not bool(polled.get("success", false)):
		_finish_failure(String(polled.get("error_code", "AUTHORITY_POLL_FAILED")), {})
		return false
	for raw in polled.get("details", {}).get("events", []):
		var event: Dictionary = Dictionary(raw)
		if String(event.get("event_type", "")) == "PEER_CONNECTED":
			_gateway_peer_id = String(event.get("peer_id", ""))
			if not Support.mark_ready(_boundary, _gateway_peer_id):
				_finish_failure("AUTHORITY_GATEWAY_PEER_NOT_READY", {})
				return false
		elif String(event.get("event_type", "")) == "MESSAGE_RECEIVED":
			var payload := Support.payload_from_event(event)
			if not payload.is_empty():
				_handle(payload)
	_boundary.flush_outbound(128)
	if Time.get_ticks_msec() - _started_ms > int(_options["timeout-ms"]):
		_finish_failure("AUTHORITY_TIMEOUT", {})
	return false


func _handle(payload: Dictionary) -> void:
	var type := String(payload.get("type", ""))
	var request_id := String(payload.get("request_id", ""))
	match type:
		"EXECUTE":
			_execute(request_id, payload)
		"FREEZE":
			_freeze(request_id, payload)
		"WARM_LOAD":
			_warm_load(request_id, payload)
		"RETIRE":
			_retire(request_id, payload)
		"ACTIVATE":
			_activate(request_id, payload)
		"STATE_QUERY":
			_state_query(request_id, payload)
		"STATUS_QUERY":
			_status_query(request_id)
		"SHUTDOWN":
			_finish_success()
		_:
			_send({"type": "ERROR", "request_id": request_id, "error_code": "UNKNOWN_AUTHORITY_MESSAGE"})


func _execute(request_id: String, payload: Dictionary) -> void:
	_counters["execute_requests"] = int(_counters["execute_requests"]) + 1
	if not _active:
		_counters["write_rejections"] = int(_counters["write_rejections"]) + 1
		_send({"type": "EXECUTE_RESULT", "request_id": request_id, "success": false, "error_code": "SM1_AUTHORITY_NOT_ACTIVE"})
		return
	if int(payload.get("authority_epoch", 0)) != _authority_epoch:
		_counters["write_rejections"] = int(_counters["write_rejections"]) + 1
		_send({"type": "EXECUTE_RESULT", "request_id": request_id, "success": false, "error_code": "SM1_AUTHORITY_EPOCH_MISMATCH"})
		return
	var operation_id := String(payload.get("operation_id", ""))
	var operations: Array = Array(_state.get("operation_ids", []))
	if operations.has(operation_id):
		_counters["replays"] = int(_counters["replays"]) + 1
		_send({"type": "EXECUTE_RESULT", "request_id": request_id, "success": true, "replay": true, "state": _state.duplicate(true), "handoff_target": ""})
		return
	var input_sequence := int(payload.get("input_sequence", -1))
	if input_sequence <= int(_state.get("last_input_sequence", -1)):
		_counters["write_rejections"] = int(_counters["write_rejections"]) + 1
		_send({"type": "EXECUTE_RESULT", "request_id": request_id, "success": false, "error_code": "SM1_INPUT_SEQUENCE_NOT_MONOTONIC"})
		return
	var kind := String(payload.get("command_kind", ""))
	if kind == "ACTION":
		_state["action_count"] = int(_state.get("action_count", 0)) + 1
	elif kind == "MOVE":
		_state["position_x"] = float(_state.get("position_x", 0.0)) + float(payload.get("delta_x", 0.0))
	else:
		_counters["write_rejections"] = int(_counters["write_rejections"]) + 1
		_send({"type": "EXECUTE_RESULT", "request_id": request_id, "success": false, "error_code": "SM1_UNKNOWN_COMMAND_KIND"})
		return
	operations.append(operation_id)
	_state["operation_ids"] = operations
	_state["last_operation_id"] = operation_id
	_state["last_input_sequence"] = input_sequence
	_state["world_revision"] = int(_state.get("world_revision", 0)) + 1
	_counters["executed"] = int(_counters["executed"]) + 1
	var handoff_target := ""
	if kind == "MOVE" and _authority_id == Support.AUTHORITY_A and float(_state.get("position_x", 0.0)) >= 10.0 and _authority_epoch == 1:
		handoff_target = Support.AUTHORITY_B
	elif kind == "MOVE" and _authority_id == Support.AUTHORITY_B and float(_state.get("position_x", 0.0)) <= 0.0:
		handoff_target = Support.AUTHORITY_A
	_send({
		"type": "EXECUTE_RESULT",
		"request_id": request_id,
		"success": true,
		"replay": false,
		"state": _state.duplicate(true),
		"state_checksum": Support.checksum(_state),
		"handoff_target": handoff_target,
	})


func _state_query(request_id: String, payload: Dictionary) -> void:
	_counters["state_queries"] = int(_counters["state_queries"]) + 1
	if not _active:
		_send({"type": "STATE_QUERY_RESULT", "request_id": request_id, "success": false, "error_code": "SM1_AUTHORITY_NOT_ACTIVE"})
		return
	if int(payload.get("authority_epoch", 0)) != _authority_epoch:
		_send({"type": "STATE_QUERY_RESULT", "request_id": request_id, "success": false, "error_code": "SM1_AUTHORITY_EPOCH_MISMATCH"})
		return
	_send({
		"type": "STATE_QUERY_RESULT",
		"request_id": request_id,
		"success": true,
		"authority_id": _authority_id,
		"authority_epoch": _authority_epoch,
		"state": _state.duplicate(true),
		"state_checksum": Support.checksum(_state),
	})


func _status_query(request_id: String) -> void:
	_counters["status_queries"] = int(_counters["status_queries"]) + 1
	_send({
		"type": "STATUS_QUERY_RESULT",
		"request_id": request_id,
		"success": true,
		"authority_id": _authority_id,
		"authority_epoch": _authority_epoch,
		"active": _active,
		"warm": _warm,
		"world_revision": int(_state.get("world_revision", 0)),
		"state_checksum": Support.checksum(_state) if not _state.is_empty() else "",
	})


func _freeze(request_id: String, payload: Dictionary) -> void:
	if not _active or int(payload.get("source_epoch", 0)) != _authority_epoch:
		_send({"type": "FREEZE_RESULT", "request_id": request_id, "success": false, "error_code": "SM1_FREEZE_SOURCE_TUPLE_INVALID"})
		return
	_active = false
	_warm = false
	_counters["freezes"] = int(_counters["freezes"]) + 1
	_send({
		"type": "FREEZE_RESULT",
		"request_id": request_id,
		"success": true,
		"state": _state.duplicate(true),
		"state_checksum": Support.checksum(_state),
		"authority_id": _authority_id,
		"authority_epoch": _authority_epoch,
	})


func _warm_load(request_id: String, payload: Dictionary) -> void:
	if _active:
		_send({"type": "WARM_RESULT", "request_id": request_id, "success": false, "error_code": "SM1_WARM_TARGET_ALREADY_ACTIVE"})
		return
	var incoming = payload.get("state", {})
	if not incoming is Dictionary:
		_send({"type": "WARM_RESULT", "request_id": request_id, "success": false, "error_code": "SM1_WARM_STATE_REQUIRED"})
		return
	var candidate: Dictionary = Dictionary(incoming).duplicate(true)
	if String(candidate.get("logical_player_id", "")) != Support.LOGICAL_PLAYER_ID \
			or String(candidate.get("player_entity_id", "")) != Support.PLAYER_ENTITY_ID \
			or int(candidate.get("spawn_generation", 0)) != 1:
		_send({"type": "WARM_RESULT", "request_id": request_id, "success": false, "error_code": "SM1_WARM_IDENTITY_DIVERGED"})
		return
	_state = candidate
	_warm = true
	_counters["warm_loads"] = int(_counters["warm_loads"]) + 1
	_send({
		"type": "WARM_RESULT",
		"request_id": request_id,
		"success": true,
		"state_checksum": Support.checksum(_state),
		"zero_write": true,
	})


func _retire(request_id: String, _payload: Dictionary) -> void:
	if _active:
		_send({"type": "RETIRE_RESULT", "request_id": request_id, "success": false, "error_code": "SM1_RETIRE_ACTIVE_SOURCE_FORBIDDEN"})
		return
	_counters["retires"] = int(_counters["retires"]) + 1
	_send({"type": "RETIRE_RESULT", "request_id": request_id, "success": true})


func _activate(request_id: String, payload: Dictionary) -> void:
	if _active or not _warm:
		_send({"type": "ACTIVATE_RESULT", "request_id": request_id, "success": false, "error_code": "SM1_TARGET_NOT_WARM"})
		return
	var target_epoch := int(payload.get("target_epoch", 0))
	if target_epoch <= _authority_epoch:
		_send({"type": "ACTIVATE_RESULT", "request_id": request_id, "success": false, "error_code": "SM1_TARGET_EPOCH_NOT_MONOTONIC"})
		return
	_authority_epoch = target_epoch
	_active = true
	_warm = false
	_counters["activations"] = int(_counters["activations"]) + 1
	_send({"type": "ACTIVATE_RESULT", "request_id": request_id, "success": true, "authority_epoch": _authority_epoch, "state_checksum": Support.checksum(_state)})


func _send(payload: Dictionary) -> void:
	if _gateway_peer_id.is_empty():
		return
	var sent: Dictionary = Support.send(_boundary, _gateway_peer_id, payload)
	if not bool(sent.get("success", false)):
		_finish_failure(String(sent.get("error_code", "AUTHORITY_SEND_FAILED")), {"payload_type": String(payload.get("type", ""))})


func _finish_success() -> void:
	if _finished:
		return
	_finished = true
	var report := {
		"schema": "planet_simulator.sm1_graphical_authority_report.v1",
		"state": "COMPLETE",
		"passed": true,
		"process_id": OS.get_process_id(),
		"authority_id": _authority_id,
		"authority_epoch": _authority_epoch,
		"active": _active,
		"warm": _warm,
		"shared_state": _state.duplicate(true),
		"state_checksum": Support.checksum(_state) if not _state.is_empty() else "",
		"counters": _counters.duplicate(true),
		"private_persistence_owner": false,
	}
	Support.write_json(String(_options["result-file"]), report)
	if _boundary != null:
		_boundary.stop()
	print("SM1_6_AUTHORITY_COMPLETE id=%s epoch=%d" % [_authority_id, _authority_epoch])
	quit(0)


func _finish_failure(error_code: String, details: Dictionary) -> void:
	if _finished:
		return
	_finished = true
	Support.write_json(String(_options.get("result-file", "")), {
		"schema": "planet_simulator.sm1_graphical_authority_report.v1",
		"state": "FAILED",
		"passed": false,
		"process_id": OS.get_process_id(),
		"authority_id": _authority_id,
		"failure_code": error_code,
		"details": details,
		"counters": _counters.duplicate(true),
	})
	if _boundary != null:
		_boundary.stop()
	push_error("SM1.6 authority failed: %s" % error_code)
	quit(1)

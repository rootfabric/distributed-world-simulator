extends SceneTree

const Support = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")

const OPTION_SPEC := {
	"client-host": {"kind": "string", "default": "127.0.0.1"},
	"client-port": {"kind": "int", "default": 0, "required": true},
	"authority-a-host": {"kind": "string", "default": "127.0.0.1"},
	"authority-a-port": {"kind": "int", "default": 0, "required": true},
	"authority-b-host": {"kind": "string", "default": "127.0.0.1"},
	"authority-b-port": {"kind": "int", "default": 0, "required": true},
	"result-file": {"kind": "string", "default": "", "required": true},
	"timeout-ms": {"kind": "int", "default": 120000},
}

var _options: Dictionary = {}
var _client_boundary = null
var _authority_boundaries: Dictionary = {}
var _authority_peer_ids := {
	Support.AUTHORITY_A: "peer/enet/sm1/gateway-authority-a",
	Support.AUTHORITY_B: "peer/enet/sm1/gateway-authority-b",
}
var _authority_ready := {Support.AUTHORITY_A: false, Support.AUTHORITY_B: false}
var _client_by_peer: Dictionary = {}
var _peer_by_client: Dictionary = {}
var _started_ms := 0
var _started_clients := false
var _finished := false
var _shutdown_at_ms := -1
var _active_authority_id := Support.AUTHORITY_A
var _authority_epoch := 1
var _pending_command: Dictionary = {}
var _transfer: Dictionary = {}
var _request_serial := 0
var _handoff_count := 0
var _last_world_revision := 0
var _last_state_checksum := ""
var _counters := {
	"client_messages": 0,
	"authority_messages": 0,
	"commands": 0,
	"handoffs": 0,
	"state_broadcasts": 0,
	"route_changes": 0,
}


func _initialize() -> void:
	var parsed: Dictionary = Support.parse_options(OS.get_cmdline_user_args(), OPTION_SPEC)
	if not bool(parsed.get("success", false)):
		_finish_failure("INVALID_OPTIONS", {"errors": parsed.get("errors", [])})
		return
	_options = parsed["options"]
	_client_boundary = Support.make_boundary()
	if _client_boundary == null:
		_finish_failure("CLIENT_BOUNDARY_CONFIGURE_FAILED", {})
		return
	var listening: Dictionary = _client_boundary.start_server(Support.endpoint(String(_options["client-host"]), int(_options["client-port"])))
	if not bool(listening.get("success", false)):
		_finish_failure(String(listening.get("error_code", "GATEWAY_LISTEN_FAILED")), {})
		return
	if not _connect_authority(Support.AUTHORITY_A, String(_options["authority-a-host"]), int(_options["authority-a-port"])):
		return
	if not _connect_authority(Support.AUTHORITY_B, String(_options["authority-b-host"]), int(_options["authority-b-port"])):
		return
	_started_ms = Time.get_ticks_msec()
	Support.write_state(String(_options["result-file"]), "LISTENING", {
		"gateway_endpoint_id": Support.GATEWAY_ENDPOINT_ID,
		"client_port": int(_options["client-port"]),
		"active_authority_id": _active_authority_id,
		"authority_epoch": _authority_epoch,
	})
	print("SM1_6_GATEWAY_LISTENING port=%d" % int(_options["client-port"]))


func _connect_authority(authority_id: String, host: String, port: int) -> bool:
	var boundary = Support.make_boundary()
	if boundary == null:
		_finish_failure("AUTHORITY_BOUNDARY_CONFIGURE_FAILED", {"authority_id": authority_id})
		return false
	var peer_id := String(_authority_peer_ids[authority_id])
	var connected: Dictionary = boundary.connect_client(
		Support.endpoint(host, port), peer_id,
		"transport-session/sm1/gateway/%s" % authority_id.replace("/", "-"),
		"route/sm1/gateway/%s" % authority_id.replace("/", "-"), 1)
	if not bool(connected.get("success", false)):
		_finish_failure(String(connected.get("error_code", "AUTHORITY_CONNECT_FAILED")), {"authority_id": authority_id})
		return false
	_authority_boundaries[authority_id] = boundary
	return true


func _process(_delta: float) -> bool:
	if _finished:
		return false
	_poll_clients()
	_poll_authority(Support.AUTHORITY_A)
	_poll_authority(Support.AUTHORITY_B)
	_flush_all()
	_maybe_start_clients()
	if _shutdown_at_ms > 0 and Time.get_ticks_msec() >= _shutdown_at_ms:
		_finish_success()
		return false
	if Time.get_ticks_msec() - _started_ms > int(_options.get("timeout-ms", 120000)):
		_finish_failure("GATEWAY_TIMEOUT", {"pending_command": _pending_command, "transfer": _transfer})
	return false


func _poll_clients() -> void:
	if _client_boundary == null:
		return
	var polled: Dictionary = _client_boundary.poll_events(128)
	if not bool(polled.get("success", false)):
		_finish_failure(String(polled.get("error_code", "CLIENT_POLL_FAILED")), {})
		return
	for raw in polled.get("details", {}).get("events", []):
		var event: Dictionary = Dictionary(raw)
		var event_type := String(event.get("event_type", ""))
		var peer_id := String(event.get("peer_id", ""))
		if event_type == "PEER_CONNECTED":
			if not Support.mark_ready(_client_boundary, peer_id):
				_finish_failure("CLIENT_PEER_NOT_READY", {"peer_id": peer_id})
				return
		elif event_type == "PEER_DISCONNECTED" and _client_by_peer.has(peer_id) and _shutdown_at_ms < 0:
			_finish_failure("CLIENT_DISCONNECTED_DURING_HANDOFF", {"client_id": String(_client_by_peer[peer_id])})
			return
		elif event_type == "MESSAGE_RECEIVED":
			var payload := Support.payload_from_event(event)
			if not payload.is_empty():
				_counters["client_messages"] = int(_counters["client_messages"]) + 1
				_handle_client(peer_id, payload)


func _poll_authority(authority_id: String) -> void:
	if not _authority_boundaries.has(authority_id):
		return
	var boundary = _authority_boundaries[authority_id]
	var peer_id := String(_authority_peer_ids[authority_id])
	var polled: Dictionary = boundary.poll_events(128)
	if not bool(polled.get("success", false)):
		_finish_failure(String(polled.get("error_code", "AUTHORITY_POLL_FAILED")), {"authority_id": authority_id})
		return
	for raw in polled.get("details", {}).get("events", []):
		var event: Dictionary = Dictionary(raw)
		var event_type := String(event.get("event_type", ""))
		if event_type == "PEER_CONNECTED":
			if not Support.mark_ready(boundary, peer_id):
				_finish_failure("AUTHORITY_PEER_NOT_READY", {"authority_id": authority_id})
				return
			_authority_ready[authority_id] = true
		elif event_type == "PEER_DISCONNECTED" and _shutdown_at_ms < 0:
			_finish_failure("AUTHORITY_DISCONNECTED_DURING_HANDOFF", {"authority_id": authority_id})
			return
		elif event_type == "MESSAGE_RECEIVED":
			var payload := Support.payload_from_event(event)
			if not payload.is_empty():
				_counters["authority_messages"] = int(_counters["authority_messages"]) + 1
				_handle_authority(authority_id, payload)
	if not bool(_authority_ready.get(authority_id, false)) and String(boundary.get_peer_snapshot(peer_id).get("state", "")) == "READY":
		_authority_ready[authority_id] = true


func _handle_client(peer_id: String, payload: Dictionary) -> void:
	var type := String(payload.get("type", ""))
	if type == "HELLO":
		var client_id := String(payload.get("client_id", ""))
		if client_id not in ["a", "b"]:
			_send_client(peer_id, {"type": "ERROR", "error_code": "SM1_CLIENT_ID_INVALID"})
			return
		if _peer_by_client.has(client_id) and String(_peer_by_client[client_id]) != peer_id:
			_finish_failure("CLIENT_RECONNECTED_OR_REBOUND", {"client_id": client_id})
			return
		_client_by_peer[peer_id] = client_id
		_peer_by_client[client_id] = peer_id
		_maybe_start_clients()
		return
	if type != "EXECUTE":
		_send_client(peer_id, {"type": "ERROR", "error_code": "SM1_CLIENT_MESSAGE_UNKNOWN"})
		return
	if String(_client_by_peer.get(peer_id, "")) != "a":
		_send_client(peer_id, {"type": "COMMAND_RESULT", "success": false, "error_code": "SM1_OBSERVER_CANNOT_WRITE"})
		return
	if not _started_clients or not _pending_command.is_empty() or not _transfer.is_empty():
		_send_client(peer_id, {"type": "COMMAND_RESULT", "success": false, "error_code": "SM1_GATEWAY_COMMAND_BUSY"})
		return
	_request_serial += 1
	var gateway_request_id := "sm1/gateway/execute/%d" % _request_serial
	_pending_command = {
		"gateway_request_id": gateway_request_id,
		"client_peer_id": peer_id,
		"client_request_id": String(payload.get("request_id", "")),
		"operation_id": String(payload.get("operation_id", "")),
	}
	_counters["commands"] = int(_counters["commands"]) + 1
	_send_authority(_active_authority_id, {
		"type": "EXECUTE",
		"request_id": gateway_request_id,
		"authority_epoch": _authority_epoch,
		"operation_id": String(payload.get("operation_id", "")),
		"input_sequence": int(payload.get("input_sequence", 0)),
		"command_kind": String(payload.get("command_kind", "")),
		"delta_x": float(payload.get("delta_x", 0.0)),
	})


func _handle_authority(authority_id: String, payload: Dictionary) -> void:
	var type := String(payload.get("type", ""))
	match type:
		"EXECUTE_RESULT":
			_handle_execute_result(authority_id, payload)
		"FREEZE_RESULT":
			_handle_freeze_result(authority_id, payload)
		"WARM_RESULT":
			_handle_warm_result(authority_id, payload)
		"RETIRE_RESULT":
			_handle_retire_result(authority_id, payload)
		"ACTIVATE_RESULT":
			_handle_activate_result(authority_id, payload)
		"ERROR":
			_finish_failure(String(payload.get("error_code", "AUTHORITY_ERROR")), {"authority_id": authority_id})


func _handle_execute_result(authority_id: String, payload: Dictionary) -> void:
	if _pending_command.is_empty() or authority_id != _active_authority_id or String(payload.get("request_id", "")) != String(_pending_command.get("gateway_request_id", "")):
		_finish_failure("EXECUTE_RESULT_CORRELATION_FAILED", {"authority_id": authority_id, "payload": payload})
		return
	if not bool(payload.get("success", false)):
		_send_client(String(_pending_command["client_peer_id"]), {
			"type": "COMMAND_RESULT", "request_id": String(_pending_command["client_request_id"]),
			"success": false, "error_code": String(payload.get("error_code", "SM1_EXECUTE_REJECTED")),
		})
		_pending_command = {}
		return
	var state_value = payload.get("state", {})
	if not state_value is Dictionary:
		_finish_failure("EXECUTE_STATE_REQUIRED", {})
		return
	var state: Dictionary = Dictionary(state_value).duplicate(true)
	if not _validate_identity(state):
		_finish_failure("EXECUTE_IDENTITY_DIVERGED", {"state": state})
		return
	var target := String(payload.get("handoff_target", ""))
	if target.is_empty():
		_complete_command(state, false)
		return
	if target == _active_authority_id or target not in [Support.AUTHORITY_A, Support.AUTHORITY_B]:
		_finish_failure("HANDOFF_TARGET_INVALID", {"target": target})
		return
	_request_serial += 1
	_transfer = {
		"transfer_id": "transfer/sm1/graphical/%d" % _request_serial,
		"source": _active_authority_id,
		"target": target,
		"source_epoch": _authority_epoch,
		"target_epoch": _authority_epoch + 1,
		"state": state,
		"state_checksum": Support.checksum(state),
	}
	_send_authority(_active_authority_id, {
		"type": "FREEZE", "request_id": String(_transfer["transfer_id"]) + "/freeze",
		"source_epoch": _authority_epoch,
	})


func _handle_freeze_result(authority_id: String, payload: Dictionary) -> void:
	if not _transfer_matches(authority_id, "source", payload, "/freeze") or not bool(payload.get("success", false)):
		_finish_failure("FREEZE_RESULT_INVALID", {"authority_id": authority_id, "payload": payload})
		return
	if String(payload.get("state_checksum", "")) != String(_transfer.get("state_checksum", "")):
		_finish_failure("FREEZE_STATE_CHANGED", {})
		return
	_send_authority(String(_transfer["target"]), {
		"type": "WARM_LOAD", "request_id": String(_transfer["transfer_id"]) + "/warm",
		"state": Dictionary(_transfer["state"]).duplicate(true),
	})


func _handle_warm_result(authority_id: String, payload: Dictionary) -> void:
	if not _transfer_matches(authority_id, "target", payload, "/warm") or not bool(payload.get("success", false)) or not bool(payload.get("zero_write", false)):
		_finish_failure("WARM_RESULT_INVALID", {"authority_id": authority_id, "payload": payload})
		return
	if String(payload.get("state_checksum", "")) != String(_transfer.get("state_checksum", "")):
		_finish_failure("WARM_STATE_CHANGED", {})
		return
	_send_authority(String(_transfer["source"]), {
		"type": "RETIRE", "request_id": String(_transfer["transfer_id"]) + "/retire",
	})


func _handle_retire_result(authority_id: String, payload: Dictionary) -> void:
	if not _transfer_matches(authority_id, "source", payload, "/retire") or not bool(payload.get("success", false)):
		_finish_failure("RETIRE_RESULT_INVALID", {"authority_id": authority_id, "payload": payload})
		return
	_send_authority(String(_transfer["target"]), {
		"type": "ACTIVATE", "request_id": String(_transfer["transfer_id"]) + "/activate",
		"target_epoch": int(_transfer["target_epoch"]),
	})


func _handle_activate_result(authority_id: String, payload: Dictionary) -> void:
	if not _transfer_matches(authority_id, "target", payload, "/activate") or not bool(payload.get("success", false)):
		_finish_failure("ACTIVATE_RESULT_INVALID", {"authority_id": authority_id, "payload": payload})
		return
	if int(payload.get("authority_epoch", 0)) != int(_transfer.get("target_epoch", 0)):
		_finish_failure("ACTIVATION_EPOCH_DIVERGED", {})
		return
	_active_authority_id = String(_transfer["target"])
	_authority_epoch = int(_transfer["target_epoch"])
	_handoff_count += 1
	_counters["handoffs"] = _handoff_count
	_counters["route_changes"] = int(_counters["route_changes"]) + 1
	var state: Dictionary = Dictionary(_transfer["state"]).duplicate(true)
	_transfer.clear()
	_complete_command(state, true)


func _complete_command(state: Dictionary, handoff_complete: bool) -> void:
	_last_world_revision = int(state.get("world_revision", 0))
	_last_state_checksum = Support.checksum(state)
	_broadcast_state(state)
	var peer_id := String(_pending_command.get("client_peer_id", ""))
	var operation_id := String(_pending_command.get("operation_id", ""))
	_send_client(peer_id, {
		"type": "COMMAND_RESULT",
		"request_id": String(_pending_command.get("client_request_id", "")),
		"success": true,
		"handoff_complete": handoff_complete,
		"active_authority_id": _active_authority_id,
		"authority_epoch": _authority_epoch,
		"world_revision": _last_world_revision,
	})
	_pending_command.clear()
	if operation_id == "operation/sm1/graphical/5":
		_begin_shutdown()


func _broadcast_state(state: Dictionary) -> void:
	for peer_value in _client_by_peer.keys():
		_send_client(String(peer_value), {
			"type": "STATE",
			"gateway_endpoint_id": Support.GATEWAY_ENDPOINT_ID,
			"product_session_id": Support.PRODUCT_SESSION_ID,
			"active_authority_id": _active_authority_id,
			"authority_epoch": _authority_epoch,
			"shared_state": state.duplicate(true),
			"state_checksum": Support.checksum(state),
		})
	_counters["state_broadcasts"] = int(_counters["state_broadcasts"]) + 1


func _maybe_start_clients() -> void:
	if _started_clients or _peer_by_client.size() != 2:
		return
	if not bool(_authority_ready.get(Support.AUTHORITY_A, false)) or not bool(_authority_ready.get(Support.AUTHORITY_B, false)):
		return
	_started_clients = true
	for peer_value in _client_by_peer.keys():
		_send_client(String(peer_value), {
			"type": "START",
			"gateway_endpoint_id": Support.GATEWAY_ENDPOINT_ID,
			"product_session_id": Support.PRODUCT_SESSION_ID,
			"active_authority_id": _active_authority_id,
			"authority_epoch": _authority_epoch,
		})


func _begin_shutdown() -> void:
	for peer_value in _client_by_peer.keys():
		_send_client(String(peer_value), {
			"type": "COMPLETE",
			"gateway_endpoint_id": Support.GATEWAY_ENDPOINT_ID,
			"active_authority_id": _active_authority_id,
			"authority_epoch": _authority_epoch,
			"world_revision": _last_world_revision,
		})
	_send_authority(Support.AUTHORITY_A, {"type": "SHUTDOWN", "request_id": "shutdown/a"})
	_send_authority(Support.AUTHORITY_B, {"type": "SHUTDOWN", "request_id": "shutdown/b"})
	_flush_all()
	_shutdown_at_ms = Time.get_ticks_msec() + 1000


func _send_client(peer_id: String, payload: Dictionary) -> void:
	if peer_id.is_empty() or _client_boundary == null:
		return
	var sent := Support.send(_client_boundary, peer_id, payload)
	if not bool(sent.get("success", false)):
		_finish_failure(String(sent.get("error_code", "GATEWAY_CLIENT_SEND_FAILED")), {"peer_id": peer_id, "type": String(payload.get("type", ""))})


func _send_authority(authority_id: String, payload: Dictionary) -> void:
	if not _authority_boundaries.has(authority_id):
		_finish_failure("AUTHORITY_ROUTE_MISSING", {"authority_id": authority_id})
		return
	var sent := Support.send(_authority_boundaries[authority_id], String(_authority_peer_ids[authority_id]), payload)
	if not bool(sent.get("success", false)):
		_finish_failure(String(sent.get("error_code", "GATEWAY_AUTHORITY_SEND_FAILED")), {"authority_id": authority_id, "type": String(payload.get("type", ""))})


func _flush_all() -> void:
	if _client_boundary != null:
		_client_boundary.flush_outbound(256)
	for boundary_value in _authority_boundaries.values():
		boundary_value.flush_outbound(256)


func _transfer_matches(authority_id: String, role: String, payload: Dictionary, suffix: String) -> bool:
	return not _transfer.is_empty() \
		and authority_id == String(_transfer.get(role, "")) \
		and String(payload.get("request_id", "")) == String(_transfer.get("transfer_id", "")) + suffix


func _validate_identity(state: Dictionary) -> bool:
	return String(state.get("product_session_id", "")) == Support.PRODUCT_SESSION_ID \
		and String(state.get("logical_player_id", "")) == Support.LOGICAL_PLAYER_ID \
		and String(state.get("player_entity_id", "")) == Support.PLAYER_ENTITY_ID \
		and int(state.get("spawn_generation", 0)) == 1


func _finish_success() -> void:
	if _finished:
		return
	_finished = true
	var report := {
		"schema": "planet_simulator.sm1_graphical_gateway_report.v1",
		"state": "COMPLETE",
		"passed": true,
		"process_id": OS.get_process_id(),
		"gateway_endpoint_id": Support.GATEWAY_ENDPOINT_ID,
		"client_ids": _peer_by_client.keys(),
		"client_connection_count": _peer_by_client.size(),
		"active_authority_id": _active_authority_id,
		"authority_epoch": _authority_epoch,
		"handoff_count": _handoff_count,
		"last_world_revision": _last_world_revision,
		"last_state_checksum": _last_state_checksum,
		"transfer_payload_retained": not _transfer.is_empty(),
		"canonical_gameplay_owner": false,
		"client_endpoint_changed": false,
		"counters": _counters.duplicate(true),
	}
	Support.write_json(String(_options["result-file"]), report)
	_stop_boundaries()
	print("SM1_6_GATEWAY_COMPLETE epoch=%d handoffs=%d" % [_authority_epoch, _handoff_count])
	quit(0)


func _finish_failure(error_code: String, details: Dictionary) -> void:
	if _finished:
		return
	_finished = true
	Support.write_json(String(_options.get("result-file", "")), {
		"schema": "planet_simulator.sm1_graphical_gateway_report.v1",
		"state": "FAILED", "passed": false, "process_id": OS.get_process_id(),
		"failure_code": error_code, "details": details,
		"active_authority_id": _active_authority_id, "authority_epoch": _authority_epoch,
		"handoff_count": _handoff_count,
	})
	_stop_boundaries()
	push_error("SM1.6 gateway failed: %s" % error_code)
	quit(1)


func _stop_boundaries() -> void:
	if _client_boundary != null:
		_client_boundary.stop()
	for boundary_value in _authority_boundaries.values():
		boundary_value.stop()

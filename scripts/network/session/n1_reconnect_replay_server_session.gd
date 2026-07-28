extends RefCounted

const BoundaryScript = preload("res://scripts/network/transports/network_transport_boundary.gd")
const EnetPortScript = preload("res://scripts/network/transports/enet_transport_port.gd")
const HandshakeServiceScript = preload("res://scripts/network/session/network_handshake_service.gd")
const HandshakeScript = preload("res://scripts/network/contracts/network_handshake_envelope.gd")
const AckScript = preload("res://scripts/network/contracts/snapshot_ack_envelope.gd")
const CommandScript = preload("res://scripts/network/contracts/network_command_envelope.gd")
const ResultScript = preload("res://scripts/network/contracts/network_command_result_envelope.gd")
const ResumeScript = preload("res://scripts/network/contracts/network_session_resume_envelope.gd")
const ResumeResultScript = preload("res://scripts/network/contracts/network_session_resume_result.gd")
const ReplayServiceScript = preload("res://scripts/network/session/network_reconnect_replay_service.gd")
const AuthorityScript = preload("res://scripts/network/session/n1_remote_item_authority.gd")

const STATE_STOPPED := "STOPPED"
const STATE_LISTENING := "LISTENING"
const STATE_SNAPSHOT_SENT := "SNAPSHOT_SENT"
const STATE_COMMAND_READY := "COMMAND_READY"
const STATE_WAITING_RECONNECT := "WAITING_RECONNECT"
const STATE_WAITING_RESUME := "WAITING_RESUME"
const STATE_REPLAY_READY := "REPLAY_READY"
const STATE_WAITING_REPLAY_ACK := "WAITING_REPLAY_ACK"
const STATE_FLUSHING := "FLUSHING"
const STATE_COMPLETE := "COMPLETE"
const STATE_FAILED := "FAILED"
const RESULT_FLUSH_GRACE_MS: int = 400
const SESSION_IDLE_TIMEOUT_MS: int = 6000
const REQUIRED_REPLAY_CYCLES: int = 2

var _boundary
var _port
var _handshake_service
var _authority
var _replay_service
var _endpoint: Dictionary = {}
var _initial_snapshot: Dictionary = {}
var _final_snapshot: Dictionary = {}
var _state: String = STATE_STOPPED
var _failure_code: String = ""
var _peer_id: int = 0
var _client_node_id: String = ""
var _logical_session_id: String = ""
var _transport_session_id: String = ""
var _transport_session_ids: Array[String] = []
var _ticket: Dictionary = {}
var _primary_command: Dictionary = {}
var _primary_result: Dictionary = {}
var _primary_delta: Dictionary = {}
var _events_processed: int = 0
var _messages_sent: int = 0
var _messages_received: int = 0
var _handshake_count: int = 0
var _resume_count: int = 0
var _command_count: int = 0
var _replay_served_count: int = 0
var _disconnect_count: int = 0
var _final_ack_count: int = 0
var _flush_started_at_ms: int = 0
var _last_progress_at_ms: int = 0


func configure(endpoint: Dictionary, service_config: Dictionary) -> Dictionary:
	if _state != STATE_STOPPED: return _failure("SESSION_NOT_STOPPED")
	_authority = AuthorityScript.new()
	var authority_result: Dictionary = _authority.setup(
		String(service_config.get("authority_owner_id", "")),
		int(service_config.get("authority_epoch", 0)),
		int(service_config.get("server_tick", 0))
	)
	if not bool(authority_result.get("success", false)): return authority_result
	_initial_snapshot = _authority.create_snapshot()
	_handshake_service = HandshakeServiceScript.new()
	var service_result: Dictionary = _handshake_service.configure(service_config)
	if not bool(service_result.get("success", false)): return service_result
	_replay_service = ReplayServiceScript.new()
	var replay_result: Dictionary = _replay_service.configure(4, 8, 64, 256, 3)
	if not bool(replay_result.get("success", false)): return replay_result
	_port = EnetPortScript.new()
	_boundary = BoundaryScript.new()
	var boundary_result: Dictionary = _boundary.configure(_port)
	if not bool(boundary_result.get("success", false)): return boundary_result
	_endpoint = endpoint.duplicate(true)
	return _success()


func start() -> Dictionary:
	if _boundary == null: return _failure("SESSION_NOT_CONFIGURED")
	var result: Dictionary = _boundary.start_server(_endpoint)
	if not bool(result.get("success", false)): return _enter_failed(String(result.get("error_code", "SERVER_START_FAILED")))
	_state = STATE_LISTENING
	_last_progress_at_ms = Time.get_ticks_msec()
	return _success({"state": _state})


func poll() -> Dictionary:
	if not is_terminal() and _last_progress_at_ms > 0 and Time.get_ticks_msec() - _last_progress_at_ms > SESSION_IDLE_TIMEOUT_MS:
		return _enter_failed("SESSION_IDLE_TIMEOUT_%s" % _state)
	if _state == STATE_FLUSHING and Time.get_ticks_msec() - _flush_started_at_ms >= RESULT_FLUSH_GRACE_MS:
		_state = STATE_COMPLETE
	if _state in [STATE_STOPPED, STATE_COMPLETE, STATE_FAILED]: return _success({"state": _state, "terminal": true})
	var event_result: Dictionary = _boundary.poll_events(64)
	if not bool(event_result.get("success", false)): return _enter_failed(String(event_result.get("error_code", "EVENT_POLL_FAILED")))
	for event in event_result.get("details", {}).get("events", []):
		_last_progress_at_ms = Time.get_ticks_msec()
		_events_processed += 1
		var handled: Dictionary = _handle_event(event)
		if not bool(handled.get("success", false)): return handled
	return _success({"state": _state, "terminal": is_terminal()})


func stop() -> Dictionary:
	if _boundary != null:
		_boundary.drain()
		_boundary.stop()
	if not is_terminal(): _state = STATE_STOPPED
	return _success({"state": _state})


func is_terminal() -> bool:
	return _state in [STATE_COMPLETE, STATE_FAILED]


func is_success() -> bool:
	return _state == STATE_COMPLETE


func get_report() -> Dictionary:
	var authority_report: Dictionary = _authority.get_report() if _authority != null else {}
	var replay_report: Dictionary = _replay_service.get_snapshot() if _replay_service != null else {}
	return {
		"schema": "planet_simulator.n1_reconnect_replay_server_report.v1",
		"state": _state,
		"passed": is_success(),
		"failure_code": _failure_code,
		"logical_session_id": _logical_session_id,
		"transport_session_ids": _transport_session_ids.duplicate(),
		"unique_transport_sessions": _unique_count(_transport_session_ids),
		"client_node_id": _client_node_id,
		"entity_id": String(authority_report.get("entity_id", "")),
		"command_item_id": String(authority_report.get("command_item_id", "")),
		"initial_snapshot_checksum": String(_initial_snapshot.get("checksum", "")),
		"final_snapshot_checksum": String(authority_report.get("snapshot_checksum", "")),
		"aggregate_revision": int(authority_report.get("aggregate_revision", -1)),
		"server_tick": int(authority_report.get("server_tick", -1)),
		"mutation_count": int(authority_report.get("mutation_count", 0)),
		"handler_invocation_count": int(authority_report.get("handler_invocation_count", 0)),
		"operation_ledger_count": int(authority_report.get("operation_ledger_count", 0)),
		"source_contains_item": bool(authority_report.get("source_contains_item", false)),
		"destination_contains_item": bool(authority_report.get("destination_contains_item", false)),
		"events_processed": _events_processed,
		"messages_sent": _messages_sent,
		"messages_received": _messages_received,
		"handshake_count": _handshake_count,
		"resume_count": _resume_count,
		"command_count": _command_count,
		"replay_served_count": _replay_served_count,
		"disconnect_count": _disconnect_count,
		"final_ack_count": _final_ack_count,
		"session_idle_timeout_ms": SESSION_IDLE_TIMEOUT_MS,
		"replay_cache": replay_report,
	}


func _handle_event(event: Dictionary) -> Dictionary:
	match String(event.get("type", "")):
		"PEER_CONNECTED":
			_peer_id = int(event.get("peer_id", 0))
		"MESSAGE":
			_peer_id = int(event.get("peer_id", _peer_id))
			_messages_received += 1
			return _handle_message(String(event.get("message_type", "")), event.get("payload", {}))
		"MALFORMED_MESSAGE": return _enter_failed(String(event.get("error_code", "MALFORMED_MESSAGE")))
		"PEER_REJECTED": return _enter_failed(String(event.get("error_code", "PEER_REJECTED")))
		"PEER_DISCONNECTED":
			if _state not in [STATE_WAITING_RECONNECT, STATE_FLUSHING, STATE_COMPLETE]:
				return _enter_failed("UNEXPECTED_PEER_DISCONNECT")
	return _success()


func _handle_message(message_type: String, payload) -> Dictionary:
	if not payload is Dictionary: return _enter_failed("INVALID_MESSAGE_PAYLOAD")
	match message_type:
		"HANDSHAKE": return _handle_handshake(payload)
		"SNAPSHOT_ACK": return _handle_snapshot_ack(payload)
		"COMMAND": return _handle_command(payload)
		"SESSION_RESUME": return _handle_resume(payload)
	return _enter_failed("UNEXPECTED_MESSAGE_TYPE")


func _handle_handshake(payload: Dictionary) -> Dictionary:
	if _state not in [STATE_LISTENING, STATE_WAITING_RECONNECT]: return _enter_failed("UNEXPECTED_HANDSHAKE")
	var validation: Dictionary = HandshakeScript.validate(payload)
	if not bool(validation.get("success", false)): return _enter_failed(String(validation.get("error_code", "INVALID_HANDSHAKE")))
	var reconnecting: bool = _state == STATE_WAITING_RECONNECT
	if reconnecting and String(payload["client_node_id"]) != _client_node_id:
		return _enter_failed("RECONNECT_CLIENT_ID_MISMATCH")
	var evaluated: Dictionary = _handshake_service.evaluate(payload, _peer_id)
	if not bool(evaluated.get("success", false)): return _enter_failed(String(evaluated.get("error_code", "HANDSHAKE_EVALUATION_FAILED")))
	var result: Dictionary = evaluated.get("details", {}).get("result", {}).duplicate(true)
	if String(_boundary.get_snapshot().get("state", "")) == BoundaryScript.STATE_LISTENING:
		var ready: Dictionary = _boundary.mark_ready()
		if not bool(ready.get("success", false)): return _enter_failed(String(ready.get("error_code", "READY_TRANSITION_FAILED")))
	var sent: Dictionary = _boundary.send("HANDSHAKE_RESULT", result)
	if not bool(sent.get("success", false)): return _enter_failed(String(sent.get("error_code", "HANDSHAKE_RESULT_SEND_FAILED")))
	_messages_sent += 1
	_handshake_count += 1
	if not bool(result.get("accepted", false)): return _enter_failed(String(result.get("error_code", "HANDSHAKE_REJECTED")))
	_transport_session_id = String(result["session_id"])
	if _transport_session_ids.has(_transport_session_id): return _enter_failed("TRANSPORT_SESSION_REUSED")
	_transport_session_ids.append(_transport_session_id)
	if reconnecting:
		_state = STATE_WAITING_RESUME
		return _success({"state": _state})
	_client_node_id = String(payload["client_node_id"])
	_logical_session_id = _transport_session_id
	var bound: Dictionary = _authority.bind_session(_logical_session_id)
	if not bool(bound.get("success", false)): return _enter_failed(String(bound.get("error_code", "SESSION_BIND_FAILED")))
	var snapshot_sent: Dictionary = _boundary.send("SNAPSHOT", _initial_snapshot)
	if not bool(snapshot_sent.get("success", false)): return _enter_failed(String(snapshot_sent.get("error_code", "SNAPSHOT_SEND_FAILED")))
	_messages_sent += 1
	_state = STATE_SNAPSHOT_SENT
	return _success({"state": _state})


func _handle_snapshot_ack(payload: Dictionary) -> Dictionary:
	var validation: Dictionary = AckScript.validate(payload)
	if not bool(validation.get("success", false)): return _enter_failed(String(validation.get("error_code", "INVALID_SNAPSHOT_ACK")))
	if _state == STATE_SNAPSHOT_SENT:
		if String(payload["session_id"]) != _logical_session_id: return _enter_failed("INITIAL_ACK_SESSION_MISMATCH")
		if String(payload["snapshot_checksum"]) != String(_initial_snapshot["checksum"]): return _enter_failed("INITIAL_ACK_CHECKSUM_MISMATCH")
		var issued: Dictionary = _replay_service.issue_ticket(_logical_session_id, _client_node_id, int(_initial_snapshot["server_tick"]))
		if not bool(issued.get("success", false)): return _enter_failed(String(issued.get("error_code", "RESUME_TICKET_FAILED")))
		_ticket = issued.get("details", {}).get("ticket", {}).duplicate(true)
		var ticket_sent: Dictionary = _boundary.send("RESUME_TICKET", _ticket)
		if not bool(ticket_sent.get("success", false)): return _enter_failed(String(ticket_sent.get("error_code", "RESUME_TICKET_SEND_FAILED")))
		_messages_sent += 1
		_state = STATE_COMMAND_READY
		return _success({"state": _state})
	if _state == STATE_WAITING_REPLAY_ACK:
		if String(payload["session_id"]) != _transport_session_id: return _enter_failed("FINAL_ACK_SESSION_MISMATCH")
		if String(payload["snapshot_checksum"]) != String(_final_snapshot["checksum"]): return _enter_failed("FINAL_ACK_CHECKSUM_MISMATCH")
		if int(payload["client_tick"]) != int(_final_snapshot["server_tick"]): return _enter_failed("FINAL_ACK_TICK_MISMATCH")
		_final_ack_count += 1
		if _final_ack_count < REQUIRED_REPLAY_CYCLES:
			return _disconnect_for_reconnect()
		_state = STATE_FLUSHING
		_flush_started_at_ms = Time.get_ticks_msec()
		return _success({"state": _state})
	return _enter_failed("UNEXPECTED_SNAPSHOT_ACK")


func _handle_command(payload: Dictionary) -> Dictionary:
	var validation: Dictionary = CommandScript.validate(payload)
	if not bool(validation.get("success", false)): return _enter_failed(String(validation.get("error_code", "INVALID_COMMAND")))
	var command: Dictionary = CommandScript.normalize(payload)
	_command_count += 1
	if _state == STATE_COMMAND_READY:
		_primary_command = command.duplicate(true)
		var result: Dictionary = _authority.handle_command(command)
		var result_validation: Dictionary = ResultScript.validate(result)
		if not bool(result_validation.get("success", false)) or String(result.get("status", "")) != "SUCCEEDED":
			return _enter_failed("PRIMARY_COMMAND_FAILED")
		_primary_result = result.duplicate(true)
		_primary_delta = _authority.get_delta(String(command["operation_id"]))
		_final_snapshot = _authority.get_final_snapshot(String(command["operation_id"]))
		var recorded: Dictionary = _replay_service.record_completed_operation(
			_logical_session_id, _client_node_id, command, result, _primary_delta, _final_snapshot,
			int(_final_snapshot["server_tick"]), _initial_snapshot
		)
		if not bool(recorded.get("success", false)): return _enter_failed(String(recorded.get("error_code", "REPLAY_RECORD_FAILED")))
		return _disconnect_for_reconnect()
	if _state == STATE_REPLAY_READY:
		var replayed: Dictionary = _replay_service.serve_replay(_transport_session_id, command, int(_final_snapshot["server_tick"]))
		if not bool(replayed.get("success", false)): return _enter_failed(String(replayed.get("error_code", "REPLAY_FAILED")))
		var details: Dictionary = replayed.get("details", {})
		var result_sent: Dictionary = _boundary.send("COMMAND_RESULT", details["result"])
		if not bool(result_sent.get("success", false)): return _enter_failed(String(result_sent.get("error_code", "REPLAY_RESULT_SEND_FAILED")))
		var delta_sent: Dictionary = _boundary.send("DELTA", details["delta"])
		if not bool(delta_sent.get("success", false)): return _enter_failed(String(delta_sent.get("error_code", "REPLAY_DELTA_SEND_FAILED")))
		_messages_sent += 2
		_replay_served_count += 1
		_state = STATE_WAITING_REPLAY_ACK
		return _success({"state": _state})
	return _enter_failed("UNEXPECTED_COMMAND")


func _handle_resume(payload: Dictionary) -> Dictionary:
	if _state != STATE_WAITING_RESUME: return _enter_failed("UNEXPECTED_SESSION_RESUME")
	var validation: Dictionary = ResumeScript.validate(payload)
	if not bool(validation.get("success", false)): return _enter_failed(String(validation.get("error_code", "INVALID_SESSION_RESUME")))
	if String(payload["transport_session_id"]) != _transport_session_id: return _enter_failed("RESUME_TRANSPORT_SESSION_MISMATCH")
	var evaluated: Dictionary = _replay_service.evaluate_resume(payload, int(_final_snapshot["server_tick"]))
	if not bool(evaluated.get("success", false)): return _enter_failed(String(evaluated.get("error_code", "RESUME_EVALUATION_FAILED")))
	var result: Dictionary = evaluated.get("details", {}).get("result", {}).duplicate(true)
	var result_validation: Dictionary = ResumeResultScript.validate(result)
	if not bool(result_validation.get("success", false)): return _enter_failed(String(result_validation.get("error_code", "INVALID_RESUME_RESULT")))
	var sent: Dictionary = _boundary.send("SESSION_RESUME_RESULT", result)
	if not bool(sent.get("success", false)): return _enter_failed(String(sent.get("error_code", "RESUME_RESULT_SEND_FAILED")))
	_messages_sent += 1
	if not bool(result["accepted"]): return _enter_failed(String(result["error_code"]))
	_resume_count += 1
	_state = STATE_REPLAY_READY
	return _success({"state": _state})


func _disconnect_for_reconnect() -> Dictionary:
	var disconnected: Dictionary = _boundary.disconnect_peer()
	if not bool(disconnected.get("success", false)): return _enter_failed(String(disconnected.get("error_code", "DISCONNECT_FAILED")))
	_disconnect_count += 1
	_state = STATE_WAITING_RECONNECT
	return _success({"state": _state})


func _unique_count(values: Array[String]) -> int:
	var unique: Dictionary = {}
	for value in values: unique[value] = true
	return unique.size()


func _enter_failed(error_code: String) -> Dictionary:
	_state = STATE_FAILED
	_failure_code = error_code if not error_code.is_empty() else "N1_RECONNECT_SERVER_FAILURE"
	return _failure(_failure_code, {"state": _state})


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}

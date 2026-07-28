extends RefCounted

const BoundaryScript = preload("res://scripts/network/transports/network_transport_boundary.gd")
const EnetPortScript = preload("res://scripts/network/transports/enet_transport_port.gd")
const AckScript = preload("res://scripts/network/contracts/snapshot_ack_envelope.gd")
const CommandScript = preload("res://scripts/network/contracts/network_command_envelope.gd")
const ResultScript = preload("res://scripts/network/contracts/network_command_result_envelope.gd")
const HandshakeServiceScript = preload("res://scripts/network/session/network_handshake_service.gd")
const AuthorityScript = preload("res://scripts/network/session/n1_remote_item_authority.gd")

const STATE_STOPPED: String = "STOPPED"
const STATE_LISTENING: String = "LISTENING"
const STATE_SNAPSHOT_SENT: String = "SNAPSHOT_SENT"
const STATE_COMMAND_READY: String = "COMMAND_READY"
const STATE_FLUSHING: String = "FLUSHING"
const STATE_COMPLETE: String = "COMPLETE"
const STATE_REJECTED: String = "REJECTED"
const STATE_FAILED: String = "FAILED"
const RESULT_FLUSH_GRACE_MS: int = 500
const EXPECTED_COMMAND_COUNT: int = 3

var _boundary
var _port
var _handshake_service
var _authority
var _endpoint: Dictionary = {}
var _snapshot: Dictionary = {}
var _state: String = STATE_STOPPED
var _session_id: String = ""
var _peer_id: int = 0
var _failure_code: String = ""
var _events_processed: int = 0
var _messages_sent: int = 0
var _messages_received: int = 0
var _handshake_result: Dictionary = {}
var _ack: Dictionary = {}
var _command_count: int = 0
var _command_result_count: int = 0
var _delta_count: int = 0
var _duplicate_replay_count: int = 0
var _operation_fingerprints: Dictionary = {}
var _stale_revision_rejected: bool = false
var _flush_started_at_ms: int = 0


func configure(endpoint: Dictionary, service_config: Dictionary) -> Dictionary:
	if _state != STATE_STOPPED:
		return _failure("SESSION_NOT_STOPPED")
	_authority = AuthorityScript.new()
	var authority_result: Dictionary = _authority.setup(
		String(service_config.get("authority_owner_id", "")),
		int(service_config.get("authority_epoch", 0)),
		int(service_config.get("server_tick", 0))
	)
	if not bool(authority_result.get("success", false)):
		return authority_result
	_snapshot = _authority.create_snapshot()
	_handshake_service = HandshakeServiceScript.new()
	var service_result: Dictionary = _handshake_service.configure(service_config)
	if not bool(service_result.get("success", false)):
		return service_result
	_port = EnetPortScript.new()
	_boundary = BoundaryScript.new()
	var boundary_result: Dictionary = _boundary.configure(_port)
	if not bool(boundary_result.get("success", false)):
		return boundary_result
	_endpoint = endpoint.duplicate(true)
	return _success({"snapshot": _snapshot.duplicate(true)})


func start() -> Dictionary:
	if _boundary == null:
		return _failure("SESSION_NOT_CONFIGURED")
	var result: Dictionary = _boundary.start_server(_endpoint)
	if not bool(result.get("success", false)):
		return _enter_failed(String(result.get("error_code", "SERVER_START_FAILED")))
	_state = STATE_LISTENING
	return _success({"state": _state})


func poll() -> Dictionary:
	if _state == STATE_FLUSHING and Time.get_ticks_msec() - _flush_started_at_ms >= RESULT_FLUSH_GRACE_MS:
		_state = STATE_COMPLETE
	if _state in [STATE_STOPPED, STATE_COMPLETE, STATE_REJECTED, STATE_FAILED]:
		return _success({"state": _state, "terminal": true})
	var event_result: Dictionary = _boundary.poll_events(64)
	if not bool(event_result.get("success", false)):
		return _enter_failed(String(event_result.get("error_code", "EVENT_POLL_FAILED")))
	for event in event_result.get("details", {}).get("events", []):
		_events_processed += 1
		var handled: Dictionary = _handle_event(event)
		if not bool(handled.get("success", false)):
			return handled
	return _success({"state": _state, "terminal": is_terminal()})


func stop() -> Dictionary:
	if _boundary != null:
		_boundary.drain()
		_boundary.stop()
	if not is_terminal():
		_state = STATE_STOPPED
	return _success({"state": _state})


func is_terminal() -> bool:
	return _state in [STATE_COMPLETE, STATE_REJECTED, STATE_FAILED]


func is_success() -> bool:
	return _state == STATE_COMPLETE


func get_report() -> Dictionary:
	var authority_report: Dictionary = _authority.get_report() if _authority != null else {}
	return {
		"schema": "planet_simulator.n1_remote_item_server_report.v1",
		"state": _state,
		"passed": is_success(),
		"failure_code": _failure_code,
		"session_id": _session_id,
		"peer_id": _peer_id,
		"initial_snapshot_checksum": String(_snapshot.get("checksum", "")),
		"final_snapshot_checksum": String(authority_report.get("snapshot_checksum", "")),
		"entity_id": String(authority_report.get("entity_id", "")),
		"command_item_id": String(authority_report.get("command_item_id", "")),
		"aggregate_revision": int(authority_report.get("aggregate_revision", -1)),
		"item_revision": int(authority_report.get("item_revision", -1)),
		"server_tick": int(authority_report.get("server_tick", -1)),
		"source_contains_item": bool(authority_report.get("source_contains_item", false)),
		"destination_contains_item": bool(authority_report.get("destination_contains_item", false)),
		"mutation_count": int(authority_report.get("mutation_count", 0)),
		"handler_invocation_count": int(authority_report.get("handler_invocation_count", 0)),
		"operation_ledger_count": int(authority_report.get("operation_ledger_count", 0)),
		"events_processed": _events_processed,
		"messages_sent": _messages_sent,
		"messages_received": _messages_received,
		"command_count": _command_count,
		"command_result_count": _command_result_count,
		"delta_count": _delta_count,
		"duplicate_replay_count": _duplicate_replay_count,
		"stale_revision_rejected": _stale_revision_rejected,
		"handshake_accepted": bool(_handshake_result.get("accepted", false)),
		"snapshot_ack_accepted": bool(_ack.get("accepted", false)),
	}


func _handle_event(event: Dictionary) -> Dictionary:
	var event_type: String = String(event.get("type", ""))
	match event_type:
		"PEER_CONNECTED":
			_peer_id = int(event.get("peer_id", 0))
			return _success()
		"MESSAGE":
			_peer_id = int(event.get("peer_id", _peer_id))
			_messages_received += 1
			return _handle_message(String(event.get("message_type", "")), event.get("payload", {}))
		"MALFORMED_MESSAGE":
			return _enter_failed(String(event.get("error_code", "MALFORMED_MESSAGE")))
		"PEER_DISCONNECTED":
			if _state not in [STATE_COMPLETE, STATE_FLUSHING]:
				return _enter_failed("PEER_DISCONNECTED_BEFORE_COMMAND_SCENARIO")
			return _success()
		"PEER_REJECTED":
			return _enter_failed(String(event.get("error_code", "PEER_REJECTED")))
	return _success()


func _handle_message(message_type: String, payload) -> Dictionary:
	if not payload is Dictionary:
		return _enter_failed("INVALID_MESSAGE_PAYLOAD")
	match message_type:
		"HANDSHAKE":
			return _handle_handshake(payload)
		"SNAPSHOT_ACK":
			return _handle_snapshot_ack(payload)
		"COMMAND":
			return _handle_command(payload)
	return _enter_failed("UNEXPECTED_MESSAGE_TYPE")


func _handle_handshake(payload: Dictionary) -> Dictionary:
	if _state != STATE_LISTENING or not _handshake_result.is_empty():
		return _enter_failed("UNEXPECTED_HANDSHAKE")
	var evaluated: Dictionary = _handshake_service.evaluate(payload, _peer_id)
	if not bool(evaluated.get("success", false)):
		return _enter_failed(String(evaluated.get("error_code", "HANDSHAKE_EVALUATION_FAILED")))
	_handshake_result = evaluated.get("details", {}).get("result", {}).duplicate(true)
	var ready_result: Dictionary = _boundary.mark_ready()
	if not bool(ready_result.get("success", false)):
		return _enter_failed(String(ready_result.get("error_code", "READY_TRANSITION_FAILED")))
	var send_result: Dictionary = _boundary.send("HANDSHAKE_RESULT", _handshake_result)
	if not bool(send_result.get("success", false)):
		return _enter_failed(String(send_result.get("error_code", "HANDSHAKE_RESULT_SEND_FAILED")))
	_messages_sent += 1
	if not bool(_handshake_result.get("accepted", false)):
		_failure_code = String(_handshake_result.get("error_code", "HANDSHAKE_REJECTED"))
		_state = STATE_REJECTED
		return _success({"state": _state})
	_session_id = String(_handshake_result["session_id"])
	var bind_result: Dictionary = _authority.bind_session(_session_id)
	if not bool(bind_result.get("success", false)):
		return _enter_failed(String(bind_result.get("error_code", "SESSION_BIND_FAILED")))
	var snapshot_send: Dictionary = _boundary.send("SNAPSHOT", _snapshot)
	if not bool(snapshot_send.get("success", false)):
		return _enter_failed(String(snapshot_send.get("error_code", "SNAPSHOT_SEND_FAILED")))
	_messages_sent += 1
	_state = STATE_SNAPSHOT_SENT
	return _success({"state": _state})


func _handle_snapshot_ack(payload: Dictionary) -> Dictionary:
	if _state != STATE_SNAPSHOT_SENT:
		return _enter_failed("UNEXPECTED_SNAPSHOT_ACK")
	var validation: Dictionary = AckScript.validate(payload)
	if not bool(validation.get("success", false)):
		return _enter_failed(String(validation.get("error_code", "INVALID_SNAPSHOT_ACK")))
	_ack = payload.duplicate(true)
	if String(_ack["session_id"]) != _session_id:
		return _enter_failed("SESSION_ID_MISMATCH")
	if String(_ack["snapshot_id"]) != String(_snapshot["snapshot_id"]):
		return _enter_failed("SNAPSHOT_ID_MISMATCH")
	if String(_ack["entity_id"]) != String(_snapshot["entity_id"]):
		return _enter_failed("ENTITY_ID_MISMATCH")
	if String(_ack["snapshot_checksum"]) != String(_snapshot["checksum"]):
		return _enter_failed("SNAPSHOT_CHECKSUM_MISMATCH")
	if int(_ack["client_tick"]) != int(_snapshot["server_tick"]):
		return _enter_failed("SNAPSHOT_ACK_TICK_MISMATCH")
	if not bool(_ack["accepted"]):
		return _enter_failed(String(_ack["error_code"]))
	_state = STATE_COMMAND_READY
	return _success({"state": _state})


func _handle_command(payload: Dictionary) -> Dictionary:
	if _state != STATE_COMMAND_READY:
		return _enter_failed("UNEXPECTED_COMMAND")
	var validation: Dictionary = CommandScript.validate(payload)
	if not bool(validation.get("success", false)):
		return _enter_failed(String(validation.get("error_code", "INVALID_COMMAND")))
	var command: Dictionary = CommandScript.normalize(payload)
	var operation_id: String = String(command["operation_id"])
	var fingerprint: String = CommandScript.command_fingerprint(command)
	if _operation_fingerprints.has(operation_id) and String(_operation_fingerprints[operation_id]) == fingerprint:
		_duplicate_replay_count += 1
	elif not _operation_fingerprints.has(operation_id):
		_operation_fingerprints[operation_id] = fingerprint
	_command_count += 1
	var result: Dictionary = _authority.handle_command(command)
	var result_validation: Dictionary = ResultScript.validate(result)
	if not bool(result_validation.get("success", false)):
		return _enter_failed(String(result_validation.get("error_code", "INVALID_COMMAND_RESULT")))
	var send_result: Dictionary = _boundary.send("COMMAND_RESULT", result)
	if not bool(send_result.get("success", false)):
		return _enter_failed(String(send_result.get("error_code", "COMMAND_RESULT_SEND_FAILED")))
	_messages_sent += 1
	_command_result_count += 1
	if String(result["status"]) == "SUCCEEDED":
		var delta: Dictionary = _authority.get_delta(operation_id)
		if delta.is_empty():
			return _enter_failed("SUCCEEDED_COMMAND_MISSING_DELTA")
		var delta_send: Dictionary = _boundary.send("DELTA", delta)
		if not bool(delta_send.get("success", false)):
			return _enter_failed(String(delta_send.get("error_code", "DELTA_SEND_FAILED")))
		_messages_sent += 1
		_delta_count += 1
	elif String(result["error_code"]) == "REVISION_CONFLICT":
		_stale_revision_rejected = true
	if _command_count >= EXPECTED_COMMAND_COUNT:
		_state = STATE_FLUSHING
		_flush_started_at_ms = Time.get_ticks_msec()
	return _success({"state": _state})


func _enter_failed(error_code: String) -> Dictionary:
	_state = STATE_FAILED
	_failure_code = error_code if not error_code.is_empty() else "N1_REMOTE_ITEM_SERVER_FAILURE"
	return _failure(_failure_code, {"state": _state})


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}

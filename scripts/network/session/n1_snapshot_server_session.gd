extends RefCounted

const BoundaryScript = preload("res://scripts/network/transports/network_transport_boundary.gd")
const EnetPortScript = preload("res://scripts/network/transports/enet_transport_port.gd")
const SnapshotScript = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")
const AckScript = preload("res://scripts/network/contracts/snapshot_ack_envelope.gd")
const HandshakeServiceScript = preload("res://scripts/network/session/network_handshake_service.gd")

const STATE_STOPPED: String = "STOPPED"
const STATE_LISTENING: String = "LISTENING"
const STATE_SNAPSHOT_SENT: String = "SNAPSHOT_SENT"
const STATE_COMPLETE: String = "COMPLETE"
const STATE_REJECTED: String = "REJECTED"
const STATE_FAILED: String = "FAILED"

var _boundary
var _port
var _handshake_service
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


func configure(endpoint: Dictionary, snapshot: Dictionary, service_config: Dictionary) -> Dictionary:
	if _state != STATE_STOPPED:
		return _failure("SESSION_NOT_STOPPED")
	var snapshot_validation: Dictionary = SnapshotScript.validate(snapshot)
	if not bool(snapshot_validation.get("success", false)):
		return _failure(String(snapshot_validation.get("error_code", "INVALID_SNAPSHOT")))
	_handshake_service = HandshakeServiceScript.new()
	var service_result: Dictionary = _handshake_service.configure(service_config)
	if not bool(service_result.get("success", false)):
		return service_result
	if String(snapshot["authority_owner_id"]) != String(service_config["authority_owner_id"]):
		return _failure("SNAPSHOT_AUTHORITY_OWNER_MISMATCH")
	if int(snapshot["authority_epoch"]) != int(service_config["authority_epoch"]):
		return _failure("SNAPSHOT_AUTHORITY_EPOCH_MISMATCH")
	if int(snapshot["server_tick"]) > int(service_config["server_tick"]):
		return _failure("SNAPSHOT_SERVER_TICK_AHEAD")
	_port = EnetPortScript.new()
	_boundary = BoundaryScript.new()
	var boundary_result: Dictionary = _boundary.configure(_port)
	if not bool(boundary_result.get("success", false)):
		return boundary_result
	_endpoint = endpoint.duplicate(true)
	_snapshot = snapshot.duplicate(true)
	return _success()


func start() -> Dictionary:
	if _boundary == null:
		return _failure("SESSION_NOT_CONFIGURED")
	var result: Dictionary = _boundary.start_server(_endpoint)
	if not bool(result.get("success", false)):
		return _enter_failed(String(result.get("error_code", "SERVER_START_FAILED")))
	_state = STATE_LISTENING
	return _success({"state": _state})


func poll() -> Dictionary:
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
	return {
		"schema": "planet_simulator.n1_snapshot_server_report.v1",
		"state": _state,
		"passed": is_success(),
		"failure_code": _failure_code,
		"session_id": _session_id,
		"peer_id": _peer_id,
		"snapshot_id": String(_snapshot.get("snapshot_id", "")),
		"entity_id": String(_snapshot.get("entity_id", "")),
		"snapshot_checksum": String(_snapshot.get("checksum", "")),
		"events_processed": _events_processed,
		"messages_sent": _messages_sent,
		"messages_received": _messages_received,
		"handshake_accepted": bool(_handshake_result.get("accepted", false)),
		"ack_accepted": bool(_ack.get("accepted", false)),
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
			if _state != STATE_COMPLETE:
				return _enter_failed("PEER_DISCONNECTED_BEFORE_ACK")
			return _success()
		"PEER_REJECTED":
			return _enter_failed(String(event.get("error_code", "PEER_REJECTED")))
	return _success()


func _handle_message(message_type: String, payload) -> Dictionary:
	if not payload is Dictionary:
		return _enter_failed("INVALID_MESSAGE_PAYLOAD")
	if message_type == "HANDSHAKE":
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
		var snapshot_send: Dictionary = _boundary.send("SNAPSHOT", _snapshot)
		if not bool(snapshot_send.get("success", false)):
			return _enter_failed(String(snapshot_send.get("error_code", "SNAPSHOT_SEND_FAILED")))
		_messages_sent += 1
		_state = STATE_SNAPSHOT_SENT
		return _success({"state": _state})
	if message_type == "SNAPSHOT_ACK":
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
		_state = STATE_COMPLETE
		return _success({"state": _state})
	return _enter_failed("UNEXPECTED_MESSAGE_TYPE")


func _enter_failed(error_code: String) -> Dictionary:
	_state = STATE_FAILED
	_failure_code = error_code if not error_code.is_empty() else "N1_SERVER_FAILURE"
	return _failure(_failure_code, {"state": _state})


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}

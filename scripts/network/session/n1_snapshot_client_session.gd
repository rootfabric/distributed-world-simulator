extends RefCounted

const BoundaryScript = preload("res://scripts/network/transports/network_transport_boundary.gd")
const EnetPortScript = preload("res://scripts/network/transports/enet_transport_port.gd")
const HandshakeScript = preload("res://scripts/network/contracts/network_handshake_envelope.gd")
const ResultScript = preload("res://scripts/network/contracts/network_handshake_result_envelope.gd")
const SnapshotScript = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")
const AckScript = preload("res://scripts/network/contracts/snapshot_ack_envelope.gd")

const STATE_STOPPED: String = "STOPPED"
const STATE_CONNECTING: String = "CONNECTING"
const STATE_HANDSHAKE_SENT: String = "HANDSHAKE_SENT"
const STATE_WAITING_SNAPSHOT: String = "WAITING_SNAPSHOT"
const STATE_ACK_SENT: String = "ACK_SENT"
const STATE_COMPLETE: String = "COMPLETE"
const STATE_REJECTED: String = "REJECTED"
const STATE_FAILED: String = "FAILED"
const ACK_FLUSH_GRACE_MS: int = 300
const REQUIRED_CAPABILITIES: Array[String] = ["handshake.v1", "snapshot.receive"]
const REQUIRED_CONTRACTS: Array[String] = [
	"entity_snapshot", "network_handshake", "network_wire_frame", "snapshot_ack",
]

var _boundary
var _port
var _endpoint: Dictionary = {}
var _handshake: Dictionary = {}
var _handshake_result: Dictionary = {}
var _snapshot: Dictionary = {}
var _ack: Dictionary = {}
var _state: String = STATE_STOPPED
var _failure_code: String = ""
var _session_id: String = ""
var _ack_sent_at_ms: int = 0
var _events_processed: int = 0
var _messages_sent: int = 0
var _messages_received: int = 0


func configure(endpoint: Dictionary, handshake: Dictionary) -> Dictionary:
	if _state != STATE_STOPPED:
		return _failure("SESSION_NOT_STOPPED")
	var validation: Dictionary = HandshakeScript.validate(handshake)
	if not bool(validation.get("success", false)):
		return _failure(String(validation.get("error_code", "INVALID_HANDSHAKE")))
	_port = EnetPortScript.new()
	_boundary = BoundaryScript.new()
	var boundary_result: Dictionary = _boundary.configure(_port)
	if not bool(boundary_result.get("success", false)):
		return boundary_result
	_endpoint = endpoint.duplicate(true)
	_handshake = handshake.duplicate(true)
	return _success()


func start() -> Dictionary:
	if _boundary == null:
		return _failure("SESSION_NOT_CONFIGURED")
	var result: Dictionary = _boundary.connect_client(_endpoint)
	if not bool(result.get("success", false)):
		return _enter_failed(String(result.get("error_code", "CLIENT_CONNECT_FAILED")))
	_state = STATE_CONNECTING
	return _success({"state": _state})


func poll() -> Dictionary:
	if _state == STATE_ACK_SENT and Time.get_ticks_msec() - _ack_sent_at_ms >= ACK_FLUSH_GRACE_MS:
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
	return {
		"schema": "planet_simulator.n1_snapshot_client_report.v1",
		"state": _state,
		"passed": is_success(),
		"failure_code": _failure_code,
		"session_id": _session_id,
		"snapshot_id": String(_snapshot.get("snapshot_id", "")),
		"entity_id": String(_snapshot.get("entity_id", "")),
		"snapshot_checksum": String(_snapshot.get("checksum", "")),
		"snapshot_revision": int(_snapshot.get("state_revision", -1)),
		"authority_owner_id": String(_snapshot.get("authority_owner_id", "")),
		"authority_epoch": int(_snapshot.get("authority_epoch", -1)),
		"server_tick": int(_snapshot.get("server_tick", -1)),
		"events_processed": _events_processed,
		"messages_sent": _messages_sent,
		"messages_received": _messages_received,
		"handshake_accepted": bool(_handshake_result.get("accepted", false)),
		"ack_accepted": bool(_ack.get("accepted", false)),
	}


func _handle_event(event: Dictionary) -> Dictionary:
	var event_type: String = String(event.get("type", ""))
	match event_type:
		"CONNECTED":
			if _state != STATE_CONNECTING:
				return _enter_failed("UNEXPECTED_CONNECTED_EVENT")
			var ready_result: Dictionary = _boundary.mark_ready()
			if not bool(ready_result.get("success", false)):
				return _enter_failed(String(ready_result.get("error_code", "READY_TRANSITION_FAILED")))
			var send_result: Dictionary = _boundary.send("HANDSHAKE", _handshake)
			if not bool(send_result.get("success", false)):
				return _enter_failed(String(send_result.get("error_code", "HANDSHAKE_SEND_FAILED")))
			_messages_sent += 1
			_state = STATE_HANDSHAKE_SENT
			return _success()
		"MESSAGE":
			_messages_received += 1
			return _handle_message(String(event.get("message_type", "")), event.get("payload", {}))
		"MALFORMED_MESSAGE":
			return _enter_failed(String(event.get("error_code", "MALFORMED_MESSAGE")))
		"CONNECTION_FAILED":
			return _enter_failed("CONNECTION_FAILED")
		"DISCONNECTED":
			if _state == STATE_ACK_SENT:
				_state = STATE_COMPLETE
			elif _state != STATE_COMPLETE:
				return _enter_failed("SERVER_DISCONNECTED_EARLY")
	return _success()


func _handle_message(message_type: String, payload) -> Dictionary:
	if not payload is Dictionary:
		return _enter_failed("INVALID_MESSAGE_PAYLOAD")
	if message_type == "HANDSHAKE_RESULT":
		if _state != STATE_HANDSHAKE_SENT or not _handshake_result.is_empty():
			return _enter_failed("UNEXPECTED_HANDSHAKE_RESULT")
		var validation: Dictionary = ResultScript.validate(payload)
		if not bool(validation.get("success", false)):
			return _enter_failed(String(validation.get("error_code", "INVALID_HANDSHAKE_RESULT")))
		_handshake_result = payload.duplicate(true)
		if String(_handshake_result["handshake_id"]) != String(_handshake["handshake_id"]):
			return _enter_failed("HANDSHAKE_ID_MISMATCH")
		if not bool(_handshake_result["accepted"]):
			_failure_code = String(_handshake_result["error_code"])
			_state = STATE_REJECTED
			return _success({"state": _state})
		for capability in _handshake_result["negotiated_capabilities"]:
			if not _handshake["capabilities"].has(capability):
				return _enter_failed("UNREQUESTED_CAPABILITY")
		for required_capability in REQUIRED_CAPABILITIES:
			if not _handshake_result["negotiated_capabilities"].has(required_capability):
				return _enter_failed("REQUIRED_CAPABILITY_NOT_NEGOTIATED")
		for contract_name in _handshake_result["contract_versions"].keys():
			if not _handshake["contract_versions"].has(contract_name):
				return _enter_failed("UNREQUESTED_CONTRACT_VERSION")
			if int(_handshake_result["contract_versions"][contract_name]) != int(_handshake["contract_versions"][contract_name]):
				return _enter_failed("NEGOTIATED_CONTRACT_VERSION_MISMATCH")
		for required_contract in REQUIRED_CONTRACTS:
			if not _handshake_result["contract_versions"].has(required_contract):
				return _enter_failed("REQUIRED_CONTRACT_NOT_NEGOTIATED")
		_session_id = String(_handshake_result["session_id"])
		_state = STATE_WAITING_SNAPSHOT
		return _success({"state": _state})
	if message_type == "SNAPSHOT":
		if _state != STATE_WAITING_SNAPSHOT or not _snapshot.is_empty():
			return _enter_failed("UNEXPECTED_SNAPSHOT")
		var validation: Dictionary = SnapshotScript.validate(payload)
		if not bool(validation.get("success", false)):
			return _send_rejected_ack(payload, String(validation.get("error_code", "INVALID_SNAPSHOT")))
		_snapshot = payload.duplicate(true)
		if String(_snapshot["authority_owner_id"]) != String(_handshake_result["authority_owner_id"]):
			return _send_rejected_ack(_snapshot, "AUTHORITY_OWNER_MISMATCH")
		if int(_snapshot["authority_epoch"]) != int(_handshake_result["authority_epoch"]):
			return _send_rejected_ack(_snapshot, "AUTHORITY_EPOCH_MISMATCH")
		if int(_snapshot["server_tick"]) > int(_handshake_result["server_tick"]):
			return _send_rejected_ack(_snapshot, "SERVER_TICK_MISMATCH")
		_ack = AckScript.create(
			_session_id,
			String(_snapshot["snapshot_id"]),
			String(_snapshot["entity_id"]),
			String(_snapshot["checksum"]),
			true,
			"",
			int(_snapshot["server_tick"])
		)
		var ack_send: Dictionary = _boundary.send("SNAPSHOT_ACK", _ack)
		if not bool(ack_send.get("success", false)):
			return _enter_failed(String(ack_send.get("error_code", "SNAPSHOT_ACK_SEND_FAILED")))
		_messages_sent += 1
		_ack_sent_at_ms = Time.get_ticks_msec()
		_state = STATE_ACK_SENT
		return _success({"state": _state})
	return _enter_failed("UNEXPECTED_MESSAGE_TYPE")


func _send_rejected_ack(snapshot: Dictionary, error_code: String) -> Dictionary:
	var snapshot_id: String = String(snapshot.get("snapshot_id", "snapshot/rejected"))
	var entity_id: String = String(snapshot.get("entity_id", "entity/rejected"))
	var checksum: String = String(snapshot.get("checksum", "0".repeat(64)))
	_ack = AckScript.create(_session_id, snapshot_id, entity_id, checksum, false, error_code, 0)
	var send_result: Dictionary = _boundary.send("SNAPSHOT_ACK", _ack)
	if bool(send_result.get("success", false)):
		_messages_sent += 1
	return _enter_failed(error_code)


func _enter_failed(error_code: String) -> Dictionary:
	_state = STATE_FAILED
	_failure_code = error_code if not error_code.is_empty() else "N1_CLIENT_FAILURE"
	return _failure(_failure_code, {"state": _state})


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}

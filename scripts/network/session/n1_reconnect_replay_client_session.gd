extends RefCounted

const BoundaryScript = preload("res://scripts/network/transports/network_transport_boundary.gd")
const EnetPortScript = preload("res://scripts/network/transports/enet_transport_port.gd")
const HandshakeScript = preload("res://scripts/network/contracts/network_handshake_envelope.gd")
const HandshakeResultScript = preload("res://scripts/network/contracts/network_handshake_result_envelope.gd")
const SnapshotScript = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")
const AckScript = preload("res://scripts/network/contracts/snapshot_ack_envelope.gd")
const CommandScript = preload("res://scripts/network/contracts/network_command_envelope.gd")
const ResultScript = preload("res://scripts/network/contracts/network_command_result_envelope.gd")
const DeltaScript = preload("res://scripts/network/contracts/entity_delta_envelope.gd")
const MovePayloadScript = preload("res://scripts/network/contracts/item_move_to_container_payload.gd")
const MoveResultScript = preload("res://scripts/network/contracts/item_move_to_container_result.gd")
const TicketScript = preload("res://scripts/network/contracts/network_resume_ticket.gd")
const ResumeScript = preload("res://scripts/network/contracts/network_session_resume_envelope.gd")
const ResumeResultScript = preload("res://scripts/network/contracts/network_session_resume_result.gd")

const STATE_STOPPED := "STOPPED"
const STATE_CONNECTING := "CONNECTING"
const STATE_HANDSHAKE_SENT := "HANDSHAKE_SENT"
const STATE_WAITING_SNAPSHOT := "WAITING_SNAPSHOT"
const STATE_WAITING_TICKET := "WAITING_TICKET"
const STATE_WAITING_COMMAND_LOSS := "WAITING_COMMAND_LOSS"
const STATE_WAITING_RESUME_RESULT := "WAITING_RESUME_RESULT"
const STATE_WAITING_REPLAY_RESULT := "WAITING_REPLAY_RESULT"
const STATE_WAITING_REPLAY_DELTA := "WAITING_REPLAY_DELTA"
const STATE_WAITING_REPLAY_DISCONNECT := "WAITING_REPLAY_DISCONNECT"
const STATE_FLUSHING := "FLUSHING"
const STATE_COMPLETE := "COMPLETE"
const STATE_REJECTED := "REJECTED"
const STATE_FAILED := "FAILED"
const FLUSH_GRACE_MS: int = 400
const SESSION_IDLE_TIMEOUT_MS: int = 6000
const COMMAND_TYPE: String = "item.move_to_container"
const OPERATION_ID: String = "operation/n1/reconnect-move/1"
const REQUIRED_RECONNECTS: int = 2
const REQUIRED_CAPABILITIES: Array[String] = [
	"handshake.v1", "snapshot.receive", "command.item_move_to_container", "delta.receive", "session.resume",
]
const REQUIRED_CONTRACTS: Array[String] = [
	"entity_delta", "entity_snapshot", "item_move_to_container", "network_command", "network_command_result",
	"network_handshake", "network_resume_ticket", "network_session_resume", "network_session_resume_result",
	"network_wire_frame", "snapshot_ack",
]

var _boundary
var _port
var _endpoint: Dictionary = {}
var _base_handshake: Dictionary = {}
var _active_handshake: Dictionary = {}
var _handshake_result: Dictionary = {}
var _snapshot: Dictionary = {}
var _initial_snapshot: Dictionary = {}
var _ticket: Dictionary = {}
var _primary_command: Dictionary = {}
var _replay_result: Dictionary = {}
var _primary_delta: Dictionary = {}
var _state: String = STATE_STOPPED
var _failure_code: String = ""
var _logical_session_id: String = ""
var _transport_session_id: String = ""
var _transport_session_ids: Array[String] = []
var _reconnect_count: int = 0
var _resume_accept_count: int = 0
var _commands_sent: int = 0
var _results_received: int = 0
var _deltas_received: int = 0
var _mutations_applied: int = 0
var _duplicate_delta_replays: int = 0
var _messages_sent: int = 0
var _messages_received: int = 0
var _events_processed: int = 0
var _final_ack_count: int = 0
var _unexpected_result_before_disconnect: bool = false
var _flush_started_at_ms: int = 0
var _last_progress_at_ms: int = 0


func configure(endpoint: Dictionary, handshake: Dictionary) -> Dictionary:
	if _state != STATE_STOPPED: return _failure("SESSION_NOT_STOPPED")
	var validation: Dictionary = HandshakeScript.validate(handshake)
	if not bool(validation.get("success", false)): return _failure(String(validation.get("error_code", "INVALID_HANDSHAKE")))
	_endpoint = endpoint.duplicate(true)
	_base_handshake = handshake.duplicate(true)
	return _configure_transport()


func start() -> Dictionary:
	if _boundary == null: return _failure("SESSION_NOT_CONFIGURED")
	return _connect(false)


func poll() -> Dictionary:
	if not is_terminal() and _last_progress_at_ms > 0 and Time.get_ticks_msec() - _last_progress_at_ms > SESSION_IDLE_TIMEOUT_MS:
		return _enter_failed("SESSION_IDLE_TIMEOUT_%s" % _state)
	if _state == STATE_FLUSHING and Time.get_ticks_msec() - _flush_started_at_ms >= FLUSH_GRACE_MS:
		_state = STATE_COMPLETE
	if _state in [STATE_STOPPED, STATE_COMPLETE, STATE_REJECTED, STATE_FAILED]: return _success({"state": _state, "terminal": true})
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
	return _state in [STATE_COMPLETE, STATE_REJECTED, STATE_FAILED]


func is_success() -> bool:
	return _state == STATE_COMPLETE


func get_report() -> Dictionary:
	var inventory: Dictionary = _snapshot.get("domain_components", {}).get("inventory", {}) if not _snapshot.is_empty() else {}
	return {
		"schema": "planet_simulator.n1_reconnect_replay_client_report.v1",
		"state": _state,
		"passed": is_success(),
		"failure_code": _failure_code,
		"logical_session_id": _logical_session_id,
		"transport_session_ids": _transport_session_ids.duplicate(),
		"unique_transport_sessions": _unique_count(_transport_session_ids),
		"reconnect_count": _reconnect_count,
		"resume_accept_count": _resume_accept_count,
		"entity_id": String(_snapshot.get("entity_id", "")),
		"command_item_id": String(inventory.get("command_item_id", "")),
		"initial_snapshot_checksum": String(_initial_snapshot.get("checksum", "")),
		"final_snapshot_checksum": String(_snapshot.get("checksum", "")),
		"snapshot_revision": int(_snapshot.get("state_revision", -1)),
		"server_tick": int(_snapshot.get("server_tick", -1)),
		"source_item_count": Array(inventory.get("source_item_ids", [])).size(),
		"destination_item_count": Array(inventory.get("destination_item_ids", [])).size(),
		"item_revision": int(inventory.get("item_revision", -1)),
		"commands_sent": _commands_sent,
		"results_received": _results_received,
		"deltas_received": _deltas_received,
		"mutations_applied": _mutations_applied,
		"duplicate_delta_replays": _duplicate_delta_replays,
		"messages_sent": _messages_sent,
		"messages_received": _messages_received,
		"events_processed": _events_processed,
		"final_ack_count": _final_ack_count,
		"unexpected_result_before_disconnect": _unexpected_result_before_disconnect,
		"ticket_id": String(_ticket.get("ticket_id", "")),
		"session_idle_timeout_ms": SESSION_IDLE_TIMEOUT_MS,
	}


func _configure_transport() -> Dictionary:
	_port = EnetPortScript.new()
	_boundary = BoundaryScript.new()
	return _boundary.configure(_port)


func _connect(reconnect: bool) -> Dictionary:
	if reconnect:
		_reconnect_count += 1
		_boundary.stop()
		var configured: Dictionary = _configure_transport()
		if not bool(configured.get("success", false)): return _enter_failed(String(configured.get("error_code", "TRANSPORT_RECONFIGURE_FAILED")))
	var result: Dictionary = _boundary.connect_client(_endpoint)
	if not bool(result.get("success", false)): return _enter_failed(String(result.get("error_code", "CLIENT_CONNECT_FAILED")))
	_state = STATE_CONNECTING
	_last_progress_at_ms = Time.get_ticks_msec()
	return _success({"state": _state})


func _handle_event(event: Dictionary) -> Dictionary:
	match String(event.get("type", "")):
		"CONNECTED":
			if _state != STATE_CONNECTING: return _enter_failed("UNEXPECTED_CONNECTED_EVENT")
			var ready: Dictionary = _boundary.mark_ready()
			if not bool(ready.get("success", false)): return _enter_failed(String(ready.get("error_code", "READY_TRANSITION_FAILED")))
			_active_handshake = _base_handshake.duplicate(true)
			_active_handshake["handshake_id"] = "handshake/n1/reconnect/%d" % _reconnect_count
			_active_handshake["checksum"] = HandshakeScript.compute_checksum(_active_handshake)
			var sent: Dictionary = _boundary.send("HANDSHAKE", _active_handshake)
			if not bool(sent.get("success", false)): return _enter_failed(String(sent.get("error_code", "HANDSHAKE_SEND_FAILED")))
			_messages_sent += 1
			_state = STATE_HANDSHAKE_SENT
		"MESSAGE":
			_messages_received += 1
			return _handle_message(String(event.get("message_type", "")), event.get("payload", {}))
		"MALFORMED_MESSAGE": return _enter_failed(String(event.get("error_code", "MALFORMED_MESSAGE")))
		"CONNECTION_FAILED": return _enter_failed("CONNECTION_FAILED")
		"DISCONNECTED":
			if _state in [STATE_WAITING_COMMAND_LOSS, STATE_WAITING_REPLAY_DISCONNECT]:
				return _connect(true)
			if _state in [STATE_FLUSHING, STATE_COMPLETE]:
				_state = STATE_COMPLETE
			elif _state != STATE_COMPLETE:
				return _enter_failed("SERVER_DISCONNECTED_EARLY")
	return _success()


func _handle_message(message_type: String, payload) -> Dictionary:
	if not payload is Dictionary: return _enter_failed("INVALID_MESSAGE_PAYLOAD")
	match message_type:
		"HANDSHAKE_RESULT": return _handle_handshake_result(payload)
		"SNAPSHOT": return _handle_snapshot(payload)
		"RESUME_TICKET": return _handle_ticket(payload)
		"SESSION_RESUME_RESULT": return _handle_resume_result(payload)
		"COMMAND_RESULT": return _handle_command_result(payload)
		"DELTA": return _handle_delta(payload)
	return _enter_failed("UNEXPECTED_MESSAGE_TYPE")


func _handle_handshake_result(payload: Dictionary) -> Dictionary:
	if _state != STATE_HANDSHAKE_SENT: return _enter_failed("UNEXPECTED_HANDSHAKE_RESULT")
	var validation: Dictionary = HandshakeResultScript.validate(payload)
	if not bool(validation.get("success", false)): return _enter_failed(String(validation.get("error_code", "INVALID_HANDSHAKE_RESULT")))
	if String(payload["handshake_id"]) != String(_active_handshake["handshake_id"]): return _enter_failed("HANDSHAKE_ID_MISMATCH")
	if not bool(payload["accepted"]):
		_state = STATE_REJECTED
		_failure_code = String(payload["error_code"])
		return _success()
	for capability in REQUIRED_CAPABILITIES:
		if not payload["negotiated_capabilities"].has(capability): return _enter_failed("REQUIRED_CAPABILITY_NOT_NEGOTIATED")
	for contract_name in REQUIRED_CONTRACTS:
		if not payload["contract_versions"].has(contract_name): return _enter_failed("REQUIRED_CONTRACT_NOT_NEGOTIATED")
	_transport_session_id = String(payload["session_id"])
	if _transport_session_ids.has(_transport_session_id): return _enter_failed("TRANSPORT_SESSION_REUSED")
	_transport_session_ids.append(_transport_session_id)
	_handshake_result = payload.duplicate(true)
	if _reconnect_count == 0:
		_logical_session_id = _transport_session_id
		_state = STATE_WAITING_SNAPSHOT
		return _success()
	if _transport_session_id == _logical_session_id: return _enter_failed("TRANSPORT_SESSION_NOT_ROTATED")
	return _send_resume()


func _handle_snapshot(payload: Dictionary) -> Dictionary:
	if _state != STATE_WAITING_SNAPSHOT or not _snapshot.is_empty(): return _enter_failed("UNEXPECTED_SNAPSHOT")
	var validation: Dictionary = SnapshotScript.validate(payload)
	if not bool(validation.get("success", false)): return _enter_failed(String(validation.get("error_code", "INVALID_SNAPSHOT")))
	_snapshot = payload.duplicate(true)
	_initial_snapshot = payload.duplicate(true)
	var ack: Dictionary = AckScript.create(
		_logical_session_id, String(_snapshot["snapshot_id"]), String(_snapshot["entity_id"]),
		String(_snapshot["checksum"]), true, "", int(_snapshot["server_tick"])
	)
	var sent: Dictionary = _boundary.send("SNAPSHOT_ACK", ack)
	if not bool(sent.get("success", false)): return _enter_failed(String(sent.get("error_code", "SNAPSHOT_ACK_SEND_FAILED")))
	_messages_sent += 1
	_state = STATE_WAITING_TICKET
	return _success()


func _handle_ticket(payload: Dictionary) -> Dictionary:
	if _state != STATE_WAITING_TICKET: return _enter_failed("UNEXPECTED_RESUME_TICKET")
	var validation: Dictionary = TicketScript.validate(payload)
	if not bool(validation.get("success", false)): return _enter_failed(String(validation.get("error_code", "INVALID_RESUME_TICKET")))
	if String(payload["logical_session_id"]) != _logical_session_id: return _enter_failed("TICKET_LOGICAL_SESSION_MISMATCH")
	if String(payload["client_node_id"]) != String(_base_handshake["client_node_id"]): return _enter_failed("TICKET_CLIENT_ID_MISMATCH")
	_ticket = payload.duplicate(true)
	return _send_primary_command()


func _handle_resume_result(payload: Dictionary) -> Dictionary:
	if _state != STATE_WAITING_RESUME_RESULT: return _enter_failed("UNEXPECTED_RESUME_RESULT")
	var validation: Dictionary = ResumeResultScript.validate(payload)
	if not bool(validation.get("success", false)): return _enter_failed(String(validation.get("error_code", "INVALID_RESUME_RESULT")))
	if String(payload["transport_session_id"]) != _transport_session_id: return _enter_failed("RESUME_RESULT_SESSION_MISMATCH")
	if String(payload["logical_session_id"]) != _logical_session_id: return _enter_failed("RESUME_RESULT_LOGICAL_SESSION_MISMATCH")
	if not bool(payload["accepted"]): return _enter_failed(String(payload["error_code"]))
	_resume_accept_count += 1
	var replay: Dictionary = _primary_command.duplicate(true)
	replay["message_id"] = "message/n1/reconnect/replay/%d" % _reconnect_count
	var sent: Dictionary = _boundary.send("COMMAND", replay)
	if not bool(sent.get("success", false)): return _enter_failed(String(sent.get("error_code", "REPLAY_COMMAND_SEND_FAILED")))
	_messages_sent += 1
	_commands_sent += 1
	_state = STATE_WAITING_REPLAY_RESULT
	return _success()


func _handle_command_result(payload: Dictionary) -> Dictionary:
	if _state == STATE_WAITING_COMMAND_LOSS:
		_unexpected_result_before_disconnect = true
		return _enter_failed("COMMAND_RESULT_WAS_NOT_LOST")
	if _state != STATE_WAITING_REPLAY_RESULT: return _enter_failed("UNEXPECTED_COMMAND_RESULT")
	var validation: Dictionary = ResultScript.validate(payload)
	if not bool(validation.get("success", false)): return _enter_failed(String(validation.get("error_code", "INVALID_COMMAND_RESULT")))
	if String(payload["operation_id"]) != OPERATION_ID or String(payload["status"]) != "SUCCEEDED": return _enter_failed("REPLAY_COMMAND_REJECTED")
	var move_validation: Dictionary = MoveResultScript.validate(payload["payload"])
	if not bool(move_validation.get("success", false)): return _enter_failed(String(move_validation.get("error_code", "INVALID_MOVE_RESULT")))
	if not _replay_result.is_empty():
		var previous: Dictionary = _replay_result.duplicate(true)
		var current: Dictionary = payload.duplicate(true)
		previous.erase("message_id")
		current.erase("message_id")
		if previous != current: return _enter_failed("REPLAY_RESULT_CHANGED")
	_replay_result = payload.duplicate(true)
	_results_received += 1
	_state = STATE_WAITING_REPLAY_DELTA
	return _success()


func _handle_delta(payload: Dictionary) -> Dictionary:
	if _state != STATE_WAITING_REPLAY_DELTA: return _enter_failed("UNEXPECTED_DELTA")
	var validation: Dictionary = DeltaScript.validate(payload)
	if not bool(validation.get("success", false)): return _enter_failed(String(validation.get("error_code", "INVALID_DELTA")))
	if String(payload["delta_id"]) != String(_replay_result["payload"]["delta_id"]): return _enter_failed("DELTA_ID_MISMATCH")
	_deltas_received += 1
	if _primary_delta.is_empty():
		var applied: Dictionary = DeltaScript.apply_to_snapshot(_snapshot, payload)
		if not bool(applied.get("success", false)): return _enter_failed(String(applied.get("error_code", "DELTA_APPLY_FAILED")))
		_snapshot = applied["snapshot"].duplicate(true)
		if String(_snapshot["checksum"]) != String(_replay_result["payload"]["result_snapshot_checksum"]): return _enter_failed("FINAL_CHECKSUM_MISMATCH")
		_primary_delta = payload.duplicate(true)
		_mutations_applied += 1
	else:
		if String(payload["checksum"]) != String(_primary_delta["checksum"]): return _enter_failed("REPLAY_DELTA_CHANGED")
		_duplicate_delta_replays += 1
	var ack: Dictionary = AckScript.create(
		_transport_session_id, String(_snapshot["snapshot_id"]), String(_snapshot["entity_id"]),
		String(_snapshot["checksum"]), true, "", int(_snapshot["server_tick"])
	)
	var sent: Dictionary = _boundary.send("SNAPSHOT_ACK", ack)
	if not bool(sent.get("success", false)): return _enter_failed(String(sent.get("error_code", "FINAL_ACK_SEND_FAILED")))
	_messages_sent += 1
	_final_ack_count += 1
	if _reconnect_count < REQUIRED_RECONNECTS:
		_state = STATE_WAITING_REPLAY_DISCONNECT
	else:
		_state = STATE_FLUSHING
		_flush_started_at_ms = Time.get_ticks_msec()
	return _success()


func _send_primary_command() -> Dictionary:
	var inventory = _snapshot.get("domain_components", {}).get("inventory", {})
	if not inventory is Dictionary: return _enter_failed("INITIAL_INVENTORY_PROJECTION_MISSING")
	var move_payload: Dictionary = MovePayloadScript.create(
		_logical_session_id, String(_snapshot["authority_owner_id"]), String(inventory["command_item_id"]),
		String(inventory["source_container_id"]), String(inventory["destination_container_id"]), int(inventory["item_revision"])
	)
	_primary_command = CommandScript.create(
		"message/n1/reconnect/primary", OPERATION_ID, String(_snapshot["entity_id"]), COMMAND_TYPE, move_payload,
		int(_snapshot["state_revision"]), int(_snapshot["authority_epoch"]), int(_snapshot["server_tick"]), Time.get_ticks_msec()
	)
	var sent: Dictionary = _boundary.send("COMMAND", _primary_command)
	if not bool(sent.get("success", false)): return _enter_failed(String(sent.get("error_code", "COMMAND_SEND_FAILED")))
	_messages_sent += 1
	_commands_sent += 1
	_state = STATE_WAITING_COMMAND_LOSS
	return _success()


func _send_resume() -> Dictionary:
	var resume: Dictionary = ResumeScript.create(
		"resume/n1/%d" % _reconnect_count,
		_ticket,
		_transport_session_id,
		OPERATION_ID,
		CommandScript.command_fingerprint(_primary_command),
		String(_snapshot["checksum"])
	)
	var sent: Dictionary = _boundary.send("SESSION_RESUME", resume)
	if not bool(sent.get("success", false)): return _enter_failed(String(sent.get("error_code", "SESSION_RESUME_SEND_FAILED")))
	_messages_sent += 1
	_state = STATE_WAITING_RESUME_RESULT
	return _success()


func _unique_count(values: Array[String]) -> int:
	var unique: Dictionary = {}
	for value in values: unique[value] = true
	return unique.size()


func _enter_failed(error_code: String) -> Dictionary:
	_state = STATE_FAILED
	_failure_code = error_code if not error_code.is_empty() else "N1_RECONNECT_CLIENT_FAILURE"
	return _failure(_failure_code, {"state": _state})


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}

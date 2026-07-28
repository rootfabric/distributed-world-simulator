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

const STATE_STOPPED: String = "STOPPED"
const STATE_CONNECTING: String = "CONNECTING"
const STATE_HANDSHAKE_SENT: String = "HANDSHAKE_SENT"
const STATE_WAITING_SNAPSHOT: String = "WAITING_SNAPSHOT"
const STATE_WAITING_COMMAND_RESULT: String = "WAITING_COMMAND_RESULT"
const STATE_WAITING_DELTA: String = "WAITING_DELTA"
const STATE_WAITING_REPLAY_RESULT: String = "WAITING_REPLAY_RESULT"
const STATE_WAITING_REPLAY_DELTA: String = "WAITING_REPLAY_DELTA"
const STATE_WAITING_STALE_RESULT: String = "WAITING_STALE_RESULT"
const STATE_FLUSHING: String = "FLUSHING"
const STATE_COMPLETE: String = "COMPLETE"
const STATE_REJECTED: String = "REJECTED"
const STATE_FAILED: String = "FAILED"
const FLUSH_GRACE_MS: int = 300
const COMMAND_TYPE: String = "item.move_to_container"
const PRIMARY_OPERATION_ID: String = "operation/n1/move-to-container/1"
const STALE_OPERATION_ID: String = "operation/n1/stale-revision/1"
const REQUIRED_CAPABILITIES: Array[String] = [
	"handshake.v1", "snapshot.receive", "command.item_move_to_container", "delta.receive",
]
const REQUIRED_CONTRACTS: Array[String] = [
	"entity_delta", "entity_snapshot", "item_move_to_container", "network_command",
	"network_command_result", "network_handshake", "network_wire_frame", "snapshot_ack",
]

var _boundary
var _port
var _endpoint: Dictionary = {}
var _handshake: Dictionary = {}
var _handshake_result: Dictionary = {}
var _snapshot: Dictionary = {}
var _initial_snapshot: Dictionary = {}
var _ack: Dictionary = {}
var _state: String = STATE_STOPPED
var _failure_code: String = ""
var _session_id: String = ""
var _events_processed: int = 0
var _messages_sent: int = 0
var _messages_received: int = 0
var _commands_sent: int = 0
var _results_received: int = 0
var _deltas_received: int = 0
var _mutations_applied: int = 0
var _duplicate_delta_replays: int = 0
var _stale_revision_rejected: bool = false
var _primary_command: Dictionary = {}
var _primary_result: Dictionary = {}
var _primary_delta: Dictionary = {}
var _pending_result: Dictionary = {}
var _flush_started_at_ms: int = 0


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
	if _state == STATE_FLUSHING and Time.get_ticks_msec() - _flush_started_at_ms >= FLUSH_GRACE_MS:
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
	var inventory: Dictionary = _snapshot.get("domain_components", {}).get("inventory", {}) if not _snapshot.is_empty() else {}
	return {
		"schema": "planet_simulator.n1_remote_item_client_report.v1",
		"state": _state,
		"passed": is_success(),
		"failure_code": _failure_code,
		"session_id": _session_id,
		"entity_id": String(_snapshot.get("entity_id", "")),
		"command_item_id": String(inventory.get("command_item_id", "")),
		"initial_snapshot_checksum": String(_initial_snapshot.get("checksum", "")),
		"final_snapshot_checksum": String(_snapshot.get("checksum", "")),
		"snapshot_revision": int(_snapshot.get("state_revision", -1)),
		"authority_owner_id": String(_snapshot.get("authority_owner_id", "")),
		"authority_epoch": int(_snapshot.get("authority_epoch", -1)),
		"server_tick": int(_snapshot.get("server_tick", -1)),
		"source_item_count": Array(inventory.get("source_item_ids", [])).size(),
		"destination_item_count": Array(inventory.get("destination_item_ids", [])).size(),
		"item_revision": int(inventory.get("item_revision", -1)),
		"events_processed": _events_processed,
		"messages_sent": _messages_sent,
		"messages_received": _messages_received,
		"commands_sent": _commands_sent,
		"results_received": _results_received,
		"deltas_received": _deltas_received,
		"mutations_applied": _mutations_applied,
		"duplicate_delta_replays": _duplicate_delta_replays,
		"stale_revision_rejected": _stale_revision_rejected,
		"handshake_accepted": bool(_handshake_result.get("accepted", false)),
		"snapshot_ack_accepted": bool(_ack.get("accepted", false)),
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
			if _state in [STATE_FLUSHING, STATE_COMPLETE]:
				_state = STATE_COMPLETE
			elif _state != STATE_COMPLETE:
				return _enter_failed("SERVER_DISCONNECTED_EARLY")
	return _success()


func _handle_message(message_type: String, payload) -> Dictionary:
	if not payload is Dictionary:
		return _enter_failed("INVALID_MESSAGE_PAYLOAD")
	match message_type:
		"HANDSHAKE_RESULT":
			return _handle_handshake_result(payload)
		"SNAPSHOT":
			return _handle_snapshot(payload)
		"COMMAND_RESULT":
			return _handle_command_result(payload)
		"DELTA":
			return _handle_delta(payload)
	return _enter_failed("UNEXPECTED_MESSAGE_TYPE")


func _handle_handshake_result(payload: Dictionary) -> Dictionary:
	if _state != STATE_HANDSHAKE_SENT or not _handshake_result.is_empty():
		return _enter_failed("UNEXPECTED_HANDSHAKE_RESULT")
	var validation: Dictionary = HandshakeResultScript.validate(payload)
	if not bool(validation.get("success", false)):
		return _enter_failed(String(validation.get("error_code", "INVALID_HANDSHAKE_RESULT")))
	_handshake_result = payload.duplicate(true)
	if String(_handshake_result["handshake_id"]) != String(_handshake["handshake_id"]):
		return _enter_failed("HANDSHAKE_ID_MISMATCH")
	if not bool(_handshake_result["accepted"]):
		_failure_code = String(_handshake_result["error_code"])
		_state = STATE_REJECTED
		return _success({"state": _state})
	for capability in REQUIRED_CAPABILITIES:
		if not _handshake_result["negotiated_capabilities"].has(capability):
			return _enter_failed("REQUIRED_CAPABILITY_NOT_NEGOTIATED")
	for contract_name in REQUIRED_CONTRACTS:
		if not _handshake_result["contract_versions"].has(contract_name):
			return _enter_failed("REQUIRED_CONTRACT_NOT_NEGOTIATED")
		if int(_handshake_result["contract_versions"][contract_name]) != int(_handshake["contract_versions"][contract_name]):
			return _enter_failed("NEGOTIATED_CONTRACT_VERSION_MISMATCH")
	_session_id = String(_handshake_result["session_id"])
	_state = STATE_WAITING_SNAPSHOT
	return _success({"state": _state})


func _handle_snapshot(payload: Dictionary) -> Dictionary:
	if _state != STATE_WAITING_SNAPSHOT or not _snapshot.is_empty():
		return _enter_failed("UNEXPECTED_SNAPSHOT")
	var validation: Dictionary = SnapshotScript.validate(payload)
	if not bool(validation.get("success", false)):
		return _enter_failed(String(validation.get("error_code", "INVALID_SNAPSHOT")))
	_snapshot = payload.duplicate(true)
	_initial_snapshot = payload.duplicate(true)
	if String(_snapshot["authority_owner_id"]) != String(_handshake_result["authority_owner_id"]):
		return _enter_failed("AUTHORITY_OWNER_MISMATCH")
	if int(_snapshot["authority_epoch"]) != int(_handshake_result["authority_epoch"]):
		return _enter_failed("AUTHORITY_EPOCH_MISMATCH")
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
	return _send_primary_command()


func _handle_command_result(payload: Dictionary) -> Dictionary:
	var validation: Dictionary = ResultScript.validate(payload)
	if not bool(validation.get("success", false)):
		return _enter_failed(String(validation.get("error_code", "INVALID_COMMAND_RESULT")))
	_results_received += 1
	var result: Dictionary = payload.duplicate(true)
	match _state:
		STATE_WAITING_COMMAND_RESULT:
			if String(result["operation_id"]) != PRIMARY_OPERATION_ID or String(result["status"]) != "SUCCEEDED":
				return _enter_failed("PRIMARY_COMMAND_REJECTED")
			var payload_validation: Dictionary = MoveResultScript.validate(result["payload"])
			if not bool(payload_validation.get("success", false)):
				return _enter_failed(String(payload_validation.get("error_code", "INVALID_MOVE_RESULT")))
			_primary_result = result.duplicate(true)
			_pending_result = result.duplicate(true)
			_state = STATE_WAITING_DELTA
			return _success()
		STATE_WAITING_REPLAY_RESULT:
			if String(result["operation_id"]) != PRIMARY_OPERATION_ID or String(result["status"]) != "SUCCEEDED":
				return _enter_failed("REPLAY_COMMAND_REJECTED")
			var original: Dictionary = _primary_result.duplicate(true)
			var replay: Dictionary = result.duplicate(true)
			original.erase("message_id")
			replay.erase("message_id")
			if original != replay:
				return _enter_failed("REPLAY_RESULT_CHANGED")
			_pending_result = result.duplicate(true)
			_state = STATE_WAITING_REPLAY_DELTA
			return _success()
		STATE_WAITING_STALE_RESULT:
			if String(result["operation_id"]) != STALE_OPERATION_ID:
				return _enter_failed("STALE_RESULT_OPERATION_MISMATCH")
			if String(result["status"]) != "REJECTED" or String(result["error_code"]) != "REVISION_CONFLICT":
				return _enter_failed("STALE_REVISION_NOT_REJECTED")
			if int(result["result_revision"]) != int(_snapshot["state_revision"]):
				return _enter_failed("STALE_RESULT_REVISION_MISMATCH")
			_stale_revision_rejected = true
			_state = STATE_FLUSHING
			_flush_started_at_ms = Time.get_ticks_msec()
			return _success()
	return _enter_failed("UNEXPECTED_COMMAND_RESULT")


func _handle_delta(payload: Dictionary) -> Dictionary:
	var validation: Dictionary = DeltaScript.validate(payload)
	if not bool(validation.get("success", false)):
		return _enter_failed(String(validation.get("error_code", "INVALID_DELTA")))
	_deltas_received += 1
	var delta: Dictionary = payload.duplicate(true)
	if _state == STATE_WAITING_DELTA:
		if String(delta["delta_id"]) != String(_pending_result["payload"]["delta_id"]):
			return _enter_failed("DELTA_ID_MISMATCH")
		var applied: Dictionary = DeltaScript.apply_to_snapshot(_snapshot, delta)
		if not bool(applied.get("success", false)):
			return _enter_failed(String(applied.get("error_code", "DELTA_APPLY_FAILED")))
		_snapshot = applied["snapshot"].duplicate(true)
		if String(_snapshot["checksum"]) != String(_pending_result["payload"]["result_snapshot_checksum"]):
			return _enter_failed("RESULT_SNAPSHOT_CHECKSUM_MISMATCH")
		_primary_delta = delta.duplicate(true)
		_mutations_applied += 1
		return _send_replay_command()
	if _state == STATE_WAITING_REPLAY_DELTA:
		if String(delta["delta_id"]) != String(_primary_delta["delta_id"]):
			return _enter_failed("REPLAY_DELTA_ID_MISMATCH")
		if String(delta["checksum"]) != String(_primary_delta["checksum"]):
			return _enter_failed("REPLAY_DELTA_CONFLICT")
		if String(_snapshot["checksum"]) != String(_pending_result["payload"]["result_snapshot_checksum"]):
			return _enter_failed("REPLAY_RESULT_CHECKSUM_MISMATCH")
		_duplicate_delta_replays += 1
		return _send_stale_command()
	return _enter_failed("UNEXPECTED_DELTA")


func _send_primary_command() -> Dictionary:
	var inventory = _snapshot.get("domain_components", {}).get("inventory", {})
	if not inventory is Dictionary:
		return _enter_failed("INITIAL_INVENTORY_PROJECTION_MISSING")
	var move_payload: Dictionary = MovePayloadScript.create(
		_session_id,
		String(_snapshot["authority_owner_id"]),
		String(inventory["command_item_id"]),
		String(inventory["source_container_id"]),
		String(inventory["destination_container_id"]),
		int(inventory["item_revision"])
	)
	_primary_command = CommandScript.create(
		"message/n1/command/1",
		PRIMARY_OPERATION_ID,
		String(_snapshot["entity_id"]),
		COMMAND_TYPE,
		move_payload,
		int(_snapshot["state_revision"]),
		int(_snapshot["authority_epoch"]),
		int(_snapshot["server_tick"]),
		Time.get_ticks_msec()
	)
	var send_result: Dictionary = _boundary.send("COMMAND", _primary_command)
	if not bool(send_result.get("success", false)):
		return _enter_failed(String(send_result.get("error_code", "COMMAND_SEND_FAILED")))
	_messages_sent += 1
	_commands_sent += 1
	_state = STATE_WAITING_COMMAND_RESULT
	return _success({"state": _state})


func _send_replay_command() -> Dictionary:
	var replay: Dictionary = _primary_command.duplicate(true)
	replay["message_id"] = "message/n1/command/replay"
	var send_result: Dictionary = _boundary.send("COMMAND", replay)
	if not bool(send_result.get("success", false)):
		return _enter_failed(String(send_result.get("error_code", "REPLAY_COMMAND_SEND_FAILED")))
	_messages_sent += 1
	_commands_sent += 1
	_state = STATE_WAITING_REPLAY_RESULT
	return _success({"state": _state})


func _send_stale_command() -> Dictionary:
	var stale: Dictionary = _primary_command.duplicate(true)
	stale["message_id"] = "message/n1/command/stale"
	stale["operation_id"] = STALE_OPERATION_ID
	stale["sent_at_monotonic_ms"] = Time.get_ticks_msec()
	var send_result: Dictionary = _boundary.send("COMMAND", stale)
	if not bool(send_result.get("success", false)):
		return _enter_failed(String(send_result.get("error_code", "STALE_COMMAND_SEND_FAILED")))
	_messages_sent += 1
	_commands_sent += 1
	_state = STATE_WAITING_STALE_RESULT
	return _success({"state": _state})


func _enter_failed(error_code: String) -> Dictionary:
	_state = STATE_FAILED
	_failure_code = error_code if not error_code.is_empty() else "N1_REMOTE_ITEM_CLIENT_FAILURE"
	return _failure(_failure_code, {"state": _state})


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}

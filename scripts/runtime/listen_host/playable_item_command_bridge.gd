extends RefCounted

const CommandEnvelope = preload("res://scripts/network/contracts/network_command_envelope.gd")
const ResultEnvelope = preload("res://scripts/network/contracts/network_command_result_envelope.gd")

const SCHEMA: String = "planet_simulator.playable_item_command_bridge.v1"

var _client_runtime
var _entity_id: String = ""
var _session_id: String = ""
var _message_sequence: int = 0
var _commands_sent: int = 0
var _deltas_applied: int = 0
var _rejections: int = 0


func setup(client_runtime_reference, entity_id: String, session_id: String) -> Dictionary:
	if client_runtime_reference == null or not client_runtime_reference is RefCounted:
		return _failure("INVALID_CLIENT_RUNTIME")
	for method_name in ["get_snapshot", "submit_command", "accept_delta"]:
		if not client_runtime_reference.has_method(method_name):
			return _failure("CLIENT_RUNTIME_METHOD_MISSING", {"method": method_name})
	if entity_id.strip_edges().is_empty() or session_id.strip_edges().is_empty():
		return _failure("PLAYABLE_BRIDGE_ID_REQUIRED")
	_client_runtime = client_runtime_reference
	_entity_id = entity_id
	_session_id = session_id
	_message_sequence = 0
	_commands_sent = 0
	_deltas_applied = 0
	_rejections = 0
	return _success()


func submit_item_command(
	command_type: String,
	payload: Dictionary,
	operation_id: String
) -> Dictionary:
	if _client_runtime == null:
		return _failure("PLAYABLE_BRIDGE_NOT_CONFIGURED")
	if command_type.strip_edges().is_empty() or operation_id.strip_edges().is_empty():
		return _failure("PLAYABLE_COMMAND_ID_REQUIRED")
	var snapshot: Dictionary = _client_runtime.get_snapshot(_entity_id)
	if snapshot.is_empty():
		return _failure("ITEM_GRAPH_REPLICA_MISSING")
	_message_sequence += 1
	var command_payload: Dictionary = payload.duplicate(true)
	command_payload["session_id"] = _session_id
	var command: Dictionary = CommandEnvelope.create(
		"message/h1/item/%d" % _message_sequence,
		operation_id,
		_entity_id,
		command_type,
		command_payload,
		int(snapshot.get("state_revision", -1)),
		int(snapshot.get("authority_epoch", -1)),
		int(snapshot.get("server_tick", 0)),
		Time.get_ticks_msec()
	)
	var submitted: Dictionary = _client_runtime.submit_command(command)
	_commands_sent += 1
	if not bool(submitted.get("success", false)):
		return _failure(
			String(submitted.get("error_code", "PLAYABLE_COMMAND_SEND_FAILED")),
			submitted.get("details", {})
		)
	var result: Dictionary = submitted.get("details", {}).get("result", {})
	var result_validation: Dictionary = ResultEnvelope.validate(result)
	if not bool(result_validation.get("success", false)):
		return _failure("INVALID_PLAYABLE_COMMAND_RESULT", {
			"validation_error_code": String(result_validation.get("error_code", "")),
		})
	var result_payload: Dictionary = Dictionary(result.get("payload", {}))
	var delta_value = result_payload.get("replication_delta", {})
	if delta_value is Dictionary and not Dictionary(delta_value).is_empty():
		var delivery: Dictionary = _client_runtime.accept_delta(Dictionary(delta_value))
		if not bool(delivery.get("success", false)):
			return _failure(
				String(delivery.get("error_code", "PLAYABLE_DELTA_REJECTED")),
				delivery.get("details", {})
			)
		_deltas_applied += 1
	var operation_result_value = result_payload.get("operation_result", {})
	var operation_result: Dictionary = (
		Dictionary(operation_result_value).duplicate(true)
		if operation_result_value is Dictionary
		else {}
	)
	if operation_result.is_empty():
		operation_result = {
			"success": String(result.get("status", "")) == "SUCCEEDED",
			"error_code": String(result.get("error_code", "")),
		}
	if String(result.get("status", "")) != "SUCCEEDED":
		_rejections += 1
		operation_result["success"] = false
		if String(operation_result.get("error_code", "")).is_empty():
			operation_result["error_code"] = String(result.get("error_code", "COMMAND_REJECTED"))
	operation_result["replica_snapshot"] = _client_runtime.get_snapshot(_entity_id)
	operation_result["network_result"] = result.duplicate(true)
	return operation_result


func invalidate() -> void:
	_client_runtime = null


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"configured": _client_runtime != null,
		"entity_id": _entity_id,
		"session_id": _session_id,
		"commands_sent": _commands_sent,
		"deltas_applied": _deltas_applied,
		"rejections": _rejections,
		"direct_authority_references": 0,
		"direct_domain_references": 0,
	}


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}

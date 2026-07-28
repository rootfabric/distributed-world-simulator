extends RefCounted

const CommandScript = preload("res://scripts/network/contracts/network_command_envelope.gd")
const ResultScript = preload("res://scripts/network/contracts/network_command_result_envelope.gd")
const MovePayloadScript = preload("res://scripts/network/contracts/item_move_to_container_payload.gd")

const SCHEMA: String = "planet_simulator.client_command_gateway.v1"
const COMMAND_TYPE: String = "item.move_to_container"
const USE_REPLICA_REVISION: int = -9223372036854775807

var _command_transport
var _replica_store
var _session_id: String = ""
var _commands_sent: int = 0
var _results_received: int = 0


func setup(command_transport_reference, replica_store_reference, session_id: String) -> Dictionary:
	if command_transport_reference == null or not command_transport_reference is RefCounted:
		return _failure("INVALID_COMMAND_TRANSPORT")
	if not command_transport_reference.has_method("send"):
		return _failure("COMMAND_TRANSPORT_SEND_MISSING")
	if replica_store_reference == null or not replica_store_reference is RefCounted:
		return _failure("INVALID_REPLICA_STORE")
	if not replica_store_reference.has_method("get_snapshot"):
		return _failure("REPLICA_STORE_GET_MISSING")
	if session_id.strip_edges().is_empty():
		return _failure("SESSION_ID_REQUIRED")
	_command_transport = command_transport_reference
	_replica_store = replica_store_reference
	_session_id = session_id
	_commands_sent = 0
	_results_received = 0
	return _success()


func send_item_move_to_container(
	entity_id: String,
	message_id: String,
	operation_id: String,
	expected_revision_override: int = USE_REPLICA_REVISION
) -> Dictionary:
	if _command_transport == null or _replica_store == null:
		return _failure("CLIENT_COMMAND_GATEWAY_NOT_CONFIGURED")
	var replica_result: Dictionary = _replica_store.get_snapshot(entity_id)
	if not bool(replica_result.get("success", false)):
		return _failure(String(replica_result.get("error_code", "CLIENT_REPLICA_NOT_FOUND")))
	var snapshot: Dictionary = replica_result.get("details", {}).get("snapshot", {})
	var inventory = snapshot.get("domain_components", {}).get("inventory", {})
	if not inventory is Dictionary:
		return _failure("INVENTORY_REPLICA_MISSING")
	var payload: Dictionary = MovePayloadScript.create(
		_session_id,
		String(snapshot.get("authority_owner_id", "")),
		String(inventory.get("command_item_id", "")),
		String(inventory.get("source_container_id", "")),
		String(inventory.get("destination_container_id", "")),
		int(inventory.get("item_revision", -1))
	)
	var expected_revision: int = int(snapshot.get("state_revision", -1))
	if expected_revision_override != USE_REPLICA_REVISION:
		expected_revision = expected_revision_override
	var command: Dictionary = CommandScript.create(
		message_id,
		operation_id,
		entity_id,
		COMMAND_TYPE,
		payload,
		expected_revision,
		int(snapshot.get("authority_epoch", -1)),
		int(snapshot.get("server_tick", -1)),
		Time.get_ticks_msec()
	)
	return submit(command)


func submit(command_value: Dictionary) -> Dictionary:
	if _command_transport == null:
		return _failure("CLIENT_COMMAND_GATEWAY_NOT_CONFIGURED")
	var validation: Dictionary = CommandScript.validate(command_value)
	if not bool(validation.get("success", false)):
		return _failure(String(validation.get("error_code", "INVALID_COMMAND")))
	var command: Dictionary = CommandScript.normalize(command_value)
	var replica_result: Dictionary = _replica_store.get_snapshot(String(command["entity_id"]))
	if not bool(replica_result.get("success", false)):
		return _failure("COMMAND_TARGET_NOT_REPLICATED")
	var transport_result: Dictionary = _command_transport.send(command)
	_commands_sent += 1
	if not bool(transport_result.get("success", false)):
		return _failure(String(transport_result.get("error_code", "COMMAND_SEND_FAILED")), transport_result)
	var result: Dictionary = Dictionary(transport_result.get("result", {})).duplicate(true)
	var result_validation: Dictionary = ResultScript.validate(result)
	if not bool(result_validation.get("success", false)):
		return _failure(String(result_validation.get("error_code", "INVALID_COMMAND_RESULT")))
	_results_received += 1
	return _success({"command": command, "result": result})


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"session_id": _session_id,
		"commands_sent": _commands_sent,
		"results_received": _results_received,
		"direct_authority_references": 0,
		"direct_domain_references": 0,
	}


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}

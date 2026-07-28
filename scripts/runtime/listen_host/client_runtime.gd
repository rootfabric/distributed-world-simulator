extends RefCounted

const ReplicaStoreScript = preload("res://scripts/runtime/listen_host/client_replica_store.gd")
const CommandGatewayScript = preload("res://scripts/runtime/listen_host/client_command_gateway.gd")

const SCHEMA: String = "planet_simulator.client_runtime.v1"

var _replica_store
var _command_gateway
var _configured: bool = false


func setup(command_transport_reference, session_id: String) -> Dictionary:
	if _configured:
		return _failure("CLIENT_RUNTIME_ALREADY_CONFIGURED")
	_replica_store = ReplicaStoreScript.new()
	var replica_result: Dictionary = _replica_store.setup()
	if not bool(replica_result.get("success", false)):
		return replica_result
	_command_gateway = CommandGatewayScript.new()
	var gateway_result: Dictionary = _command_gateway.setup(
		command_transport_reference,
		_replica_store,
		session_id
	)
	if not bool(gateway_result.get("success", false)):
		_replica_store = null
		_command_gateway = null
		return gateway_result
	_configured = true
	return _success()


func accept_snapshot(snapshot: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("CLIENT_RUNTIME_NOT_CONFIGURED")
	return _replica_store.accept_snapshot(snapshot)


func accept_delta(delta: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("CLIENT_RUNTIME_NOT_CONFIGURED")
	return _replica_store.accept_delta(delta)


func send_item_move_to_container(
	entity_id: String,
	message_id: String,
	operation_id: String,
	expected_revision_override: int = CommandGatewayScript.USE_REPLICA_REVISION
) -> Dictionary:
	if not _configured:
		return _failure("CLIENT_RUNTIME_NOT_CONFIGURED")
	return _command_gateway.send_item_move_to_container(
		entity_id,
		message_id,
		operation_id,
		expected_revision_override
	)


func submit_command(command: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("CLIENT_RUNTIME_NOT_CONFIGURED")
	return _command_gateway.submit(command)


func get_snapshot(entity_id: String) -> Dictionary:
	if not _configured:
		return {}
	var result: Dictionary = _replica_store.get_snapshot(entity_id)
	if not bool(result.get("success", false)):
		return {}
	return result.get("details", {}).get("snapshot", {}).duplicate(true)


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"configured": _configured,
		"replica_store": _replica_store.get_report() if _replica_store != null else {},
		"command_gateway": _command_gateway.get_report() if _command_gateway != null else {},
		"direct_authority_references": 0,
		"direct_domain_references": 0,
		"presentation_reads_replica_only": true,
	}


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}

extends RefCounted

const AuthorityScript = preload("res://scripts/network/session/n1_remote_item_authority.gd")
const AuthorityAdapterScript = preload("res://scripts/runtime/listen_host/listen_host_authority_gateway_adapter.gd")
const CommandTransportScript = preload("res://scripts/network/loopback/loopback_command_transport.gd")
const ClientRuntimeScript = preload("res://scripts/runtime/listen_host/client_runtime.gd")
const MoveResultScript = preload("res://scripts/network/contracts/item_move_to_container_result.gd")

const SCHEMA: String = "planet_simulator.listen_host_runtime.v1"
const STATE_STOPPED: String = "STOPPED"
const STATE_READY: String = "READY"
const STATE_COMPLETE: String = "COMPLETE"
const STATE_FAILED: String = "FAILED"
const DEFAULT_SESSION_ID: String = "session/h0/listen-host/1"
const PRIMARY_OPERATION_ID: String = "operation/h0/move-to-container/1"
const STALE_OPERATION_ID: String = "operation/h0/stale-revision/1"

var _state: String = STATE_STOPPED
var _failure_code: String = ""
var _authority
var _authority_adapter
var _command_transport
var _client_runtime
var _entity_id: String = ""
var _initial_snapshot: Dictionary = {}
var _primary_result: Dictionary = {}
var _primary_delta: Dictionary = {}
var _initial_snapshot_delivered: bool = false
var _primary_delta_delivered: bool = false
var _replay_delta_fenced: bool = false
var _stale_revision_rejected: bool = false
var _boundary_round_trips: int = 0
var _alias_isolation_verified: bool = false


func setup(config: Dictionary = {}) -> Dictionary:
	if _state != STATE_STOPPED:
		return _failure("LISTEN_HOST_NOT_STOPPED")
	var owner_id: String = String(config.get("authority_owner_id", "listen-host-authority"))
	var authority_epoch: int = int(config.get("authority_epoch", 7))
	var server_tick: int = int(config.get("server_tick", AuthorityScript.INITIAL_SERVER_TICK))
	var session_id: String = String(config.get("session_id", DEFAULT_SESSION_ID))
	if owner_id.strip_edges().is_empty() or authority_epoch < 1 or server_tick < 0 or session_id.strip_edges().is_empty():
		return _failure("INVALID_LISTEN_HOST_CONFIGURATION")

	_authority = AuthorityScript.new()
	var authority_setup: Dictionary = _authority.setup(owner_id, authority_epoch, server_tick)
	if not bool(authority_setup.get("success", false)):
		return _enter_failed(String(authority_setup.get("error_code", "AUTHORITY_SETUP_FAILED")))
	var bind_result: Dictionary = _authority.bind_session(session_id)
	if not bool(bind_result.get("success", false)):
		return _enter_failed(String(bind_result.get("error_code", "AUTHORITY_SESSION_BIND_FAILED")))

	_authority_adapter = AuthorityAdapterScript.new()
	var adapter_result: Dictionary = _authority_adapter.setup(_authority)
	if not bool(adapter_result.get("success", false)):
		return _enter_failed(String(adapter_result.get("error_code", "AUTHORITY_ADAPTER_SETUP_FAILED")))

	_command_transport = CommandTransportScript.new()
	_command_transport.setup(_authority_adapter)
	_client_runtime = ClientRuntimeScript.new()
	var client_setup: Dictionary = _client_runtime.setup(_command_transport, session_id)
	if not bool(client_setup.get("success", false)):
		return _enter_failed(String(client_setup.get("error_code", "CLIENT_RUNTIME_SETUP_FAILED")))

	_initial_snapshot = _authority_adapter.create_snapshot()
	_entity_id = String(_initial_snapshot.get("entity_id", ""))
	var snapshot_delivery: Dictionary = _client_runtime.accept_snapshot(_initial_snapshot)
	if not bool(snapshot_delivery.get("success", false)):
		return _enter_failed(String(snapshot_delivery.get("error_code", "INITIAL_SNAPSHOT_DELIVERY_FAILED")))
	_initial_snapshot_delivered = true
	_boundary_round_trips += 1
	_alias_isolation_verified = _verify_alias_isolation()
	if not _alias_isolation_verified:
		return _enter_failed("CLIENT_SERVER_ALIAS_DETECTED")
	_state = STATE_READY
	return _success({"state": _state, "entity_id": _entity_id})


func run_vertical_scenario() -> Dictionary:
	if _state != STATE_READY:
		return _failure("LISTEN_HOST_NOT_READY")
	var primary: Dictionary = _client_runtime.send_item_move_to_container(
		_entity_id,
		"message/h0/command/1",
		PRIMARY_OPERATION_ID
	)
	if not bool(primary.get("success", false)):
		return _enter_failed(String(primary.get("error_code", "PRIMARY_COMMAND_FAILED")))
	var primary_command: Dictionary = primary.get("details", {}).get("command", {}).duplicate(true)
	_primary_result = primary.get("details", {}).get("result", {}).duplicate(true)
	if String(_primary_result.get("status", "")) != "SUCCEEDED":
		return _enter_failed("PRIMARY_COMMAND_REJECTED")
	var move_validation: Dictionary = MoveResultScript.validate(_primary_result.get("payload", {}))
	if not bool(move_validation.get("success", false)):
		return _enter_failed(String(move_validation.get("error_code", "INVALID_PRIMARY_RESULT_PAYLOAD")))
	_primary_delta = _authority_adapter.get_delta(PRIMARY_OPERATION_ID)
	if _primary_delta.is_empty():
		return _enter_failed("PRIMARY_DELTA_MISSING")
	var delta_delivery: Dictionary = _client_runtime.accept_delta(_primary_delta)
	if not bool(delta_delivery.get("success", false)) or bool(delta_delivery.get("details", {}).get("replay", true)):
		return _enter_failed(String(delta_delivery.get("error_code", "PRIMARY_DELTA_DELIVERY_FAILED")))
	_primary_delta_delivered = true
	_boundary_round_trips += 2
	var primary_snapshot: Dictionary = delta_delivery.get("details", {}).get("snapshot", {})
	if String(primary_snapshot.get("checksum", "")) != String(_primary_result.get("payload", {}).get("result_snapshot_checksum", "")):
		return _enter_failed("PRIMARY_RESULT_CHECKSUM_MISMATCH")

	var replay_command: Dictionary = primary_command.duplicate(true)
	replay_command["message_id"] = "message/h0/command/replay"
	replay_command["sent_at_monotonic_ms"] = Time.get_ticks_msec()
	var replay: Dictionary = _client_runtime.submit_command(replay_command)
	if not bool(replay.get("success", false)):
		return _enter_failed(String(replay.get("error_code", "REPLAY_COMMAND_FAILED")))
	var replay_result: Dictionary = replay.get("details", {}).get("result", {})
	if String(replay_result.get("status", "")) != "SUCCEEDED":
		return _enter_failed("REPLAY_COMMAND_REJECTED")
	var comparable_primary: Dictionary = _primary_result.duplicate(true)
	var comparable_replay: Dictionary = replay_result.duplicate(true)
	comparable_primary.erase("message_id")
	comparable_replay.erase("message_id")
	if comparable_primary != comparable_replay:
		return _enter_failed("REPLAY_RESULT_CHANGED")
	var replay_delta: Dictionary = _authority_adapter.get_delta(PRIMARY_OPERATION_ID)
	var replay_delivery: Dictionary = _client_runtime.accept_delta(replay_delta)
	if not bool(replay_delivery.get("success", false)) or not bool(replay_delivery.get("details", {}).get("replay", false)):
		return _enter_failed(String(replay_delivery.get("error_code", "REPLAY_DELTA_NOT_FENCED")))
	_replay_delta_fenced = true
	_boundary_round_trips += 2

	var stale: Dictionary = _client_runtime.send_item_move_to_container(
		_entity_id,
		"message/h0/command/stale",
		STALE_OPERATION_ID,
		int(_initial_snapshot.get("state_revision", -1))
	)
	if not bool(stale.get("success", false)):
		return _enter_failed(String(stale.get("error_code", "STALE_COMMAND_TRANSPORT_FAILED")))
	var stale_result: Dictionary = stale.get("details", {}).get("result", {})
	if String(stale_result.get("status", "")) != "REJECTED" or String(stale_result.get("error_code", "")) != "REVISION_CONFLICT":
		return _enter_failed("STALE_REVISION_NOT_REJECTED")
	_stale_revision_rejected = true
	_boundary_round_trips += 1

	var final_replica: Dictionary = _client_runtime.get_snapshot(_entity_id)
	if final_replica.is_empty():
		return _enter_failed("FINAL_REPLICA_MISSING")
	var final_authority: Dictionary = _authority_adapter.create_snapshot()
	if String(final_replica.get("checksum", "")) != String(final_authority.get("checksum", "")):
		return _enter_failed("CLIENT_SERVER_CHECKSUM_MISMATCH")
	if not _verify_alias_isolation():
		return _enter_failed("CLIENT_SERVER_ALIAS_DETECTED_AFTER_MUTATION")
	_state = STATE_COMPLETE
	return _success({"state": _state, "report": get_report()})


func get_report() -> Dictionary:
	var authority_report: Dictionary = _authority_adapter.get_authority_report() if _authority_adapter != null else {}
	var client_report: Dictionary = _client_runtime.get_report() if _client_runtime != null else {}
	var replica_report: Dictionary = client_report.get("replica_store", {})
	var gateway_report: Dictionary = client_report.get("command_gateway", {})
	var replica_snapshot: Dictionary = {}
	if _client_runtime != null and not _entity_id.is_empty():
		replica_snapshot = _client_runtime.get_snapshot(_entity_id)
	return {
		"schema": SCHEMA,
		"state": _state,
		"passed": _state == STATE_COMPLETE,
		"failure_code": _failure_code,
		"entity_id": _entity_id,
		"initial_snapshot_checksum": String(_initial_snapshot.get("checksum", "")),
		"client_snapshot_checksum": String(replica_snapshot.get("checksum", "")),
		"authority_snapshot_checksum": String(authority_report.get("snapshot_checksum", "")),
		"client_revision": int(replica_snapshot.get("state_revision", -1)),
		"authority_revision": int(authority_report.get("aggregate_revision", -1)),
		"server_tick": int(authority_report.get("server_tick", -1)),
		"authority_mutation_count": int(authority_report.get("mutation_count", 0)),
		"authority_handler_invocation_count": int(authority_report.get("handler_invocation_count", 0)),
		"operation_ledger_count": int(authority_report.get("operation_ledger_count", 0)),
		"initial_snapshot_delivered": _initial_snapshot_delivered,
		"primary_delta_delivered": _primary_delta_delivered,
		"replay_delta_fenced": _replay_delta_fenced,
		"stale_revision_rejected": _stale_revision_rejected,
		"boundary_round_trips": _boundary_round_trips,
		"alias_isolation_verified": _alias_isolation_verified,
		"client_runtime": client_report,
		"replica_store": replica_report,
		"client_gateway": gateway_report,
		"transport_kind": "LOOPBACK",
		"direct_client_domain_access": false,
	}


func get_client_snapshot() -> Dictionary:
	if _client_runtime == null or _entity_id.is_empty():
		return {}
	return _client_runtime.get_snapshot(_entity_id)


func get_authority_snapshot_for_diagnostics() -> Dictionary:
	return _authority_adapter.create_snapshot() if _authority_adapter != null else {}


func _verify_alias_isolation() -> bool:
	if _client_runtime == null or _authority_adapter == null or _entity_id.is_empty():
		return false
	var client_before: Dictionary = get_client_snapshot()
	var authority_before: Dictionary = _authority_adapter.create_snapshot()
	if client_before.is_empty() or authority_before.is_empty():
		return false
	var client_checksum: String = String(client_before.get("checksum", ""))
	var authority_checksum: String = String(authority_before.get("checksum", ""))
	client_before["domain_components"]["alias_probe"] = {"mutated": true}
	authority_before["domain_components"]["alias_probe"] = {"mutated": true}
	var client_after: Dictionary = get_client_snapshot()
	var authority_after: Dictionary = _authority_adapter.create_snapshot()
	return (
		String(client_after.get("checksum", "")) == client_checksum
		and String(authority_after.get("checksum", "")) == authority_checksum
		and not client_after.get("domain_components", {}).has("alias_probe")
		and not authority_after.get("domain_components", {}).has("alias_probe")
	)


func _enter_failed(error_code: String) -> Dictionary:
	_state = STATE_FAILED
	_failure_code = error_code if not error_code.is_empty() else "LISTEN_HOST_FAILURE"
	return _failure(_failure_code, {"state": _state})


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}

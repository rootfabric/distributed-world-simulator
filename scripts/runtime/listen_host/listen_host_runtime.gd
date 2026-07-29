extends RefCounted

const AuthorityScript = preload("res://scripts/network/session/n1_remote_item_authority.gd")
const AuthorityAdapterScript = preload("res://scripts/runtime/listen_host/listen_host_authority_gateway_adapter.gd")
const CommandTransportScript = preload("res://scripts/network/loopback/loopback_command_transport.gd")
const ClientRuntimeScript = preload("res://scripts/runtime/listen_host/client_runtime.gd")
const MoveResultScript = preload("res://scripts/network/contracts/item_move_to_container_result.gd")
const PlayableAuthorityScript = preload("res://scripts/runtime/listen_host/playable_listen_host_authority.gd")
const PlayableAuthorityAdapterScript = preload("res://scripts/runtime/listen_host/playable_authority_gateway_adapter.gd")
const PlayableItemBridgeScript = preload("res://scripts/runtime/listen_host/playable_item_command_bridge.gd")
const PlayableClientSessionScript = preload("res://scripts/runtime/listen_host/playable_client_session.gd")

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

var _playable_authority_host: Node
var _playable_authority
var _playable_authority_adapter
var _playable_command_transport
var _playable_client_runtime
var _playable_item_bridge
var _playable_client_session
var _playable_session_id: String = ""
var _playable_attached: bool = false
var _playable_attach_count: int = 0


func setup(config: Dictionary = {}) -> Dictionary:
	if _state != STATE_STOPPED:
		return _failure("LISTEN_HOST_NOT_STOPPED")
	var owner_id: String = String(config.get("authority_owner_id", "listen-host-authority"))
	var authority_epoch: int = int(config.get("authority_epoch", 7))
	var server_tick: int = int(config.get("server_tick", AuthorityScript.INITIAL_SERVER_TICK))
	var session_id: String = String(config.get("session_id", DEFAULT_SESSION_ID))
	if owner_id.strip_edges().is_empty() or authority_epoch < 1 or server_tick < 0 or session_id.strip_edges().is_empty():
		return _failure("INVALID_LISTEN_HOST_CONFIGURATION")
	var authority_host_value = config.get("authority_host")
	if authority_host_value != null and authority_host_value is Node:
		_playable_authority_host = authority_host_value

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
		"playable": get_playable_report(),
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


func attach_playable_world(config: Dictionary) -> Dictionary:
	if _playable_attached:
		var detached: Dictionary = detach_playable_world()
		if not bool(detached.get("success", false)):
			return detached
	if _playable_authority_host == null or not is_instance_valid(_playable_authority_host):
		return _failure("PLAYABLE_AUTHORITY_HOST_REQUIRED")
	_playable_session_id = String(
		config.get("session_id", "session/h1/playable-listen-host/1")
	).strip_edges()
	if _playable_session_id.is_empty():
		return _failure("PLAYABLE_SESSION_ID_REQUIRED")

	_playable_authority = PlayableAuthorityScript.new()
	_playable_authority.name = "H1PlayableAuthority"
	_playable_authority_host.add_child(_playable_authority)
	var authority_config: Dictionary = config.duplicate(true)
	authority_config["session_id"] = _playable_session_id
	var authority_setup: Dictionary = _playable_authority.setup(authority_config)
	if not bool(authority_setup.get("success", false)):
		_cleanup_playable_objects()
		return _failure(
			String(authority_setup.get("error_code", "PLAYABLE_AUTHORITY_SETUP_FAILED")),
			authority_setup.get("details", {})
		)

	_playable_authority_adapter = PlayableAuthorityAdapterScript.new()
	var adapter_setup: Dictionary = _playable_authority_adapter.setup(_playable_authority)
	if not bool(adapter_setup.get("success", false)):
		_cleanup_playable_objects()
		return adapter_setup
	_playable_command_transport = CommandTransportScript.new()
	_playable_command_transport.setup(_playable_authority_adapter)
	_playable_client_runtime = ClientRuntimeScript.new()
	var client_setup: Dictionary = _playable_client_runtime.setup(
		_playable_command_transport,
		_playable_session_id
	)
	if not bool(client_setup.get("success", false)):
		_cleanup_playable_objects()
		return client_setup

	for snapshot in _playable_authority.create_initial_snapshots():
		var delivered: Dictionary = _playable_client_runtime.accept_snapshot(snapshot)
		if not bool(delivered.get("success", false)):
			_cleanup_playable_objects()
			return _failure(
				String(delivered.get("error_code", "PLAYABLE_INITIAL_SNAPSHOT_REJECTED")),
				delivered.get("details", {})
			)

	_playable_item_bridge = PlayableItemBridgeScript.new()
	var bridge_setup: Dictionary = _playable_item_bridge.setup(
		_playable_client_runtime,
		PlayableAuthorityScript.ITEM_GRAPH_ENTITY_ID,
		_playable_session_id
	)
	if not bool(bridge_setup.get("success", false)):
		_cleanup_playable_objects()
		return bridge_setup
	_playable_client_session = PlayableClientSessionScript.new()
	var session_setup: Dictionary = _playable_client_session.setup(
		_playable_client_runtime,
		_playable_item_bridge,
		_playable_session_id
	)
	if not bool(session_setup.get("success", false)):
		_cleanup_playable_objects()
		return session_setup
	_playable_attached = true
	_playable_attach_count += 1
	return _success({
		"player_entity_id": PlayableAuthorityScript.PLAYER_ENTITY_ID,
		"item_graph_entity_id": PlayableAuthorityScript.ITEM_GRAPH_ENTITY_ID,
		"player_snapshot": get_playable_snapshot(PlayableAuthorityScript.PLAYER_ENTITY_ID),
		"item_snapshot": get_playable_snapshot(PlayableAuthorityScript.ITEM_GRAPH_ENTITY_ID),
	})


func detach_playable_world() -> Dictionary:
	if not _playable_attached and _playable_authority == null:
		return _success({"already_detached": true})
	var shutdown_result: Dictionary = _success()
	if _playable_authority != null and _playable_authority.has_method("shutdown"):
		shutdown_result = _playable_authority.shutdown()
	_cleanup_playable_objects()
	return shutdown_result


func get_playable_client_session():
	return _playable_client_session


func get_playable_item_bridge():
	return (
		_playable_client_session.get_item_bridge()
		if _playable_client_session != null
		else null
	)


func get_playable_snapshot(entity_id: String) -> Dictionary:
	if _playable_client_session == null:
		return {}
	return _playable_client_session.get_snapshot(entity_id)


func submit_player_state(
	player_state: Dictionary,
	delta_seconds: float,
	operation_id: String
) -> Dictionary:
	if not _playable_attached or _playable_client_session == null:
		return _failure("PLAYABLE_WORLD_NOT_ATTACHED")
	return _playable_client_session.submit_player_state(
		player_state, delta_seconds, operation_id
	)


func get_playable_report() -> Dictionary:
	var client_session_report: Dictionary = (
		_playable_client_session.get_report()
		if _playable_client_session != null
		else {}
	)
	var authority_report: Dictionary = (
		_playable_authority.get_report()
		if _playable_authority != null and _playable_authority.has_method("get_report")
		else {}
	)
	var client_report: Dictionary = (
		_playable_client_runtime.get_report()
		if _playable_client_runtime != null
		else {}
	)
	return {
		"schema": "planet_simulator.h1_playable_listen_host_report.v1",
		"attached": _playable_attached,
		"session_id": _playable_session_id,
		"attach_count": _playable_attach_count,
		"command_count": int(client_session_report.get("command_count", 0)),
		"delta_count": int(client_session_report.get("delta_count", 0)),
		"rejection_count": int(client_session_report.get("rejection_count", 0)),
		"authority": authority_report,
		"client_session": client_session_report,
		"client_runtime": client_report,
		"item_bridge": (
			_playable_item_bridge.get_report()
			if _playable_item_bridge != null
			else {}
		),
		"player_replica": get_playable_snapshot(PlayableAuthorityScript.PLAYER_ENTITY_ID),
		"item_replica": get_playable_snapshot(PlayableAuthorityScript.ITEM_GRAPH_ENTITY_ID),
		"direct_client_authority_access": false,
		"direct_client_domain_access": false,
	}


func get_playable_authority_world_entity_store_for_kernel():
	if _playable_authority == null:
		return null
	return _playable_authority.get_world_entity_store_for_kernel()


func _cleanup_playable_objects() -> void:
	if _playable_client_session != null and _playable_client_session.has_method("invalidate"):
		_playable_client_session.invalidate()
	_playable_client_session = null
	if _playable_item_bridge != null and _playable_item_bridge.has_method("invalidate"):
		_playable_item_bridge.invalidate()
	_playable_item_bridge = null
	_playable_client_runtime = null
	_playable_command_transport = null
	_playable_authority_adapter = null
	if _playable_authority != null and is_instance_valid(_playable_authority):
		if _playable_authority.get_parent() != null:
			_playable_authority.get_parent().remove_child(_playable_authority)
		_playable_authority.free()
	_playable_authority = null
	_playable_session_id = ""
	_playable_attached = false


func _enter_failed(error_code: String) -> Dictionary:
	_state = STATE_FAILED
	_failure_code = error_code if not error_code.is_empty() else "LISTEN_HOST_FAILURE"
	return _failure(_failure_code, {"state": _state})


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}

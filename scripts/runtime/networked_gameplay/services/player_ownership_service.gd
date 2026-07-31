extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const JoinCommand = preload("res://scripts/runtime/networked_gameplay/contracts/player_join_command.gd")
const LeaveCommand = preload("res://scripts/runtime/networked_gameplay/contracts/player_leave_command.gd")
const OwnershipSnapshot = preload("res://scripts/runtime/networked_gameplay/contracts/player_ownership_snapshot.gd")

const SCHEMA := "planet_simulator.player_ownership_service.v1"
const SNAPSHOT_SCHEMA := OwnershipSnapshot.SCHEMA
const DELTA_SCHEMA := "planet_simulator.player_ownership_delta.v1"
const DURABLE_SCHEMA := "planet_simulator.player_ownership_state.v1"
const REPLAY_SCHEMA := "planet_simulator.player_ownership_replay_state.v1"

var _authority_owner_id := ""
var _authority_epoch := 0
var _revision := 0
var _tick := 0
var _players: Dictionary = {}
var _session_to_player: Dictionary = {}
var _operation_ledger: Dictionary = {}


func setup(authority_owner_id: String, authority_epoch: int, server_tick: int = 0) -> Dictionary:
	if authority_owner_id.strip_edges().is_empty() or authority_epoch < 1 or server_tick < 0:
		return _failure("INVALID_OWNERSHIP_REGISTRY_CONFIGURATION")
	_authority_owner_id = authority_owner_id.strip_edges()
	_authority_epoch = authority_epoch
	_tick = server_tick
	_revision = 0
	_players.clear()
	_session_to_player.clear()
	_operation_ledger.clear()
	return _success({"snapshot": create_snapshot()})


func handle_join_command(command: Dictionary) -> Dictionary:
	var validation := JoinCommand.validate(command)
	if not bool(validation.get("success", false)):
		return _failure(String(validation.get("error_code", "INVALID_PLAYER_JOIN_COMMAND")))
	if int(command.get("authority_epoch", 0)) != _authority_epoch:
		return _failure("STALE_AUTHORITY_EPOCH")
	return _join(
		String(command.get("logical_player_id", "")),
		String(command.get("transport_session_id", "")),
		String(command.get("operation_id", "")),
		Utils.payload_hash(command)
	)


func handle_leave_command(command: Dictionary) -> Dictionary:
	var validation := LeaveCommand.validate(command)
	if not bool(validation.get("success", false)):
		return _failure(String(validation.get("error_code", "INVALID_PLAYER_LEAVE_COMMAND")))
	if int(command.get("authority_epoch", 0)) != _authority_epoch:
		return _failure("STALE_AUTHORITY_EPOCH")
	var logical_player_id := String(command.get("logical_player_id", ""))
	var record: Dictionary = _players.get(logical_player_id, {})
	if not record.is_empty() and int(command.get("ownership_epoch", 0)) != int(record.get("ownership_epoch", 0)):
		return _failure("STALE_PLAYER_OWNERSHIP_EPOCH")
	return _leave(
		logical_player_id,
		String(command.get("transport_session_id", "")),
		String(command.get("operation_id", "")),
		Utils.payload_hash(command)
	)


func join(logical_player_id: String, transport_session_id: String, operation_id: String) -> Dictionary:
	return handle_join_command(JoinCommand.create(
		"message/m1/ownership/join/%s" % operation_id.sha256_text().left(12),
		operation_id,
		logical_player_id,
		transport_session_id,
		_authority_epoch
	))


func leave(logical_player_id: String, transport_session_id: String, operation_id: String) -> Dictionary:
	var record: Dictionary = _players.get(logical_player_id.strip_edges().to_lower(), {})
	return handle_leave_command(LeaveCommand.create(
		"message/m1/ownership/leave/%s" % operation_id.sha256_text().left(12),
		operation_id,
		logical_player_id,
		transport_session_id,
		_authority_epoch,
		int(record.get("ownership_epoch", 1))
	))


func leave_transport_session(transport_session_id: String, operation_id: String) -> Dictionary:
	if not _session_to_player.has(transport_session_id):
		return _success({"replay": true, "snapshot": create_snapshot()})
	return leave(String(_session_to_player[transport_session_id]), transport_session_id, operation_id)


func create_snapshot() -> Dictionary:
	var players: Array = []
	var ids := _players.keys()
	ids.sort()
	for id in ids:
		players.append(Dictionary(_players[id]).duplicate(true))
	return OwnershipSnapshot.create(_authority_owner_id, _authority_epoch, _revision, _tick, players)


func validate_snapshot(snapshot: Dictionary) -> Dictionary:
	var validation := OwnershipSnapshot.validate_legacy(snapshot)
	if bool(validation.get("success", false)):
		return _success()
	var error_code := String(validation.get("error_code", "INVALID_OWNERSHIP_SNAPSHOT"))
	if error_code == "WIRE_CHECKSUM_MISMATCH":
		error_code = "OWNERSHIP_SNAPSHOT_CHECKSUM_MISMATCH"
	return _failure(error_code)


func get_player(logical_player_id: String) -> Dictionary:
	return Dictionary(_players.get(logical_player_id.strip_edges().to_lower(), {})).duplicate(true)


func get_player_for_session(transport_session_id: String) -> Dictionary:
	if not _session_to_player.has(transport_session_id):
		return {}
	return get_player(String(_session_to_player[transport_session_id]))


func get_players() -> Array:
	var result: Array = []
	var ids := _players.keys()
	ids.sort()
	for logical_id in ids:
		result.append(Dictionary(_players[logical_id]).duplicate(true))
	return result



func export_durable_state() -> Dictionary:
	var players: Array = []
	var ids := _players.keys()
	ids.sort()
	for id_value in ids:
		var record: Dictionary = Dictionary(_players[id_value]).duplicate(true)
		record["connected"] = false
		record["transport_session_id"] = ""
		players.append(record)
	var state: Dictionary = {
		"schema": DURABLE_SCHEMA,
		"authority_owner_id": _authority_owner_id,
		"authority_epoch": _authority_epoch,
		"revision": _revision,
		"server_tick": _tick,
		"players": players,
		"checksum": "",
	}
	state["checksum"] = _state_checksum(state)
	return state


func restore_durable_state(value: Dictionary) -> Dictionary:
	var validation := validate_durable_state(value)
	if not bool(validation.get("success", false)):
		return validation
	if not _authority_owner_id.is_empty() and String(value.get("authority_owner_id", "")) != _authority_owner_id:
		return _failure("OWNERSHIP_RECOVERY_OWNER_MISMATCH")
	if _authority_epoch > 0 and int(value.get("authority_epoch", 0)) != _authority_epoch:
		return _failure("OWNERSHIP_RECOVERY_EPOCH_MISMATCH")
	var staged_players: Dictionary = {}
	for record_value in value.get("players", []):
		var record: Dictionary = Dictionary(record_value).duplicate(true)
		var logical_id := String(record.get("logical_player_id", ""))
		record["connected"] = false
		record["transport_session_id"] = ""
		staged_players[logical_id] = record
	_authority_owner_id = String(value.get("authority_owner_id", ""))
	_authority_epoch = int(value.get("authority_epoch", 0))
	_revision = int(value.get("revision", 0))
	_tick = int(value.get("server_tick", 0))
	_players = staged_players
	_session_to_player.clear()
	_operation_ledger.clear()
	return _success({"player_count": _players.size(), "revision": _revision, "server_tick": _tick})


func validate_durable_state(value: Dictionary) -> Dictionary:
	if String(value.get("schema", "")) != DURABLE_SCHEMA:
		return _failure("INVALID_OWNERSHIP_STATE_SCHEMA")
	for field in ["authority_owner_id", "authority_epoch", "revision", "server_tick", "players", "checksum"]:
		if not value.has(field):
			return _failure("OWNERSHIP_STATE_FIELD_MISSING", {"field": field})
	if String(value.get("authority_owner_id", "")).strip_edges().is_empty():
		return _failure("INVALID_OWNERSHIP_STATE_OWNER")
	if int(value.get("authority_epoch", 0)) < 1 or int(value.get("revision", -1)) < 0 or int(value.get("server_tick", -1)) < 0:
		return _failure("INVALID_OWNERSHIP_STATE_REVISION")
	if typeof(value.get("players")) != TYPE_ARRAY or typeof(value.get("checksum")) != TYPE_STRING:
		return _failure("INVALID_OWNERSHIP_STATE")
	if String(value.get("checksum", "")) != _state_checksum(value):
		return _failure("OWNERSHIP_STATE_CHECKSUM_MISMATCH")
	var seen: Dictionary = {}
	for record_value in value.get("players", []):
		if not record_value is Dictionary:
			return _failure("INVALID_OWNERSHIP_PLAYER_RECORD")
		var record: Dictionary = record_value
		var logical_id := String(record.get("logical_player_id", ""))
		if logical_id.is_empty() or logical_id != logical_id.strip_edges().to_lower() or seen.has(logical_id):
			return _failure("INVALID_OWNERSHIP_PLAYER_ID")
		if String(record.get("player_entity_id", "")) != "player/%s" % logical_id:
			return _failure("INVALID_OWNERSHIP_PLAYER_ENTITY")
		if int(record.get("ownership_epoch", 0)) < 1:
			return _failure("INVALID_PLAYER_OWNERSHIP_EPOCH")
		if int(record.get("joined_tick", -1)) < 0 or int(record.get("left_tick", -1)) < 0:
			return _failure("INVALID_PLAYER_OWNERSHIP_TICK")
		if int(record.get("joined_tick", 0)) > int(value.get("server_tick", 0)) or int(record.get("left_tick", 0)) > int(value.get("server_tick", 0)):
			return _failure("PLAYER_OWNERSHIP_TICK_AHEAD_OF_SERVER")
		if typeof(record.get("connected")) != TYPE_BOOL:
			return _failure("INVALID_PLAYER_OWNERSHIP_CONNECTED_STATE")
		if bool(record.get("connected", true)) or not String(record.get("transport_session_id", "")).is_empty():
			return _failure("DURABLE_OWNERSHIP_SESSION_MUST_BE_DISCONNECTED")
		seen[logical_id] = true
	var safe := Utils.canonicalize(value, "$.ownership_state")
	if not bool(safe.get("success", false)):
		return _failure("OWNERSHIP_STATE_NOT_JSON_SAFE", {"message": String(safe.get("error", ""))})
	return _success({"player_count": seen.size()})


func export_replay_state() -> Dictionary:
	var records: Dictionary = {}
	var operation_ids := _operation_ledger.keys()
	operation_ids.sort()
	for operation_id_value in operation_ids:
		records[String(operation_id_value)] = Dictionary(_operation_ledger[operation_id_value]).duplicate(true)
	var state: Dictionary = {"schema": REPLAY_SCHEMA, "records": records, "checksum": ""}
	state["checksum"] = _state_checksum(state)
	return state


func restore_replay_state(value: Dictionary) -> Dictionary:
	var validation := validate_replay_state(value)
	if not bool(validation.get("success", false)):
		return validation
	_operation_ledger = Dictionary(value.get("records", {})).duplicate(true)
	return _success({"operation_count": _operation_ledger.size()})


func validate_replay_state(value: Dictionary) -> Dictionary:
	if String(value.get("schema", "")) != REPLAY_SCHEMA or typeof(value.get("records")) != TYPE_DICTIONARY:
		return _failure("INVALID_OWNERSHIP_REPLAY_STATE")
	if typeof(value.get("checksum")) != TYPE_STRING or String(value.get("checksum", "")) != _state_checksum(value):
		return _failure("OWNERSHIP_REPLAY_CHECKSUM_MISMATCH")
	for operation_id_value in value.get("records", {}).keys():
		var operation_id := String(operation_id_value)
		var entry_value = value["records"][operation_id_value]
		if operation_id.strip_edges().is_empty() or not entry_value is Dictionary:
			return _failure("INVALID_OWNERSHIP_REPLAY_RECORD")
		var entry: Dictionary = entry_value
		if String(entry.get("fingerprint", "")).length() != 64 or typeof(entry.get("result")) != TYPE_DICTIONARY:
			return _failure("INVALID_OWNERSHIP_REPLAY_RECORD")
	var safe := Utils.canonicalize(value, "$.ownership_replay")
	if not bool(safe.get("success", false)):
		return _failure("OWNERSHIP_REPLAY_NOT_JSON_SAFE", {"message": String(safe.get("error", ""))})
	return _success({"operation_count": value.get("records", {}).size()})


func _state_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload.erase("checksum")
	return Utils.payload_hash(payload)

func get_report() -> Dictionary:
	var connected := 0
	for record in _players.values():
		if bool(record.get("connected", false)):
			connected += 1
	return {
		"schema": SCHEMA,
		"authority_owner_id": _authority_owner_id,
		"authority_epoch": _authority_epoch,
		"revision": _revision,
		"server_tick": _tick,
		"player_count": _players.size(),
		"connected_count": connected,
		"operation_count": _operation_ledger.size(),
		"wire_contract": OwnershipSnapshot.SCHEMA,
	}


func _join(logical_player_id: String, transport_session_id: String, operation_id: String, fingerprint: String) -> Dictionary:
	logical_player_id = logical_player_id.strip_edges().to_lower()
	transport_session_id = transport_session_id.strip_edges()
	operation_id = operation_id.strip_edges()
	var replay := _replay(operation_id, fingerprint)
	if not replay.is_empty():
		return replay
	if _session_to_player.has(transport_session_id) and String(_session_to_player[transport_session_id]) != logical_player_id:
		return _record_failure(operation_id, fingerprint, "TRANSPORT_SESSION_ALREADY_BOUND")
	var before := _revision
	var record: Dictionary = _players.get(logical_player_id, {})
	if not record.is_empty() and bool(record.get("connected", false)):
		if String(record.get("transport_session_id", "")) == transport_session_id:
			var exact := _success({"replay": true, "snapshot": create_snapshot(), "player": record.duplicate(true)})
			_record(operation_id, fingerprint, exact)
			return exact
		return _record_failure(operation_id, fingerprint, "PLAYER_ALREADY_CONNECTED")
	var player_entity_id := String(record.get("player_entity_id", "player/%s" % logical_player_id))
	var ownership_epoch := int(record.get("ownership_epoch", 0)) + 1
	if not record.is_empty():
		_session_to_player.erase(String(record.get("transport_session_id", "")))
	record = {
		"logical_player_id": logical_player_id,
		"player_entity_id": player_entity_id,
		"transport_session_id": transport_session_id,
		"ownership_epoch": ownership_epoch,
		"connected": true,
		"joined_tick": _tick + 1,
		"left_tick": int(record.get("left_tick", 0)),
	}
	_players[logical_player_id] = record
	_session_to_player[transport_session_id] = logical_player_id
	_revision += 1
	_tick += 1
	var delta := _create_delta(before, "JOINED", record)
	var result := _success({"replay": false, "player": record.duplicate(true), "delta": delta, "snapshot": create_snapshot()})
	_record(operation_id, fingerprint, result)
	return result


func _leave(logical_player_id: String, transport_session_id: String, operation_id: String, fingerprint: String) -> Dictionary:
	logical_player_id = logical_player_id.strip_edges().to_lower()
	transport_session_id = transport_session_id.strip_edges()
	operation_id = operation_id.strip_edges()
	var replay := _replay(operation_id, fingerprint)
	if not replay.is_empty():
		return replay
	if not _players.has(logical_player_id):
		return _record_failure(operation_id, fingerprint, "PLAYER_NOT_FOUND")
	var record: Dictionary = _players[logical_player_id]
	if String(record.get("transport_session_id", "")) != transport_session_id:
		return _record_failure(operation_id, fingerprint, "STALE_PLAYER_SESSION")
	if not bool(record.get("connected", false)):
		var exact := _success({"replay": true, "snapshot": create_snapshot(), "player": record.duplicate(true)})
		_record(operation_id, fingerprint, exact)
		return exact
	var before := _revision
	record["connected"] = false
	record["left_tick"] = _tick + 1
	_players[logical_player_id] = record
	_session_to_player.erase(transport_session_id)
	_revision += 1
	_tick += 1
	var delta := _create_delta(before, "LEFT", record)
	var result := _success({"replay": false, "player": record.duplicate(true), "delta": delta, "snapshot": create_snapshot()})
	_record(operation_id, fingerprint, result)
	return result


func _create_delta(base_revision: int, event_type: String, record: Dictionary) -> Dictionary:
	var payload := {
		"schema": DELTA_SCHEMA,
		"authority_owner_id": _authority_owner_id,
		"authority_epoch": _authority_epoch,
		"base_revision": base_revision,
		"target_revision": _revision,
		"server_tick": _tick,
		"event_type": event_type,
		"player": record.duplicate(true),
	}
	payload["checksum"] = Utils.payload_hash(payload)
	return payload


func _replay(operation_id: String, fingerprint: String) -> Dictionary:
	if operation_id.is_empty():
		return _failure("OPERATION_ID_REQUIRED")
	if not _operation_ledger.has(operation_id):
		return {}
	var entry: Dictionary = _operation_ledger[operation_id]
	if String(entry.get("fingerprint", "")) != fingerprint:
		return _failure("OPERATION_REPLAY_CONFLICT")
	var result: Dictionary = Dictionary(entry.get("result", {})).duplicate(true)
	result["replay"] = true
	var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
	details["replay"] = true
	result["details"] = details
	return result


func _record(operation_id: String, fingerprint: String, result: Dictionary) -> void:
	_operation_ledger[operation_id] = {"fingerprint": fingerprint, "result": result.duplicate(true)}


func _record_failure(operation_id: String, fingerprint: String, code: String) -> Dictionary:
	var result := _failure(code)
	_record(operation_id, fingerprint, result)
	return result


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}

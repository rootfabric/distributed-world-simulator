extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const OwnershipRegistry = preload("res://scripts/runtime/host_client/player_ownership_registry.gd")

const SCHEMA := "planet_simulator.multiplayer_gameplay_authority.v1"
const SNAPSHOT_SCHEMA := "planet_simulator.multiplayer_gameplay_snapshot.v1"
const DELTA_SCHEMA := "planet_simulator.multiplayer_gameplay_delta.v1"
const SHARED_ITEM_ID := "item/shared/beacon/1"

var _authority_owner_id := ""
var _authority_epoch := 0
var _revision := 0
var _tick := 0
var _ownership
var _players: Dictionary = {}
var _shared_item: Dictionary = {}
var _operation_ledger: Dictionary = {}


func setup(authority_owner_id: String, authority_epoch: int, server_tick: int = 0) -> Dictionary:
	if authority_owner_id.strip_edges().is_empty() or authority_epoch < 1 or server_tick < 0:
		return _failure("INVALID_MULTIPLAYER_AUTHORITY_CONFIGURATION")
	_authority_owner_id = authority_owner_id.strip_edges()
	_authority_epoch = authority_epoch
	_revision = 0
	_tick = server_tick
	_players.clear()
	_operation_ledger.clear()
	_shared_item = {
		"item_id": SHARED_ITEM_ID,
		"available": true,
		"owner_player_entity_id": "",
		"revision": 0,
	}
	_ownership = OwnershipRegistry.new()
	var ownership_setup: Dictionary = _ownership.setup(_authority_owner_id, _authority_epoch, server_tick)
	if not bool(ownership_setup.get("success", false)):
		return ownership_setup
	return _success({"snapshot": create_snapshot()})


func join(logical_player_id: String, transport_session_id: String, operation_id: String) -> Dictionary:
	logical_player_id = _normalize_player_id(logical_player_id)
	transport_session_id = transport_session_id.strip_edges()
	operation_id = operation_id.strip_edges()
	var fingerprint := Utils.payload_hash({
		"type": "join",
		"logical_player_id": logical_player_id,
		"transport_session_id": transport_session_id,
	})
	var replay := _replay(operation_id, fingerprint)
	if not replay.is_empty():
		return replay
	var ownership_result: Dictionary = _ownership.join(logical_player_id, transport_session_id, operation_id + "/ownership")
	if not bool(ownership_result.get("success", false)):
		return _record_failure(operation_id, fingerprint, String(ownership_result.get("error_code", "OWNERSHIP_JOIN_FAILED")))
	var ownership_record: Dictionary = ownership_result.get("details", {}).get("player", {})
	var before_revision := _revision
	var record: Dictionary = _players.get(logical_player_id, {})
	if record.is_empty():
		record = {
			"logical_player_id": logical_player_id,
			"player_entity_id": String(ownership_record.get("player_entity_id", "player/%s" % logical_player_id)),
			"transport_session_id": transport_session_id,
			"ownership_epoch": int(ownership_record.get("ownership_epoch", 1)),
			"connected": true,
			"position": _spawn_position(logical_player_id),
			"velocity": {"x": 0.0, "y": 0.0, "z": 0.0},
			"inventory": [],
			"last_input_sequence": 0,
			"state_revision": 1,
		}
	else:
		record["transport_session_id"] = transport_session_id
		record["ownership_epoch"] = int(ownership_record.get("ownership_epoch", int(record.get("ownership_epoch", 0)) + 1))
		record["connected"] = true
		record["state_revision"] = int(record.get("state_revision", 0)) + 1
	_players[logical_player_id] = record
	_advance()
	var delta := _create_delta(before_revision, "PLAYER_JOINED", record, {})
	var result := _success({
		"replay": false,
		"player": record.duplicate(true),
		"delta": delta,
		"snapshot": create_snapshot(),
	})
	_record(operation_id, fingerprint, result)
	return result


func leave(logical_player_id: String, transport_session_id: String, operation_id: String) -> Dictionary:
	logical_player_id = _normalize_player_id(logical_player_id)
	transport_session_id = transport_session_id.strip_edges()
	operation_id = operation_id.strip_edges()
	var fingerprint := Utils.payload_hash({
		"type": "leave",
		"logical_player_id": logical_player_id,
		"transport_session_id": transport_session_id,
	})
	var replay := _replay(operation_id, fingerprint)
	if not replay.is_empty():
		return replay
	var ownership_result: Dictionary = _ownership.leave(logical_player_id, transport_session_id, operation_id + "/ownership")
	if not bool(ownership_result.get("success", false)):
		return _record_failure(operation_id, fingerprint, String(ownership_result.get("error_code", "OWNERSHIP_LEAVE_FAILED")))
	if not _players.has(logical_player_id):
		return _record_failure(operation_id, fingerprint, "PLAYER_STATE_NOT_FOUND")
	var before_revision := _revision
	var record: Dictionary = _players[logical_player_id]
	record["connected"] = false
	record["state_revision"] = int(record.get("state_revision", 0)) + 1
	_players[logical_player_id] = record
	_advance()
	var delta := _create_delta(before_revision, "PLAYER_LEFT", record, {})
	var result := _success({"replay": false, "player": record.duplicate(true), "delta": delta, "snapshot": create_snapshot()})
	_record(operation_id, fingerprint, result)
	return result


func leave_transport_session(transport_session_id: String, operation_id: String) -> Dictionary:
	for logical_player_id in _players.keys():
		var record: Dictionary = _players[logical_player_id]
		if bool(record.get("connected", false)) and String(record.get("transport_session_id", "")) == transport_session_id:
			return leave(String(logical_player_id), transport_session_id, operation_id)
	return _success({"replay": true, "snapshot": create_snapshot()})


func move_player(
	logical_player_id: String,
	transport_session_id: String,
	ownership_epoch: int,
	input_sequence: int,
	delta_x: float,
	delta_z: float,
	operation_id: String
) -> Dictionary:
	logical_player_id = _normalize_player_id(logical_player_id)
	operation_id = operation_id.strip_edges()
	var fingerprint := Utils.payload_hash({
		"type": "move",
		"logical_player_id": logical_player_id,
		"transport_session_id": transport_session_id,
		"ownership_epoch": ownership_epoch,
		"input_sequence": input_sequence,
		"delta_x": delta_x,
		"delta_z": delta_z,
	})
	var replay := _replay(operation_id, fingerprint)
	if not replay.is_empty():
		return replay
	var owner_check := _validate_owner(logical_player_id, transport_session_id, ownership_epoch)
	if not bool(owner_check.get("success", false)):
		return _record_failure(operation_id, fingerprint, String(owner_check.get("error_code", "PLAYER_OWNERSHIP_REJECTED")))
	if input_sequence < 1:
		return _record_failure(operation_id, fingerprint, "INVALID_INPUT_SEQUENCE")
	if is_nan(delta_x) or is_inf(delta_x) or is_nan(delta_z) or is_inf(delta_z) or absf(delta_x) > 10.0 or absf(delta_z) > 10.0:
		return _record_failure(operation_id, fingerprint, "INVALID_MOVEMENT_DELTA")
	var record: Dictionary = _players[logical_player_id]
	if input_sequence <= int(record.get("last_input_sequence", 0)):
		return _record_failure(operation_id, fingerprint, "STALE_OR_DUPLICATE_INPUT_SEQUENCE")
	var before_revision := _revision
	var position: Dictionary = record.get("position", {}).duplicate(true)
	position["x"] = float(position.get("x", 0.0)) + delta_x
	position["z"] = float(position.get("z", 0.0)) + delta_z
	record["position"] = position
	record["velocity"] = {"x": delta_x, "y": 0.0, "z": delta_z}
	record["last_input_sequence"] = input_sequence
	record["state_revision"] = int(record.get("state_revision", 0)) + 1
	_players[logical_player_id] = record
	_advance()
	var delta := _create_delta(before_revision, "PLAYER_MOVED", record, {})
	var result := _success({"replay": false, "player": record.duplicate(true), "delta": delta, "snapshot": create_snapshot()})
	_record(operation_id, fingerprint, result)
	return result


func pickup_shared_item(
	logical_player_id: String,
	transport_session_id: String,
	ownership_epoch: int,
	item_id: String,
	operation_id: String
) -> Dictionary:
	logical_player_id = _normalize_player_id(logical_player_id)
	item_id = item_id.strip_edges()
	operation_id = operation_id.strip_edges()
	var fingerprint := Utils.payload_hash({
		"type": "pickup",
		"logical_player_id": logical_player_id,
		"transport_session_id": transport_session_id,
		"ownership_epoch": ownership_epoch,
		"item_id": item_id,
	})
	var replay := _replay(operation_id, fingerprint)
	if not replay.is_empty():
		return replay
	var owner_check := _validate_owner(logical_player_id, transport_session_id, ownership_epoch)
	if not bool(owner_check.get("success", false)):
		return _record_failure(operation_id, fingerprint, String(owner_check.get("error_code", "PLAYER_OWNERSHIP_REJECTED")))
	if item_id != SHARED_ITEM_ID:
		return _record_failure(operation_id, fingerprint, "ITEM_NOT_FOUND")
	if not bool(_shared_item.get("available", false)):
		return _record_failure(operation_id, fingerprint, "ITEM_ALREADY_CLAIMED", {
			"owner_player_entity_id": String(_shared_item.get("owner_player_entity_id", "")),
		})
	var before_revision := _revision
	var record: Dictionary = _players[logical_player_id]
	var inventory: Array = Array(record.get("inventory", [])).duplicate(true)
	if item_id not in inventory:
		inventory.append(item_id)
	record["inventory"] = inventory
	record["state_revision"] = int(record.get("state_revision", 0)) + 1
	_players[logical_player_id] = record
	_shared_item["available"] = false
	_shared_item["owner_player_entity_id"] = String(record.get("player_entity_id", ""))
	_shared_item["revision"] = int(_shared_item.get("revision", 0)) + 1
	_advance()
	var delta := _create_delta(before_revision, "ITEM_PICKED_UP", record, _shared_item)
	var result := _success({
		"replay": false,
		"player": record.duplicate(true),
		"shared_item": _shared_item.duplicate(true),
		"delta": delta,
		"snapshot": create_snapshot(),
	})
	_record(operation_id, fingerprint, result)
	return result


func request_inventory_write(
	requester_player_id: String,
	target_player_id: String,
	transport_session_id: String,
	ownership_epoch: int,
	operation_id: String
) -> Dictionary:
	requester_player_id = _normalize_player_id(requester_player_id)
	target_player_id = _normalize_player_id(target_player_id)
	var fingerprint := Utils.payload_hash({
		"type": "inventory_write_probe",
		"requester_player_id": requester_player_id,
		"target_player_id": target_player_id,
		"transport_session_id": transport_session_id,
		"ownership_epoch": ownership_epoch,
	})
	var replay := _replay(operation_id, fingerprint)
	if not replay.is_empty():
		return replay
	var owner_check := _validate_owner(requester_player_id, transport_session_id, ownership_epoch)
	if not bool(owner_check.get("success", false)):
		return _record_failure(operation_id, fingerprint, String(owner_check.get("error_code", "PLAYER_OWNERSHIP_REJECTED")))
	if requester_player_id != target_player_id:
		return _record_failure(operation_id, fingerprint, "PLAYER_PERMISSION_DENIED")
	var result := _success({"replay": false, "player": _players[requester_player_id].duplicate(true)})
	_record(operation_id, fingerprint, result)
	return result


func create_snapshot() -> Dictionary:
	var players: Array = []
	var ids := _players.keys()
	ids.sort()
	for logical_player_id in ids:
		players.append(Dictionary(_players[logical_player_id]).duplicate(true))
	var snapshot := {
		"schema": SNAPSHOT_SCHEMA,
		"authority_owner_id": _authority_owner_id,
		"authority_epoch": _authority_epoch,
		"revision": _revision,
		"server_tick": _tick,
		"region_id": "region/h3/test-arena",
		"players": players,
		"shared_item": _shared_item.duplicate(true),
	}
	snapshot["checksum"] = Utils.payload_hash(snapshot)
	return snapshot


func validate_snapshot(snapshot: Dictionary) -> Dictionary:
	var fields: Array[String] = [
		"schema", "authority_owner_id", "authority_epoch", "revision", "server_tick",
		"region_id", "players", "shared_item", "checksum",
	]
	var exact := Utils.validate_exact_fields(snapshot, fields)
	if not bool(exact.get("success", false)):
		return _failure("INVALID_MULTIPLAYER_SNAPSHOT_FIELDS")
	if String(snapshot.get("schema", "")) != SNAPSHOT_SCHEMA or not snapshot.get("players") is Array or not snapshot.get("shared_item") is Dictionary:
		return _failure("INVALID_MULTIPLAYER_SNAPSHOT")
	if String(snapshot.get("authority_owner_id", "")).strip_edges().is_empty() or String(snapshot.get("region_id", "")).strip_edges().is_empty():
		return _failure("INVALID_MULTIPLAYER_SNAPSHOT_IDENTITY")
	if not Utils.is_json_integer(snapshot.get("authority_epoch")) or int(snapshot.get("authority_epoch", 0)) < 1:
		return _failure("INVALID_MULTIPLAYER_SNAPSHOT_AUTHORITY")
	if not Utils.is_json_integer(snapshot.get("revision")) or int(snapshot.get("revision", -1)) < 0 or not Utils.is_json_integer(snapshot.get("server_tick")) or int(snapshot.get("server_tick", -1)) < 0:
		return _failure("INVALID_MULTIPLAYER_SNAPSHOT_REVISION")
	var logical_ids: Dictionary = {}
	var entity_ids: Dictionary = {}
	var connected_sessions: Dictionary = {}
	for player_value in snapshot.get("players", []):
		if not player_value is Dictionary:
			return _failure("INVALID_MULTIPLAYER_PLAYER_RECORD")
		var player_validation := _validate_player_record(player_value)
		if not bool(player_validation.get("success", false)):
			return player_validation
		var logical_id := String(player_value.get("logical_player_id", ""))
		var entity_id := String(player_value.get("player_entity_id", ""))
		var session_id := String(player_value.get("transport_session_id", ""))
		if logical_ids.has(logical_id) or entity_ids.has(entity_id):
			return _failure("DUPLICATE_MULTIPLAYER_PLAYER_IDENTITY")
		if bool(player_value.get("connected", false)) and connected_sessions.has(session_id):
			return _failure("DUPLICATE_MULTIPLAYER_TRANSPORT_SESSION")
		logical_ids[logical_id] = true
		entity_ids[entity_id] = true
		if bool(player_value.get("connected", false)):
			connected_sessions[session_id] = true
	var shared_item_validation := _validate_shared_item(snapshot.get("shared_item", {}))
	if not bool(shared_item_validation.get("success", false)):
		return shared_item_validation
	var copy := snapshot.duplicate(true)
	var checksum := String(copy.get("checksum", ""))
	copy.erase("checksum")
	if checksum.is_empty() or checksum != Utils.payload_hash(copy):
		return _failure("MULTIPLAYER_SNAPSHOT_CHECKSUM_MISMATCH")
	return _success()


func validate_delta(delta: Dictionary) -> Dictionary:
	var fields: Array[String] = [
		"schema", "authority_owner_id", "authority_epoch", "base_revision", "target_revision",
		"server_tick", "event_type", "player", "shared_item", "target_checksum", "checksum",
	]
	var exact := Utils.validate_exact_fields(delta, fields)
	if not bool(exact.get("success", false)):
		return _failure("INVALID_MULTIPLAYER_DELTA_FIELDS")
	if String(delta.get("schema", "")) != DELTA_SCHEMA or not delta.get("player") is Dictionary or not delta.get("shared_item") is Dictionary:
		return _failure("INVALID_MULTIPLAYER_DELTA")
	if String(delta.get("authority_owner_id", "")).strip_edges().is_empty() or int(delta.get("authority_epoch", 0)) < 1:
		return _failure("INVALID_MULTIPLAYER_DELTA_AUTHORITY")
	if String(delta.get("event_type", "")) not in ["PLAYER_JOINED", "PLAYER_LEFT", "PLAYER_MOVED", "ITEM_PICKED_UP"]:
		return _failure("INVALID_MULTIPLAYER_DELTA_EVENT")
	if int(delta.get("target_revision", 0)) != int(delta.get("base_revision", -1)) + 1 or int(delta.get("server_tick", -1)) < 0:
		return _failure("INVALID_MULTIPLAYER_DELTA_REVISION")
	var player_validation := _validate_player_record(delta.get("player", {}))
	if not bool(player_validation.get("success", false)):
		return player_validation
	if not delta.get("shared_item", {}).is_empty():
		var item_validation := _validate_shared_item(delta.get("shared_item", {}))
		if not bool(item_validation.get("success", false)):
			return item_validation
	if String(delta.get("target_checksum", "")).length() != 64:
		return _failure("INVALID_MULTIPLAYER_DELTA_TARGET_CHECKSUM")
	var copy := delta.duplicate(true)
	var checksum := String(copy.get("checksum", ""))
	copy.erase("checksum")
	if checksum.is_empty() or checksum != Utils.payload_hash(copy):
		return _failure("MULTIPLAYER_DELTA_CHECKSUM_MISMATCH")
	return _success()


func get_player(logical_player_id: String) -> Dictionary:
	return Dictionary(_players.get(_normalize_player_id(logical_player_id), {})).duplicate(true)


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
		"shared_item_available": bool(_shared_item.get("available", false)),
		"shared_item_owner": String(_shared_item.get("owner_player_entity_id", "")),
	}


func _create_delta(base_revision: int, event_type: String, player: Dictionary, shared_item: Dictionary) -> Dictionary:
	var target_snapshot := create_snapshot()
	var delta := {
		"schema": DELTA_SCHEMA,
		"authority_owner_id": _authority_owner_id,
		"authority_epoch": _authority_epoch,
		"base_revision": base_revision,
		"target_revision": _revision,
		"server_tick": _tick,
		"event_type": event_type,
		"player": player.duplicate(true),
		"shared_item": shared_item.duplicate(true),
		"target_checksum": String(target_snapshot.get("checksum", "")),
	}
	delta["checksum"] = Utils.payload_hash(delta)
	return delta


func _validate_player_record(record: Dictionary) -> Dictionary:
	var fields: Array[String] = [
		"logical_player_id", "player_entity_id", "transport_session_id", "ownership_epoch",
		"connected", "position", "velocity", "inventory", "last_input_sequence", "state_revision",
	]
	var exact := Utils.validate_exact_fields(record, fields)
	if not bool(exact.get("success", false)):
		return _failure("INVALID_MULTIPLAYER_PLAYER_FIELDS")
	var logical_id := String(record.get("logical_player_id", ""))
	if logical_id.strip_edges().is_empty() or logical_id != logical_id.to_lower():
		return _failure("INVALID_MULTIPLAYER_LOGICAL_PLAYER_ID")
	if String(record.get("player_entity_id", "")) != "player/%s" % logical_id:
		return _failure("INVALID_MULTIPLAYER_PLAYER_ENTITY_ID")
	if not String(record.get("transport_session_id", "")).begins_with("transport-session/"):
		return _failure("INVALID_MULTIPLAYER_TRANSPORT_SESSION")
	if not Utils.is_json_integer(record.get("ownership_epoch")) or int(record.get("ownership_epoch", 0)) < 1:
		return _failure("INVALID_MULTIPLAYER_OWNERSHIP_EPOCH")
	if typeof(record.get("connected")) != TYPE_BOOL:
		return _failure("INVALID_MULTIPLAYER_CONNECTED_FLAG")
	for vector_field in ["position", "velocity"]:
		var vector_validation := _validate_vector3_record(record.get(vector_field), String(vector_field))
		if not bool(vector_validation.get("success", false)):
			return vector_validation
	if not record.get("inventory") is Array:
		return _failure("INVALID_MULTIPLAYER_INVENTORY")
	var inventory_ids: Dictionary = {}
	for item_value in record.get("inventory", []):
		if typeof(item_value) != TYPE_STRING or String(item_value).strip_edges().is_empty():
			return _failure("INVALID_MULTIPLAYER_INVENTORY_ITEM")
		if inventory_ids.has(String(item_value)):
			return _failure("DUPLICATE_MULTIPLAYER_INVENTORY_ITEM")
		inventory_ids[String(item_value)] = true
	if not Utils.is_json_integer(record.get("last_input_sequence")) or int(record.get("last_input_sequence", -1)) < 0:
		return _failure("INVALID_MULTIPLAYER_INPUT_SEQUENCE")
	if not Utils.is_json_integer(record.get("state_revision")) or int(record.get("state_revision", 0)) < 1:
		return _failure("INVALID_MULTIPLAYER_PLAYER_REVISION")
	return _success()


func _validate_vector3_record(value, field_name: String) -> Dictionary:
	if not value is Dictionary:
		return _failure("INVALID_MULTIPLAYER_VECTOR", {"field": field_name})
	var exact := Utils.validate_exact_fields(value, ["x", "y", "z"])
	if not bool(exact.get("success", false)):
		return _failure("INVALID_MULTIPLAYER_VECTOR_FIELDS", {"field": field_name})
	for component in ["x", "y", "z"]:
		if typeof(value.get(component)) not in [TYPE_INT, TYPE_FLOAT]:
			return _failure("INVALID_MULTIPLAYER_VECTOR_COMPONENT", {"field": field_name, "component": component})
		var number := float(value.get(component))
		if is_nan(number) or is_inf(number):
			return _failure("INVALID_MULTIPLAYER_VECTOR_COMPONENT", {"field": field_name, "component": component})
	return _success()


func _validate_shared_item(item: Dictionary) -> Dictionary:
	var exact := Utils.validate_exact_fields(item, ["item_id", "available", "owner_player_entity_id", "revision"])
	if not bool(exact.get("success", false)):
		return _failure("INVALID_MULTIPLAYER_SHARED_ITEM_FIELDS")
	if String(item.get("item_id", "")) != SHARED_ITEM_ID or typeof(item.get("available")) != TYPE_BOOL:
		return _failure("INVALID_MULTIPLAYER_SHARED_ITEM")
	if not Utils.is_json_integer(item.get("revision")) or int(item.get("revision", -1)) < 0:
		return _failure("INVALID_MULTIPLAYER_SHARED_ITEM_REVISION")
	var owner_id := String(item.get("owner_player_entity_id", ""))
	if bool(item.get("available", false)) and not owner_id.is_empty():
		return _failure("AVAILABLE_ITEM_HAS_OWNER")
	if not bool(item.get("available", false)) and not owner_id.begins_with("player/"):
		return _failure("CLAIMED_ITEM_OWNER_REQUIRED")
	return _success()


func _validate_owner(logical_player_id: String, transport_session_id: String, ownership_epoch: int) -> Dictionary:
	if not _players.has(logical_player_id):
		return _failure("PLAYER_NOT_FOUND")
	var record: Dictionary = _players[logical_player_id]
	if not bool(record.get("connected", false)):
		return _failure("PLAYER_NOT_CONNECTED")
	if String(record.get("transport_session_id", "")) != transport_session_id:
		return _failure("STALE_PLAYER_SESSION")
	if int(record.get("ownership_epoch", 0)) != ownership_epoch:
		return _failure("STALE_PLAYER_OWNERSHIP_EPOCH")
	return _success()


func _spawn_position(logical_player_id: String) -> Dictionary:
	return {"x": -2.0 if logical_player_id == "a" else 2.0, "y": 0.0, "z": 0.0}


func _normalize_player_id(value: String) -> String:
	return value.strip_edges().to_lower()


func _advance() -> void:
	_revision += 1
	_tick += 1


func _replay(operation_id: String, fingerprint: String) -> Dictionary:
	if operation_id.strip_edges().is_empty():
		return _failure("OPERATION_ID_REQUIRED")
	if not _operation_ledger.has(operation_id):
		return {}
	var entry: Dictionary = _operation_ledger[operation_id]
	if String(entry.get("fingerprint", "")) != fingerprint:
		return _failure("OPERATION_REPLAY_CONFLICT")
	var result: Dictionary = Dictionary(entry.get("result", {})).duplicate(true)
	if bool(result.get("success", false)):
		result["details"]["replay"] = true
	return result


func _record(operation_id: String, fingerprint: String, result: Dictionary) -> void:
	_operation_ledger[operation_id] = {"fingerprint": fingerprint, "result": result.duplicate(true)}


func _record_failure(operation_id: String, fingerprint: String, error_code: String, details: Dictionary = {}) -> Dictionary:
	var result := _failure(error_code, details)
	_record(operation_id, fingerprint, result)
	return result


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}

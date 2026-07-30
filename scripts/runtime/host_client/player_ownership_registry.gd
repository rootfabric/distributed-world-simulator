extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA := "planet_simulator.player_ownership_registry.v1"
const SNAPSHOT_SCHEMA := "planet_simulator.player_ownership_snapshot.v1"
const DELTA_SCHEMA := "planet_simulator.player_ownership_delta.v1"

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
	_authority_owner_id = authority_owner_id
	_authority_epoch = authority_epoch
	_tick = server_tick
	_revision = 0
	_players.clear()
	_session_to_player.clear()
	_operation_ledger.clear()
	return _success({"snapshot": create_snapshot()})

func join(logical_player_id: String, transport_session_id: String, operation_id: String) -> Dictionary:
	logical_player_id = logical_player_id.strip_edges().to_lower()
	transport_session_id = transport_session_id.strip_edges()
	operation_id = operation_id.strip_edges()
	if logical_player_id.is_empty() or transport_session_id.is_empty() or operation_id.is_empty():
		return _failure("JOIN_ID_REQUIRED")
	var fingerprint := Utils.payload_hash({"type":"join", "logical_player_id":logical_player_id, "transport_session_id":transport_session_id})
	var replay := _replay(operation_id, fingerprint)
	if not replay.is_empty(): return replay
	if _session_to_player.has(transport_session_id) and String(_session_to_player[transport_session_id]) != logical_player_id:
		return _record_failure(operation_id, fingerprint, "TRANSPORT_SESSION_ALREADY_BOUND")
	var before := _revision
	var record: Dictionary = _players.get(logical_player_id, {})
	if not record.is_empty() and bool(record.get("connected", false)):
		if String(record.get("transport_session_id", "")) == transport_session_id:
			var exact := _success({"replay": true, "snapshot": create_snapshot(), "player": record.duplicate(true)})
			_operation_ledger[operation_id] = {"fingerprint":fingerprint, "result":exact.duplicate(true)}
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
	_revision += 1; _tick += 1
	var delta := _create_delta(before, "JOINED", record)
	var result := _success({"replay": false, "player":record.duplicate(true), "delta":delta, "snapshot":create_snapshot()})
	_operation_ledger[operation_id] = {"fingerprint":fingerprint, "result":result.duplicate(true)}
	return result

func leave(logical_player_id: String, transport_session_id: String, operation_id: String) -> Dictionary:
	logical_player_id = logical_player_id.strip_edges().to_lower()
	transport_session_id = transport_session_id.strip_edges(); operation_id = operation_id.strip_edges()
	if logical_player_id.is_empty() or transport_session_id.is_empty() or operation_id.is_empty(): return _failure("LEAVE_ID_REQUIRED")
	var fingerprint := Utils.payload_hash({"type":"leave", "logical_player_id":logical_player_id, "transport_session_id":transport_session_id})
	var replay := _replay(operation_id, fingerprint)
	if not replay.is_empty(): return replay
	if not _players.has(logical_player_id): return _record_failure(operation_id, fingerprint, "PLAYER_NOT_FOUND")
	var record: Dictionary = _players[logical_player_id]
	if String(record.get("transport_session_id", "")) != transport_session_id:
		return _record_failure(operation_id, fingerprint, "STALE_PLAYER_SESSION")
	if not bool(record.get("connected", false)):
		var exact := _success({"replay":true, "snapshot":create_snapshot(), "player":record.duplicate(true)})
		_operation_ledger[operation_id] = {"fingerprint":fingerprint, "result":exact.duplicate(true)}
		return exact
	var before := _revision
	record["connected"] = false; record["left_tick"] = _tick + 1
	_players[logical_player_id] = record; _session_to_player.erase(transport_session_id)
	_revision += 1; _tick += 1
	var delta := _create_delta(before, "LEFT", record)
	var result := _success({"replay":false, "player":record.duplicate(true), "delta":delta, "snapshot":create_snapshot()})
	_operation_ledger[operation_id] = {"fingerprint":fingerprint, "result":result.duplicate(true)}
	return result

func leave_transport_session(transport_session_id: String, operation_id: String) -> Dictionary:
	if not _session_to_player.has(transport_session_id): return _success({"replay":true, "snapshot":create_snapshot()})
	return leave(String(_session_to_player[transport_session_id]), transport_session_id, operation_id)

func create_snapshot() -> Dictionary:
	var players: Array = []
	var ids := _players.keys(); ids.sort()
	for id in ids: players.append(Dictionary(_players[id]).duplicate(true))
	var payload := {"schema":SNAPSHOT_SCHEMA, "authority_owner_id":_authority_owner_id, "authority_epoch":_authority_epoch, "revision":_revision, "server_tick":_tick, "players":players}
	payload["checksum"] = Utils.payload_hash(payload)
	return payload

func validate_snapshot(snapshot: Dictionary) -> Dictionary:
	for field in ["schema","authority_owner_id","authority_epoch","revision","server_tick","players","checksum"]:
		if not snapshot.has(field): return _failure("OWNERSHIP_SNAPSHOT_MISSING_FIELD", {"field":field})
	if String(snapshot.schema) != SNAPSHOT_SCHEMA or not snapshot.players is Array: return _failure("INVALID_OWNERSHIP_SNAPSHOT")
	var copy := snapshot.duplicate(true); var checksum := String(copy.get("checksum", "")); copy.erase("checksum")
	if checksum != Utils.payload_hash(copy): return _failure("OWNERSHIP_SNAPSHOT_CHECKSUM_MISMATCH")
	return _success()

func get_report() -> Dictionary:
	var connected := 0
	for record in _players.values(): connected += 1 if bool(record.get("connected", false)) else 0
	return {"schema":SCHEMA,"authority_owner_id":_authority_owner_id,"authority_epoch":_authority_epoch,"revision":_revision,"server_tick":_tick,"player_count":_players.size(),"connected_count":connected,"operation_count":_operation_ledger.size()}

func _create_delta(base_revision: int, event_type: String, record: Dictionary) -> Dictionary:
	var payload := {"schema":DELTA_SCHEMA,"authority_owner_id":_authority_owner_id,"authority_epoch":_authority_epoch,"base_revision":base_revision,"target_revision":_revision,"server_tick":_tick,"event_type":event_type,"player":record.duplicate(true)}
	payload["checksum"] = Utils.payload_hash(payload)
	return payload

func _replay(operation_id: String, fingerprint: String) -> Dictionary:
	if not _operation_ledger.has(operation_id): return {}
	var entry: Dictionary = _operation_ledger[operation_id]
	if String(entry.fingerprint) != fingerprint: return _failure("OPERATION_REPLAY_CONFLICT")
	var result: Dictionary = Dictionary(entry.result).duplicate(true); result.details["replay"] = true
	return result

func _record_failure(operation_id: String, fingerprint: String, code: String) -> Dictionary:
	var result := _failure(code); _operation_ledger[operation_id] = {"fingerprint":fingerprint,"result":result.duplicate(true)}; return result
func _success(details: Dictionary = {}) -> Dictionary: return {"success":true,"error_code":"","details":details.duplicate(true)}
func _failure(error_code: String, details: Dictionary = {}) -> Dictionary: return {"success":false,"error_code":error_code,"details":details.duplicate(true)}

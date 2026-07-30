extends RefCounted

const Wire = preload("res://scripts/runtime/networked_gameplay/contracts/wire_contract_utils.gd")
const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SCHEMA := "planet_simulator.player_ownership_snapshot.v1"
const FIELDS: Array[String] = ["schema", "authority_owner_id", "authority_epoch", "revision", "server_tick", "players"]
const PLAYER_FIELDS: Array[String] = ["logical_player_id", "player_entity_id", "transport_session_id", "ownership_epoch", "connected", "joined_tick", "left_tick"]

static func create(authority_owner_id: String, authority_epoch: int, revision: int, server_tick: int, players: Array) -> Dictionary:
	return Wire.create(SCHEMA, {"authority_owner_id": authority_owner_id, "authority_epoch": authority_epoch, "revision": revision, "server_tick": server_tick, "players": players.duplicate(true)})

static func validate(value: Dictionary) -> Dictionary:
	var wire_validation: Dictionary = Wire.validate(value, SCHEMA, FIELDS)
	if not bool(wire_validation.get("success", false)):
		if String(wire_validation.get("error_code", "")) == "WIRE_CHECKSUM_MISMATCH": return Wire.failure("OWNERSHIP_SNAPSHOT_CHECKSUM_MISMATCH")
		return Wire.failure("INVALID_PLAYER_OWNERSHIP_SNAPSHOT")
	if String(value.get("authority_owner_id", "")).strip_edges().is_empty(): return Wire.failure("INVALID_PLAYER_OWNERSHIP_SNAPSHOT")
	for field in ["authority_epoch"]:
		if not bool(Wire.require_positive_integer(value, field).get("success", false)): return Wire.failure("INVALID_PLAYER_OWNERSHIP_SNAPSHOT")
	for field in ["revision", "server_tick"]:
		if not bool(Wire.require_positive_integer(value, field, true).get("success", false)): return Wire.failure("INVALID_PLAYER_OWNERSHIP_SNAPSHOT")
	if not value.get("players") is Array: return Wire.failure("INVALID_PLAYER_OWNERSHIP_SNAPSHOT")
	var logical_ids: Dictionary = {}; var entity_ids: Dictionary = {}; var sessions: Dictionary = {}
	for record_value in value.get("players", []):
		if not record_value is Dictionary or not bool(NetworkUtils.validate_exact_fields(record_value, PLAYER_FIELDS).get("success", false)): return Wire.failure("INVALID_PLAYER_OWNERSHIP_RECORD")
		var logical_id := String(record_value.get("logical_player_id", "")); var entity_id := String(record_value.get("player_entity_id", "")); var session_id := String(record_value.get("transport_session_id", ""))
		if logical_id.is_empty() or entity_id != "player/%s" % logical_id or logical_ids.has(logical_id) or entity_ids.has(entity_id): return Wire.failure("INVALID_PLAYER_OWNERSHIP_RECORD")
		if typeof(record_value.get("connected")) != TYPE_BOOL: return Wire.failure("INVALID_PLAYER_OWNERSHIP_RECORD")
		for field in ["ownership_epoch"]:
			if not bool(Wire.require_positive_integer(record_value, field).get("success", false)): return Wire.failure("INVALID_PLAYER_OWNERSHIP_RECORD")
		for field in ["joined_tick", "left_tick"]:
			if not bool(Wire.require_positive_integer(record_value, field, true).get("success", false)): return Wire.failure("INVALID_PLAYER_OWNERSHIP_RECORD")
		if bool(record_value.get("connected", false)):
			if not session_id.begins_with("transport-session/") or sessions.has(session_id): return Wire.failure("INVALID_PLAYER_OWNERSHIP_RECORD")
			sessions[session_id] = true
		logical_ids[logical_id] = true; entity_ids[entity_id] = true
	return Wire.success()


static func validate_legacy(value: Dictionary) -> Dictionary:
	return validate(Wire.stringify_dictionary_keys(value))

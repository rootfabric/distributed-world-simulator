extends RefCounted

const Wire = preload("res://scripts/runtime/networked_gameplay/contracts/wire_contract_utils.gd")
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SCHEMA := "planet_simulator.player_state_snapshot.v1"
const FIELDS: Array[String] = ["schema", "authority_owner_id", "authority_epoch", "revision", "server_tick", "region_id", "players", "shared_item"]
const PLAYER_FIELDS: Array[String] = ["logical_player_id", "player_entity_id", "transport_session_id", "ownership_epoch", "connected", "position", "velocity", "inventory", "last_input_sequence", "state_revision"]
const SHARED_ITEM_FIELDS: Array[String] = ["item_id", "available", "owner_player_entity_id", "revision"]

static func create(authority_owner_id: String, authority_epoch: int, revision: int, server_tick: int, region_id: String, players: Array, shared_item: Dictionary) -> Dictionary:
	return Wire.create(SCHEMA, {"authority_owner_id": authority_owner_id, "authority_epoch": authority_epoch, "revision": revision, "server_tick": server_tick, "region_id": region_id, "players": players.duplicate(true), "shared_item": shared_item.duplicate(true)})

static func validate(value: Dictionary) -> Dictionary:
	var fields: Array[String] = FIELDS.duplicate(); fields.append("checksum")
	if not bool(Utils.validate_exact_fields(value, fields).get("success", false)): return Wire.failure("INVALID_MULTIPLAYER_SNAPSHOT_FIELDS")
	if String(value.get("schema", "")) != SCHEMA or not value.get("players") is Array or not value.get("shared_item") is Dictionary: return Wire.failure("INVALID_MULTIPLAYER_SNAPSHOT")
	if String(value.get("authority_owner_id", "")).strip_edges().is_empty() or String(value.get("region_id", "")).strip_edges().is_empty(): return Wire.failure("INVALID_MULTIPLAYER_SNAPSHOT_IDENTITY")
	if not Utils.is_json_integer(value.get("authority_epoch")) or int(value.get("authority_epoch", 0)) < 1: return Wire.failure("INVALID_MULTIPLAYER_SNAPSHOT_AUTHORITY")
	if not Utils.is_json_integer(value.get("revision")) or int(value.get("revision", -1)) < 0 or not Utils.is_json_integer(value.get("server_tick")) or int(value.get("server_tick", -1)) < 0: return Wire.failure("INVALID_MULTIPLAYER_SNAPSHOT_REVISION")
	var logical_ids: Dictionary = {}; var entity_ids: Dictionary = {}; var connected_sessions: Dictionary = {}
	for player_value in value.get("players", []):
		if not player_value is Dictionary: return Wire.failure("INVALID_MULTIPLAYER_PLAYER_RECORD")
		var player_validation := validate_player_record(player_value)
		if not bool(player_validation.get("success", false)): return player_validation
		var logical_id := String(player_value.get("logical_player_id", "")); var entity_id := String(player_value.get("player_entity_id", "")); var session_id := String(player_value.get("transport_session_id", ""))
		if logical_ids.has(logical_id) or entity_ids.has(entity_id): return Wire.failure("DUPLICATE_MULTIPLAYER_PLAYER_IDENTITY")
		if bool(player_value.get("connected", false)) and connected_sessions.has(session_id): return Wire.failure("DUPLICATE_MULTIPLAYER_TRANSPORT_SESSION")
		logical_ids[logical_id] = true; entity_ids[entity_id] = true
		if bool(player_value.get("connected", false)): connected_sessions[session_id] = true
	var item_validation := validate_shared_item(value.get("shared_item", {}))
	if not bool(item_validation.get("success", false)): return item_validation
	var copy := value.duplicate(true); var checksum := String(copy.get("checksum", "")); copy.erase("checksum")
	if checksum.is_empty() or checksum != Utils.payload_hash(copy): return Wire.failure("MULTIPLAYER_SNAPSHOT_CHECKSUM_MISMATCH")
	if not bool(Utils.canonicalize(value).get("success", false)): return Wire.failure("MULTIPLAYER_SNAPSHOT_NOT_JSON_SAFE")
	return Wire.success()

static func validate_player_record(record: Dictionary) -> Dictionary:
	if not bool(Utils.validate_exact_fields(record, PLAYER_FIELDS).get("success", false)): return Wire.failure("INVALID_MULTIPLAYER_PLAYER_FIELDS")
	var logical_id := String(record.get("logical_player_id", ""))
	if logical_id.strip_edges().is_empty() or logical_id != logical_id.to_lower(): return Wire.failure("INVALID_MULTIPLAYER_LOGICAL_PLAYER_ID")
	if String(record.get("player_entity_id", "")) != "player/%s" % logical_id: return Wire.failure("INVALID_MULTIPLAYER_PLAYER_ENTITY_ID")
	if not String(record.get("transport_session_id", "")).begins_with("transport-session/"): return Wire.failure("INVALID_MULTIPLAYER_TRANSPORT_SESSION")
	if not Utils.is_json_integer(record.get("ownership_epoch")) or int(record.get("ownership_epoch", 0)) < 1: return Wire.failure("INVALID_MULTIPLAYER_OWNERSHIP_EPOCH")
	if typeof(record.get("connected")) != TYPE_BOOL: return Wire.failure("INVALID_MULTIPLAYER_CONNECTED_FLAG")
	for field in ["position", "velocity"]:
		if not bool(Wire.validate_vector3(record.get(field), field).get("success", false)): return Wire.failure("INVALID_MULTIPLAYER_VECTOR")
	if not record.get("inventory") is Array: return Wire.failure("INVALID_MULTIPLAYER_INVENTORY")
	var inventory_ids: Dictionary = {}
	for item_value in record.get("inventory", []):
		if typeof(item_value) != TYPE_STRING or String(item_value).strip_edges().is_empty(): return Wire.failure("INVALID_MULTIPLAYER_INVENTORY_ITEM")
		if inventory_ids.has(String(item_value)): return Wire.failure("DUPLICATE_MULTIPLAYER_INVENTORY_ITEM")
		inventory_ids[String(item_value)] = true
	if not Utils.is_json_integer(record.get("last_input_sequence")) or int(record.get("last_input_sequence", -1)) < 0: return Wire.failure("INVALID_MULTIPLAYER_INPUT_SEQUENCE")
	if not Utils.is_json_integer(record.get("state_revision")) or int(record.get("state_revision", 0)) < 1: return Wire.failure("INVALID_MULTIPLAYER_PLAYER_REVISION")
	return Wire.success()

static func validate_shared_item(item: Dictionary) -> Dictionary:
	if not bool(Utils.validate_exact_fields(item, SHARED_ITEM_FIELDS).get("success", false)): return Wire.failure("INVALID_MULTIPLAYER_SHARED_ITEM_FIELDS")
	if String(item.get("item_id", "")) != "item/shared/beacon/1" or typeof(item.get("available")) != TYPE_BOOL: return Wire.failure("INVALID_MULTIPLAYER_SHARED_ITEM")
	if not Utils.is_json_integer(item.get("revision")) or int(item.get("revision", -1)) < 0: return Wire.failure("INVALID_MULTIPLAYER_SHARED_ITEM_REVISION")
	var owner_id := String(item.get("owner_player_entity_id", ""))
	if bool(item.get("available", false)) and not owner_id.is_empty(): return Wire.failure("AVAILABLE_ITEM_HAS_OWNER")
	if not bool(item.get("available", false)) and not owner_id.begins_with("player/"): return Wire.failure("CLAIMED_ITEM_OWNER_REQUIRED")
	return Wire.success()


static func validate_legacy(value: Dictionary) -> Dictionary:
	return validate(Wire.stringify_dictionary_keys(value))

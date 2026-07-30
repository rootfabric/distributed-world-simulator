extends RefCounted

const Wire = preload("res://scripts/runtime/networked_gameplay/contracts/wire_contract_utils.gd")
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Snapshot = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd")
const SCHEMA := "planet_simulator.player_state_delta.v1"
const FIELDS: Array[String] = ["schema", "authority_owner_id", "authority_epoch", "base_revision", "target_revision", "server_tick", "event_type", "player", "shared_item", "target_checksum"]
const EVENTS := ["PLAYER_JOINED", "PLAYER_LEFT", "PLAYER_MOVED", "ITEM_PICKED_UP", "PLAYER_PRESENTATION_UPDATED"]

static func create(authority_owner_id: String, authority_epoch: int, base_revision: int, target_revision: int, server_tick: int, event_type: String, player: Dictionary, shared_item: Dictionary, target_checksum: String) -> Dictionary:
	return Wire.create(SCHEMA, {"authority_owner_id": authority_owner_id, "authority_epoch": authority_epoch, "base_revision": base_revision, "target_revision": target_revision, "server_tick": server_tick, "event_type": event_type, "player": player.duplicate(true), "shared_item": shared_item.duplicate(true), "target_checksum": target_checksum})

static func validate(value: Dictionary) -> Dictionary:
	var fields: Array[String] = FIELDS.duplicate(); fields.append("checksum")
	if not bool(Utils.validate_exact_fields(value, fields).get("success", false)): return Wire.failure("INVALID_MULTIPLAYER_DELTA_FIELDS")
	if String(value.get("schema", "")) != SCHEMA or not value.get("player") is Dictionary or not value.get("shared_item") is Dictionary: return Wire.failure("INVALID_MULTIPLAYER_DELTA")
	if String(value.get("authority_owner_id", "")).strip_edges().is_empty() or int(value.get("authority_epoch", 0)) < 1: return Wire.failure("INVALID_MULTIPLAYER_DELTA_AUTHORITY")
	if String(value.get("event_type", "")) not in EVENTS: return Wire.failure("INVALID_MULTIPLAYER_DELTA_EVENT")
	if int(value.get("target_revision", 0)) != int(value.get("base_revision", -1)) + 1 or int(value.get("server_tick", -1)) < 0: return Wire.failure("INVALID_MULTIPLAYER_DELTA_REVISION")
	var player_validation := Snapshot.validate_player_record(value.get("player", {}))
	if not bool(player_validation.get("success", false)): return player_validation
	if not value.get("shared_item", {}).is_empty():
		var item_validation := Snapshot.validate_shared_item(value.get("shared_item", {}))
		if not bool(item_validation.get("success", false)): return item_validation
	if String(value.get("target_checksum", "")).length() != 64: return Wire.failure("INVALID_MULTIPLAYER_DELTA_TARGET_CHECKSUM")
	var copy := value.duplicate(true); var checksum := String(copy.get("checksum", "")); copy.erase("checksum")
	if checksum.is_empty() or checksum != Utils.payload_hash(copy): return Wire.failure("MULTIPLAYER_DELTA_CHECKSUM_MISMATCH")
	if not bool(Utils.canonicalize(value).get("success", false)): return Wire.failure("MULTIPLAYER_DELTA_NOT_JSON_SAFE")
	return Wire.success()


static func validate_legacy(value: Dictionary) -> Dictionary:
	return validate(Wire.stringify_dictionary_keys(value))

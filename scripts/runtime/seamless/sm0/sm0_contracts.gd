extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

const DIRECTORY_SCHEMA := "distributed_world_simulator.sm0_directory.v1"
const HANDOFF_PACKAGE_SCHEMA := "distributed_world_simulator.sm0_player_handoff_package.v1"
const MESSAGE_SCHEMA := "distributed_world_simulator.sm0_wire_message.v1"

const AUTHORITY_A := "authority/sm0/a"
const AUTHORITY_B := "authority/sm0/b"
const ZONE_A := "zone/earth/sm0/west"
const ZONE_B := "zone/earth/sm0/east"


static func authority_for_zone(zone_id: String) -> String:
	match zone_id:
		ZONE_A:
			return AUTHORITY_A
		ZONE_B:
			return AUTHORITY_B
		_:
			return ""


static func peer_authority(authority_id: String) -> String:
	return AUTHORITY_B if authority_id == AUTHORITY_A else AUTHORITY_A if authority_id == AUTHORITY_B else ""


static func peer_zone(zone_id: String) -> String:
	return ZONE_B if zone_id == ZONE_A else ZONE_A if zone_id == ZONE_B else ""


static func zone_for_x(x: float) -> String:
	return ZONE_A if x < 0.0 else ZONE_B


static func create_directory(owner_authority_id: String = AUTHORITY_A, authority_epoch: int = 1, revision: int = 1) -> Dictionary:
	return Utils.finalize_json_checksum({
		"schema": DIRECTORY_SCHEMA,
		"world_id": "earth",
		"logical_player_id": "a",
		"owner_authority_id": owner_authority_id,
		"owner_zone_id": ZONE_A if owner_authority_id == AUTHORITY_A else ZONE_B,
		"authority_epoch": authority_epoch,
		"revision": revision,
		"checksum": "",
	})


static func validate_directory(value: Dictionary) -> Dictionary:
	if String(value.get("schema", "")) != DIRECTORY_SCHEMA:
		return _failure("SM0_INVALID_DIRECTORY_SCHEMA")
	var owner := String(value.get("owner_authority_id", ""))
	if owner not in [AUTHORITY_A, AUTHORITY_B]:
		return _failure("SM0_INVALID_DIRECTORY_OWNER")
	if String(value.get("owner_zone_id", "")) != (ZONE_A if owner == AUTHORITY_A else ZONE_B):
		return _failure("SM0_DIRECTORY_ZONE_OWNER_MISMATCH")
	if String(value.get("world_id", "")) != "earth" or String(value.get("logical_player_id", "")) != "a":
		return _failure("SM0_INVALID_DIRECTORY_IDENTITY")
	if int(value.get("authority_epoch", 0)) < 1 or int(value.get("revision", 0)) < 1:
		return _failure("SM0_INVALID_DIRECTORY_REVISION")
	if String(value.get("checksum", "")) != _checksum(value):
		return _failure("SM0_DIRECTORY_CHECKSUM_MISMATCH")
	return _success()


static func create_handoff_package(
	transfer_id: String,
	player: Dictionary,
	source_authority_id: String,
	target_authority_id: String,
	source_zone_id: String,
	target_zone_id: String,
	source_authority_epoch: int,
	target_authority_epoch: int,
	directory_revision: int
) -> Dictionary:
	return Utils.finalize_json_checksum({
		"schema": HANDOFF_PACKAGE_SCHEMA,
		"transfer_id": transfer_id,
		"logical_player_id": String(player.get("logical_player_id", "")),
		"player_entity_id": String(player.get("player_entity_id", "")),
		"source_authority_id": source_authority_id,
		"target_authority_id": target_authority_id,
		"source_zone_id": source_zone_id,
		"target_zone_id": target_zone_id,
		"source_authority_epoch": source_authority_epoch,
		"target_authority_epoch": target_authority_epoch,
		"directory_revision": directory_revision,
		"position": Dictionary(player.get("position", {})).duplicate(true),
		"velocity": Dictionary(player.get("velocity", {})).duplicate(true),
		"orientation_yaw": float(player.get("orientation_yaw", 0.0)),
		"last_input_sequence": int(player.get("last_input_sequence", 0)),
		"state_revision": int(player.get("state_revision", 0)),
		"source_player_ownership_epoch": int(player.get("ownership_epoch", 0)),
		"checksum": "",
	})


static func validate_handoff_package(value: Dictionary) -> Dictionary:
	if String(value.get("schema", "")) != HANDOFF_PACKAGE_SCHEMA:
		return _failure("SM0_INVALID_HANDOFF_PACKAGE_SCHEMA")
	var transfer_id := String(value.get("transfer_id", ""))
	if transfer_id.strip_edges().is_empty():
		return _failure("SM0_HANDOFF_TRANSFER_ID_REQUIRED")
	if String(value.get("logical_player_id", "")) != "a" or String(value.get("player_entity_id", "")) != "player/a":
		return _failure("SM0_HANDOFF_PLAYER_IDENTITY_MISMATCH")
	var source_authority := String(value.get("source_authority_id", ""))
	var target_authority := String(value.get("target_authority_id", ""))
	if source_authority not in [AUTHORITY_A, AUTHORITY_B] or target_authority != peer_authority(source_authority):
		return _failure("SM0_HANDOFF_AUTHORITY_ROUTE_INVALID")
	var source_zone := String(value.get("source_zone_id", ""))
	var target_zone := String(value.get("target_zone_id", ""))
	if authority_for_zone(source_zone) != source_authority or authority_for_zone(target_zone) != target_authority:
		return _failure("SM0_HANDOFF_ZONE_ROUTE_INVALID")
	var source_epoch := int(value.get("source_authority_epoch", 0))
	var target_epoch := int(value.get("target_authority_epoch", 0))
	if source_epoch < 1 or target_epoch != source_epoch + 1:
		return _failure("SM0_HANDOFF_AUTHORITY_EPOCH_INVALID")
	if int(value.get("directory_revision", 0)) < 1:
		return _failure("SM0_HANDOFF_DIRECTORY_REVISION_INVALID")
	if not value.get("position") is Dictionary or not value.get("velocity") is Dictionary:
		return _failure("SM0_HANDOFF_PLAYER_STATE_REQUIRED")
	if int(value.get("last_input_sequence", -1)) < 0 or int(value.get("state_revision", 0)) < 1:
		return _failure("SM0_HANDOFF_PLAYER_REVISION_INVALID")
	if String(value.get("checksum", "")) != _checksum(value):
		return _failure("SM0_HANDOFF_PACKAGE_CHECKSUM_MISMATCH")
	return _success()


static func create_message(message_type: String, payload: Dictionary = {}, request_id: String = "") -> Dictionary:
	return Utils.finalize_json_checksum({
		"schema": MESSAGE_SCHEMA,
		"type": message_type,
		"request_id": request_id,
		"payload": payload.duplicate(true),
		"checksum": "",
	})


static func validate_message(message: Dictionary) -> Dictionary:
	if String(message.get("schema", "")) != MESSAGE_SCHEMA:
		return _failure("SM0_INVALID_MESSAGE_SCHEMA")
	if String(message.get("type", "")).strip_edges().is_empty() or not message.get("payload") is Dictionary:
		return _failure("SM0_INVALID_MESSAGE_FIELDS")
	if String(message.get("checksum", "")) != _checksum(message):
		return _failure("SM0_MESSAGE_CHECKSUM_MISMATCH")
	return _success()


static func encode_message(message: Dictionary) -> PackedByteArray:
	return JSON.stringify(message, "", false, true).to_utf8_buffer()


static func decode_message(packet: PackedByteArray) -> Dictionary:
	var decoded = JSON.parse_string(packet.get_string_from_utf8())
	if not decoded is Dictionary:
		return {}
	return Dictionary(decoded)


static func _checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload.erase("checksum")
	return Utils.payload_hash(payload)


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}

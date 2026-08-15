extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA := "planet_simulator.v0_canonical_state_fingerprint.v1"


static func create(
	world_id: String,
	gameplay_snapshot: Dictionary,
	item_graph_snapshot: Dictionary,
	construction_bundle: Dictionary
) -> Dictionary:
	var normalized_world := world_id.strip_edges().to_lower()
	if normalized_world.is_empty():
		return _failure("V0_FINGERPRINT_WORLD_REQUIRED")
	var players_value = gameplay_snapshot.get("players", [])
	if not players_value is Array:
		return _failure("V0_FINGERPRINT_PLAYERS_REQUIRED")
	var item_checksum := String(item_graph_snapshot.get("checksum", ""))
	if item_checksum.length() != 64:
		return _failure("V0_FINGERPRINT_ITEM_GRAPH_REQUIRED")
	var construction_checksum := String(construction_bundle.get("checksum", ""))
	if construction_checksum.length() != 64:
		return _failure("V0_FINGERPRINT_CONSTRUCTION_REQUIRED")
	var item_revision := int(item_graph_snapshot.get("revision", -1))
	var item_tick := int(item_graph_snapshot.get("tick", -1))
	var construction_generation := int(construction_bundle.get("server_generation", -1))
	if item_revision < 0 or item_tick < 0 or construction_generation < 0:
		return _failure("V0_FINGERPRINT_REVISION_INVALID")

	var players: Array = []
	for player_value in players_value:
		if not player_value is Dictionary:
			return _failure("V0_FINGERPRINT_PLAYER_INVALID")
		var player: Dictionary = player_value
		var logical_player_id := String(player.get("logical_player_id", ""))
		var player_entity_id := String(player.get("player_entity_id", ""))
		var ownership_epoch := int(player.get("ownership_epoch", 0))
		var state_revision := int(player.get("state_revision", 0))
		var position_value = player.get("position", {})
		if (
			logical_player_id.is_empty()
			or player_entity_id != "player/%s" % logical_player_id
			or ownership_epoch < 1
			or state_revision < 1
			or not position_value is Dictionary
		):
			return _failure("V0_FINGERPRINT_PLAYER_INVALID")
		var position: Dictionary = position_value
		for axis in ["x", "y", "z"]:
			var component = position.get(axis)
			if typeof(component) not in [TYPE_INT, TYPE_FLOAT] or is_nan(float(component)) or is_inf(float(component)):
				return _failure("V0_FINGERPRINT_PLAYER_POSITION_INVALID")
		var yaw_value = player.get("orientation_yaw", 0.0)
		if typeof(yaw_value) not in [TYPE_INT, TYPE_FLOAT] or is_nan(float(yaw_value)) or is_inf(float(yaw_value)):
			return _failure("V0_FINGERPRINT_PLAYER_ORIENTATION_INVALID")
		players.append({
			"logical_player_id": logical_player_id,
			"player_entity_id": player_entity_id,
			"ownership_epoch": ownership_epoch,
			"connected": bool(player.get("connected", false)),
			"state_revision": state_revision,
			"position": {
				"x": float(position.get("x", 0.0)),
				"y": float(position.get("y", 0.0)),
				"z": float(position.get("z", 0.0)),
			},
			"orientation_yaw": float(yaw_value),
		})
	players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("logical_player_id", "")) < String(b.get("logical_player_id", ""))
	)
	for index in range(1, players.size()):
		if String(players[index - 1].get("logical_player_id", "")) == String(players[index].get("logical_player_id", "")):
			return _failure("V0_FINGERPRINT_DUPLICATE_PLAYER")

	var body: Dictionary = {
		"schema": SCHEMA,
		"world_id": normalized_world,
		"players": players,
		"item_graph": {
			"revision": item_revision,
			"tick": item_tick,
			"checksum": item_checksum,
		},
		"construction": {
			"server_generation": construction_generation,
			"checksum": construction_checksum,
		},
	}
	var safe := Utils.canonicalize(body, "$.v0_canonical_state_fingerprint")
	if not bool(safe.get("success", false)):
		return _failure("V0_FINGERPRINT_NOT_JSON_SAFE")
	var checksum := Utils.payload_hash(body)
	if checksum.length() != 64:
		return _failure("V0_FINGERPRINT_HASH_FAILED")
	var fingerprint := body.duplicate(true)
	fingerprint["checksum"] = checksum
	return {
		"success": true,
		"error_code": "",
		"details": {
			"fingerprint": fingerprint,
			"checksum": checksum,
		},
	}


static func _failure(error_code: String) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": {}}

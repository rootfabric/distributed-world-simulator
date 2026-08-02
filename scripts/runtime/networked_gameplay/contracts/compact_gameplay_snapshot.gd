extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const FullSnapshot = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd")

const SCHEMA: String = "planet_simulator.compact_gameplay_snapshot.v1"
const FIELDS: Array[String] = ["schema", "a", "e", "r", "t", "g", "p", "i", "c", "h"]
const PLAYER_FIELDS: Array[String] = ["l", "e", "s", "o", "c", "p", "v", "n", "q", "r", "y", "f"]
const ITEM_FIELDS: Array[String] = ["i", "a", "o", "r"]


static func encode(snapshot: Dictionary) -> Dictionary:
	var normalized: Dictionary = FullSnapshot.Wire.stringify_dictionary_keys(snapshot)
	var validation: Dictionary = FullSnapshot.validate(normalized)
	if not bool(validation.get("success", false)):
		return validation
	var players: Array = []
	for player_value in normalized.get("players", []):
		var player: Dictionary = Dictionary(player_value)
		players.append({
			"l": String(player.get("logical_player_id", "")),
			"e": String(player.get("player_entity_id", "")),
			"s": String(player.get("transport_session_id", "")),
			"o": int(player.get("ownership_epoch", 0)),
			"c": bool(player.get("connected", false)),
			"p": _vector_to_array(Dictionary(player.get("position", {}))),
			"v": _vector_to_array(Dictionary(player.get("velocity", {}))),
			"n": Array(player.get("inventory", [])).duplicate(true),
			"q": int(player.get("last_input_sequence", 0)),
			"r": int(player.get("state_revision", 0)),
			"y": float(player.get("orientation_yaw", 0.0)),
			"f": bool(player.get("flashlight_enabled", false)),
		})
	var item: Dictionary = Dictionary(normalized.get("shared_item", {}))
	var body: Dictionary = {
		"schema": SCHEMA,
		"a": String(normalized.get("authority_owner_id", "")),
		"e": int(normalized.get("authority_epoch", 0)),
		"r": int(normalized.get("revision", 0)),
		"t": int(normalized.get("server_tick", 0)),
		"g": String(normalized.get("region_id", "")),
		"p": players,
		"i": {
			"i": String(item.get("item_id", "")),
			"a": bool(item.get("available", false)),
			"o": String(item.get("owner_player_entity_id", "")),
			"r": int(item.get("revision", 0)),
		},
		"c": String(normalized.get("checksum", "")),
	}
	body["h"] = Utils.payload_hash(body)
	return _success({"snapshot": body})


static func decode(value: Dictionary) -> Dictionary:
	var validation: Dictionary = validate(value)
	if not bool(validation.get("success", false)):
		return validation
	var players: Array = []
	for player_value in value.get("p", []):
		var player: Dictionary = Dictionary(player_value)
		players.append({
			"logical_player_id": String(player.get("l", "")),
			"player_entity_id": String(player.get("e", "")),
			"transport_session_id": String(player.get("s", "")),
			"ownership_epoch": int(player.get("o", 0)),
			"connected": bool(player.get("c", false)),
			"position": _array_to_vector(Array(player.get("p", []))),
			"velocity": _array_to_vector(Array(player.get("v", []))),
			"inventory": Array(player.get("n", [])).duplicate(true),
			"last_input_sequence": int(player.get("q", 0)),
			"state_revision": int(player.get("r", 0)),
			"orientation_yaw": float(player.get("y", 0.0)),
			"flashlight_enabled": bool(player.get("f", false)),
		})
	var item: Dictionary = Dictionary(value.get("i", {}))
	var snapshot: Dictionary = {
		"schema": FullSnapshot.SCHEMA,
		"authority_owner_id": String(value.get("a", "")),
		"authority_epoch": int(value.get("e", 0)),
		"revision": int(value.get("r", 0)),
		"server_tick": int(value.get("t", 0)),
		"region_id": String(value.get("g", "")),
		"players": players,
		"shared_item": {
			"item_id": String(item.get("i", "")),
			"available": bool(item.get("a", false)),
			"owner_player_entity_id": String(item.get("o", "")),
			"revision": int(item.get("r", 0)),
		},
		"checksum": String(value.get("c", "")),
	}
	var full_validation: Dictionary = FullSnapshot.validate(snapshot)
	if not bool(full_validation.get("success", false)):
		return _failure("COMPACT_GAMEPLAY_SNAPSHOT_DECODE_FAILED", {"cause": full_validation})
	return _success({"snapshot": snapshot})


static func validate(value: Dictionary) -> Dictionary:
	if not bool(Utils.validate_exact_fields(value, FIELDS).get("success", false)):
		return _failure("COMPACT_GAMEPLAY_SNAPSHOT_FIELD_SET_MISMATCH")
	if String(value.get("schema", "")) != SCHEMA:
		return _failure("INVALID_COMPACT_GAMEPLAY_SNAPSHOT_SCHEMA")
	if String(value.get("a", "")).strip_edges().is_empty() or String(value.get("g", "")).strip_edges().is_empty():
		return _failure("INVALID_COMPACT_GAMEPLAY_SNAPSHOT_IDENTITY")
	for field in ["e", "r", "t"]:
		if not Utils.is_json_integer(value.get(field)) or int(value.get(field, -1)) < (1 if field == "e" else 0):
			return _failure("INVALID_COMPACT_GAMEPLAY_SNAPSHOT_REVISION")
	if not value.get("p") is Array or not value.get("i") is Dictionary:
		return _failure("INVALID_COMPACT_GAMEPLAY_SNAPSHOT_PAYLOAD")
	var logical_ids: Dictionary = {}
	for player_value in value.get("p", []):
		if not player_value is Dictionary:
			return _failure("INVALID_COMPACT_GAMEPLAY_PLAYER")
		var player: Dictionary = player_value
		if not bool(Utils.validate_exact_fields(player, PLAYER_FIELDS).get("success", false)):
			return _failure("INVALID_COMPACT_GAMEPLAY_PLAYER_FIELDS")
		var logical_id: String = String(player.get("l", ""))
		if logical_id.is_empty() or logical_ids.has(logical_id):
			return _failure("INVALID_COMPACT_GAMEPLAY_PLAYER_ID")
		logical_ids[logical_id] = true
		for vector_field in ["p", "v"]:
			if not _valid_vector_array(player.get(vector_field)):
				return _failure("INVALID_COMPACT_GAMEPLAY_VECTOR")
		if not player.get("n") is Array or typeof(player.get("c")) != TYPE_BOOL or typeof(player.get("f")) != TYPE_BOOL:
			return _failure("INVALID_COMPACT_GAMEPLAY_PLAYER_VALUE")
		for integer_field in ["o", "q", "r"]:
			if not Utils.is_json_integer(player.get(integer_field)) or int(player.get(integer_field, -1)) < (1 if integer_field in ["o", "r"] else 0):
				return _failure("INVALID_COMPACT_GAMEPLAY_PLAYER_REVISION")
		if not _finite_number(player.get("y")):
			return _failure("INVALID_COMPACT_GAMEPLAY_ORIENTATION")
	var item: Dictionary = value.get("i", {})
	if not bool(Utils.validate_exact_fields(item, ITEM_FIELDS).get("success", false)):
		return _failure("INVALID_COMPACT_GAMEPLAY_ITEM_FIELDS")
	if typeof(item.get("a")) != TYPE_BOOL or not Utils.is_json_integer(item.get("r")):
		return _failure("INVALID_COMPACT_GAMEPLAY_ITEM")
	if String(value.get("c", "")).length() != 64:
		return _failure("INVALID_COMPACT_GAMEPLAY_TARGET_CHECKSUM")
	var copy: Dictionary = value.duplicate(true)
	var checksum: String = String(copy.get("h", ""))
	copy.erase("h")
	if checksum.length() != 64 or checksum != Utils.payload_hash(copy):
		return _failure("COMPACT_GAMEPLAY_SNAPSHOT_CHECKSUM_MISMATCH")
	return _success()


static func _vector_to_array(value: Dictionary) -> Array:
	return [float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0))]


static func _array_to_vector(value: Array) -> Dictionary:
	return {"x": float(value[0]), "y": float(value[1]), "z": float(value[2])}


static func _valid_vector_array(value) -> bool:
	if not value is Array or Array(value).size() != 3:
		return false
	for component in value:
		if not _finite_number(component):
			return false
	return true


static func _finite_number(value) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number: float = float(value)
	return not is_nan(number) and not is_inf(number)


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}

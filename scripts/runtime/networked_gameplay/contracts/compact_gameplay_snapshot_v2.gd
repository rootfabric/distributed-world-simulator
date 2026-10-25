extends RefCounted

# EXPERIMENTAL, UNROUTED numeric-wire version. The v1 sender/decoder and
# ProtocolFrameV2 are untouched. Explicit future capability negotiation is
# required before ANY real peer can receive this schema.
#
# Numeric player coordinates are fixed 16-character lowercase little-endian
# IEEE754 binary64 hex strings, never JSON decimal numbers. Restore exact
# source bits before calling the ORIGINAL FullSnapshot validator/checksum.
# No rounding/tolerance, no repeated parse, no accepted-checksum rewrite.
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const FullSnapshot = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd")

const SCHEMA: String = "planet_simulator.compact_gameplay_snapshot.v2"
const NUMBER_FORMAT: String = "IEEE754_BINARY64_LE_HEX_V1"
const FIELDS: Array[String] = ["schema", "nf", "a", "e", "r", "t", "g", "p", "i", "c", "h"]
const PLAYER_FIELDS: Array[String] = ["l", "e", "s", "o", "c", "p", "v", "n", "q", "r", "y", "f"]
const ITEM_FIELDS: Array[String] = ["i", "a", "o", "r"]
const HEX_DIGITS: String = "0123456789abcdef"


static func _pack64(number: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, number)
	return bytes.hex_encode()


static func _platform_supported() -> bool:
	# This is a VERSIONED wire representation, not an assumed host ABI.
	return _pack64(1.0) == "000000000000f03f"


static func _unpack64(value) -> Dictionary:
	if typeof(value) != TYPE_STRING or String(value).length() != 16:
		return _failure("INVALID_COMPACT_F64LE")
	var text: String = value
	var bytes := PackedByteArray()
	bytes.resize(8)
	for index in range(8):
		var hi: int = HEX_DIGITS.find(text.substr(2 * index, 1))
		var lo: int = HEX_DIGITS.find(text.substr(2 * index + 1, 1))
		if hi < 0 or lo < 0:
			return _failure("INVALID_COMPACT_F64LE")
		bytes[index] = hi * 16 + lo
	var number: float = bytes.decode_double(0)
	if is_nan(number) or is_inf(number):
		return _failure("NON_FINITE_COMPACT_F64LE")
	if _pack64(number) != text:
		return _failure("NON_CANONICAL_COMPACT_F64LE")
	return _success({"value": number})


static func encode(snapshot: Dictionary) -> Dictionary:
	if not _platform_supported():
		return _failure("UNSUPPORTED_COMPACT_FLOAT_PLATFORM")
	# Match the original v1 StringName-key normalization, without decimal
	# JSON serialization or numeric changes. This is a detached DTO copy.
	var source: Dictionary = FullSnapshot.Wire.stringify_dictionary_keys(snapshot)
	# ORIGINAL source checksum and every session/authority field must pass.
	var checked: Dictionary = FullSnapshot.validate(source)
	if not bool(checked.get("success", false)):
		return checked
	var players: Array = []
	for value in source["players"]:
		var p: Dictionary = value
		players.append({
			"l": p["logical_player_id"], "e": p["player_entity_id"],
			"s": p["transport_session_id"], "o": int(p["ownership_epoch"]),
			"c": p["connected"],
			"p": [_pack64(float(p["position"]["x"])), _pack64(float(p["position"]["y"])), _pack64(float(p["position"]["z"]))],
			"v": [_pack64(float(p["velocity"]["x"])), _pack64(float(p["velocity"]["y"])), _pack64(float(p["velocity"]["z"]))],
			"n": Array(p["inventory"]).duplicate(true),
			"q": int(p["last_input_sequence"]), "r": int(p["state_revision"]),
			"y": _pack64(float(p["orientation_yaw"])), "f": p["flashlight_enabled"],
		})
	var item: Dictionary = source["shared_item"]
	var body: Dictionary = {
		"schema": SCHEMA, "nf": NUMBER_FORMAT,
		"a": source["authority_owner_id"], "e": int(source["authority_epoch"]),
		"r": int(source["revision"]), "t": int(source["server_tick"]),
		"g": source["region_id"], "p": players,
		"i": {"i": item["item_id"], "a": item["available"], "o": item["owner_player_entity_id"], "r": int(item["revision"])},
		"c": source["checksum"],
	}
	body["h"] = Utils.payload_hash(body)
	return _success({"snapshot": body})


static func decode(value: Dictionary) -> Dictionary:
	if not _platform_supported():
		return _failure("UNSUPPORTED_COMPACT_FLOAT_PLATFORM")
	if value.get("schema") != SCHEMA or value.get("nf") != NUMBER_FORMAT:
		return _failure("UNSUPPORTED_COMPACT_NUMERIC_SCHEMA")
	if not bool(Utils.validate_exact_fields(value, FIELDS).get("success", false)):
		return _failure("COMPACT_GAMEPLAY_SNAPSHOT_FIELD_SET_MISMATCH")
	for key in ["a", "g", "c", "h"]:
		if typeof(value.get(key)) != TYPE_STRING:
			return _failure("INVALID_COMPACT_GAMEPLAY_SNAPSHOT_IDENTITY")
	for key in ["e", "r", "t"]:
		if not Utils.is_json_integer(value.get(key)):
			return _failure("INVALID_COMPACT_GAMEPLAY_SNAPSHOT_REVISION")
	if not value.get("p") is Array or not value.get("i") is Dictionary:
		return _failure("INVALID_COMPACT_GAMEPLAY_SNAPSHOT_PAYLOAD")
	# Authenticate entire packed representation, including nf and nested c,
	# before expansion. Public checksums detect corruption, not malicious
	# authenticated peers; transport session/authority checks remain external.
	var body: Dictionary = value.duplicate(true)
	body.erase("h")
	if String(value["h"]).length() != 64 or String(value["h"]) != Utils.payload_hash(body):
		return _failure("COMPACT_GAMEPLAY_SNAPSHOT_CHECKSUM_MISMATCH")
	var players: Array = []
	for pv in value["p"]:
		if not pv is Dictionary:
			return _failure("INVALID_COMPACT_GAMEPLAY_PLAYER")
		var p: Dictionary = pv
		if not bool(Utils.validate_exact_fields(p, PLAYER_FIELDS).get("success", false)):
			return _failure("INVALID_COMPACT_GAMEPLAY_PLAYER_FIELDS")
		for key in ["l", "e", "s"]:
			if typeof(p[key]) != TYPE_STRING:
				return _failure("INVALID_COMPACT_GAMEPLAY_PLAYER_ID")
		for key in ["o", "q", "r"]:
			if not Utils.is_json_integer(p[key]):
				return _failure("INVALID_COMPACT_GAMEPLAY_PLAYER_REVISION")
		if typeof(p["c"]) != TYPE_BOOL or typeof(p["f"]) != TYPE_BOOL or not p["n"] is Array:
			return _failure("INVALID_COMPACT_GAMEPLAY_PLAYER_VALUE")
		var vectors: Dictionary = {}
		for name in ["p", "v"]:
			if not p[name] is Array or Array(p[name]).size() != 3:
				return _failure("INVALID_COMPACT_GAMEPLAY_VECTOR")
			var components: Array[float] = []
			for component in p[name]:
				var number: Dictionary = _unpack64(component)
				if not bool(number.get("success", false)):
					return number
				components.append(float(number["details"]["value"]))
			vectors[name] = {"x": components[0], "y": components[1], "z": components[2]}
		var yaw: Dictionary = _unpack64(p["y"])
		if not bool(yaw.get("success", false)):
			return yaw
		players.append({
			"logical_player_id": p["l"], "player_entity_id": p["e"],
			"transport_session_id": p["s"], "ownership_epoch": int(p["o"]),
			"connected": p["c"], "position": vectors["p"], "velocity": vectors["v"],
			"inventory": Array(p["n"]).duplicate(true),
			"last_input_sequence": int(p["q"]), "state_revision": int(p["r"]),
			"orientation_yaw": float(yaw["details"]["value"]), "flashlight_enabled": p["f"],
		})
	var i: Dictionary = value["i"]
	if not bool(Utils.validate_exact_fields(i, ITEM_FIELDS).get("success", false)):
		return _failure("INVALID_COMPACT_GAMEPLAY_ITEM_FIELDS")
	if typeof(i["i"]) != TYPE_STRING or typeof(i["o"]) != TYPE_STRING or typeof(i["a"]) != TYPE_BOOL or not Utils.is_json_integer(i["r"]):
		return _failure("INVALID_COMPACT_GAMEPLAY_ITEM")
	var snapshot: Dictionary = {
		"schema": FullSnapshot.SCHEMA,
		"authority_owner_id": value["a"], "authority_epoch": int(value["e"]),
		"revision": int(value["r"]), "server_tick": int(value["t"]),
		"region_id": value["g"], "players": players,
		"shared_item": {"item_id": i["i"], "available": i["a"], "owner_player_entity_id": i["o"], "revision": int(i["r"])},
		"checksum": value["c"],
	}
	# Validate the ORIGINAL full checksum; never regenerate or waive it.
	var checked: Dictionary = FullSnapshot.validate(snapshot)
	if not bool(checked.get("success", false)):
		return _failure("COMPACT_GAMEPLAY_SNAPSHOT_DECODE_FAILED", {"cause": checked})
	return _success({"snapshot": snapshot})


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = decode(value)
	if not bool(checked.get("success", false)):
		return checked
	return _success()


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}

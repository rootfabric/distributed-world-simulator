extends RefCounted

# Full production contracts, controlled two-player Earth-local DTO fixtures.
# NOT a reconstruction of the historical Windows packet; NOT a GUI test.
# Original v1 source files are never patched or replaced by a fake codec.
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Full = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd")
const Compact = preload("res://scripts/runtime/networked_gameplay/contracts/compact_gameplay_snapshot.gd")
const Frame = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")
const CORPUS_SEED: int = 81526026
const CORPUS_COUNT: int = 2048


static func bits(value: float) -> String:
	var data := PackedByteArray()
	data.resize(8)
	data.encode_double(0, value)
	return data.hex_encode()


static func from_bits(value: String) -> float:
	var data := PackedByteArray()
	data.resize(8)
	for i in range(8):
		data[i] = value.substr(2 * i, 2).hex_to_int()
	return data.decode_double(0)


static func player(id: String, sequence: int, pos: Vector3, vel: Vector3, yaw: float) -> Dictionary:
	return {
		"logical_player_id": id, "player_entity_id": "player/" + id,
		"transport_session_id": "transport-session/815/" + id,
		"ownership_epoch": 1, "connected": true,
		"position": {"x": pos.x, "y": pos.y, "z": pos.z},
		"velocity": {"x": vel.x, "y": vel.y, "z": vel.z},
		"inventory": [], "last_input_sequence": sequence,
		"state_revision": sequence + 1, "orientation_yaw": yaw,
		"flashlight_enabled": false,
	}


static func make_full(players: Array, sequence: int) -> Dictionary:
	return Full.create("simulation/earth/815", 1, sequence, sequence * 3,
		"region/user1/a", players, {
			"item_id": "item/shared/beacon/1", "available": true,
			"owner_player_entity_id": "", "revision": sequence,
		})


static func generated_players(rng: RandomNumberGenerator, sequence: int) -> Array:
	var p := Vector3(rng.randf_range(-20, 20), rng.randf_range(-2, 2), rng.randf_range(-20, 20))
	var v := Vector3(rng.randf_range(-3, 3), rng.randf_range(-0.3, 0.3), rng.randf_range(-3, 3))
	var yaw: float = rng.randf_range(-PI, PI)
	if sequence % 3 == 0:
		v.y *= pow(10.0, -rng.randi_range(1, 14))
	return [player("a", sequence, p, v, yaw),
		player("b", sequence, p + Vector3(1.25, 0.0, 1.5), Vector3.ZERO, 0.0)]


static func fixed_witness_players() -> Array:
	# Frozen IEEE754 bits from seed 81526026, generated sample 84. All
	# player fields are legal native FullSnapshot DTOs; no runtime shim.
	return [
		player("a", 84,
			Vector3(from_bits("7076b09f69e92bc0"), from_bits("4442c7b4b70dff3f"), from_bits("00a609cc8324de3f")),
			Vector3(from_bits("eb218f01338df8bf"), from_bits("391e0df76695bebc"), from_bits("3053caf7d2360640")),
			from_bits("70cd04a5345ff5bf")),
		player("b", 84,
			Vector3(from_bits("7076b09f696929c0"), from_bits("4442c7b4b70dff3f"), from_bits("806902f32089ff3f")),
			Vector3.ZERO, 0.0),
	]


static func message(snapshot: Dictionary, index: int) -> Dictionary:
	return {"type": "COMPACT_GAMEPLAY_SNAPSHOT", "server_sent_at_ms": index * 50,
		"reason": "MOVEMENT_NETWORK_TICK", "snapshot": snapshot}


static func create_frame(snapshot: Dictionary, index: int) -> Dictionary:
	return Frame.create("frame/815/a/%d" % index, "transport-session/815/a", index,
		"SNAPSHOT", "UNRELIABLE_SEQUENCED", "planet_simulator.m3_network_message.v1",
		message(snapshot, index))


static func diagnostic_expand_v1(c: Dictionary) -> Dictionary:
	# Observability only. If h is invalid, production Compact.decode() must
	# refuse; expand here solely to inspect the ORIGINAL full checksum c.
	# This object is NEVER sent to product or used as an accepted snapshot.
	var players: Array = []
	for p in c["p"]:
		players.append({
			"logical_player_id": p["l"], "player_entity_id": p["e"],
			"transport_session_id": p["s"], "ownership_epoch": p["o"],
			"connected": p["c"], "position": Compact._array_to_vector(p["p"]),
			"velocity": Compact._array_to_vector(p["v"]), "inventory": p["n"].duplicate(),
			"last_input_sequence": p["q"], "state_revision": p["r"],
			"orientation_yaw": p["y"], "flashlight_enabled": p["f"],
		})
	var i: Dictionary = c["i"]
	return {"schema": Full.SCHEMA, "authority_owner_id": c["a"],
		"authority_epoch": c["e"], "revision": c["r"], "server_tick": c["t"],
		"region_id": c["g"], "players": players,
		"shared_item": {"item_id": i["i"], "available": i["a"], "owner_player_entity_id": i["o"], "revision": i["r"]},
		"checksum": c["c"]}


static func layer_checks(compact: Dictionary) -> Dictionary:
	var expanded: Dictionary = diagnostic_expand_v1(compact)
	var h_body: Dictionary = compact.duplicate(true)
	h_body.erase("h")
	var c_body: Dictionary = expanded.duplicate(true)
	c_body.erase("checksum")
	var h_check: Dictionary = Compact.validate(compact)
	var c_check: Dictionary = Full.validate(expanded)
	return {"h_valid": bool(h_check["success"]), "c_valid": bool(c_check["success"]),
		"h_error": h_check["error_code"], "c_error": c_check["error_code"],
		"h_stored": compact["h"], "h_computed": Utils.payload_hash(h_body),
		"c_stored": compact["c"], "c_computed": Utils.payload_hash(c_body)}


static func first_numeric_change(before, after, path: String = "$") -> Dictionary:
	if typeof(before) in [TYPE_INT, TYPE_FLOAT] and typeof(after) in [TYPE_INT, TYPE_FLOAT]:
		# JSON int/float retyping is NOT itself a numerical change.
		var left: String = bits(float(before))
		var right: String = bits(float(after))
		if left != right:
			return {"path": path, "before_f64le": left, "after_f64le": right,
				"before_json_number": Utils.canonical_json(before),
				"after_json_number": Utils.canonical_json(after)}
	elif before is Dictionary and after is Dictionary:
		var keys: Array = before.keys()
		keys.sort()
		for key in keys:
			if after.has(key):
				var diff: Dictionary = first_numeric_change(before[key], after[key], path + "." + String(key))
				if not diff.is_empty():
					return diff
	elif before is Array and after is Array:
		for index in range(mini(before.size(), after.size())):
			var diff: Dictionary = first_numeric_change(before[index], after[index], "%s[%d]" % [path, index])
			if not diff.is_empty():
				return diff
	return {}


static func inspect_v1(full: Dictionary, index: int) -> Dictionary:
	var full_valid: Dictionary = Full.validate(full)
	if not bool(full_valid["success"]):
		return {"fatal_stage": "FULL_CREATE", "error": full_valid["error_code"]}
	var encoded: Dictionary = Compact.encode(full)
	if not bool(encoded["success"]):
		return {"fatal_stage": "COMPACT_ENCODE", "error": encoded["error_code"]}
	var compact: Dictionary = encoded["details"]["snapshot"]
	var compact_layers: Dictionary = layer_checks(compact)
	var original_decode: Dictionary = Compact.decode(compact)
	var expanded: Dictionary = diagnostic_expand_v1(compact)
	if bool(original_decode["success"]) and Utils.canonical_json(original_decode["details"]["snapshot"]) != Utils.canonical_json(expanded):
		return {"fatal_stage": "DIAGNOSTIC_EXPANSION_NOT_PARITY", "error": "TEST_HELPER_INVALID"}
	var frame: Dictionary = create_frame(compact, index)
	var created_layers: Dictionary = layer_checks(frame["payload"]["snapshot"])
	var wire: Dictionary = Frame.encode(frame)
	if not bool(wire["success"]):
		return {"fatal_stage": "FRAME_ENCODE", "error": wire["error_code"]}
	var packet: PackedByteArray = wire["details"]["packet"]
	var text: String = packet.get_string_from_utf8()
	var parsed_value = JSON.parse_string(text)
	if not parsed_value is Dictionary:
		return {"fatal_stage": "FRAME_PARSE", "error": "INVALID_JSON"}
	var parsed: Dictionary = parsed_value
	var recv_layers: Dictionary = layer_checks(parsed["payload"]["snapshot"])
	var receive: Dictionary = Frame.decode(packet)
	var receiver_error: String = String(receive["error_code"])
	var first_broken_stage: String = "NONE"
	var first_layers: Array[String] = []
	for stage in [["COMPACT_ENCODE", compact_layers], ["FRAME_CREATE_JSON", created_layers], ["RECEIVER_JSON", recv_layers]]:
		if not bool(stage[1]["h_valid"]) or not bool(stage[1]["c_valid"]):
			first_broken_stage = stage[0]
			if not bool(stage[1]["h_valid"]): first_layers.append("h")
			if not bool(stage[1]["c_valid"]): first_layers.append("c")
			break
	if first_broken_stage == "NONE" and not bool(receive["success"]):
		first_broken_stage = "RECEIVER_FRAME"
		first_layers.append("payload_checksum" if receiver_error == "PAYLOAD_CHECKSUM_MISMATCH" else "canonical_frame")
	var causal_change: Dictionary = first_numeric_change(compact, frame["payload"]["snapshot"], "$.payload.snapshot")
	var receive_change: Dictionary = first_numeric_change(frame, parsed)
	return {
		"case": index, "full_valid": true,
		"first_broken_stage": first_broken_stage, "first_broken_checksums": first_layers,
		"compact_created": compact_layers, "frame_created": created_layers,
		"receiver_parsed": recv_layers, "receiver_error": receiver_error,
		"receiver_pass": bool(receive["success"]),
		"outer_stored": frame["payload_checksum"],
		"outer_after_frame_create": Utils.payload_hash(frame["payload"]),
		"outer_after_receive_parse": Utils.payload_hash(parsed["payload"]),
		"first_frame_create_numeric_change": causal_change,
		"first_receive_parse_numeric_change": receive_change,
		"packet_bytes": packet.size(), "packet_sha256": text.sha256_text(),
		"historical_incident_proven": false,
	}


static func source_fingerprints() -> Array:
	var paths: Array[String] = [
		"scripts/network/contracts/network_contract_utils.gd",
		"scripts/network/transports/v2/transport_contract_utils.gd",
		"scripts/network/realtime/realtime_channel_policy.gd",
		"scripts/network/transports/v2/protocol_frame_v2.gd",
		"scripts/runtime/networked_gameplay/contracts/wire_contract_utils.gd",
		"scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd",
		"scripts/runtime/networked_gameplay/contracts/compact_gameplay_snapshot.gd",
	]
	var result: Array = []
	for path in paths:
		var data: PackedByteArray = FileAccess.get_file_as_bytes("res://" + path)
		var header: PackedByteArray = ("blob %d" % data.size()).to_utf8_buffer()
		header.append(0)
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA1)
		context.update(header)
		context.update(data)
		result.append({"path": path, "git_blob_sha1": context.finish().hex_encode(),
			"sha256": data.get_string_from_utf8().sha256_text()})
	return result

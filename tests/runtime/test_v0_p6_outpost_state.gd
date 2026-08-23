extends SceneTree

## P6.7 L0: canonical outpost state container — serialize/deserialize
## round-trip, checksum determinism, delta application (place/break block,
## move player, container ops), fail-closed on corrupt data, checksum
## sensitivity to any mutation.

const StateScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_outpost_state.gd")

var assertions := 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[p6.7-outpost-state-l0][FAIL] %s" % message)


func _build_populated_state() -> RefCounted:
	var state = StateScript.new()
	state.set_world_seed(4242)
	state.apply_delta({"op": "place_block", "pos": [1, 2, 3], "block_type": "stone"})
	state.apply_delta({"op": "place_block", "pos": [-4, 0, 7], "block_type": "wood"})
	state.apply_delta({"op": "container_create", "container_id": "container/storage-1"})
	state.apply_delta({"op": "container_add_item", "container_id": "container/storage-1", "item": "item/hammer"})
	state.apply_delta({"op": "container_add_item", "container_id": "container/storage-1", "item": "item/plank"})
	state.apply_delta({"op": "player_move", "player_id": "player/alpha", "pos": [10, 0, -2], "rot": 1.5})
	state.advance_tick(3)
	return state


func _init() -> void:
	# --- serialize/deserialize round-trip ---
	var original = _build_populated_state()
	var serialized: Dictionary = original.serialize()
	_assert(String(serialized.get("schema", "")) == StateScript.SCHEMA, "serialized schema missing")
	_assert(int(serialized.get("tick", -1)) == 3, "tick not serialized")
	_assert(int(serialized.get("world_seed", -1)) == 4242, "world_seed not serialized")
	var restored = StateScript.new()
	_assert(restored.deserialize(serialized), "deserialize rejected valid payload: %s" % restored.get_report()["last_error_code"])
	_assert(restored.serialize().hash() == serialized.hash(), "round-trip serialization diverged")
	_assert(restored.compute_checksum() == original.compute_checksum(), "round-trip checksum diverged")
	_assert(restored.block_count() == 2, "blocks lost in round-trip")
	_assert(String(restored.container_items("container/storage-1")[0]) == "item/hammer", "container items lost in round-trip")
	_assert(Dictionary(restored.player_position("player/alpha")).get("rot", 0.0) == 1.5, "player rotation lost in round-trip")
	_assert(bool(restored.has_block("1,2,3")) and String(restored.block_type_at("1,2,3")) == "stone", "block content lost in round-trip")

	# --- checksum determinism (construction order must not matter) ---
	var order_a = StateScript.new()
	order_a.apply_delta({"op": "place_block", "pos": [1, 2, 3], "block_type": "stone"})
	order_a.apply_delta({"op": "place_block", "pos": [9, 9, 9], "block_type": "glass"})
	var order_b = StateScript.new()
	order_b.apply_delta({"op": "place_block", "pos": [9, 9, 9], "block_type": "glass"})
	order_b.apply_delta({"op": "place_block", "pos": [1, 2, 3], "block_type": "stone"})
	_assert(order_a.compute_checksum() == order_b.compute_checksum(), "checksum depends on construction order")
	_assert(StateScript.checksum_of_data(order_a.serialize()) == order_a.compute_checksum(), "static checksum helper diverged")
	_assert(order_a.compute_checksum().length() == 64, "checksum is not hex sha-256 length")

	# --- JSON round-trip (floats from parser must still deserialize) ---
	var json_round_trip = StateScript.new()
	var parsed = JSON.parse_string(JSON.stringify(order_a.serialize()))
	_assert(typeof(parsed) == TYPE_DICTIONARY, "canonical json did not parse")
	_assert(json_round_trip.deserialize(parsed), "json-parsed payload rejected: %s" % json_round_trip.get_report()["last_error_code"])
	_assert(json_round_trip.compute_checksum() == order_a.compute_checksum(), "json round-trip checksum diverged")

	# --- delta application: place/break block ---
	var deltas = StateScript.new()
	_assert(deltas.apply_delta({"op": "place_block", "pos": [0, 0, 0], "block_type": "brick"}), "valid place_block rejected")
	_assert(not deltas.apply_delta({"op": "place_block", "pos": [0, 0, 0], "block_type": "brick"}), "double place accepted")
	_assert(String(deltas.get_report()["last_error_code"]) == "POSITION_OCCUPIED", "occupied position error code wrong")
	_assert(deltas.apply_delta({"op": "break_block", "pos": [0, 0, 0]}), "valid break_block rejected")
	_assert(not deltas.apply_delta({"op": "break_block", "pos": [0, 0, 0]}), "break of missing block accepted")
	_assert(String(deltas.get_report()["last_error_code"]) == "UNKNOWN_BLOCK", "unknown block error code wrong")

	# --- delta application: player move ---
	_assert(deltas.apply_delta({"op": "player_move", "player_id": "player/alpha", "pos": [3, 0, 4], "rot": 0.25}), "valid player_move rejected")
	var moved: Dictionary = deltas.player_position("player/alpha")
	_assert((moved.get("pos", []) as Array).hash() == [3, 0, 4].hash(), "player pos not applied")
	_assert(not deltas.apply_delta({"op": "player_move", "player_id": "", "pos": [1, 1, 1]}), "empty player id accepted")
	_assert(not deltas.apply_delta({"op": "player_move", "player_id": "player/alpha", "pos": [1, 1]}), "short pos accepted")

	# --- delta application: container ops ---
	_assert(deltas.apply_delta({"op": "container_create", "container_id": "container/crate"}), "container_create rejected")
	_assert(not deltas.apply_delta({"op": "container_create", "container_id": "container/crate"}), "duplicate container accepted")
	_assert(deltas.apply_delta({"op": "container_add_item", "container_id": "container/crate", "item": "item/nail"}), "container_add_item rejected")
	_assert(deltas.apply_delta({"op": "container_add_item", "container_id": "container/crate", "item": "item/nail"}), "second identical item rejected")
	_assert(int(deltas.container_items("container/crate").size()) == 2, "item count wrong")
	_assert(deltas.apply_delta({"op": "container_remove_item", "container_id": "container/crate", "item": "item/nail"}), "container_remove_item rejected")
	_assert(int(deltas.container_items("container/crate").size()) == 1, "item not removed")
	_assert(deltas.apply_delta({"op": "container_remove", "container_id": "container/crate"}), "container_remove rejected")
	_assert(not deltas.container_exists("container/crate"), "container not removed")
	_assert(not deltas.apply_delta({"op": "container_remove", "container_id": "container/crate"}), "remove of missing container accepted")

	# --- fail-closed on corrupt data (state must stay untouched) ---
	var guard = _build_populated_state()
	var guard_checksum: String = guard.compute_checksum()
	var corrupt_payloads: Array = [
		{},
		{"schema": "wrong.schema"},
		{"schema": StateScript.SCHEMA},
		{"schema": StateScript.SCHEMA, "version": 2, "world_seed": 0, "tick": 0, "blocks": {}, "containers": {}, "player_positions": {}},
		{"schema": StateScript.SCHEMA, "version": 1, "world_seed": "x", "tick": 0, "blocks": {}, "containers": {}, "player_positions": {}},
		{"schema": StateScript.SCHEMA, "version": 1, "world_seed": 0, "tick": "x", "blocks": {}, "containers": {}, "player_positions": {}},
		{"schema": StateScript.SCHEMA, "version": 1, "world_seed": 0, "tick": 0, "blocks": "no", "containers": {}, "player_positions": {}},
		{"schema": StateScript.SCHEMA, "version": 1, "world_seed": 0, "tick": 0, "blocks": {"1,2": "stone"}, "containers": {}, "player_positions": {}},
		{"schema": StateScript.SCHEMA, "version": 1, "world_seed": 0, "tick": 0, "blocks": {"1,2,3": ""}, "containers": {}, "player_positions": {}},
		{"schema": StateScript.SCHEMA, "version": 1, "world_seed": 0, "tick": 0, "blocks": {}, "containers": {"c": "no"}, "player_positions": {}},
		{"schema": StateScript.SCHEMA, "version": 1, "world_seed": 0, "tick": 0, "blocks": {}, "containers": {"c": {"items": "no"}}, "player_positions": {}},
		{"schema": StateScript.SCHEMA, "version": 1, "world_seed": 0, "tick": 0, "blocks": {}, "containers": {"c": {"items": [42]}}, "player_positions": {}},
		{"schema": StateScript.SCHEMA, "version": 1, "world_seed": 0, "tick": 0, "blocks": {}, "containers": {}, "player_positions": {"p": "no"}},
		{"schema": StateScript.SCHEMA, "version": 1, "world_seed": 0, "tick": 0, "blocks": {}, "containers": {}, "player_positions": {"p": {"pos": [1, 2]}}},
		{"schema": StateScript.SCHEMA, "version": 1, "world_seed": 0, "tick": 0, "blocks": {}, "containers": {}, "player_positions": {"p": {"pos": [1, 2, 3], "rot": "x"}}},
		{"schema": StateScript.SCHEMA, "version": 1, "world_seed": 0, "tick": 0, "blocks": {}, "containers": {}, "player_positions": {}, "sneaky_field": 1},
	]
	for corrupt_value in corrupt_payloads:
		var payload: Dictionary = corrupt_value
		_assert(not guard.deserialize(payload), "corrupt payload accepted: %s" % JSON.stringify(payload))
	_assert(guard.compute_checksum() == guard_checksum, "failed deserialize mutated state")
	_assert(not deltas.apply_delta({"op": "teleport_everything"}), "unknown op accepted")
	_assert(not deltas.apply_delta({}), "empty delta accepted")

	# --- checksum changes on ANY mutation ---
	var sensitive = StateScript.new()
	var base_checksum: String = sensitive.compute_checksum()
	sensitive.apply_delta({"op": "place_block", "pos": [5, 5, 5], "block_type": "stone"})
	var after_place: String = sensitive.compute_checksum()
	_assert(after_place != base_checksum, "place_block did not change checksum")
	sensitive.apply_delta({"op": "break_block", "pos": [5, 5, 5]})
	_assert(sensitive.compute_checksum() != after_place, "break_block did not change checksum")
	sensitive.apply_delta({"op": "player_move", "player_id": "player/alpha", "pos": [1, 1, 1]})
	var after_move: String = sensitive.compute_checksum()
	_assert(after_move != base_checksum, "player_move did not change checksum")
	sensitive.apply_delta({"op": "container_create", "container_id": "container/c"})
	sensitive.apply_delta({"op": "container_add_item", "container_id": "container/c", "item": "item/i"})
	_assert(sensitive.compute_checksum() != after_move, "container add did not change checksum")
	sensitive.apply_delta({"op": "set_tick", "value": 7})
	_assert(sensitive.compute_checksum() != after_move, "set_tick did not change checksum")

	if failures.is_empty():
		print("[p6.7-outpost-state-l0] all %d assertions passed" % assertions)
		print("[p6.7-outpost-state-l0][stage] OUTPOST_STATE_PASS")
		quit(0)
	else:
		print("[p6.7-outpost-state-l0] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
		quit(1)

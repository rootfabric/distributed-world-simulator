extends SceneTree

const Service = preload(
	"res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd"
)

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_run()


func _run() -> void:
	var service = Service.new()
	_assert(
		_ok(service.setup(
			"simulation/v0-s1/local-two-player",
			1,
			0,
			{
				"profile": Service.PROFILE_MULTIPLAYER_CORE,
				"topology_adapter": "TEST",
				"region_id": "region/v0-s1/local-two-player",
				"playable_sandbox": false,
				"fixed_tick_authority": true,
			}
		)),
		"V0 local two-player service configures on SERVER_PREDICTED fixed-tick path"
	)

	_assert(
		_ok(service.join(
			"a",
			"transport-session/v0-s1/local/a",
			"operation/v0-s1/local/join/a"
		)),
		"Client A joins"
	)
	_assert(
		_ok(service.join(
			"b",
			"transport-session/v0-s1/local/b",
			"operation/v0-s1/local/join/b"
		)),
		"Client B joins"
	)

	var a_before := _player_position(service.get_player("a"))
	var b_before := _player_position(service.get_player("b"))
	var spawn_distance := a_before.distance_to(b_before)
	_assert(spawn_distance >= 2.0, "A and B do not overlap at spawn")
	_assert(spawn_distance <= 12.0, "A and B start close enough for immediate visual inspection")
	_assert(is_equal_approx(a_before.y, b_before.y), "A and B start on the same local height plane")

	var snapshot_before: Dictionary = service.create_snapshot()
	_assert(_connected_player_count(snapshot_before) == 2, "authoritative snapshot contains exactly two connected players")

	_assert(_ok(service.advance_fixed_server_tick(1)), "server advances fixed tick for both players")
	var a_move := service.simulate_fixed_movement_tick(
		"a",
		"transport-session/v0-s1/local/a",
		1,
		1,
		_intent(0.0, 1.0),
		1.0 / 60.0
	)
	var b_move := service.simulate_fixed_movement_tick(
		"b",
		"transport-session/v0-s1/local/b",
		1,
		1,
		_intent(1.0, 0.0),
		1.0 / 60.0
	)
	_assert(_ok(a_move), "Client A movement reaches authoritative fixed-tick simulation")
	_assert(_ok(b_move), "Client B movement reaches authoritative fixed-tick simulation")

	var a_after := _player_position(service.get_player("a"))
	var b_after := _player_position(service.get_player("b"))
	_assert(a_after.distance_to(a_before) > 0.05, "A authoritative position changes after A input")
	_assert(b_after.distance_to(b_before) > 0.05, "B authoritative position changes after B input")

	var snapshot_after: Dictionary = service.create_snapshot()
	_assert(_connected_player_count(snapshot_after) == 2, "two-player authoritative snapshot remains intact after movement")
	_assert(_snapshot_position(snapshot_after, "a").is_equal_approx(a_after), "replicated snapshot carries A movement")
	_assert(_snapshot_position(snapshot_after, "b").is_equal_approx(b_after), "replicated snapshot carries B movement")
	_assert(a_after.distance_to(b_after) > 0.5, "players remain distinct after bidirectional movement")

	service.shutdown()
	_finish()


func _intent(move_x: float, move_z: float) -> Dictionary:
	return {
		"move_x": move_x,
		"move_z": move_z,
		"look_yaw": 0.0,
		"look_pitch": 0.0,
		"jump_pressed": false,
		"sprint": false,
		"delta_seconds": 1.0 / 60.0,
	}


func _connected_player_count(snapshot: Dictionary) -> int:
	var count := 0
	for player_value in snapshot.get("players", []):
		if player_value is Dictionary and bool(player_value.get("connected", false)):
			count += 1
	return count


func _snapshot_position(snapshot: Dictionary, logical_player_id: String) -> Vector3:
	for player_value in snapshot.get("players", []):
		if not player_value is Dictionary:
			continue
		if String(player_value.get("logical_player_id", "")) == logical_player_id:
			return _position_from_record(player_value)
	return Vector3.INF


func _player_position(record: Dictionary) -> Vector3:
	return _position_from_record(record)


func _position_from_record(record: Dictionary) -> Vector3:
	var value: Dictionary = Dictionary(record.get("position", {}))
	return Vector3(
		float(value.get("x", 0.0)),
		float(value.get("y", 0.0)),
		float(value.get("z", 0.0))
	)


func _ok(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)


func _finish() -> void:
	print("V0-S1 local two-player contract: %d assertions, %d failures" % [
		assertions,
		failures.size(),
	])
	quit(0 if failures.is_empty() else 1)

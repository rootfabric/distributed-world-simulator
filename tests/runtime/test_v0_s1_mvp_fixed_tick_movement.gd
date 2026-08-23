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
		_ok(service.setup("simulation/v0-s1/fixed-tick", 1, 0, {
			"profile": Service.PROFILE_MULTIPLAYER_CORE,
			"topology_adapter": "TEST",
			"region_id": "region/v0-s1/fixed-tick",
			"playable_sandbox": false,
			"fixed_tick_authority": true,
		})),
		"V0-S1 service enables fixed-tick authority without playground mode"
	)
	_assert(
		_ok(service.join(
			"a",
			"transport-session/v0-s1/fixed-tick/a",
			"operation/v0-s1/fixed-tick/join/a"
		)),
		"V0-S1 player joins non-sandbox authoritative service"
	)
	_assert(
		_ok(service.advance_fixed_server_tick(1)),
		"V0-S1 authoritative server advances its first fixed tick"
	)

	var intent := {
		"move_x": 0.0,
		"move_z": 1.0,
		"look_yaw": 0.0,
		"look_pitch": 0.0,
		"jump_pressed": false,
		"sprint": false,
		"delta_seconds": 1.0 / 60.0,
	}
	var fixed_result: Dictionary = service.simulate_fixed_movement_tick(
		"a",
		"transport-session/v0-s1/fixed-tick/a",
		1,
		1,
		intent,
		1.0 / 60.0
	)
	_assert(
		_ok(fixed_result),
		"fixed-tick movement is available outside playable_sandbox"
	)
	var player: Dictionary = service.get_player("a")
	_assert(
		absf(float(player.get("position", {}).get("z", 0.0))) > 0.09,
		"fixed-tick movement mutates the authoritative player state"
	)

	# Keep the legacy direct MOVEMENT_INTENT contract sandbox-only. V0-S1 uses
	# queued fixed-tick input; removing this guard would silently broaden the old
	# command surface instead of only enabling the accepted NX3 authority path.
	var direct_result: Dictionary = service.submit_movement_intent(
		"a",
		"transport-session/v0-s1/fixed-tick/a",
		1,
		2,
		intent,
		"operation/v0-s1/fixed-tick/direct-intent/2"
	)
	_assert(
		_error(direct_result) == "MOVEMENT_INTENT_REQUIRES_PLAYABLE_SANDBOX",
		"legacy direct movement intent remains sandbox-only"
	)

	var disabled = Service.new()
	_assert(
		_ok(disabled.setup("simulation/v0-s1/no-fixed-tick", 1, 0, {
			"profile": Service.PROFILE_MULTIPLAYER_CORE,
			"topology_adapter": "TEST",
			"region_id": "region/v0-s1/no-fixed-tick",
			"playable_sandbox": false,
			"fixed_tick_authority": false,
		})),
		"control service without fixed-tick authority configures"
	)
	_assert(
		_error(disabled.advance_fixed_server_tick(1)) == "FIXED_TICK_AUTHORITY_NOT_ENABLED",
		"fixed-tick authority gate remains enforced"
	)

	service.shutdown()
	disabled.shutdown()
	_finish()


func _ok(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _error(result: Dictionary) -> String:
	return String(result.get("error_code", ""))


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)


func _finish() -> void:
	print("V0-S1 fixed-tick movement boundary: %d assertions, %d failures" % [
		assertions,
		failures.size(),
	])
	quit(0 if failures.is_empty() else 1)

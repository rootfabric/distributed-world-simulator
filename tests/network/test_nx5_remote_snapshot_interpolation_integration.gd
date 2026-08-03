extends SceneTree

const Presenter = preload(
	"res://scripts/runtime/networked_gameplay/m3/remote_player_presenter.gd"
)

class MockClientRuntime:
	extends RefCounted
	var snapshot: Dictionary = {}
	func get_snapshot() -> Dictionary:
		return snapshot.duplicate(true)

class MockWorld:
	extends Node3D
	var m3_multiplayer_client_runtime

var assertions := 0
var failures: Array[String] = []
var world: MockWorld
var runtime: MockClientRuntime


func _init() -> void:
	world = MockWorld.new()
	runtime = MockClientRuntime.new()
	world.m3_multiplayer_client_runtime = runtime
	root.add_child(world)
	_test_parent_snapshot_clock_and_render_delay()
	_test_bounded_extrapolation_and_reconnect_reset()
	_test_multiple_remote_players_are_isolated()
	world.queue_free()
	_finish()


func _test_parent_snapshot_clock_and_render_delay() -> void:
	var first := _record("b", Vector3.ZERO, Vector3(10.0, 0.0, 0.0), 1, 1)
	runtime.snapshot = _snapshot(100, 10, 1, [first])
	var presenter = Presenter.new()
	world.add_child(presenter)
	_assert(bool(presenter.setup(first).get("success", false)), "presenter setup from parent snapshot clock")
	_assert(presenter.position.is_equal_approx(Vector3.ZERO), "initial baseline snaps")
	_assert(not presenter.has_input_authority(), "remote presenter has no input authority")
	var initial_report: Dictionary = presenter.get_report()
	_assert(String(initial_report.get("schema", "")) == "planet_simulator.remote_player_presenter.v2", "NX5 presenter schema")
	_assert(int(initial_report.get("interpolation", {}).get("latest_server_tick", -1)) == 100, "parent server tick captured")
	_assert(int(initial_report.get("interpolation", {}).get("authority_epoch", 0)) == 1, "parent authority epoch captured")
	_assert(is_equal_approx(float(initial_report.get("interpolation", {}).get("config", {}).get("interpolation_delay_ms", 0.0)), 100.0), "100ms render delay")

	var second := _record("b", Vector3(1.0, 0.0, 0.0), Vector3(10.0, 0.0, 0.0), 2, 1)
	runtime.snapshot = _snapshot(106, 11, 1, [second])
	_assert(bool(presenter.apply_replica(second).get("success", false)), "second replica accepted")
	_assert(presenter.position.is_equal_approx(Vector3.ZERO), "arrival does not snap to latest target")
	presenter._process(1.0 / 60.0)
	_assert(presenter.position.distance_to(Vector3(1.0 / 6.0, 0.0, 0.0)) < 0.000001, "render tick interpolates one tick after delayed baseline")
	for index in range(5):
		presenter._process(1.0 / 60.0)
	_assert(presenter.position.distance_to(Vector3(1.0, 0.0, 0.0)) < 0.000001, "render reaches latest authoritative point after six frames")
	var report: Dictionary = presenter.get_report()
	_assert(String(report.get("interpolation_mode", "")) == "INTERPOLATE", "presenter reports interpolation mode")
	_assert(int(report.get("interpolation", {}).get("interpolation_samples", 0)) >= 6, "interpolation samples reported")
	_assert(int(report.get("updates", 0)) == 2, "replica update count")
	_assert(int(report.get("interpolation_failures", -1)) == 0, "no interpolation failures")

	var duplicate: Dictionary = presenter.apply_replica(second)
	_assert(bool(duplicate.get("success", false)), "duplicate snapshot is nonfatal")
	_assert(bool(duplicate.get("details", {}).get("duplicate", false)), "duplicate surfaced to presentation caller")
	_assert(int(presenter.get_report().get("interpolation", {}).get("duplicates_suppressed", 0)) == 1, "duplicate telemetry visible")

	var presentation_revision := second.duplicate(true)
	presentation_revision["state_revision"] = 3
	presentation_revision["orientation_yaw"] = PI / 3.0
	presentation_revision["flashlight_enabled"] = true
	runtime.snapshot = _snapshot(106, 12, 1, [presentation_revision])
	var same_tick_update: Dictionary = presenter.apply_replica(
		presentation_revision
	)
	_assert(
		bool(same_tick_update.get("success", false)),
		"newer outer revision inside the same server tick is accepted"
	)
	_assert(
		bool(same_tick_update.get("details", {}).get(
			"same_tick_replacement", false
		)),
		"same-tick replacement is surfaced to presentation caller"
	)
	var same_tick_report: Dictionary = presenter.get_report()
	_assert(
		bool(same_tick_report.get("flashlight_enabled", false)),
		"same-tick presentation revision updates flashlight target"
	)
	_assert(
		is_equal_approx(
			float(same_tick_report.get("orientation_yaw", 0.0)),
			PI / 3.0
		),
		"same-tick presentation revision updates orientation target"
	)
	_assert(
		int(same_tick_report.get(
			"interpolation", {}
		).get("same_tick_replacements", 0)) == 1,
		"same-tick replacement telemetry visible"
	)

	var stale_presentation := presentation_revision.duplicate(true)
	stale_presentation["flashlight_enabled"] = false
	runtime.snapshot = _snapshot(106, 11, 1, [stale_presentation])
	var stale_same_tick: Dictionary = presenter.apply_replica(stale_presentation)
	_assert(
		bool(stale_same_tick.get("success", false))
		and bool(stale_same_tick.get("details", {}).get("stale", false)),
		"older same-tick presentation revision is ignored nonfatally"
	)
	_assert(
		bool(presenter.get_report().get("flashlight_enabled", false)),
		"stale same-tick revision cannot roll back flashlight target"
	)

	var conflicting_revision := presentation_revision.duplicate(true)
	conflicting_revision["position"] = {"x": 9.0, "y": 0.0, "z": 0.0}
	runtime.snapshot = _snapshot(106, 12, 1, [conflicting_revision])
	var conflict_result: Dictionary = presenter.apply_replica(
		conflicting_revision
	)
	_assert(
		String(conflict_result.get("error_code", ""))
		== "CONFLICTING_REMOTE_SNAPSHOT_TICK",
		"conflicting state for the exact same clock tuple is rejected"
	)
	_assert(
		String(presenter.get_report().get("last_apply_error_code", ""))
		== "CONFLICTING_REMOTE_SNAPSHOT_TICK",
		"ignored apply failure remains observable in presenter report"
	)
	presenter.queue_free()


func _test_bounded_extrapolation_and_reconnect_reset() -> void:
	var first := _record("c", Vector3.ZERO, Vector3(6.0, 0.0, 0.0), 1, 1)
	runtime.snapshot = _snapshot(200, 20, 1, [first])
	var presenter = Presenter.new()
	world.add_child(presenter)
	_assert(bool(presenter.setup(first).get("success", false)), "extrapolation presenter setup")
	var second := _record("c", Vector3(0.6, 0.0, 0.0), Vector3(6.0, 0.0, 0.0), 2, 1)
	runtime.snapshot = _snapshot(206, 21, 1, [second])
	_assert(bool(presenter.apply_replica(second).get("success", false)), "extrapolation target accepted")
	for index in range(12):
		presenter._process(1.0 / 60.0)
	_assert(presenter.position.distance_to(Vector3(1.2, 0.0, 0.0)) < 0.000001, "extrapolation bounded at 100ms")
	presenter._process(1.0 / 60.0)
	_assert(presenter.position.distance_to(Vector3(0.6, 0.0, 0.0)) < 0.000001, "past horizon holds latest authoritative state")
	_assert(String(presenter.get_report().get("interpolation_mode", "")) == "HOLD_EXTRAPOLATION_LIMIT", "hold mode reported")

	var reconnect := _record("c", Vector3(20.0, 0.0, 0.0), Vector3.ZERO, 1, 2)
	reconnect["transport_session_id"] = "transport-session/m3/c/reconnect"
	runtime.snapshot = _snapshot(400, 1, 2, [reconnect])
	var reset: Dictionary = presenter.apply_replica(reconnect)
	_assert(bool(reset.get("success", false)), "reconnect snapshot accepted")
	_assert(String(reset.get("details", {}).get("reset_reason", "")) == "AUTHORITY_OR_SESSION_CHANGED", "reconnect resets timeline")
	_assert(presenter.position.is_equal_approx(Vector3(20.0, 0.0, 0.0)), "reconnect baseline snaps without crossing epochs")
	_assert(int(presenter.get_report().get("interpolation", {}).get("buffer_size", 0)) == 1, "old epoch samples discarded")
	_assert(int(presenter.get_report().get("interpolation", {}).get("identity_resets", 0)) == 1, "identity reset telemetry")

	var stale := second.duplicate(true)
	runtime.snapshot = _snapshot(401, 22, 1, [stale])
	var stale_result: Dictionary = presenter.apply_replica(stale)
	_assert(String(stale_result.get("error_code", "")) == "STALE_REMOTE_AUTHORITY_EPOCH", "stale old authority rejected")
	_assert(presenter.position.is_equal_approx(Vector3(20.0, 0.0, 0.0)), "stale snapshot cannot move presenter")
	_assert(int(presenter.get_report().get("interpolation_failures", 0)) == 1, "rejected snapshot counted")
	presenter.queue_free()


func _test_multiple_remote_players_are_isolated() -> void:
	var record_b := _record("b", Vector3(2.0, 0.0, 0.0), Vector3.ZERO, 1, 1)
	var record_c := _record("c", Vector3(-3.0, 0.0, 0.0), Vector3.ZERO, 1, 1)
	runtime.snapshot = _snapshot(500, 50, 3, [record_b, record_c])
	var presenter_b = Presenter.new()
	var presenter_c = Presenter.new()
	world.add_child(presenter_b)
	world.add_child(presenter_c)
	_assert(bool(presenter_b.setup(record_b).get("success", false)), "B setup")
	_assert(bool(presenter_c.setup(record_c).get("success", false)), "C setup")
	_assert(presenter_b.position.is_equal_approx(Vector3(2.0, 0.0, 0.0)), "B baseline independent")
	_assert(presenter_c.position.is_equal_approx(Vector3(-3.0, 0.0, 0.0)), "C baseline independent")
	var next_b := _record("b", Vector3(4.0, 0.0, 0.0), Vector3.ZERO, 2, 1)
	runtime.snapshot = _snapshot(506, 51, 3, [next_b, record_c])
	_assert(bool(presenter_b.apply_replica(next_b).get("success", false)), "B update accepted")
	presenter_b._process(1.0 / 60.0)
	_assert(presenter_b.position.x > 2.0 and presenter_b.position.x < 4.0, "B interpolates")
	_assert(presenter_c.position.is_equal_approx(Vector3(-3.0, 0.0, 0.0)), "C unaffected by B update")
	_assert(String(presenter_b.get_report().get("logical_player_id", "")) == "b", "B identity remains bound")
	_assert(String(presenter_c.get_report().get("logical_player_id", "")) == "c", "C identity remains bound")
	presenter_b.queue_free()
	presenter_c.queue_free()


func _snapshot(
	server_tick: int,
	revision: int,
	authority_epoch: int,
	players: Array
) -> Dictionary:
	return {
		"server_tick": server_tick,
		"revision": revision,
		"authority_epoch": authority_epoch,
		"players": players.duplicate(true),
	}


func _record(
	logical_id: String,
	position: Vector3,
	velocity: Vector3,
	state_revision: int,
	ownership_epoch: int
) -> Dictionary:
	return {
		"logical_player_id": logical_id,
		"player_entity_id": "player/%s" % logical_id,
		"transport_session_id": "transport-session/m3/%s/nx5" % logical_id,
		"ownership_epoch": ownership_epoch,
		"connected": true,
		"position": {"x": position.x, "y": position.y, "z": position.z},
		"velocity": {"x": velocity.x, "y": velocity.y, "z": velocity.z},
		"inventory": [],
		"last_input_sequence": maxi(0, state_revision),
		"state_revision": maxi(1, state_revision),
		"orientation_yaw": 0.0,
		"flashlight_enabled": false,
	}


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("NX5 remote snapshot interpolation integration: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("NX5 remote snapshot interpolation integration: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)

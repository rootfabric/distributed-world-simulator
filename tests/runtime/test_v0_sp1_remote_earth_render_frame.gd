extends SceneTree

const PresenterScript = preload("res://scripts/app/earth_m3_remote_spectator_presenter.gd")

var assertions := 0
var failures: Array[String] = []


class FakeEarthWorld:
	extends Node3D
	var render_origin := Vector3(0.0, 100.0, 0.0)

	func get_render_origin() -> Vector3:
		return render_origin


class Host:
	extends Node3D
	var earth_world


func _init() -> void:
	var host := Host.new()
	var world := FakeEarthWorld.new()
	host.earth_world = world
	host.add_child(world)
	get_root().add_child(host)

	var presenter = PresenterScript.new()
	host.add_child(presenter)
	var record := {
		"logical_player_id": "b",
		"player_entity_id": "player/b",
		"transport_session_id": "transport-session/test/b",
		"ownership_epoch": 1,
		"connected": true,
		"position": {"x": 10.0, "y": 0.0, "z": 4.0},
		"velocity": {"x": 0.0, "y": 0.0, "z": 0.0},
		"inventory": [],
		"last_input_sequence": 0,
		"state_revision": 1,
		"orientation_yaw": 0.0,
		"flashlight_enabled": false,
	}
	var snapshot := {
		"authority_epoch": 1,
		"server_tick": 1,
		"revision": 1,
	}
	var setup := presenter.setup(record, snapshot, Callable(self, "_map_position"))
	_assert(bool(setup.get("success", false)), "presenter setup")
	await process_frame

	var canonical_before: Vector3 = presenter.earth_mapped_position
	var render_before: Vector3 = presenter.position
	var report: Dictionary = presenter.get_report()
	_assert(bool(report.get("render_frame_ready", false)), "shared Earth render frame active")
	_assert(
		String(report.get("spatial_projection", "")) == "EARTH_FIXED_TO_SHARED_RENDER_FRAME",
		"shared projector reported"
	)

	# Old implementation changed remote presentation when these local-player
	# diagnostics changed. Shared render-frame mode must ignore them.
	presenter.set_local_planar_position(Vector2(500.0, -700.0))
	presenter.set_local_vertical_offset(80.0)
	var after_local_state: Vector3 = presenter.position
	_assert(
		after_local_state.distance_to(render_before) < 0.001,
		"local player offsets do not move remote replica"
	)

	# Detached spectator moves the shared floating origin. The canonical remote
	# position is unchanged, while its render position shifts exactly with the
	# origin just like terrain/buildings do.
	world.render_origin += Vector3(0.0, 25.0, 0.0)
	await process_frame
	var render_after_spectator: Vector3 = presenter.position
	_assert(
		presenter.earth_mapped_position.distance_to(canonical_before) < 0.001,
		"spectator does not mutate remote canonical Earth position"
	)
	_assert(
		absf((render_after_spectator.y - render_before.y) + 25.0) < 0.01,
		"remote replica follows shared spectator render origin"
	)

	world.render_origin += Vector3(30.0, 0.0, -40.0)
	await process_frame
	var render_after_translation: Vector3 = presenter.position
	var expected_delta := Vector3(-30.0, 0.0, 40.0)
	_assert(
		(render_after_translation - render_after_spectator).distance_to(expected_delta) < 0.01,
		"remote replica uses same floating-origin translation as world"
	)
	_assert(
		presenter.basis.y.normalized().dot(canonical_before.normalized()) > 0.99,
		"remote surface orientation remains Earth-relative"
	)

	presenter.queue_free()
	host.queue_free()
	await process_frame
	_finish()


func _map_position(x: float, z: float) -> Vector3:
	return Vector3(x, 101.75, z)


func _assert(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("V0-SP1 remote Earth render frame: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("V0-SP1 remote Earth render frame: FAIL (%d failures)" % failures.size())
	quit(1)

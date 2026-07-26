extends SceneTree

const MAIN_SCENE_PATH := "res://main.tscn"
const MAX_IDLE_WAIT_FRAMES := 900

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed = load(MAIN_SCENE_PATH)
	_assert(packed is PackedScene, "Main simulator scene failed to load.")
	if not packed is PackedScene:
		_finish()
		return

	var simulator = packed.instantiate()
	get_root().add_child(simulator)
	current_scene = simulator
	await process_frame
	await process_frame
	await process_frame

	_assert(
		simulator.get_current_world_id() == "earth_moon",
		"The generation-switch test requires the default earth_moon world."
	)
	var old_runtime = simulator.get_current_runtime()
	_assert(old_runtime != null, "The initial planetary runtime is missing.")
	if old_runtime == null:
		_finish()
		return

	var moon_world = old_runtime.get("moon_world")
	_assert(moon_world != null, "The planetary runtime has no Moon world.")
	if moon_world == null:
		_finish()
		return

	var streamer = moon_world.get("terrain_streamer")
	_assert(streamer != null, "The Moon terrain streamer is missing.")
	if streamer == null:
		_finish()
		return

	await _wait_until_streamer_is_active(streamer)
	var active_snapshot: Dictionary = streamer.create_snapshot()
	_assert(
		String(active_snapshot.get("state", "")) == "ACTIVE",
		"Terrain streamer did not become ACTIVE before the forced request."
	)

	var active_direction := _vector_from_array(
		active_snapshot.get("active_center_direction", [0.0, 1.0, 0.0])
	)
	if active_direction.length_squared() < 0.5:
		active_direction = Vector3.UP
	var request_id: int = int(streamer.request_surface(
		-active_direction.normalized(),
		false,
		false,
		"world_switch_during_generation_test",
		0,
		true
	))
	_assert(request_id > 0, "The forced terrain request was not accepted.")

	var generating_snapshot: Dictionary = streamer.create_snapshot()
	_assert(
		String(generating_snapshot.get("state", "")) == "GENERATING",
		"The terrain request was not active when the world switch started."
	)
	_assert(
		int(generating_snapshot.get("running_request", {}).get("request_id", -1))
		== request_id,
		"The active terrain request ID does not match the forced request."
	)

	var switch_result: Dictionary = simulator.load_world("playground", false)
	_assert(
		bool(switch_result.get("success", false)),
		"Switching to playground failed while terrain generation was active."
	)
	_assert(
		simulator.get_current_world_id() == "playground",
		"The simulator did not activate playground after the switch."
	)
	_assert(
		simulator.world_host.get_child_count() == 1,
		"WorldHost must contain exactly one runtime after the switch."
	)

	var cancelled_snapshot: Dictionary = streamer.create_snapshot()
	_assert(
		int(cancelled_snapshot.get("cancelled_through_revision", 0)) >= request_id,
		"Runtime unload did not fence the active terrain generation revision."
	)
	_assert(
		String(cancelled_snapshot.get("state", "")) == "ACTIVE",
		"Terrain streamer was not returned to a safe state during unload."
	)
	_assert(
		cancelled_snapshot.get("pending_request", {}).is_empty(),
		"A pending terrain request survived runtime unload."
	)

	await process_frame
	await process_frame
	_assert(
		not is_instance_valid(old_runtime),
		"The previous planetary runtime survived deferred unload."
	)
	_assert(
		simulator.command_registry.has_command("playground.spawn_box"),
		"Playground commands were not registered after the switch."
	)
	_assert(
		not simulator.command_registry.has_command("world.beacon.place"),
		"A lunar command leaked after switching away during generation."
	)

	_finish()


func _wait_until_streamer_is_active(streamer) -> void:
	for _frame_index in range(MAX_IDLE_WAIT_FRAMES):
		var snapshot: Dictionary = streamer.create_snapshot()
		if (
			String(snapshot.get("state", "")) == "ACTIVE"
			and snapshot.get("running_request", {}).is_empty()
			and snapshot.get("pending_request", {}).is_empty()
			and String(snapshot.get("commit_stage", "")) == "idle"
		):
			return
		await process_frame


func _vector_from_array(value) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


func _finish() -> void:
	if failures.is_empty():
		print("World switch during generation: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("World switch during generation: FAIL (%d)" % failures.size())
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

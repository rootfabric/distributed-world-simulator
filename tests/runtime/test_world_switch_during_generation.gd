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

	var persistence = old_runtime.get("persistence")
	_assert(persistence != null, "The initial planetary runtime has no persistence repository.")
	if persistence != null:
		_assert(
			bool(persistence.get("initialized")),
			"The initial planetary persistence repository failed to initialize."
		)

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

	var request_context: Dictionary = await _acquire_generation_request(streamer)
	_assert(
		not request_context.is_empty(),
		"Terrain streamer did not expose an active request before the world switch."
	)
	if request_context.is_empty():
		_finish()
		return
	var request_id: int = int(request_context.get("request_id", -1))
	_assert(request_id > 0, "The terrain request ID is invalid.")

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

	var drain_result: Dictionary = simulator._last_runtime_drain
	var terrain_drain: Dictionary = drain_result.get("details", {}).get("terrain", {})
	_assert(bool(drain_result.get("success", false)), "Runtime lifecycle drain failed.")
	_assert(bool(drain_result.get("drained", false)), "Runtime was not fully drained.")
	_assert(
		int(terrain_drain.get("cancelled_through_revision", 0)) >= request_id,
		"Runtime unload did not fence the active terrain generation revision."
	)
	_assert(
		String(terrain_drain.get("state", "")) == "STOPPED",
		"Terrain streamer did not reach STOPPED before runtime disposal."
	)
	_assert(
		bool(terrain_drain.get("within_timeout", false)),
		"Terrain streamer exceeded the configured drain timeout."
	)
	_assert(
		not is_instance_valid(old_runtime),
		"The previous planetary runtime survived synchronous drain/disposal."
	)

	await process_frame
	await process_frame
	_assert(
		simulator.command_registry.has_command("playground.spawn_box"),
		"Playground commands were not registered after the switch."
	)
	_assert(
		not simulator.command_registry.has_command("world.beacon.place"),
		"A lunar command leaked after switching away during generation."
	)

	_finish()


func _acquire_generation_request(streamer) -> Dictionary:
	for _frame_index in range(MAX_IDLE_WAIT_FRAMES):
		var snapshot: Dictionary = streamer.create_snapshot()
		var running_request: Dictionary = snapshot.get("running_request", {})
		if (
			String(snapshot.get("state", "")) == "GENERATING"
			and not running_request.is_empty()
		):
			return {
				"request_id": int(running_request.get("request_id", -1)),
				"source": "existing",
			}
		if (
			String(snapshot.get("state", "")) == "ACTIVE"
			and running_request.is_empty()
			and snapshot.get("pending_request", {}).is_empty()
			and String(snapshot.get("commit_stage", "")) == "idle"
		):
			var active_direction := _vector_from_array(
				snapshot.get("active_center_direction", [0.0, 1.0, 0.0])
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
			if request_id > 0:
				return {"request_id": request_id, "source": "forced"}
		await create_timer(0.01).timeout
	return {}


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

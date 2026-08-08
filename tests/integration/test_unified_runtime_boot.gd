extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed = load("res://main.tscn")
	_assert(packed is PackedScene, "Main scene failed to load.")
	if not packed is PackedScene:
		_finish()
		return

	var simulator = packed.instantiate()
	get_root().add_child(simulator)
	current_scene = simulator
	await process_frame
	await process_frame
	await process_frame

	_assert(simulator.get_current_world_id() == "earth_moon", "Default earth_moon world was not selected.")
	var planetary_runtime = simulator.get_current_runtime()
	_assert(planetary_runtime != null, "Planetary runtime was not created.")
	if planetary_runtime != null:
		var persistence = planetary_runtime.get("persistence")
		_assert(persistence != null, "Planetary runtime persistence repository is missing.")
		if persistence != null:
			_assert(
				bool(persistence.get("initialized")),
				"Planetary runtime persistence repository failed to initialize."
			)
		_assert(planetary_runtime.celestial_system != null, "Celestial system was not initialized.")
		_assert(planetary_runtime.shared_space_mode, "Shared-space startup mode did not activate.")
		_assert(planetary_runtime.earth_initialized, "Earth did not initialize lazily.")
		var observer_space_position: Vector3 = (
			planetary_runtime.earth_explorer.get_world_position()
		)
		var observer_moon_direction: Vector3 = (
			planetary_runtime.celestial_system.to_body_local(
				observer_space_position,
				"moon"
			).normalized()
		)
		_assert(
			simulator._execute_first_available_command(
				simulator.get_hotkey_command_candidates(KEY_F2)
			),
			"F2 command route was not executed."
		)
		await process_frame
		_assert(
			not planetary_runtime.shared_space_mode,
			"F2 did not return control to the player."
		)
		_assert(
			planetary_runtime.player.get_world_position().normalized().dot(
				observer_moon_direction
			) > 0.999,
			"F2 did not move the player to the spectator surface position."
		)
		var camera_mode_before: String = (
			planetary_runtime.player.get_camera_mode()
		)
		_assert(
			simulator._execute_first_available_command(
				simulator.get_hotkey_command_candidates(KEY_F5)
			),
			"F5 camera command route was not executed."
		)
		_assert(
			planetary_runtime.player.get_camera_mode() != camera_mode_before,
			"F5 did not toggle first-person and third-person camera modes."
		)
		_assert(
			simulator._execute_first_available_command(
				simulator.get_hotkey_command_candidates(KEY_J)
			),
			"J controller command route was not executed."
		)
		_assert(
			planetary_runtime.player.get_controller_id() == "lunar_jetpack",
			"J did not activate the lunar jetpack controller."
		)
		_assert(
			simulator._execute_first_available_command(
				simulator.get_hotkey_command_candidates(KEY_F3)
			),
			"F3 command route was not executed."
		)
		await process_frame
		_assert(
			planetary_runtime.shared_space_mode,
			"F3 did not switch from player to shared-space spectator."
		)
		var lod_debug_before: bool = planetary_runtime.moon_world.is_lod_debug_enabled()
		_assert(
			simulator._execute_first_available_command(
				simulator.get_hotkey_command_candidates(KEY_F4)
			),
			"F4 command route was not executed."
		)
		_assert(
			planetary_runtime.moon_world.is_lod_debug_enabled()
			!= lod_debug_before,
			"F4 did not toggle LOD visualization."
		)

	var earth_result: Dictionary = simulator.execute_command("world.load earth")
	_assert(bool(earth_result.get("success", false)), "earth command route failed.")
	await process_frame
	await process_frame
	await process_frame
	var earth_runtime = simulator.get_current_runtime()
	_assert(earth_runtime != null, "Dedicated Earth runtime was not created.")
	if earth_runtime != null:
		var earth_snapshot: Dictionary = earth_runtime.create_runtime_snapshot()
		var celestial_snapshot: Dictionary = earth_snapshot.get("celestial_system", {})
		var body_ids: Array = celestial_snapshot.get("body_ids", [])
		_assert(body_ids.size() == 1 and body_ids.has("earth"), "Earth runtime leaked another celestial body.")
	_assert(not simulator.command_registry.has_command("world.beacon.place"), "Lunar command leaked into Earth runtime.")
	_assert(simulator.command_registry.has_command("display.fullscreen.toggle"), "Core display command disappeared after Earth load.")

	var item_result: Dictionary = simulator.execute_command("world.load item_lab")
	_assert(bool(item_result.get("success", false)), "item_lab command route failed.")
	await process_frame
	await process_frame
	var lab = simulator.get_current_runtime()
	_assert(lab != null and lab.has_method("get_debug_snapshot"), "Item laboratory runtime contract is unavailable.")

	var playground_result: Dictionary = simulator.execute_command("world.load playground")
	_assert(bool(playground_result.get("success", false)), "playground command route failed.")
	await process_frame
	await process_frame
	var playground = simulator.get_current_runtime()
	_assert(playground != null and playground.player != null, "Playground player was not initialized.")
	_assert(simulator.command_registry.has_command("playground.spawn_box"), "Playground commands were not registered.")

	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("Unified runtime boot test: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Unified runtime boot test: FAIL (%d)" % failures.size())
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

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

	var app = packed.instantiate()
	get_root().add_child(app)
	current_scene = app
	await process_frame
	await process_frame

	_assert(
		app.celestial_system != null,
		"Celestial system was not initialized by the main runtime."
	)
	_assert(
		app.celestial_system.get_body_ids().has("moon")
		and app.celestial_system.get_body_ids().has("earth"),
		"Main runtime does not expose both Moon and Earth."
	)
	_assert(
		app.world_interactor != null,
		"World interaction was not initialized."
	)
	_assert(
		app.persistence != null
		and app.persistence.has_method("toggle_survey_beacon_signal"),
		"Interactive beacon persistence contract is unavailable."
	)

	app.toggle_shared_space_mode()
	await process_frame
	await process_frame
	_assert(app.shared_space_mode, "Shared Earth-Moon mode did not activate.")
	_assert(app.earth_initialized, "Earth did not initialize lazily.")
	_assert(
		app.earth_world != null and app.earth_world.visible,
		"Procedural Earth is not visible in shared-space mode."
	)

	app.open_item_system_lab()
	await process_frame
	await process_frame
	var lab = current_scene
	_assert(lab != null, "Item laboratory scene was not installed.")
	if lab != null:
		_assert(
			String(lab.get_script().resource_path)
			== "res://scripts/items/presentation/item_system_lab.gd",
			"F5 route did not switch to the item laboratory."
		)
		_assert(
			lab.has_method("get_debug_snapshot"),
			"Item laboratory runtime contract is unavailable."
		)

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

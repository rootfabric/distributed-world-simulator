extends SceneTree

const SimulatorAppScript = preload("res://scripts/app/simulator_app.gd")

var failures: Array[String] = []


func _init() -> void:
	var app = SimulatorAppScript.new()
	app._ensure_input_actions()

	_assert(
		app.get_hotkey_command_candidates(KEY_F2)
		== ["player.teleport.spectator"],
		"F2 must teleport the player to the spectator."
	)
	_assert(
		app.get_hotkey_command_candidates(KEY_F3)
		== ["space.mode.toggle", "player.spectator.toggle"],
		"F3 must prefer the shared-space spectator and fall back to lunar spectator."
	)
	_assert(
		app.get_hotkey_command_candidates(KEY_F4)[0]
		== "world.lod.debug.toggle",
		"F4 must toggle LOD visualization."
	)
	_assert(
		app.get_hotkey_command_candidates(KEY_F5)
		== ["player.camera.toggle"],
		"F5 must toggle first-person and third-person camera modes."
	)
	_assert(
		app.get_hotkey_command_candidates(KEY_J)
		== ["player.controller.toggle"],
		"J must toggle the humanoid and jetpack controllers."
	)
	_assert(app.get_inventory_hotbar_command_for_key(KEY_1) == "inventory.hotbar.select 1", "1 must select the first inventory hotbar slot.")
	_assert(app.get_inventory_hotbar_command_for_key(KEY_0) == "inventory.hotbar.select 10", "0 must select the tenth inventory hotbar slot.")
	_assert(
		_action_has_physical_key("roll_left", KEY_E),
		"E must roll the spectator left."
	)
	_assert(
		_action_has_physical_key("roll_right", KEY_Q),
		"Q must roll the spectator right."
	)
	_assert(
		not _action_has_physical_key("roll_right", KEY_R),
		"R must not remain bound to spectator roll."
	)

	app.free()
	_finish()


func _action_has_physical_key(action_name: StringName, keycode: int) -> bool:
	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey and event.physical_keycode == keycode:
			return true
	return false


func _finish() -> void:
	if failures.is_empty():
		print("Hotkey contract tests: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Hotkey contract tests: FAIL (%d)" % failures.size())
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

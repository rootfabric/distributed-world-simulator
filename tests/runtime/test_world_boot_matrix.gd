extends SceneTree

const MAIN_SCENE_PATH := "res://main.tscn"
const WORLD_IDS := ["moon", "earth", "earth_moon", "item_lab", "playground"]
const COMMAND_EXPECTATIONS := {
	"moon": {
		"required": ["world.beacon.place"],
		"forbidden": ["earth.rules.reload", "item.graph.validate", "playground.spawn_box"],
	},
	"earth": {
		"required": ["earth.rules.reload", "space.teleport.body"],
		"forbidden": ["world.beacon.place", "space.focus.other_body", "item.graph.validate"],
	},
	"earth_moon": {
		"required": ["world.beacon.place", "earth.rules.reload", "space.focus.other_body"],
		"forbidden": ["item.graph.validate", "playground.spawn_box"],
	},
	"item_lab": {
		"required": ["item.graph.validate"],
		"forbidden": ["world.beacon.place", "earth.rules.reload", "playground.spawn_box"],
	},
	"playground": {
		"required": ["playground.spawn_box", "player.reset", "player.interact"],
		"forbidden": ["world.beacon.place", "earth.rules.reload", "item.graph.validate"],
	},
}

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

	_assert(simulator.get_current_world_id() == "earth_moon", "Default world did not load.")
	_assert(simulator.command_registry.has_command("world.load"), "Core world.load command is missing.")
	_assert(simulator.command_registry.has_command("display.fullscreen.toggle"), "Core display command is missing.")
	_assert(simulator.command_registry.has_command("display.resolution.cycle"), "Core resolution command is missing.")
	_assert(simulator.developer_console != null, "Developer console was not initialized.")
	_test_console_process_lifecycle(simulator)

	for world_id in WORLD_IDS:
		var load_result: Dictionary = simulator.load_world(world_id, false)
		_assert(bool(load_result.get("success", false)), "World failed to load: %s" % world_id)
		await process_frame
		await process_frame
		await process_frame
		var runtime = simulator.get_current_runtime()
		_assert(runtime != null, "World has no runtime: %s" % world_id)
		_assert(simulator.world_host.get_child_count() == 1, "WorldHost must contain exactly one runtime: %s" % world_id)
		_assert(simulator.command_registry.get_owner_command_count("active_world") > 0, "World registered no commands: %s" % world_id)
		_assert(simulator.command_registry.get_registration_errors().is_empty(), "Command registration errors remain after load: %s" % world_id)
		_assert(simulator.test_registry.get_registration_errors().is_empty(), "Test registration errors remain after load: %s" % world_id)
		_assert(simulator.command_registry.has_command("display.fullscreen.toggle"), "Core display command disappeared in %s" % world_id)
		_assert(simulator.command_registry.has_command("display.resolution.cycle"), "Core resolution command disappeared in %s" % world_id)
		_assert_world_command_surface(simulator, world_id)
		if runtime == null:
			continue
		_assert(runtime.has_method("create_runtime_snapshot"), "Runtime snapshot contract missing: %s" % world_id)
		_assert(simulator.test_registry.list_tests("active_world").size() > 0, "World registered no regression tests: %s" % world_id)
		_assert_optional_diagnostic_menu_is_closed(runtime, world_id)
		var suite: Dictionary = simulator.test_registry.run_all("active_world")
		_assert(bool(suite.get("passed", false)), "World regression suite failed: %s -> %s" % [world_id, suite.get("output", "")])

	_finish()


func _test_console_process_lifecycle(simulator) -> void:
	var runtime = simulator.get_current_runtime()
	_assert(runtime != null, "Console lifecycle test has no active runtime.")
	if runtime == null:
		return
	var initial_process_mode: int = runtime.process_mode
	simulator.developer_console.set_open(true)
	simulator.developer_console.set_open(true)
	_assert(
		runtime.process_mode == Node.PROCESS_MODE_DISABLED,
		"Open console did not pause the active runtime."
	)
	simulator.developer_console.set_open(false)
	_assert(
		runtime.process_mode == initial_process_mode,
		"Repeated console.open corrupted the runtime process mode."
	)


func _assert_optional_diagnostic_menu_is_closed(runtime, world_id: String) -> void:
	if world_id not in ["moon", "earth_moon"]:
		return
	var runtime_hud = runtime.get("hud")
	if runtime_hud == null or not runtime_hud.has_method("is_menu_visible"):
		_assert(false, "Lunar diagnostic HUD is missing in %s" % world_id)
		return
	_assert(
		not bool(runtime_hud.call("is_menu_visible")),
		"World-specific diagnostics menu intercepted startup in %s" % world_id
	)


func _finish() -> void:
	if failures.is_empty():
		print("World boot matrix: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("World boot matrix: FAIL (%d)" % failures.size())
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _assert_world_command_surface(simulator, world_id: String) -> void:
	var expectation: Dictionary = COMMAND_EXPECTATIONS.get(world_id, {})
	for command_id in expectation.get("required", []):
		_assert(
			simulator.command_registry.has_command(String(command_id)),
			"Required command is missing in %s: %s" % [world_id, command_id]
		)
	for command_id in expectation.get("forbidden", []):
		_assert(
			not simulator.command_registry.has_command(String(command_id)),
			"Foreign command leaked into %s: %s" % [world_id, command_id]
		)

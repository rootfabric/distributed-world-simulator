extends SceneTree

const CommandRegistry = preload("res://scripts/core/command_registry.gd")
const DeveloperConsole = preload("res://scripts/ui/developer_console.gd")
const SystemMenu = preload("res://scripts/ui/system_menu.gd")
const LunarPlayer = preload("res://scripts/actors/player/lunar_player.gd")
const FlatWorldAdapter = preload("res://scripts/world/testing/flat_world_adapter.gd")

class FakeCatalog:
	extends RefCounted
	func list_worlds() -> Array[Dictionary]:
		return [
			{"id": "playground", "display_name": "Полигон"},
			{"id": "moon", "display_name": "Луна"},
		]

class FakeSimulator:
	extends RefCounted
	var current_world_id: String = "playground"
	var grant_quantity: int = 0
	func get_debug_item_catalog() -> Array[Dictionary]:
		return [{"definition_id": "survey_beacon", "display_name": "Полевой маяк"}]
	func grant_debug_item(_definition_id: String, quantity: int) -> Dictionary:
		grant_quantity += quantity
		return {"success": true, "message": "Выдано"}
	func load_world(world_id: String) -> Dictionary:
		current_world_id = world_id
		return {"success": true, "output": "loaded"}

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = CommandRegistry.new()
	registry.register_command({"id": "help"}, Callable(self, "_help"), "test")
	var console = DeveloperConsole.new()
	get_root().add_child(console)
	console.setup(registry, null)
	console.set_completion_provider(Callable(self, "_complete"))
	console.set_open(true)
	console.execute_line("help")
	console.input_line.text = ""
	console.history_index = console.history.size()
	console._show_history(-1)
	await process_frame
	_assert(console.input_line.text == "help", "Up history must restore previous command")
	_assert(console.input_line.has_focus(), "History recall must restore keyboard focus without mouse click")
	_assert(console.input_line.caret_column == console.input_line.text.length(), "History recall must place caret at end for immediate editing")
	console.input_line.text = "world.load pl"
	console.input_line.caret_column = console.input_line.text.length()
	console._complete_command()
	await process_frame
	_assert(console.input_line.text == "world.load playground ", "Tab completion must complete command arguments")
	_assert(console.input_line.has_focus(), "Tab completion must preserve input focus")
	_assert(console.input_line.caret_column == console.input_line.text.length(), "Tab completion must preserve resulting caret position")

	var fake_simulator = FakeSimulator.new()
	var menu = SystemMenu.new()
	get_root().add_child(menu)
	menu.setup(fake_simulator, FakeCatalog.new())
	menu.set_open(true)
	_assert(menu.panel.visible and menu.worlds_box.get_child_count() == 2, "F10 system menu must render one-click world list")
	_assert(menu.items_box.get_child_count() == 1, "System menu must render debug item catalog")
	var item_row = menu.items_box.get_child(0)
	var hundred_button = item_row.get_child(2) as Button
	hundred_button.pressed.emit()
	_assert(fake_simulator.grant_quantity == 100, "Admin ×100 button must request exact quantity")
	var moon_button = menu.worlds_box.get_child(1) as Button
	moon_button.pressed.emit()
	_assert(fake_simulator.current_world_id == "moon", "World menu button must switch location in one click")

	var adapter = FlatWorldAdapter.new()
	get_root().add_child(adapter)
	adapter.setup(Vector3.ZERO)
	var player = LunarPlayer.new()
	get_root().add_child(player)
	player.setup(adapter, null, "flat_humanoid")
	var initial := player.get_flashlight_snapshot()
	_assert(not bool(initial.get("enabled", true)), "Area flashlight must start disabled")
	_assert(absf(float(initial.get("range_m", 0.0)) - 1000.0) < 0.001, "Area flashlight must cover configured 1000 metre radius")
	_assert(String(initial.get("light_type", "")) == "OMNI_DUAL_FILL", "Player flashlight must use dual omnidirectional flood layers")
	_assert(int(initial.get("layer_count", 0)) == 2, "Flashlight must combine wide terrain fill and readable near fill")
	_assert(float(initial.get("energy", 0.0)) >= 60.0 and float(initial.get("attenuation", 1.0)) <= 0.05, "Wide 1000 m fill must have enough energy and slow attenuation for lunar terrain")
	_assert(float(initial.get("near_range_m", 0.0)) >= 90.0 and float(initial.get("near_energy", 0.0)) >= 6.0, "Near layer must keep nearby objects readable")
	_assert(player.toggle_flashlight() and player.area_flashlight.visible and player.near_flashlight.visible, "Flashlight toggle must enable both light layers")
	_assert(not player.toggle_flashlight() and not player.area_flashlight.visible and not player.near_flashlight.visible, "Second flashlight toggle must disable both light layers")

	player.queue_free()
	adapter.queue_free()
	menu.queue_free()
	console.queue_free()
	await process_frame
	_finish()


func _help(_arguments: Array[String]) -> Dictionary:
	return {"success": true, "output": "ok"}


func _complete(command_line: String, _caret: int) -> Array[String]:
	if command_line.begins_with("world.load pl"):
		return ["playground"]
	return []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("Console, system menu and flashlight: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Console, system menu and flashlight: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)

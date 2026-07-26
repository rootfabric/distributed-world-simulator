extends SceneTree

const MAIN_SCENE_PATH := "res://main.tscn"

var failures: Array[String] = []


func _init() -> void:
	var main_scene = load(MAIN_SCENE_PATH)
	_assert(main_scene is PackedScene, "Unified main scene must load.")
	if main_scene is PackedScene:
		var simulator = main_scene.instantiate()
		_assert(
			String(simulator.get_script().resource_path)
			== "res://scripts/app/simulator_app.gd",
			"main.tscn must use the common SimulatorApp shell."
		)
		_assert(simulator.has_method("load_world"), "World loading contract is missing.")
		_assert(simulator.has_method("execute_command"), "Command execution contract is missing.")
		simulator.free()

	_assert(FileAccess.file_exists("res://config/worlds/catalog.json"), "World catalog is missing.")
	_assert(FileAccess.file_exists("res://scripts/core/command_registry.gd"), "Command registry is missing.")
	_assert(FileAccess.file_exists("res://scripts/ui/developer_console.gd"), "Developer console is missing.")
	_assert(FileAccess.file_exists("res://scripts/app/earth_app.gd"), "Dedicated Earth runtime is missing.")
	_assert(FileAccess.file_exists("res://scenes/testing/playground.tscn"), "Playground scene is missing.")

	if failures.is_empty():
		print("Unified planetary runtime tests: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Unified planetary runtime tests: FAIL (%d)" % failures.size())
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

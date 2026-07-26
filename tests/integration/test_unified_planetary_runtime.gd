extends SceneTree

const MAIN_SCENE_PATH := "res://main.tscn"
const ITEM_LAB_SCENE_PATH := "res://scenes/items/item_system_lab.tscn"

var failures: Array[String] = []


func _init() -> void:
	var main_scene = load(MAIN_SCENE_PATH)
	_assert(main_scene is PackedScene, "Unified main scene must load.")
	if main_scene is PackedScene:
		var app = main_scene.instantiate()
		_assert(
			String(app.get_script().resource_path)
			== "res://scripts/app/planetary_app.gd",
			"main.tscn must use the unified planetary app."
		)
		_assert(
			app.has_method("toggle_shared_space_mode"),
			"Earth-Moon shared-space mode is missing."
		)
		_assert(
			app.has_method("open_item_system_lab"),
			"Item laboratory entrypoint is missing."
		)
		_assert(
			app.has_method("interact_with_world"),
			"First-person world interaction is missing."
		)
		_assert(
			app.has_method("toggle_beacon_markers"),
			"Persistent beacon marker control is missing."
		)
		app.free()

	_assert(
		load(ITEM_LAB_SCENE_PATH) is PackedScene,
		"Item laboratory scene must remain loadable."
	)
	_assert(
		FileAccess.file_exists("res://config/planets/celestial_system.json"),
		"Celestial system configuration is missing."
	)
	_assert(
		FileAccess.file_exists("res://config/planets/earth.json"),
		"Earth configuration is missing."
	)
	_assert(
		FileAccess.file_exists("res://scripts/interaction/survey_beacon_interactable.gd"),
		"Survey beacon interaction implementation is missing."
	)

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

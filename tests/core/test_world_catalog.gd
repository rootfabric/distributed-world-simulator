extends SceneTree

const WorldCatalogScript = preload("res://scripts/core/world_catalog.gd")
const CATALOG_PATH := "res://config/worlds/catalog.json"

var failures: Array[String] = []


func _init() -> void:
	var catalog = WorldCatalogScript.new()
	_assert(catalog.load_catalog(CATALOG_PATH), "World catalog failed validation.")
	for error_message in catalog.get_validation_errors():
		failures.append(String(error_message))
	_assert(catalog.get_default_world_id() == "earth_moon", "Unexpected default world.")
	for world_id in ["moon", "earth", "earth_moon", "item_lab", "playground"]:
		_assert(catalog.has_world(world_id), "Missing world: %s" % world_id)
		var definition: Dictionary = catalog.get_world(world_id)
		_assert(not String(definition.get("display_name", "")).is_empty(), "World has no display name: %s" % world_id)
	var earth_definition: Dictionary = catalog.get_world("earth")
	_assert(
		String(earth_definition.get("runtime_script", ""))
		== "res://scripts/app/earth_app.gd",
		"Earth world must use the dedicated EarthApp runtime."
	)
	_assert(catalog.list_worlds().size() == 5, "Catalog must contain exactly five initial worlds.")
	_assert(
		String(catalog.get_world("earth_moon").get("instance_id", "")) == "persistent",
		"Persistent planetary profiles must share one universe instance."
	)
	_assert(
		String(catalog.get_world("item_lab").get("instance_id", "")) == "scenario-item-lab",
		"Test scenarios must not share the persistent instance namespace."
	)
	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("World catalog tests: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("World catalog tests: FAIL (%d)" % failures.size())
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

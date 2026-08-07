extends SceneTree

const RuntimeFix7 = preload("res://scripts/world/testing/playground_view_relative_runtime_fix7.gd")
const PlaygroundScene = preload("res://scenes/testing/playground.tscn")

class FakeScreen:
	extends RefCounted
	var visible: bool = true
	var refresh_calls: int = 0
	func is_inventory_visible() -> bool:
		return visible
	func refresh() -> void:
		refresh_calls += 1

class FakeInventoryUI:
	extends RefCounted
	var active_screen
	var hotbar_refresh_calls: int = 0
	func _refresh_persistent_hotbar() -> void:
		hotbar_refresh_calls += 1

class FakeItemGameplay:
	extends RefCounted
	var inventory_ui

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_visible_inventory_reacts_immediately()
	_test_closed_inventory_keeps_hotbar_reactive()
	_test_playground_composition_uses_fix7()
	if failures.is_empty():
		print("Inventory network rev6 fix7: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Inventory network rev6 fix7: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)


func _test_visible_inventory_reacts_immediately() -> void:
	var runtime = RuntimeFix7.new()
	_assert(runtime != null, "fix7 runtime instantiates")
	if runtime == null:
		return
	var screen := FakeScreen.new()
	var ui := FakeInventoryUI.new()
	ui.active_screen = screen
	var gameplay := FakeItemGameplay.new()
	gameplay.inventory_ui = ui
	runtime.item_gameplay = gameplay

	runtime._refresh_m7_item_replica_presentation()
	_assert(screen.refresh_calls == 1, "visible InventoryScreen refreshes in the same authoritative apply reaction")
	_assert(ui.hotbar_refresh_calls == 1, "persistent hotbar refreshes with the same replica update")
	var report: Dictionary = runtime.get_m7_item_replica_presentation_report()
	_assert(String(report.get("schema", "")) == "planet_simulator.m7_item_replica_presentation.fix7.v1", "fix7 report schema is active")
	_assert(String(report.get("policy", "")) == "REFRESH_VISIBLE_INVENTORY_AFTER_APPLIED_ITEM_PROJECTION", "fix7 reports reactive presentation policy")
	_assert(int(report.get("inventory_screen_refreshes", 0)) == 1, "fix7 counts visible inventory refresh")
	_assert(int(report.get("persistent_hotbar_refreshes", 0)) == 1, "fix7 counts persistent hotbar refresh")
	runtime.free()


func _test_closed_inventory_keeps_hotbar_reactive() -> void:
	var runtime = RuntimeFix7.new()
	var screen := FakeScreen.new()
	screen.visible = false
	var ui := FakeInventoryUI.new()
	ui.active_screen = screen
	var gameplay := FakeItemGameplay.new()
	gameplay.inventory_ui = ui
	runtime.item_gameplay = gameplay

	runtime._refresh_m7_item_replica_presentation()
	_assert(screen.refresh_calls == 0, "closed InventoryScreen is not needlessly rebuilt")
	_assert(ui.hotbar_refresh_calls == 1, "persistent hotbar still reacts while inventory is closed")
	runtime.free()


func _test_playground_composition_uses_fix7() -> void:
	var instance = PlaygroundScene.instantiate()
	_assert(instance != null, "playground scene instantiates")
	if instance != null:
		_assert(instance.get_script() == RuntimeFix7, "playground scene selects fix7 reactive runtime")
		instance.free()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

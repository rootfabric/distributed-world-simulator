extends SceneTree

const CarryProjectionScript = preload("res://scripts/ui/inventory/interactions/inventory_slot_projection_carry_aware.gd")
const EnhancerFix7 = preload("res://scripts/ui/inventory/inventory_network_rev6_enhancer_fix7.gd")
const RuntimeFix7 = preload("res://scripts/world/testing/playground_view_relative_runtime_fix7.gd")
const PlaygroundScene = preload("res://scenes/testing/playground.tscn")

class FakeItem:
	extends RefCounted
	var definition_id: String
	func _init(value: String) -> void:
		definition_id = value
	func is_stack_compatible(other) -> bool:
		return other != null and String(other.get("definition_id")) == definition_id

class FakeController:
	extends RefCounted
	var items: Dictionary = {}
	func get_item(item_id: String):
		return items.get(item_id)

class FakeViewModel:
	extends RefCounted
	var model: Dictionary = {}
	func build_container(_container_id: String) -> Dictionary:
		return model.duplicate(true)

class FakeScreen:
	extends RefCounted
	var view_model

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_projection_override_survives_refresh()
	_test_fix7_builds_final_sorted_merge_preview()
	_test_fix7_report_contract()
	_test_playground_composition_uses_fix7()
	if failures.is_empty():
		print("Inventory network rev6 fix7: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Inventory network rev6 fix7: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)


func _test_projection_override_survives_refresh() -> void:
	var projection = CarryProjectionScript.new()
	projection.enabled = true
	projection.slot_columns = 4
	var physical := _model([
		_cell("item/z", "z", "Zulu", 1, 1, 0),
		_cell("item/a", "a", "Alpha", 1, 1, 1),
		_empty(2),
		_empty(3),
	])
	var preview := _model([
		_cell("item/a", "a", "Alpha", 1, 1, 0),
		_cell("item/z", "z", "Zulu", 1, 1, 1),
		_empty(2),
		_empty(3),
	])
	projection.set_container_presentation_override("player_inventory", preview)
	var first: Dictionary = projection.project_container(physical)
	var second: Dictionary = projection.project_container(physical)
	_assert(_item_at(first, 0) == "item/a", "sort presentation override wins on first render")
	_assert(_item_at(second, 0) == "item/a", "sort presentation override survives subsequent refreshes")
	_assert(projection.has_container_presentation_override("player_inventory"), "projection reports active container override")
	projection.clear_container_presentation_override("player_inventory")
	var restored: Dictionary = projection.project_container(physical)
	_assert(_item_at(restored, 0) == "item/z", "clearing preview restores physical replica order")


func _test_fix7_builds_final_sorted_merge_preview() -> void:
	var enhancer = EnhancerFix7.new()
	var projection = CarryProjectionScript.new()
	projection.enabled = true
	projection.slot_columns = 4
	var controller := FakeController.new()
	controller.items = {
		"item/z": FakeItem.new("z"),
		"item/rock1": FakeItem.new("rock"),
		"item/rock2": FakeItem.new("rock"),
	}
	var view_model := FakeViewModel.new()
	view_model.model = _model([
		_cell("item/z", "z", "Zulu", 1, 1, 0),
		_cell("item/rock1", "rock", "Alpha", 30, 50, 1),
		_cell("item/rock2", "rock", "Alpha", 25, 50, 2),
		_empty(3),
	])
	var screen := FakeScreen.new()
	screen.view_model = view_model
	enhancer.projection = projection
	enhancer.gameplay_controller = controller
	enhancer.screen = screen

	var preview: Dictionary = enhancer._build_optimistic_sort_preview("player_inventory")
	_assert(not preview.is_empty(), "fix7 builds optimistic sort preview")
	_assert(_item_at(preview, 0) == "item/rock1", "alphabetical result moves Alpha stack to first slot")
	_assert(_quantity_at(preview, 0) == 50, "first compatible stack is filled to max_stack")
	_assert(_item_at(preview, 1) == "item/rock2", "compatible remainder survives as second stack")
	_assert(_quantity_at(preview, 1) == 5, "compatible remainder quantity is exact")
	_assert(_item_at(preview, 2) == "item/z", "Zulu item follows merged Alpha stacks")
	_assert(bool(preview.get("presentation_sort_preview", false)), "preview model is explicitly presentation-only")
	enhancer.free()


func _test_fix7_report_contract() -> void:
	var enhancer = EnhancerFix7.new()
	var report: Dictionary = enhancer.get_report()
	_assert(String(report.get("schema", "")) == "planet_simulator.inventory_network_rev6_enhancer.fix7.v1", "fix7 enhancer report schema is active")
	_assert(String(report.get("sort_presentation", "")) == "OPTIMISTIC_FINAL_LAYOUT_UNTIL_REPLICA_MATCH", "fix7 reports optimistic final-layout policy")
	_assert(int(report.get("sort_preview_reconcile_timeout_ms", 0)) == 5000, "fix7 reconciliation timeout is bounded")
	enhancer.free()


func _test_playground_composition_uses_fix7() -> void:
	var instance = PlaygroundScene.instantiate()
	_assert(instance != null, "playground scene instantiates")
	if instance != null:
		_assert(instance.get_script() == RuntimeFix7, "playground scene selects fix7 optimistic-sort composition")
		instance.free()


func _model(cells: Array) -> Dictionary:
	return {
		"schema": "planet_simulator.container_view.v2",
		"container_id": "player_inventory",
		"display_name": "Inventory",
		"storage_mode": "SLOTS",
		"is_slot_container": true,
		"slot_count": 4,
		"visual_capacity": 4,
		"columns": 4,
		"cells": cells,
		"used_entries": 3,
		"rendered_cell_count": 4,
		"physical_cell_count": 4,
		"projected_total_count": 3,
		"matched_count": 3,
		"unfiltered_count": 3,
	}


func _cell(item_id: String, definition_id: String, display_name: String, quantity: int, max_stack: int, slot: int) -> Dictionary:
	return {
		"item_id": item_id,
		"definition_id": definition_id,
		"display_name": display_name,
		"quantity": quantity,
		"max_stack": max_stack,
		"owns_container": false,
		"source_container_id": "player_inventory",
		"source_slot_index": slot,
		"target_container_id": "player_inventory",
		"target_slot_index": slot,
		"projection_match": true,
		"slot_rule": {},
	}


func _empty(slot: int) -> Dictionary:
	return _cell("", "", "Пусто", 0, 1, slot)


func _item_at(model: Dictionary, slot: int) -> String:
	var cells: Array = Array(model.get("cells", []))
	if slot < 0 or slot >= cells.size() or not cells[slot] is Dictionary:
		return ""
	return String(Dictionary(cells[slot]).get("item_id", ""))


func _quantity_at(model: Dictionary, slot: int) -> int:
	var cells: Array = Array(model.get("cells", []))
	if slot < 0 or slot >= cells.size() or not cells[slot] is Dictionary:
		return 0
	return int(Dictionary(cells[slot]).get("quantity", 0))


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

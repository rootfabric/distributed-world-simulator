extends SceneTree

const CarryAwareProjection = preload(
	"res://scripts/ui/inventory/interactions/inventory_slot_projection_carry_aware.gd"
)
const InventoryRev6Enhancer = preload(
	"res://scripts/ui/inventory/inventory_network_rev6_enhancer_fix1.gd"
)

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_carry_suppression_survives_slot_projection_refresh()
	_test_rev6_enhancer_loads()
	if failures.is_empty():
		print("Inventory network rev6: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Inventory network rev6: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)


func _test_carry_suppression_survives_slot_projection_refresh() -> void:
	var projection = CarryAwareProjection.new()
	projection.enabled = true
	projection.slot_columns = 4
	var model := {
		"container_id": "player_inventory",
		"is_slot_container": true,
		"storage_mode": "SLOTS",
		"slot_count": 4,
		"visual_capacity": 4,
		"columns": 4,
		"cells": [
			_empty_cell("player_inventory", 0),
			_item_cell("player_inventory", 1, "item/test/rock"),
			_empty_cell("player_inventory", 2),
			_empty_cell("player_inventory", 3),
		],
	}
	var initial: Dictionary = projection.project_container(model)
	_assert(_cell_item(initial, 1) == "item/test/rock", "baseline slot renders carried candidate")

	projection.suppress_item("player_inventory", "item/test/rock")
	var carried: Dictionary = projection.project_container(model)
	_assert(_cell_item(carried, 1).is_empty(), "whole-stack carry renders origin slot empty")
	_assert(bool(_cell(carried, 1).get("carry_suppressed", false)), "origin slot records presentation-only carry suppression")
	_assert(projection.is_suppressed("player_inventory", "item/test/rock"), "suppression survives projection refresh")

	projection.reveal_item("player_inventory", "item/test/rock")
	var cancelled: Dictionary = projection.project_container(model)
	_assert(_cell_item(cancelled, 1) == "item/test/rock", "cancel/reveal restores original item without authority mutation")
	_assert(not projection.is_suppressed("player_inventory", "item/test/rock"), "reveal clears suppression state")


func _test_rev6_enhancer_loads() -> void:
	var enhancer = InventoryRev6Enhancer.new()
	get_root().add_child(enhancer)
	var report: Dictionary = enhancer.get_report()
	_assert(String(report.get("schema", "")) == "planet_simulator.inventory_network_rev6_enhancer.fix1.v1", "rev6 fix1 enhancer parses and exposes report schema")
	_assert(String(report.get("pickup_stack_mode", "")) == "CONSOLIDATE_COMPATIBLE_ON_PICKUP_COMPLETION", "pickup stack mode is authoritative-completion driven")
	enhancer.queue_free()


func _item_cell(container_id: String, slot_index: int, item_id: String) -> Dictionary:
	return {
		"item_id": item_id,
		"definition_id": "lunar_rock",
		"display_name": "Лунный камень",
		"quantity": 8,
		"revision": 1,
		"tags": ["rock", "resource"],
		"icon_color": [0.65, 0.65, 0.70],
		"source_container_id": container_id,
		"source_slot_index": slot_index,
		"target_container_id": container_id,
		"target_slot_index": slot_index,
		"selected": false,
		"inspected": false,
		"slot_rule": {},
		"projection_match": true,
	}


func _empty_cell(container_id: String, slot_index: int) -> Dictionary:
	return {
		"item_id": "",
		"definition_id": "",
		"display_name": "Пусто",
		"quantity": 0,
		"revision": -1,
		"tags": [],
		"icon_color": [],
		"source_container_id": container_id,
		"source_slot_index": slot_index,
		"target_container_id": container_id,
		"target_slot_index": slot_index,
		"selected": false,
		"inspected": false,
		"slot_rule": {},
		"projection_match": true,
	}


func _cell(model: Dictionary, slot_index: int) -> Dictionary:
	for cell_value in model.get("cells", []):
		if cell_value is Dictionary and int(cell_value.get("source_slot_index", -1)) == slot_index:
			return Dictionary(cell_value)
	return {}


func _cell_item(model: Dictionary, slot_index: int) -> String:
	return String(_cell(model, slot_index).get("item_id", ""))


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

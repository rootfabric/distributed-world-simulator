extends SceneTree

const CARRY_PROJECTION_PATH := "res://scripts/ui/inventory/interactions/inventory_slot_projection_carry_aware.gd"
const ENHANCER_PATH := "res://scripts/ui/inventory/inventory_network_rev6_enhancer_fix1.gd"
const COMPAT_ENHANCER_PATH := "res://scripts/ui/inventory/inventory_network_rev6_enhancer.gd"

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_carry_projection_whole_partial_and_hotbar()
	_test_rev6_enhancer_loads_and_instantiates()
	if failures.is_empty():
		print("Inventory network rev6: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Inventory network rev6: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)


func _test_carry_projection_whole_partial_and_hotbar() -> void:
	var projection_script = _load_instantiable_script(CARRY_PROJECTION_PATH, "carry-aware projection")
	if projection_script == null:
		return
	var projection = projection_script.new()
	_assert(projection != null, "carry-aware projection instantiates")
	if projection == null:
		return
	projection.set("enabled", true)
	projection.set("slot_columns", 4)
	var model := _slot_model("player_inventory", 8)
	var initial: Dictionary = projection.project_container(model)
	_assert(_cell_item(initial, 1) == "item/test/rock", "baseline slot renders carried candidate")
	_assert(int(_cell(initial, 1).get("quantity", 0)) == 8, "baseline renders authoritative quantity")

	projection.set_carried_quantity("player_inventory", "item/test/rock", 3)
	var partial: Dictionary = projection.project_container(model)
	_assert(_cell_item(partial, 1) == "item/test/rock", "partial carry leaves source stack visible")
	_assert(int(_cell(partial, 1).get("quantity", 0)) == 5, "partial carry renders only the remainder")
	_assert(bool(_cell(partial, 1).get("carry_remainder", false)), "partial source is marked as carry remainder")
	_assert(int(projection.carried_quantity("player_inventory", "item/test/rock")) == 3, "partial carried quantity survives projection refresh")

	projection.set_carried_quantity("player_inventory", "item/test/rock", 8)
	var whole: Dictionary = projection.project_container(model)
	_assert(_cell_item(whole, 1).is_empty(), "whole-stack carry renders origin slot empty")
	_assert(bool(_cell(whole, 1).get("carry_suppressed", false)), "whole-stack origin records presentation-only suppression")

	var hotbar_model := _slot_model("player_hotbar", 6)
	projection.set_carried_quantity("player_hotbar", "item/test/rock", 2)
	var hotbar_partial: Dictionary = projection.apply_carry_overlay(hotbar_model)
	_assert(_cell_item(hotbar_partial, 1) == "item/test/rock", "hotbar partial carry keeps the source slot")
	_assert(int(_cell(hotbar_partial, 1).get("quantity", 0)) == 4, "hotbar partial carry shows the correct remainder")
	projection.set_carried_quantity("player_hotbar", "item/test/rock", 6)
	var hotbar_whole: Dictionary = projection.apply_carry_overlay(hotbar_model)
	_assert(_cell_item(hotbar_whole, 1).is_empty(), "hotbar whole carry hides the original slot")

	projection.reveal_item("player_inventory", "item/test/rock")
	projection.reveal_item("player_hotbar", "item/test/rock")
	var cancelled: Dictionary = projection.project_container(model)
	_assert(_cell_item(cancelled, 1) == "item/test/rock", "cancel/reveal restores original item without authority mutation")
	_assert(int(_cell(cancelled, 1).get("quantity", 0)) == 8, "cancel/reveal restores original quantity")
	_assert(int(projection.carried_quantity("player_inventory", "item/test/rock")) == 0, "reveal clears carried quantity state")

	projection.suppress_item("player_inventory", "item/test/rock")
	var compatibility_hidden: Dictionary = projection.project_container(model)
	_assert(_cell_item(compatibility_hidden, 1).is_empty(), "legacy whole suppression API remains compatible")
	_assert(projection.is_suppressed("player_inventory", "item/test/rock"), "legacy suppression state remains queryable")
	projection.reveal_all()


func _test_rev6_enhancer_loads_and_instantiates() -> void:
	var enhancer_script = _load_instantiable_script(ENHANCER_PATH, "rev6 standalone enhancer")
	if enhancer_script != null:
		var enhancer = enhancer_script.new()
		_assert(enhancer != null, "rev6 standalone enhancer instantiates")
		if enhancer != null:
			get_root().add_child(enhancer)
			var report: Dictionary = enhancer.get_report()
			_assert(String(report.get("schema", "")) == "planet_simulator.inventory_network_rev6_enhancer.fix5.v1", "rev6 fix5 enhancer exposes expected schema")
			_assert(String(report.get("pickup_stack_mode", "")) == "CONSOLIDATE_COMPATIBLE_ON_PICKUP_COMPLETION", "pickup stack mode is authoritative-completion driven")
			_assert(String(report.get("sort_mode", "")) == "AUTHORITATIVE_SERIAL_TRANSFER", "sort is serialized against authoritative completions")
			_assert(Vector2(report.get("sort_button_size", Vector2.ZERO)) == Vector2(112.0, 30.0), "sort button has compact fixed geometry")
			_assert(Vector2(report.get("interaction_hint_position", Vector2.ZERO)) == Vector2(-300.0, -170.0), "interaction hint is raised above persistent hotbar")
			enhancer.queue_free()

	var compat_script = _load_instantiable_script(COMPAT_ENHANCER_PATH, "rev6 compatibility enhancer")
	if compat_script != null:
		var compat = compat_script.new()
		_assert(compat != null, "rev6 compatibility enhancer instantiates")
		if compat != null:
			get_root().add_child(compat)
			var compat_report: Dictionary = compat.get_report()
			_assert(String(compat_report.get("schema", "")) == "planet_simulator.inventory_network_rev6_enhancer.fix5.v1", "compatibility path resolves to standalone fix5 implementation")
			compat.queue_free()


func _load_instantiable_script(path: String, label: String):
	var resource = ResourceLoader.load(path, "Script", ResourceLoader.CACHE_MODE_IGNORE)
	_assert(resource != null, "%s loads" % label)
	if resource == null:
		return null
	_assert(resource is Script, "%s is a Script resource" % label)
	if not resource is Script:
		return null
	var script := resource as Script
	_assert(script.can_instantiate(), "%s can instantiate" % label)
	if not script.can_instantiate():
		return null
	return script


func _slot_model(container_id: String, quantity: int) -> Dictionary:
	return {
		"container_id": container_id,
		"is_slot_container": true,
		"storage_mode": "SLOTS",
		"slot_count": 4,
		"visual_capacity": 4,
		"columns": 4,
		"cells": [
			_empty_cell(container_id, 0),
			_item_cell(container_id, 1, "item/test/rock", quantity),
			_empty_cell(container_id, 2),
			_empty_cell(container_id, 3),
		],
	}


func _item_cell(container_id: String, slot_index: int, item_id: String, quantity: int) -> Dictionary:
	return {
		"item_id": item_id,
		"definition_id": "lunar_rock",
		"display_name": "Лунный камень",
		"quantity": quantity,
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

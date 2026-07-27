class_name InventoryViewModel
extends RefCounted

const SORT_CONTAINER_ORDER: String = "CONTAINER_ORDER"
const SORT_NAME: String = "NAME"
const SORT_TYPE: String = "TYPE"
const SORT_QUANTITY: String = "QUANTITY"

var gameplay_controller
var search_query: String = ""
var active_filters: PackedStringArray = PackedStringArray()
var sort_mode: String = SORT_CONTAINER_ORDER
var selected_item_id: String = ""
var pending_operation: Dictionary = {}


func setup(controller) -> void:
	gameplay_controller = controller


func set_search_query(value: String) -> void:
	search_query = value.strip_edges()


func set_active_filters(values: PackedStringArray) -> void:
	active_filters = values.duplicate()


func set_sort_mode(value: String) -> void:
	var normalized: String = value.to_upper()
	if normalized not in [SORT_CONTAINER_ORDER, SORT_NAME, SORT_TYPE, SORT_QUANTITY]:
		normalized = SORT_CONTAINER_ORDER
	sort_mode = normalized


func build_screen(external_container_id: String = "") -> Dictionary:
	if gameplay_controller == null:
		return {
			"schema": "planet_simulator.inventory_view.v1",
			"success": false,
			"error_code": "CONTROLLER_NOT_READY",
		}
	var player_model: Dictionary = build_container(gameplay_controller.player_inventory_id)
	var hotbar_model: Dictionary = build_container(
		gameplay_controller.player_hotbar_id,
		int(gameplay_controller.selected_hotbar_index)
	)
	var external_model: Dictionary = {}
	if not external_container_id.is_empty():
		external_model = build_container(external_container_id)
	return {
		"schema": "planet_simulator.inventory_view.v1",
		"success": true,
		"player": player_model,
		"hotbar": hotbar_model,
		"external": external_model,
		"external_container_id": external_container_id,
		"search_query": search_query,
		"active_filters": Array(active_filters),
		"sort_mode": sort_mode,
		"selected_item_id": selected_item_id,
		"pending_operation": pending_operation.duplicate(true),
	}


func build_container(container_id: String, selected_slot_index: int = -1) -> Dictionary:
	if gameplay_controller == null:
		return {}
	var container = gameplay_controller.get_container(container_id)
	if container == null:
		return {}
	var cells: Array[Dictionary] = []
	if container.is_slot_container():
		for slot_index in range(int(container.slot_count)):
			var item_id: String = String(container.get_item_at_slot(slot_index))
			cells.append(_build_cell(
				item_id,
				container_id,
				slot_index,
				slot_index == selected_slot_index,
				container.get_slot_rule(slot_index)
			))
	else:
		for item_id_value in container.item_ids:
			var cell: Dictionary = _build_cell(String(item_id_value), container_id, -1, false, {})
			if _matches_projection(cell):
				cells.append(cell)
		_sort_cells(cells)
	var used_entries: int = int(container.item_ids.size())
	var visual_capacity: int = _visual_capacity(container)
	var maximum_mass: float = float(container.maximum_mass_kg)
	var maximum_volume: float = float(container.maximum_volume_l)
	var current_mass: float = 0.0
	var current_volume: float = 0.0
	if gameplay_controller.domain.has("mass"):
		current_mass = float(gameplay_controller.domain.mass.container_mass_kg(container_id))
		current_volume = float(gameplay_controller.domain.mass.container_direct_volume_l(container_id))
	return {
		"schema": "planet_simulator.container_view.v1",
		"container_id": container_id,
		"display_name": gameplay_controller.get_container_display_name(container_id),
		"storage_mode": String(container.storage_mode),
		"is_slot_container": bool(container.is_slot_container()),
		"slot_count": int(container.slot_count),
		"used_entries": used_entries,
		"visual_capacity": visual_capacity,
		"columns": _columns_for_capacity(visual_capacity),
		"cells": cells,
		"rendered_cell_count": cells.size(),
		"current_mass_kg": current_mass,
		"maximum_mass_kg": maximum_mass,
		"current_volume_l": current_volume,
		"maximum_volume_l": maximum_volume,
		"allow_nested_containers": bool(container.allow_nested_containers),
		"revision": int(container.revision),
	}


func _build_cell(
	item_id: String,
	container_id: String,
	slot_index: int,
	selected: bool,
	slot_rule: Dictionary
) -> Dictionary:
	var item = gameplay_controller.get_item(item_id) if not item_id.is_empty() else null
	var definition = gameplay_controller.get_definition(item.definition_id) if item != null else null
	var display_name: String = "Пусто"
	var definition_id: String = ""
	var quantity: int = 0
	var tags: Array = []
	var icon_color: Array = []
	var revision: int = -1
	if item != null:
		definition_id = String(item.definition_id)
		quantity = int(item.quantity)
		revision = int(item.revision)
		if not String(item.display_name).is_empty():
			display_name = String(item.display_name)
		elif definition != null:
			display_name = String(definition.display_name)
	if definition != null:
		tags = Array(definition.tags).duplicate()
		icon_color = Array(definition.metadata.get("icon_color", [])).duplicate()
	return {
		"item_id": item_id,
		"definition_id": definition_id,
		"display_name": display_name,
		"quantity": quantity,
		"revision": revision,
		"tags": tags,
		"icon_color": icon_color,
		"source_container_id": container_id,
		"source_slot_index": slot_index,
		"target_container_id": container_id,
		"target_slot_index": slot_index,
		"selected": selected,
		"slot_rule": slot_rule.duplicate(true),
	}


func _matches_projection(cell: Dictionary) -> bool:
	if String(cell.get("item_id", "")).is_empty():
		return true
	if not search_query.is_empty():
		var query: String = search_query.to_lower()
		var haystack: String = "%s %s %s" % [
			String(cell.get("display_name", "")),
			String(cell.get("definition_id", "")),
			" ".join(PackedStringArray(cell.get("tags", []))),
		]
		if not haystack.to_lower().contains(query):
			return false
	if not active_filters.is_empty():
		var tags: PackedStringArray = PackedStringArray(cell.get("tags", []))
		var matched: bool = false
		for filter_value in active_filters:
			if tags.has(String(filter_value)):
				matched = true
				break
		if not matched:
			return false
	return true


func _sort_cells(cells: Array[Dictionary]) -> void:
	match sort_mode:
		SORT_NAME:
			cells.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return String(a.get("display_name", "")).naturalnocasecmp_to(String(b.get("display_name", ""))) < 0
			)
		SORT_TYPE:
			cells.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return String(a.get("definition_id", "")).naturalnocasecmp_to(String(b.get("definition_id", ""))) < 0
			)
		SORT_QUANTITY:
			cells.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return int(a.get("quantity", 0)) > int(b.get("quantity", 0))
			)
		_:
			pass


func _visual_capacity(container) -> int:
	if container.is_slot_container():
		return maxi(1, int(container.slot_count))
	if int(container.slot_count) > 0:
		return maxi(int(container.slot_count), int(container.item_ids.size()))
	return maxi(1, int(container.item_ids.size()))


func _columns_for_capacity(capacity: int) -> int:
	if capacity <= 4:
		return maxi(1, capacity)
	if capacity <= 8:
		return 4
	if capacity <= 18:
		return 6
	return 8

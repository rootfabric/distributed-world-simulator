class_name InventorySlotProjection
extends RefCounted

const SCHEMA: String = "planet_simulator.inventory_slot_projection.v1"

var enabled: bool = false
var slot_columns: int = 10
var layouts: Dictionary = {}


func configure(profile: InventoryInteractionProfile) -> void:
	enabled = profile != null and profile.container_layout == "FIXED_SLOTS"
	slot_columns = maxi(1, profile.slot_columns if profile != null else 10)


func import_layouts(data: Dictionary) -> void:
	layouts.clear()
	for container_id_value in data:
		var container_id := String(container_id_value).strip_edges()
		if container_id.is_empty():
			continue
		var raw_layout = data[container_id_value]
		if not raw_layout is Array:
			continue
		var layout: Array[String] = []
		for item_id_value in Array(raw_layout).slice(0, 512):
			layout.append(String(item_id_value))
		layouts[container_id] = layout


func export_layouts() -> Dictionary:
	var result: Dictionary = {}
	for container_id_value in layouts:
		var container_id := String(container_id_value)
		var layout: Array = Array(layouts[container_id_value])
		result[container_id] = layout.duplicate()
	return result


func project_container(model: Dictionary) -> Dictionary:
	if not enabled or model.is_empty():
		return model.duplicate(true)
	if bool(model.get("is_slot_container", false)):
		var slot_model := model.duplicate(true)
		var capacity := maxi(1, int(slot_model.get("visual_capacity", slot_model.get("slot_count", 1))))
		var container_id := String(slot_model.get("container_id", ""))
		var layout: Array[String] = []
		layout.resize(capacity)
		for slot_index in range(capacity):
			layout[slot_index] = ""
		for cell_value in Array(slot_model.get("cells", [])):
			var cell := Dictionary(cell_value)
			var slot_index := int(cell.get("source_slot_index", cell.get("target_slot_index", -1)))
			if slot_index >= 0 and slot_index < capacity:
				layout[slot_index] = String(cell.get("item_id", ""))
		if not container_id.is_empty():
			layouts[container_id] = layout
		slot_model["columns"] = mini(slot_columns, capacity)
		slot_model["is_profile_slot_layout"] = true
		slot_model["domain_storage_mode"] = "SLOTS"
		return slot_model
	var projected := model.duplicate(true)
	var container_id := String(projected.get("container_id", ""))
	if container_id.is_empty():
		return projected
	var source_cells: Array = Array(projected.get("cells", []))
	var capacity := maxi(int(projected.get("visual_capacity", 0)), source_cells.size())
	capacity = maxi(1, capacity)
	var layout := _reconcile_layout(container_id, capacity, source_cells)
	var cells_by_id: Dictionary = {}
	for cell_value in source_cells:
		var cell := Dictionary(cell_value)
		var item_id := String(cell.get("item_id", ""))
		if not item_id.is_empty():
			cells_by_id[item_id] = cell
	var projected_cells: Array[Dictionary] = []
	for slot_index in range(capacity):
		var item_id := String(layout[slot_index])
		var cell := _empty_cell(container_id, slot_index)
		if not item_id.is_empty() and cells_by_id.has(item_id):
			cell = Dictionary(cells_by_id[item_id]).duplicate(true)
			cell["source_container_id"] = container_id
			cell["source_slot_index"] = slot_index
			cell["target_container_id"] = container_id
			cell["target_slot_index"] = slot_index
		cell["virtual_slot"] = true
		cell["domain_storage_mode"] = String(model.get("storage_mode", "BULK"))
		projected_cells.append(cell)
	projected["domain_storage_mode"] = String(model.get("storage_mode", "BULK"))
	projected["storage_mode"] = "SLOTS"
	projected["is_slot_container"] = true
	projected["is_profile_slot_projection"] = true
	projected["slot_count"] = capacity
	projected["visual_capacity"] = capacity
	projected["columns"] = mini(slot_columns, capacity)
	projected["cells"] = projected_cells
	projected["rendered_cell_count"] = projected_cells.size()
	projected["physical_cell_count"] = projected_cells.size()
	projected["virtualized"] = false
	projected["page_index"] = 0
	projected["page_count"] = 1
	return projected


func place_item(container_id: String, item_id: String, slot_index: int) -> void:
	if not enabled or container_id.is_empty() or item_id.is_empty() or slot_index < 0:
		return
	var layout := _layout(container_id)
	if layout.is_empty():
		return
	_remove_item_from_layout(layout, item_id)
	if slot_index >= layout.size():
		layout.resize(slot_index + 1)
		for index in range(layout.size()):
			if layout[index] == null:
				layout[index] = ""
	var displaced := String(layout[slot_index])
	layout[slot_index] = item_id
	if not displaced.is_empty() and displaced != item_id:
		var free_slot := _first_free_slot(layout)
		if free_slot >= 0:
			layout[free_slot] = displaced
	layouts[container_id] = layout


func remove_item(container_id: String, item_id: String) -> int:
	if container_id.is_empty() or item_id.is_empty():
		return -1
	var layout := _layout(container_id)
	for index in range(layout.size()):
		if String(layout[index]) == item_id:
			layout[index] = ""
			layouts[container_id] = layout
			return index
	return -1


func swap_item_at_slot(container_id: String, slot_index: int, incoming_item_id: String) -> String:
	if not enabled or container_id.is_empty() or slot_index < 0:
		return ""
	var layout := _layout(container_id)
	if slot_index >= layout.size():
		return ""
	var displaced := String(layout[slot_index])
	_remove_item_from_layout(layout, incoming_item_id)
	layout[slot_index] = incoming_item_id
	layouts[container_id] = layout
	return displaced


func item_at_slot(container_id: String, slot_index: int) -> String:
	var layout := _layout(container_id)
	if slot_index < 0 or slot_index >= layout.size():
		return ""
	return String(layout[slot_index])


func slot_for_item(container_id: String, item_id: String) -> int:
	var layout := _layout(container_id)
	for index in range(layout.size()):
		if String(layout[index]) == item_id:
			return index
	return -1


func first_free_slot(container_id: String) -> int:
	return _first_free_slot(_layout(container_id))


func clear_container(container_id: String) -> void:
	layouts.erase(container_id)


func debug_snapshot() -> Dictionary:
	var serialized: Dictionary = {}
	for container_id in layouts:
		serialized[String(container_id)] = Array(layouts[container_id]).duplicate()
	return {
		"schema": SCHEMA,
		"enabled": enabled,
		"slot_columns": slot_columns,
		"layouts": serialized,
	}


func _reconcile_layout(container_id: String, capacity: int, source_cells: Array) -> Array:
	var current_ids := PackedStringArray()
	for cell_value in source_cells:
		var item_id := String(Dictionary(cell_value).get("item_id", ""))
		if not item_id.is_empty() and not current_ids.has(item_id):
			current_ids.append(item_id)
	var layout := _layout(container_id)
	layout.resize(capacity)
	for index in range(capacity):
		if layout[index] == null:
			layout[index] = ""
		var item_id := String(layout[index])
		if not item_id.is_empty() and not current_ids.has(item_id):
			layout[index] = ""
	for item_id in current_ids:
		if _array_has_string(layout, item_id):
			continue
		var free_slot := _first_free_slot(layout)
		if free_slot < 0:
			break
		layout[free_slot] = item_id
	layouts[container_id] = layout
	return layout


func _layout(container_id: String) -> Array:
	if not layouts.has(container_id):
		return []
	return Array(layouts[container_id]).duplicate()


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


func _remove_item_from_layout(layout: Array, item_id: String) -> void:
	for index in range(layout.size()):
		if String(layout[index]) == item_id:
			layout[index] = ""


func _first_free_slot(layout: Array) -> int:
	for index in range(layout.size()):
		if String(layout[index]).is_empty():
			return index
	return -1


func _array_has_string(values: Array, expected: String) -> bool:
	for value in values:
		if String(value) == expected:
			return true
	return false

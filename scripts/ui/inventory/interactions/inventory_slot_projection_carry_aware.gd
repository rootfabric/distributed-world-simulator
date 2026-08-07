class_name InventorySlotProjectionCarryAware
extends "res://scripts/ui/inventory/interactions/inventory_slot_projection.gd"

# Presentation-only carry overlay for the 7 Days cursor profile. Network
# authority intentionally keeps the source stack in its real container until
# placement commands are confirmed, while the UI must look as if the carried
# quantity has already left the source slot. This layer never mutates Item Graph.

const SCHEMA_CARRY_AWARE: String = "planet_simulator.inventory_slot_projection.carry_aware.v2"

var suppressed_items: Dictionary = {}
var carried_quantities: Dictionary = {}


func suppress_item(container_id: String, item_id: String) -> void:
	var normalized_container := container_id.strip_edges()
	var normalized_item := item_id.strip_edges()
	if normalized_container.is_empty() or normalized_item.is_empty():
		return
	var values: Dictionary = Dictionary(suppressed_items.get(normalized_container, {})).duplicate(true)
	values[normalized_item] = true
	suppressed_items[normalized_container] = values
	_clear_carried_quantity(normalized_container, normalized_item)


func set_carried_quantity(container_id: String, item_id: String, quantity: int) -> void:
	var normalized_container := container_id.strip_edges()
	var normalized_item := item_id.strip_edges()
	if normalized_container.is_empty() or normalized_item.is_empty():
		return
	if quantity <= 0:
		_clear_carried_quantity(normalized_container, normalized_item)
		return
	var values: Dictionary = Dictionary(carried_quantities.get(normalized_container, {})).duplicate(true)
	values[normalized_item] = quantity
	carried_quantities[normalized_container] = values
	if suppressed_items.has(normalized_container):
		var hidden: Dictionary = Dictionary(suppressed_items[normalized_container]).duplicate(true)
		hidden.erase(normalized_item)
		if hidden.is_empty():
			suppressed_items.erase(normalized_container)
		else:
			suppressed_items[normalized_container] = hidden


func carried_quantity(container_id: String, item_id: String) -> int:
	if not carried_quantities.has(container_id):
		return 0
	return maxi(0, int(Dictionary(carried_quantities[container_id]).get(item_id, 0)))


func reveal_item(container_id: String, item_id: String) -> void:
	var normalized_container := container_id.strip_edges()
	var normalized_item := item_id.strip_edges()
	if normalized_container.is_empty() or normalized_item.is_empty():
		return
	if suppressed_items.has(normalized_container):
		var values: Dictionary = Dictionary(suppressed_items[normalized_container]).duplicate(true)
		values.erase(normalized_item)
		if values.is_empty():
			suppressed_items.erase(normalized_container)
		else:
			suppressed_items[normalized_container] = values
	_clear_carried_quantity(normalized_container, normalized_item)


func reveal_all() -> void:
	suppressed_items.clear()
	carried_quantities.clear()


func is_suppressed(container_id: String, item_id: String) -> bool:
	if not suppressed_items.has(container_id):
		return false
	return bool(Dictionary(suppressed_items[container_id]).get(item_id, false))


func apply_carry_overlay(model: Dictionary) -> Dictionary:
	if model.is_empty():
		return model.duplicate(true)
	var container_id := String(model.get("container_id", ""))
	if container_id.is_empty():
		return model.duplicate(true)
	var hidden: Dictionary = Dictionary(suppressed_items.get(container_id, {}))
	var carried: Dictionary = Dictionary(carried_quantities.get(container_id, {}))
	if hidden.is_empty() and carried.is_empty():
		return model.duplicate(true)

	var filtered := model.duplicate(true)
	var filtered_cells: Array = []
	for cell_value in Array(model.get("cells", [])):
		if not cell_value is Dictionary:
			filtered_cells.append(cell_value)
			continue
		var cell: Dictionary = Dictionary(cell_value).duplicate(true)
		var item_id := String(cell.get("item_id", ""))
		if item_id.is_empty():
			filtered_cells.append(cell)
			continue

		var hide_whole: bool = bool(hidden.get(item_id, false))
		var carried_quantity_value: int = maxi(0, int(carried.get(item_id, 0)))
		if not hide_whole and carried_quantity_value <= 0:
			filtered_cells.append(cell)
			continue

		var slot_index := int(cell.get("source_slot_index", cell.get("target_slot_index", -1)))
		var source_quantity := maxi(0, int(cell.get("quantity", 0)))
		var remaining_quantity := 0 if hide_whole else maxi(0, source_quantity - carried_quantity_value)
		if remaining_quantity > 0:
			cell["quantity"] = remaining_quantity
			cell["carry_remainder"] = true
			cell["carried_quantity"] = carried_quantity_value
			filtered_cells.append(cell)
			continue

		# Keep the physical slot in SLOTS models while removing the carried stack
		# visually. BULK projections may omit the placeholder and let the base
		# projection reconcile the remaining aggregates.
		if slot_index >= 0:
			var empty := _empty_cell(container_id, slot_index)
			empty["carry_suppressed"] = true
			empty["carried_quantity"] = carried_quantity_value if not hide_whole else source_quantity
			empty["domain_storage_mode"] = String(cell.get("domain_storage_mode", model.get("storage_mode", "SLOTS")))
			filtered_cells.append(empty)
	filtered["cells"] = filtered_cells
	return filtered


func project_container(model: Dictionary) -> Dictionary:
	return super.project_container(apply_carry_overlay(model))


func debug_snapshot() -> Dictionary:
	var result: Dictionary = super.debug_snapshot()
	var serialized_hidden: Dictionary = {}
	for container_id_value in suppressed_items.keys():
		var container_id := String(container_id_value)
		var ids := Array(Dictionary(suppressed_items[container_id]).keys())
		ids.sort()
		serialized_hidden[container_id] = ids
	var serialized_carried: Dictionary = {}
	for container_id_value in carried_quantities.keys():
		var container_id := String(container_id_value)
		serialized_carried[container_id] = Dictionary(carried_quantities[container_id]).duplicate(true)
	result["carry_aware_schema"] = SCHEMA_CARRY_AWARE
	result["suppressed_items"] = serialized_hidden
	result["carried_quantities"] = serialized_carried
	return result


func _clear_carried_quantity(container_id: String, item_id: String) -> void:
	if not carried_quantities.has(container_id):
		return
	var values: Dictionary = Dictionary(carried_quantities[container_id]).duplicate(true)
	values.erase(item_id)
	if values.is_empty():
		carried_quantities.erase(container_id)
	else:
		carried_quantities[container_id] = values

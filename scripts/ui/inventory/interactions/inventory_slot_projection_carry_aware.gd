class_name InventorySlotProjectionCarryAware
extends "res://scripts/ui/inventory/interactions/inventory_slot_projection.gd"

# Presentation-only suppression used by the 7 Days cursor carry in a network
# replica. Authority intentionally keeps the source item in its real slot until
# the player chooses a destination, but the UI must render that slot as empty
# while the whole stack is on the cursor. This overlay never mutates Item Graph.

const SCHEMA_CARRY_AWARE: String = "planet_simulator.inventory_slot_projection.carry_aware.v1"

var suppressed_items: Dictionary = {}


func suppress_item(container_id: String, item_id: String) -> void:
	var normalized_container := container_id.strip_edges()
	var normalized_item := item_id.strip_edges()
	if normalized_container.is_empty() or normalized_item.is_empty():
		return
	var values: Dictionary = Dictionary(suppressed_items.get(normalized_container, {})).duplicate(true)
	values[normalized_item] = true
	suppressed_items[normalized_container] = values


func reveal_item(container_id: String, item_id: String) -> void:
	var normalized_container := container_id.strip_edges()
	var normalized_item := item_id.strip_edges()
	if normalized_container.is_empty() or normalized_item.is_empty():
		return
	if not suppressed_items.has(normalized_container):
		return
	var values: Dictionary = Dictionary(suppressed_items[normalized_container]).duplicate(true)
	values.erase(normalized_item)
	if values.is_empty():
		suppressed_items.erase(normalized_container)
	else:
		suppressed_items[normalized_container] = values


func reveal_all() -> void:
	suppressed_items.clear()


func is_suppressed(container_id: String, item_id: String) -> bool:
	if not suppressed_items.has(container_id):
		return false
	return bool(Dictionary(suppressed_items[container_id]).get(item_id, false))


func project_container(model: Dictionary) -> Dictionary:
	if model.is_empty():
		return super.project_container(model)
	var container_id := String(model.get("container_id", ""))
	if container_id.is_empty() or not suppressed_items.has(container_id):
		return super.project_container(model)
	var hidden: Dictionary = Dictionary(suppressed_items[container_id])
	if hidden.is_empty():
		return super.project_container(model)

	var filtered := model.duplicate(true)
	var filtered_cells: Array = []
	for cell_value in Array(model.get("cells", [])):
		if not cell_value is Dictionary:
			filtered_cells.append(cell_value)
			continue
		var cell: Dictionary = Dictionary(cell_value).duplicate(true)
		var item_id := String(cell.get("item_id", ""))
		if item_id.is_empty() or not bool(hidden.get(item_id, false)):
			filtered_cells.append(cell)
			continue
		# Keep the physical slot in the model, but make it visually empty. This is
		# important for real SLOTS containers: deleting the cell would collapse the
		# rendered grid instead of showing an empty origin slot.
		var slot_index := int(cell.get("source_slot_index", cell.get("target_slot_index", -1)))
		if slot_index >= 0:
			var empty := _empty_cell(container_id, slot_index)
			empty["carry_suppressed"] = true
			empty["domain_storage_mode"] = String(cell.get("domain_storage_mode", model.get("storage_mode", "SLOTS")))
			filtered_cells.append(empty)
		# BULK projections do not need a placeholder; the base projection will
		# reconcile the remaining aggregates into the fixed visual grid.
	filtered["cells"] = filtered_cells
	return super.project_container(filtered)


func debug_snapshot() -> Dictionary:
	var result: Dictionary = super.debug_snapshot()
	var serialized: Dictionary = {}
	for container_id_value in suppressed_items.keys():
		var container_id := String(container_id_value)
		var ids := Array(Dictionary(suppressed_items[container_id]).keys())
		ids.sort()
		serialized[container_id] = ids
	result["carry_aware_schema"] = SCHEMA_CARRY_AWARE
	result["suppressed_items"] = serialized
	return result

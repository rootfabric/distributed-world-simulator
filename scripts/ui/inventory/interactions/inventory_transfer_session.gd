class_name InventoryTransferSession
extends RefCounted

const SCHEMA: String = "planet_simulator.inventory_transfer_session.v2"

enum Stage {
	IDLE,
	CARRYING,
}

var stage: Stage = Stage.IDLE
var item_id: String = ""
var source_container_id: String = ""
var source_slot_index: int = -1
var requested_quantity: int = 0
var remaining_quantity: int = 0
var display_name: String = ""
var definition_id: String = ""
var icon_texture: Texture2D
var start_revision: int = -1
var domain_backed: bool = false
var cursor_container_id: String = ""
var origin_item_id: String = ""
var swap_history: Array[Dictionary] = []


func begin(cell_data: Dictionary, quantity: int, texture: Texture2D = null, revision: int = -1) -> Dictionary:
	var new_item_id := String(cell_data.get("item_id", ""))
	var available := int(cell_data.get("quantity", 0))
	if new_item_id.is_empty() or available <= 0:
		return {"success": false, "error_code": "CARRY_SOURCE_EMPTY"}
	var selected_quantity := clampi(quantity, 1, available)
	stage = Stage.CARRYING
	item_id = new_item_id
	origin_item_id = new_item_id
	source_container_id = String(cell_data.get("source_container_id", ""))
	source_slot_index = int(cell_data.get("source_slot_index", -1))
	requested_quantity = selected_quantity
	remaining_quantity = selected_quantity
	display_name = String(cell_data.get("display_name", "Предмет"))
	definition_id = String(cell_data.get("definition_id", ""))
	icon_texture = texture
	start_revision = revision
	domain_backed = false
	cursor_container_id = ""
	swap_history.clear()
	return {"success": true, "session": snapshot()}


func begin_domain_backed(
	origin_data: Dictionary,
	carried_item_id: String,
	carried_quantity: int,
	texture: Texture2D,
	revision: int,
	cursor_id: String
) -> Dictionary:
	if carried_item_id.is_empty() or carried_quantity <= 0 or cursor_id.is_empty():
		return {"success": false, "error_code": "DOMAIN_CARRY_INVALID"}
	stage = Stage.CARRYING
	item_id = carried_item_id
	origin_item_id = String(origin_data.get("item_id", carried_item_id))
	source_container_id = String(origin_data.get("source_container_id", ""))
	source_slot_index = int(origin_data.get("source_slot_index", -1))
	requested_quantity = carried_quantity
	remaining_quantity = carried_quantity
	display_name = String(origin_data.get("display_name", "Предмет"))
	definition_id = String(origin_data.get("definition_id", ""))
	icon_texture = texture
	start_revision = revision
	domain_backed = true
	cursor_container_id = cursor_id
	swap_history.clear()
	return {"success": true, "session": snapshot()}


func record_domain_swap(
	target_container_id: String,
	target_slot_index: int,
	placed_item_id: String,
	displaced_item_data: Dictionary,
	texture: Texture2D,
	revision: int
) -> void:
	var displaced_item_id := String(displaced_item_data.get("item_id", ""))
	if displaced_item_id.is_empty():
		return
	swap_history.append({
		"target_container_id": target_container_id,
		"target_slot_index": target_slot_index,
		"placed_item_id": placed_item_id,
		"displaced_item_id": displaced_item_id,
	})
	item_id = displaced_item_id
	requested_quantity = int(displaced_item_data.get("quantity", 0))
	remaining_quantity = requested_quantity
	display_name = String(displaced_item_data.get("display_name", "Предмет"))
	definition_id = String(displaced_item_data.get("definition_id", ""))
	icon_texture = texture
	start_revision = revision
	stage = Stage.CARRYING if not item_id.is_empty() and remaining_quantity > 0 else Stage.IDLE


func set_domain_carried_item(item_data: Dictionary, texture: Texture2D, revision: int) -> void:
	item_id = String(item_data.get("item_id", ""))
	requested_quantity = int(item_data.get("quantity", 0))
	remaining_quantity = requested_quantity
	display_name = String(item_data.get("display_name", "Предмет"))
	definition_id = String(item_data.get("definition_id", ""))
	icon_texture = texture
	start_revision = revision
	stage = Stage.CARRYING if not item_id.is_empty() and remaining_quantity > 0 else Stage.IDLE


func sync_domain_item(item) -> void:
	if not domain_backed:
		return
	if item == null:
		clear()
		return
	item_id = String(item.instance_id)
	remaining_quantity = int(item.quantity)
	requested_quantity = remaining_quantity
	start_revision = int(item.revision)
	if remaining_quantity <= 0:
		clear()


func is_active() -> bool:
	return stage == Stage.CARRYING and not item_id.is_empty() and remaining_quantity > 0


func consume(quantity: int) -> int:
	if not is_active():
		return 0
	var consumed := clampi(quantity, 0, remaining_quantity)
	remaining_quantity -= consumed
	if remaining_quantity <= 0:
		clear()
	return consumed


func clear() -> void:
	stage = Stage.IDLE
	item_id = ""
	origin_item_id = ""
	source_container_id = ""
	source_slot_index = -1
	requested_quantity = 0
	remaining_quantity = 0
	display_name = ""
	definition_id = ""
	icon_texture = null
	start_revision = -1
	domain_backed = false
	cursor_container_id = ""
	swap_history.clear()


func snapshot() -> Dictionary:
	return {
		"schema": SCHEMA,
		"active": is_active(),
		"stage": Stage.keys()[stage],
		"item_id": item_id,
		"origin_item_id": origin_item_id,
		"source_container_id": source_container_id,
		"source_slot_index": source_slot_index,
		"requested_quantity": requested_quantity,
		"remaining_quantity": remaining_quantity,
		"display_name": display_name,
		"definition_id": definition_id,
		"start_revision": start_revision,
		"domain_backed": domain_backed,
		"cursor_container_id": cursor_container_id,
		"swap_history": swap_history.duplicate(true),
	}

class_name InventoryTransferSession
extends RefCounted

const SCHEMA: String = "planet_simulator.inventory_transfer_session.v1"

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


func begin(cell_data: Dictionary, quantity: int, texture: Texture2D = null, revision: int = -1) -> Dictionary:
	var new_item_id := String(cell_data.get("item_id", ""))
	var available := int(cell_data.get("quantity", 0))
	if new_item_id.is_empty() or available <= 0:
		return {"success": false, "error_code": "CARRY_SOURCE_EMPTY"}
	var selected_quantity := clampi(quantity, 1, available)
	stage = Stage.CARRYING
	item_id = new_item_id
	source_container_id = String(cell_data.get("source_container_id", ""))
	source_slot_index = int(cell_data.get("source_slot_index", -1))
	requested_quantity = selected_quantity
	remaining_quantity = selected_quantity
	display_name = String(cell_data.get("display_name", "Предмет"))
	definition_id = String(cell_data.get("definition_id", ""))
	icon_texture = texture
	start_revision = revision
	return {"success": true, "session": snapshot()}


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
	source_container_id = ""
	source_slot_index = -1
	requested_quantity = 0
	remaining_quantity = 0
	display_name = ""
	definition_id = ""
	icon_texture = null
	start_revision = -1


func snapshot() -> Dictionary:
	return {
		"schema": SCHEMA,
		"active": is_active(),
		"stage": Stage.keys()[stage],
		"item_id": item_id,
		"source_container_id": source_container_id,
		"source_slot_index": source_slot_index,
		"requested_quantity": requested_quantity,
		"remaining_quantity": remaining_quantity,
		"display_name": display_name,
		"definition_id": definition_id,
		"start_revision": start_revision,
	}

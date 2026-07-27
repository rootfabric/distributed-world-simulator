class_name InventoryCommandFacade
extends RefCounted

signal operation_started(operation: Dictionary)
signal operation_finished(result: Dictionary)

var gameplay_controller


func setup(controller) -> void:
	gameplay_controller = controller


func preview_transfer(
	item_id: String,
	quantity: int,
	target_container_id: String,
	target_slot_index: int = -1,
	target_item_id: String = ""
) -> Dictionary:
	if gameplay_controller == null:
		return {"success": false, "error_code": "CONTROLLER_NOT_READY"}
	return gameplay_controller.preview_item_quantity_to_container(
		item_id,
		quantity,
		target_container_id,
		target_slot_index,
		target_item_id
	)


func transfer_stack(
	item_id: String,
	target_container_id: String,
	target_slot_index: int = -1,
	target_item_id: String = ""
) -> Dictionary:
	return transfer_quantity(item_id, -1, target_container_id, target_slot_index, target_item_id)


func transfer_quantity(
	item_id: String,
	quantity: int,
	target_container_id: String,
	target_slot_index: int = -1,
	target_item_id: String = ""
) -> Dictionary:
	if gameplay_controller == null:
		return {"success": false, "error_code": "CONTROLLER_NOT_READY"}
	operation_started.emit({
		"kind": "TRANSFER",
		"item_id": item_id,
		"quantity": quantity,
		"target_container_id": target_container_id,
		"target_slot_index": target_slot_index,
		"target_item_id": target_item_id,
	})
	var result: Dictionary = gameplay_controller.move_item_quantity_to_container(
		item_id,
		quantity,
		target_container_id,
		target_slot_index,
		target_item_id
	)
	operation_finished.emit(result.duplicate(true))
	return result


func quick_transfer(item_id: String, source_container_id: String, external_container_id: String) -> Dictionary:
	if gameplay_controller == null:
		return {"success": false, "error_code": "CONTROLLER_NOT_READY"}
	if external_container_id.is_empty():
		return {
			"success": false,
			"error_code": "NO_EXTERNAL_CONTAINER",
			"message": "Быстрый перенос доступен только при открытом внешнем контейнере",
		}
	var target_container_id: String = String(gameplay_controller.player_inventory_id)
	if source_container_id == gameplay_controller.player_inventory_id:
		target_container_id = external_container_id
	elif source_container_id != external_container_id:
		return {
			"success": false,
			"error_code": "QUICK_TRANSFER_SOURCE_UNSUPPORTED",
			"message": "Источник не относится к активной паре контейнеров",
		}
	return transfer_stack(item_id, target_container_id)


func select_hotbar(slot_index: int) -> Dictionary:
	if gameplay_controller == null:
		return {"success": false, "error_code": "CONTROLLER_NOT_READY"}
	return gameplay_controller.select_hotbar(slot_index)


func drop_item(item_id: String) -> Dictionary:
	if gameplay_controller == null:
		return {"success": false, "error_code": "CONTROLLER_NOT_READY"}
	return gameplay_controller.drop_item(item_id)


func result_message(result: Dictionary) -> String:
	if gameplay_controller == null:
		return String(result.get("message", result.get("error_code", "Ошибка")))
	return gameplay_controller.result_message(result)

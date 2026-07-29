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


func preview_quick_transfer(
	item_id: String,
	source_container_id: String,
	external_container_id: String,
	quantity: int = -1
) -> Dictionary:
	if gameplay_controller == null:
		return {"success": false, "error_code": "CONTROLLER_NOT_READY"}
	if external_container_id.is_empty():
		return {
			"success": false,
			"error_code": "NO_EXTERNAL_CONTAINER",
			"message": "Быстрый перенос доступен только при открытом внешнем контейнере",
		}
	var target_container_id := ""
	if source_container_id == gameplay_controller.player_inventory_id:
		target_container_id = external_container_id
	elif source_container_id == external_container_id:
		target_container_id = gameplay_controller.player_inventory_id
	else:
		return {
			"success": false,
			"error_code": "QUICK_TRANSFER_SOURCE_UNSUPPORTED",
			"message": "Источник не относится к активной паре контейнеров",
		}
	var item = gameplay_controller.get_item(item_id)
	if item == null:
		return {"success": false, "error_code": "ITEM_NOT_FOUND", "target_container_id": target_container_id}
	var requested_quantity: int = int(item.quantity) if quantity < 0 else clampi(quantity, 1, int(item.quantity))
	var target = gameplay_controller.get_container(target_container_id)
	if target == null:
		return {"success": false, "error_code": "CONTAINER_NOT_FOUND", "target_container_id": target_container_id}
	if not target.is_slot_container():
		var bulk_preview: Dictionary = preview_transfer(item_id, requested_quantity, target_container_id)
		bulk_preview["target_container_id"] = target_container_id
		bulk_preview["target_slot_index"] = -1
		bulk_preview["target_item_id"] = ""
		bulk_preview["requested_quantity"] = requested_quantity
		bulk_preview["whole_stack_fits"] = (
			bool(bulk_preview.get("success", false))
			and int(bulk_preview.get("maximum_quantity", 0)) >= requested_quantity
		)
		return bulk_preview

	# SLOTS quick-transfer must preserve the semantic "move the requested amount".
	# Prefer a slot that can accept the complete request. A partial compatible stack
	# is kept only as a split-dialog hint and is never executed by quick_transfer().
	var last_error: Dictionary = {"success": false, "error_code": "NO_COMPATIBLE_SLOT"}
	var best_partial: Dictionary = {}
	var best_partial_capacity: int = 0
	var total_compatible_headroom: int = 0
	for slot_index in range(int(target.slot_count)):
		var target_item_id := String(target.get_item_at_slot(slot_index))
		var preview: Dictionary = preview_transfer(
			item_id,
			requested_quantity,
			target_container_id,
			slot_index,
			target_item_id
		)
		if bool(preview.get("success", false)):
			var capacity := maxi(0, int(preview.get("maximum_quantity", requested_quantity)))
			preview["target_container_id"] = target_container_id
			preview["target_slot_index"] = slot_index
			preview["target_item_id"] = target_item_id
			preview["requested_quantity"] = requested_quantity
			preview["whole_stack_fits"] = capacity >= requested_quantity
			if capacity >= requested_quantity:
				return preview
			total_compatible_headroom += capacity
			if capacity > best_partial_capacity:
				best_partial_capacity = capacity
				best_partial = preview.duplicate(true)
		else:
			last_error = preview

	if not best_partial.is_empty():
		best_partial["success"] = true
		best_partial["whole_stack_fits"] = false
		best_partial["maximum_quantity"] = best_partial_capacity
		best_partial["total_compatible_headroom"] = total_compatible_headroom
		best_partial["message"] = "В одном слоте недостаточно места для всего стака"
		return best_partial
	last_error["target_container_id"] = target_container_id
	last_error["requested_quantity"] = requested_quantity
	last_error["whole_stack_fits"] = false
	return last_error


func quick_transfer(item_id: String, source_container_id: String, external_container_id: String) -> Dictionary:
	return quick_transfer_quantity(item_id, source_container_id, external_container_id, -1)


func quick_transfer_quantity(
	item_id: String,
	source_container_id: String,
	external_container_id: String,
	quantity: int
) -> Dictionary:
	var preview: Dictionary = preview_quick_transfer(item_id, source_container_id, external_container_id, quantity)
	if not bool(preview.get("success", false)):
		return preview
	var item = gameplay_controller.get_item(item_id) if gameplay_controller != null else null
	if item == null:
		return {"success": false, "error_code": "ITEM_NOT_FOUND"}
	var requested_quantity: int = int(item.quantity) if quantity < 0 else clampi(quantity, 1, int(item.quantity))
	var maximum_quantity := int(preview.get("maximum_quantity", requested_quantity))
	if not bool(preview.get("whole_stack_fits", maximum_quantity >= requested_quantity)) or maximum_quantity < requested_quantity:
		return {
			"success": false,
			"error_code": "QUICK_TRANSFER_WHOLE_STACK_NO_FIT",
			"message": "В одном слоте недостаточно места для всего стака. Перенесите часть через контекстное меню.",
			"target_container_id": String(preview.get("target_container_id", "")),
			"target_slot_index": int(preview.get("target_slot_index", -1)),
			"target_item_id": String(preview.get("target_item_id", "")),
			"requested_quantity": requested_quantity,
			"maximum_quantity": maximum_quantity,
			"total_compatible_headroom": int(preview.get("total_compatible_headroom", maximum_quantity)),
		}
	var result: Dictionary = transfer_quantity(
		item_id,
		requested_quantity,
		String(preview.get("target_container_id", "")),
		int(preview.get("target_slot_index", -1)),
		String(preview.get("target_item_id", ""))
	)
	result["requested_quantity"] = requested_quantity
	result["quick_transfer"] = true
	return result


func assign_hotbar(item_id: String, slot_index: int) -> Dictionary:
	if gameplay_controller == null:
		return {"success": false, "error_code": "CONTROLLER_NOT_READY"}
	var hotbar = gameplay_controller.get_container(gameplay_controller.player_hotbar_id)
	if hotbar == null or not hotbar.is_slot_container():
		return {"success": false, "error_code": "HOTBAR_NOT_READY"}
	if slot_index < 0 or slot_index >= int(hotbar.slot_count):
		return {"success": false, "error_code": "INVALID_HOTBAR_SLOT"}
	return transfer_stack(
		item_id,
		gameplay_controller.player_hotbar_id,
		slot_index,
		String(hotbar.get_item_at_slot(slot_index))
	)


func assign_hotbar_first_free(item_id: String) -> Dictionary:
	if gameplay_controller == null:
		return {"success": false, "error_code": "CONTROLLER_NOT_READY"}
	var hotbar = gameplay_controller.get_container(gameplay_controller.player_hotbar_id)
	if hotbar == null:
		return {"success": false, "error_code": "HOTBAR_NOT_READY"}
	var last_error: Dictionary = {"success": false, "error_code": "NO_COMPATIBLE_SLOT"}
	for slot_index in range(int(hotbar.slot_count)):
		if not String(hotbar.get_item_at_slot(slot_index)).is_empty():
			continue
		var preview: Dictionary = preview_transfer(item_id, -1, hotbar.container_id, slot_index, "")
		if bool(preview.get("success", false)):
			return assign_hotbar(item_id, slot_index)
		last_error = preview
	return last_error


func hotbar_slot_options(item_id: String) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if gameplay_controller == null:
		return options
	var hotbar = gameplay_controller.get_container(gameplay_controller.player_hotbar_id)
	if hotbar == null:
		return options
	for slot_index in range(int(hotbar.slot_count)):
		var target_item_id := String(hotbar.get_item_at_slot(slot_index))
		var preview: Dictionary = preview_transfer(item_id, -1, hotbar.container_id, slot_index, target_item_id)
		options.append({
			"slot_index": slot_index,
			"occupied": not target_item_id.is_empty(),
			"enabled": bool(preview.get("success", false)),
			"error_code": String(preview.get("error_code", "")),
		})
	return options


func select_hotbar(slot_index: int) -> Dictionary:
	if gameplay_controller == null:
		return {"success": false, "error_code": "CONTROLLER_NOT_READY"}
	return gameplay_controller.select_hotbar(slot_index)


func drop_one(item_id: String) -> Dictionary:
	if gameplay_controller == null:
		return {"success": false, "error_code": "CONTROLLER_NOT_READY"}
	return gameplay_controller.drop_item(item_id)


func drop_stack(item_id: String) -> Dictionary:
	if gameplay_controller == null:
		return {"success": false, "error_code": "CONTROLLER_NOT_READY"}
	return gameplay_controller.drop_item_stack(item_id)


func drop_quantity(item_id: String, quantity: int) -> Dictionary:
	if gameplay_controller == null:
		return {"success": false, "error_code": "CONTROLLER_NOT_READY"}
	return gameplay_controller.drop_item_quantity(item_id, quantity)


func inspect_item(item_id: String) -> Dictionary:
	if gameplay_controller == null:
		return {"success": false, "error_code": "CONTROLLER_NOT_READY"}
	var item = gameplay_controller.get_item(item_id)
	if item == null:
		return {"success": false, "error_code": "ITEM_NOT_FOUND"}
	var definition = gameplay_controller.get_definition(item.definition_id)
	return {
		"success": true,
		"item_id": item_id,
		"definition_id": String(item.definition_id),
		"display_name": String(item.display_name) if not String(item.display_name).is_empty() else String(definition.display_name),
		"quantity": int(item.quantity),
		"revision": int(item.revision),
		"components": item.components.duplicate(true),
		"relation": item.relation.duplicate(true),
	}


func result_message(result: Dictionary) -> String:
	if gameplay_controller == null:
		return String(result.get("message", result.get("error_code", "Ошибка")))
	var message: String = gameplay_controller.result_message(result)
	if not message.begins_with("Ошибка:"):
		return message
	var code := String(result.get("error_code", "UNKNOWN"))
	var ui_messages := {
		"NO_EXTERNAL_CONTAINER": "Сначала откройте контейнер клавишей E.",
		"QUICK_TRANSFER_SOURCE_UNSUPPORTED": "Быстрый перенос работает только между рюкзаком и открытым контейнером.",
		"NO_COMPATIBLE_SLOT": "В контейнере нет подходящей свободной ячейки.",
		"QUICK_TRANSFER_WHOLE_STACK_NO_FIT": "В одном слоте недостаточно места для всего стака. Перенесите часть через контекстное меню.",
		"SLOT_TAG_REJECTED": "Эта ячейка не принимает предмет такого типа.",
		"SLOT_DEFINITION_REJECTED": "Эта ячейка предназначена для другого предмета.",
		"HOTBAR_NOT_READY": "Быстрая панель недоступна.",
		"INVALID_HOTBAR_SLOT": "Выбран неверный слот быстрой панели.",
		"DROP_REJECTED": "Сюда нельзя положить предмет.",
	}
	return String(ui_messages.get(code, message))

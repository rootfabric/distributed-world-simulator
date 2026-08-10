class_name NetworkCharacterEquipmentGameplayController
extends "res://scripts/characters/equipment/character_equipment_gameplay_controller.gd"

const RESULT_EQUIPMENT_NETWORK_APPLY_FAILED := "CHARACTER_EQUIPMENT_NETWORK_APPLY_FAILED"


func equip_character_item(item_id: String, slot_index: int, quantity: int = -1) -> Dictionary:
	if not _uses_network_commands():
		return super.equip_character_item(item_id, slot_index, quantity)
	if not has_character_equipment():
		return _remember_character_equipment(_failure(RESULT_EQUIPMENT_NOT_CONFIGURED))
	var item = get_item(item_id)
	if item == null:
		return _remember_character_equipment(_failure("ITEM_NOT_FOUND"))
	var requested_quantity := int(item.quantity) if quantity < 0 else quantity
	if requested_quantity != 1 or int(item.quantity) != 1:
		return _remember_character_equipment(_failure(RESULT_EQUIPMENT_QUANTITY_INVALID))
	var result: Dictionary = _submit_network_operation(
		"equipment.equip",
		{"item_id": item_id, "slot_index": slot_index},
		"character_equip"
	)
	return _finish_network_equipment_operation(result, "Предмет надет")


func unequip_character_item(
	item_id: String,
	target_container_id: String,
	target_slot_index: int = -1
) -> Dictionary:
	if not _uses_network_commands():
		return super.unequip_character_item(item_id, target_container_id, target_slot_index)
	if not has_character_equipment():
		return _remember_character_equipment(_failure(RESULT_EQUIPMENT_NOT_CONFIGURED))
	if target_container_id != player_inventory_id or target_slot_index >= 0:
		return _remember_character_equipment(_failure("NETWORK_EQUIPMENT_UNEQUIP_TARGET_UNSUPPORTED", {
			"target_container_id": target_container_id,
			"target_slot_index": target_slot_index,
		}))
	var result: Dictionary = _submit_network_operation(
		"equipment.unequip",
		{"item_id": item_id},
		"character_unequip"
	)
	return _finish_network_equipment_operation(result, "Предмет снят")


func create_character_equipment_debug_snapshot() -> Dictionary:
	var result: Dictionary = super.create_character_equipment_debug_snapshot()
	result["schema"] = "planet_simulator.network_character_equipment_gameplay_controller.v1"
	result["network_mutation_enabled"] = _uses_network_commands()
	result["network_authority"] = "SERVER_ITEM_GRAPH" if _uses_network_commands() else "LOCAL_ITEM_TRANSFER_SERVICE"
	return result


func _finish_network_equipment_operation(result: Dictionary, success_message: String) -> Dictionary:
	if not bool(result.get("success", false)):
		return _remember_character_equipment(_normalize_equipment_result(result))
	# ItemGameplayController._submit_network_operation has already applied the
	# authoritative replica snapshot returned by the network bridge. Presentation
	# is therefore refreshed only after canonical server state is installed.
	var presentation_result: Dictionary = synchronize_character_equipment_presentation()
	if not bool(presentation_result.get("success", false)):
		return _remember_character_equipment(_failure(RESULT_EQUIPMENT_NETWORK_APPLY_FAILED, {
			"cause": presentation_result,
			"network_result": result,
		}))
	var normalized := _normalize_equipment_result(result)
	normalized["message"] = success_message
	normalized["character_equipment_presentation"] = presentation_result
	_refresh_ui()
	return _remember_character_equipment(normalized)

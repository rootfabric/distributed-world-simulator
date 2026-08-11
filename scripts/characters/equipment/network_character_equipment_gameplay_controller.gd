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


func preview_character_unequip(
	item_id: String,
	target_container_id: String,
	target_slot_index: int = -1,
	quantity: int = -1
) -> Dictionary:
	if not _uses_network_commands():
		return {"success": false, "error_code": "NETWORK_EQUIPMENT_PREVIEW_NOT_ACTIVE"}
	if not has_character_equipment():
		return _failure(RESULT_EQUIPMENT_NOT_CONFIGURED)
	var item = get_item(item_id)
	if item == null:
		return _failure("ITEM_NOT_FOUND")
	var requested_quantity := int(item.quantity) if quantity < 0 else quantity
	if requested_quantity != 1 or int(item.quantity) != 1:
		return _failure(RESULT_EQUIPMENT_QUANTITY_INVALID)
	var relation: Dictionary = Dictionary(item.relation)
	if (
		String(relation.get("kind", "")) != "CONTAINER"
		or String(relation.get("container_id", "")) != character_equipment_container_id
	):
		return _failure("CHARACTER_EQUIPMENT_ITEM_NOT_EQUIPPED")
	if target_container_id != player_inventory_id or target_slot_index < -1:
		return _failure("NETWORK_EQUIPMENT_UNEQUIP_TARGET_UNSUPPORTED", {
			"target_container_id": target_container_id,
			"target_slot_index": target_slot_index,
		})
	if get_container(player_inventory_id) == null:
		return _failure("TARGET_CONTAINER_INVALID", {"target_container_id": target_container_id})
	return {
		"success": true,
		"code": "OK",
		"mode": "NETWORK_UNEQUIP_TO_BACKPACK",
		"maximum_quantity": 1,
		"target_container_id": player_inventory_id,
		"requested_target_slot_index": target_slot_index,
		# This CH lineage predates the later slot-aware canonical network transfer
		# foundation. A graphical slot is therefore an accepted drop target, while
		# authority returns the item to the canonical backpack and the replica
		# deterministically assigns the available presentation slot.
		"placement_policy": "CANONICAL_BACKPACK_PRESENTATION_SLOT",
	}


func unequip_character_item(
	item_id: String,
	target_container_id: String,
	target_slot_index: int = -1
) -> Dictionary:
	if not _uses_network_commands():
		return super.unequip_character_item(item_id, target_container_id, target_slot_index)
	var preview: Dictionary = preview_character_unequip(item_id, target_container_id, target_slot_index, 1)
	if not bool(preview.get("success", false)):
		return _remember_character_equipment(preview)
	var result: Dictionary = _submit_network_operation(
		"equipment.unequip",
		{"item_id": item_id},
		"character_unequip"
	)
	if bool(result.get("success", false)):
		var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
		details["requested_target_slot_index"] = target_slot_index
		details["placement_policy"] = String(preview.get("placement_policy", ""))
		result["details"] = details
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

extends "res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service_p4.gd"

# V0-P5 canonical equipment relation.
#
# Equipment is not a second inventory/store. The existing canonical Item Graph
# item remains in its owning inventory and carries one optional `equipment`
# relation. Snapshot, checksum, replication and durable persistence therefore
# continue to use the single M4 Item Graph truth and the exact same item_id.

const EQUIP_COMMAND_TYPE := "item.equip"
const UNEQUIP_COMMAND_TYPE := "item.unequip"
const EQUIPMENT_SLOT_TOOL_MAIN := "tool/main"
const MINING_TOOL_DEFINITION_ID := "item/tool/mining"


func _execute(
	player_id: String,
	command_type: String,
	payload: Dictionary,
	authority_context: Dictionary
) -> Dictionary:
	match command_type:
		EQUIP_COMMAND_TYPE:
			return _equip_item(
				player_id,
				String(payload.get("item_id", "")),
				String(payload.get("slot_id", ""))
			)
		UNEQUIP_COMMAND_TYPE:
			return _unequip_item(
				player_id,
				String(payload.get("item_id", "")),
				String(payload.get("slot_id", ""))
			)
	return super._execute(player_id, command_type, payload, authority_context)


func get_equipped_item(
	logical_player_id: String,
	slot_id: String = EQUIPMENT_SLOT_TOOL_MAIN
) -> Dictionary:
	var player_id := logical_player_id.strip_edges().to_lower()
	var slot := slot_id.strip_edges().to_lower()
	if player_id.is_empty() or not _is_supported_equipment_slot(slot):
		return {}
	var item_ids := _items.keys()
	item_ids.sort()
	for item_id_value in item_ids:
		var item: Dictionary = _items[item_id_value]
		var equipment_value = item.get("equipment", null)
		if not equipment_value is Dictionary:
			continue
		var equipment: Dictionary = equipment_value
		if (
			String(equipment.get("player_id", "")) == player_id
			and String(equipment.get("slot_id", "")) == slot
		):
			return item.duplicate(true)
	return {}


func has_equipped_mining_tool(logical_player_id: String) -> bool:
	var item := get_equipped_item(logical_player_id, EQUIPMENT_SLOT_TOOL_MAIN)
	return (
		not item.is_empty()
		and String(item.get("definition_id", "")) == MINING_TOOL_DEFINITION_ID
		and int(item.get("quantity", 0)) == 1
	)


func validate_durable_state(value: Dictionary) -> Dictionary:
	var validation := super.validate_durable_state(value)
	if not bool(validation.get("success", false)):
		return validation
	var snapshot_value = value.get("snapshot", null)
	if not snapshot_value is Dictionary:
		return _failure("INVALID_P5_EQUIPMENT_DURABLE_STATE")
	var snapshot: Dictionary = snapshot_value
	var occupied_slots: Dictionary = {}
	for item_value in snapshot.get("items", []):
		if not item_value is Dictionary:
			return _failure("INVALID_P5_EQUIPMENT_ITEM")
		var item: Dictionary = item_value
		if not item.has("equipment"):
			continue
		var equipment_value = item.get("equipment", null)
		if not equipment_value is Dictionary:
			return _failure("INVALID_P5_EQUIPMENT_RELATION")
		var equipment: Dictionary = equipment_value
		var player_id := String(equipment.get("player_id", ""))
		var slot_id := String(equipment.get("slot_id", ""))
		var location_value = item.get("location", null)
		if (
			player_id.is_empty()
			or player_id != player_id.strip_edges().to_lower()
			or not _is_supported_equipment_slot(slot_id)
			or not location_value is Dictionary
			or String(location_value.get("kind", "")) != "INVENTORY"
			or String(location_value.get("player_id", "")) != player_id
			or String(item.get("definition_id", "")) != MINING_TOOL_DEFINITION_ID
			or int(item.get("quantity", 0)) != 1
		):
			return _failure("INVALID_P5_EQUIPMENT_RELATION")
		var key := "%s|%s" % [player_id, slot_id]
		if occupied_slots.has(key):
			return _failure("DUPLICATE_P5_EQUIPMENT_SLOT")
		occupied_slots[key] = String(item.get("item_id", ""))
	return validation


func _equip_item(player_id: String, item_id: String, slot_id: String) -> Dictionary:
	var normalized_item_id := item_id.strip_edges().to_lower()
	var slot := slot_id.strip_edges().to_lower()
	if normalized_item_id.is_empty():
		return _failure("INVALID_EQUIPMENT_ITEM")
	if not _is_supported_equipment_slot(slot):
		return _failure("INVALID_EQUIPMENT_SLOT")
	var access := _owned_item(player_id, normalized_item_id)
	if not bool(access.get("success", false)):
		return access
	var item: Dictionary = _items[normalized_item_id]
	if String(item.get("definition_id", "")) != MINING_TOOL_DEFINITION_ID:
		return _failure("ITEM_NOT_EQUIPPABLE_TOOL")
	if int(item.get("quantity", 0)) != 1:
		return _failure("EQUIPMENT_ITEM_MUST_BE_SINGLETON")
	if item.has("equipment"):
		return _failure("ITEM_ALREADY_EQUIPPED")
	var occupied := get_equipped_item(player_id, slot)
	if not occupied.is_empty():
		return _failure("EQUIPMENT_SLOT_OCCUPIED")
	item["equipment"] = {
		"player_id": player_id,
		"slot_id": slot,
	}
	_items[normalized_item_id] = item
	return _success({
		"item_id": normalized_item_id,
		"definition_id": String(item.get("definition_id", "")),
		"slot_id": slot,
		"logical_player_id": player_id,
	})


func _unequip_item(player_id: String, item_id: String, slot_id: String) -> Dictionary:
	var normalized_item_id := item_id.strip_edges().to_lower()
	var slot := slot_id.strip_edges().to_lower()
	if normalized_item_id.is_empty():
		return _failure("INVALID_EQUIPMENT_ITEM")
	if not _is_supported_equipment_slot(slot):
		return _failure("INVALID_EQUIPMENT_SLOT")
	var access := _owned_item(player_id, normalized_item_id)
	if not bool(access.get("success", false)):
		return access
	var item: Dictionary = _items[normalized_item_id]
	var equipment_value = item.get("equipment", null)
	if not equipment_value is Dictionary:
		return _failure("ITEM_NOT_EQUIPPED")
	var equipment: Dictionary = equipment_value
	if (
		String(equipment.get("player_id", "")) != player_id
		or String(equipment.get("slot_id", "")) != slot
	):
		return _failure("EQUIPMENT_RELATION_MISMATCH")
	item.erase("equipment")
	_items[normalized_item_id] = item
	return _success({
		"item_id": normalized_item_id,
		"slot_id": slot,
		"logical_player_id": player_id,
	})


func _is_supported_equipment_slot(slot_id: String) -> bool:
	return slot_id == EQUIPMENT_SLOT_TOOL_MAIN

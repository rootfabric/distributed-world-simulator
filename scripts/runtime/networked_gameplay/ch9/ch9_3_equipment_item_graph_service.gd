class_name Ch9EquipmentItemGraphService
extends "res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd"

const EquipmentCatalog = preload("res://scripts/characters/equipment/network_character_equipment_catalog.gd")

const RESULT_EQUIPMENT_SLOT_INVALID := "EQUIPMENT_SLOT_INVALID"
const RESULT_EQUIPMENT_DEFINITION_MISMATCH := "EQUIPMENT_DEFINITION_MISMATCH"
const RESULT_EQUIPMENT_ITEM_NOT_OWNED := "EQUIPMENT_ITEM_NOT_OWNED"
const RESULT_EQUIPMENT_ITEM_NOT_EQUIPPED := "EQUIPMENT_ITEM_NOT_EQUIPPED"
const RESULT_EQUIPMENT_QUANTITY_INVALID := "EQUIPMENT_QUANTITY_INVALID"
const RESULT_EQUIPMENT_CONTAINER_INVALID := "EQUIPMENT_CONTAINER_INVALID"


func ensure_player(logical_player_id: String) -> void:
	var player_id := logical_player_id.strip_edges().to_lower()
	if player_id.is_empty():
		return
	var existed := _inventories.has(player_id)
	super.ensure_player(player_id)
	_ensure_equipment_container(player_id)
	if _sandbox_mode and not existed:
		_seed_equipment_wearables(player_id)


func _execute(player_id: String, command_type: String, payload: Dictionary, authority_context: Dictionary) -> Dictionary:
	match command_type:
		"equipment.equip":
			return _equip_item(player_id, String(payload.get("item_id", "")), int(payload.get("slot_index", -1)))
		"equipment.unequip":
			return _unequip_item(player_id, String(payload.get("item_id", "")))
	return super._execute(player_id, command_type, payload, authority_context)


func _ensure_equipment_container(player_id: String) -> void:
	var container_id := EquipmentCatalog.equipment_container_id(player_id)
	if _containers.has(container_id):
		return
	_containers[container_id] = {
		"container_id": container_id,
		"owner_item_id": "",
		"owner_player_id": player_id,
		"owner_entity_id": EquipmentCatalog.owner_entity_id(player_id),
		"container_kind": EquipmentCatalog.EQUIPMENT_CONTAINER_KIND,
		"capacity": EquipmentCatalog.EQUIPMENT_SLOT_COUNT,
		"slots": [],
		"equipment_slots": {},
	}


func _seed_equipment_wearables(player_id: String) -> void:
	var inventory: Dictionary = _inventories[player_id]
	var inventory_items: Array = Array(inventory.get("inventory", [])).duplicate()
	for spec in EquipmentCatalog.wearable_specs():
		var item_id := "item/player/%s/wearable/%s" % [player_id, String(spec.get("suffix", ""))]
		if not _items.has(item_id):
			_items[item_id] = {
				"item_id": item_id,
				"definition_id": String(spec.get("definition_id", "")),
				"quantity": 1,
				"location": {"kind": "INVENTORY", "player_id": player_id},
				"mounted": false,
			}
		if item_id not in inventory_items:
			inventory_items.append(item_id)
	inventory["inventory"] = inventory_items
	_inventories[player_id] = inventory


func _equip_item(player_id: String, item_id: String, slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= EquipmentCatalog.EQUIPMENT_SLOT_COUNT:
		return _failure(RESULT_EQUIPMENT_SLOT_INVALID)
	if not _items.has(item_id):
		return _failure("ITEM_NOT_FOUND")
	var item: Dictionary = _items[item_id]
	if int(item.get("quantity", 0)) != 1:
		return _failure(RESULT_EQUIPMENT_QUANTITY_INVALID)
	if String(item.get("definition_id", "")) != EquipmentCatalog.canonical_definition_for_slot(slot_index):
		return _failure(RESULT_EQUIPMENT_DEFINITION_MISMATCH)
	var container_id := EquipmentCatalog.equipment_container_id(player_id)
	_ensure_equipment_container(player_id)
	if not _containers.has(container_id):
		return _failure(RESULT_EQUIPMENT_CONTAINER_INVALID)
	var location: Dictionary = Dictionary(item.get("location", {}))
	if (
		String(location.get("kind", "")) == "CONTAINER"
		and String(location.get("container_id", "")) == container_id
		and int(location.get("slot_index", -1)) == slot_index
	):
		return _success({"item_id": item_id, "slot_index": slot_index, "container_id": container_id, "no_op": true})
	if String(location.get("kind", "")) != "INVENTORY" or String(location.get("player_id", "")) != player_id:
		return _failure(RESULT_EQUIPMENT_ITEM_NOT_OWNED)

	var container: Dictionary = _containers[container_id]
	var equipment_slots: Dictionary = Dictionary(container.get("equipment_slots", {})).duplicate(true)
	var slot_key := str(slot_index)
	var replaced_item_id := String(equipment_slots.get(slot_key, ""))
	if not replaced_item_id.is_empty() and replaced_item_id != item_id:
		if not _items.has(replaced_item_id):
			return _failure(RESULT_EQUIPMENT_CONTAINER_INVALID)
		var replaced: Dictionary = _items[replaced_item_id]
		var replaced_location: Dictionary = Dictionary(replaced.get("location", {}))
		if (
			String(replaced_location.get("kind", "")) != "CONTAINER"
			or String(replaced_location.get("container_id", "")) != container_id
			or int(replaced_location.get("slot_index", -1)) != slot_index
		):
			return _failure(RESULT_EQUIPMENT_CONTAINER_INVALID)
		# One-for-one replacement is one authority operation. Both item locations
		# and membership collections are changed before the snapshot is published.
		replaced["location"] = {"kind": "INVENTORY", "player_id": player_id}
		_items[replaced_item_id] = replaced
		_add_to_inventory(player_id, replaced_item_id)

	_remove_from_inventory(player_id, item_id)
	item["location"] = {"kind": "CONTAINER", "container_id": container_id, "slot_index": slot_index}
	_items[item_id] = item
	equipment_slots[slot_key] = item_id
	container["equipment_slots"] = equipment_slots
	var referenced_items: Array = Array(container.get("slots", [])).duplicate()
	if not replaced_item_id.is_empty():
		referenced_items.erase(replaced_item_id)
	if item_id not in referenced_items:
		referenced_items.append(item_id)
	container["slots"] = referenced_items
	_containers[container_id] = container
	return _success({
		"item_id": item_id,
		"slot_index": slot_index,
		"container_id": container_id,
		"replaced_item_id": replaced_item_id,
		"atomic_single_replacement": not replaced_item_id.is_empty(),
	})


func _unequip_item(player_id: String, item_id: String) -> Dictionary:
	if not _items.has(item_id):
		return _failure("ITEM_NOT_FOUND")
	var item: Dictionary = _items[item_id]
	var location: Dictionary = Dictionary(item.get("location", {}))
	var container_id := EquipmentCatalog.equipment_container_id(player_id)
	if String(location.get("kind", "")) == "INVENTORY" and String(location.get("player_id", "")) == player_id:
		return _success({"item_id": item_id, "container_id": "inventory/%s" % player_id, "no_op": true})
	if String(location.get("kind", "")) != "CONTAINER" or String(location.get("container_id", "")) != container_id:
		return _failure(RESULT_EQUIPMENT_ITEM_NOT_EQUIPPED)
	if not _containers.has(container_id):
		return _failure(RESULT_EQUIPMENT_CONTAINER_INVALID)
	var slot_index := int(location.get("slot_index", -1))
	var container: Dictionary = _containers[container_id]
	var equipment_slots: Dictionary = Dictionary(container.get("equipment_slots", {})).duplicate(true)
	if String(equipment_slots.get(str(slot_index), "")) != item_id:
		return _failure(RESULT_EQUIPMENT_CONTAINER_INVALID)
	equipment_slots.erase(str(slot_index))
	container["equipment_slots"] = equipment_slots
	var referenced_items: Array = Array(container.get("slots", [])).duplicate()
	referenced_items.erase(item_id)
	container["slots"] = referenced_items
	_containers[container_id] = container
	item["location"] = {"kind": "INVENTORY", "player_id": player_id}
	_items[item_id] = item
	_add_to_inventory(player_id, item_id)
	return _success({
		"item_id": item_id,
		"slot_index": slot_index,
		"container_id": "inventory/%s" % player_id,
	})


func equipment_container_snapshot(logical_player_id: String) -> Dictionary:
	var container_id := EquipmentCatalog.equipment_container_id(logical_player_id)
	return Dictionary(_containers.get(container_id, {})).duplicate(true)

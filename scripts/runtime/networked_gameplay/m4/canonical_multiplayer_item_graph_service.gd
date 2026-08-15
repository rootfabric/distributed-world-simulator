extends "res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service_base.gd"

# V0-P1 R5 canonical slot adapter.
# The inherited M4 service remains the sole Item Graph owner. Membership arrays
# remain durable/backward-compatible; location.slot_index is authoritative slot
# identity. Adapted from accepted M7 slot-aware transfers to P1's 32-slot bag.

const PLAYER_INVENTORY_CAPACITY := 32

var _player_materializations: int = 0


func ensure_player(logical_player_id: String) -> void:
	var player_id := logical_player_id.strip_edges().to_lower()
	if player_id.is_empty():
		return
	var existed := _inventories.has(player_id)
	super.ensure_player(player_id)
	if _inventories.has(player_id):
		_normalize_player_inventory_slots(player_id)
	if not existed and _inventories.has(player_id):
		_revision += 1
		_tick += 1
		_player_materializations += 1


func ensure_player_for_join(logical_player_id: String) -> Dictionary:
	var player_id := logical_player_id.strip_edges().to_lower()
	if player_id.is_empty():
		return {"success": false, "error_code": "ITEM_GRAPH_PLAYER_ID_REQUIRED", "details": {}}
	var before_revision := _revision
	ensure_player(player_id)
	if not _inventories.has(player_id):
		return {"success": false, "error_code": "ITEM_GRAPH_PLAYER_MATERIALIZATION_FAILED", "details": {"logical_player_id": player_id}}
	var inventory: Dictionary = Dictionary(_inventories[player_id]).duplicate(true)
	return {
		"success": true,
		"error_code": "",
		"details": {
			"logical_player_id": player_id,
			"created": _revision > before_revision,
			"revision": _revision,
			"tick": _tick,
			"inventory_item_count": Array(inventory.get("inventory", [])).size(),
			"hotbar_size": Array(inventory.get("hotbar", [])).size(),
		}
	}


func get_player_materialization_report() -> Dictionary:
	return {
		"player_materializations": _player_materializations,
		"inventory_count": _inventories.size(),
		"revision": _revision,
		"tick": _tick,
	}


func create_snapshot() -> Dictionary:
	_normalize_slot_locations()
	return super.create_snapshot()


func _transfer(
	player_id: String,
	item_id: String,
	quantity: int,
	target_container_id: String,
	target_slot_index: int,
	target_item_id: String
) -> Dictionary:
	if not _items.has(item_id):
		return _failure("ITEM_NOT_FOUND")
	var access := _accessible_item(player_id, item_id)
	if not bool(access.get("success", false)):
		return access
	var source: Dictionary = _items[item_id]
	var source_quantity := int(source.get("quantity", 1))
	var amount := source_quantity if quantity < 0 else quantity
	if amount < 1 or amount > source_quantity:
		return _failure("INVALID_TRANSFER_QUANTITY")
	var normalized_target := target_container_id.strip_edges()
	if normalized_target.is_empty():
		return _failure("TARGET_CONTAINER_REQUIRED")
	if not target_item_id.strip_edges().is_empty():
		return _transfer_to_stack(player_id, item_id, amount, target_item_id.strip_edges())
	if normalized_target == "inventory/%s" % player_id:
		return _transfer_to_inventory_slot(player_id, item_id, amount, target_slot_index)
	if normalized_target == "hotbar/%s" % player_id:
		return super._transfer(player_id, item_id, quantity, target_container_id, target_slot_index, target_item_id)
	if normalized_target.begins_with("container/"):
		return _transfer_to_container_slot(player_id, item_id, amount, normalized_target, target_slot_index)
	return _failure("UNSUPPORTED_TRANSFER_TARGET")


func _transfer_to_inventory_slot(player_id: String, item_id: String, amount: int, target_slot_index: int) -> Dictionary:
	ensure_player(player_id)
	_normalize_player_inventory_slots(player_id)
	var item: Dictionary = _items[item_id]
	var location: Dictionary = Dictionary(item.get("location", {})).duplicate(true)
	var kind := String(location.get("kind", ""))
	if kind == "CONTAINER":
		var source_container_id := String(location.get("container_id", ""))
		if String(_open_containers.get(player_id, "")) != source_container_id:
			return _failure("SOURCE_CONTAINER_ACCESS_DENIED")
	if kind == "MOUNT":
		return _failure("MOUNT_DETACH_REQUIRED")
	var source_quantity := int(item.get("quantity", 1))
	var whole_move := amount == source_quantity
	var source_is_same_inventory := kind == "INVENTORY" and String(location.get("player_id", "")) == player_id
	var source_hotbar_assigned := _is_hotbar_assigned(player_id, item_id)
	var resolved_slot := target_slot_index
	if resolved_slot < 0:
		resolved_slot = _first_free_inventory_slot(player_id, item_id if whole_move and source_is_same_inventory and not source_hotbar_assigned else "")
	if resolved_slot < 0 or resolved_slot >= PLAYER_INVENTORY_CAPACITY:
		return _failure("CONTAINER_FULL")
	var exclude_source := item_id if whole_move and source_is_same_inventory and not source_hotbar_assigned else ""
	var occupant := _inventory_slot_occupant(player_id, resolved_slot, exclude_source)
	if not occupant.is_empty():
		return _failure("TARGET_SLOT_OCCUPIED")
	if whole_move and source_is_same_inventory and not source_hotbar_assigned and int(location.get("slot_index", -1)) == resolved_slot:
		return _success({"item_id": item_id, "container_id": "inventory/%s" % player_id, "quantity": amount, "moved_quantity": amount, "target_slot_index": resolved_slot, "no_op": true})
	var moved_item_id := _extract_transfer_item(item_id, amount)
	if moved_item_id.is_empty():
		return _failure("INVALID_TRANSFER_QUANTITY")
	if moved_item_id == item_id:
		_remove_from_source(item_id, location)
	var moved: Dictionary = _items[moved_item_id]
	moved["location"] = {"kind": "INVENTORY", "player_id": player_id, "slot_index": resolved_slot}
	_items[moved_item_id] = moved
	_add_to_inventory(player_id, moved_item_id)
	if moved_item_id == item_id:
		_clear_hotbar_assignment(player_id, moved_item_id)
	_normalize_player_inventory_slots(player_id)
	return _success({"item_id": moved_item_id, "container_id": "inventory/%s" % player_id, "quantity": amount, "moved_quantity": amount, "target_slot_index": resolved_slot})


func _transfer_to_container_slot(player_id: String, item_id: String, amount: int, container_id: String, target_slot_index: int) -> Dictionary:
	if not _containers.has(container_id):
		return _failure("CONTAINER_NOT_FOUND")
	if String(_open_containers.get(player_id, "")) != container_id:
		return _failure("TARGET_CONTAINER_ACCESS_DENIED")
	_normalize_container_slots(container_id)
	var item: Dictionary = _items[item_id]
	var location: Dictionary = Dictionary(item.get("location", {})).duplicate(true)
	if String(location.get("kind", "")) == "MOUNT":
		return _failure("MOUNT_DETACH_REQUIRED")
	if String(location.get("kind", "")) == "CONTAINER":
		var source_container_id := String(location.get("container_id", ""))
		if String(_open_containers.get(player_id, "")) != source_container_id:
			return _failure("SOURCE_CONTAINER_ACCESS_DENIED")
		_normalize_container_slots(source_container_id)
	var container: Dictionary = _containers[container_id]
	var capacity := int(container.get("capacity", 0))
	if capacity < 1:
		return _failure("CONTAINER_FULL")
	var source_quantity := int(item.get("quantity", 1))
	var whole_move := amount == source_quantity
	var source_is_same_container := String(location.get("kind", "")) == "CONTAINER" and String(location.get("container_id", "")) == container_id
	var resolved_slot := target_slot_index
	if resolved_slot < 0:
		resolved_slot = _first_free_container_slot(container_id, item_id if whole_move and source_is_same_container else "")
	if resolved_slot < 0 or resolved_slot >= capacity:
		return _failure("CONTAINER_FULL")
	var exclude_source := item_id if whole_move and source_is_same_container else ""
	var occupant := _container_slot_occupant(container_id, resolved_slot, exclude_source)
	if not occupant.is_empty():
		return _failure("TARGET_SLOT_OCCUPIED")
	if whole_move and source_is_same_container and int(location.get("slot_index", -1)) == resolved_slot:
		return _success({"item_id": item_id, "container_id": container_id, "quantity": amount, "moved_quantity": amount, "target_slot_index": resolved_slot, "no_op": true})
	var moved_item_id := _extract_transfer_item(item_id, amount)
	if moved_item_id.is_empty():
		return _failure("INVALID_TRANSFER_QUANTITY")
	if moved_item_id == item_id and not source_is_same_container:
		_remove_from_source(item_id, location)
	var slots: Array = Array(container.get("slots", [])).duplicate()
	if moved_item_id not in slots:
		slots.append(moved_item_id)
	container["slots"] = slots
	_containers[container_id] = container
	var moved: Dictionary = _items[moved_item_id]
	moved["location"] = {"kind": "CONTAINER", "container_id": container_id, "slot_index": resolved_slot}
	_items[moved_item_id] = moved
	_normalize_container_slots(container_id)
	return _success({"item_id": moved_item_id, "container_id": container_id, "quantity": amount, "moved_quantity": amount, "target_slot_index": resolved_slot})


func _normalize_slot_locations() -> void:
	for player_id_value in _inventories.keys():
		_normalize_player_inventory_slots(String(player_id_value))
	for container_id_value in _containers.keys():
		_normalize_container_slots(String(container_id_value))


func _normalize_player_inventory_slots(player_id: String) -> void:
	if not _inventories.has(player_id):
		return
	var inventory: Dictionary = _inventories[player_id]
	var membership: Array = Array(inventory.get("inventory", [])).duplicate()
	var hotbar_items := _hotbar_item_set(player_id)
	var used: Dictionary = {}
	for item_id_value in membership:
		var item_id := String(item_id_value)
		if hotbar_items.has(item_id) or not _items.has(item_id):
			continue
		var item: Dictionary = _items[item_id]
		var location: Dictionary = Dictionary(item.get("location", {})).duplicate(true)
		if String(location.get("kind", "")) != "INVENTORY" or String(location.get("player_id", "")) != player_id:
			continue
		var slot_index := int(location.get("slot_index", -1))
		if slot_index >= 0 and slot_index < PLAYER_INVENTORY_CAPACITY and not used.has(slot_index):
			used[slot_index] = item_id
		else:
			location.erase("slot_index")
			item["location"] = location
			_items[item_id] = item
	for membership_index in range(membership.size()):
		var item_id := String(membership[membership_index])
		if hotbar_items.has(item_id) or not _items.has(item_id):
			continue
		var item: Dictionary = _items[item_id]
		var location: Dictionary = Dictionary(item.get("location", {})).duplicate(true)
		if String(location.get("kind", "")) != "INVENTORY" or String(location.get("player_id", "")) != player_id or location.has("slot_index"):
			continue
		var resolved_slot := -1
		if membership_index < PLAYER_INVENTORY_CAPACITY and not used.has(membership_index):
			resolved_slot = membership_index
		else:
			for candidate in range(PLAYER_INVENTORY_CAPACITY):
				if not used.has(candidate):
					resolved_slot = candidate
					break
		if resolved_slot < 0:
			continue
		location["slot_index"] = resolved_slot
		item["location"] = location
		_items[item_id] = item
		used[resolved_slot] = item_id


func _normalize_container_slots(container_id: String) -> void:
	if not _containers.has(container_id):
		return
	var container: Dictionary = _containers[container_id]
	var capacity := int(container.get("capacity", 0))
	if capacity < 1:
		return
	var membership: Array = Array(container.get("slots", [])).duplicate()
	var used: Dictionary = {}
	for item_id_value in membership:
		var item_id := String(item_id_value)
		if not _items.has(item_id):
			continue
		var item: Dictionary = _items[item_id]
		var location: Dictionary = Dictionary(item.get("location", {})).duplicate(true)
		if String(location.get("kind", "")) != "CONTAINER" or String(location.get("container_id", "")) != container_id:
			continue
		var slot_index := int(location.get("slot_index", -1))
		if slot_index >= 0 and slot_index < capacity and not used.has(slot_index):
			used[slot_index] = item_id
		else:
			location.erase("slot_index")
			item["location"] = location
			_items[item_id] = item
	for membership_index in range(membership.size()):
		var item_id := String(membership[membership_index])
		if not _items.has(item_id):
			continue
		var item: Dictionary = _items[item_id]
		var location: Dictionary = Dictionary(item.get("location", {})).duplicate(true)
		if String(location.get("kind", "")) != "CONTAINER" or String(location.get("container_id", "")) != container_id or location.has("slot_index"):
			continue
		var resolved_slot := -1
		if membership_index < capacity and not used.has(membership_index):
			resolved_slot = membership_index
		else:
			for candidate in range(capacity):
				if not used.has(candidate):
					resolved_slot = candidate
					break
		if resolved_slot < 0:
			continue
		location["slot_index"] = resolved_slot
		item["location"] = location
		_items[item_id] = item
		used[resolved_slot] = item_id


func _inventory_slot_occupant(player_id: String, slot_index: int, exclude_item_id: String = "") -> String:
	if not _inventories.has(player_id):
		return ""
	var membership: Array = Array(Dictionary(_inventories[player_id]).get("inventory", []))
	var hotbar_items := _hotbar_item_set(player_id)
	for item_id_value in membership:
		var item_id := String(item_id_value)
		if item_id == exclude_item_id or hotbar_items.has(item_id) or not _items.has(item_id):
			continue
		var location: Dictionary = Dictionary(_items[item_id]).get("location", {})
		if String(location.get("kind", "")) == "INVENTORY" and String(location.get("player_id", "")) == player_id and int(location.get("slot_index", -1)) == slot_index:
			return item_id
	return ""


func _container_slot_occupant(container_id: String, slot_index: int, exclude_item_id: String = "") -> String:
	if not _containers.has(container_id):
		return ""
	var membership: Array = Array(Dictionary(_containers[container_id]).get("slots", []))
	for item_id_value in membership:
		var item_id := String(item_id_value)
		if item_id == exclude_item_id or not _items.has(item_id):
			continue
		var location: Dictionary = Dictionary(_items[item_id]).get("location", {})
		if String(location.get("kind", "")) == "CONTAINER" and String(location.get("container_id", "")) == container_id and int(location.get("slot_index", -1)) == slot_index:
			return item_id
	return ""


func _first_free_inventory_slot(player_id: String, exclude_item_id: String = "") -> int:
	for slot_index in range(PLAYER_INVENTORY_CAPACITY):
		if _inventory_slot_occupant(player_id, slot_index, exclude_item_id).is_empty():
			return slot_index
	return -1


func _first_free_container_slot(container_id: String, exclude_item_id: String = "") -> int:
	if not _containers.has(container_id):
		return -1
	var capacity := int(Dictionary(_containers[container_id]).get("capacity", 0))
	for slot_index in range(capacity):
		if _container_slot_occupant(container_id, slot_index, exclude_item_id).is_empty():
			return slot_index
	return -1


func _hotbar_item_set(player_id: String) -> Dictionary:
	var result: Dictionary = {}
	if not _inventories.has(player_id):
		return result
	var hotbar: Array = Array(Dictionary(_inventories[player_id]).get("hotbar", []))
	for item_id_value in hotbar:
		var item_id := String(item_id_value)
		if not item_id.is_empty():
			result[item_id] = true
	return result


func _is_hotbar_assigned(player_id: String, item_id: String) -> bool:
	return _hotbar_item_set(player_id).has(item_id)

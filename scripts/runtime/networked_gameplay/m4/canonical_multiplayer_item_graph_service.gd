extends "res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service_base.gd"

# V0-P1 R7 canonical slot adapter.
# The inherited M4 service remains the sole Item Graph owner. Membership arrays
# remain durable/backward-compatible; location.slot_index is authoritative slot
# identity. R7 makes existing-player/rejection paths mutation-free and ensures
# inventory-producing successful mutations publish complete slot identity.

const PLAYER_INVENTORY_CAPACITY := 32

var _player_materializations: int = 0


func ensure_player(logical_player_id: String) -> void:
	var player_id := logical_player_id.strip_edges().to_lower()
	if player_id.is_empty():
		return
	var existed := _inventories.has(player_id)
	super.ensure_player(player_id)
	if not existed and _inventories.has(player_id):
		# First materialization is the only runtime compatibility-normalization
		# boundary in P1. It is published by the same revision/tick advance below.
		_normalize_player_inventory_slots(player_id)
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


func _pickup(player_id: String, item_id: String, authority_context: Dictionary = {}) -> Dictionary:
	if not _items.has(item_id):
		return _failure("ITEM_NOT_FOUND")
	var item: Dictionary = _items[item_id]
	if String(item.get("location", {}).get("kind", "")) != "WORLD":
		return _failure("ITEM_ALREADY_CLAIMED")
	var spatial_check := _validate_world_item_interaction(item, authority_context, SANDBOX_PICKUP_RANGE_M)
	if not bool(spatial_check.get("success", false)):
		return spatial_check
	var resolved_slot := _first_free_inventory_slot(player_id)
	if resolved_slot < 0:
		return _failure("CONTAINER_FULL")
	item["location"] = {
		"kind": "INVENTORY",
		"player_id": player_id,
		"slot_index": resolved_slot,
	}
	_items[item_id] = item
	_add_to_inventory(player_id, item_id)
	return _success({
		"item_id": item_id,
		"winner_player_id": player_id,
		"target_slot_index": resolved_slot,
		"spatially_validated": _sandbox_mode,
	})


func _split(player_id: String, item_id: String, quantity: int) -> Dictionary:
	var access := _owned_item(player_id, item_id)
	if not bool(access.get("success", false)):
		return access
	var item: Dictionary = _items[item_id]
	var source_quantity := int(item.get("quantity", 1))
	if quantity < 1 or quantity >= source_quantity:
		return _failure("INVALID_SPLIT_QUANTITY")
	var resolved_slot := _first_free_inventory_slot(player_id)
	if resolved_slot < 0:
		return _failure("CONTAINER_FULL")
	item["quantity"] = source_quantity - quantity
	_items[item_id] = item
	var new_item_id := "%s/split/%d" % [item_id, _revision + 1]
	_items[new_item_id] = {
		"item_id": new_item_id,
		"definition_id": item["definition_id"],
		"quantity": quantity,
		"location": {
			"kind": "INVENTORY",
			"player_id": player_id,
			"slot_index": resolved_slot,
		},
		"mounted": false,
	}
	_add_to_inventory(player_id, new_item_id)
	return _success({
		"item_id": new_item_id,
		"target_slot_index": resolved_slot,
	})


func _detach(player_id: String, mount_id: String, authority_context: Dictionary = {}) -> Dictionary:
	if not _mounts.has(mount_id):
		return _failure("MOUNT_NOT_FOUND")
	var mount: Dictionary = _mounts[mount_id]
	var mount_spatial := _validate_mount_interaction(mount, authority_context)
	if not bool(mount_spatial.get("success", false)):
		return mount_spatial
	var item_id := String(mount.get("item_id", ""))
	if item_id.is_empty():
		return _failure("MOUNT_EMPTY")
	var item: Dictionary = _items[item_id]
	if String(item.get("location", {}).get("owner_player_id", "")) != player_id:
		return _failure("PLAYER_PERMISSION_DENIED")
	var resolved_slot := _first_free_inventory_slot(player_id)
	if resolved_slot < 0:
		return _failure("CONTAINER_FULL")
	mount["item_id"] = ""
	_mounts[mount_id] = mount
	item["location"] = {
		"kind": "INVENTORY",
		"player_id": player_id,
		"slot_index": resolved_slot,
	}
	item["mounted"] = false
	_items[item_id] = item
	_add_to_inventory(player_id, item_id)
	return _success({
		"item_id": item_id,
		"target_slot_index": resolved_slot,
	})


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
	var normalized_target_item := target_item_id.strip_edges()
	if not normalized_target_item.is_empty():
		if not _items.has(normalized_target_item):
			return _failure("ITEM_NOT_FOUND")
		var target: Dictionary = _items[normalized_target_item]
		if String(source.get("definition_id", "")) == String(target.get("definition_id", "")):
			return _transfer_to_stack(player_id, item_id, amount, normalized_target_item)
		return _swap_with_occupied_target(
			player_id,
			item_id,
			amount,
			normalized_target,
			target_slot_index,
			normalized_target_item
		)
	if normalized_target == "inventory/%s" % player_id:
		return _transfer_to_inventory_slot(player_id, item_id, amount, target_slot_index)
	if normalized_target == "hotbar/%s" % player_id:
		if target_slot_index < 0 or target_slot_index >= _hotbar_size():
			return _failure("INVALID_HOTBAR_INDEX")
		return super._transfer(player_id, item_id, quantity, target_container_id, target_slot_index, target_item_id)
	if normalized_target.begins_with("container/"):
		return _transfer_to_container_slot(player_id, item_id, amount, normalized_target, target_slot_index)
	return _failure("UNSUPPORTED_TRANSFER_TARGET")


func _swap_with_occupied_target(
	player_id: String,
	item_id: String,
	amount: int,
	target_container_id: String,
	target_slot_index: int,
	target_item_id: String
) -> Dictionary:
	if target_slot_index < 0:
		return _failure("SWAP_TARGET_SLOT_REQUIRED")
	if target_container_id == "hotbar/%s" % player_id:
		return _failure("SWAP_HOTBAR_UNSUPPORTED")
	if not _items.has(item_id) or not _items.has(target_item_id):
		return _failure("ITEM_NOT_FOUND")
	var source: Dictionary = _items[item_id]
	var target: Dictionary = _items[target_item_id]
	var source_quantity := int(source.get("quantity", 1))
	if amount != source_quantity:
		return {
			"success": false,
			"error_code": "SWAP_REQUIRES_FULL_STACK",
			"details": {
				"requested_quantity": amount,
				"source_quantity": source_quantity,
			},
		}
	var target_access := _accessible_item(player_id, target_item_id)
	if not bool(target_access.get("success", false)):
		return target_access
	if _is_hotbar_assigned(player_id, item_id) or _is_hotbar_assigned(player_id, target_item_id):
		return _failure("SWAP_HOTBAR_UNSUPPORTED")
	var source_location: Dictionary = Dictionary(source.get("location", {})).duplicate(true)
	var target_location: Dictionary = Dictionary(target.get("location", {})).duplicate(true)
	if not _is_swap_location_accessible(player_id, source_location):
		return _failure("SWAP_SOURCE_NOT_SLOT_BACKED")
	if not _is_swap_location_accessible(player_id, target_location):
		return _failure("SWAP_TARGET_NOT_SLOT_BACKED")
	if int(source_location.get("slot_index", -1)) < 0:
		return _failure("SWAP_SOURCE_SLOT_REQUIRED")
	if not _location_matches_target(
		player_id,
		target_location,
		target_container_id,
		target_slot_index
	):
		return {
			"success": false,
			"error_code": "SWAP_TARGET_MISMATCH",
			"details": {
				"target_item_id": target_item_id,
				"target_container_id": target_container_id,
				"target_slot_index": target_slot_index,
			},
		}
	var source_container_id := _location_container_id(source_location)
	var target_owner_id := _location_container_id(target_location)
	if source_container_id.is_empty() or target_owner_id.is_empty():
		return _failure("SWAP_LOCATION_INVALID")
	if source_container_id != target_owner_id:
		_remove_from_source(item_id, source_location)
		_remove_from_source(target_item_id, target_location)
		_add_to_location_membership(item_id, target_location)
		_add_to_location_membership(target_item_id, source_location)
	source["location"] = target_location.duplicate(true)
	target["location"] = source_location.duplicate(true)
	_items[item_id] = source
	_items[target_item_id] = target
	_normalize_location_owner(source_location)
	if target_owner_id != source_container_id:
		_normalize_location_owner(target_location)
	return _success({
		"item_id": item_id,
		"placed_item_id": item_id,
		"swapped": true,
		"moved_quantity": amount,
		"target_container_id": target_container_id,
		"target_slot_index": target_slot_index,
		"displaced_item_id": target_item_id,
		"displaced_quantity": int(target.get("quantity", 1)),
		"displaced_container_id": source_container_id,
		"displaced_slot_index": int(source_location.get("slot_index", -1)),
	})


func _is_swap_location_accessible(player_id: String, location: Dictionary) -> bool:
	match String(location.get("kind", "")):
		"INVENTORY":
			return String(location.get("player_id", "")) == player_id
		"CONTAINER":
			var container_id := String(location.get("container_id", ""))
			return (
				_containers.has(container_id)
				and String(_open_containers.get(player_id, "")) == container_id
			)
	return false


func _location_matches_target(
	player_id: String,
	location: Dictionary,
	target_container_id: String,
	target_slot_index: int
) -> bool:
	if int(location.get("slot_index", -1)) != target_slot_index:
		return false
	if target_container_id == "inventory/%s" % player_id:
		return (
			String(location.get("kind", "")) == "INVENTORY"
			and String(location.get("player_id", "")) == player_id
		)
	if target_container_id.begins_with("container/"):
		return (
			String(location.get("kind", "")) == "CONTAINER"
			and String(location.get("container_id", "")) == target_container_id
		)
	return false


func _location_container_id(location: Dictionary) -> String:
	match String(location.get("kind", "")):
		"INVENTORY":
			var owner_player_id := String(location.get("player_id", ""))
			return "inventory/%s" % owner_player_id if not owner_player_id.is_empty() else ""
		"CONTAINER":
			return String(location.get("container_id", ""))
	return ""


func _add_to_location_membership(item_id: String, location: Dictionary) -> void:
	match String(location.get("kind", "")):
		"INVENTORY":
			_add_to_inventory(String(location.get("player_id", "")), item_id)
		"CONTAINER":
			var container_id := String(location.get("container_id", ""))
			if not _containers.has(container_id):
				return
			var container: Dictionary = _containers[container_id]
			var slots: Array = Array(container.get("slots", [])).duplicate()
			if item_id not in slots:
				slots.append(item_id)
			container["slots"] = slots
			_containers[container_id] = container


func _normalize_location_owner(location: Dictionary) -> void:
	match String(location.get("kind", "")):
		"INVENTORY":
			_normalize_player_inventory_slots(String(location.get("player_id", "")))
		"CONTAINER":
			_normalize_container_slots(String(location.get("container_id", "")))


func _transfer_to_inventory_slot(player_id: String, item_id: String, amount: int, target_slot_index: int) -> Dictionary:
	ensure_player(player_id)
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
	return _success({"item_id": moved_item_id, "container_id": "inventory/%s" % player_id, "quantity": amount, "moved_quantity": amount, "target_slot_index": resolved_slot})


func _transfer_to_container_slot(player_id: String, item_id: String, amount: int, container_id: String, target_slot_index: int) -> Dictionary:
	if not _containers.has(container_id):
		return _failure("CONTAINER_NOT_FOUND")
	if String(_open_containers.get(player_id, "")) != container_id:
		return _failure("TARGET_CONTAINER_ACCESS_DENIED")
	var item: Dictionary = _items[item_id]
	var location: Dictionary = Dictionary(item.get("location", {})).duplicate(true)
	if String(location.get("kind", "")) == "MOUNT":
		return _failure("MOUNT_DETACH_REQUIRED")
	if String(location.get("kind", "")) == "CONTAINER":
		var source_container_id := String(location.get("container_id", ""))
		if String(_open_containers.get(player_id, "")) != source_container_id:
			return _failure("SOURCE_CONTAINER_ACCESS_DENIED")
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

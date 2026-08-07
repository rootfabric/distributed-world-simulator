extends "res://scripts/network/prediction/predicted_item_interaction_journal.gd"

# Slot-aware NX6 projection. The base journal only checked the broad location
# kind for transfer confirmation, so a same-inventory reorder was considered
# satisfied before the requested slot changed and a partial split could be
# replayed on top of the already-authoritative split.

const PLAYER_INVENTORY_CAPACITY := 18


func _assign_target_location(
	snapshot: Dictionary,
	item_id: String,
	item: Dictionary,
	target_container_id: String,
	target_slot_index: int
) -> Dictionary:
	if target_container_id == "inventory/%s" % _local_player_id:
		var resolved_slot := target_slot_index
		if resolved_slot < 0:
			resolved_slot = _first_free_inventory_slot(snapshot, item_id)
		if resolved_slot < 0 or resolved_slot >= PLAYER_INVENTORY_CAPACITY:
			return _failure("CONTAINER_FULL")
		var occupant := _inventory_slot_occupant(snapshot, resolved_slot, item_id)
		if not occupant.is_empty():
			return _failure("TARGET_SLOT_OCCUPIED")
		item["location"] = {
			"kind": "INVENTORY",
			"player_id": _local_player_id,
			"slot_index": resolved_slot,
		}
		_add_to_player_inventory(snapshot, item_id)
		var inventory := _player_inventory(snapshot)
		var hotbar: Array = Array(inventory.get("hotbar", [])).duplicate()
		for index in range(hotbar.size()):
			if String(hotbar[index]) == item_id:
				hotbar[index] = ""
		inventory["hotbar"] = hotbar
		_set_player_inventory(snapshot, inventory)
		return _success({"item": item})

	if target_container_id == "hotbar/%s" % _local_player_id:
		return super._assign_target_location(
			snapshot,
			item_id,
			item,
			target_container_id,
			target_slot_index
		)

	var container_index := _container_index(snapshot, target_container_id)
	if container_index < 0:
		return _failure("CONTAINER_NOT_FOUND")
	var containers: Array = Array(snapshot.get("containers", [])).duplicate(true)
	var container: Dictionary = Dictionary(containers[container_index]).duplicate(true)
	var capacity := int(container.get("capacity", 0))
	var resolved_slot := target_slot_index
	if resolved_slot < 0:
		resolved_slot = _first_free_container_slot(snapshot, target_container_id, item_id)
	if resolved_slot < 0 or resolved_slot >= capacity:
		return _failure("CONTAINER_FULL")
	var occupant := _container_slot_occupant(snapshot, target_container_id, resolved_slot, item_id)
	if not occupant.is_empty():
		return _failure("TARGET_SLOT_OCCUPIED")
	var slots: Array = Array(container.get("slots", [])).duplicate()
	if item_id not in slots:
		slots.append(item_id)
	container["slots"] = slots
	containers[container_index] = container
	snapshot["containers"] = containers
	item["location"] = {
		"kind": "CONTAINER",
		"container_id": target_container_id,
		"slot_index": resolved_slot,
	}
	return _success({"item": item})


func _prediction_satisfied(snapshot: Dictionary, entry: Dictionary) -> bool:
	if String(entry.get("command_type", "")) != "item.transfer":
		return super._prediction_satisfied(snapshot, entry)

	var payload: Dictionary = Dictionary(entry.get("payload", {}))
	var source_id := String(payload.get("item_id", ""))
	var target_item_id := String(payload.get("target_item_id", ""))
	if not target_item_id.is_empty():
		var before_target := int(Dictionary(entry.get("precondition", {})).get("target_quantity", -1))
		return int(_item(snapshot, target_item_id).get("quantity", 0)) > before_target

	var precondition: Dictionary = Dictionary(entry.get("precondition", {}))
	var source_before := int(precondition.get("source_quantity", 0))
	var requested := int(payload.get("quantity", -1))
	var amount := source_before if requested < 0 else requested
	if amount < 1 or source_before < amount:
		return false
	var target_container_id := String(payload.get("target_container_id", ""))
	var target_slot_index := int(payload.get("target_slot_index", -1))
	var source := _item(snapshot, source_id)

	if amount == source_before:
		return (
			not source.is_empty()
			and _location_matches_transfer_target(
				snapshot,
				source_id,
				Dictionary(source.get("location", {})),
				target_container_id,
				target_slot_index
			)
		)

	if source.is_empty() or int(source.get("quantity", 0)) != source_before - amount:
		return false
	var source_definition_id := String(precondition.get("source_definition_id", ""))
	var authoritative_child_prefix := "%s/transfer/" % source_id
	for item_value in snapshot.get("items", []):
		if not item_value is Dictionary:
			continue
		var candidate: Dictionary = item_value
		var candidate_id := String(candidate.get("item_id", ""))
		if (
			candidate_id.is_empty()
			or candidate_id == source_id
			or not candidate_id.begins_with(authoritative_child_prefix)
		):
			continue
		if String(candidate.get("definition_id", "")) != source_definition_id:
			continue
		if int(candidate.get("quantity", 0)) != amount:
			continue
		if _location_matches_transfer_target(
			snapshot,
			candidate_id,
			Dictionary(candidate.get("location", {})),
			target_container_id,
			target_slot_index
		):
			return true
	return false


func _capture_precondition(command_type: String, payload: Dictionary) -> Dictionary:
	var result: Dictionary = super._capture_precondition(command_type, payload)
	if command_type != "item.transfer":
		return result
	var source := _item(_authoritative_snapshot, String(payload.get("item_id", "")))
	result["source_definition_id"] = String(source.get("definition_id", ""))
	result["source_location"] = Dictionary(source.get("location", {})).duplicate(true)
	return result


func _location_matches_transfer_target(
	snapshot: Dictionary,
	item_id: String,
	location: Dictionary,
	target_container_id: String,
	target_slot_index: int
) -> bool:
	if target_container_id == "inventory/%s" % _local_player_id:
		if (
			String(location.get("kind", "")) != "INVENTORY"
			or String(location.get("player_id", "")) != _local_player_id
		):
			return false
		var hotbar: Array = Array(_player_inventory(snapshot).get("hotbar", []))
		if item_id in hotbar:
			return false
		return target_slot_index < 0 or int(location.get("slot_index", -1)) == target_slot_index

	if target_container_id == "hotbar/%s" % _local_player_id:
		if (
			String(location.get("kind", "")) != "INVENTORY"
			or String(location.get("player_id", "")) != _local_player_id
		):
			return false
		var hotbar: Array = Array(_player_inventory(snapshot).get("hotbar", []))
		if target_slot_index >= 0:
			return (
				target_slot_index < hotbar.size()
				and String(hotbar[target_slot_index]) == item_id
			)
		return item_id in hotbar

	return (
		String(location.get("kind", "")) == "CONTAINER"
		and String(location.get("container_id", "")) == target_container_id
		and (
			target_slot_index < 0
			or int(location.get("slot_index", -1)) == target_slot_index
		)
	)


func _inventory_slot_occupant(
	snapshot: Dictionary,
	slot_index: int,
	exclude_item_id: String = ""
) -> String:
	var inventory := _player_inventory(snapshot)
	var membership: Array = Array(inventory.get("inventory", []))
	var hotbar: Array = Array(inventory.get("hotbar", []))
	for item_id_value in membership:
		var item_id := String(item_id_value)
		if item_id == exclude_item_id or item_id in hotbar:
			continue
		var item := _item(snapshot, item_id)
		var location: Dictionary = Dictionary(item.get("location", {}))
		if (
			String(location.get("kind", "")) == "INVENTORY"
			and String(location.get("player_id", "")) == _local_player_id
			and int(location.get("slot_index", -1)) == slot_index
		):
			return item_id
	return ""


func _container_slot_occupant(
	snapshot: Dictionary,
	container_id: String,
	slot_index: int,
	exclude_item_id: String = ""
) -> String:
	var container_index := _container_index(snapshot, container_id)
	if container_index < 0:
		return ""
	var container: Dictionary = Dictionary(Array(snapshot.get("containers", []))[container_index])
	for item_id_value in container.get("slots", []):
		var item_id := String(item_id_value)
		if item_id == exclude_item_id:
			continue
		var item := _item(snapshot, item_id)
		var location: Dictionary = Dictionary(item.get("location", {}))
		if (
			String(location.get("kind", "")) == "CONTAINER"
			and String(location.get("container_id", "")) == container_id
			and int(location.get("slot_index", -1)) == slot_index
		):
			return item_id
	return ""


func _first_free_inventory_slot(snapshot: Dictionary, exclude_item_id: String = "") -> int:
	for slot_index in range(PLAYER_INVENTORY_CAPACITY):
		if _inventory_slot_occupant(snapshot, slot_index, exclude_item_id).is_empty():
			return slot_index
	return -1


func _first_free_container_slot(
	snapshot: Dictionary,
	container_id: String,
	exclude_item_id: String = ""
) -> int:
	var container_index := _container_index(snapshot, container_id)
	if container_index < 0:
		return -1
	var container: Dictionary = Dictionary(Array(snapshot.get("containers", []))[container_index])
	var capacity := int(container.get("capacity", 0))
	for slot_index in range(capacity):
		if _container_slot_occupant(snapshot, container_id, slot_index, exclude_item_id).is_empty():
			return slot_index
	return -1

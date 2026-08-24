extends "res://scripts/runtime/networked_gameplay/m5/m4_item_graph_ui_projection.gd"

# P1 projection adapter: canonical location.slot_index is presentation truth.
# Compact membership arrays remain transport/durable compatibility data only.


func _build_inventory_container(
	player_id: String,
	inventory_record: Dictionary,
	transient_overlay: Dictionary
) -> Dictionary:
	var membership: Array = Array(inventory_record.get("inventory", [])).duplicate()
	var hotbar_items: Dictionary = {}
	for item_id_value in Array(inventory_record.get("hotbar", [])):
		var hotbar_item_id := String(item_id_value)
		if not hotbar_item_id.is_empty():
			hotbar_items[hotbar_item_id] = true
	var visible_membership: Array = []
	for item_id_value in membership:
		var item_id := String(item_id_value)
		if not hotbar_items.has(item_id):
			visible_membership.append(item_id)
	var capacity := maxi(PLAYER_CAPACITY, visible_membership.size())
	var ids := _slot_ids_for_membership(
		visible_membership,
		capacity,
		"INVENTORY",
		"player_id",
		player_id
	)
	return _build_slot_container(
		"inventory/%s" % player_id,
		"Рюкзак",
		ids,
		capacity,
		-1,
		transient_overlay,
		"player"
	)


func _build_external_container(container_id: String, transient_overlay: Dictionary) -> Dictionary:
	var record := _container_by_id(container_id)
	if record.is_empty():
		return {}
	var membership: Array = Array(record.get("slots", [])).duplicate()
	var capacity := maxi(1, int(record.get("capacity", membership.size())))
	var ids := _slot_ids_for_membership(
		membership,
		capacity,
		"CONTAINER",
		"container_id",
		container_id
	)
	return _build_slot_container(
		container_id,
		"Внешний контейнер",
		ids,
		capacity,
		-1,
		transient_overlay,
		"external"
	)


func _slot_ids_for_membership(
	membership: Array,
	capacity: int,
	expected_kind: String,
	owner_field: String,
	owner_id: String
) -> Array:
	var slots: Array = []
	for _index in range(capacity):
		slots.append("")
	var unresolved: Array[String] = []
	for item_id_value in membership:
		var item_id := String(item_id_value)
		if item_id.is_empty():
			continue
		var item := _item_by_id(item_id)
		var location: Dictionary = Dictionary(item.get("location", {}))
		var slot_index := int(location.get("slot_index", -1))
		if (
			String(location.get("kind", "")) == expected_kind
			and String(location.get(owner_field, "")) == owner_id
			and slot_index >= 0
			and slot_index < capacity
			and String(slots[slot_index]).is_empty()
		):
			slots[slot_index] = item_id
		else:
			unresolved.append(item_id)
	for item_id in unresolved:
		for slot_index in range(capacity):
			if String(slots[slot_index]).is_empty():
				slots[slot_index] = item_id
				break
	return slots

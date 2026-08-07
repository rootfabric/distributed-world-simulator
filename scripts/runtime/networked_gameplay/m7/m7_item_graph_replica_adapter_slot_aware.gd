extends "res://scripts/runtime/networked_gameplay/m7/m7_item_graph_replica_adapter.gd"

# Canonical M7 keeps compact inventory membership for durable compatibility,
# but slot identity is carried by item.location.slot_index. Prefer that stable
# authority value over the item's position in the compact membership array.

func _relation_for_item(
	row: Dictionary,
	location: Dictionary,
	inventory_map: Dictionary,
	mount_map: Dictionary
) -> Dictionary:
	if String(location.get("kind", "")) != "INVENTORY":
		return super._relation_for_item(row, location, inventory_map, mount_map)

	var item_id := String(row.get("item_id", ""))
	var player_id := String(location.get("player_id", ""))
	if player_id != _local_player_id:
		return _success({"relation": Relations.container(_remote_inventory_id(player_id))})

	var inventory: Dictionary = Dictionary(inventory_map.get(player_id, {}))
	var hotbar: Array = Array(inventory.get("hotbar", []))
	var hotbar_index := hotbar.find(item_id)
	if hotbar_index >= 0:
		return _success({"relation": Relations.container(LOCAL_HOTBAR_ID, hotbar_index)})

	var inventory_slot := int(location.get("slot_index", -1))
	if inventory_slot < 0 or inventory_slot >= INVENTORY_SIZE:
		var inventory_items: Array = Array(inventory.get("inventory", []))
		inventory_slot = inventory_items.find(item_id)
	if inventory_slot < 0:
		inventory_slot = 0
	return _success({
		"relation": Relations.container(
			LOCAL_INVENTORY_ID,
			mini(inventory_slot, INVENTORY_SIZE - 1)
		)
	})

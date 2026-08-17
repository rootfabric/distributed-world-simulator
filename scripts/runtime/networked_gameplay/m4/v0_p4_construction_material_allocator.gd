extends RefCounted

const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")

const R1_DEFINITION_ID := "item/ore"


static func allocate_r1(
	item_graph,
	logical_player_id: String,
	required_quantity: int
) -> Dictionary:
	if item_graph == null or not item_graph.has_method("create_snapshot") or not item_graph.has_method("validate_snapshot"):
		return _failure("CONSTRUCTION_MATERIAL_ITEM_GRAPH_REQUIRED")
	var player_id := logical_player_id.strip_edges().to_lower()
	if player_id.is_empty():
		return _failure("CONSTRUCTION_MATERIAL_PLAYER_REQUIRED")
	if required_quantity < 1:
		return _failure("CONSTRUCTION_MATERIAL_REQUIREMENT_INVALID", {"required_quantity": required_quantity})
	var snapshot_value = item_graph.create_snapshot()
	if not snapshot_value is Dictionary:
		return _failure("CONSTRUCTION_MATERIAL_ITEM_GRAPH_SNAPSHOT_REQUIRED")
	var snapshot: Dictionary = snapshot_value
	var validation_value = item_graph.validate_snapshot(snapshot)
	if not validation_value is Dictionary or not bool(Dictionary(validation_value).get("success", false)):
		return _failure("CONSTRUCTION_MATERIAL_ITEM_GRAPH_SNAPSHOT_INVALID")
	return allocate_r1_from_snapshot(snapshot, player_id, required_quantity)


static func allocate_r1_from_snapshot(
	snapshot: Dictionary,
	logical_player_id: String,
	required_quantity: int
) -> Dictionary:
	var player_id := logical_player_id.strip_edges().to_lower()
	if player_id.is_empty():
		return _failure("CONSTRUCTION_MATERIAL_PLAYER_REQUIRED")
	if required_quantity < 1:
		return _failure("CONSTRUCTION_MATERIAL_REQUIREMENT_INVALID", {"required_quantity": required_quantity})
	if typeof(snapshot.get("items")) != TYPE_ARRAY or typeof(snapshot.get("inventories")) != TYPE_DICTIONARY:
		return _failure("CONSTRUCTION_MATERIAL_ITEM_GRAPH_SNAPSHOT_INVALID")
	var inventories: Dictionary = snapshot["inventories"]
	if not inventories.has(player_id) or not inventories[player_id] is Dictionary:
		return _failure("CONSTRUCTION_MATERIAL_PLAYER_INVENTORY_NOT_FOUND", {
			"logical_player_id": player_id,
		})
	var inventory: Dictionary = inventories[player_id]
	if typeof(inventory.get("inventory")) != TYPE_ARRAY:
		return _failure("CONSTRUCTION_MATERIAL_PLAYER_INVENTORY_INVALID", {
			"logical_player_id": player_id,
		})

	var item_rows: Dictionary = {}
	for item_value in snapshot["items"]:
		if not item_value is Dictionary:
			return _failure("CONSTRUCTION_MATERIAL_ITEM_ROW_INVALID")
		var item: Dictionary = item_value
		var item_id := String(item.get("item_id", ""))
		if item_id.is_empty() or item_rows.has(item_id):
			return _failure("CONSTRUCTION_MATERIAL_ITEM_ID_INVALID", {"item_id": item_id})
		item_rows[item_id] = item

	var membership_seen: Dictionary = {}
	var candidates: Array = []
	for item_id_value in inventory["inventory"]:
		var item_id := String(item_id_value)
		if item_id.is_empty() or membership_seen.has(item_id):
			return _failure("CONSTRUCTION_MATERIAL_INVENTORY_MEMBERSHIP_INVALID", {
				"logical_player_id": player_id,
				"item_id": item_id,
			})
		membership_seen[item_id] = true
		if not item_rows.has(item_id):
			return _failure("CONSTRUCTION_MATERIAL_INVENTORY_ITEM_MISSING", {
				"logical_player_id": player_id,
				"item_id": item_id,
			})
		var item: Dictionary = item_rows[item_id]
		if String(item.get("definition_id", "")).strip_edges().to_lower() != R1_DEFINITION_ID:
			continue
		var location_value = item.get("location", {})
		if not location_value is Dictionary:
			return _failure("CONSTRUCTION_MATERIAL_INVENTORY_OWNERSHIP_INVALID", {"item_id": item_id})
		var location: Dictionary = location_value
		if String(location.get("kind", "")) != "INVENTORY" or String(location.get("player_id", "")).strip_edges().to_lower() != player_id:
			return _failure("CONSTRUCTION_MATERIAL_INVENTORY_OWNERSHIP_INVALID", {"item_id": item_id})
		var slot_index := int(location.get("slot_index", -1))
		# Hotbar-assigned items intentionally have no inventory slot identity and
		# are not spendable by the first P4 recipe.
		if slot_index < 0:
			continue
		var quantity := int(item.get("quantity", 0))
		if quantity < 1:
			return _failure("CONSTRUCTION_MATERIAL_ITEM_QUANTITY_INVALID", {"item_id": item_id})
		candidates.append({
			"item_id": item_id,
			"definition_id": R1_DEFINITION_ID,
			"slot_index": slot_index,
			"available_quantity": quantity,
		})

	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_slot := int(left.get("slot_index", -1))
		var right_slot := int(right.get("slot_index", -1))
		if left_slot != right_slot:
			return left_slot < right_slot
		return String(left.get("item_id", "")) < String(right.get("item_id", ""))
	)

	var available_quantity := 0
	for candidate in candidates:
		available_quantity += int(candidate.get("available_quantity", 0))
	if available_quantity < required_quantity:
		return _failure("CONSTRUCTION_MATERIAL_INSUFFICIENT", {
			"logical_player_id": player_id,
			"definition_id": R1_DEFINITION_ID,
			"required_quantity": required_quantity,
			"available_quantity": available_quantity,
			"snapshot_revision": int(snapshot.get("revision", -1)),
			"snapshot_tick": int(snapshot.get("tick", -1)),
			"snapshot_checksum": String(snapshot.get("checksum", "")),
		})

	var allocations: Array = []
	var remaining := required_quantity
	for candidate in candidates:
		if remaining == 0:
			break
		var take := mini(remaining, int(candidate.get("available_quantity", 0)))
		if take <= 0:
			continue
		allocations.append({
			"item_id": String(candidate.get("item_id", "")),
			"definition_id": R1_DEFINITION_ID,
			"quantity": take,
			"slot_index": int(candidate.get("slot_index", -1)),
			"available_quantity": int(candidate.get("available_quantity", 0)),
		})
		remaining -= take

	var allocation_identity := {
		"logical_player_id": player_id,
		"definition_id": R1_DEFINITION_ID,
		"required_quantity": required_quantity,
		"snapshot_revision": int(snapshot.get("revision", -1)),
		"snapshot_tick": int(snapshot.get("tick", -1)),
		"snapshot_checksum": String(snapshot.get("checksum", "")),
		"allocations": allocations,
	}
	return _success({
		"logical_player_id": player_id,
		"definition_id": R1_DEFINITION_ID,
		"required_quantity": required_quantity,
		"allocated_quantity": required_quantity - remaining,
		"available_quantity": available_quantity,
		"candidate_stack_count": candidates.size(),
		"selected_stack_count": allocations.size(),
		"allocations": allocations,
		"snapshot_revision": int(snapshot.get("revision", -1)),
		"snapshot_tick": int(snapshot.get("tick", -1)),
		"snapshot_checksum": String(snapshot.get("checksum", "")),
		"allocation_checksum": NetworkUtils.payload_hash(allocation_identity),
	})


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}

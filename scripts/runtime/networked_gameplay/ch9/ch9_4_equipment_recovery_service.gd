class_name Ch9EquipmentRecoveryService
extends "res://scripts/runtime/networked_gameplay/ch9/ch9_3_networked_gameplay_service.gd"

const EquipmentItemGraph = preload("res://scripts/runtime/networked_gameplay/ch9/ch9_3_equipment_item_graph_service.gd")
const EquipmentCatalog = preload("res://scripts/characters/equipment/network_character_equipment_catalog.gd")

const RESULT_EQUIPMENT_DURABLE_STATE_INVALID := "CH9_4_EQUIPMENT_DURABLE_STATE_INVALID"
const RESULT_EQUIPMENT_GRAPH_REHYDRATE_FAILED := "CH9_4_EQUIPMENT_GRAPH_REHYDRATE_FAILED"


func validate_durable_state(value: Dictionary) -> Dictionary:
	var base_validation: Dictionary = super.validate_durable_state(value)
	if not bool(base_validation.get("success", false)):
		return base_validation
	var item_state_value = value.get("canonical_item_graph", {})
	if not item_state_value is Dictionary:
		return _failure(RESULT_EQUIPMENT_DURABLE_STATE_INVALID)
	var snapshot_value = Dictionary(item_state_value).get("snapshot", {})
	if not snapshot_value is Dictionary:
		return _failure(RESULT_EQUIPMENT_DURABLE_STATE_INVALID)
	return _validate_equipment_snapshot(Dictionary(snapshot_value))


func restore_durable_state(value: Dictionary) -> Dictionary:
	var equipment_validation: Dictionary = validate_durable_state(value)
	if not bool(equipment_validation.get("success", false)):
		return equipment_validation

	# Reuse the accepted base restore for players, ownership, shared items,
	# revisions and all transactionality. It restores a generic canonical Item
	# Graph; CH9.4 then replaces only that staged graph with the equipment-aware
	# subclass restored from the exact same durable bytes.
	var restored: Dictionary = super.restore_durable_state(value)
	if not bool(restored.get("success", false)):
		return restored

	var durable_item_state: Dictionary = Dictionary(value.get("canonical_item_graph", {}))
	var durable_snapshot: Dictionary = Dictionary(durable_item_state.get("snapshot", {}))
	var equipment_graph = EquipmentItemGraph.new()
	var setup_result: Dictionary = equipment_graph.setup(
		String(value.get("authority_owner_id", "")),
		int(value.get("authority_epoch", 0)),
		{"playable_sandbox": bool(durable_snapshot.get("playable_sandbox", false))}
	)
	if not bool(setup_result.get("success", false)):
		return _failure(RESULT_EQUIPMENT_GRAPH_REHYDRATE_FAILED, {"cause": setup_result})
	var graph_restore: Dictionary = equipment_graph.restore_durable_state(durable_item_state)
	if not bool(graph_restore.get("success", false)):
		return _failure(RESULT_EQUIPMENT_GRAPH_REHYDRATE_FAILED, {"cause": graph_restore})
	var restored_snapshot: Dictionary = equipment_graph.create_snapshot()
	var restored_validation: Dictionary = _validate_equipment_snapshot(restored_snapshot)
	if not bool(restored_validation.get("success", false)):
		return restored_validation
	if String(restored_snapshot.get("checksum", "")) != String(durable_snapshot.get("checksum", "")):
		return _failure(RESULT_EQUIPMENT_GRAPH_REHYDRATE_FAILED, {
			"cause": "CHECKSUM_MISMATCH",
			"expected": String(durable_snapshot.get("checksum", "")),
			"actual": String(restored_snapshot.get("checksum", "")),
		})

	_canonical_multiplayer_items = equipment_graph
	var details: Dictionary = Dictionary(restored.get("details", {})).duplicate(true)
	details["character_equipment_recovered"] = true
	details["equipment_container_count"] = int(restored_validation.get("details", {}).get("equipment_container_count", 0))
	details["equipped_item_count"] = int(restored_validation.get("details", {}).get("equipped_item_count", 0))
	restored["details"] = details
	return restored


func _validate_equipment_snapshot(snapshot: Dictionary) -> Dictionary:
	var items_by_id: Dictionary = {}
	for value in snapshot.get("items", []):
		if value is Dictionary:
			items_by_id[String(value.get("item_id", ""))] = Dictionary(value)

	var equipment_container_count := 0
	var equipped_item_count := 0
	for value in snapshot.get("containers", []):
		if not value is Dictionary:
			continue
		var container: Dictionary = value
		if String(container.get("container_kind", "")) != EquipmentCatalog.EQUIPMENT_CONTAINER_KIND:
			continue
		equipment_container_count += 1
		var player_id := String(container.get("owner_player_id", "")).strip_edges().to_lower()
		var container_id := String(container.get("container_id", ""))
		if player_id.is_empty() \
			or container_id != EquipmentCatalog.equipment_container_id(player_id) \
			or String(container.get("owner_entity_id", "")) != EquipmentCatalog.owner_entity_id(player_id) \
			or int(container.get("capacity", -1)) != EquipmentCatalog.EQUIPMENT_SLOT_COUNT:
			return _failure(RESULT_EQUIPMENT_DURABLE_STATE_INVALID, {"container_id": container_id, "reason": "IDENTITY_OR_CAPACITY"})
		var slot_map_value = container.get("equipment_slots", {})
		if not slot_map_value is Dictionary:
			return _failure(RESULT_EQUIPMENT_DURABLE_STATE_INVALID, {"container_id": container_id, "reason": "SLOT_MAP_REQUIRED"})
		var slot_map: Dictionary = slot_map_value
		var expected_references: Array = []
		var seen: Dictionary = {}
		for slot_index in range(EquipmentCatalog.EQUIPMENT_SLOT_COUNT):
			var item_id := String(slot_map.get(str(slot_index), ""))
			if item_id.is_empty():
				continue
			if seen.has(item_id) or not items_by_id.has(item_id):
				return _failure(RESULT_EQUIPMENT_DURABLE_STATE_INVALID, {"container_id": container_id, "item_id": item_id, "reason": "MISSING_OR_DUPLICATE_ITEM"})
			seen[item_id] = true
			var item: Dictionary = items_by_id[item_id]
			var location: Dictionary = Dictionary(item.get("location", {}))
			if String(location.get("kind", "")) != "CONTAINER" \
				or String(location.get("container_id", "")) != container_id \
				or int(location.get("slot_index", -1)) != slot_index \
				or int(item.get("quantity", 0)) != 1 \
				or String(item.get("definition_id", "")) != EquipmentCatalog.canonical_definition_for_slot(slot_index):
				return _failure(RESULT_EQUIPMENT_DURABLE_STATE_INVALID, {"container_id": container_id, "item_id": item_id, "slot_index": slot_index, "reason": "ITEM_SLOT_MISMATCH"})
			expected_references.append(item_id)
			equipped_item_count += 1
		var references: Array = Array(container.get("slots", []))
		if references != expected_references:
			return _failure(RESULT_EQUIPMENT_DURABLE_STATE_INVALID, {"container_id": container_id, "reason": "REFERENCE_ORDER_MISMATCH"})

	# No item may claim an equipment container without being present in its
	# semantic slot map. Generic containers remain owned by the base validator.
	for item_id_value in items_by_id.keys():
		var item_id := String(item_id_value)
		var item: Dictionary = items_by_id[item_id]
		var location: Dictionary = Dictionary(item.get("location", {}))
		if String(location.get("kind", "")) != "CONTAINER":
			continue
		var container_id := String(location.get("container_id", ""))
		if not container_id.begins_with("equipment/"):
			continue
		var found := false
		for container_value in snapshot.get("containers", []):
			if not container_value is Dictionary:
				continue
			var container: Dictionary = container_value
			if String(container.get("container_id", "")) != container_id:
				continue
			var slot_map: Dictionary = Dictionary(container.get("equipment_slots", {}))
			found = String(slot_map.get(str(int(location.get("slot_index", -1))), "")) == item_id
			break
		if not found:
			return _failure(RESULT_EQUIPMENT_DURABLE_STATE_INVALID, {"container_id": container_id, "item_id": item_id, "reason": "ORPHAN_EQUIPMENT_RELATION"})

	return _success({
		"equipment_container_count": equipment_container_count,
		"equipped_item_count": equipped_item_count,
	})

class_name InventorySlotModeAdapter
extends RefCounted

const ContainerState = preload("res://scripts/containers/container_state.gd")
const Relations = preload("res://scripts/items/domain/item_relations.gd")

const SCHEMA: String = "planet_simulator.inventory_slot_mode_adapter.v1"

var gameplay_controller


func setup(controller) -> void:
	gameplay_controller = controller


func ensure_container_slots(container_id: String, preferred_layout: Array = []) -> Dictionary:
	if gameplay_controller == null:
		return _fail("CONTROLLER_NOT_READY")
	if container_id.is_empty():
		return _fail("CONTAINER_ID_REQUIRED")
	var container = gameplay_controller.get_container(container_id)
	if container == null:
		return _fail("CONTAINER_NOT_FOUND", {"container_id": container_id})
	if container.is_slot_container():
		return {
			"success": true,
			"no_change": true,
			"container_id": container_id,
			"slot_count": int(container.slot_count),
		}
	if String(container.storage_mode) != ContainerState.STORAGE_BULK:
		return _fail("CONTAINER_STORAGE_MODE_UNSUPPORTED", {
			"container_id": container_id,
			"storage_mode": String(container.storage_mode),
		})

	var container_snapshot: Dictionary = container.to_dict()
	var item_snapshots: Dictionary = {}
	for item_id_value in container.item_ids:
		var item_id := String(item_id_value)
		var item = gameplay_controller.get_item(item_id)
		if item == null:
			return _fail("CONTAINER_MEMBER_NOT_FOUND", {
				"container_id": container_id,
				"item_id": item_id,
			})
		item_snapshots[item_id] = {
			"relation": item.relation.duplicate(true),
			"revision": int(item.revision),
		}

	var ordered_item_ids := _ordered_item_ids(container.item_ids, preferred_layout)
	var resolved_slot_count := maxi(1, maxi(int(container.slot_count), ordered_item_ids.size()))
	var next_rules: Array = container.slot_rules.duplicate(true)
	while next_rules.size() < resolved_slot_count:
		next_rules.append({"accepted_tags": []})
	if next_rules.size() > resolved_slot_count:
		next_rules.resize(resolved_slot_count)

	container.storage_mode = ContainerState.STORAGE_SLOTS
	container.slot_count = resolved_slot_count
	container.slot_rules = next_rules
	container.slot_assignments.clear()
	for slot_index in range(ordered_item_ids.size()):
		var item_id := String(ordered_item_ids[slot_index])
		container.slot_assignments[slot_index] = item_id
		var item = gameplay_controller.get_item(item_id)
		item.set_relation(Relations.container(container_id, slot_index))
		item.revision += 1
	container.revision += 1

	var graph_validation: Dictionary = gameplay_controller.domain.validator.validate_graph()
	if not bool(graph_validation.get("success", false)):
		_restore(container_id, container_snapshot, item_snapshots)
		return _fail("SLOT_MIGRATION_GRAPH_INVALID", {"cause": graph_validation})
	var save_result: Dictionary = gameplay_controller.save_graph()
	if not bool(save_result.get("success", false)) or bool(save_result.get("skipped", false)):
		_restore(container_id, container_snapshot, item_snapshots)
		return _fail("SLOT_MIGRATION_SAVE_FAILED", {"cause": save_result})
	return {
		"success": true,
		"migrated": true,
		"container_id": container_id,
		"slot_count": resolved_slot_count,
		"item_count": ordered_item_ids.size(),
		"schema": SCHEMA,
	}


func _ordered_item_ids(item_ids: Array[String], preferred_layout: Array) -> Array[String]:
	var result: Array[String] = []
	for item_id_value in preferred_layout:
		var item_id := String(item_id_value)
		if not item_id.is_empty() and item_ids.has(item_id) and not result.has(item_id):
			result.append(item_id)
	for item_id_value in item_ids:
		var item_id := String(item_id_value)
		if not item_id.is_empty() and not result.has(item_id):
			result.append(item_id)
	return result


func _restore(container_id: String, container_snapshot: Dictionary, item_snapshots: Dictionary) -> void:
	var restored_container := ContainerState.new(container_snapshot)
	gameplay_controller.domain.containers.containers[container_id] = restored_container
	for item_id_value in item_snapshots:
		var item_id := String(item_id_value)
		var item = gameplay_controller.get_item(item_id)
		if item == null:
			continue
		var snapshot := Dictionary(item_snapshots[item_id_value])
		item.set_relation(Dictionary(snapshot.get("relation", {})).duplicate(true))
		item.revision = int(snapshot.get("revision", int(item.revision)))


func _fail(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"details": details.duplicate(true),
	}

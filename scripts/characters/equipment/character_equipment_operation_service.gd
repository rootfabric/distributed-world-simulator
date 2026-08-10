class_name CharacterEquipmentOperationService
extends RefCounted

const ItemRelations = preload("res://scripts/items/domain/item_relations.gd")

const RESULT_OK := "OK"
const RESULT_INVALID_SETUP := "INVALID_SETUP"
const RESULT_INVALID_OPERATION_ID := "INVALID_OPERATION_ID"
const RESULT_ITEM_NOT_FOUND := "ITEM_NOT_FOUND"
const RESULT_ITEM_NOT_IN_CONTAINER := "ITEM_NOT_IN_CONTAINER"
const RESULT_ITEM_ALREADY_EQUIPPED_OTHER_SLOT := "ITEM_ALREADY_EQUIPPED_OTHER_SLOT"
const RESULT_EQUIPMENT_SLOT_OCCUPIED := "EQUIPMENT_SLOT_OCCUPIED"
const RESULT_EQUIPMENT_REPLACEMENT_REQUIRED := "EQUIPMENT_REPLACEMENT_REQUIRED"
const RESULT_MULTI_ITEM_TRANSACTION_REQUIRED := "MULTI_ITEM_TRANSACTION_REQUIRED"
const RESULT_REPLACEMENT_TARGET_MISMATCH := "REPLACEMENT_TARGET_MISMATCH"
const RESULT_ITEM_NOT_EQUIPPED := "ITEM_NOT_EQUIPPED"
const RESULT_TARGET_CONTAINER_INVALID := "TARGET_CONTAINER_INVALID"
const RESULT_TRANSFER_REJECTED := "TRANSFER_REJECTED"
const RESULT_POST_COMMIT_PROJECTION_FAILED := "POST_COMMIT_PROJECTION_FAILED"

const MODE_MOVE := "MOVE"
const MODE_SWAP := "SWAP"
const MODE_NO_CHANGE := "NO_CHANGE"
const MODE_MULTI_ITEM_TRANSACTION_REQUIRED := "MULTI_ITEM_TRANSACTION_REQUIRED"

var owner_entity_id := ""
var equipment_container_id := ""
var equipment_source: ItemGraphEquipmentSource

var _item_registry
var _container_registry
var _transfer_service
var _last_result: Dictionary = {}


func setup(
	p_owner_entity_id: String,
	p_equipment_container_id: String,
	p_equipment_source: ItemGraphEquipmentSource,
	p_item_registry,
	p_container_registry,
	p_transfer_service
) -> Dictionary:
	owner_entity_id = p_owner_entity_id.strip_edges()
	equipment_container_id = p_equipment_container_id.strip_edges()
	equipment_source = p_equipment_source
	_item_registry = p_item_registry
	_container_registry = p_container_registry
	_transfer_service = p_transfer_service

	if owner_entity_id.is_empty() or equipment_container_id.is_empty():
		return _store(_result(false, RESULT_INVALID_SETUP, {"reason": "OWNER_OR_CONTAINER_ID_REQUIRED"}))
	if equipment_source == null:
		return _store(_result(false, RESULT_INVALID_SETUP, {"reason": "EQUIPMENT_SOURCE_REQUIRED"}))
	if not _valid_item_registry(_item_registry) or not _valid_container_registry(_container_registry):
		return _store(_result(false, RESULT_INVALID_SETUP, {"reason": "ITEM_GRAPH_PORT_INVALID"}))
	if not _valid_transfer_service(_transfer_service):
		return _store(_result(false, RESULT_INVALID_SETUP, {"reason": "ITEM_TRANSFER_SERVICE_INVALID"}))

	var report: Dictionary = equipment_source.create_report()
	if (
		String(report.get("owner_entity_id", "")) != owner_entity_id
		or String(report.get("equipment_container_id", "")) != equipment_container_id
	):
		return _store(_result(false, RESULT_INVALID_SETUP, {
			"reason": "EQUIPMENT_SOURCE_BINDING_MISMATCH",
			"source_owner_entity_id": String(report.get("owner_entity_id", "")),
			"source_equipment_container_id": String(report.get("equipment_container_id", "")),
		}))
	var refresh_result: Dictionary = equipment_source.refresh()
	if not bool(refresh_result.get("success", false)):
		return _store(_result(false, RESULT_INVALID_SETUP, {
			"reason": "EQUIPMENT_SOURCE_NOT_READY",
			"source_result": refresh_result,
		}))
	return _store(_result(true, RESULT_OK, {
		"owner_entity_id": owner_entity_id,
		"equipment_container_id": equipment_container_id,
		"mutation_owner": "ITEM_TRANSFER_SERVICE",
	}))


# Plans a desired equip without touching canonical state. The plan combines the
# physical equipment slot occupant with CH8 semantic channel conflicts. A move
# can execute directly. A one-item replacement can execute as ItemTransferService
# swap_items. Any conflict set that cannot be expressed by one existing atomic
# transfer primitive is rejected before mutation.
func plan_equip_from_container(item_id: String, slot_index: int) -> Dictionary:
	var refresh_result: Dictionary = equipment_source.refresh()
	if not bool(refresh_result.get("success", false)):
		return _store(refresh_result)

	var item = _item_registry.get_item(item_id)
	if item == null:
		return _store(_result(false, RESULT_ITEM_NOT_FOUND, {"item_id": item_id}))
	var relation: Dictionary = ItemRelations.canonicalize(item.relation)
	if ItemRelations.kind_of(relation) != ItemRelations.CONTAINER:
		return _store(_result(false, RESULT_ITEM_NOT_IN_CONTAINER, {
			"item_id": item_id,
			"relation": relation,
		}))

	var current_container_id := String(relation.get("container_id", ""))
	var current_slot_index := int(relation.get("slot_index", -1))
	if current_container_id == equipment_container_id:
		if current_slot_index == slot_index:
			return _store(_result(true, RESULT_OK, {
				"mode": MODE_NO_CHANGE,
				"item_id": item_id,
				"slot_index": slot_index,
				"replacement_item_ids": [],
			}))
		return _store(_result(false, RESULT_ITEM_ALREADY_EQUIPPED_OTHER_SLOT, {
			"item_id": item_id,
			"current_slot_index": current_slot_index,
			"requested_slot_index": slot_index,
		}))

	var equipment_container = _container_registry.get_container(equipment_container_id)
	if equipment_container == null or not bool(equipment_container.is_slot_container()):
		return _store(_result(false, RESULT_INVALID_SETUP, {"reason": "EQUIPMENT_CONTAINER_NOT_SLOTTED"}))
	var occupant_item_id := String(equipment_container.get_item_at_slot(slot_index))

	var semantic_plan: Dictionary = equipment_source.plan_candidate(item_id, slot_index)
	if not bool(semantic_plan.get("success", false)):
		return _store(semantic_plan)
	var replacement_set: Dictionary = {}
	for raw_conflict_id in Dictionary(semantic_plan.get("details", {})).get("conflicting_item_ids", []):
		var conflict_id := str(raw_conflict_id).strip_edges()
		if not conflict_id.is_empty():
			replacement_set[conflict_id] = true
	if not occupant_item_id.is_empty():
		replacement_set[occupant_item_id] = true
	var replacement_item_ids := _sorted_string_values(replacement_set.keys())

	if replacement_item_ids.is_empty():
		return _store(_result(true, RESULT_OK, {
			"mode": MODE_MOVE,
			"item_id": item_id,
			"slot_index": slot_index,
			"profile_id": equipment_source.slot_profile_id(slot_index),
			"source_relation": relation,
			"target_relation": ItemRelations.container(equipment_container_id, slot_index),
			"replacement_item_ids": [],
			"semantic_plan": semantic_plan,
		}))

	if replacement_item_ids.size() == 1 and not occupant_item_id.is_empty() and replacement_item_ids[0] == occupant_item_id:
		var resulting_plan: Dictionary = equipment_source.plan_candidate(item_id, slot_index, [occupant_item_id])
		if bool(resulting_plan.get("success", false)) and _conflicting_item_ids(resulting_plan).is_empty():
			return _store(_result(true, RESULT_OK, {
				"mode": MODE_SWAP,
				"item_id": item_id,
				"slot_index": slot_index,
				"profile_id": equipment_source.slot_profile_id(slot_index),
				"source_relation": relation,
				"target_relation": ItemRelations.container(equipment_container_id, slot_index),
				"replacement_item_ids": replacement_item_ids,
				"replacement_item_id": occupant_item_id,
				"semantic_plan": semantic_plan,
				"resulting_plan": resulting_plan,
			}))

	return _store(_result(true, RESULT_MULTI_ITEM_TRANSACTION_REQUIRED, {
		"mode": MODE_MULTI_ITEM_TRANSACTION_REQUIRED,
		"item_id": item_id,
		"slot_index": slot_index,
		"profile_id": equipment_source.slot_profile_id(slot_index),
		"physical_target_occupant_item_id": occupant_item_id,
		"replacement_item_ids": replacement_item_ids,
		"semantic_plan": semantic_plan,
		"mutation_performed": false,
	}))


func equip_strict(
	item_id: String,
	slot_index: int,
	operation_id: String,
	expected_item_revision: int = -1
) -> Dictionary:
	if operation_id.strip_edges().is_empty():
		return _store(_result(false, RESULT_INVALID_OPERATION_ID))
	var plan: Dictionary = plan_equip_from_container(item_id, slot_index)
	if not bool(plan.get("success", false)):
		return plan
	var details: Dictionary = Dictionary(plan.get("details", {}))
	var mode := String(details.get("mode", ""))
	if mode not in [MODE_MOVE, MODE_NO_CHANGE]:
		return _store(_result(false, RESULT_EQUIPMENT_REPLACEMENT_REQUIRED, details))

	var transfer_result: Dictionary = _transfer_service.move_item(
		item_id,
		ItemRelations.container(equipment_container_id, slot_index),
		operation_id,
		expected_item_revision
	)
	if not bool(transfer_result.get("success", false)):
		return _store(_transfer_failure(transfer_result, {
			"operation": "EQUIP_STRICT",
			"item_id": item_id,
			"slot_index": slot_index,
		}))
	return _store(_post_commit_result(
		"EQUIP_STRICT",
		item_id,
		slot_index,
		true,
		transfer_result,
		{"mode": mode}
	))


func replace_one_from_container(
	incoming_item_id: String,
	slot_index: int,
	replaced_item_id: String,
	operation_id: String,
	expected_incoming_revision: int = -1,
	expected_replaced_revision: int = -1
) -> Dictionary:
	if operation_id.strip_edges().is_empty():
		return _store(_result(false, RESULT_INVALID_OPERATION_ID))
	if replaced_item_id.strip_edges().is_empty():
		return _store(_result(false, RESULT_REPLACEMENT_TARGET_MISMATCH, {"reason": "REPLACED_ITEM_ID_REQUIRED"}))

	var incoming = _item_registry.get_item(incoming_item_id)
	var replaced = _item_registry.get_item(replaced_item_id)
	if incoming == null or replaced == null:
		return _store(_result(false, RESULT_ITEM_NOT_FOUND, {
			"incoming_item_id": incoming_item_id,
			"replaced_item_id": replaced_item_id,
		}))

	# Desired-state replay: after a successful swap the incoming item already
	# occupies the requested equipment slot and the old item is back in its
	# previous container. Do not swap them back on a retry with a new wrapper call.
	var incoming_relation: Dictionary = ItemRelations.canonicalize(incoming.relation)
	if (
		ItemRelations.kind_of(incoming_relation) == ItemRelations.CONTAINER
		and String(incoming_relation.get("container_id", "")) == equipment_container_id
		and int(incoming_relation.get("slot_index", -1)) == slot_index
	):
		var replay_refresh: Dictionary = equipment_source.refresh()
		if not bool(replay_refresh.get("success", false)):
			return _store(_result(false, RESULT_POST_COMMIT_PROJECTION_FAILED, {"source_result": replay_refresh}))
		return _store(_result(true, RESULT_OK, {
			"operation": "REPLACE_ONE",
			"mode": MODE_NO_CHANGE,
			"item_id": incoming_item_id,
			"slot_index": slot_index,
			"replaced_item_id": replaced_item_id,
			"no_change": true,
			"desired_state_already_reached": true,
		}))

	var plan: Dictionary = plan_equip_from_container(incoming_item_id, slot_index)
	if not bool(plan.get("success", false)):
		return plan
	var details: Dictionary = Dictionary(plan.get("details", {}))
	if String(details.get("mode", "")) == MODE_MULTI_ITEM_TRANSACTION_REQUIRED:
		return _store(_result(false, RESULT_MULTI_ITEM_TRANSACTION_REQUIRED, details))
	if String(details.get("mode", "")) != MODE_SWAP:
		return _store(_result(false, RESULT_REPLACEMENT_TARGET_MISMATCH, {
			"reason": "PLAN_IS_NOT_SINGLE_SWAP",
			"plan": plan,
		}))
	if String(details.get("replacement_item_id", "")) != replaced_item_id:
		return _store(_result(false, RESULT_REPLACEMENT_TARGET_MISMATCH, {
			"expected_replaced_item_id": String(details.get("replacement_item_id", "")),
			"requested_replaced_item_id": replaced_item_id,
			"plan": plan,
		}))

	var transfer_result: Dictionary = _transfer_service.swap_items(
		incoming_item_id,
		replaced_item_id,
		operation_id,
		expected_incoming_revision,
		expected_replaced_revision
	)
	if not bool(transfer_result.get("success", false)):
		return _store(_transfer_failure(transfer_result, {
			"operation": "REPLACE_ONE",
			"incoming_item_id": incoming_item_id,
			"replaced_item_id": replaced_item_id,
			"slot_index": slot_index,
		}))
	return _store(_post_commit_result(
		"REPLACE_ONE",
		incoming_item_id,
		slot_index,
		true,
		transfer_result,
		{"mode": MODE_SWAP, "replaced_item_id": replaced_item_id}
	))


func unequip_to_container(
	item_id: String,
	target_container_id: String,
	target_slot_index: int,
	operation_id: String,
	expected_item_revision: int = -1
) -> Dictionary:
	if operation_id.strip_edges().is_empty():
		return _store(_result(false, RESULT_INVALID_OPERATION_ID))
	var item = _item_registry.get_item(item_id)
	if item == null:
		return _store(_result(false, RESULT_ITEM_NOT_FOUND, {"item_id": item_id}))
	if target_container_id.strip_edges().is_empty() or target_container_id == equipment_container_id:
		return _store(_result(false, RESULT_TARGET_CONTAINER_INVALID, {"target_container_id": target_container_id}))
	if _container_registry.get_container(target_container_id) == null:
		return _store(_result(false, RESULT_TARGET_CONTAINER_INVALID, {"target_container_id": target_container_id}))

	var current_relation: Dictionary = ItemRelations.canonicalize(item.relation)
	var currently_equipped := (
		ItemRelations.kind_of(current_relation) == ItemRelations.CONTAINER
		and String(current_relation.get("container_id", "")) == equipment_container_id
	)
	if not currently_equipped:
		var already_at_target := (
			ItemRelations.kind_of(current_relation) == ItemRelations.CONTAINER
			and String(current_relation.get("container_id", "")) == target_container_id
			and (target_slot_index < 0 or int(current_relation.get("slot_index", -1)) == target_slot_index)
		)
		if already_at_target:
			return _store(_result(true, RESULT_OK, {
				"operation": "UNEQUIP",
				"mode": MODE_NO_CHANGE,
				"item_id": item_id,
				"target_container_id": target_container_id,
				"target_slot_index": target_slot_index,
				"no_change": true,
				"desired_state_already_reached": true,
			}))
		return _store(_result(false, RESULT_ITEM_NOT_EQUIPPED, {
			"item_id": item_id,
			"relation": current_relation,
		}))

	var transfer_result: Dictionary = _transfer_service.move_item(
		item_id,
		ItemRelations.container(target_container_id, target_slot_index),
		operation_id,
		expected_item_revision
	)
	if not bool(transfer_result.get("success", false)):
		return _store(_transfer_failure(transfer_result, {
			"operation": "UNEQUIP",
			"item_id": item_id,
			"target_container_id": target_container_id,
			"target_slot_index": target_slot_index,
		}))
	return _store(_post_commit_result(
		"UNEQUIP",
		item_id,
		-1,
		false,
		transfer_result,
		{
			"mode": MODE_MOVE,
			"target_container_id": target_container_id,
			"target_slot_index": target_slot_index,
		}
	))


func get_last_result() -> Dictionary:
	return _last_result.duplicate(true)


func create_report() -> Dictionary:
	return {
		"schema": "planet_simulator.character_equipment_operation_service_report.v1",
		"owner_entity_id": owner_entity_id,
		"equipment_container_id": equipment_container_id,
		"mutation_owner": "ITEM_TRANSFER_SERVICE",
		"owns_operation_ledger": false,
		"owns_item_registry": false,
		"owns_container_registry": false,
		"supports_strict_move": true,
		"supports_single_atomic_swap": true,
		"supports_multi_item_replacement": false,
		"multi_item_policy": "FAIL_CLOSED_REQUIRES_EXISTING_MULTI_ITEM_TRANSACTION_PATH",
		"last_success": bool(_last_result.get("success", false)),
		"last_code": String(_last_result.get("code", "")),
	}


func _post_commit_result(
	operation_name: String,
	item_id: String,
	slot_index: int,
	should_be_equipped: bool,
	transfer_result: Dictionary,
	extra_details: Dictionary
) -> Dictionary:
	var refresh_result: Dictionary = equipment_source.refresh()
	if not bool(refresh_result.get("success", false)):
		return _result(false, RESULT_POST_COMMIT_PROJECTION_FAILED, {
			"operation": operation_name,
			"item_id": item_id,
			"transfer_result": transfer_result,
			"source_result": refresh_result,
			"canonical_mutation_committed": true,
		})
	var snapshot: CharacterEquipmentDomain.Snapshot = equipment_source.get_snapshot()
	var present := snapshot.find_item(item_id) != null
	if present != should_be_equipped:
		return _result(false, RESULT_POST_COMMIT_PROJECTION_FAILED, {
			"operation": operation_name,
			"item_id": item_id,
			"expected_equipped": should_be_equipped,
			"actual_equipped": present,
			"transfer_result": transfer_result,
			"canonical_mutation_committed": true,
		})
	var details: Dictionary = extra_details.duplicate(true)
	details["operation"] = operation_name
	details["item_id"] = item_id
	details["slot_index"] = slot_index
	details["transfer_result"] = transfer_result.duplicate(true)
	details["equipment_revision"] = snapshot.revision
	details["state_fingerprint"] = snapshot.state_fingerprint()
	return _result(true, RESULT_OK, details)


func _transfer_failure(transfer_result: Dictionary, context: Dictionary) -> Dictionary:
	var details: Dictionary = context.duplicate(true)
	details["transfer_result"] = transfer_result.duplicate(true)
	details["transfer_error_code"] = String(transfer_result.get("error_code", ""))
	return _result(false, RESULT_TRANSFER_REJECTED, details)


func _conflicting_item_ids(plan: Dictionary) -> Array[String]:
	var details: Dictionary = Dictionary(plan.get("details", {}))
	return _sorted_string_values(Array(details.get("conflicting_item_ids", [])))


func _sorted_string_values(values: Array) -> Array[String]:
	var unique: Dictionary = {}
	for raw_value in values:
		var value := str(raw_value).strip_edges()
		if not value.is_empty():
			unique[value] = true
	var result: Array[String] = []
	for key in unique.keys():
		result.append(str(key))
	result.sort()
	return result


func _valid_item_registry(value) -> bool:
	return value != null and value.has_method("get_item") and value.has_method("get_definition")


func _valid_container_registry(value) -> bool:
	return value != null and value.has_method("get_container")


func _valid_transfer_service(value) -> bool:
	return value != null and value.has_method("move_item") and value.has_method("swap_items")


func _store(result: Dictionary) -> Dictionary:
	_last_result = result.duplicate(true)
	return _last_result.duplicate(true)


func _result(success: bool, code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": success,
		"code": code,
		"details": details.duplicate(true),
	}

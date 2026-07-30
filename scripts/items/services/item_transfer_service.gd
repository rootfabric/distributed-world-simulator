extends RefCounted

signal relation_changed(
	item_id: String,
	old_relation: Dictionary,
	new_relation: Dictionary
)
signal item_removed(item_id: String)
signal item_created(item_id: String)
signal quantity_changed(item_id: String, old_quantity: int, new_quantity: int)

const Relations = preload("res://scripts/items/domain/item_relations.gd")
const OperationFingerprint = preload("res://scripts/items/services/item_operation_fingerprint.gd")
const OperationLedger = preload("res://scripts/items/services/item_operation_ledger.gd")

const COMMAND_MOVE_ITEM: String = "MOVE_ITEM"
const COMMAND_SPLIT_AND_MOVE: String = "SPLIT_AND_MOVE"
const COMMAND_STACK_ITEMS: String = "STACK_ITEMS"
const COMMAND_SWAP_ITEMS: String = "SWAP_ITEMS"

var item_registry
var container_registry
var validator
var mass_service
var operation_ledger


func setup(
	new_item_registry,
	new_container_registry,
	new_validator,
	new_mass_service,
	new_operation_ledger = null
) -> void:
	item_registry = new_item_registry
	container_registry = new_container_registry
	validator = new_validator
	mass_service = new_mass_service
	operation_ledger = (
		new_operation_ledger
		if new_operation_ledger != null
		else OperationLedger.new()
	)


func move_item(
	item_id: String,
	new_relation: Dictionary,
	operation_id: String,
	expected_revision: int = -1
) -> Dictionary:
	if operation_id.is_empty():
		return _fail("OPERATION_ID_REQUIRED")
	if expected_revision < -1:
		return _fail("INVALID_EXPECTED_REVISION")
	var canonical_relation: Dictionary = Relations.canonicalize(new_relation)
	var prepared: Dictionary = _prepare_operation(
		operation_id,
		COMMAND_MOVE_ITEM,
		item_id,
		expected_revision,
		{"new_relation": canonical_relation}
	)
	if not bool(prepared.get("ready", false)):
		return Dictionary(prepared.get("result", {})).duplicate(true)
	var payload_hash: String = String(prepared.get("payload_hash", ""))
	var item = item_registry.get_item(item_id)
	if item == null:
		return _finish_operation(
			operation_id,
			COMMAND_MOVE_ITEM,
			payload_hash,
			item_id,
			expected_revision,
			-1,
			_fail("ITEM_NOT_FOUND")
		)
	if expected_revision >= 0 and int(item.revision) != expected_revision:
		return _finish_operation(
			operation_id,
			COMMAND_MOVE_ITEM,
			payload_hash,
			item_id,
			expected_revision,
			int(item.revision),
			_fail("REVISION_CONFLICT", {
				"expected_revision": expected_revision,
				"actual_revision": int(item.revision),
			})
		)

	var applied: Dictionary = _apply_move(item, canonical_relation)
	var result_revision: int = int(applied.get("_result_revision", int(item.revision)))
	applied.erase("_result_revision")
	return _finish_operation(
		operation_id,
		COMMAND_MOVE_ITEM,
		payload_hash,
		item_id,
		expected_revision,
		result_revision,
		applied
	)


func split_and_move(
	item_id: String,
	quantity: int,
	new_relation: Dictionary,
	operation_id: String,
	expected_revision: int = -1
) -> Dictionary:
	if operation_id.is_empty():
		return _fail("OPERATION_ID_REQUIRED")
	if expected_revision < -1:
		return _fail("INVALID_EXPECTED_REVISION")
	var canonical_relation: Dictionary = Relations.canonicalize(new_relation)
	var prepared: Dictionary = _prepare_operation(
		operation_id,
		COMMAND_SPLIT_AND_MOVE,
		item_id,
		expected_revision,
		{
			"quantity": quantity,
			"new_relation": canonical_relation,
		}
	)
	if not bool(prepared.get("ready", false)):
		return Dictionary(prepared.get("result", {})).duplicate(true)
	var payload_hash: String = String(prepared.get("payload_hash", ""))
	var source = item_registry.get_item(item_id)
	if source == null:
		return _finish_operation(
			operation_id,
			COMMAND_SPLIT_AND_MOVE,
			payload_hash,
			item_id,
			expected_revision,
			-1,
			_fail("ITEM_NOT_FOUND")
		)
	if expected_revision >= 0 and int(source.revision) != expected_revision:
		return _finish_operation(
			operation_id,
			COMMAND_SPLIT_AND_MOVE,
			payload_hash,
			item_id,
			expected_revision,
			int(source.revision),
			_fail("REVISION_CONFLICT", {
				"expected_revision": expected_revision,
				"actual_revision": int(source.revision),
			})
		)
	if quantity <= 0 or quantity >= source.quantity:
		return _finish_operation(
			operation_id,
			COMMAND_SPLIT_AND_MOVE,
			payload_hash,
			item_id,
			expected_revision,
			int(source.revision),
			_fail("INVALID_SPLIT_QUANTITY")
		)
	if source.owns_container():
		return _finish_operation(
			operation_id,
			COMMAND_SPLIT_AND_MOVE,
			payload_hash,
			item_id,
			expected_revision,
			int(source.revision),
			_fail("CONTAINER_ITEM_CANNOT_SPLIT")
		)

	var original_quantity: int = source.quantity
	var original_revision: int = source.revision
	var new_item = item_registry.create_item(
		source.definition_id,
		quantity,
		source.components,
		Relations.destroyed(),
		source.display_name
	)
	if new_item == null:
		return _finish_operation(
			operation_id,
			COMMAND_SPLIT_AND_MOVE,
			payload_hash,
			item_id,
			expected_revision,
			int(source.revision),
			_fail("SPLIT_CREATE_FAILED")
		)

	source.quantity -= quantity
	source.revision += 1
	quantity_changed.emit(
		source.instance_id,
		original_quantity,
		source.quantity
	)
	item_created.emit(new_item.instance_id)

	var move_result: Dictionary = _apply_move(new_item, canonical_relation)
	var moved_item_revision: int = int(
		move_result.get("_result_revision", int(new_item.revision))
	)
	move_result.erase("_result_revision")
	if not bool(move_result.get("success", false)):
		source.quantity = original_quantity
		source.revision = original_revision
		item_registry.remove_item(new_item.instance_id)
		quantity_changed.emit(
			source.instance_id,
			original_quantity - quantity,
			original_quantity
		)
		return _finish_operation(
			operation_id,
			COMMAND_SPLIT_AND_MOVE,
			payload_hash,
			item_id,
			expected_revision,
			original_revision,
			move_result
		)

	var result: Dictionary = move_result.duplicate(true)
	result["source_item_id"] = item_id
	result["new_item_id"] = new_item.instance_id
	result["split_quantity"] = quantity
	result["source_result_revision"] = int(source.revision)
	result["moved_item_result_revision"] = moved_item_revision
	return _finish_operation(
		operation_id,
		COMMAND_SPLIT_AND_MOVE,
		payload_hash,
		item_id,
		expected_revision,
		int(source.revision),
		result
	)


func stack_items(
	source_item_id: String,
	target_item_id: String,
	quantity: int,
	operation_id: String,
	expected_source_revision: int = -1,
	expected_target_revision: int = -1
) -> Dictionary:
	if operation_id.is_empty():
		return _fail("OPERATION_ID_REQUIRED")
	if expected_source_revision < -1 or expected_target_revision < -1:
		return _fail("INVALID_EXPECTED_REVISION")
	var prepared: Dictionary = _prepare_operation(
		operation_id,
		COMMAND_STACK_ITEMS,
		source_item_id,
		expected_source_revision,
		{
			"target_item_id": target_item_id,
			"quantity": quantity,
			"expected_target_revision": expected_target_revision,
		}
	)
	if not bool(prepared.get("ready", false)):
		return Dictionary(prepared.get("result", {})).duplicate(true)
	var payload_hash: String = String(prepared.get("payload_hash", ""))
	var source = item_registry.get_item(source_item_id)
	var target = item_registry.get_item(target_item_id)
	if source == null or target == null:
		return _finish_operation(
			operation_id,
			COMMAND_STACK_ITEMS,
			payload_hash,
			source_item_id,
			expected_source_revision,
			-1,
			_fail("ITEM_NOT_FOUND")
		)
	if Relations.kind_of(target.relation) != Relations.CONTAINER:
		return _finish_operation(
			operation_id,
			COMMAND_STACK_ITEMS,
			payload_hash,
			source_item_id,
			expected_source_revision,
			int(source.revision),
			_fail("STACK_TARGET_NOT_IN_CONTAINER")
		)
	if source_item_id == target_item_id:
		return _finish_operation(
			operation_id,
			COMMAND_STACK_ITEMS,
			payload_hash,
			source_item_id,
			expected_source_revision,
			int(source.revision),
			_fail("STACK_TARGET_IS_SOURCE")
		)
	if expected_source_revision >= 0 and int(source.revision) != expected_source_revision:
		return _finish_operation(
			operation_id,
			COMMAND_STACK_ITEMS,
			payload_hash,
			source_item_id,
			expected_source_revision,
			int(source.revision),
			_fail("REVISION_CONFLICT", {
				"aggregate_id": source_item_id,
				"expected_revision": expected_source_revision,
				"actual_revision": int(source.revision),
			})
		)
	if expected_target_revision >= 0 and int(target.revision) != expected_target_revision:
		return _finish_operation(
			operation_id,
			COMMAND_STACK_ITEMS,
			payload_hash,
			source_item_id,
			expected_source_revision,
			int(source.revision),
			_fail("REVISION_CONFLICT", {
				"aggregate_id": target_item_id,
				"expected_revision": expected_target_revision,
				"actual_revision": int(target.revision),
			})
		)
	if not source.is_stack_compatible(target):
		return _finish_operation(
			operation_id,
			COMMAND_STACK_ITEMS,
			payload_hash,
			source_item_id,
			expected_source_revision,
			int(source.revision),
			_fail("STACK_INCOMPATIBLE")
		)
	var definition = item_registry.get_definition(source.definition_id)
	if definition == null:
		return _finish_operation(
			operation_id,
			COMMAND_STACK_ITEMS,
			payload_hash,
			source_item_id,
			expected_source_revision,
			int(source.revision),
			_fail("ITEM_DEFINITION_NOT_FOUND")
		)
	var requested: int = int(source.quantity) if quantity < 0 else clampi(quantity, 1, int(source.quantity))
	var available: int = maxi(0, int(definition.max_stack) - int(target.quantity))
	if available <= 0:
		return _finish_operation(
			operation_id,
			COMMAND_STACK_ITEMS,
			payload_hash,
			source_item_id,
			expected_source_revision,
			int(source.revision),
			_fail("STACK_FULL")
		)
	var moved: int = mini(requested, available)
	var capacity: Dictionary = _validate_stack_capacity(source, target, moved)
	if not bool(capacity.get("success", false)):
		return _finish_operation(
			operation_id,
			COMMAND_STACK_ITEMS,
			payload_hash,
			source_item_id,
			expected_source_revision,
			int(source.revision),
			capacity
		)

	var source_old_quantity: int = int(source.quantity)
	var target_old_quantity: int = int(target.quantity)
	target.quantity += moved
	target.revision += 1
	source.quantity -= moved
	var source_removed: bool = int(source.quantity) <= 0
	if source_removed:
		_remove_from_old_container(source)
		item_registry.remove_item(source_item_id)
		item_removed.emit(source_item_id)
	else:
		source.revision += 1
		_touch_relation_container(source.relation)
		quantity_changed.emit(source_item_id, source_old_quantity, int(source.quantity))
	_touch_relation_container(target.relation)
	quantity_changed.emit(target_item_id, target_old_quantity, int(target.quantity))

	var result: Dictionary = {
		"success": true,
		"item_id": source_item_id,
		"source_item_id": source_item_id,
		"target_item_id": target_item_id,
		"result_item_id": target_item_id if source_removed else source_item_id,
		"merged": true,
		"partial_merge": not source_removed,
		"moved_quantity": moved,
		"remaining_quantity": 0 if source_removed else int(source.quantity),
		"source_removed": source_removed,
		"source_result_revision": -1 if source_removed else int(source.revision),
		"target_result_revision": int(target.revision),
		"no_change": false,
	}
	return _finish_operation(
		operation_id,
		COMMAND_STACK_ITEMS,
		payload_hash,
		source_item_id,
		expected_source_revision,
		int(target.revision) if source_removed else int(source.revision),
		result
	)


func swap_items(
	first_item_id: String,
	second_item_id: String,
	operation_id: String,
	expected_first_revision: int = -1,
	expected_second_revision: int = -1
) -> Dictionary:
	if operation_id.is_empty():
		return _fail("OPERATION_ID_REQUIRED")
	if first_item_id.is_empty() or second_item_id.is_empty():
		return _fail("ITEM_ID_REQUIRED")
	if first_item_id == second_item_id:
		return _fail("SWAP_ITEMS_MUST_DIFFER")
	if expected_first_revision < -1 or expected_second_revision < -1:
		return _fail("INVALID_EXPECTED_REVISION")
	var first = item_registry.get_item(first_item_id)
	var second = item_registry.get_item(second_item_id)
	if first == null or second == null:
		return _fail("ITEM_NOT_FOUND")
	var first_relation: Dictionary = Relations.canonicalize(first.relation)
	var second_relation: Dictionary = Relations.canonicalize(second.relation)
	if Relations.kind_of(first_relation) != Relations.CONTAINER or Relations.kind_of(second_relation) != Relations.CONTAINER:
		return _fail("SWAP_REQUIRES_CONTAINER_ITEMS")
	var prepared: Dictionary = _prepare_operation(
		operation_id,
		COMMAND_SWAP_ITEMS,
		first_item_id,
		expected_first_revision,
		{
			"second_item_id": second_item_id,
			"expected_second_revision": expected_second_revision,
		}
	)
	if not bool(prepared.get("ready", false)):
		return Dictionary(prepared.get("result", {})).duplicate(true)
	var payload_hash := String(prepared.get("payload_hash", ""))
	if expected_first_revision >= 0 and int(first.revision) != expected_first_revision:
		return _finish_operation(
			operation_id,
			COMMAND_SWAP_ITEMS,
			payload_hash,
			first_item_id,
			expected_first_revision,
			int(first.revision),
			_fail("REVISION_CONFLICT", {
				"item_id": first_item_id,
				"expected_revision": expected_first_revision,
				"actual_revision": int(first.revision),
			})
		)
	if expected_second_revision >= 0 and int(second.revision) != expected_second_revision:
		return _finish_operation(
			operation_id,
			COMMAND_SWAP_ITEMS,
			payload_hash,
			first_item_id,
			expected_first_revision,
			int(first.revision),
			_fail("SWAP_SECOND_REVISION_CONFLICT", {
				"item_id": second_item_id,
				"expected_revision": expected_second_revision,
				"actual_revision": int(second.revision),
			})
		)

	var container_ids := PackedStringArray([
		String(first_relation.get("container_id", "")),
		String(second_relation.get("container_id", "")),
	])
	var snapshot := _snapshot_swap_state(first, second, container_ids)
	_remove_item_membership_without_revision(first)
	_remove_item_membership_without_revision(second)
	var first_validation: Dictionary = validator.validate_reparent(first_item_id, second_relation)
	if not bool(first_validation.get("success", false)):
		_restore_swap_state(first, second, snapshot)
		return _finish_operation(operation_id, COMMAND_SWAP_ITEMS, payload_hash, first_item_id, expected_first_revision, int(first.revision), first_validation)
	var second_validation: Dictionary = validator.validate_reparent(second_item_id, first_relation)
	if not bool(second_validation.get("success", false)):
		_restore_swap_state(first, second, snapshot)
		return _finish_operation(operation_id, COMMAND_SWAP_ITEMS, payload_hash, first_item_id, expected_first_revision, int(first.revision), second_validation)
	var capacity_validation := _validate_swap_final_capacity(first, second, first_relation, second_relation, snapshot)
	if not bool(capacity_validation.get("success", false)):
		_restore_swap_state(first, second, snapshot)
		return _finish_operation(operation_id, COMMAND_SWAP_ITEMS, payload_hash, first_item_id, expected_first_revision, int(first.revision), capacity_validation)

	first.set_relation(second_relation)
	second.set_relation(first_relation)
	first.revision += 1
	second.revision += 1
	if not _assign_item_membership_without_revision(first) or not _assign_item_membership_without_revision(second):
		_restore_swap_state(first, second, snapshot)
		return _finish_operation(
			operation_id,
			COMMAND_SWAP_ITEMS,
			payload_hash,
			first_item_id,
			expected_first_revision,
			int(first.revision),
			_fail("SWAP_ASSIGNMENT_FAILED")
		)
	var snapshot_containers := Dictionary(snapshot.get("containers", {}))
	var touched_container_ids := PackedStringArray()
	for container_id_value in container_ids:
		var normalized_container_id := String(container_id_value)
		if normalized_container_id.is_empty() or touched_container_ids.has(normalized_container_id):
			continue
		touched_container_ids.append(normalized_container_id)
		var container = container_registry.get_container(normalized_container_id)
		if container == null:
			continue
		var container_snapshot := Dictionary(snapshot_containers.get(normalized_container_id, {}))
		container.revision = int(container_snapshot.get("revision", int(container.revision))) + 1
	var graph_validation: Dictionary = validator.validate_graph()
	if not bool(graph_validation.get("success", false)):
		_restore_swap_state(first, second, snapshot)
		return _finish_operation(operation_id, COMMAND_SWAP_ITEMS, payload_hash, first_item_id, expected_first_revision, int(first.revision), graph_validation)
	relation_changed.emit(first_item_id, first_relation, first.relation.duplicate(true))
	relation_changed.emit(second_item_id, second_relation, second.relation.duplicate(true))
	return _finish_operation(
		operation_id,
		COMMAND_SWAP_ITEMS,
		payload_hash,
		first_item_id,
		expected_first_revision,
		int(first.revision),
		{
			"success": true,
			"swapped": true,
			"item_id": first_item_id,
			"first_item_id": first_item_id,
			"second_item_id": second_item_id,
			"first_relation": first.relation.duplicate(true),
			"second_relation": second.relation.duplicate(true),
			"first_result_revision": int(first.revision),
			"second_result_revision": int(second.revision),
			"result_item_id": first_item_id,
			"no_change": false,
		}
	)


func _apply_move(item, canonical_relation: Dictionary) -> Dictionary:
	canonical_relation = _resolve_container_relation(item, canonical_relation)
	if item.relation == canonical_relation:
		var graph_validation: Dictionary = validator.validate_graph()
		if not bool(graph_validation.get("success", false)):
			graph_validation["_result_revision"] = int(item.revision)
			return graph_validation
		return {
			"success": true,
			"item_id": item.instance_id,
			"result_item_id": item.instance_id,
			"merged": false,
			"no_change": true,
			"_result_revision": int(item.revision),
		}

	var validation: Dictionary = validator.validate_reparent(
		item.instance_id,
		canonical_relation
	)
	if not bool(validation.get("success", false)):
		validation["_result_revision"] = int(item.revision)
		return validation

	var capacity: Dictionary = _validate_capacity(
		item.instance_id,
		canonical_relation
	)
	if not bool(capacity.get("success", false)):
		capacity["_result_revision"] = int(item.revision)
		return capacity

	var old_relation: Dictionary = item.relation.duplicate(true)
	_remove_from_old_container(item)

	var merge_result: Dictionary = {"merged": false, "transferred_quantity": 0}
	if Relations.kind_of(canonical_relation) == Relations.CONTAINER:
		merge_result = _try_merge(
			item,
			String(canonical_relation.get("container_id", "")),
			int(canonical_relation.get("slot_index", -1))
		)
		if bool(merge_result.get("fully_merged", false)):
			var merged_into_item_id: String = String(
				merge_result.get("merged_into_item_id", "")
			)
			item_removed.emit(item.instance_id)
			return {
				"success": true,
				"item_id": item.instance_id,
				"result_item_id": merged_into_item_id,
				"merged": true,
				"partial_merge": false,
				"merged_into_item_id": merged_into_item_id,
				"merged_into_item_ids": merge_result.get("merged_into_item_ids", []).duplicate(),
				"moved_quantity": int(merge_result.get("transferred_quantity", 0)),
				"remaining_quantity": 0,
				"no_change": false,
				"_result_revision": int(
					merge_result.get("result_revision", -1)
				),
			}

	item.set_relation(canonical_relation)
	item.revision += 1
	_add_to_new_container(item)

	var transferred_quantity := int(merge_result.get("transferred_quantity", 0))
	var result: Dictionary = {
		"success": true,
		"item_id": item.instance_id,
		"result_item_id": item.instance_id,
		"merged": transferred_quantity > 0,
		"partial_merge": transferred_quantity > 0,
		"merged_into_item_id": String(merge_result.get("merged_into_item_id", "")),
		"merged_into_item_ids": merge_result.get("merged_into_item_ids", []).duplicate(),
		"moved_quantity": transferred_quantity + int(item.quantity),
		"remaining_quantity": int(item.quantity),
		"no_change": false,
		"_result_revision": int(item.revision),
	}
	relation_changed.emit(
		item.instance_id,
		old_relation,
		item.relation.duplicate(true)
	)
	return result


func _resolve_container_relation(item, relation: Dictionary) -> Dictionary:
	if Relations.kind_of(relation) != Relations.CONTAINER:
		return relation
	var container_id := String(relation.get("container_id", ""))
	var container = container_registry.get_container(container_id)
	if container == null or not container.is_slot_container():
		return Relations.container(container_id, -1)
	var requested_slot := int(relation.get("slot_index", -1))
	if requested_slot >= 0:
		return Relations.container(container_id, requested_slot)
	var definition = item_registry.get_definition(item.definition_id)
	for slot_index in range(container.slot_count):
		var occupant_id: String = String(container.get_item_at_slot(slot_index))
		if occupant_id.is_empty():
			if definition != null and container.can_accept_definition_in_slot(definition, slot_index):
				return Relations.container(container_id, slot_index)
			continue
		var occupant = item_registry.get_item(occupant_id)
		if occupant != null and occupant.is_stack_compatible(item):
			if int(occupant.quantity) + int(item.quantity) <= int(definition.max_stack):
				return Relations.container(container_id, slot_index)
	return relation


func _prepare_operation(
	operation_id: String,
	command_type: String,
	aggregate_id: String,
	expected_revision: int,
	payload: Dictionary
) -> Dictionary:
	var fingerprint: Dictionary = OperationFingerprint.build(
		command_type,
		aggregate_id,
		expected_revision,
		payload
	)
	if not bool(fingerprint.get("success", false)):
		return {
			"ready": false,
			"result": fingerprint,
		}
	var payload_hash: String = String(fingerprint.get("payload_hash", ""))
	var resolved: Dictionary = operation_ledger.resolve(
		operation_id,
		command_type,
		payload_hash,
		aggregate_id,
		expected_revision
	)
	if bool(resolved.get("found", false)):
		return {
			"ready": false,
			"result": Dictionary(resolved.get("result", {})).duplicate(true),
		}
	return {
		"ready": true,
		"payload_hash": payload_hash,
	}


func _finish_operation(
	operation_id: String,
	command_type: String,
	payload_hash: String,
	aggregate_id: String,
	expected_revision: int,
	result_revision: int,
	base_result: Dictionary
) -> Dictionary:
	if bool(base_result.get("success", false)):
		return operation_ledger.remember_terminal(
			operation_id,
			command_type,
			payload_hash,
			aggregate_id,
			expected_revision,
			result_revision,
			OperationLedger.STATUS_SUCCEEDED,
			base_result
		)
	var error_code: String = String(base_result.get("error_code", ""))
	if _is_retryable_error(error_code):
		return operation_ledger.decorate_retryable(
			base_result,
			operation_id,
			command_type,
			payload_hash,
			aggregate_id,
			expected_revision,
			result_revision
		)
	return operation_ledger.remember_terminal(
		operation_id,
		command_type,
		payload_hash,
		aggregate_id,
		expected_revision,
		result_revision,
		OperationLedger.STATUS_REJECTED,
		base_result
	)


func _is_retryable_error(error_code: String) -> bool:
	return error_code in [
		"ITEM_NOT_FOUND",
		"CONTAINER_NOT_FOUND",
		"SPLIT_CREATE_FAILED",
	]


func _validate_capacity(
	item_id: String,
	relation: Dictionary
) -> Dictionary:
	if Relations.kind_of(relation) != Relations.CONTAINER:
		return {"success": true}

	var container_id: String = String(relation.get("container_id", ""))
	var container = container_registry.get_container(container_id)
	if container == null:
		return _fail("CONTAINER_NOT_FOUND")

	var item = item_registry.get_item(item_id)
	var item_mass: float = mass_service.item_recursive_mass_kg(item_id)
	var item_volume: float = mass_service.item_external_volume_l(item_id)
	var current_mass: float = mass_service.container_mass_kg(container_id)
	var current_volume: float = mass_service.container_direct_volume_l(container_id)

	var already_in_target: bool = (
		item != null
		and Relations.kind_of(item.relation) == Relations.CONTAINER
		and String(item.relation.get("container_id", "")) == container_id
		and container.item_ids.has(item_id)
	)
	if already_in_target:
		current_mass -= item_mass
		current_volume -= item_volume

	if current_mass + item_mass > container.maximum_mass_kg + 0.000001:
		return _fail("MAXIMUM_MASS_EXCEEDED")
	if current_volume + item_volume > container.maximum_volume_l + 0.000001:
		return _fail("MAXIMUM_VOLUME_EXCEEDED")
	return {"success": true}


func _validate_stack_capacity(source, target, moved_quantity: int) -> Dictionary:
	if moved_quantity <= 0 or Relations.kind_of(target.relation) != Relations.CONTAINER:
		return {"success": true}
	var target_container_id := String(target.relation.get("container_id", ""))
	var target_container = container_registry.get_container(target_container_id)
	if target_container == null:
		return _fail("CONTAINER_NOT_FOUND")
	var source_container_id := ""
	if Relations.kind_of(source.relation) == Relations.CONTAINER:
		source_container_id = String(source.relation.get("container_id", ""))
	if source_container_id == target_container_id:
		return {"success": true}
	var definition = item_registry.get_definition(source.definition_id)
	if definition == null:
		return _fail("ITEM_DEFINITION_NOT_FOUND")
	var added_mass: float = float(definition.unit_mass_kg) * float(moved_quantity)
	var added_volume: float = float(definition.external_volume_l) * float(moved_quantity)
	var current_mass: float = mass_service.container_mass_kg(target_container_id)
	var current_volume: float = mass_service.container_direct_volume_l(target_container_id)
	if current_mass + added_mass > target_container.maximum_mass_kg + 0.000001:
		return _fail("MAXIMUM_MASS_EXCEEDED")
	if current_volume + added_volume > target_container.maximum_volume_l + 0.000001:
		return _fail("MAXIMUM_VOLUME_EXCEEDED")
	return {"success": true}


func _touch_relation_container(relation: Dictionary) -> void:
	if Relations.kind_of(relation) != Relations.CONTAINER:
		return
	var container = container_registry.get_container(String(relation.get("container_id", "")))
	if container != null:
		container.revision += 1


func _remove_from_old_container(item) -> void:
	if Relations.kind_of(item.relation) != Relations.CONTAINER:
		return
	var container = container_registry.get_container(
		String(item.relation.get("container_id", ""))
	)
	if container != null:
		container.remove_item(item.instance_id)
		container.revision += 1


func _add_to_new_container(item) -> void:
	if Relations.kind_of(item.relation) != Relations.CONTAINER:
		return
	var container = container_registry.get_container(
		String(item.relation.get("container_id", ""))
	)
	if container != null and not container.item_ids.has(item.instance_id):
		var assigned_slot: int = int(container.assign_item(
			item.instance_id,
			int(item.relation.get("slot_index", -1))
		))
		if container.is_slot_container() and assigned_slot >= 0:
			item.set_relation(Relations.container(container.container_id, assigned_slot))
		container.revision += 1


func _try_merge(item, container_id: String, requested_slot_index: int = -1) -> Dictionary:
	var container = container_registry.get_container(container_id)
	var definition = item_registry.get_definition(item.definition_id)
	if container == null or definition == null or int(definition.max_stack) <= 1:
		return {"merged": false, "transferred_quantity": 0}

	var candidate_ids: Array[String] = []
	if container.is_slot_container():
		if requested_slot_index < 0:
			return {"merged": false, "transferred_quantity": 0}
		var occupant_id: String = String(container.get_item_at_slot(requested_slot_index))
		if not occupant_id.is_empty():
			candidate_ids.append(occupant_id)
	else:
		for existing_id in container.item_ids:
			candidate_ids.append(String(existing_id))

	var original_quantity: int = int(item.quantity)
	var transferred_quantity: int = 0
	var merged_into_ids: Array[String] = []
	var highest_result_revision: int = -1
	for existing_id in candidate_ids:
		if item.quantity <= 0:
			break
		if existing_id == item.instance_id:
			continue
		var existing = item_registry.get_item(existing_id)
		if existing == null or not existing.is_stack_compatible(item):
			continue
		var available: int = maxi(0, int(definition.max_stack) - int(existing.quantity))
		if available <= 0:
			continue
		var moved: int = mini(available, int(item.quantity))
		var old_existing_quantity: int = int(existing.quantity)
		existing.quantity += moved
		existing.revision += 1
		item.quantity -= moved
		transferred_quantity += moved
		merged_into_ids.append(existing.instance_id)
		highest_result_revision = maxi(highest_result_revision, int(existing.revision))
		quantity_changed.emit(existing.instance_id, old_existing_quantity, int(existing.quantity))

	if transferred_quantity <= 0:
		return {"merged": false, "transferred_quantity": 0}

	container.revision += 1
	var fully_merged: bool = int(item.quantity) <= 0
	if fully_merged:
		item_registry.remove_item(item.instance_id)
	else:
		item.revision += 1
		quantity_changed.emit(item.instance_id, original_quantity, int(item.quantity))

	return {
		"merged": true,
		"fully_merged": fully_merged,
		"transferred_quantity": transferred_quantity,
		"remaining_quantity": int(item.quantity),
		"merged_into_item_id": merged_into_ids[0] if not merged_into_ids.is_empty() else "",
		"merged_into_item_ids": merged_into_ids,
		"result_revision": highest_result_revision if fully_merged else int(item.revision),
	}


func _snapshot_swap_state(first, second, container_ids: PackedStringArray) -> Dictionary:
	var containers: Dictionary = {}
	for container_id in container_ids:
		var normalized := String(container_id)
		if normalized.is_empty() or containers.has(normalized):
			continue
		var container = container_registry.get_container(normalized)
		if container != null:
			containers[normalized] = {
				"item_ids": container.item_ids.duplicate(),
				"slot_assignments": container.slot_assignments.duplicate(true),
				"revision": int(container.revision),
				"mass_kg": mass_service.container_mass_kg(normalized),
				"volume_l": mass_service.container_direct_volume_l(normalized),
			}
	return {
		"first_relation": first.relation.duplicate(true),
		"second_relation": second.relation.duplicate(true),
		"first_revision": int(first.revision),
		"second_revision": int(second.revision),
		"containers": containers,
	}


func _restore_swap_state(first, second, snapshot: Dictionary) -> void:
	first.set_relation(Dictionary(snapshot.get("first_relation", {})).duplicate(true))
	second.set_relation(Dictionary(snapshot.get("second_relation", {})).duplicate(true))
	first.revision = int(snapshot.get("first_revision", int(first.revision)))
	second.revision = int(snapshot.get("second_revision", int(second.revision)))
	var containers := Dictionary(snapshot.get("containers", {}))
	for container_id in containers:
		var container = container_registry.get_container(String(container_id))
		if container == null:
			continue
		var state := Dictionary(containers[container_id])
		var restored_item_ids: Array[String] = []
		for item_id_value in Array(state.get("item_ids", [])):
			restored_item_ids.append(String(item_id_value))
		container.item_ids = restored_item_ids
		container.slot_assignments = Dictionary(state.get("slot_assignments", {})).duplicate(true)
		container.revision = int(state.get("revision", int(container.revision)))


func _remove_item_membership_without_revision(item) -> void:
	if Relations.kind_of(item.relation) != Relations.CONTAINER:
		return
	var container = container_registry.get_container(String(item.relation.get("container_id", "")))
	if container != null:
		container.remove_item(String(item.instance_id))


func _assign_item_membership_without_revision(item) -> bool:
	if Relations.kind_of(item.relation) != Relations.CONTAINER:
		return true
	var container = container_registry.get_container(String(item.relation.get("container_id", "")))
	if container == null:
		return false
	var requested_slot := int(item.relation.get("slot_index", -1))
	var assigned_slot := int(container.assign_item(String(item.instance_id), requested_slot))
	if container.is_slot_container():
		if assigned_slot < 0:
			return false
		item.set_relation(Relations.container(String(container.container_id), assigned_slot))
	return container.item_ids.has(String(item.instance_id))


func _validate_swap_final_capacity(first, second, first_relation: Dictionary, second_relation: Dictionary, snapshot: Dictionary) -> Dictionary:
	var first_old_container := String(first_relation.get("container_id", ""))
	var second_old_container := String(second_relation.get("container_id", ""))
	var destinations := {
		String(first.instance_id): second_old_container,
		String(second.instance_id): first_old_container,
	}
	var old_containers := {
		String(first.instance_id): first_old_container,
		String(second.instance_id): second_old_container,
	}
	var containers := Dictionary(snapshot.get("containers", {}))
	for container_id in containers:
		var container = container_registry.get_container(String(container_id))
		if container == null:
			return _fail("CONTAINER_NOT_FOUND")
		var state := Dictionary(containers[container_id])
		var final_mass := float(state.get("mass_kg", 0.0))
		var final_volume := float(state.get("volume_l", 0.0))
		var final_entries := Array(state.get("item_ids", [])).size()
		for item in [first, second]:
			var item_id := String(item.instance_id)
			var item_mass: float = float(mass_service.item_recursive_mass_kg(item_id))
			var item_volume: float = float(mass_service.item_external_volume_l(item_id))
			if String(old_containers[item_id]) == String(container_id):
				final_mass -= item_mass
				final_volume -= item_volume
				final_entries -= 1
			if String(destinations[item_id]) == String(container_id):
				final_mass += item_mass
				final_volume += item_volume
				final_entries += 1
		if final_mass > float(container.maximum_mass_kg) + 0.000001:
			return _fail("MAXIMUM_MASS_EXCEEDED")
		if final_volume > float(container.maximum_volume_l) + 0.000001:
			return _fail("MAXIMUM_VOLUME_EXCEEDED")
		if not container.is_slot_container() and int(container.slot_count) > 0 and final_entries > int(container.slot_count):
			return _fail("NO_FREE_SLOT")
	return {"success": true}


func _fail(code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": code,
		"details": details.duplicate(true),
	}

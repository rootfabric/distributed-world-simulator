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


func _apply_move(item, canonical_relation: Dictionary) -> Dictionary:
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

	if Relations.kind_of(canonical_relation) == Relations.CONTAINER:
		var merge_result: Dictionary = _try_merge(
			item,
			String(canonical_relation.get("container_id", ""))
		)
		if bool(merge_result.get("merged", false)):
			var merged_into_item_id: String = String(
				merge_result.get("merged_into_item_id", "")
			)
			item_removed.emit(item.instance_id)
			return {
				"success": true,
				"item_id": item.instance_id,
				"result_item_id": merged_into_item_id,
				"merged": true,
				"merged_into_item_id": merged_into_item_id,
				"no_change": false,
				"_result_revision": int(
					merge_result.get("result_revision", -1)
				),
			}

	item.set_relation(canonical_relation)
	item.revision += 1
	_add_to_new_container(item)

	var result: Dictionary = {
		"success": true,
		"item_id": item.instance_id,
		"result_item_id": item.instance_id,
		"merged": false,
		"no_change": false,
		"_result_revision": int(item.revision),
	}
	relation_changed.emit(
		item.instance_id,
		old_relation,
		item.relation.duplicate(true)
	)
	return result


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


func _remove_from_old_container(item) -> void:
	if Relations.kind_of(item.relation) != Relations.CONTAINER:
		return
	var container = container_registry.get_container(
		String(item.relation.get("container_id", ""))
	)
	if container != null:
		container.item_ids.erase(item.instance_id)
		container.revision += 1


func _add_to_new_container(item) -> void:
	if Relations.kind_of(item.relation) != Relations.CONTAINER:
		return
	var container = container_registry.get_container(
		String(item.relation.get("container_id", ""))
	)
	if container != null and not container.item_ids.has(item.instance_id):
		container.item_ids.append(item.instance_id)
		container.revision += 1


func _try_merge(item, container_id: String) -> Dictionary:
	var container = container_registry.get_container(container_id)
	var definition = item_registry.get_definition(item.definition_id)
	for existing_id in container.item_ids:
		if existing_id == item.instance_id:
			continue
		var existing = item_registry.get_item(existing_id)
		if existing == null or not existing.is_stack_compatible(item):
			continue
		var available: int = definition.max_stack - existing.quantity
		if available < item.quantity:
			continue
		var old_quantity: int = existing.quantity
		existing.quantity += item.quantity
		existing.revision += 1
		container.revision += 1
		item_registry.remove_item(item.instance_id)
		quantity_changed.emit(
			existing.instance_id,
			old_quantity,
			existing.quantity
		)
		return {
			"merged": true,
			"merged_into_item_id": existing.instance_id,
			"result_revision": int(existing.revision),
		}
	return {"merged": false}


func _fail(code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": code,
		"details": details.duplicate(true),
	}

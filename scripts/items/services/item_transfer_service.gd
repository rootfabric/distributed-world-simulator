extends RefCounted

signal relation_changed(item_id: String, old_relation: Dictionary, new_relation: Dictionary)
signal item_removed(item_id: String)
signal item_created(item_id: String)

const Relations = preload("res://scripts/items/domain/item_relations.gd")

var item_registry
var container_registry
var validator
var mass_service
var completed_operations: Dictionary = {}


func setup(new_item_registry, new_container_registry, new_validator, new_mass_service) -> void:
	item_registry = new_item_registry
	container_registry = new_container_registry
	validator = new_validator
	mass_service = new_mass_service


func move_item(item_id: String, new_relation: Dictionary, operation_id: String) -> Dictionary:
	if operation_id.is_empty():
		return _fail("OPERATION_ID_REQUIRED")
	if completed_operations.has(operation_id):
		return Dictionary(completed_operations[operation_id]).duplicate(true)
	var item = item_registry.get_item(item_id)
	if item == null:
		return _remember(operation_id, _fail("ITEM_NOT_FOUND"))
	var validation: Dictionary = validator.validate_reparent(item_id, new_relation)
	if not bool(validation.get("success", false)):
		return _remember(operation_id, validation)
	var capacity := _validate_capacity(item_id, new_relation)
	if not bool(capacity.get("success", false)):
		return _remember(operation_id, capacity)
	var old_relation: Dictionary = item.relation.duplicate(true)
	_remove_from_old_container(item)
	if Relations.kind_of(new_relation) == Relations.CONTAINER:
		var merged := _try_merge(item, String(new_relation.get("container_id", "")))
		if merged:
			var merge_result := {
				"success": true,
				"operation_id": operation_id,
				"item_id": item_id,
				"merged": true,
			}
			item_removed.emit(item_id)
			return _remember(operation_id, merge_result)
	item.relation = new_relation.duplicate(true)
	item.revision += 1
	_add_to_new_container(item)
	var result := {
		"success": true,
		"operation_id": operation_id,
		"item_id": item_id,
		"merged": false,
	}
	relation_changed.emit(item_id, old_relation, item.relation.duplicate(true))
	return _remember(operation_id, result)


func split_and_move(item_id: String, quantity: int, new_relation: Dictionary, operation_id: String) -> Dictionary:
	if completed_operations.has(operation_id):
		return Dictionary(completed_operations[operation_id]).duplicate(true)
	var source = item_registry.get_item(item_id)
	if source == null:
		return _remember(operation_id, _fail("ITEM_NOT_FOUND"))
	if quantity <= 0 or quantity >= source.quantity:
		return _remember(operation_id, _fail("INVALID_SPLIT_QUANTITY"))
	if source.owns_container():
		return _remember(operation_id, _fail("CONTAINER_ITEM_CANNOT_SPLIT"))
	var validation: Dictionary = validator.validate_reparent(item_id, new_relation)
	if not bool(validation.get("success", false)):
		return _remember(operation_id, validation)
	var new_item = item_registry.create_item(source.definition_id, quantity, source.components, source.relation)
	if new_item == null:
		return _remember(operation_id, _fail("SPLIT_CREATE_FAILED"))
	item_created.emit(new_item.instance_id)
	source.quantity -= quantity
	source.revision += 1
	var move_result := move_item(new_item.instance_id, new_relation, operation_id + ":move")
	if not bool(move_result.get("success", false)):
		source.quantity += quantity
		source.revision += 1
		item_registry.remove_item(new_item.instance_id)
		return _remember(operation_id, move_result)
	var result := move_result.duplicate(true)
	result["operation_id"] = operation_id
	result["source_item_id"] = item_id
	result["new_item_id"] = new_item.instance_id
	result["split_quantity"] = quantity
	return _remember(operation_id, result)


func _validate_capacity(item_id: String, relation: Dictionary) -> Dictionary:
	if Relations.kind_of(relation) != Relations.CONTAINER:
		return {"success": true}
	var container_id := String(relation.get("container_id", ""))
	var container = container_registry.get_container(container_id)
	var new_mass := mass_service.container_mass_kg(container_id) + mass_service.item_recursive_mass_kg(item_id)
	if new_mass > container.maximum_mass_kg + 0.000001:
		return _fail("MAXIMUM_MASS_EXCEEDED")
	var new_volume := mass_service.container_direct_volume_l(container_id) + mass_service.item_external_volume_l(item_id)
	if new_volume > container.maximum_volume_l + 0.000001:
		return _fail("MAXIMUM_VOLUME_EXCEEDED")
	return {"success": true}


func _remove_from_old_container(item) -> void:
	if Relations.kind_of(item.relation) != Relations.CONTAINER:
		return
	var container = container_registry.get_container(String(item.relation.get("container_id", "")))
	if container != null:
		container.item_ids.erase(item.instance_id)
		container.revision += 1


func _add_to_new_container(item) -> void:
	if Relations.kind_of(item.relation) != Relations.CONTAINER:
		return
	var container = container_registry.get_container(String(item.relation.get("container_id", "")))
	if container != null and not container.item_ids.has(item.instance_id):
		container.item_ids.append(item.instance_id)
		container.revision += 1


func _try_merge(item, container_id: String) -> bool:
	var container = container_registry.get_container(container_id)
	var definition = item_registry.get_definition(item.definition_id)
	for existing_id in container.item_ids:
		var existing = item_registry.get_item(existing_id)
		if existing == null or not existing.is_stack_compatible(item):
			continue
		var available := definition.max_stack - existing.quantity
		if available < item.quantity:
			continue
		existing.quantity += item.quantity
		existing.revision += 1
		container.revision += 1
		item_registry.remove_item(item.instance_id)
		return true
	return false


func _remember(operation_id: String, result: Dictionary) -> Dictionary:
	completed_operations[operation_id] = result.duplicate(true)
	return result


func _fail(code: String) -> Dictionary:
	return {"success": false, "error_code": code}

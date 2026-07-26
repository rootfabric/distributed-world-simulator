extends RefCounted

const Relations = preload("res://scripts/items/domain/item_relations.gd")

var item_registry
var container_registry


func setup(new_item_registry, new_container_registry) -> void:
	item_registry = new_item_registry
	container_registry = new_container_registry


func validate_reparent(item_id: String, new_relation: Dictionary) -> Dictionary:
	var item = item_registry.get_item(item_id)
	if item == null:
		return _fail("ITEM_NOT_FOUND")
	var kind := Relations.kind_of(new_relation)
	if not [Relations.WORLD, Relations.CONTAINER, Relations.ATTACHMENT, Relations.DESTROYED].has(kind):
		return _fail("INVALID_RELATION")
	if kind == Relations.CONTAINER:
		return _validate_container_target(item, String(new_relation.get("container_id", "")))
	if kind == Relations.ATTACHMENT:
		return _validate_attachment_target(item, String(new_relation.get("parent_item_id", "")))
	return {"success": true}


func validate_graph() -> Dictionary:
	for item in item_registry.all_items():
		var seen: Dictionary = {}
		var current_id := String(item.instance_id)
		while not current_id.is_empty():
			if seen.has(current_id):
				return _fail("RELATION_CYCLE", {"item_id": item.instance_id})
			seen[current_id] = true
			var current = item_registry.get_item(current_id)
			if current == null:
				break
			current_id = Relations.relation_parent_item_id(current.relation, container_registry)
	return {"success": true}


func get_nested_depth(item_id: String) -> int:
	var depth := 0
	var current = item_registry.get_item(item_id)
	while current != null:
		var parent_id := Relations.relation_parent_item_id(current.relation, container_registry)
		if parent_id.is_empty():
			break
		depth += 1
		current = item_registry.get_item(parent_id)
	return depth


func _validate_container_target(item, container_id: String) -> Dictionary:
	var container = container_registry.get_container(container_id)
	if container == null:
		return _fail("CONTAINER_NOT_FOUND")
	var owner_item_id := container.owner_id if container.owner_kind == "ITEM_INSTANCE" else ""
	if not owner_item_id.is_empty():
		if owner_item_id == item.instance_id:
			return _fail("RELATION_CYCLE")
		if _is_descendant(owner_item_id, item.instance_id):
			return _fail("RELATION_CYCLE")
	if item.owns_container() and not container.allow_nested_containers:
		return _fail("NESTED_CONTAINERS_FORBIDDEN")
	if not container.has_free_slot() and not _can_merge_into_container(item, container):
		return _fail("NO_FREE_SLOT")
	if not container.accepted_tags.is_empty():
		var definition = item_registry.get_definition(item.definition_id)
		var accepted := false
		for tag in container.accepted_tags:
			if definition.has_tag(tag):
				accepted = true
				break
		if not accepted:
			return _fail("ITEM_TAG_REJECTED")
	if not owner_item_id.is_empty():
		if item.owns_container():
			var resulting_depth := get_nested_depth(owner_item_id) + 1
			if resulting_depth > container.maximum_nested_depth:
				return _fail("MAX_NESTED_DEPTH")
	return {"success": true}


func _validate_attachment_target(item, parent_item_id: String) -> Dictionary:
	if parent_item_id.is_empty() or item_registry.get_item(parent_item_id) == null:
		return _fail("ATTACHMENT_PARENT_NOT_FOUND")
	if parent_item_id == item.instance_id or _is_descendant(parent_item_id, item.instance_id):
		return _fail("RELATION_CYCLE")
	return {"success": true}


func _can_merge_into_container(item, container) -> bool:
	for existing_id in container.item_ids:
		var existing = item_registry.get_item(existing_id)
		if existing != null and existing.is_stack_compatible(item):
			var definition = item_registry.get_definition(item.definition_id)
			if existing.quantity < definition.max_stack:
				return true
	return false


func _is_descendant(candidate_item_id: String, ancestor_item_id: String) -> bool:
	var current_id := candidate_item_id
	var seen: Dictionary = {}
	while not current_id.is_empty() and not seen.has(current_id):
		if current_id == ancestor_item_id:
			return true
		seen[current_id] = true
		var current = item_registry.get_item(current_id)
		if current == null:
			return false
		current_id = Relations.relation_parent_item_id(current.relation, container_registry)
	return false


func _fail(code: String, extra: Dictionary = {}) -> Dictionary:
	var result := {"success": false, "error_code": code}
	result.merge(extra, true)
	return result

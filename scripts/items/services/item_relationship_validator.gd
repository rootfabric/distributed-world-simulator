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
		return _validate_container_target(
			item,
			String(new_relation.get("container_id", "")),
			int(new_relation.get("slot_index", -1))
		)
	if kind == Relations.ATTACHMENT:
		return _validate_attachment_target(item, String(new_relation.get("parent_item_id", "")))
	return {"success": true}


func validate_graph() -> Dictionary:
	var memberships: Dictionary = {}
	for container in container_registry.all_containers():
		if String(container.container_id).is_empty():
			return _fail("EMPTY_CONTAINER_ID")
		var parent_check := _validate_container_parent_chain(container)
		if not bool(parent_check.get("success", false)):
			return parent_check
		if container.owner_kind == "ITEM_INSTANCE":
			var owner = item_registry.get_item(container.owner_id)
			if owner == null:
				return _fail("CONTAINER_OWNER_NOT_FOUND", {"container_id": container.container_id, "owner_id": container.owner_id})
			if owner.get_owned_container_id() != container.container_id:
				return _fail("CONTAINER_OWNER_COMPONENT_MISMATCH", {"container_id": container.container_id, "owner_id": container.owner_id})
		var local_members: Dictionary = {}
		for item_id in container.item_ids:
			if local_members.has(item_id):
				return _fail("DUPLICATE_CONTAINER_MEMBERSHIP", {"container_id": container.container_id, "item_id": item_id})
			local_members[item_id] = true
			if memberships.has(item_id):
				return _fail("MULTIPLE_CONTAINER_MEMBERSHIP", {"item_id": item_id, "first_container_id": memberships[item_id], "second_container_id": container.container_id})
			memberships[item_id] = container.container_id
			var member = item_registry.get_item(item_id)
			if member == null:
				return _fail("CONTAINER_MEMBER_NOT_FOUND", {"container_id": container.container_id, "item_id": item_id})
			if Relations.kind_of(member.relation) != Relations.CONTAINER:
				return _fail("CONTAINER_MEMBER_RELATION_MISMATCH", {"container_id": container.container_id, "item_id": item_id})
			if String(member.relation.get("container_id", "")) != container.container_id:
				return _fail("CONTAINER_MEMBER_TARGET_MISMATCH", {"container_id": container.container_id, "item_id": item_id})
			if container.is_slot_container():
				var relation_slot := int(member.relation.get("slot_index", -1))
				if relation_slot < 0 or container.get_item_at_slot(relation_slot) != item_id:
					return _fail("ITEM_SLOT_ASSIGNMENT_MISMATCH", {"container_id": container.container_id, "item_id": item_id, "slot_index": relation_slot})
				var definition = item_registry.get_definition(member.definition_id)
				if definition == null or not container.can_accept_definition_in_slot(definition, relation_slot):
					return _fail("SLOT_ITEM_REJECTED", {"container_id": container.container_id, "item_id": item_id, "slot_index": relation_slot})
	for item in item_registry.all_items():
		var kind := Relations.kind_of(item.relation)
		if not [Relations.WORLD, Relations.CONTAINER, Relations.ATTACHMENT, Relations.DESTROYED].has(kind):
			return _fail("INVALID_RELATION", {"item_id": item.instance_id})
		if kind == Relations.CONTAINER:
			var target_container_id := String(item.relation.get("container_id", ""))
			if container_registry.get_container(target_container_id) == null:
				return _fail("CONTAINER_NOT_FOUND", {"item_id": item.instance_id, "container_id": target_container_id})
			if String(memberships.get(item.instance_id, "")) != target_container_id:
				return _fail("ITEM_CONTAINER_MEMBERSHIP_MISSING", {"item_id": item.instance_id, "container_id": target_container_id})
		elif kind == Relations.ATTACHMENT:
			var parent_item_id := String(item.relation.get("parent_item_id", ""))
			if parent_item_id.is_empty() or item_registry.get_item(parent_item_id) == null:
				return _fail("ATTACHMENT_PARENT_NOT_FOUND", {"item_id": item.instance_id, "parent_item_id": parent_item_id})
		if item.owns_container():
			var owned_container_id: String = String(item.get_owned_container_id())
			var owned_container = container_registry.get_container(owned_container_id)
			if owned_container == null:
				return _fail("OWNED_CONTAINER_NOT_FOUND", {"item_id": item.instance_id, "container_id": owned_container_id})
			if owned_container.owner_kind != "ITEM_INSTANCE" or owned_container.owner_id != item.instance_id:
				return _fail("OWNED_CONTAINER_BACK_REFERENCE_MISMATCH", {"item_id": item.instance_id, "container_id": owned_container_id})
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
	var seen: Dictionary = {}
	while current != null and not seen.has(current.instance_id):
		seen[current.instance_id] = true
		var parent_id := Relations.relation_parent_item_id(current.relation, container_registry)
		if parent_id.is_empty():
			break
		depth += 1
		current = item_registry.get_item(parent_id)
	return depth


func _validate_container_target(item, container_id: String, requested_slot_index: int = -1) -> Dictionary:
	var container = container_registry.get_container(container_id)
	if container == null:
		return _fail("CONTAINER_NOT_FOUND")
	var definition = item_registry.get_definition(item.definition_id)
	if definition == null:
		return _fail("ITEM_DEFINITION_NOT_FOUND")
	var owner_item_id: String = String(container.owner_id) if container.owner_kind == "ITEM_INSTANCE" else ""
	if not owner_item_id.is_empty():
		if owner_item_id == item.instance_id or _is_descendant(owner_item_id, item.instance_id):
			return _fail("RELATION_CYCLE")
	if item.owns_container() and not container.allow_nested_containers:
		return _fail("NESTED_CONTAINERS_FORBIDDEN")
	if not container.accepted_definition_ids.is_empty() and not container.accepted_definition_ids.has(item.definition_id):
		return _fail("ITEM_DEFINITION_REJECTED")
	if not container.accepted_tags.is_empty():
		var accepted := false
		for tag in container.accepted_tags:
			if definition.has_tag(String(tag)):
				accepted = true
				break
		if not accepted:
			return _fail("ITEM_TAG_REJECTED")
	var already_member: bool = (
		Relations.kind_of(item.relation) == Relations.CONTAINER
		and String(item.relation.get("container_id", "")) == container_id
		and container.item_ids.has(item.instance_id)
	)
	if container.is_slot_container():
		var resolved_slot := requested_slot_index
		if resolved_slot < 0 and already_member:
			resolved_slot = container.get_slot_for_item(item.instance_id)
		if resolved_slot < 0:
			for slot_index in range(container.slot_count):
				if not container.slot_assignments.has(slot_index) and container.can_accept_definition_in_slot(definition, slot_index):
					resolved_slot = slot_index
					break
		if resolved_slot < 0 or resolved_slot >= container.slot_count:
			return _fail("NO_COMPATIBLE_SLOT")
		var occupying_item_id := String(container.get_item_at_slot(resolved_slot))
		if not occupying_item_id.is_empty() and occupying_item_id != item.instance_id:
			var occupying_item = item_registry.get_item(occupying_item_id)
			if occupying_item == null or not occupying_item.is_stack_compatible(item):
				return _fail("SLOT_OCCUPIED")
			if int(occupying_item.quantity) + int(item.quantity) > int(definition.max_stack):
				return _fail("SLOT_STACK_LIMIT")
		if not container.can_accept_definition_in_slot(definition, resolved_slot):
			return _fail("SLOT_ITEM_REJECTED")
	elif not container.has_free_slot() and not _can_merge_into_container(item, container):
		if not already_member:
			return _fail("NO_FREE_SLOT")
	if not owner_item_id.is_empty() and item.owns_container():
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


func _validate_container_parent_chain(container) -> Dictionary:
	if String(container.parent_container_id).is_empty():
		return {"success": true}
	if container.parent_container_id == container.container_id:
		return _fail("CONTAINER_PARENT_CYCLE", {"container_id": container.container_id})
	if container_registry.get_container(container.parent_container_id) == null:
		return _fail("PARENT_CONTAINER_NOT_FOUND", {"container_id": container.container_id, "parent_container_id": container.parent_container_id})
	var seen: Dictionary = {container.container_id: true}
	var parent_id: String = container.parent_container_id
	while not parent_id.is_empty():
		if seen.has(parent_id):
			return _fail("CONTAINER_PARENT_CYCLE", {"container_id": container.container_id})
		seen[parent_id] = true
		var parent = container_registry.get_container(parent_id)
		if parent == null:
			break
		parent_id = String(parent.parent_container_id)
	return {"success": true}


func _is_descendant(candidate_parent_id: String, possible_ancestor_id: String) -> bool:
	var current_id := candidate_parent_id
	var seen: Dictionary = {}
	while not current_id.is_empty() and not seen.has(current_id):
		if current_id == possible_ancestor_id:
			return true
		seen[current_id] = true
		var current = item_registry.get_item(current_id)
		if current == null:
			break
		current_id = Relations.relation_parent_item_id(current.relation, container_registry)
	return false


func _can_merge_into_container(item, container) -> bool:
	var definition = item_registry.get_definition(item.definition_id)
	if definition == null:
		return false
	var available_total: int = 0
	for existing_id in container.item_ids:
		if String(existing_id) == String(item.instance_id):
			continue
		var existing = item_registry.get_item(existing_id)
		if existing != null and existing.is_stack_compatible(item):
			available_total += maxi(0, int(definition.max_stack) - int(existing.quantity))
			if available_total >= int(item.quantity):
				return true
	return false


func _fail(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}

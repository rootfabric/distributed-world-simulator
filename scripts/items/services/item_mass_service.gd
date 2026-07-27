extends RefCounted

var item_registry
var container_registry


func setup(new_item_registry, new_container_registry) -> void:
	item_registry = new_item_registry
	container_registry = new_container_registry


func item_recursive_mass_kg(item_id: String) -> float:
	return _item_recursive_mass_kg(item_id, {}, {})


func container_mass_kg(container_id: String) -> float:
	return _container_mass_kg(container_id, {}, {})


func item_external_volume_l(item_id: String) -> float:
	var item = item_registry.get_item(item_id)
	if item == null:
		return 0.0
	var definition = item_registry.get_definition(item.definition_id)
	if definition == null:
		return 0.0
	return definition.external_volume_l * float(item.quantity)


func container_direct_volume_l(container_id: String) -> float:
	var container = container_registry.get_container(container_id)
	if container == null:
		return 0.0
	var total := 0.0
	for item_id in container.item_ids:
		total += item_external_volume_l(item_id)
	return total


func _item_recursive_mass_kg(item_id: String, seen_items: Dictionary, seen_containers: Dictionary) -> float:
	if seen_items.has(item_id):
		return 0.0
	seen_items[item_id] = true
	var item = item_registry.get_item(item_id)
	if item == null:
		return 0.0
	var definition = item_registry.get_definition(item.definition_id)
	if definition == null:
		return 0.0
	var total: float = float(definition.unit_mass_kg) * float(item.quantity)
	var owned_container_id: String = String(item.get_owned_container_id())
	if not owned_container_id.is_empty():
		total += _container_mass_kg(owned_container_id, seen_items, seen_containers)
	return total


func _container_mass_kg(container_id: String, seen_items: Dictionary, seen_containers: Dictionary) -> float:
	if seen_containers.has(container_id):
		return 0.0
	seen_containers[container_id] = true
	var container = container_registry.get_container(container_id)
	if container == null:
		return 0.0
	var total := 0.0
	for item_id in container.item_ids:
		total += _item_recursive_mass_kg(item_id, seen_items, seen_containers)
	# Child containers such as the player hotbar are part of their parent even
	# when they are not themselves represented by an ItemInstance.
	for child in container_registry.all_containers():
		if String(child.parent_container_id) == container_id:
			total += _container_mass_kg(child.container_id, seen_items, seen_containers)
	return total

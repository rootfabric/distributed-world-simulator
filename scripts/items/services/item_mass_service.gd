extends RefCounted

var item_registry
var container_registry


func setup(new_item_registry, new_container_registry) -> void:
	item_registry = new_item_registry
	container_registry = new_container_registry


func item_recursive_mass_kg(item_id: String) -> float:
	return _item_recursive_mass_kg(item_id, {})


func container_mass_kg(container_id: String) -> float:
	return _container_mass_kg(container_id, {})


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
	var total = 0.0
	for item_id in container.item_ids:
		total += item_external_volume_l(item_id)
	return total


func _item_recursive_mass_kg(item_id: String, seen: Dictionary) -> float:
	if seen.has(item_id):
		return 0.0
	seen[item_id] = true
	var item = item_registry.get_item(item_id)
	if item == null:
		return 0.0
	var definition = item_registry.get_definition(item.definition_id)
	if definition == null:
		return 0.0
	var total = definition.unit_mass_kg * float(item.quantity)
	var owned_container_id = item.get_owned_container_id()
	if not owned_container_id.is_empty():
		total += _container_mass_kg(owned_container_id, seen)
	return total


func _container_mass_kg(container_id: String, seen: Dictionary) -> float:
	var container = container_registry.get_container(container_id)
	if container == null:
		return 0.0
	var total = 0.0
	for item_id in container.item_ids:
		total += _item_recursive_mass_kg(item_id, seen)
	return total

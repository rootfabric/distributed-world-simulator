extends RefCounted

const ItemDefinitionScript = preload("res://scripts/items/domain/item_definition.gd")
const ItemInstanceScript = preload("res://scripts/items/domain/item_instance.gd")

var definitions: Dictionary = {}
var items: Dictionary = {}
var _sequence: int = 1


func register_definition(definition) -> void:
	assert(definition != null)
	assert(not String(definition.id).is_empty())
	definitions[definition.id] = definition


func create_item(definition_id: String, quantity: int = 1, components: Dictionary = {}, relation: Dictionary = {}) -> Variant:
	var definition = get_definition(definition_id)
	if definition == null:
		return null
	if quantity < 1 or quantity > definition.max_stack:
		return null
	var item_id = _next_id(definition_id)
	var item = ItemInstanceScript.new({
		"instance_id": item_id,
		"definition_id": definition_id,
		"quantity": quantity,
		"components": components,
		"relation": relation,
	})
	items[item_id] = item
	return item


func add_item(item) -> bool:
	if item == null or String(item.instance_id).is_empty():
		return false
	if items.has(item.instance_id):
		return false
	if get_definition(item.definition_id) == null:
		return false
	items[item.instance_id] = item
	return true


func remove_item(item_id: String) -> bool:
	return items.erase(item_id)


func get_item(item_id: String) -> Variant:
	return items.get(item_id)


func get_definition(definition_id: String) -> Variant:
	return definitions.get(definition_id)


func all_items() -> Array:
	return items.values()


func to_dict() -> Dictionary:
	var definition_rows: Array = []
	for definition in definitions.values():
		definition_rows.append(definition.to_dict())
	var item_rows: Array = []
	for item in items.values():
		item_rows.append(item.to_dict())
	return {
		"sequence": _sequence,
		"definitions": definition_rows,
		"items": item_rows,
	}


func load_dict(data: Dictionary) -> void:
	definitions.clear()
	items.clear()
	_sequence = maxi(1, int(data.get("sequence", 1)))
	for definition_data in data.get("definitions", []):
		register_definition(ItemDefinitionScript.new(Dictionary(definition_data)))
	for item_data in data.get("items", []):
		var item = ItemInstanceScript.new(Dictionary(item_data))
		items[item.instance_id] = item


func _next_id(prefix: String) -> String:
	var result = "%s_%06d" % [prefix, _sequence]
	_sequence += 1
	return result

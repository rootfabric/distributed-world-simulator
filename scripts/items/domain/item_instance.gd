extends RefCounted

const ItemRelationsScript = preload("res://scripts/items/domain/item_relations.gd")

const SCHEMA: String = "planet_simulator.item_instance.v2"
const SCHEMA_VERSION: int = 2

var instance_id: String = ""
var definition_id: String = ""
var display_name: String = ""
var quantity: int = 1
var relation: Dictionary = {}
var components: Dictionary = {}
var revision: int = 0


func _init(data: Dictionary = {}) -> void:
	instance_id = String(data.get("instance_id", ""))
	definition_id = String(data.get("definition_id", ""))
	display_name = String(data.get("display_name", ""))
	quantity = maxi(1, int(data.get("quantity", 1)))
	var relation_value = data.get("relation", {})
	set_relation(
		Dictionary(relation_value)
		if relation_value is Dictionary
		else {}
	)
	var components_value = data.get("components", {})
	components = (
		Dictionary(components_value).duplicate(true)
		if components_value is Dictionary
		else {}
	)
	revision = maxi(0, int(data.get("revision", 0)))


func set_relation(value: Dictionary) -> void:
	relation = ItemRelationsScript.canonicalize(value)


func owns_container() -> bool:
	return components.has("container") and components["container"] is Dictionary


func get_owned_container_id() -> String:
	if not owns_container():
		return ""
	return String(Dictionary(components["container"]).get("container_id", ""))


func is_stack_compatible(other) -> bool:
	if other == null:
		return false
	if definition_id != String(other.definition_id):
		return false
	if display_name != String(other.display_name):
		return false
	if owns_container() or bool(other.owns_container()):
		return false
	return components == Dictionary(other.components)


func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA,
		"schema_version": SCHEMA_VERSION,
		"instance_id": instance_id,
		"definition_id": definition_id,
		"display_name": display_name,
		"quantity": quantity,
		"relation": ItemRelationsScript.canonicalize(relation),
		"components": components.duplicate(true),
		"revision": revision,
	}

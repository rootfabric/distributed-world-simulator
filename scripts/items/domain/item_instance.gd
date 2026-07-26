extends RefCounted

var instance_id: String = ""
var definition_id: String = ""
var quantity: int = 1
var relation: Dictionary = {}
var components: Dictionary = {}
var revision: int = 0


func _init(data: Dictionary = {}) -> void:
	instance_id = String(data.get("instance_id", ""))
	definition_id = String(data.get("definition_id", ""))
	quantity = maxi(1, int(data.get("quantity", 1)))
	relation = Dictionary(data.get("relation", {})).duplicate(true)
	components = Dictionary(data.get("components", {})).duplicate(true)
	revision = int(data.get("revision", 0))


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
	if owns_container() or bool(other.owns_container()):
		return false
	return components == Dictionary(other.components)


func to_dict() -> Dictionary:
	return {
		"instance_id": instance_id,
		"definition_id": definition_id,
		"quantity": quantity,
		"relation": relation.duplicate(true),
		"components": components.duplicate(true),
		"revision": revision,
	}

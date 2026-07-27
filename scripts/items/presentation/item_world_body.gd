extends RigidBody3D

const INTERACTABLE_GROUP: StringName = &"world_interactable"

var gameplay_controller
var item_instance_id: String = ""
var focused: bool = false
var outline_material: StandardMaterial3D


func _ready() -> void:
	add_to_group(INTERACTABLE_GROUP)


func setup_interaction(controller, item_id: String) -> void:
	gameplay_controller = controller
	item_instance_id = item_id
	add_to_group(INTERACTABLE_GROUP)


func get_interaction_descriptor(_actor = null) -> Dictionary:
	if gameplay_controller == null:
		return {}
	var item = gameplay_controller.get_item(item_instance_id)
	if item == null:
		return {}
	var definition = gameplay_controller.get_definition(item.definition_id)
	var owns_container := bool(item.owns_container())
	return {
		"schema": "planet_simulator.item_interaction.v1",
		"entity_id": item_instance_id,
		"entity_type": "item_container" if owns_container else "item",
		"title": String(definition.display_name) if definition != null else item.display_name,
		"details": "Количество: %d\nМасса: %.2f кг" % [item.quantity, gameplay_controller.get_item_mass_kg(item_instance_id)],
		"prompt": "E — открыть контейнер" if owns_container else "E — подобрать",
	}


func interact(_actor = null, _context: Dictionary = {}) -> Dictionary:
	if gameplay_controller == null:
		return {"success": false, "message": "Предметная система недоступна"}
	return gameplay_controller.interact_world_item(item_instance_id)


func set_interaction_focus(value: bool) -> void:
	focused = value
	if outline_material == null:
		outline_material = StandardMaterial3D.new()
		outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		outline_material.albedo_color = Color(0.25, 0.75, 1.0, 0.65)
		outline_material.emission_enabled = true
		outline_material.emission = Color(0.1, 0.55, 1.0)
		outline_material.emission_energy_multiplier = 1.2
		outline_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		outline_material.cull_mode = BaseMaterial3D.CULL_FRONT
		outline_material.grow = true
		outline_material.grow_amount = 0.025
	for child in get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_overlay = outline_material if value else null

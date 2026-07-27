extends StaticBody3D

const INTERACTABLE_GROUP: StringName = &"world_interactable"

var gameplay_controller
var assembly_id: String = ""
var socket_id: String = ""
var fixture_item_id: String = ""


func _ready() -> void:
	add_to_group(INTERACTABLE_GROUP)


func setup_socket(
	controller,
	configured_assembly_id: String,
	configured_socket_id: String,
	configured_fixture_item_id: String = ""
) -> void:
	gameplay_controller = controller
	assembly_id = configured_assembly_id
	socket_id = configured_socket_id
	fixture_item_id = configured_fixture_item_id
	add_to_group(INTERACTABLE_GROUP)


func get_interaction_descriptor(_actor = null) -> Dictionary:
	var state: Dictionary = gameplay_controller.get_socket_state(assembly_id, socket_id) if gameplay_controller != null else {}
	var occupied := not String(state.get("item_id", "")).is_empty()
	return {
		"schema": "planet_simulator.mount_socket_interaction.v1",
		"entity_id": "%s/%s" % [assembly_id, socket_id],
		"entity_type": "mount_socket",
		"title": "Монтажное гнездо маяка",
		"details": (
			("Занято" if occupied else "Свободно — выберите маяк на панели 1–0")
			+ ("\nОснование: предмет %s" % fixture_item_id if not fixture_item_id.is_empty() else "")
		),
		"prompt": "E — снять в рюкзак" if occupied else "E — установить выбранный маяк",
	}


func interact(_actor = null, _context: Dictionary = {}) -> Dictionary:
	if gameplay_controller == null:
		return {"success": false, "message": "Предметная система недоступна"}
	var state: Dictionary = gameplay_controller.get_socket_state(assembly_id, socket_id)
	if not String(state.get("item_id", "")).is_empty():
		return gameplay_controller.detach_socket_to_inventory(assembly_id, socket_id)
	return gameplay_controller.mount_selected_item(assembly_id, socket_id)


func set_interaction_focus(_value: bool) -> void:
	pass

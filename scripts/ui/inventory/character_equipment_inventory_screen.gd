class_name CharacterEquipmentInventoryScreen
extends "res://scripts/ui/inventory/inventory_screen.gd"

const ContainerPanelScene = preload("res://scenes/ui/inventory/container_panel.tscn")

var equipment_panel: InventoryContainerPanel


func setup(
	controller,
	model: InventoryViewModel,
	commands: InventoryCommandFacade,
	profile_override: String = ""
) -> void:
	_ensure_equipment_panel()
	super.setup(controller, model, commands, profile_override)
	if equipment_panel != null:
		equipment_panel.set_visual_role("equipment")
		equipment_panel.set_interaction_profile(active_interaction_profile)
		_wire_panel(equipment_panel)
	_requested_panel_size.x = maxf(_requested_panel_size.x, 1260.0)
	refresh()


func refresh(message: String = "") -> void:
	super.refresh(message)
	if equipment_panel == null or gameplay_controller == null or view_model == null:
		return
	var equipment_container_id := ""
	if gameplay_controller.has_method("get_character_equipment_container_id"):
		equipment_container_id = String(gameplay_controller.call("get_character_equipment_container_id"))
	if equipment_container_id.is_empty():
		equipment_panel.clear_panel()
		return
	var model: Dictionary = view_model.build_container(equipment_container_id)
	if model.is_empty():
		equipment_panel.clear_panel()
		return
	model["display_name"] = "Экипировка"
	model["columns"] = 2
	equipment_panel.render(
		model,
		Callable(self, "_icon_for_cell"),
		Callable(self, "_preview_equipment_drop")
	)
	equipment_panel.visible = true
	set_meta("character_equipment_container_id", equipment_container_id)


func create_debug_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.create_debug_snapshot()
	snapshot["character_equipment"] = {
		"container_id": equipment_panel.container_id if equipment_panel != null else "",
		"visible": equipment_panel.visible if equipment_panel != null else false,
		"model": equipment_panel.current_model.duplicate(true) if equipment_panel != null else {},
	}
	return snapshot


func _on_drop_requested(
	item_id: String,
	target_container_id: String,
	target_slot_index: int,
	quantity: int = -1,
	target_item_id: String = ""
) -> void:
	var equipment_container_id := _equipment_container_id()
	if not equipment_container_id.is_empty() and target_container_id == equipment_container_id:
		var result: Dictionary = gameplay_controller.call(
			"equip_character_item",
			item_id,
			target_slot_index,
			quantity
		)
		_present_result(result, target_container_id, "Надето: %s" % String(_cell_data_for_item(item_id).get("display_name", "Предмет")))
		return
	var source_item = gameplay_controller.get_item(item_id) if gameplay_controller != null else null
	if source_item != null and not equipment_container_id.is_empty():
		var source_relation: Dictionary = Dictionary(source_item.relation)
		if (
			String(source_relation.get("kind", "")) == "CONTAINER"
			and String(source_relation.get("container_id", "")) == equipment_container_id
		):
			var result: Dictionary = gameplay_controller.call(
				"unequip_character_item",
				item_id,
				target_container_id,
				target_slot_index
			)
			_present_result(result, target_container_id, "Снято: %s" % String(_cell_data_for_item(item_id).get("display_name", "Предмет")))
			return
	super._on_drop_requested(item_id, target_container_id, target_slot_index, quantity, target_item_id)


func _on_quantity_drop_requested(
	item_id: String,
	target_container_id: String,
	target_slot_index: int,
	total_quantity: int,
	target_item_id: String
) -> void:
	if target_container_id == _equipment_container_id():
		_on_drop_requested(item_id, target_container_id, target_slot_index, total_quantity, target_item_id)
		return
	super._on_quantity_drop_requested(item_id, target_container_id, target_slot_index, total_quantity, target_item_id)


func _panel_for_container(container_id: String) -> InventoryContainerPanel:
	if equipment_panel != null and container_id == equipment_panel.container_id:
		return equipment_panel
	return super._panel_for_container(container_id)


func _cell_data_for_item(item_id: String) -> Dictionary:
	if equipment_panel != null:
		for value in equipment_panel.current_model.get("cells", []):
			var cell: Dictionary = Dictionary(value)
			if String(cell.get("item_id", "")) == item_id:
				return cell.duplicate(true)
	return super._cell_data_for_item(item_id)


func _preview_equipment_drop(
	item_id: String,
	quantity: int,
	target_container_id: String,
	target_slot_index: int,
	_target_item_id: String = ""
) -> Dictionary:
	if gameplay_controller == null or not gameplay_controller.has_method("preview_character_equipment"):
		return {"success": false, "error_code": "CHARACTER_EQUIPMENT_NOT_CONFIGURED"}
	if target_container_id != _equipment_container_id():
		return command_facade.preview_transfer(item_id, quantity, target_container_id, target_slot_index)
	return gameplay_controller.call("preview_character_equipment", item_id, target_slot_index, quantity)


func _equipment_container_id() -> String:
	if gameplay_controller == null or not gameplay_controller.has_method("get_character_equipment_container_id"):
		return ""
	return String(gameplay_controller.call("get_character_equipment_container_id"))


func _ensure_equipment_panel() -> void:
	if equipment_panel != null:
		return
	var instance = ContainerPanelScene.instantiate()
	if not instance is InventoryContainerPanel:
		if instance is Node:
			(instance as Node).free()
		return
	equipment_panel = instance as InventoryContainerPanel
	equipment_panel.name = "EquipmentPanel"
	equipment_panel.custom_minimum_size = Vector2(230.0, 0.0)
	columns.add_child(equipment_panel)
	columns.move_child(equipment_panel, 0)
	equipment_panel.visible = false

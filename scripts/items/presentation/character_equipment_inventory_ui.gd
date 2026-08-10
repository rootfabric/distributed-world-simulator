class_name CharacterEquipmentInventoryUI
extends "res://scripts/items/presentation/item_inventory_ui.gd"

const EquipmentScreenScene = preload("res://scenes/ui/inventory/character_equipment_inventory_screen.tscn")
const EquipmentViewModel = preload("res://scripts/ui/inventory/inventory_view_model.gd")
const EquipmentCommandFacade = preload("res://scripts/ui/inventory/inventory_command_facade.gd")


func setup(
	controller,
	implementation_override: String = "component",
	interaction_profile_override: String = ""
) -> void:
	gameplay_controller = controller
	implementation_id = COMPONENT_IMPLEMENTATION
	view_model = EquipmentViewModel.new()
	command_facade = EquipmentCommandFacade.new()
	active_screen = EquipmentScreenScene.instantiate()
	add_child(active_screen)
	active_screen.setup(controller, view_model, command_facade, interaction_profile_override)
	_setup_persistent_hotbar()

class_name FirstPersonCharacterEquipmentInventoryUI
extends "res://scripts/items/presentation/character_equipment_inventory_ui.gd"

const ResearchEquipmentScreenScene = preload("res://scenes/ui/inventory/first_person_character_equipment_inventory_screen.tscn")
const ResearchViewModel = preload("res://scripts/ui/inventory/inventory_view_model.gd")
const ResearchCommandFacade = preload("res://scripts/ui/inventory/inventory_command_facade.gd")


func setup(
	controller,
	implementation_override: String = "component",
	interaction_profile_override: String = ""
) -> void:
	gameplay_controller = controller
	implementation_id = "component"
	view_model = ResearchViewModel.new()
	command_facade = ResearchCommandFacade.new()
	active_screen = ResearchEquipmentScreenScene.instantiate()
	add_child(active_screen)
	active_screen.setup(controller, view_model, command_facade, interaction_profile_override)
	_setup_persistent_hotbar()


func create_fpe_equipment_ui_report() -> Dictionary:
	if active_screen != null and active_screen.has_method("create_fpe_equipment_ui_report"):
		return active_screen.call("create_fpe_equipment_ui_report")
	return {
		"schema": "planet_simulator.first_person_character_equipment_inventory_ui.v1",
		"recovered_false_negatives": 0,
		"changes_network_authority": false,
		"changes_item_authority": false,
	}

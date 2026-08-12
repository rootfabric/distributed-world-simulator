class_name FirstPersonCharacterEquipmentInventoryScreen
extends "res://scripts/ui/inventory/character_equipment_inventory_screen.gd"

const ResultPolicyType = preload("res://scripts/characters/interaction/first_person_equipment_result_policy.gd")

var _fpe_result_policy = ResultPolicyType.new()
var _fpe_recovered_false_negatives := 0
var _fpe_last_presentation_warning: Dictionary = {}


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
		result = _normalize_fpe_equipment_result(
			result,
			item_id,
			target_container_id,
			target_slot_index,
			true
		)
		var success_message := "Надето: %s" % String(_cell_data_for_item(item_id).get("display_name", "Предмет"))
		if bool(result.get("network_apply_false_negative_recovered", false)):
			success_message += " — сервер подтвердил, presentation warning сохранён"
		_present_result(result, target_container_id, success_message)
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
			# CH9.6 canonical unequip returns the item to the backpack and may choose a
			# deterministic presentation slot different from the graphical drop slot.
			result = _normalize_fpe_equipment_result(
				result,
				item_id,
				target_container_id,
				target_slot_index,
				false
			)
			var success_message := "Снято: %s" % String(_cell_data_for_item(item_id).get("display_name", "Предмет"))
			if bool(result.get("network_apply_false_negative_recovered", false)):
				success_message += " — сервер подтвердил, presentation warning сохранён"
			_present_result(result, target_container_id, success_message)
			return

	super._on_drop_requested(item_id, target_container_id, target_slot_index, quantity, target_item_id)


func _normalize_fpe_equipment_result(
	result: Dictionary,
	item_id: String,
	target_container_id: String,
	target_slot_index: int,
	require_slot_match: bool
) -> Dictionary:
	if bool(result.get("success", false)) or gameplay_controller == null:
		return result
	var item = gameplay_controller.get_item(item_id)
	var relation: Dictionary = Dictionary(item.relation) if item != null else {}
	var normalized: Dictionary = _fpe_result_policy.normalize(
		result,
		relation,
		target_container_id,
		target_slot_index,
		require_slot_match
	)
	if bool(normalized.get("network_apply_false_negative_recovered", false)):
		_fpe_recovered_false_negatives += 1
		var warning_value: Variant = normalized.get("presentation_warning", {})
		_fpe_last_presentation_warning = (
			Dictionary(warning_value).duplicate(true)
			if warning_value is Dictionary
			else {}
		)
	return normalized


func create_fpe_equipment_ui_report() -> Dictionary:
	return {
		"schema": "planet_simulator.first_person_character_equipment_inventory_screen.v1",
		"recovered_false_negatives": _fpe_recovered_false_negatives,
		"last_presentation_warning": _fpe_last_presentation_warning.duplicate(true),
		"changes_network_authority": false,
		"changes_item_authority": false,
	}

class_name CharacterEquipmentGameplayController
extends "res://scripts/items/presentation/item_gameplay_controller.gd"

const EquipmentOperationService = preload("res://scripts/characters/equipment/character_equipment_operation_service.gd")

const RESULT_EQUIPMENT_NOT_CONFIGURED := "CHARACTER_EQUIPMENT_NOT_CONFIGURED"
const RESULT_EQUIPMENT_NETWORK_DEFERRED := "CHARACTER_EQUIPMENT_NETWORK_DEFERRED"
const RESULT_EQUIPMENT_QUANTITY_INVALID := "CHARACTER_EQUIPMENT_QUANTITY_INVALID"
const RESULT_EQUIPMENT_PRESENTATION_FAILED := "CHARACTER_EQUIPMENT_PRESENTATION_FAILED"

var character_equipment_container_id: String = ""
var character_equipment_source: ItemGraphEquipmentSource
var character_equipment_operations: CharacterEquipmentOperationService
var character_equipment_presenter: CharacterEquipmentPresenter
var character_body_suppression_coordinator
var character_body_topology_coordinator
var character_equipment_last_result: Dictionary = {}


func configure_character_equipment(
	equipment_container_id: String,
	equipment_source: ItemGraphEquipmentSource,
	operation_service: CharacterEquipmentOperationService,
	equipment_presenter: CharacterEquipmentPresenter,
	body_suppression_coordinator = null,
	body_topology_coordinator = null
) -> Dictionary:
	character_equipment_container_id = equipment_container_id.strip_edges()
	character_equipment_source = equipment_source
	character_equipment_operations = operation_service
	character_equipment_presenter = equipment_presenter
	character_body_suppression_coordinator = body_suppression_coordinator
	character_body_topology_coordinator = body_topology_coordinator
	if (
		character_equipment_container_id.is_empty()
		or get_container(character_equipment_container_id) == null
		or character_equipment_source == null
		or character_equipment_operations == null
		or character_equipment_presenter == null
	):
		return _remember_character_equipment(_failure(RESULT_EQUIPMENT_NOT_CONFIGURED))
	var presentation_result: Dictionary = synchronize_character_equipment_presentation()
	if not bool(presentation_result.get("success", false)):
		return _remember_character_equipment(presentation_result)
	_refresh_ui()
	return _remember_character_equipment({
		"success": true,
		"code": "OK",
		"equipment_container_id": character_equipment_container_id,
		"mutation_owner": "ITEM_TRANSFER_SERVICE",
		"network_owner": false,
	})


func get_character_equipment_container_id() -> String:
	return character_equipment_container_id


func has_character_equipment() -> bool:
	return (
		not character_equipment_container_id.is_empty()
		and character_equipment_source != null
		and character_equipment_operations != null
		and character_equipment_presenter != null
	)


func is_character_equipment_container(container_id: String) -> bool:
	return has_character_equipment() and container_id == character_equipment_container_id


func preview_character_equipment(item_id: String, slot_index: int, quantity: int = -1) -> Dictionary:
	if not has_character_equipment():
		return _failure(RESULT_EQUIPMENT_NOT_CONFIGURED)
	var item = get_item(item_id)
	if item == null:
		return _failure("ITEM_NOT_FOUND")
	var requested_quantity: int = int(item.quantity) if quantity < 0 else quantity
	if requested_quantity != 1 or int(item.quantity) != 1:
		return _failure(RESULT_EQUIPMENT_QUANTITY_INVALID, {
			"requested_quantity": requested_quantity,
			"item_quantity": int(item.quantity),
		})
	var plan: Dictionary = character_equipment_operations.plan_equip_from_container(item_id, slot_index)
	if not bool(plan.get("success", false)):
		return _normalize_equipment_result(plan)
	var code: String = String(plan.get("code", ""))
	var details: Dictionary = Dictionary(plan.get("details", {})).duplicate(true)
	var mode: String = String(details.get("mode", ""))
	if code == EquipmentOperationService.RESULT_MULTI_ITEM_TRANSACTION_REQUIRED or mode == EquipmentOperationService.MODE_MULTI_ITEM_TRANSACTION_REQUIRED:
		return _failure(EquipmentOperationService.RESULT_MULTI_ITEM_TRANSACTION_REQUIRED, details)
	return {
		"success": true,
		"mode": mode,
		"maximum_quantity": 1,
		"target_container_id": character_equipment_container_id,
		"target_slot_index": slot_index,
		"target_item_id": String(details.get("replacement_item_id", "")),
		"replacement_item_ids": details.get("replacement_item_ids", []).duplicate(),
		"plan": plan.duplicate(true),
	}


func equip_character_item(item_id: String, slot_index: int, quantity: int = -1) -> Dictionary:
	if _uses_network_commands():
		return _remember_character_equipment(_failure(RESULT_EQUIPMENT_NETWORK_DEFERRED))
	var preview: Dictionary = preview_character_equipment(item_id, slot_index, quantity)
	if not bool(preview.get("success", false)):
		return _remember_character_equipment(preview)
	var item = get_item(item_id)
	if item == null:
		return _remember_character_equipment(_failure("ITEM_NOT_FOUND"))
	var mode: String = String(preview.get("mode", ""))
	var result: Dictionary
	if mode in [EquipmentOperationService.MODE_MOVE, EquipmentOperationService.MODE_NO_CHANGE]:
		result = character_equipment_operations.equip_strict(
			item_id,
			slot_index,
			_operation("character_equip"),
			int(item.revision)
		)
	elif mode == EquipmentOperationService.MODE_SWAP:
		var replaced_item_id: String = String(preview.get("target_item_id", ""))
		var replaced = get_item(replaced_item_id)
		if replaced == null:
			return _remember_character_equipment(_failure("ITEM_NOT_FOUND", {"item_id": replaced_item_id}))
		result = character_equipment_operations.replace_one_from_container(
			item_id,
			slot_index,
			replaced_item_id,
			_operation("character_equip_swap"),
			int(item.revision),
			int(replaced.revision)
		)
	else:
		return _remember_character_equipment(_failure(EquipmentOperationService.RESULT_MULTI_ITEM_TRANSACTION_REQUIRED))
	return _finish_character_equipment_operation(result, "Предмет надет")


func unequip_character_item(
	item_id: String,
	target_container_id: String,
	target_slot_index: int = -1
) -> Dictionary:
	if _uses_network_commands():
		return _remember_character_equipment(_failure(RESULT_EQUIPMENT_NETWORK_DEFERRED))
	if not has_character_equipment():
		return _remember_character_equipment(_failure(RESULT_EQUIPMENT_NOT_CONFIGURED))
	var item = get_item(item_id)
	if item == null:
		return _remember_character_equipment(_failure("ITEM_NOT_FOUND"))
	var result: Dictionary = character_equipment_operations.unequip_to_container(
		item_id,
		target_container_id,
		target_slot_index,
		_operation("character_unequip"),
		int(item.revision)
	)
	return _finish_character_equipment_operation(result, "Предмет снят")


func synchronize_character_equipment_presentation() -> Dictionary:
	if not has_character_equipment():
		return _failure(RESULT_EQUIPMENT_NOT_CONFIGURED)
	var refresh_result: Dictionary = character_equipment_source.refresh()
	if not bool(refresh_result.get("success", false)):
		return _failure(RESULT_EQUIPMENT_PRESENTATION_FAILED, {"stage": "SOURCE_REFRESH", "cause": refresh_result})
	var snapshot: CharacterEquipmentDomain.Snapshot = character_equipment_source.get_snapshot()
	var presenter_result: Dictionary = character_equipment_presenter.apply_snapshot(snapshot)
	if not bool(presenter_result.get("success", false)):
		return _failure(RESULT_EQUIPMENT_PRESENTATION_FAILED, {"stage": "PRESENTER", "cause": presenter_result})
	if character_body_suppression_coordinator != null:
		var suppression_result: Dictionary = character_body_suppression_coordinator.apply_snapshot(snapshot)
		if not bool(suppression_result.get("success", false)):
			return _failure(RESULT_EQUIPMENT_PRESENTATION_FAILED, {"stage": "BODY_SUPPRESSION", "cause": suppression_result})
	if character_body_topology_coordinator != null:
		var topology_result: Dictionary = character_body_topology_coordinator.apply_snapshot(snapshot)
		if not bool(topology_result.get("success", false)):
			return _failure(RESULT_EQUIPMENT_PRESENTATION_FAILED, {"stage": "BODY_TOPOLOGY", "cause": topology_result})
	return {
		"success": true,
		"code": "OK",
		"snapshot_fingerprint": snapshot.fingerprint(),
		"equipped_item_count": snapshot.entries().size(),
		"presenter": presenter_result,
	}


func get_container_display_name(container_id: String) -> String:
	if is_character_equipment_container(container_id):
		return "Экипировка персонажа"
	return super.get_container_display_name(container_id)


func result_message(result: Dictionary) -> String:
	var code: String = String(result.get("error_code", result.get("code", "")))
	var messages := {
		RESULT_EQUIPMENT_NOT_CONFIGURED: "Экипировка персонажа ещё не настроена.",
		RESULT_EQUIPMENT_NETWORK_DEFERRED: "Сетевая экипировка будет подключена на CH9.3.",
		RESULT_EQUIPMENT_QUANTITY_INVALID: "Надевать можно только один физический предмет.",
		RESULT_EQUIPMENT_PRESENTATION_FAILED: "Item Graph изменён, но внешний вид экипировки не удалось обновить.",
		EquipmentOperationService.RESULT_MULTI_ITEM_TRANSACTION_REQUIRED: "Этот комплект заменяет несколько вещей и требует общей атомарной транзакции.",
		EquipmentOperationService.RESULT_EQUIPMENT_REPLACEMENT_REQUIRED: "Слот экипировки занят несовместимым предметом.",
	}
	if messages.has(code):
		return String(messages[code])
	return super.result_message(result)


func create_character_equipment_debug_snapshot() -> Dictionary:
	return {
		"schema": "planet_simulator.character_equipment_gameplay_controller.v1",
		"configured": has_character_equipment(),
		"equipment_container_id": character_equipment_container_id,
		"source": character_equipment_source.create_report() if character_equipment_source != null else {},
		"operations": character_equipment_operations.create_report() if character_equipment_operations != null else {},
		"presenter": character_equipment_presenter.create_report() if character_equipment_presenter != null else {},
		"last_result": character_equipment_last_result.duplicate(true),
		"network_mutation_enabled": false,
	}


func _finish_character_equipment_operation(result: Dictionary, success_message: String) -> Dictionary:
	var normalized: Dictionary = _normalize_equipment_result(result)
	if not bool(normalized.get("success", false)):
		return _remember_character_equipment(normalized)
	var presentation_result: Dictionary = synchronize_character_equipment_presentation()
	if not bool(presentation_result.get("success", false)):
		return _remember_character_equipment(presentation_result)
	normalized["message"] = success_message
	normalized["character_equipment_presentation"] = presentation_result
	var final_result: Dictionary = _after_operation(normalized)
	return _remember_character_equipment(final_result)


func _normalize_equipment_result(result: Dictionary) -> Dictionary:
	var normalized: Dictionary = result.duplicate(true)
	if bool(normalized.get("success", false)):
		if not normalized.has("code"):
			normalized["code"] = "OK"
		return normalized
	var code: String = String(normalized.get("error_code", normalized.get("code", "UNKNOWN")))
	normalized["error_code"] = code
	if not normalized.has("code"):
		normalized["code"] = code
	return normalized


func _remember_character_equipment(result: Dictionary) -> Dictionary:
	character_equipment_last_result = result.duplicate(true)
	return result


func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"code": code,
		"error_code": code,
		"details": details.duplicate(true),
	}

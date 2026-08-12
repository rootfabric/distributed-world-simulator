class_name QuaterniusFirstPersonEmbodimentFix7
extends "res://scripts/characters/lab/quaternius_first_person_embodiment_lab.gd"

const ResearchInventoryUIType = preload("res://scripts/items/presentation/first_person_character_equipment_inventory_ui.gd")
const PROJECTION_HOTBAR_METADATA_ONLY := "HOTBAR_METADATA_ONLY"

var _research_inventory_ui_installed := false
var _hotbar_local_prediction_applies := 0
var _hotbar_local_prediction_clears := 0
var _hotbar_local_prediction_max_us := 0


func _process(delta: float) -> void:
	super._process(delta)
	_ensure_research_inventory_ui()


func _bind_network_projection_signal() -> void:
	if _network_projection_signal_bound or base_lab == null:
		return
	# Fix6 host classifies the canonical projection after it has been applied.
	# Listen there instead of the raw network bridge so hotbar metadata does not
	# dirty/rebuild the equipment lane.
	if base_lab.has_signal("fpe_canonical_projection_applied"):
		var callback := Callable(self, "_on_fpe_canonical_projection_applied")
		if not base_lab.is_connected("fpe_canonical_projection_applied", callback):
			base_lab.connect("fpe_canonical_projection_applied", callback)
		_network_projection_signal_bound = true
		_equipment_sync_dirty = true
		_hotbar_presentation_dirty = true
		return
	# Fail-safe fallback for an older host: retain the accepted projected signal.
	super._bind_network_projection_signal()


func _on_fpe_canonical_projection_applied(classification: String, _snapshot: Dictionary) -> void:
	_hotbar_presentation_dirty = true
	if classification != PROJECTION_HOTBAR_METADATA_ONLY:
		_equipment_sync_dirty = true


func _select_hotbar_nonblocking(index: int) -> Dictionary:
	if not _ensure_hotbar_network_adapter():
		return _failure("FPE_HOTBAR_NETWORK_NOT_READY")
	var controller = base_lab.character_gameplay_controller
	if controller == null:
		return _failure("FPE_HOTBAR_CONTROLLER_NOT_READY")

	var canonical_index: int = hotbar_network_adapter.canonical_selected_index()
	if int(controller.selected_hotbar_index) == index and canonical_index == index:
		return {
			"success": true,
			"code": "OK",
			"details": {"changed": false, "selected_hotbar_index": index},
		}

	var submitted: Dictionary = hotbar_network_adapter.submit(index)
	if not bool(submitted.get("success", false)):
		return submitted

	# Predict only presentation selection. Hotbar contents remain the currently
	# installed canonical replica; server authority still decides the selected
	# index. Apply the hand proxy synchronously in this input callback so RTT /
	# server tick never becomes visible as a half-second viewmodel delay.
	controller.selected_hotbar_index = index
	_refresh_persistent_hotbar_only()
	_hotbar_prediction_index = index
	var local_result: Dictionary = _apply_hotbar_presentation_for_index(index)
	if not bool(local_result.get("success", false)):
		_hotbar_presentation_dirty = true
	return submitted


func _poll_hotbar_authority() -> void:
	if hotbar_network_adapter == null or not hotbar_network_adapter.has_pending():
		return
	var polled: Dictionary = hotbar_network_adapter.poll()
	var details: Dictionary = Dictionary(polled.get("details", {}))
	if bool(polled.get("success", false)):
		if bool(details.get("confirmed", false)):
			_hotbar_prediction_index = -1
			_last_fpe_status_code = "HOTBAR_AUTHORITY_CONFIRMED"
			# Confirmation normally changes no presentation because local prediction
			# already applied it. Mark dirty only as a cheap consistency check.
			_hotbar_presentation_dirty = true
			_refresh_status()
		return
	if not bool(details.get("rollback_required", false)):
		return
	var canonical_index: int = int(details.get("canonical_selected_hotbar_index", -1))
	if canonical_index >= 0 and base_lab.character_gameplay_controller != null:
		base_lab.character_gameplay_controller.selected_hotbar_index = canonical_index
		_refresh_persistent_hotbar_only()
		_apply_hotbar_presentation_for_index(canonical_index)
	_hotbar_prediction_index = -1
	_last_fpe_status_code = String(polled.get("error_code", "FPE_HOTBAR_AUTHORITY_CONFIRM_TIMEOUT"))
	_refresh_status()


func _sync_authoritative_hotbar_presentation() -> void:
	if base_lab == null or not bool(base_lab.network_ready):
		_hotbar_presentation_dirty = true
		return
	var controller = base_lab.character_gameplay_controller
	if controller == null:
		_hotbar_presentation_dirty = true
		return
	_apply_hotbar_presentation_for_index(int(controller.selected_hotbar_index))


func _apply_hotbar_presentation_for_index(index: int) -> Dictionary:
	var started_us := Time.get_ticks_usec()
	if base_lab == null or base_lab.character_gameplay_controller == null:
		return _failure("FPE_HOTBAR_CONTROLLER_NOT_READY")
	if first_person_embodiment == null:
		return _failure("FPE_EMBODIMENT_NOT_READY")
	var controller = base_lab.character_gameplay_controller
	var hotbar = controller.get_container(controller.player_hotbar_id)
	if hotbar == null or index < 0 or index >= int(hotbar.slot_count):
		return _failure("FPE_HOTBAR_SLOT_UNAVAILABLE", {"index": index})

	var selected_item_id: String = String(hotbar.get_item_at_slot(index))
	if selected_item_id == _last_hotbar_item_id:
		_record_hotbar_prediction_cost(started_us)
		return {
			"success": true,
			"code": "OK",
			"details": {"changed": false, "item_id": selected_item_id, "index": index},
		}

	var previous_item_id := _last_hotbar_item_id
	_last_hotbar_item_id = selected_item_id
	_hotbar_sync_runs += 1
	_hotbar_local_prediction_applies += 1
	if selected_item_id.is_empty():
		var cleared: Dictionary = first_person_embodiment.clear_authoritative_hand_item("right")
		if bool(cleared.get("success", false)):
			_hotbar_local_prediction_clears += 1
		_record_hotbar_prediction_cost(started_us)
		return cleared

	var item: Variant = controller.get_item(selected_item_id)
	if item == null:
		# Never retain a stale old item if the newly selected replica item cannot
		# be resolved. Empty hand is the safe presentation fallback.
		_last_hotbar_item_id = ""
		first_person_embodiment.clear_authoritative_hand_item("right")
		_hotbar_local_prediction_clears += 1
		_record_hotbar_prediction_cost(started_us)
		return _failure("FPE_SELECTED_HOTBAR_ITEM_MISSING", {
			"index": index,
			"item_id": selected_item_id,
			"previous_item_id": previous_item_id,
		})
	var definition: Variant = controller.get_definition(String(item.definition_id))
	var display_name: String = String(item.definition_id)
	var item_color := Color(0.65, 0.68, 0.72, 1.0)
	if definition != null:
		display_name = String(definition.display_name)
		item_color = _metadata_color(definition.metadata, item_color)
	var applied: Dictionary = first_person_embodiment.set_authoritative_hand_item(
		"right",
		selected_item_id,
		display_name,
		item_color
	)
	_record_hotbar_prediction_cost(started_us)
	return applied


func _record_hotbar_prediction_cost(started_us: int) -> void:
	_hotbar_local_prediction_max_us = maxi(
		_hotbar_local_prediction_max_us,
		maxi(Time.get_ticks_usec() - started_us, 0)
	)


func _ensure_research_inventory_ui() -> void:
	if _research_inventory_ui_installed or base_lab == null or not bool(base_lab.network_ready):
		return
	var controller = base_lab.character_gameplay_controller
	if controller == null:
		return
	var current_ui = controller.inventory_ui
	if current_ui != null and current_ui is FirstPersonCharacterEquipmentInventoryUI:
		_research_inventory_ui_installed = true
		base_lab.character_inventory_ui = current_ui
		return

	var was_visible := bool(controller.inventory_open)
	if current_ui != null and is_instance_valid(current_ui):
		if current_ui.get_parent() != null:
			current_ui.get_parent().remove_child(current_ui)
		current_ui.queue_free()

	var replacement = ResearchInventoryUIType.new()
	replacement.name = "FPECharacterEquipmentInventoryUI"
	controller.add_child(replacement)
	controller.inventory_ui = replacement
	base_lab.character_inventory_ui = replacement
	replacement.setup(controller, "component", "planet_default")
	replacement.set_inventory_visible(was_visible)
	_research_inventory_ui_installed = true


func get_first_person_embodiment_debug_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_first_person_embodiment_debug_snapshot()
	var ui_report: Dictionary = {}
	if (
		base_lab != null
		and base_lab.character_gameplay_controller != null
		and base_lab.character_gameplay_controller.inventory_ui != null
		and base_lab.character_gameplay_controller.inventory_ui.has_method("create_fpe_equipment_ui_report")
	):
		ui_report = base_lab.character_gameplay_controller.inventory_ui.call("create_fpe_equipment_ui_report")
	snapshot["fix7"] = {
		"research_inventory_ui_installed": _research_inventory_ui_installed,
		"hotbar_local_prediction_applies": _hotbar_local_prediction_applies,
		"hotbar_local_prediction_clears": _hotbar_local_prediction_clears,
		"hotbar_local_prediction_max_us": _hotbar_local_prediction_max_us,
		"equipment_ui": ui_report,
		"third_person_item_presentation": "FOLLOWUP_NOT_IN_FIX7",
	}
	return snapshot

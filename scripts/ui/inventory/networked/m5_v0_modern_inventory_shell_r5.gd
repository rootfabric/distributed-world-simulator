extends "res://scripts/ui/inventory/networked/m5_v0_modern_inventory_shell.gd"

const P1InventoryBridge = preload(
	"res://scripts/runtime/networked_gameplay/m5/m5_v0_inventory_ui_bridge.gd"
)
const P1OutpostClientAdapter = preload(
	"res://scripts/runtime/networked_gameplay/m3/m3_mvp_outpost_client_adapter.gd"
)

# R5 composition adapter. Restores the accepted rev6 7-Days interaction
# surfaces while every mutation still crosses M5 -> canonical M4.

var _player_sort_button: Button
var _external_sort_button: Button
var _sort_in_progress := false


func setup(runtime, logical_player_id: String) -> Dictionary:
	if _configured:
		return _failure("M5_INVENTORY_SHELL_ALREADY_CONFIGURED")
	bridge = P1InventoryBridge.new()
	bridge.name = "M5InventoryUiBridge"
	add_child(bridge)
	var setup_result: Dictionary = bridge.setup(runtime, logical_player_id)
	if not bool(setup_result.get("success", false)):
		bridge.queue_free()
		bridge = null
		return setup_result
	var profile_result := _load_interaction_profile()
	if not bool(profile_result.get("success", false)):
		bridge.stop()
		bridge.queue_free()
		bridge = null
		return profile_result
	_outpost_adapter = P1OutpostClientAdapter.new()
	var outpost_setup: Dictionary = _outpost_adapter.setup(runtime)
	if not bool(outpost_setup.get("success", false)):
		_outpost_adapter = null
	_build_ui()
	bridge.view_updated.connect(_on_view_updated)
	bridge.command_completed.connect(_on_command_completed)
	if runtime != null and runtime.has_signal("construction_updated"):
		if not runtime.construction_updated.is_connected(_on_construction_updated):
			runtime.construction_updated.connect(_on_construction_updated)
	_configured = true
	_on_view_updated(bridge.build_view())
	_refresh_construction_status()
	return _success({"interaction_profile": String(active_profile.profile_id)})


func _build_ui() -> void:
	super._build_ui()
	_setup_r5_sort_actions()
	_update_r5_sort_actions()


func _on_view_updated(view: Dictionary) -> void:
	super._on_view_updated(view)
	_update_r5_sort_actions()


func _on_modern_profile_selected(index: int) -> void:
	super._on_modern_profile_selected(index)
	_update_r5_sort_actions()


func set_inventory_visible(value: bool) -> void:
	super.set_inventory_visible(value)
	_update_r5_sort_actions()


func _input(event: InputEvent) -> void:
	if (
		not _inventory_visible
		or bridge == null
		or not bridge.has_cursor()
		or active_profile == null
		or String(active_profile.ui_style) != "SEVEN_DAYS"
		or not event is InputEventMouseButton
	):
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.pressed or mouse_event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		return
	if inventory_window != null and inventory_window.get_global_rect().has_point(mouse_event.position):
		return
	get_viewport().set_input_as_handled()
	_drop_network_cursor_to_world(mouse_event.button_index)


func _on_background_interaction_requested(button_index: int) -> void:
	if (
		bridge != null
		and bridge.has_cursor()
		and active_profile != null
		and String(active_profile.ui_style) == "SEVEN_DAYS"
		and button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]
	):
		_drop_network_cursor_to_world(button_index)
		return
	super._on_background_interaction_requested(button_index)


func _drop_network_cursor_to_world(button_index: int) -> void:
	if bridge == null or not bridge.has_cursor():
		return
	var cursor: Dictionary = bridge.get_cursor()
	var before_quantity := int(cursor.get("quantity", 0))
	var mode := "ONE" if button_index == MOUSE_BUTTON_RIGHT else "ALL"
	var result: Dictionary = bridge.drop_cursor_blocking(mode)
	_last_command_result = result.duplicate(true)
	_present_result(result)
	if bool(result.get("success", false)):
		var dropped_quantity := 1 if mode == "ONE" else before_quantity
		status_label.text = "Выброшено на поверхность ×%d" % dropped_quantity
	_update_network_carry_preview()
	_update_r5_sort_actions()


func _setup_r5_sort_actions() -> void:
	var actions := inventory_window.get_node_or_null("Margin/Main/NetworkedActions")
	if actions == null:
		return
	_player_sort_button = Button.new()
	_player_sort_button.name = "PlayerSortButton"
	_player_sort_button.text = "Сортировать"
	_player_sort_button.focus_mode = Control.FOCUS_NONE
	_player_sort_button.pressed.connect(_on_player_sort_pressed)
	actions.add_child(_player_sort_button)
	actions.move_child(_player_sort_button, 0)

	_external_sort_button = Button.new()
	_external_sort_button.name = "ExternalSortButton"
	_external_sort_button.text = "Сортировать контейнер"
	_external_sort_button.focus_mode = Control.FOCUS_NONE
	_external_sort_button.pressed.connect(_on_external_sort_pressed)
	actions.add_child(_external_sort_button)
	actions.move_child(_external_sort_button, 1)


func _update_r5_sort_actions() -> void:
	if _player_sort_button == null or _external_sort_button == null:
		return
	var seven_days := active_profile != null and String(active_profile.ui_style) == "SEVEN_DAYS"
	var cursor_active := bridge != null and bridge.has_cursor()
	var view: Dictionary = bridge.get_last_view() if bridge != null else {}
	var external: Dictionary = Dictionary(view.get("external", {}))
	_player_sort_button.visible = _inventory_visible and seven_days
	_external_sort_button.visible = _inventory_visible and seven_days and not external.is_empty()
	_player_sort_button.disabled = _sort_in_progress or cursor_active
	_external_sort_button.disabled = _sort_in_progress or cursor_active


func _on_player_sort_pressed() -> void:
	if bridge == null or _sort_in_progress:
		return
	var view: Dictionary = bridge.get_last_view()
	var player: Dictionary = Dictionary(view.get("player", {}))
	_sort_visible_container(String(player.get("container_id", "")))


func _on_external_sort_pressed() -> void:
	if bridge == null or _sort_in_progress:
		return
	var view: Dictionary = bridge.get_last_view()
	var external: Dictionary = Dictionary(view.get("external", {}))
	_sort_visible_container(String(external.get("container_id", "")))


func _sort_visible_container(container_id: String) -> void:
	if container_id.is_empty():
		_present_result(_failure("SORT_CONTAINER_NOT_VISIBLE"))
		return
	_sort_in_progress = true
	_update_r5_sort_actions()
	var result: Dictionary = bridge.sort_container_blocking(container_id)
	_last_command_result = result.duplicate(true)
	_sort_in_progress = false
	_present_result(result)
	if bool(result.get("success", false)):
		var moved := int(result.get("details", {}).get("moved", 0))
		status_label.text = "Сортировка завершена · перемещений: %d" % moved
	_update_r5_sort_actions()


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	report["r5_slot_aware_projection"] = true
	report["r5_cursor_world_drop"] = bridge != null and bridge.has_method("drop_cursor_blocking")
	report["r5_authoritative_sort"] = bridge != null and bridge.has_method("sort_container_blocking")
	report["player_sort_button"] = _player_sort_button != null
	report["external_sort_button"] = _external_sort_button != null
	return report

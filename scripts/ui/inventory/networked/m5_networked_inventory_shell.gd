extends CanvasLayer

const Bridge = preload("res://scripts/runtime/networked_gameplay/m5/m5_inventory_ui_bridge.gd")
const ContainerPanelScene = preload("res://scenes/ui/inventory/container_panel.tscn")
const HotbarPanelScene = preload("res://scenes/ui/inventory/hotbar_panel.tscn")

const SCHEMA := "planet_simulator.m5_networked_inventory_shell.v1"

var bridge
var root_control: Control
var inventory_window: PanelContainer
var player_panel
var external_panel
var hotbar_panel
var status_label: Label
var _inventory_visible := false
var _configured := false
var _render_count := 0
var _last_error_code := ""


func setup(runtime, logical_player_id: String) -> Dictionary:
	if _configured:
		return _failure("M5_INVENTORY_SHELL_ALREADY_CONFIGURED")
	bridge = Bridge.new()
	bridge.name = "M5InventoryUiBridge"
	add_child(bridge)
	var setup_result: Dictionary = bridge.setup(runtime, logical_player_id)
	if not bool(setup_result.get("success", false)):
		bridge.queue_free()
		bridge = null
		return setup_result
	_build_ui()
	bridge.view_updated.connect(_on_view_updated)
	bridge.command_completed.connect(_on_command_completed)
	_configured = true
	_on_view_updated(bridge.build_view())
	return _success()


func toggle_inventory() -> Dictionary:
	set_inventory_visible(not _inventory_visible)
	return {
		"success": true,
		"visible": _inventory_visible,
		"output": "Сетевой инвентарь: %s" % ("открыт" if _inventory_visible else "закрыт"),
	}


func set_inventory_visible(value: bool) -> void:
	_inventory_visible = value
	if inventory_window != null:
		inventory_window.visible = value
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED


func select_hotbar(index: int) -> Dictionary:
	if bridge == null:
		return _failure("M5_INVENTORY_SHELL_NOT_CONFIGURED")
	return bridge.submit_ui_action_blocking(
		"select_hotbar",
		{"selected_hotbar_index": clampi(index, 0, 7)}
	)


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"configured": _configured,
		"inventory_visible": _inventory_visible,
		"render_count": _render_count,
		"last_error_code": _last_error_code,
		"bridge": bridge.get_report() if bridge != null else {},
		"player_model": player_panel.current_model.duplicate(true) if player_panel != null else {},
		"external_model": external_panel.current_model.duplicate(true) if external_panel != null else {},
		"hotbar_model": hotbar_panel.current_model.duplicate(true) if hotbar_panel != null else {},
	}


func _build_ui() -> void:
	root_control = Control.new()
	root_control.name = "M5NetworkedInventoryRoot"
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)

	inventory_window = PanelContainer.new()
	inventory_window.name = "M5NetworkedInventoryWindow"
	inventory_window.set_anchors_preset(Control.PRESET_CENTER)
	inventory_window.offset_left = -540.0
	inventory_window.offset_top = -300.0
	inventory_window.offset_right = 540.0
	inventory_window.offset_bottom = 300.0
	root_control.add_child(inventory_window)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	inventory_window.add_child(outer)
	var title := Label.new()
	title.text = "СЕТЕВОЙ ИНВЕНТАРЬ · M5 PREPARATION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	outer.add_child(columns)
	player_panel = ContainerPanelScene.instantiate()
	player_panel.set_visual_role("player")
	player_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(player_panel)
	external_panel = ContainerPanelScene.instantiate()
	external_panel.set_visual_role("external")
	external_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(external_panel)
	status_label = Label.new()
	status_label.text = "Replica state · canonical mutation only on dedicated server"
	outer.add_child(status_label)

	hotbar_panel = HotbarPanelScene.instantiate()
	hotbar_panel.name = "M5NetworkedHotbar"
	hotbar_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hotbar_panel.offset_left = -390.0
	hotbar_panel.offset_top = -92.0
	hotbar_panel.offset_right = 390.0
	hotbar_panel.offset_bottom = -16.0
	hotbar_panel.set_visual_role("hotbar")
	root_control.add_child(hotbar_panel)

	player_panel.drop_requested.connect(_on_drop_requested)
	external_panel.drop_requested.connect(_on_drop_requested)
	hotbar_panel.drop_requested.connect(_on_drop_requested)
	player_panel.item_selected.connect(_on_item_selected)
	external_panel.item_selected.connect(_on_item_selected)
	hotbar_panel.item_selected.connect(_on_item_selected)
	inventory_window.visible = false


func _on_view_updated(view: Dictionary) -> void:
	if not bool(view.get("success", false)):
		_last_error_code = String(view.get("error_code", "M5_VIEW_REJECTED"))
		return
	var player_model: Dictionary = view.get("player", {})
	var external_model: Dictionary = view.get("external", {})
	var hotbar_model: Dictionary = view.get("hotbar", {})
	player_panel.render(player_model, Callable(self, "_icon_for_cell"), Callable(bridge, "preview_transfer"))
	if external_model.is_empty():
		external_panel.clear_panel()
	else:
		external_panel.render(external_model, Callable(self, "_icon_for_cell"), Callable(bridge, "preview_transfer"))
	hotbar_panel.render_hotbar(hotbar_model, Callable(self, "_icon_for_cell"), Callable(bridge, "preview_transfer"))
	status_label.text = "Revision %d · %s" % [
		int(view.get("canonical_revision", -1)),
		String(view.get("canonical_checksum", "")).left(12),
	]
	_render_count += 1


func _on_drop_requested(
	item_id: String,
	target_container_id: String,
	target_slot_index: int,
	quantity: int,
	target_item_id: String
) -> void:
	var result: Dictionary = bridge.submit_ui_action_blocking("transfer", {
		"item_id": item_id,
		"quantity": quantity,
		"target_container_id": target_container_id,
		"target_slot_index": target_slot_index,
		"target_item_id": target_item_id,
	})
	_on_command_completed(result)


func _on_item_selected(item_id: String) -> void:
	if bridge != null:
		bridge.set_selected_item(item_id)


func _on_command_completed(result: Dictionary) -> void:
	if status_label == null:
		return
	if bool(result.get("success", false)):
		status_label.text = "Команда подтверждена сервером"
	else:
		_last_error_code = String(result.get("error_code", "M5_COMMAND_REJECTED"))
		status_label.text = "Отклонено: %s" % _last_error_code


func _icon_for_cell(_cell: Dictionary):
	return null


func _exit_tree() -> void:
	if bridge != null:
		bridge.stop()


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}

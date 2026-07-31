extends CanvasLayer

const Bridge = preload("res://scripts/runtime/networked_gameplay/m5/m5_inventory_ui_bridge.gd")
const InteractionProfileLoader = preload("res://scripts/ui/inventory/interactions/inventory_interaction_profile_loader.gd")
const ContainerPanelScene = preload("res://scenes/ui/inventory/container_panel.tscn")
const HotbarPanelScene = preload("res://scenes/ui/inventory/hotbar_panel.tscn")

const SCHEMA := "planet_simulator.m5_networked_inventory_shell.v1"
const DEFAULT_PROFILE_ID := "seven_days_like"

var bridge
var root_control: Control
var inventory_window: PanelContainer
var player_panel
var external_panel
var world_panel
var mounts_panel
var hotbar_panel
var status_label: Label
var drop_selected_button: Button
var close_container_button: Button
var activate_selected_button: Button
var active_profile
var _inventory_visible := false
var _configured := false
var _render_count := 0
var _last_error_code := ""
var _selected_item_id := ""
var _ui_action_count := 0
var _ui_success_count := 0
var _ui_rejection_count := 0
var _cursor_begin_count := 0
var _cursor_place_count := 0
var _last_command_result: Dictionary = {}


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
	var profile_result := _load_interaction_profile()
	if not bool(profile_result.get("success", false)):
		bridge.stop()
		bridge.queue_free()
		bridge = null
		return profile_result
	_build_ui()
	bridge.view_updated.connect(_on_view_updated)
	bridge.command_completed.connect(_on_command_completed)
	_configured = true
	_on_view_updated(bridge.build_view())
	return _success({"interaction_profile": String(active_profile.profile_id)})


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


func is_inventory_visible() -> bool:
	return _inventory_visible


func select_hotbar(index: int) -> Dictionary:
	if bridge == null:
		return _failure("M5_INVENTORY_SHELL_NOT_CONFIGURED")
	return _submit("select_hotbar", {"selected_hotbar_index": clampi(index, 0, 7)})


func open_container(container_id: String) -> Dictionary:
	return _submit("open_container", {"container_id": container_id})


func close_container() -> Dictionary:
	var view: Dictionary = bridge.get_last_view() if bridge != null else {}
	var container_id := String(view.get("external_container_id", ""))
	if container_id.is_empty():
		return _failure("EXTERNAL_CONTAINER_NOT_OPEN")
	return _submit("close_container", {"container_id": container_id})


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"configured": _configured,
		"inventory_visible": _inventory_visible,
		"render_count": _render_count,
		"last_error_code": _last_error_code,
		"selected_item_id": _selected_item_id,
		"interaction_profile": String(active_profile.profile_id) if active_profile != null else "",
		"ui_action_count": _ui_action_count,
		"ui_success_count": _ui_success_count,
		"ui_rejection_count": _ui_rejection_count,
		"cursor_begin_count": _cursor_begin_count,
		"cursor_place_count": _cursor_place_count,
		"cursor_active": bridge.has_cursor() if bridge != null else false,
		"cursor": bridge.get_cursor() if bridge != null else {},
		"last_command_result": _last_command_result.duplicate(true),
		"bridge": bridge.get_report() if bridge != null else {},
		"player_model": player_panel.current_model.duplicate(true) if player_panel != null else {},
		"external_model": external_panel.current_model.duplicate(true) if external_panel != null else {},
		"world_model": world_panel.current_model.duplicate(true) if world_panel != null else {},
		"mounts_model": mounts_panel.current_model.duplicate(true) if mounts_panel != null else {},
		"hotbar_model": hotbar_panel.current_model.duplicate(true) if hotbar_panel != null else {},
		"authority_references": 0,
		"domain_references": 0,
	}


# Acceptance helpers deliberately drive the existing UI controls. They do not
# call the gameplay runtime and therefore exercise the same signals as a user.
func acceptance_click_item(item_id: String, button_index: int = MOUSE_BUTTON_LEFT) -> Dictionary:
	var cell = _find_cell(item_id)
	if cell == null:
		return _failure("M5_UI_ITEM_CELL_NOT_FOUND", {"item_id": item_id})
	return _dispatch_cell_click(cell, button_index, false)


func acceptance_double_click_item(item_id: String) -> Dictionary:
	var cell = _find_cell(item_id)
	if cell == null:
		return _failure("M5_UI_ITEM_CELL_NOT_FOUND", {"item_id": item_id})
	return _dispatch_cell_click(cell, MOUSE_BUTTON_LEFT, true)


func acceptance_click_slot(
	container_id: String,
	slot_index: int,
	button_index: int = MOUSE_BUTTON_LEFT
) -> Dictionary:
	var cell = _find_slot_cell(container_id, slot_index)
	if cell == null:
		return _failure("M5_UI_TARGET_CELL_NOT_FOUND", {
			"container_id": container_id,
			"slot_index": slot_index,
		})
	return _dispatch_cell_click(cell, button_index, false)


func acceptance_press_drop_selected() -> Dictionary:
	if drop_selected_button == null:
		return _failure("M5_DROP_BUTTON_MISSING")
	_last_command_result = {}
	drop_selected_button.pressed.emit()
	return _last_command_result.duplicate(true) if not _last_command_result.is_empty() else _success()



func acceptance_cancel_cursor() -> Dictionary:
	if bridge == null:
		return _failure("M5_INVENTORY_SHELL_NOT_CONFIGURED")
	return bridge.cancel_cursor()



func acceptance_activate_item(item_id: String) -> Dictionary:
	var click_result: Dictionary = acceptance_click_item(item_id)
	if not bool(click_result.get("success", false)):
		return click_result
	acceptance_cancel_cursor()
	if activate_selected_button == null:
		return _failure("M5_ACTIVATE_BUTTON_MISSING")
	_last_command_result = {}
	activate_selected_button.pressed.emit()
	return _last_command_result.duplicate(true) if not _last_command_result.is_empty() else _success()

func acceptance_press_close_container() -> Dictionary:
	if close_container_button == null:
		return _failure("M5_CLOSE_CONTAINER_BUTTON_MISSING")
	_last_command_result = {}
	close_container_button.pressed.emit()
	return _last_command_result.duplicate(true) if not _last_command_result.is_empty() else _success()

func acceptance_capture_viewport(path: String) -> Dictionary:
	if path.strip_edges().is_empty():
		return _failure("SCREENSHOT_PATH_REQUIRED")
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		return _failure("VIEWPORT_IMAGE_EMPTY")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var saved := image.save_png(path)
	if saved != OK:
		return _failure("SCREENSHOT_SAVE_FAILED", {"error": saved})
	return _success({
		"path": path,
		"width": image.get_width(),
		"height": image.get_height(),
		"sha256": FileAccess.get_sha256(path),
	})


func _load_interaction_profile() -> Dictionary:
	var loader = InteractionProfileLoader.new()
	var catalog := loader.load_catalog()
	if not bool(catalog.get("success", false)):
		return _failure("M5_INTERACTION_PROFILE_CATALOG_FAILED", catalog)
	var resolved := loader.resolve_profile(DEFAULT_PROFILE_ID)
	if not bool(resolved.get("success", false)):
		return _failure("M5_INTERACTION_PROFILE_MISSING", resolved)
	active_profile = resolved.get("profile")
	if active_profile == null:
		return _failure("M5_INTERACTION_PROFILE_INVALID")
	return _success()


func _build_ui() -> void:
	root_control = Control.new()
	root_control.name = "M5NetworkedInventoryRoot"
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)

	inventory_window = PanelContainer.new()
	inventory_window.name = "M5NetworkedInventoryWindow"
	inventory_window.set_anchors_preset(Control.PRESET_CENTER)
	inventory_window.offset_left = -600.0
	inventory_window.offset_top = -330.0
	inventory_window.offset_right = 600.0
	inventory_window.offset_bottom = 310.0
	root_control.add_child(inventory_window)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	inventory_window.add_child(outer)
	var title := Label.new()
	title.text = "СЕТЕВОЙ ИНВЕНТАРЬ · M5 GRAPHICAL ACCEPTANCE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)

	var upper := HBoxContainer.new()
	upper.add_theme_constant_override("separation", 8)
	outer.add_child(upper)
	world_panel = ContainerPanelScene.instantiate()
	world_panel.set_visual_role("world")
	world_panel.custom_minimum_size = Vector2(548.0, 150.0)
	upper.add_child(world_panel)
	mounts_panel = ContainerPanelScene.instantiate()
	mounts_panel.set_visual_role("mounts")
	mounts_panel.custom_minimum_size = Vector2(260.0, 150.0)
	upper.add_child(mounts_panel)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 8)
	outer.add_child(columns)
	player_panel = ContainerPanelScene.instantiate()
	player_panel.set_visual_role("player")
	player_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(player_panel)
	external_panel = ContainerPanelScene.instantiate()
	external_panel.set_visual_role("external")
	external_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(external_panel)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	outer.add_child(actions)
	drop_selected_button = Button.new()
	drop_selected_button.text = "Выбросить выбранное"
	drop_selected_button.pressed.connect(_on_drop_selected_pressed)
	actions.add_child(drop_selected_button)
	activate_selected_button = Button.new()
	activate_selected_button.text = "Активировать выбранное"
	activate_selected_button.pressed.connect(_on_activate_selected_pressed)
	actions.add_child(activate_selected_button)
	close_container_button = Button.new()
	close_container_button.text = "Закрыть контейнер"
	close_container_button.pressed.connect(_on_close_container_pressed)
	actions.add_child(close_container_button)
	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.text = "Replica state · canonical mutation only on dedicated server"
	actions.add_child(status_label)

	hotbar_panel = HotbarPanelScene.instantiate()
	hotbar_panel.name = "M5NetworkedHotbar"
	hotbar_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hotbar_panel.offset_left = -390.0
	hotbar_panel.offset_top = -92.0
	hotbar_panel.offset_right = 390.0
	hotbar_panel.offset_bottom = -16.0
	hotbar_panel.set_visual_role("hotbar")
	root_control.add_child(hotbar_panel)

	for panel in [player_panel, external_panel, world_panel, mounts_panel, hotbar_panel]:
		panel.set_interaction_profile(active_profile)
		_wire_panel(panel)
	inventory_window.visible = false


func _wire_panel(panel) -> void:
	panel.drop_requested.connect(_on_drop_requested)
	panel.drop_outside_requested.connect(_on_drop_outside_requested)
	panel.quick_transfer_requested.connect(_on_quick_transfer_requested)
	panel.activated.connect(_on_slot_activated)
	panel.item_selected.connect(_on_item_selected)
	panel.interaction_requested.connect(_on_interaction_requested)
	panel.background_interaction_requested.connect(_on_background_interaction_requested)


func _on_view_updated(view: Dictionary) -> void:
	if not bool(view.get("success", false)):
		_last_error_code = String(view.get("error_code", "M5_VIEW_REJECTED"))
		return
	var player_model: Dictionary = view.get("player", {})
	var external_model: Dictionary = view.get("external", {})
	var world_model: Dictionary = view.get("world", {})
	var mounts_model: Dictionary = view.get("mounts_view", {})
	var hotbar_model: Dictionary = view.get("hotbar", {})
	var cursor_active: bool = bridge.has_cursor()
	for panel in [player_panel, external_panel, world_panel, mounts_panel, hotbar_panel]:
		panel.set_cursor_carry_state(cursor_active, cursor_active)
	player_panel.render(player_model, Callable(self, "_icon_for_cell"), Callable(bridge, "preview_transfer"))
	if external_model.is_empty():
		external_panel.clear_panel()
	else:
		external_panel.render(external_model, Callable(self, "_icon_for_cell"), Callable(bridge, "preview_transfer"))
	world_panel.render(world_model, Callable(self, "_icon_for_cell"), Callable(bridge, "preview_transfer"))
	mounts_panel.render(mounts_model, Callable(self, "_icon_for_cell"), Callable(bridge, "preview_transfer"))
	hotbar_panel.render_hotbar(hotbar_model, Callable(self, "_icon_for_cell"), Callable(bridge, "preview_transfer"))
	status_label.text = "Revision %d · %s%s" % [
		int(view.get("canonical_revision", -1)),
		String(view.get("canonical_checksum", "")).left(12),
		" · CURSOR" if cursor_active else "",
	]
	close_container_button.disabled = String(view.get("external_container_id", "")).is_empty()
	_render_count += 1


func _on_drop_requested(
	item_id: String,
	target_container_id: String,
	target_slot_index: int,
	quantity: int,
	target_item_id: String
) -> void:
	var source: Dictionary = bridge.find_cell(item_id)
	_submit("transfer", {
		"item_id": item_id,
		"quantity": quantity,
		"source_quantity": int(source.get("quantity", quantity)),
		"source_container_id": String(source.get("source_container_id", "")),
		"source_slot_index": int(source.get("source_slot_index", -1)),
		"target_container_id": target_container_id,
		"target_slot_index": target_slot_index,
		"target_item_id": target_item_id,
	})


func _on_interaction_requested(action_id: String, payload: Dictionary) -> void:
	if bridge == null:
		return
	if not bridge.has_cursor():
		if String(payload.get("item_id", "")).is_empty():
			return
		var quantity_mode := String(payload.get("quantity_mode", "ALL"))
		var begin: Dictionary = bridge.begin_cursor_from_cell(payload, quantity_mode)
		if bool(begin.get("success", false)):
			_cursor_begin_count += 1
			_selected_item_id = String(payload.get("item_id", ""))
		else:
			_present_result(begin)
		return
	var cursor: Dictionary = bridge.get_cursor()
	var target_container_id := String(payload.get("target_container_id", ""))
	var target_slot_index := int(payload.get("target_slot_index", -1))
	var target_item_id := String(payload.get("target_item_id", payload.get("item_id", "")))
	if (
		String(cursor.get("item_id", "")) == target_item_id
		and String(cursor.get("source_container_id", "")) == target_container_id
	):
		bridge.cancel_cursor()
		return
	var place_mode := "ONE" if action_id == "CARRY_HALF_OR_PLACE_ONE" else "ALL"
	var placed: Dictionary = bridge.place_cursor_blocking(
		target_container_id,
		target_slot_index,
		target_item_id,
		place_mode
	)
	_last_command_result = placed.duplicate(true)
	_cursor_place_count += 1
	_present_result(placed)


func _on_quick_transfer_requested(item_id: String, source_container_id: String, source_slot_index: int) -> void:
	var view: Dictionary = bridge.get_last_view()
	var target: String = "inventory/%s" % String(view.get("logical_player_id", ""))
	if source_container_id.begins_with("inventory/"):
		var external: String = String(view.get("external_container_id", ""))
		target = external if not external.is_empty() else "hotbar/%s" % String(view.get("logical_player_id", ""))
	var source: Dictionary = bridge.find_cell(item_id)
	_submit("transfer", {
		"item_id": item_id,
		"quantity": -1,
		"source_quantity": int(source.get("quantity", -1)),
		"source_container_id": source_container_id,
		"source_slot_index": source_slot_index,
		"target_container_id": target,
		"target_slot_index": -1,
		"target_item_id": "",
	})


func _on_drop_outside_requested(item_id: String, quantity: int) -> void:
	_submit("drop", {"item_id": item_id, "quantity": quantity})


func _on_slot_activated(item_id: String, container_id: String, slot_index: int) -> void:
	if container_id.begins_with("hotbar/"):
		select_hotbar(slot_index)
		return
	if container_id.begins_with("mount/") and not item_id.is_empty():
		_submit("detach", {"mount_id": container_id})
		return
	var cell: Dictionary = bridge.find_cell(item_id)
	var owned_container_id := String(cell.get("owned_container_id", ""))
	if container_id.begins_with("world/") and not owned_container_id.is_empty():
		open_container(owned_container_id)


func _on_item_selected(item_id: String) -> void:
	_selected_item_id = item_id
	if bridge != null:
		bridge.set_selected_item(item_id)


func _on_background_interaction_requested(_button_index: int) -> void:
	if bridge != null and bridge.has_cursor():
		bridge.cancel_cursor()



func _on_activate_selected_pressed() -> void:
	if _selected_item_id.is_empty():
		_present_result(_failure("M5_SELECTED_ITEM_REQUIRED"))
		return
	var cell: Dictionary = bridge.find_cell(_selected_item_id)
	var source_container_id := String(cell.get("source_container_id", ""))
	var source_slot_index := int(cell.get("source_slot_index", -1))
	_on_slot_activated(_selected_item_id, source_container_id, source_slot_index)


func _on_drop_selected_pressed() -> void:
	if _selected_item_id.is_empty():
		_present_result(_failure("M5_SELECTED_ITEM_REQUIRED"))
		return
	var cell: Dictionary = bridge.find_cell(_selected_item_id)
	if String(cell.get("source_container_id", "")).begins_with("inventory/"):
		_submit("drop", {"item_id": _selected_item_id, "quantity": -1})
	else:
		_present_result(_failure("M5_DROP_REQUIRES_INVENTORY_ITEM"))


func _on_close_container_pressed() -> void:
	close_container()


func _submit(action_id: String, payload: Dictionary) -> Dictionary:
	_ui_action_count += 1
	var result: Dictionary = bridge.submit_ui_action_blocking(action_id, payload)
	_last_command_result = result.duplicate(true)
	_present_result(result)
	return result


func _on_command_completed(result: Dictionary) -> void:
	# submit() already presents synchronous results; this signal also covers
	# commands initiated by cursor interaction helpers.
	_last_command_result = result.duplicate(true)
	if not bool(result.get("success", false)):
		_last_error_code = String(result.get("error_code", "M5_COMMAND_REJECTED"))


func _present_result(result: Dictionary) -> void:
	if status_label == null:
		return
	if bool(result.get("success", false)):
		_ui_success_count += 1
		status_label.text = "Команда подтверждена сервером"
	else:
		_ui_rejection_count += 1
		_last_error_code = String(result.get("error_code", "M5_COMMAND_REJECTED"))
		status_label.text = "Отклонено: %s" % _last_error_code


func _find_cell(item_id: String):
	for panel in [player_panel, external_panel, world_panel, mounts_panel, hotbar_panel]:
		if panel == null:
			continue
		var cell = panel.find_cell_by_item_id(item_id)
		if cell != null:
			return cell
	return null


func _find_slot_cell(container_id: String, slot_index: int):
	var panel = _panel_for_container(container_id)
	if panel == null or slot_index < 0 or slot_index >= panel.grid.get_child_count():
		return null
	var cell = panel.grid.get_child(slot_index)
	return cell if cell.visible else null


func _panel_for_container(container_id: String):
	if player_panel != null and String(player_panel.container_id) == container_id:
		return player_panel
	if external_panel != null and String(external_panel.container_id) == container_id:
		return external_panel
	if world_panel != null and String(world_panel.container_id) == container_id:
		return world_panel
	if hotbar_panel != null and String(hotbar_panel.container_id) == container_id:
		return hotbar_panel
	if container_id == "mounts/shared" or container_id.begins_with("mount/"):
		return mounts_panel
	return null


func _dispatch_cell_click(cell, button_index: int, double_click: bool) -> Dictionary:
	var position: Vector2 = cell.size * 0.5
	var press := InputEventMouseButton.new()
	press.button_index = button_index
	press.pressed = true
	press.double_click = double_click
	press.position = position
	press.global_position = cell.global_position + position
	cell._gui_input(press)
	var release := InputEventMouseButton.new()
	release.button_index = button_index
	release.pressed = false
	release.double_click = double_click
	release.position = position
	release.global_position = cell.global_position + position
	cell._gui_input(release)
	return _success({"item_id": String(cell.item_id), "button_index": button_index})


func _icon_for_cell(cell: Dictionary):
	var values = cell.get("icon_color", [])
	var color := Color(0.18, 0.22, 0.28, 1.0)
	if values is Array and values.size() >= 3:
		color = Color(float(values[0]), float(values[1]), float(values[2]), 1.0)
	var image := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _exit_tree() -> void:
	if bridge != null:
		bridge.stop()


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}

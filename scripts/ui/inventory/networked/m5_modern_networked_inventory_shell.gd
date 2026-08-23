extends "res://scripts/ui/inventory/networked/m5_networked_inventory_shell.gd"

const ModernInventoryScreenScene = preload("res://scenes/ui/inventory/inventory_screen.tscn")
const ModernContainerPanelScene = preload("res://scenes/ui/inventory/container_panel.tscn")
const ModernHotbarPanelScene = preload("res://scenes/ui/inventory/hotbar_panel.tscn")
const ModernInteractionProfileLoader = preload(
	"res://scripts/ui/inventory/interactions/inventory_interaction_profile_loader.gd"
)
const ModernContextMenuScript = preload("res://scripts/ui/inventory/item_context_menu.gd")

const UI_VARIANT := "MODERN_INVENTORY_SCREEN"
const FILTER_OPTIONS := [
	["ALL", "Все"],
	["RESOURCE", "Ресурсы"],
	["TOOL", "Инструменты"],
	["CONTAINER", "Контейнеры"],
	["BATTERY", "Батареи"],
	["MOUNTABLE", "Монтаж"],
	["CONSTRUCTION", "Стройка"],
]
const SORT_OPTIONS := [
	["CONTAINER_ORDER", "По ячейкам"],
	["NAME", "По названию"],
	["TYPE", "По типу"],
	["QUANTITY", "По количеству"],
	["RECENT", "Недавние"],
]
const FILTER_TAGS := {
	"RESOURCE": ["resource", "rock", "ore", "material"],
	"TOOL": ["tool", "sensor", "beacon", "electronic"],
	"CONTAINER": ["container", "rack"],
	"BATTERY": ["battery", "power"],
	"MOUNTABLE": ["mountable", "mount_socket"],
	"CONSTRUCTION": ["construction", "placeable", "assembly_root", "mount_socket"],
}

var _modern_screen
var _embedded_hotbar_panel
var _compatibility_holder: Control
var _search_edit: LineEdit
var _filter_option: OptionButton
var _sort_option: OptionButton
var _profile_option: OptionButton
var _reset_projection_button: Button
var _inspector_toggle: CheckButton
var _projection_summary: Label
var _inspector
var _toast_layer
var _tooltip
var _context_menu
var _split_dialog
var _profile_loader
var _profile_ids: PackedStringArray = PackedStringArray()
var _projection_query := ""
var _projection_filter := "ALL"
var _projection_sort := "CONTAINER_ORDER"


func _build_ui() -> void:
	root_control = Control.new()
	root_control.name = "M5ModernNetworkedInventoryRoot"
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_control)

	_modern_screen = ModernInventoryScreenScene.instantiate()
	inventory_window = _modern_screen
	inventory_window.name = "M5ModernNetworkedInventoryWindow"
	inventory_window.mouse_filter = Control.MOUSE_FILTER_STOP
	inventory_window.set_anchors_preset(Control.PRESET_CENTER)
	inventory_window.offset_left = -530.0
	inventory_window.offset_top = -340.0
	inventory_window.offset_right = 530.0
	inventory_window.offset_bottom = 340.0
	root_control.add_child(inventory_window)

	player_panel = inventory_window.get_node("%PlayerPanel")
	external_panel = inventory_window.get_node("%ExternalPanel")
	_embedded_hotbar_panel = inventory_window.get_node("%HotbarPanel")
	_embedded_hotbar_panel.visible = false
	status_label = inventory_window.get_node("%StatusLabel")
	_search_edit = inventory_window.get_node("%SearchEdit")
	_filter_option = inventory_window.get_node("%FilterOption")
	_sort_option = inventory_window.get_node("%SortOption")
	_profile_option = inventory_window.get_node("%InteractionProfileOption")
	_reset_projection_button = inventory_window.get_node("%ResetProjectionButton")
	_inspector_toggle = inventory_window.get_node("%InspectorToggle")
	_projection_summary = inventory_window.get_node("%ProjectionSummary")
	_inspector = inventory_window.get_node("%Inspector")
	_toast_layer = inventory_window.get_node("%ToastLayer")
	_tooltip = inventory_window.get_node("%ItemTooltip")
	_context_menu = inventory_window.get_node("%ItemContextMenu")
	_split_dialog = inventory_window.get_node("%StackSplitDialog")

	player_panel.set_visual_role("player")
	external_panel.set_visual_role("external")

	hotbar_panel = ModernHotbarPanelScene.instantiate()
	hotbar_panel.name = "M5NetworkedHotbar"
	hotbar_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hotbar_panel.offset_left = -390.0
	hotbar_panel.offset_top = -92.0
	hotbar_panel.offset_right = 390.0
	hotbar_panel.offset_bottom = -16.0
	hotbar_panel.set_visual_role("hotbar")
	root_control.add_child(hotbar_panel)

	# Preserve old acceptance/report surfaces without shipping them as UI.
	# They remain derived from the same bridge view and never own canonical state.
	_compatibility_holder = Control.new()
	_compatibility_holder.name = "M5HiddenCompatibilitySurfaces"
	_compatibility_holder.visible = false
	root_control.add_child(_compatibility_holder)
	world_panel = ModernContainerPanelScene.instantiate()
	world_panel.name = "HiddenWorldPanel"
	_compatibility_holder.add_child(world_panel)
	world_panel.set_visual_role("world")
	mounts_panel = ModernContainerPanelScene.instantiate()
	mounts_panel.name = "HiddenMountsPanel"
	_compatibility_holder.add_child(mounts_panel)
	mounts_panel.set_visual_role("mounts")

	_build_modern_action_row()
	_setup_modern_toolbar()

	for panel in [player_panel, external_panel, world_panel, mounts_panel, hotbar_panel]:
		panel.set_interaction_profile(active_profile)
		_wire_modern_panel(panel)

	_context_menu.action_requested.connect(_on_modern_context_action_requested)
	_split_dialog.transfer_confirmed.connect(_on_modern_split_confirmed)
	_split_dialog.transfer_cancelled.connect(_on_modern_split_cancelled)
	_inspector_toggle.toggled.connect(_on_modern_inspector_toggled)
	_inspector.visible = _inspector_toggle.button_pressed
	inventory_window.visible = false


func set_inventory_visible(value: bool) -> void:
	super.set_inventory_visible(value)
	if value:
		return
	if _context_menu != null:
		_context_menu.close_menu()
	if _split_dialog != null and _split_dialog.visible:
		_split_dialog.hide()
		_split_dialog.clear_request()
	if _tooltip != null:
		_tooltip.clear_item(true)


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	report["ui_variant"] = UI_VARIANT
	report["inventory_screen_scene"] = "res://scenes/ui/inventory/inventory_screen.tscn"
	report["canonical_mutation_boundary"] = "M5_INVENTORY_UI_BRIDGE"
	report["modern_projection"] = {
		"query": _projection_query,
		"filter": _projection_filter,
		"sort": _projection_sort,
	}
	report["legacy_world_surface_visible"] = (
		world_panel != null and world_panel.is_visible_in_tree()
	)
	report["legacy_mount_surface_visible"] = (
		mounts_panel != null and mounts_panel.is_visible_in_tree()
	)
	return report


func _build_modern_action_row() -> void:
	var main := inventory_window.get_node("Margin/Main")
	var actions := HBoxContainer.new()
	actions.name = "NetworkedActions"
	actions.add_theme_constant_override("separation", 8)

	build_next_stage_button = Button.new()
	build_next_stage_button.text = "Построить следующий этап"
	build_next_stage_button.focus_mode = Control.FOCUS_NONE
	build_next_stage_button.pressed.connect(_on_build_next_stage_pressed)
	actions.add_child(build_next_stage_button)

	construction_status_label = Label.new()
	construction_status_label.text = "Ожидание Construction replica…"
	construction_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(construction_status_label)

	drop_selected_button = Button.new()
	drop_selected_button.text = "Выбросить"
	drop_selected_button.focus_mode = Control.FOCUS_NONE
	drop_selected_button.pressed.connect(_on_drop_selected_pressed)
	actions.add_child(drop_selected_button)

	activate_selected_button = Button.new()
	activate_selected_button.text = "Активировать"
	activate_selected_button.focus_mode = Control.FOCUS_NONE
	activate_selected_button.pressed.connect(_on_activate_selected_pressed)
	actions.add_child(activate_selected_button)

	close_container_button = Button.new()
	close_container_button.text = "Закрыть контейнер"
	close_container_button.focus_mode = Control.FOCUS_NONE
	close_container_button.pressed.connect(_on_close_container_pressed)
	actions.add_child(close_container_button)

	main.add_child(actions)
	main.move_child(actions, status_label.get_index())


func _setup_modern_toolbar() -> void:
	_filter_option.clear()
	for option_value in FILTER_OPTIONS:
		var entry: Array = option_value
		var index := _filter_option.item_count
		_filter_option.add_item(String(entry[1]))
		_filter_option.set_item_metadata(index, String(entry[0]))
	_filter_option.select(0)

	_sort_option.clear()
	for option_value in SORT_OPTIONS:
		var entry: Array = option_value
		var index := _sort_option.item_count
		_sort_option.add_item(String(entry[1]))
		_sort_option.set_item_metadata(index, String(entry[0]))
	_sort_option.select(0)

	_profile_loader = ModernInteractionProfileLoader.new()
	var catalog: Dictionary = _profile_loader.load_catalog()
	_profile_option.clear()
	_profile_ids = PackedStringArray()
	if bool(catalog.get("success", false)):
		for profile_value in _profile_loader.profile_options():
			var profile_entry: Dictionary = profile_value
			var profile_id := String(profile_entry.get("profile_id", ""))
			_profile_ids.append(profile_id)
			_profile_option.add_item(String(profile_entry.get("display_name", profile_id)))
			if active_profile != null and profile_id == String(active_profile.profile_id):
				_profile_option.select(_profile_option.item_count - 1)

	_search_edit.text_changed.connect(_on_modern_search_changed)
	_filter_option.item_selected.connect(_on_modern_filter_selected)
	_sort_option.item_selected.connect(_on_modern_sort_selected)
	_profile_option.item_selected.connect(_on_modern_profile_selected)
	_reset_projection_button.pressed.connect(_on_modern_reset_projection)


func _wire_modern_panel(panel) -> void:
	_wire_panel(panel)
	panel.quantity_drop_requested.connect(_on_modern_quantity_drop_requested)
	panel.context_requested.connect(_on_modern_context_requested)
	panel.item_hovered.connect(_on_modern_item_hovered)
	panel.item_unhovered.connect(_on_modern_item_unhovered)
	panel.drop_preview_rejected.connect(_on_modern_drop_preview_rejected)


func _on_view_updated(view: Dictionary) -> void:
	if not bool(view.get("success", false)):
		_last_error_code = String(view.get("error_code", "M5_VIEW_REJECTED"))
		return

	var player_model := _project_container(Dictionary(view.get("player", {})))
	var external_model := _project_container(Dictionary(view.get("external", {})))
	var world_model: Dictionary = Dictionary(view.get("world", {})).duplicate(true)
	var mounts_model: Dictionary = Dictionary(view.get("mounts_view", {})).duplicate(true)
	var hotbar_model: Dictionary = Dictionary(view.get("hotbar", {})).duplicate(true)
	var cursor_active: bool = bridge.has_cursor()

	for panel in [player_panel, external_panel, world_panel, mounts_panel, hotbar_panel]:
		panel.set_cursor_carry_state(cursor_active, cursor_active)

	player_panel.render(
		player_model,
		Callable(self, "_icon_for_cell"),
		Callable(bridge, "preview_transfer")
	)
	if external_model.is_empty():
		external_panel.clear_panel()
	else:
		external_panel.render(
			external_model,
			Callable(self, "_icon_for_cell"),
			Callable(bridge, "preview_transfer")
		)
	world_panel.render(
		world_model,
		Callable(self, "_icon_for_cell"),
		Callable(bridge, "preview_transfer")
	)
	mounts_panel.render(
		mounts_model,
		Callable(self, "_icon_for_cell"),
		Callable(bridge, "preview_transfer")
	)
	hotbar_panel.render_hotbar(
		hotbar_model,
		Callable(self, "_icon_for_cell"),
		Callable(bridge, "preview_transfer")
	)

	var selected_item: Dictionary = Dictionary(view.get("selected_item", {}))
	if _inspector_toggle.button_pressed and not selected_item.is_empty():
		_inspector.visible = true
		_inspector.show_item(selected_item)
	elif _inspector_toggle.button_pressed:
		_inspector.visible = true
		_inspector.clear_item()
	else:
		_inspector.visible = false

	_update_projection_summary(player_model, external_model)
	status_label.text = "Revision %d · %s%s · M5 canonical bridge" % [
		int(view.get("canonical_revision", -1)),
		String(view.get("canonical_checksum", "")).left(12),
		" · CURSOR" if cursor_active else "",
	]
	close_container_button.disabled = String(
		view.get("external_container_id", "")
	).is_empty()
	_render_count += 1
	_refresh_construction_status()


func _project_container(model: Dictionary) -> Dictionary:
	if model.is_empty():
		return {}
	var projected := model.duplicate(true)
	var cells: Array = []
	var matched := 0
	for cell_value in projected.get("cells", []):
		if not cell_value is Dictionary:
			continue
		var cell: Dictionary = Dictionary(cell_value).duplicate(true)
		var matches := _matches_modern_projection(cell)
		cell["projection_match"] = matches
		if matches and not String(cell.get("item_id", "")).is_empty():
			matched += 1
		cells.append(cell)

	# Canonical slot identity/order is never rearranged by presentation sorting.
	# This matches the existing full InventoryScreen behavior for slot containers.
	if not bool(projected.get("is_slot_container", false)):
		_sort_projection_cells(cells)

	projected["cells"] = cells
	projected["rendered_cell_count"] = cells.size()
	projected["matched_count"] = matched
	projected["projected_total_count"] = matched
	return projected


func _matches_modern_projection(cell: Dictionary) -> bool:
	if String(cell.get("item_id", "")).is_empty():
		return true
	if not _projection_query.is_empty():
		var query := _projection_query.to_lower()
		var tags := PackedStringArray(cell.get("tags", []))
		var haystack := "%s %s %s %s" % [
			String(cell.get("display_name", "")),
			String(cell.get("definition_id", "")),
			" ".join(tags),
			String(cell.get("relation_kind", "")),
		]
		if not haystack.to_lower().contains(query):
			return false
	if _projection_filter == "ALL":
		return true
	var accepted_tags: Array = Array(FILTER_TAGS.get(_projection_filter, []))
	var cell_tags := PackedStringArray(cell.get("tags", []))
	for accepted_tag_value in accepted_tags:
		if cell_tags.has(String(accepted_tag_value)):
			return true
	return false


func _sort_projection_cells(cells: Array) -> void:
	match _projection_sort:
		"NAME":
			cells.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return String(a.get("display_name", "")).naturalnocasecmp_to(String(b.get("display_name", ""))) < 0
			)
		"TYPE":
			cells.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return String(a.get("definition_id", "")).naturalnocasecmp_to(String(b.get("definition_id", ""))) < 0
			)
		"QUANTITY":
			cells.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return int(a.get("quantity", 0)) > int(b.get("quantity", 0))
			)
		"RECENT":
			cells.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return int(a.get("activity_sequence", 0)) > int(b.get("activity_sequence", 0))
			)


func _update_projection_summary(
	player_model: Dictionary,
	external_model: Dictionary
) -> void:
	var matched := int(player_model.get("matched_count", 0))
	var total := int(player_model.get("unfiltered_count", 0))
	if not external_model.is_empty():
		matched += int(external_model.get("matched_count", 0))
		total += int(external_model.get("unfiltered_count", 0))
	_projection_summary.text = (
		"Найдено %d из %d · фильтр: %s · сортировка не меняет canonical slot order"
		% [matched, total, _projection_filter]
	)


func _refresh_modern_view() -> void:
	if bridge == null:
		return
	var view: Dictionary = bridge.get_last_view()
	if view.is_empty():
		view = bridge.build_view()
	if not view.is_empty():
		_on_view_updated(view)


func _on_modern_search_changed(value: String) -> void:
	_projection_query = value.strip_edges()
	_refresh_modern_view()


func _on_modern_filter_selected(index: int) -> void:
	_projection_filter = String(_filter_option.get_item_metadata(index))
	if _projection_filter.is_empty():
		_projection_filter = "ALL"
	_refresh_modern_view()


func _on_modern_sort_selected(index: int) -> void:
	_projection_sort = String(_sort_option.get_item_metadata(index))
	if _projection_sort.is_empty():
		_projection_sort = "CONTAINER_ORDER"
	_refresh_modern_view()


func _on_modern_profile_selected(index: int) -> void:
	if _profile_loader == null or index < 0 or index >= _profile_ids.size():
		return
	var result: Dictionary = _profile_loader.resolve_profile(_profile_ids[index])
	if not bool(result.get("success", false)):
		_last_error_code = String(result.get("error_code", "M5_INTERACTION_PROFILE_MISSING"))
		return
	var resolved_profile = result.get("profile")
	if resolved_profile == null:
		return
	active_profile = resolved_profile
	for panel in [player_panel, external_panel, world_panel, mounts_panel, hotbar_panel]:
		panel.set_interaction_profile(active_profile)
	_refresh_modern_view()


func _on_modern_reset_projection() -> void:
	_projection_query = ""
	_projection_filter = "ALL"
	_projection_sort = "CONTAINER_ORDER"
	_search_edit.text = ""
	_filter_option.select(0)
	_sort_option.select(0)
	_refresh_modern_view()


func _on_modern_inspector_toggled(enabled: bool) -> void:
	_inspector.visible = enabled
	_refresh_modern_view()


func _on_modern_item_hovered(cell_data: Dictionary, cell_rect) -> void:
	if _tooltip == null or String(cell_data.get("item_id", "")).is_empty():
		return
	if active_profile != null and String(active_profile.ui_style) == "SEVEN_DAYS":
		_tooltip.show_name_only(cell_data)
	else:
		_tooltip.show_item(cell_data)
	if typeof(cell_rect) == TYPE_RECT2:
		var rect: Rect2 = cell_rect
		_tooltip.position = rect.position + Vector2(rect.size.x + 8.0, 0.0)


func _on_modern_item_unhovered(_item_id: String) -> void:
	if _tooltip != null:
		_tooltip.clear_item()


func _on_modern_drop_preview_rejected(
	_target_container_id: String,
	_target_slot_index: int,
	error_code: String
) -> void:
	_last_error_code = error_code
	status_label.text = "Отклонено: %s" % error_code


func _on_modern_context_requested(
	item_id: String,
	source_container_id: String,
	source_slot_index: int,
	screen_position: Vector2
) -> void:
	if _context_menu == null or bridge == null:
		return
	var cell: Dictionary = bridge.find_cell(item_id)
	if cell.is_empty():
		return
	var view: Dictionary = bridge.get_last_view()
	var external_id := String(view.get("external_container_id", ""))
	var can_quick := (
		source_container_id.begins_with("inventory/")
		or source_container_id.begins_with("hotbar/")
		or (not external_id.is_empty() and source_container_id == external_id)
	)
	var hotbar_slots: Array[Dictionary] = []
	if not source_container_id.begins_with("hotbar/"):
		var hotbar_model: Dictionary = Dictionary(view.get("hotbar", {}))
		var hotbar_cells: Array = Array(hotbar_model.get("cells", []))
		for slot_index in range(8):
			var target_item_id := ""
			if slot_index < hotbar_cells.size() and hotbar_cells[slot_index] is Dictionary:
				target_item_id = String(hotbar_cells[slot_index].get("item_id", ""))
			hotbar_slots.append({
				"slot_index": slot_index,
				"occupied": not target_item_id.is_empty(),
				"enabled": true,
			})
	_context_menu.open_for_item(
		cell,
		Vector2i(screen_position),
		{
			"can_quick_transfer": can_quick,
			"can_drop": (
				source_container_id.begins_with("inventory/")
				or source_container_id.begins_with("hotbar/")
			),
			"hotbar_slots": hotbar_slots,
			"source_slot_index": source_slot_index,
		}
	)


func _on_modern_context_action_requested(
	action_id: int,
	context: Dictionary
) -> void:
	var item_id := String(context.get("item_id", ""))
	var source_container_id := String(context.get("source_container_id", ""))
	var source_slot_index := int(context.get("source_slot_index", -1))
	var quantity := maxi(1, int(context.get("quantity", 1)))
	match action_id:
		ModernContextMenuScript.ACTION_INSPECT:
			_on_item_selected(item_id)
			_inspector_toggle.button_pressed = true
		ModernContextMenuScript.ACTION_TRANSFER_ALL:
			_on_quick_transfer_requested(item_id, source_container_id, source_slot_index)
		ModernContextMenuScript.ACTION_TRANSFER_ONE:
			_submit_context_transfer(item_id, source_container_id, source_slot_index, 1)
		ModernContextMenuScript.ACTION_TRANSFER_HALF:
			_submit_context_transfer(
				item_id,
				source_container_id,
				source_slot_index,
				maxi(1, int(ceil(float(quantity) * 0.5)))
			)
		ModernContextMenuScript.ACTION_TRANSFER_EXACT:
			_open_modern_split_for_quick_transfer(
				item_id,
				source_container_id,
				source_slot_index,
				quantity
			)
		ModernContextMenuScript.ACTION_DROP_ONE:
			_submit("drop", {"item_id": item_id, "quantity": 1})
		ModernContextMenuScript.ACTION_DROP_ALL:
			_submit("drop", {"item_id": item_id, "quantity": -1})
		ModernContextMenuScript.ACTION_HOTBAR_FIRST_FREE:
			_assign_first_free_hotbar(item_id)
		_:
			if action_id >= ModernContextMenuScript.ACTION_HOTBAR_SLOT_BASE:
				var hotbar_slot := int(
					context.get(
						"hotbar_slot_index",
						action_id - ModernContextMenuScript.ACTION_HOTBAR_SLOT_BASE
					)
				)
				_submit("assign_hotbar", {
					"item_id": item_id,
					"slot_index": hotbar_slot,
				})


func _submit_context_transfer(
	item_id: String,
	source_container_id: String,
	source_slot_index: int,
	quantity: int
) -> void:
	var target_container_id := _quick_transfer_target(source_container_id)
	if target_container_id.is_empty():
		_present_result(_failure("NO_QUICK_TRANSFER_TARGET"))
		return
	var source: Dictionary = bridge.find_cell(item_id)
	_submit("transfer", {
		"item_id": item_id,
		"quantity": quantity,
		"source_quantity": int(source.get("quantity", quantity)),
		"source_container_id": source_container_id,
		"source_slot_index": source_slot_index,
		"target_container_id": target_container_id,
		"target_slot_index": -1,
		"target_item_id": "",
	})


func _quick_transfer_target(source_container_id: String) -> String:
	var view: Dictionary = bridge.get_last_view()
	var player_id := String(view.get("logical_player_id", ""))
	var inventory_id := "inventory/%s" % player_id
	var hotbar_id := "hotbar/%s" % player_id
	var external_id := String(view.get("external_container_id", ""))
	if source_container_id.begins_with("inventory/"):
		return external_id if not external_id.is_empty() else hotbar_id
	if source_container_id.begins_with("hotbar/"):
		return inventory_id
	if not external_id.is_empty() and source_container_id == external_id:
		return inventory_id
	return ""


func _open_modern_split_for_quick_transfer(
	item_id: String,
	source_container_id: String,
	_source_slot_index: int,
	total_quantity: int
) -> void:
	var target_container_id := _quick_transfer_target(source_container_id)
	if target_container_id.is_empty():
		_present_result(_failure("NO_QUICK_TRANSFER_TARGET"))
		return
	var cell: Dictionary = bridge.find_cell(item_id)
	_split_dialog.open_request(
		item_id,
		total_quantity,
		target_container_id,
		-1,
		"",
		String(cell.get("display_name", "Предмет")),
		target_container_id
	)


func _on_modern_quantity_drop_requested(
	item_id: String,
	target_container_id: String,
	target_slot_index: int,
	total_quantity: int,
	target_item_id: String
) -> void:
	var cell: Dictionary = bridge.find_cell(item_id)
	_split_dialog.open_request(
		item_id,
		maxi(1, total_quantity),
		target_container_id,
		target_slot_index,
		target_item_id,
		String(cell.get("display_name", "Предмет")),
		target_container_id
	)


func _on_modern_split_confirmed(
	item_id: String,
	quantity: int,
	target_container_id: String,
	target_slot_index: int,
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


func _on_modern_split_cancelled() -> void:
	status_label.text = "Перенос отменён"


func _assign_first_free_hotbar(item_id: String) -> void:
	var view: Dictionary = bridge.get_last_view()
	var hotbar_model: Dictionary = Dictionary(view.get("hotbar", {}))
	var cells: Array = Array(hotbar_model.get("cells", []))
	for slot_index in range(8):
		var occupied := false
		if slot_index < cells.size() and cells[slot_index] is Dictionary:
			occupied = not String(cells[slot_index].get("item_id", "")).is_empty()
		if not occupied:
			_submit("assign_hotbar", {
				"item_id": item_id,
				"slot_index": slot_index,
			})
			return
	_present_result(_failure("NO_COMPATIBLE_SLOT"))

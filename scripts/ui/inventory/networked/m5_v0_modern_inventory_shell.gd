extends "res://scripts/ui/inventory/networked/m5_modern_networked_inventory_shell.gd"

const V0_UI_VARIANT := "V0_MODERN_INVENTORY_SCREEN"

var _network_carry_preview: PanelContainer
var _network_carry_icon: TextureRect
var _network_carry_quantity: Label
var _cursor_preview_texture: Texture2D
var _cursor_preview_name := ""


func _build_ui() -> void:
	super._build_ui()
	_restore_complete_sort_options()
	_setup_network_carry_preview()
	_apply_v0_profile_visual_style()


func _on_view_updated(view: Dictionary) -> void:
	super._on_view_updated(view)
	_apply_v0_profile_visual_style()
	_update_network_carry_preview()


func _on_modern_profile_selected(index: int) -> void:
	super._on_modern_profile_selected(index)
	_apply_v0_profile_visual_style()
	_update_network_carry_preview()


func _on_interaction_requested(action_id: String, payload: Dictionary) -> void:
	var starting_cursor: bool = (
		bridge != null
		and not bridge.has_cursor()
		and not String(payload.get("item_id", "")).is_empty()
	)
	if starting_cursor:
		_cursor_preview_texture = payload.get("icon_texture") as Texture2D
		_cursor_preview_name = String(payload.get("display_name", "Предмет"))
	super._on_interaction_requested(action_id, payload)
	_update_network_carry_preview()


func set_inventory_visible(value: bool) -> void:
	super.set_inventory_visible(value)
	_update_network_carry_preview()


func _process(_delta: float) -> void:
	if _network_carry_preview == null or not _network_carry_preview.visible:
		return
	_network_carry_preview.position = (
		get_viewport().get_mouse_position() + Vector2(18.0, 18.0)
	)


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	report["ui_variant"] = V0_UI_VARIANT
	report["profile_visual_style"] = (
		String(active_profile.ui_style)
		if active_profile != null
		else ""
	)
	report["cursor_preview_visible"] = (
		_network_carry_preview != null and _network_carry_preview.visible
	)
	return report


func _restore_complete_sort_options() -> void:
	_sort_option.clear()
	for entry_value in [
		["Порядок контейнера", "CONTAINER_ORDER"],
		["По имени", "NAME"],
		["По типу", "TYPE"],
		["По количеству", "QUANTITY"],
		["По массе", "MASS"],
		["По объёму", "VOLUME"],
		["Недавние операции", "RECENT"],
	]:
		var entry: Array = entry_value
		_sort_option.add_item(String(entry[0]))
		_sort_option.set_item_metadata(
			_sort_option.item_count - 1,
			String(entry[1])
		)
	_sort_option.select(0)
	_projection_sort = "CONTAINER_ORDER"


func _sort_projection_cells(cells: Array) -> void:
	match _projection_sort:
		"MASS":
			cells.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return float(a.get("total_mass_kg", 0.0)) > float(b.get("total_mass_kg", 0.0))
			)
		"VOLUME":
			cells.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return float(a.get("total_volume_l", 0.0)) > float(b.get("total_volume_l", 0.0))
			)
		_:
			super._sort_projection_cells(cells)


func _apply_v0_profile_visual_style() -> void:
	if inventory_window == null or active_profile == null:
		return
	var seven_days_style := String(active_profile.ui_style) == "SEVEN_DAYS"
	var header: Label = inventory_window.get_node("Margin/Main/Header")
	var toolbar: HBoxContainer = inventory_window.get_node("Margin/Main/ProjectionToolbar")
	var columns: HBoxContainer = inventory_window.get_node("%Columns")

	header.visible = not seven_days_style
	_search_edit.visible = not seven_days_style
	_filter_option.visible = not seven_days_style
	_sort_option.visible = not seven_days_style
	_reset_projection_button.visible = not seven_days_style
	_inspector_toggle.visible = not seven_days_style
	_projection_summary.visible = not seven_days_style
	toolbar.alignment = (
		BoxContainer.ALIGNMENT_END
		if seven_days_style
		else BoxContainer.ALIGNMENT_BEGIN
	)
	columns.add_theme_constant_override(
		"separation",
		4 if seven_days_style else 14
	)
	if seven_days_style:
		columns.move_child(external_panel, 0)
		columns.move_child(player_panel, 1)
		columns.move_child(_inspector, 2)
		_inspector.visible = false
		_set_inventory_window_size(Vector2(1240.0, 720.0))
	else:
		columns.move_child(player_panel, 0)
		columns.move_child(external_panel, 1)
		columns.move_child(_inspector, 2)
		_inspector.visible = _inspector_toggle.button_pressed
		_set_inventory_window_size(Vector2(1060.0, 680.0))
	_apply_v0_window_style(seven_days_style)


func _set_inventory_window_size(target_size: Vector2) -> void:
	inventory_window.custom_minimum_size = target_size
	inventory_window.offset_left = -target_size.x * 0.5
	inventory_window.offset_top = -target_size.y * 0.5
	inventory_window.offset_right = target_size.x * 0.5
	inventory_window.offset_bottom = target_size.y * 0.5


func _apply_v0_window_style(seven_days_style: bool) -> void:
	var style := StyleBoxFlat.new()
	if seven_days_style:
		style.bg_color = Color(0.035, 0.035, 0.03, 0.82)
		style.border_color = Color(0.92, 0.75, 0.18, 1.0)
		style.set_border_width_all(2)
		style.set_corner_radius_all(0)
	else:
		style.bg_color = Color(0.035, 0.045, 0.065, 0.97)
		style.border_color = Color(0.22, 0.5, 0.72, 1.0)
		style.set_border_width_all(2)
		style.set_corner_radius_all(10)
	inventory_window.add_theme_stylebox_override("panel", style)
	_apply_network_carry_style(seven_days_style)


func _setup_network_carry_preview() -> void:
	_network_carry_preview = PanelContainer.new()
	_network_carry_preview.name = "NetworkCarryPreview"
	_network_carry_preview.visible = false
	_network_carry_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_network_carry_preview.top_level = true
	_network_carry_preview.z_as_relative = false
	_network_carry_preview.z_index = 4095
	_network_carry_preview.custom_minimum_size = Vector2(56.0, 56.0)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_network_carry_preview.add_child(row)

	_network_carry_icon = TextureRect.new()
	_network_carry_icon.custom_minimum_size = Vector2(48.0, 48.0)
	_network_carry_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_network_carry_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_network_carry_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_network_carry_icon)

	_network_carry_quantity = Label.new()
	_network_carry_quantity.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_network_carry_quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_network_carry_quantity.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_network_carry_quantity.add_theme_font_size_override("font_size", 18)
	_network_carry_quantity.add_theme_color_override("font_color", Color.WHITE)
	_network_carry_quantity.add_theme_color_override(
		"font_outline_color",
		Color(0.03, 0.03, 0.03, 1.0)
	)
	_network_carry_quantity.add_theme_constant_override("outline_size", 4)
	_network_carry_quantity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_network_carry_icon.add_child(_network_carry_quantity)

	root_control.add_child(_network_carry_preview)
	_apply_network_carry_style(
		active_profile != null and String(active_profile.ui_style) == "SEVEN_DAYS"
	)


func _apply_network_carry_style(seven_days_style: bool) -> void:
	if _network_carry_preview == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = (
		Color.TRANSPARENT
		if seven_days_style
		else Color(0.08, 0.08, 0.07, 0.92)
	)
	style.border_color = (
		Color.TRANSPARENT
		if seven_days_style
		else Color(0.45, 0.82, 1.0, 1.0)
	)
	style.set_border_width_all(0 if seven_days_style else 2)
	style.set_corner_radius_all(2 if seven_days_style else 6)
	style.content_margin_left = 4.0 if seven_days_style else 6.0
	style.content_margin_top = 4.0 if seven_days_style else 5.0
	style.content_margin_right = 4.0 if seven_days_style else 6.0
	style.content_margin_bottom = 4.0 if seven_days_style else 5.0
	_network_carry_preview.add_theme_stylebox_override("panel", style)


func _update_network_carry_preview() -> void:
	if _network_carry_preview == null:
		return
	var active: bool = (
		inventory_window != null
		and inventory_window.visible
		and bridge != null
		and bridge.has_cursor()
	)
	_network_carry_preview.visible = active
	if not active:
		_network_carry_icon.texture = null
		_network_carry_quantity.text = ""
		if bridge == null or not bridge.has_cursor():
			_cursor_preview_texture = null
			_cursor_preview_name = ""
		return

	var cursor: Dictionary = bridge.get_cursor()
	var item_id := String(cursor.get("item_id", ""))
	if _cursor_preview_texture == null:
		var cell: Dictionary = bridge.find_cell(item_id)
		if not cell.is_empty():
			_cursor_preview_texture = _icon_for_cell(cell)
			_cursor_preview_name = String(cell.get("display_name", "Предмет"))
	_network_carry_icon.texture = _cursor_preview_texture
	var quantity := maxi(1, int(cursor.get("quantity", 1)))
	_network_carry_quantity.text = str(quantity) if quantity > 1 else ""
	_network_carry_preview.tooltip_text = (
		"%s ×%d" % [_cursor_preview_name, quantity]
		if not _cursor_preview_name.is_empty()
		else ""
	)

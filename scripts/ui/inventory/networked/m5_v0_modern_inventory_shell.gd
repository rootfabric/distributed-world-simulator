extends "res://scripts/ui/inventory/networked/m5_modern_networked_inventory_shell.gd"

const V0_UI_VARIANT := "V0_MODERN_INVENTORY_SCREEN"


func _build_ui() -> void:
	super._build_ui()
	_restore_complete_sort_options()
	_apply_v0_profile_visual_style()


func _on_view_updated(view: Dictionary) -> void:
	super._on_view_updated(view)
	_apply_v0_profile_visual_style()


func _on_modern_profile_selected(index: int) -> void:
	super._on_modern_profile_selected(index)
	_apply_v0_profile_visual_style()


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	report["ui_variant"] = V0_UI_VARIANT
	report["profile_visual_style"] = (
		String(active_profile.ui_style)
		if active_profile != null
		else ""
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

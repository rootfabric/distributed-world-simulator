class_name InventoryContainerPanel
extends PanelContainer

signal drop_requested(item_id: String, target_container_id: String, target_slot_index: int, quantity: int, target_item_id: String)
signal quantity_drop_requested(item_id: String, target_container_id: String, target_slot_index: int, total_quantity: int, target_item_id: String)
signal activated(item_id: String, container_id: String, slot_index: int)

const ItemCellScene = preload("res://scenes/ui/inventory/item_cell.tscn")

@onready var title_label: Label = %TitleLabel
@onready var metadata_label: Label = %MetadataLabel
@onready var role_label: Label = %RoleLabel
@onready var scroll: ScrollContainer = %Scroll
@onready var grid: GridContainer = %Grid
@onready var drop_hint_label: Label = %DropHintLabel

var container_id: String = ""
var storage_mode: String = ""
var visual_capacity: int = 0
var rendered_cell_count: int = 0
var drop_validator: Callable
var icon_provider: Callable
var current_model: Dictionary = {}
var visual_role: String = "container"


func _ready() -> void:
	_apply_boundary_style()


func set_visual_role(role: String) -> void:
	visual_role = role.strip_edges().to_lower()
	if visual_role.is_empty():
		visual_role = "container"
	_apply_boundary_style()
	_update_role_copy()


func render(model: Dictionary, new_icon_provider: Callable, new_drop_validator: Callable) -> void:
	current_model = model.duplicate(true)
	icon_provider = new_icon_provider
	drop_validator = new_drop_validator
	container_id = String(model.get("container_id", ""))
	storage_mode = String(model.get("storage_mode", ""))
	visual_capacity = int(model.get("visual_capacity", 0))
	grid.columns = maxi(1, int(model.get("columns", 1)))
	title_label.text = String(model.get("display_name", container_id))
	metadata_label.text = _format_metadata(model)
	_clear_grid()
	for cell_data_value in model.get("cells", []):
		var cell_data: Dictionary = Dictionary(cell_data_value)
		var cell = ItemCellScene.instantiate()
		var texture: Texture2D
		if icon_provider.is_valid():
			texture = icon_provider.call(cell_data)
		cell.render_cell(cell_data, texture, drop_validator)
		cell.drop_requested.connect(_forward_drop_requested)
		cell.quantity_drop_requested.connect(_forward_quantity_drop_requested)
		cell.activated.connect(_forward_activated)
		grid.add_child(cell)
	rendered_cell_count = grid.get_child_count()
	visible = not model.is_empty()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_update_role_copy()
	set_meta("inventory_container_model", current_model.duplicate(true))


func clear_panel() -> void:
	container_id = ""
	storage_mode = ""
	visual_capacity = 0
	current_model = {}
	title_label.text = ""
	metadata_label.text = ""
	_clear_grid()
	visible = false


func get_visual_cell_count() -> int:
	return visual_capacity


func get_rendered_cell_count() -> int:
	return rendered_cell_count


func get_boundary_snapshot() -> Dictionary:
	var style = get_theme_stylebox("panel")
	var has_visible_border := false
	var border_color := Color.TRANSPARENT
	if style is StyleBoxFlat:
		var flat := style as StyleBoxFlat
		has_visible_border = (
			flat.border_width_left >= 2
			and flat.border_width_top >= 2
			and flat.border_width_right >= 2
			and flat.border_width_bottom >= 2
			and flat.border_color.a > 0.5
		)
		border_color = flat.border_color
	return {
		"schema": "planet_simulator.inventory_panel_boundary.v1",
		"role": visual_role,
		"visible": has_visible_border,
		"border_color": [border_color.r, border_color.g, border_color.b, border_color.a],
		"minimum_size": [custom_minimum_size.x, custom_minimum_size.y],
		"drop_hint": drop_hint_label.text if drop_hint_label != null else "",
	}


func _can_drop_data(_at_position: Vector2, data) -> bool:
	if container_id.is_empty() or not data is Dictionary:
		return false
	if String(data.get("kind", "")) != "ITEM_STACK":
		return false
	if not drop_validator.is_valid():
		return true
	var requested_quantity: int = 1 if bool(data.get("ask_quantity", false)) else int(data.get("quantity", -1))
	var result = drop_validator.call(
		String(data.get("item_id", "")),
		requested_quantity,
		container_id,
		-1,
		""
	)
	return result is Dictionary and bool(result.get("success", false))


func _drop_data(_at_position: Vector2, data) -> void:
	if bool(data.get("ask_quantity", false)):
		quantity_drop_requested.emit(
			String(data.get("item_id", "")),
			container_id,
			-1,
			int(data.get("quantity", 1)),
			""
		)
		return
	drop_requested.emit(
		String(data.get("item_id", "")),
		container_id,
		-1,
		int(data.get("quantity", -1)),
		""
	)


func _format_metadata(model: Dictionary) -> String:
	var mode: String = String(model.get("storage_mode", ""))
	var used: int = int(model.get("used_entries", 0))
	var capacity: int = int(model.get("visual_capacity", 0))
	var entry_text: String = "%d/%d" % [used, capacity] if capacity > 0 else "%d" % used
	var mode_text: String = "%s · %s" % [mode, entry_text]
	if mode == "BULK":
		mode_text += " · автостак"
	return "%s · масса %s · объём %s" % [
		mode_text,
		_format_capacity(float(model.get("current_mass_kg", 0.0)), float(model.get("maximum_mass_kg", INF)), "кг"),
		_format_capacity(float(model.get("current_volume_l", 0.0)), float(model.get("maximum_volume_l", INF)), "л"),
	]


func _format_capacity(current: float, maximum: float, unit: String) -> String:
	if is_inf(maximum):
		return "%.1f %s" % [current, unit]
	return "%.1f/%.1f %s" % [current, maximum, unit]


func _clear_grid() -> void:
	for child in grid.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.remove_child(child)
		child.queue_free()
	rendered_cell_count = 0


func _update_role_copy() -> void:
	if role_label == null or drop_hint_label == null:
		return
	match visual_role:
		"player":
			role_label.text = "ЛИЧНЫЙ КОНТЕЙНЕР"
		"external":
			role_label.text = "ОТКРЫТЫЙ КОНТЕЙНЕР"
		"hotbar":
			role_label.text = "БЫСТРЫЙ ДОСТУП"
		_:
			role_label.text = "КОНТЕЙНЕР"
	if visual_role == "hotbar":
		drop_hint_label.text = "Перетащите предмет в нужный слот 1–0"
	elif storage_mode == "SLOTS":
		drop_hint_label.text = "Перетащите предмет в подходящую ячейку"
	else:
		drop_hint_label.text = "Перетащите предмет в свободную область контейнера"


func _apply_boundary_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.06, 0.085, 0.94)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	style.content_margin_left = 10.0
	style.content_margin_top = 8.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 8.0
	match visual_role:
		"player":
			style.border_color = Color(0.25, 0.56, 0.82, 1.0)
			style.bg_color = Color(0.045, 0.075, 0.11, 0.94)
		"external":
			style.border_color = Color(0.88, 0.58, 0.18, 1.0)
			style.bg_color = Color(0.095, 0.07, 0.035, 0.94)
		"hotbar":
			style.border_color = Color(0.26, 0.72, 0.68, 1.0)
			style.bg_color = Color(0.035, 0.085, 0.085, 0.94)
		_:
			style.border_color = Color(0.4, 0.48, 0.58, 1.0)
	add_theme_stylebox_override("panel", style)


func _forward_drop_requested(item_id: String, target_container_id: String, target_slot_index: int, quantity: int, target_item_id: String) -> void:
	drop_requested.emit(item_id, target_container_id, target_slot_index, quantity, target_item_id)


func _forward_quantity_drop_requested(item_id: String, target_container_id: String, target_slot_index: int, total_quantity: int, target_item_id: String) -> void:
	quantity_drop_requested.emit(item_id, target_container_id, target_slot_index, total_quantity, target_item_id)


func _forward_activated(item_id: String, source_container_id: String, slot_index: int) -> void:
	activated.emit(item_id, source_container_id, slot_index)

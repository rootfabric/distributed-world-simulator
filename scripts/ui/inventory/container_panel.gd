class_name InventoryContainerPanel
extends PanelContainer

signal drop_requested(item_id: String, target_container_id: String, target_slot_index: int, quantity: int, target_item_id: String)
signal quantity_drop_requested(item_id: String, target_container_id: String, target_slot_index: int, total_quantity: int, target_item_id: String)
signal activated(item_id: String, container_id: String, slot_index: int)
signal quick_transfer_requested(item_id: String, source_container_id: String, source_slot_index: int)
signal context_requested(item_id: String, source_container_id: String, source_slot_index: int, screen_position: Vector2)
signal item_hovered(cell_data: Dictionary, screen_position: Vector2)
signal item_unhovered(item_id: String)
signal item_selected(item_id: String)
signal drop_preview_rejected(target_container_id: String, target_slot_index: int, error_code: String)
signal page_requested(container_id: String, page_index: int)

const ItemCellScene = preload("res://scenes/ui/inventory/item_cell.tscn")

@onready var title_label: Label = %TitleLabel
@onready var metadata_label: Label = %MetadataLabel
@onready var role_label: Label = %RoleLabel
@onready var scroll: ScrollContainer = %Scroll
@onready var grid: GridContainer = %Grid
@onready var drop_hint_label: Label = %DropHintLabel
@onready var feedback_label: Label = %FeedbackLabel
@onready var feedback_timer: Timer = %FeedbackTimer
@onready var virtualization_bar: HBoxContainer = %VirtualizationBar
@onready var previous_page_button: Button = %PreviousPageButton
@onready var page_label: Label = %PageLabel
@onready var next_page_button: Button = %NextPageButton

var container_id: String = ""
var storage_mode: String = ""
var visual_capacity: int = 0
var rendered_cell_count: int = 0
var drop_validator: Callable
var icon_provider: Callable
var current_model: Dictionary = {}
var visual_role: String = "container"
var active_cell_count: int = 0


func _ready() -> void:
	_apply_boundary_style()
	feedback_timer.timeout.connect(_clear_feedback)
	previous_page_button.pressed.connect(_request_previous_page)
	next_page_button.pressed.connect(_request_next_page)


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
	var cells: Array = Array(model.get("cells", []))
	_ensure_pool_size(cells.size())
	for index in range(grid.get_child_count()):
		var cell = grid.get_child(index)
		if index >= cells.size():
			cell.visible = false
			continue
		var cell_data := Dictionary(cells[index])
		var texture: Texture2D
		if icon_provider.is_valid():
			texture = icon_provider.call(cell_data)
		cell.render_cell(cell_data, texture, drop_validator)
		cell.visible = true
	active_cell_count = cells.size()
	rendered_cell_count = active_cell_count
	visible = not model.is_empty()
	_clear_feedback()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_update_role_copy()
	_update_virtualization(model)
	set_meta("inventory_container_model", current_model.duplicate(true))


func clear_panel() -> void:
	container_id = ""
	storage_mode = ""
	visual_capacity = 0
	current_model = {}
	title_label.text = ""
	metadata_label.text = ""
	_hide_pool()
	virtualization_bar.visible = false
	visible = false
	_clear_feedback()


func get_visual_cell_count() -> int:
	return visual_capacity


func get_rendered_cell_count() -> int:
	return rendered_cell_count


func get_pool_size() -> int:
	return grid.get_child_count()


func show_feedback(message: String, success: bool = false, duration_seconds: float = 2.8) -> void:
	if feedback_label == null or message.is_empty():
		return
	feedback_label.text = message
	feedback_label.visible = true
	feedback_label.add_theme_color_override(
		"font_color",
		Color(0.55, 0.95, 0.68) if success else Color(1.0, 0.55, 0.48)
	)
	feedback_timer.start(maxf(0.1, duration_seconds))


func find_cell_by_item_id(item_id: String):
	for child in grid.get_children():
		if child.visible and String(child.get("item_id")) == item_id:
			return child
	return null


func _clear_feedback() -> void:
	if feedback_label == null:
		return
	feedback_label.visible = false
	feedback_label.text = ""


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
		"pool_size": get_pool_size(),
		"active_cell_count": active_cell_count,
		"virtualized": bool(current_model.get("virtualized", false)),
		"page_index": int(current_model.get("page_index", 0)),
		"page_count": int(current_model.get("page_count", 1)),
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
	var success := result is Dictionary and bool(result.get("success", false))
	if not success:
		var error_code := String(result.get("error_code", "DROP_REJECTED")) if result is Dictionary else "DROP_REJECTED"
		drop_preview_rejected.emit(container_id, -1, error_code)
	return success


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
	var projected_total := int(model.get("projected_total_count", used))
	if projected_total != used and mode == "BULK":
		mode_text += " · найдено %d" % projected_total
	if bool(model.get("virtualized", false)):
		mode_text += " · окно %d/%d" % [int(model.get("page_index", 0)) + 1, int(model.get("page_count", 1))]
	return "%s · масса %s · объём %s" % [
		mode_text,
		_format_capacity(float(model.get("current_mass_kg", 0.0)), float(model.get("maximum_mass_kg", INF)), "кг"),
		_format_capacity(float(model.get("current_volume_l", 0.0)), float(model.get("maximum_volume_l", INF)), "л"),
	]


func _format_capacity(current: float, maximum: float, unit: String) -> String:
	if is_inf(maximum):
		return "%.1f %s" % [current, unit]
	return "%.1f/%.1f %s" % [current, maximum, unit]


func _ensure_pool_size(required: int) -> void:
	while grid.get_child_count() < required:
		var cell = ItemCellScene.instantiate()
		_wire_cell(cell)
		grid.add_child(cell)


func _wire_cell(cell) -> void:
	cell.drop_requested.connect(_forward_drop_requested)
	cell.quantity_drop_requested.connect(_forward_quantity_drop_requested)
	cell.activated.connect(_forward_activated)
	cell.quick_transfer_requested.connect(_forward_quick_transfer_requested)
	cell.context_requested.connect(_forward_context_requested)
	cell.item_hovered.connect(_forward_item_hovered)
	cell.item_unhovered.connect(_forward_item_unhovered)
	cell.item_selected.connect(_forward_item_selected)
	cell.drop_preview_rejected.connect(_forward_drop_preview_rejected)


func _hide_pool() -> void:
	for child in grid.get_children():
		child.visible = false
	active_cell_count = 0
	rendered_cell_count = 0


func _update_virtualization(model: Dictionary) -> void:
	var page_count := int(model.get("page_count", 1))
	var page_index := int(model.get("page_index", 0))
	virtualization_bar.visible = bool(model.get("virtualized", false))
	page_label.text = "Страница %d из %d · показано %d из %d" % [
		page_index + 1,
		page_count,
		int(model.get("rendered_cell_count", 0)),
		int(model.get("projected_total_count", 0)),
	]
	previous_page_button.disabled = page_index <= 0
	next_page_button.disabled = page_index >= page_count - 1


func _request_previous_page() -> void:
	page_requested.emit(container_id, maxi(0, int(current_model.get("page_index", 0)) - 1))


func _request_next_page() -> void:
	page_requested.emit(container_id, int(current_model.get("page_index", 0)) + 1)


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


func _forward_quick_transfer_requested(item_id: String, source_container_id: String, source_slot_index: int) -> void:
	quick_transfer_requested.emit(item_id, source_container_id, source_slot_index)


func _forward_context_requested(item_id: String, source_container_id: String, source_slot_index: int, screen_position: Vector2) -> void:
	context_requested.emit(item_id, source_container_id, source_slot_index, screen_position)


func _forward_item_hovered(cell_data: Dictionary, screen_position: Vector2) -> void:
	item_hovered.emit(cell_data, screen_position)


func _forward_item_unhovered(item_id: String) -> void:
	item_unhovered.emit(item_id)


func _forward_item_selected(item_id: String) -> void:
	item_selected.emit(item_id)


func _forward_drop_preview_rejected(target_container_id: String, target_slot_index: int, error_code: String) -> void:
	drop_preview_rejected.emit(target_container_id, target_slot_index, error_code)

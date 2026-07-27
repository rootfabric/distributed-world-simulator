class_name InventoryContainerPanel
extends VBoxContainer

signal drop_requested(item_id: String, target_container_id: String, target_slot_index: int, quantity: int, target_item_id: String)
signal quantity_drop_requested(item_id: String, target_container_id: String, target_slot_index: int, total_quantity: int, target_item_id: String)
signal activated(item_id: String, container_id: String, slot_index: int)

const ItemCellScene = preload("res://scenes/ui/inventory/item_cell.tscn")

@onready var title_label: Label = %TitleLabel
@onready var metadata_label: Label = %MetadataLabel
@onready var scroll: ScrollContainer = %Scroll
@onready var grid: GridContainer = %Grid

var container_id: String = ""
var storage_mode: String = ""
var visual_capacity: int = 0
var rendered_cell_count: int = 0
var drop_validator: Callable
var icon_provider: Callable
var current_model: Dictionary = {}


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


func _forward_drop_requested(item_id: String, target_container_id: String, target_slot_index: int, quantity: int, target_item_id: String) -> void:
	drop_requested.emit(item_id, target_container_id, target_slot_index, quantity, target_item_id)


func _forward_quantity_drop_requested(item_id: String, target_container_id: String, target_slot_index: int, total_quantity: int, target_item_id: String) -> void:
	quantity_drop_requested.emit(item_id, target_container_id, target_slot_index, total_quantity, target_item_id)


func _forward_activated(item_id: String, source_container_id: String, slot_index: int) -> void:
	activated.emit(item_id, source_container_id, slot_index)

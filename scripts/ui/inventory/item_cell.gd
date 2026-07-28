class_name InventoryItemCell
extends "res://scripts/items/presentation/item_slot_control.gd"

signal quick_transfer_requested(item_id: String, source_container_id: String, source_slot_index: int)
signal context_requested(item_id: String, source_container_id: String, source_slot_index: int, screen_position: Vector2)
signal item_hovered(cell_data: Dictionary, screen_position: Vector2)
signal item_unhovered(item_id: String)
signal item_selected(item_id: String)
signal drop_preview_rejected(target_container_id: String, target_slot_index: int, error_code: String)

var view_data: Dictionary = {}
var _context_press_position: Vector2 = Vector2.ZERO
var _context_pressed: bool = false
var _context_dragged: bool = false
var _last_preview_error: String = ""


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func render_cell(data: Dictionary, texture: Texture2D, validator: Callable) -> void:
	view_data = data.duplicate(true)
	setup_slot({
		"item_id": String(data.get("item_id", "")),
		"source_container_id": String(data.get("source_container_id", "")),
		"source_slot_index": int(data.get("source_slot_index", -1)),
		"target_container_id": String(data.get("target_container_id", "")),
		"target_slot_index": int(data.get("target_slot_index", -1)),
		"icon_texture": texture,
		"title": String(data.get("display_name", "Пусто")),
		"quantity": int(data.get("quantity", 0)),
		"selected": bool(data.get("selected", false)) or bool(data.get("inspected", false)),
		"drop_validator": validator,
	})
	set_meta("inventory_view_data", view_data.duplicate(true))
	modulate = Color.WHITE if bool(data.get("projection_match", true)) else Color(1.0, 1.0, 1.0, 0.24)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed and not item_id.is_empty():
			item_selected.emit(item_id)
		if (
			mouse_event.button_index == MOUSE_BUTTON_LEFT
			and mouse_event.pressed
			and mouse_event.shift_pressed
			and not item_id.is_empty()
		):
			quick_transfer_requested.emit(item_id, source_container_id, source_slot_index)
			accept_event()
			return
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			if mouse_event.pressed and not item_id.is_empty():
				_context_pressed = true
				_context_dragged = false
				_context_press_position = mouse_event.position
			elif not mouse_event.pressed and _context_pressed:
				var should_open := not _context_dragged
				_context_pressed = false
				if should_open:
					context_requested.emit(
						item_id,
						source_container_id,
						source_slot_index,
						get_global_mouse_position()
					)
					accept_event()
					return
	if event is InputEventMouseMotion and _context_pressed:
		var motion := event as InputEventMouseMotion
		if (motion.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
			_context_dragged = _context_dragged or motion.position.distance_to(_context_press_position) >= RIGHT_DRAG_THRESHOLD_PX
	super._gui_input(event)


func _get_drag_data(at_position: Vector2):
	if Input.is_key_pressed(KEY_SHIFT):
		return null
	return super._get_drag_data(at_position)


func _can_drop_data(_at_position: Vector2, data) -> bool:
	if not data is Dictionary:
		return false
	if String(data.get("kind", "")) != "ITEM_STACK" or target_container_id.is_empty():
		return false
	if not drop_validator.is_valid():
		_last_preview_error = ""
		return true
	var requested_quantity := 1 if bool(data.get("ask_quantity", false)) else int(data.get("quantity", -1))
	var result = drop_validator.call(
		String(data.get("item_id", "")),
		requested_quantity,
		target_container_id,
		target_slot_index,
		item_id
	)
	var success := result is Dictionary and bool(result.get("success", false))
	if success:
		_last_preview_error = ""
		return true
	var error_code := String(result.get("error_code", "DROP_REJECTED")) if result is Dictionary else "DROP_REJECTED"
	if error_code != _last_preview_error:
		_last_preview_error = error_code
		drop_preview_rejected.emit(target_container_id, target_slot_index, error_code)
	return false


func _on_mouse_entered() -> void:
	if item_id.is_empty():
		return
	item_hovered.emit(view_data.duplicate(true), get_global_rect().end + Vector2(8.0, -custom_minimum_size.y))


func _on_mouse_exited() -> void:
	if not item_id.is_empty():
		item_unhovered.emit(item_id)

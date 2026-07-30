class_name InventoryItemCell
extends "res://scripts/items/presentation/item_slot_control.gd"

signal quick_transfer_requested(item_id: String, source_container_id: String, source_slot_index: int)
signal context_requested(item_id: String, source_container_id: String, source_slot_index: int, screen_position: Vector2)
signal item_hovered(cell_data: Dictionary, screen_position: Vector2)
signal item_unhovered(item_id: String)
signal item_selected(item_id: String)
signal drop_preview_rejected(target_container_id: String, target_slot_index: int, error_code: String)
signal drop_outside_requested(item_id: String, quantity: int)
signal interaction_requested(action_id: String, payload: Dictionary)

var view_data: Dictionary = {}
var _last_preview_error: String = ""
var _active_drag_payload: Dictionary = {}
var _cell_press_positions: Dictionary = {}
var _cell_press_modifiers: Dictionary = {}
var _cell_dragged_buttons: Dictionary = {}
var _double_click_buttons: Dictionary = {}
var _press_actions_emitted: Dictionary = {}
var _cursor_carry_active: bool = false
var _carry_target_highlight_enabled: bool = false
var _carry_hovered: bool = false


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	drag_started.connect(_on_drag_started)


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
	# Detailed data is rendered in InventoryInspector; native hover tooltips
	# would cover the inventory and duplicate that information.
	tooltip_text = ""
	modulate = Color.WHITE if bool(data.get("projection_match", true)) else Color(1.0, 1.0, 1.0, 0.24)
	_update_carry_hover()


func set_cursor_carry_state(active: bool, target_highlight_enabled: bool) -> void:
	_cursor_carry_active = active
	_carry_target_highlight_enabled = target_highlight_enabled
	_update_carry_hover()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if mouse_event.pressed:
				_cell_press_positions[mouse_event.button_index] = mouse_event.position
				_cell_press_modifiers[mouse_event.button_index] = {
					"shift": mouse_event.shift_pressed,
					"alt": mouse_event.alt_pressed,
					"ctrl": mouse_event.ctrl_pressed,
				}
				_cell_dragged_buttons[mouse_event.button_index] = false
				_double_click_buttons[mouse_event.button_index] = mouse_event.double_click
				_press_actions_emitted[mouse_event.button_index] = false
				var press_binding := interaction_router.resolve_mouse(
					mouse_event.button_index,
					mouse_event.shift_pressed,
					mouse_event.alt_pressed,
					mouse_event.ctrl_pressed,
					false,
					mouse_event.double_click
				) if interaction_profile != null else {}
				var press_action := String(press_binding.get("action", ""))
				if (
					_is_seven_days_style()
					and not _cursor_carry_active
					and not item_id.is_empty()
					and press_action in ["CARRY_ALL_OR_PLACE_ALL", "CARRY_HALF_OR_PLACE_ONE"]
				):
					_press_actions_emitted[mouse_event.button_index] = true
					_handle_click_binding(press_binding, mouse_event.button_index, "PRESS", mouse_event.position)
					accept_event()
					return
				if mouse_event.button_index == MOUSE_BUTTON_LEFT and not item_id.is_empty() and press_action in ["SELECT_ITEM", "QUICK_TRANSFER"]:
					item_selected.emit(item_id)
					_press_actions_emitted[mouse_event.button_index] = true
				if press_action == "QUICK_TRANSFER" and not item_id.is_empty():
					quick_transfer_requested.emit(item_id, source_container_id, source_slot_index)
					accept_event()
					return
			else:
				var was_dragged := bool(_cell_dragged_buttons.get(mouse_event.button_index, false))
				var was_double := bool(_double_click_buttons.get(mouse_event.button_index, false))
				if not was_dragged and not was_double:
					var modifiers := Dictionary(_cell_press_modifiers.get(mouse_event.button_index, {}))
					var release_binding := _resolve_click_binding(mouse_event.button_index, modifiers)
					if not bool(_press_actions_emitted.get(mouse_event.button_index, false)):
						_handle_click_binding(release_binding, mouse_event.button_index, "RELEASE", mouse_event.position)
				_cell_press_positions.erase(mouse_event.button_index)
				_cell_press_modifiers.erase(mouse_event.button_index)
				_cell_dragged_buttons.erase(mouse_event.button_index)
				_double_click_buttons.erase(mouse_event.button_index)
				_press_actions_emitted.erase(mouse_event.button_index)
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		for button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if not _cell_press_positions.has(button_index):
				continue
			var mask := _button_mask(button_index)
			if mask == 0 or (motion.button_mask & mask) == 0:
				continue
			var press_position: Vector2 = _cell_press_positions[button_index]
			if motion.position.distance_to(press_position) >= _drag_threshold():
				var modifiers := Dictionary(_cell_press_modifiers.get(button_index, {}))
				var can_drag := interaction_profile == null or interaction_router.can_drag(
					button_index,
					bool(modifiers.get("shift", false)),
					bool(modifiers.get("alt", false)),
					bool(modifiers.get("ctrl", false))
				)
				if can_drag:
					_cell_dragged_buttons[button_index] = true
	super._gui_input(event)


func _get_drag_data(at_position: Vector2):
	var payload = super._get_drag_data(at_position)
	if payload is Dictionary:
		_active_drag_payload = (payload as Dictionary).duplicate(true)
		_cell_dragged_buttons[MOUSE_BUTTON_LEFT] = true
	return payload


func _notification(what: int) -> void:
	if what != NOTIFICATION_DRAG_END:
		return
	_complete_drag(get_viewport().gui_is_drag_successful())


func _complete_drag(drop_was_accepted: bool) -> void:
	if _active_drag_payload.is_empty():
		return
	var payload := _active_drag_payload.duplicate(true)
	_active_drag_payload.clear()
	if drop_was_accepted or bool(payload.get("ask_quantity", false)):
		return
	if String(payload.get("outside_drop_action", "DROP_TO_WORLD")) != "DROP_TO_WORLD":
		return
	if _is_pointer_inside_inventory_window():
		return
	drop_outside_requested.emit(String(payload.get("item_id", "")), int(payload.get("quantity", -1)))


func _is_pointer_inside_inventory_window() -> bool:
	var ancestor: Node = self
	while ancestor != null:
		if ancestor is Control and ancestor.has_method("is_inventory_visible"):
			return (ancestor as Control).get_global_rect().has_point(get_global_mouse_position())
		ancestor = ancestor.get_parent()
	return false


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


func _on_drag_started(payload: Dictionary) -> void:
	_active_drag_payload = payload.duplicate(true)
	var gesture := String(payload.get("gesture", ""))
	if gesture.contains("SECONDARY"):
		_cell_dragged_buttons[MOUSE_BUTTON_RIGHT] = true
	elif gesture.contains("MIDDLE"):
		_cell_dragged_buttons[MOUSE_BUTTON_MIDDLE] = true


func _resolve_click_binding(button_index: int, modifiers: Dictionary) -> Dictionary:
	if interaction_profile == null:
		if button_index == MOUSE_BUTTON_RIGHT:
			return {"action": "OPEN_CONTEXT_MENU"}
		if button_index == MOUSE_BUTTON_LEFT:
			return {"action": "SELECT_ITEM"}
		return {}
	return interaction_router.resolve_mouse(
		button_index,
		bool(modifiers.get("shift", false)),
		bool(modifiers.get("alt", false)),
		bool(modifiers.get("ctrl", false)),
		false
	)


func _handle_click_binding(
	binding: Dictionary,
	button_index: int,
	input_phase: String = "RELEASE",
	pointer_position: Vector2 = Vector2.ZERO
) -> void:
	var action := String(binding.get("action", ""))
	match action:
		"SELECT_ITEM":
			if not item_id.is_empty():
				item_selected.emit(item_id)
		"OPEN_CONTEXT_MENU":
			if not item_id.is_empty():
				context_requested.emit(item_id, source_container_id, source_slot_index, get_global_mouse_position())
		"CARRY_ALL_OR_PLACE_ALL", "CARRY_HALF_OR_PLACE_ONE", "CARRY_EXACT_OR_PLACE_ONE", "PLACE_ALL_OR_SELECT":
			var payload := view_data.duplicate(true)
			payload["button_index"] = button_index
			payload["input_phase"] = input_phase
			payload["screen_position"] = global_position + pointer_position
			payload["source_cell_screen_position"] = global_position
			payload["source_cell_size"] = size
			payload["pointer_local_position"] = pointer_position
			payload["quantity_mode"] = String(binding.get("quantity_mode", "ALL"))
			payload["target_container_id"] = target_container_id
			payload["target_slot_index"] = target_slot_index
			payload["target_item_id"] = item_id
			payload["icon_texture"] = icon_texture
			interaction_requested.emit(action, payload)
			accept_event()


func _button_mask(button_index: int) -> int:
	match button_index:
		MOUSE_BUTTON_LEFT:
			return MOUSE_BUTTON_MASK_LEFT
		MOUSE_BUTTON_RIGHT:
			return MOUSE_BUTTON_MASK_RIGHT
		MOUSE_BUTTON_MIDDLE:
			return MOUSE_BUTTON_MASK_MIDDLE
		_:
			return 0


func _on_mouse_entered() -> void:
	_carry_hovered = true
	_update_carry_hover()
	if item_id.is_empty():
		return
	item_hovered.emit(view_data.duplicate(true), get_global_rect())


func _on_mouse_exited() -> void:
	_carry_hovered = false
	_update_carry_hover()
	if not item_id.is_empty():
		item_unhovered.emit(item_id)


func _update_carry_hover() -> void:
	set_drop_target_highlight(
		_cursor_carry_active and _carry_target_highlight_enabled and _carry_hovered
	)

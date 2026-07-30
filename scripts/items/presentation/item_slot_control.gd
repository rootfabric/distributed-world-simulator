extends PanelContainer

signal drop_requested(
	item_id: String,
	target_container_id: String,
	target_slot_index: int,
	quantity: int,
	target_item_id: String
)
signal quantity_drop_requested(
	item_id: String,
	target_container_id: String,
	target_slot_index: int,
	total_quantity: int,
	target_item_id: String
)
signal activated(item_id: String, container_id: String, slot_index: int)
signal drag_started(payload: Dictionary)

const Profile = preload("res://scripts/ui/inventory/interactions/inventory_interaction_profile.gd")
const Router = preload("res://scripts/ui/inventory/interactions/inventory_interaction_router.gd")
const RIGHT_DRAG_THRESHOLD_PX: float = 5.0

var item_id: String = ""
var source_container_id: String = ""
var source_slot_index: int = -1
var target_container_id: String = ""
var target_slot_index: int = -1
var icon_texture: Texture2D
var title_text: String = ""
var quantity: int = 0
var selected: bool = false
var drop_target_highlight: bool = false
var drop_validator: Callable
var interaction_profile: InventoryInteractionProfile
var interaction_router := Router.new()
var _armed_buttons: Dictionary = {}
var _press_positions: Dictionary = {}
var _press_modifiers: Dictionary = {}


func setup_slot(data: Dictionary) -> void:
	item_id = String(data.get("item_id", ""))
	source_container_id = String(data.get("source_container_id", ""))
	source_slot_index = int(data.get("source_slot_index", data.get("target_slot_index", -1)))
	target_container_id = String(data.get("target_container_id", source_container_id))
	target_slot_index = int(data.get("target_slot_index", -1))
	icon_texture = data.get("icon_texture") as Texture2D
	title_text = String(data.get("title", "Пусто"))
	quantity = int(data.get("quantity", 0))
	selected = bool(data.get("selected", false))
	drop_validator = data.get("drop_validator", Callable())
	custom_minimum_size = Vector2(56.0, 56.0) if _is_seven_days_style() else Vector2(72.0, 72.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = _tooltip()
	_build_content()


func set_interaction_profile(profile: InventoryInteractionProfile) -> void:
	interaction_profile = profile
	interaction_router.setup(profile)
	custom_minimum_size = Vector2(56.0, 56.0) if _is_seven_days_style() else Vector2(72.0, 72.0)
	if not title_text.is_empty():
		tooltip_text = _tooltip()
	if is_inside_tree() and get_child_count() > 0:
		_build_content()


func set_drop_target_highlight(value: bool) -> void:
	if drop_target_highlight == value:
		return
	drop_target_highlight = value
	if is_inside_tree() and get_child_count() > 0:
		_build_content()


func _build_content() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if _is_seven_days_style():
		_build_seven_days_content()
		return
	var root := VBoxContainer.new()
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(root)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(40.0, 40.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = icon_texture
	root.add_child(icon)
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if item_id.is_empty():
		label.text = "—"
	else:
		label.text = "×%d" % quantity if quantity > 1 else "1"
	label.add_theme_font_size_override("font_size", 12)
	root.add_child(label)
	var style := StyleBoxFlat.new()
	if selected or drop_target_highlight:
		style.bg_color = Color(0.15, 0.42, 0.62, 0.92)
		style.border_color = Color(0.4, 0.82, 1.0)
	else:
		style.bg_color = Color(0.10, 0.12, 0.16, 0.92)
		style.border_color = Color(0.32, 0.36, 0.44)
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	add_theme_stylebox_override("panel", style)


func _build_seven_days_content() -> void:
	var root := Control.new()
	root.custom_minimum_size = Vector2(54.0, 54.0)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var icon := TextureRect.new()
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 3.0
	icon.offset_top = 3.0
	icon.offset_right = -3.0
	icon.offset_bottom = -3.0
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = icon_texture
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(icon)
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	label.offset_left = -42.0
	label.offset_top = -24.0
	label.offset_right = -3.0
	label.offset_bottom = -1.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.text = str(quantity) if not item_id.is_empty() and quantity > 1 else ""
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(label)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.20, 0.20, 0.18, 0.52)
	style.border_color = Color(0.96, 0.84, 0.28, 1.0) if selected or drop_target_highlight else Color(0.04, 0.04, 0.035, 0.96)
	style.set_border_width_all(2 if selected or drop_target_highlight else 1)
	style.set_corner_radius_all(0)
	add_theme_stylebox_override("panel", style)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			return
		if mouse_event.pressed:
			_armed_buttons[mouse_event.button_index] = not item_id.is_empty()
			_press_positions[mouse_event.button_index] = mouse_event.position
			_press_modifiers[mouse_event.button_index] = _modifier_snapshot(mouse_event)
			if mouse_event.double_click and not item_id.is_empty():
				var double_binding := interaction_router.resolve_mouse(
					mouse_event.button_index,
					mouse_event.shift_pressed,
					mouse_event.alt_pressed,
					mouse_event.ctrl_pressed,
					false,
					true
				)
				if interaction_profile == null or String(double_binding.get("action", "")) == "ACTIVATE_SLOT":
					activated.emit(item_id, source_container_id, target_slot_index)
					accept_event()
					return
		else:
			_armed_buttons[mouse_event.button_index] = false
		return
	if not event is InputEventMouseMotion:
		return
	var motion := event as InputEventMouseMotion
	for button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		if not bool(_armed_buttons.get(button_index, false)):
			continue
		var mask := MOUSE_BUTTON_MASK_RIGHT if button_index == MOUSE_BUTTON_RIGHT else MOUSE_BUTTON_MASK_MIDDLE
		if (motion.button_mask & mask) == 0:
			_armed_buttons[button_index] = false
			continue
		var press_position: Vector2 = _press_positions.get(button_index, motion.position)
		if motion.position.distance_to(press_position) < _drag_threshold():
			continue
		_armed_buttons[button_index] = false
		var modifiers := Dictionary(_press_modifiers.get(button_index, {}))
		var binding := _resolve_drag_binding(button_index, modifiers)
		if String(binding.get("action", "")) != "MOVE_TO_TARGET":
			continue
		var payload := build_drag_payload_for_binding(binding)
		if payload.is_empty():
			continue
		drag_started.emit(payload.duplicate(true))
		force_drag(payload, _build_drag_preview(int(payload.get("quantity", 1))))
		accept_event()
		return


func build_drag_payload(ask_quantity_after_drop: bool = false) -> Dictionary:
	if item_id.is_empty():
		return {}
	return {
		"kind": "ITEM_STACK",
		"item_id": item_id,
		"source_container_id": source_container_id,
		"source_slot_index": source_slot_index,
		"quantity": quantity,
		"ask_quantity": ask_quantity_after_drop,
		"outside_drop_action": _outside_drop_action(),
	}


func build_drag_payload_for_binding(binding: Dictionary) -> Dictionary:
	if item_id.is_empty():
		return {}
	var payload := build_drag_payload(bool(binding.get("ask_quantity_after_target", false)))
	payload["quantity"] = interaction_router.quantity_for(binding, quantity) if interaction_profile != null else quantity
	payload["gesture"] = String(binding.get("gesture", ""))
	payload["quantity_mode"] = String(binding.get("quantity_mode", "ALL"))
	return payload


func build_middle_drag_payload() -> Dictionary:
	if item_id.is_empty():
		return {}
	var payload := build_drag_payload(false)
	payload["quantity"] = maxi(1, int(ceil(float(quantity) * 0.5)))
	payload["middle_drag"] = true
	payload["quantity_mode"] = "HALF_CEIL"
	return payload


func _get_drag_data(_at_position: Vector2):
	if item_id.is_empty():
		return null
	var modifiers := Dictionary(_press_modifiers.get(MOUSE_BUTTON_LEFT, {
		"shift": Input.is_key_pressed(KEY_SHIFT),
		"alt": Input.is_key_pressed(KEY_ALT),
		"ctrl": Input.is_key_pressed(KEY_CTRL),
	}))
	var binding := _resolve_drag_binding(MOUSE_BUTTON_LEFT, modifiers)
	if interaction_profile != null and String(binding.get("action", "")) != "MOVE_TO_TARGET":
		return null
	var payload: Dictionary = build_drag_payload_for_binding(binding) if interaction_profile != null else build_drag_payload(false)
	if payload.is_empty():
		return null
	drag_started.emit(payload.duplicate(true))
	set_drag_preview(_build_drag_preview(int(payload.get("quantity", quantity))))
	return payload


func _build_drag_preview(preview_quantity: int) -> Control:
	var preview_root := VBoxContainer.new()
	preview_root.top_level = true
	preview_root.z_as_relative = false
	preview_root.z_index = 4096
	preview_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(48.0, 48.0)
	preview.texture = icon_texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_root.add_child(preview)
	var count_label := Label.new()
	count_label.text = "×%d" % preview_quantity
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_root.add_child(count_label)
	return preview_root


func _can_drop_data(_at_position: Vector2, data) -> bool:
	if not data is Dictionary:
		return false
	if String(data.get("kind", "")) != "ITEM_STACK" or target_container_id.is_empty():
		return false
	if not drop_validator.is_valid():
		return true
	var requested_quantity := 1 if bool(data.get("ask_quantity", false)) else int(data.get("quantity", -1))
	var preview_result = drop_validator.call(
		String(data.get("item_id", "")),
		requested_quantity,
		target_container_id,
		target_slot_index,
		item_id
	)
	return preview_result is Dictionary and bool(preview_result.get("success", false))


func _drop_data(_at_position: Vector2, data) -> void:
	if bool(data.get("ask_quantity", false)):
		quantity_drop_requested.emit(
			String(data.get("item_id", "")),
			target_container_id,
			target_slot_index,
			int(data.get("quantity", 1)),
			item_id
		)
		return
	drop_requested.emit(
		String(data.get("item_id", "")),
		target_container_id,
		target_slot_index,
		int(data.get("quantity", -1)),
		item_id
	)


func _resolve_drag_binding(button_index: int, modifiers: Dictionary) -> Dictionary:
	if interaction_profile == null:
		if button_index == MOUSE_BUTTON_RIGHT:
			return {"action": "MOVE_TO_TARGET", "quantity_mode": "ALL", "ask_quantity_after_target": true}
		if button_index == MOUSE_BUTTON_MIDDLE:
			return {"action": "MOVE_TO_TARGET", "quantity_mode": "HALF_CEIL", "ask_quantity_after_target": false}
		return {"action": "MOVE_TO_TARGET", "quantity_mode": "ALL", "ask_quantity_after_target": false}
	return interaction_router.resolve_mouse(
		button_index,
		bool(modifiers.get("shift", false)),
		bool(modifiers.get("alt", false)),
		bool(modifiers.get("ctrl", false)),
		true
	)


func _modifier_snapshot(event: InputEventMouseButton) -> Dictionary:
	return {
		"shift": event.shift_pressed,
		"alt": event.alt_pressed,
		"ctrl": event.ctrl_pressed,
	}


func _drag_threshold() -> float:
	return interaction_profile.drag_threshold_px if interaction_profile != null else RIGHT_DRAG_THRESHOLD_PX


func _outside_drop_action() -> String:
	return interaction_profile.outside_drop_action() if interaction_profile != null else "DROP_TO_WORLD"


func _is_seven_days_style() -> bool:
	return interaction_profile != null and interaction_profile.ui_style == "SEVEN_DAYS"


func _tooltip() -> String:
	if item_id.is_empty():
		return title_text
	if interaction_profile != null and not interaction_profile.legend.is_empty():
		return title_text + "\n" + "\n".join(interaction_profile.legend)
	return title_text + "\nЛКМ: перенести весь стак\nПКМ + перетаскивание: выбрать количество после выбора цели"

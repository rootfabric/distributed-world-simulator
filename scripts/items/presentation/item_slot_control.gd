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
var drop_validator: Callable
var _right_drag_armed: bool = false
var _right_press_position: Vector2 = Vector2.ZERO


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
	custom_minimum_size = Vector2(72.0, 72.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = _tooltip()
	_build_content()


func _build_content() -> void:
	for child in get_children():
		child.queue_free()
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
	if selected:
		style.bg_color = Color(0.15, 0.42, 0.62, 0.92)
		style.border_color = Color(0.4, 0.82, 1.0)
	else:
		style.bg_color = Color(0.10, 0.12, 0.16, 0.92)
		style.border_color = Color(0.32, 0.36, 0.44)
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	add_theme_stylebox_override("panel", style)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			_right_drag_armed = mouse_event.pressed and not item_id.is_empty()
			_right_press_position = mouse_event.position
			accept_event()
			return
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.double_click:
			activated.emit(item_id, source_container_id, target_slot_index)
			accept_event()
			return
	if event is InputEventMouseMotion and _right_drag_armed:
		var motion := event as InputEventMouseMotion
		if (motion.button_mask & MOUSE_BUTTON_MASK_RIGHT) == 0:
			_right_drag_armed = false
			return
		if motion.position.distance_to(_right_press_position) < RIGHT_DRAG_THRESHOLD_PX:
			return
		_right_drag_armed = false
		var payload := build_drag_payload(true)
		if payload.is_empty():
			return
		force_drag(payload, _build_drag_preview(quantity))
		accept_event()


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
	}


func _get_drag_data(_at_position: Vector2):
	var payload: Dictionary = build_drag_payload(false)
	if payload.is_empty():
		return null
	set_drag_preview(_build_drag_preview(quantity))
	return payload


func _build_drag_preview(preview_quantity: int) -> Control:
	var preview_root := VBoxContainer.new()
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


func _tooltip() -> String:
	if item_id.is_empty():
		return title_text
	return title_text + "\nЛКМ: перенести весь стак\nПКМ + перетаскивание: выбрать количество после выбора цели"

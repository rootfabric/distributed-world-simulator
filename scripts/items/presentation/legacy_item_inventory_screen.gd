extends CanvasLayer

const SlotControl = preload("res://scripts/items/presentation/item_slot_control.gd")

var gameplay_controller
var visible_inventory: bool = false
var external_container_id: String = ""
var root_panel: PanelContainer
var columns: HBoxContainer
var player_grid: GridContainer
var external_section: VBoxContainer
var external_scroll: ScrollContainer
var external_grid: GridContainer
var hotbar_grid: GridContainer
var external_title: Label
var status_label: Label
var icon_cache: Dictionary = {}
var quantity_popup: PopupPanel
var quantity_spin: SpinBox
var quantity_prompt: Label
var pending_item_id: String = ""
var pending_target_container_id: String = ""
var pending_target_slot_index: int = -1
var pending_target_item_id: String = ""
var pending_total_quantity: int = 0


func setup(controller) -> void:
	gameplay_controller = controller
	_build_ui()
	set_inventory_visible(false)


func set_inventory_visible(value: bool) -> void:
	visible_inventory = value
	if root_panel != null:
		root_panel.visible = value
		if value:
			_recenter_panel()
	if not value and quantity_popup != null:
		quantity_popup.hide()


func is_inventory_visible() -> bool:
	return visible_inventory


func _input(event: InputEvent) -> void:
	if not visible_inventory:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		gameplay_controller.set_inventory_visible(false)
		get_viewport().set_input_as_handled()


func open_external_container(container_id: String) -> void:
	external_container_id = container_id
	set_inventory_visible(true)
	refresh()


func close_external_container(refresh_now: bool = true) -> void:
	external_container_id = ""
	if external_section != null:
		external_section.visible = false
	if refresh_now:
		refresh()


func refresh(message: String = "") -> void:
	if gameplay_controller == null or root_panel == null:
		return
	_fill_container_grid(player_grid, gameplay_controller.player_inventory_id, 18)
	_fill_container_grid(hotbar_grid, gameplay_controller.player_hotbar_id, 10, true)
	if external_container_id.is_empty():
		external_section.visible = false
		_clear_grid(external_grid)
		_apply_panel_size(false, 0)
	else:
		var container = gameplay_controller.get_container(external_container_id)
		if container == null:
			close_external_container(false)
			_apply_panel_size(false, 0)
		else:
			external_section.visible = true
			var capacity := _container_visual_capacity(container)
			var columns_count := _columns_for_capacity(capacity)
			external_grid.columns = columns_count
			var mode_label := "SLOTS · %d фиксированных слотов" % container.slot_count if container.is_slot_container() else "BULK · %d/%s стаков · автостак" % [container.item_ids.size(), str(container.slot_count) if container.slot_count > 0 else "∞"]
			external_title.text = "%s\n%s" % [gameplay_controller.get_container_display_name(external_container_id), mode_label]
			_fill_container_grid(external_grid, external_container_id, capacity)
			var rows := maxi(1, ceili(float(capacity) / float(columns_count)))
			external_scroll.custom_minimum_size = Vector2(minf(520.0, columns_count * 76.0 + 12.0), minf(350.0, rows * 76.0 + 12.0))
			_apply_panel_size(true, columns_count)
	if not message.is_empty():
		status_label.text = message


func _build_ui() -> void:
	root_panel = PanelContainer.new()
	root_panel.name = "InventoryRoot"
	# Use viewport coordinates instead of centered anchors.  Canvas stretching can
	# otherwise apply the panel's negative offset against a different canvas size
	# and leave part of the inventory outside the left edge of the window.
	root_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.045, 0.065, 0.97)
	style.border_color = Color(0.22, 0.50, 0.72)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	root_panel.add_theme_stylebox_override("panel", style)
	add_child(root_panel)
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 10)
	root_panel.add_child(main)
	var title := Label.new()
	title.text = "ИНВЕНТАРЬ — ЛКМ переносит стак, ПКМ перетаскивает часть"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	main.add_child(title)
	columns = HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 18)
	main.add_child(columns)
	var left := _make_section("Рюкзак игрока · BULK · автостак")
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	player_grid = GridContainer.new()
	player_grid.columns = 6
	left.add_child(player_grid)
	external_section = _make_section("")
	external_section.visible = false
	columns.add_child(external_section)
	external_title = Label.new()
	external_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	external_title.add_theme_font_size_override("font_size", 17)
	external_section.add_child(external_title)
	external_scroll = ScrollContainer.new()
	external_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	external_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	external_section.add_child(external_scroll)
	external_grid = GridContainer.new()
	external_grid.columns = 4
	external_scroll.add_child(external_grid)
	var hotbar_title := Label.new()
	hotbar_title.text = "Быстрая панель 1–0 · пустой слот сохраняет отдельный стак"
	hotbar_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.add_child(hotbar_title)
	hotbar_grid = GridContainer.new()
	hotbar_grid.columns = 10
	main.add_child(hotbar_grid)
	status_label = Label.new()
	status_label.text = "ЛКМ — весь стак · ПКМ перетащить и затем выбрать количество · Tab — закрыть"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.add_child(status_label)
	_build_quantity_popup()
	_apply_panel_size(false, 0)


func _build_quantity_popup() -> void:
	quantity_popup = PopupPanel.new()
	quantity_popup.name = "StackQuantityPopup"
	quantity_popup.size = Vector2i(440, 190)
	add_child(quantity_popup)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	quantity_popup.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var title := Label.new()
	title.text = "СКОЛЬКО ПЕРЕМЕСТИТЬ?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	column.add_child(title)
	quantity_prompt = Label.new()
	quantity_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(quantity_prompt)
	quantity_spin = SpinBox.new()
	quantity_spin.min_value = 1.0
	quantity_spin.step = 1.0
	quantity_spin.allow_greater = false
	quantity_spin.allow_lesser = false
	column.add_child(quantity_spin)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	var confirm := Button.new()
	confirm.text = "Переместить"
	confirm.pressed.connect(_on_quantity_confirmed)
	buttons.add_child(confirm)
	var cancel := Button.new()
	cancel.text = "Отмена"
	cancel.pressed.connect(_on_quantity_cancelled)
	buttons.add_child(cancel)


func _on_quantity_drop_requested(
	item_id: String,
	target_container_id: String,
	target_slot_index: int,
	total_quantity: int,
	target_item_id: String
) -> void:
	var preview: Dictionary = gameplay_controller.preview_item_quantity_to_container(
		item_id,
		total_quantity,
		target_container_id,
		target_slot_index,
		target_item_id
	)
	if not bool(preview.get("success", false)):
		refresh(gameplay_controller.result_message(preview))
		return
	pending_item_id = item_id
	pending_target_container_id = target_container_id
	pending_target_slot_index = target_slot_index
	pending_target_item_id = target_item_id
	pending_total_quantity = mini(maxi(1, total_quantity), maxi(1, int(preview.get("maximum_quantity", total_quantity))))
	quantity_spin.max_value = float(pending_total_quantity)
	quantity_spin.value = 1.0
	var item = gameplay_controller.get_item(item_id)
	var definition = gameplay_controller.get_definition(item.definition_id) if item != null else null
	var display_name := String(item.display_name) if item != null and not String(item.display_name).is_empty() else (String(definition.display_name) if definition != null else "Предмет")
	var destination: String = String(gameplay_controller.get_container_display_name(target_container_id))
	quantity_prompt.text = "%s · в стаке %d\nКуда: %s" % [display_name, pending_total_quantity, destination]
	quantity_popup.popup_centered(Vector2i(440, 190))


func _on_quantity_confirmed() -> void:
	var result: Dictionary = gameplay_controller.move_item_quantity_to_container(
		pending_item_id,
		int(quantity_spin.value),
		pending_target_container_id,
		pending_target_slot_index,
		pending_target_item_id
	)
	quantity_popup.hide()
	_clear_pending_quantity_drop()
	refresh(gameplay_controller.result_message(result))
	call_deferred("_restore_inventory_focus")


func _on_quantity_cancelled() -> void:
	quantity_popup.hide()
	_clear_pending_quantity_drop()
	call_deferred("_restore_inventory_focus")


func _clear_pending_quantity_drop() -> void:
	pending_item_id = ""
	pending_target_container_id = ""
	pending_target_slot_index = -1
	pending_target_item_id = ""
	pending_total_quantity = 0


func _make_section(title_text: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not title_text.is_empty():
		var label := Label.new()
		label.text = title_text
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 17)
		box.add_child(label)
	return box


func _fill_container_grid(grid: GridContainer, container_id: String, visual_capacity: int, hotbar: bool = false) -> void:
	_clear_grid(grid)
	var container = gameplay_controller.get_container(container_id)
	if container == null:
		return
	if container.is_slot_container():
		for slot_index in range(container.slot_count):
			var item_id: String = String(container.get_item_at_slot(slot_index))
			_add_slot(grid, item_id, container_id, slot_index, hotbar and slot_index == gameplay_controller.selected_hotbar_index, "Слот %d" % (slot_index + 1))
		return
	var visible_ids: Array = container.item_ids.duplicate()
	for item_id in visible_ids:
		_add_slot(grid, String(item_id), container_id, -1, false)
	var total_cells := maxi(visual_capacity, visible_ids.size())
	for _index in range(maxi(0, total_cells - visible_ids.size())):
		_add_slot(grid, "", container_id, -1, false)


func _add_slot(grid: GridContainer, item_id: String, container_id: String, slot_index: int, selected: bool, empty_title: String = "Пусто") -> void:
	var item = gameplay_controller.get_item(item_id) if not item_id.is_empty() else null
	var definition = gameplay_controller.get_definition(item.definition_id) if item != null else null
	var slot = SlotControl.new()
	slot.setup_slot({
		"item_id": item_id,
		"source_container_id": container_id,
		"source_slot_index": slot_index,
		"target_container_id": container_id,
		"target_slot_index": slot_index,
		"icon_texture": _icon_for_definition(definition),
		"title": String(item.display_name) if item != null and not String(item.display_name).is_empty() else (String(definition.display_name) if definition != null else empty_title),
		"quantity": int(item.quantity) if item != null else 0,
		"selected": selected,
		"drop_validator": Callable(gameplay_controller, "preview_item_quantity_to_container"),
	})
	slot.drop_requested.connect(_on_drop_requested)
	slot.quantity_drop_requested.connect(_on_quantity_drop_requested)
	slot.activated.connect(_on_slot_activated)
	grid.add_child(slot)


func _icon_for_definition(definition) -> Texture2D:
	var key := "empty" if definition == null else String(definition.id)
	if icon_cache.has(key):
		return icon_cache[key]
	var color := Color(0.16, 0.18, 0.22, 0.8)
	if definition != null:
		var values = definition.metadata.get("icon_color", [])
		if values is Array and values.size() >= 3:
			color = Color(float(values[0]), float(values[1]), float(values[2]), 1.0)
		elif definition.has_tag("beacon"):
			color = Color(1.0, 0.42, 0.08)
		elif definition.has_tag("battery"):
			color = Color(0.25, 0.85, 0.35)
		elif definition.has_tag("rock"):
			color = Color(0.65, 0.65, 0.70)
		elif definition.has_tag("container"):
			color = Color(0.62, 0.38, 0.14)
	var image := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	image.fill(color)
	for x in range(48):
		image.set_pixel(x, 0, Color.WHITE)
		image.set_pixel(x, 47, Color.WHITE)
	for y in range(48):
		image.set_pixel(0, y, Color.WHITE)
		image.set_pixel(47, y, Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	icon_cache[key] = texture
	return texture


func _clear_grid(grid: GridContainer) -> void:
	for child in grid.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.remove_child(child)
		child.queue_free()


func _on_drop_requested(
	item_id: String,
	target_container_id: String,
	target_slot_index: int,
	quantity: int = -1,
	target_item_id: String = ""
) -> void:
	var result: Dictionary = gameplay_controller.move_item_quantity_to_container(
		item_id,
		quantity,
		target_container_id,
		target_slot_index,
		target_item_id
	)
	if not bool(result.get("success", false)):
		print("[inventory-transfer] failed item=%s target=%s slot=%d quantity=%d target_item=%s code=%s details=%s" % [
			item_id, target_container_id, target_slot_index, quantity, target_item_id,
			String(result.get("error_code", "UNKNOWN")), str(result.get("details", {})),
		])
	refresh(gameplay_controller.result_message(result))


func _on_slot_activated(item_id: String, container_id: String, slot_index: int) -> void:
	if container_id == gameplay_controller.player_hotbar_id and slot_index >= 0:
		gameplay_controller.select_hotbar(slot_index)
		refresh("Выбран быстрый слот %d" % (slot_index + 1))
	elif not item_id.is_empty() and container_id == external_container_id:
		var result: Dictionary = gameplay_controller.move_item_to_container(item_id, gameplay_controller.player_inventory_id)
		refresh(gameplay_controller.result_message(result))


func _container_visual_capacity(container) -> int:
	if container == null:
		return 0
	if container.is_slot_container():
		return maxi(1, int(container.slot_count))
	if int(container.slot_count) > 0:
		return maxi(int(container.slot_count), container.item_ids.size())
	return maxi(6, container.item_ids.size() + 1)


func _columns_for_capacity(capacity: int) -> int:
	if capacity <= 4:
		return maxi(1, capacity)
	if capacity <= 8:
		return 4
	if capacity <= 18:
		return 6
	return 8


func _apply_panel_size(has_external: bool, external_columns: int) -> void:
	var width := 800.0
	if has_external:
		width = minf(1240.0, 800.0 + maxf(310.0, external_columns * 76.0))
	var panel_size := Vector2(width, 600.0)
	root_panel.custom_minimum_size = panel_size
	root_panel.size = panel_size
	_recenter_panel()


func _recenter_panel() -> void:
	if root_panel == null or not is_instance_valid(root_panel):
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_size := viewport.get_visible_rect().size
	root_panel.position = (viewport_size - root_panel.size) * 0.5


func get_external_visible_cell_count() -> int:
	return external_grid.get_child_count() if external_grid != null else 0


func _restore_inventory_focus() -> void:
	if root_panel == null or not visible_inventory:
		return
	root_panel.focus_mode = Control.FOCUS_ALL
	root_panel.grab_focus()

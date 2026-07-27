extends CanvasLayer

signal menu_visibility_changed(opened: bool)

var simulator
var world_catalog
var panel: PanelContainer
var worlds_box: VBoxContainer
var items_box: VBoxContainer
var status_label: Label
var opened: bool = false


func setup(simulator_reference, world_catalog_reference) -> void:
	simulator = simulator_reference
	world_catalog = world_catalog_reference
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	set_open(false)


func _build_ui() -> void:
	panel = PanelContainer.new()
	panel.name = "SystemMenuPanel"
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -500.0
	panel.offset_right = 0.0
	panel.offset_top = 0.0
	panel.offset_bottom = 0.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.035, 0.055, 0.98)
	style.border_color = Color(0.20, 0.55, 0.75)
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "СИСТЕМНОЕ МЕНЮ"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "Закрыть · F10"
	close.pressed.connect(func(): set_open(false))
	header.add_child(close)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)

	content.add_child(_section_title("Быстрые переходы между локациями"))
	worlds_box = VBoxContainer.new()
	worlds_box.add_theme_constant_override("separation", 5)
	content.add_child(worlds_box)

	content.add_child(_section_title("Админская выдача предметов"))
	var admin_hint := Label.new()
	admin_hint.text = "Предметы создаются прямо в BULK-рюкзаке. Кнопка ×100 предназначена для нагрузочной отладки."
	admin_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	admin_hint.modulate = Color(0.70, 0.76, 0.86)
	content.add_child(admin_hint)
	items_box = VBoxContainer.new()
	items_box.add_theme_constant_override("separation", 5)
	content.add_child(items_box)

	content.add_child(_section_title("Основные хоткеи"))
	var hotkeys := Label.new()
	hotkeys.text = (
		"F10 — это меню\n"
		+ "F1 / ` — консоль разработчика\n"
		+ "Tab — инвентарь\n"
		+ "E — взаимодействие или установка предмета\n"
		+ "G — выбросить предмет\n"
		+ "F — круговой фонарь\n"
		+ "1–0 — быстрые слоты\n"
		+ "F5 — камера от первого/третьего лица\n"
		+ "F3 — режим пространства/спектатор"
	)
	content.add_child(hotkeys)

	status_label = Label.new()
	status_label.text = "Готово"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.modulate = Color(0.45, 0.86, 0.68)
	column.add_child(status_label)


func _section_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 17)
	return label


func set_open(value: bool) -> void:
	var changed := opened != value
	opened = value
	if panel != null:
		panel.visible = opened
	if opened:
		refresh()
	if changed:
		menu_visibility_changed.emit(opened)


func is_open() -> bool:
	return opened


func refresh() -> void:
	_refresh_worlds()
	_refresh_items()


func _refresh_worlds() -> void:
	_clear_box(worlds_box)
	if world_catalog == null:
		return
	for world in world_catalog.list_worlds():
		var world_id := String(world.get("id", ""))
		var button := Button.new()
		button.text = "%s  [%s]" % [String(world.get("display_name", world_id)), world_id]
		button.disabled = simulator != null and simulator.current_world_id == world_id
		button.pressed.connect(_on_world_pressed.bind(world_id))
		worlds_box.add_child(button)


func _refresh_items() -> void:
	_clear_box(items_box)
	if simulator == null:
		return
	var catalog: Array[Dictionary] = simulator.get_debug_item_catalog()
	if catalog.is_empty():
		var unavailable := Label.new()
		unavailable.text = "В текущей локации предметный runtime недоступен."
		unavailable.modulate = Color(0.86, 0.58, 0.38)
		items_box.add_child(unavailable)
		return
	for row in catalog:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		var label := Label.new()
		label.text = "%s\n%s" % [String(row.get("display_name", "Предмет")), String(row.get("definition_id", ""))]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(label)
		var one := Button.new()
		one.text = "×1"
		one.pressed.connect(_on_grant_pressed.bind(String(row.get("definition_id", "")), 1))
		line.add_child(one)
		var hundred := Button.new()
		hundred.text = "×100"
		hundred.pressed.connect(_on_grant_pressed.bind(String(row.get("definition_id", "")), 100))
		line.add_child(hundred)
		items_box.add_child(line)


func _on_world_pressed(world_id: String) -> void:
	var result: Dictionary = simulator.load_world(world_id) if simulator != null else {"success": false, "output": "Simulator недоступен"}
	status_label.text = String(result.get("output", result.get("message", "")))
	if bool(result.get("success", false)):
		call_deferred("refresh")


func _on_grant_pressed(definition_id: String, quantity: int) -> void:
	var result: Dictionary = simulator.grant_debug_item(definition_id, quantity) if simulator != null else {"success": false, "message": "Simulator недоступен"}
	status_label.text = String(result.get("message", result.get("output", "")))
	_refresh_items()


func _clear_box(box: VBoxContainer) -> void:
	if box == null:
		return
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()

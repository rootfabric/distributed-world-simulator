extends CanvasLayer

var main_controller
var moon_world
var player
var spectator
var zone_manager
var entity_registry
var persistence
var logger

var panel: PanelContainer
var compact_hint: Label
var info_label: Label
var help_label: Label
var precision_label: Label
var crosshair: Label
var interaction_panel: PanelContainer
var interaction_title: Label
var interaction_details: Label
var interaction_prompt: Label
var interaction_snapshot: Dictionary = {}
var menu_visible: bool = true
var spectator_mode: bool = false
var pointer_captured: bool = true


func setup(
	main_reference: Node,
	moon_reference,
	player_reference,
	spectator_reference,
	zone_manager_reference = null,
	entity_registry_reference = null,
	persistence_reference = null,
	logger_reference = null
) -> void:
	main_controller = main_reference
	moon_world = moon_reference
	player = player_reference
	spectator = spectator_reference
	zone_manager = zone_manager_reference
	entity_registry = entity_registry_reference
	persistence = persistence_reference
	logger = logger_reference

	panel = PanelContainer.new()
	panel.position = Vector2(18.0, 18.0)
	panel.size = Vector2(900.0, 680.0)
	add_child(panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.018, 0.022, 0.035, 0.91)
	panel_style.border_color = Color(0.25, 0.30, 0.40, 0.72)
	panel_style.set_border_width_all(1)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	var vertical := VBoxContainer.new()
	vertical.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vertical.add_theme_constant_override("separation", 5)
	scroll.add_child(vertical)

	var title := Label.new()
	title.text = "PLANETARY WORLD — ITEMS + INTERACTION + STREAMING"
	title.add_theme_font_size_override("font_size", 19)
	vertical.add_child(title)

	precision_label = Label.new()
	precision_label.add_theme_font_size_override("font_size", 13)
	vertical.add_child(precision_label)

	info_label = Label.new()
	info_label.add_theme_font_size_override("font_size", 14)
	vertical.add_child(info_label)

	help_label = Label.new()
	help_label.text = (
		"~ — консоль   F1 — команды   F2 — игрок к спектатору\n"
		+ "F3 — игрок/спектатор   F4 — показать LOD   Tab — мышь\n"
		+ "WASD, Shift, Space — движение   Q/E — крен спектатора\n"
		+ "Вся функциональность доступна командами независимо от выбранного мира.\n"
		+ "Начните с: help, world.list, test.list, runtime.snapshot"
	)
	help_label.add_theme_font_size_override("font_size", 13)
	help_label.modulate = Color(0.78, 0.82, 0.90)
	vertical.add_child(help_label)

	var controller_row := HBoxContainer.new()
	controller_row.add_theme_constant_override("separation", 8)
	vertical.add_child(controller_row)
	_add_button(controller_row, "Камера 1/3 лицо", _on_camera_mode_pressed)
	_add_button(controller_row, "Lunar EVA / Jetpack", _on_controller_toggle_pressed)
	_add_button(controller_row, "Тест контроллера", _on_controller_test_pressed)

	var streaming_row := HBoxContainer.new()
	streaming_row.add_theme_constant_override("separation", 8)
	vertical.add_child(streaming_row)
	_add_button(streaming_row, "Streaming-тест", _on_streaming_test_pressed)
	_add_button(streaming_row, "Сохранить диагностику", _on_diagnostic_pressed)

	var placement_row := HBoxContainer.new()
	placement_row.add_theme_constant_override("separation", 8)
	vertical.add_child(placement_row)
	_add_button(placement_row, "Поставить маяк", _on_place_beacon_pressed)
	_add_button(placement_row, "Удалить ближайший", _on_remove_beacon_pressed)
	_add_button(placement_row, "Метки маяков", _on_toggle_markers_pressed)
	_add_button(placement_row, "Сохранить мир", _on_save_world_pressed)

	var test_row := HBoxContainer.new()
	test_row.add_theme_constant_override("separation", 8)
	vertical.add_child(test_row)
	_add_button(test_row, "Тест миграции", _on_migration_test_pressed)
	_add_button(test_row, "Тест сохранения", _on_persistence_test_pressed)
	_add_button(test_row, "Лаборатория предметов", _on_item_lab_pressed)

	var world_row := HBoxContainer.new()
	world_row.add_theme_constant_override("separation", 8)
	vertical.add_child(world_row)
	_add_button(world_row, "Случайная точка", _on_random_spawn_pressed)
	_add_button(world_row, "Очистить постоянный слой", _on_clear_world_pressed)
	_add_button(world_row, "Закрыть меню", _on_close_pressed)

	compact_hint = Label.new()
	compact_hint.text = "F2 — ТП игрока | F3 — спектатор | F4 — LOD | Q/E — крен | ~ — консоль"
	compact_hint.position = Vector2(18.0, 18.0)
	compact_hint.add_theme_font_size_override("font_size", 15)
	compact_hint.modulate = Color(0.90, 0.93, 1.0, 0.92)
	add_child(compact_hint)

	crosshair = Label.new()
	crosshair.text = "+"
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-12.0, -15.0)
	crosshair.size = Vector2(24.0, 30.0)
	crosshair.add_theme_font_size_override("font_size", 20)
	crosshair.modulate = Color(0.92, 0.95, 1.0, 0.88)
	add_child(crosshair)

	interaction_panel = PanelContainer.new()
	interaction_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	# Keep the contextual object card above the persistent hotbar. The latter
	# occupies the bottom 94 px of the viewport including its lower inset.
	interaction_panel.position = Vector2(-250.0, -226.0)
	interaction_panel.size = Vector2(500.0, 112.0)
	interaction_panel.visible = false
	add_child(interaction_panel)

	var interaction_style := StyleBoxFlat.new()
	interaction_style.bg_color = Color(0.012, 0.016, 0.026, 0.90)
	interaction_style.border_color = Color(0.95, 0.45, 0.12, 0.78)
	interaction_style.set_border_width_all(1)
	interaction_style.set_corner_radius_all(6)
	interaction_panel.add_theme_stylebox_override("panel", interaction_style)

	var interaction_margin := MarginContainer.new()
	interaction_margin.add_theme_constant_override("margin_left", 12)
	interaction_margin.add_theme_constant_override("margin_right", 12)
	interaction_margin.add_theme_constant_override("margin_top", 8)
	interaction_margin.add_theme_constant_override("margin_bottom", 8)
	interaction_panel.add_child(interaction_margin)

	var interaction_column := VBoxContainer.new()
	interaction_column.add_theme_constant_override("separation", 2)
	interaction_margin.add_child(interaction_column)

	interaction_title = Label.new()
	interaction_title.add_theme_font_size_override("font_size", 17)
	interaction_column.add_child(interaction_title)

	interaction_details = Label.new()
	interaction_details.add_theme_font_size_override("font_size", 13)
	interaction_details.modulate = Color(0.82, 0.86, 0.92)
	interaction_column.add_child(interaction_details)

	interaction_prompt = Label.new()
	interaction_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_prompt.add_theme_font_size_override("font_size", 15)
	interaction_prompt.modulate = Color(1.0, 0.60, 0.20)
	interaction_column.add_child(interaction_prompt)

	var capture_hint := Label.new()
	capture_hint.text = "Клик по окну возвращает управление мышью"
	capture_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	capture_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	capture_hint.offset_top = -40.0
	capture_hint.offset_bottom = -8.0
	capture_hint.add_theme_font_size_override("font_size", 15)
	add_child(capture_hint)

	_update_precision_label()
	set_menu_visible(true)


func _add_button(parent: Control, text_value: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text_value
	button.pressed.connect(callback)
	parent.add_child(button)


func set_menu_visible(visible_value: bool) -> void:
	menu_visible = visible_value
	if panel != null:
		panel.visible = visible_value
	if compact_hint != null:
		compact_hint.visible = not visible_value
	_refresh_interaction_visibility()


func set_interaction_state(snapshot: Dictionary) -> void:
	interaction_snapshot = snapshot.duplicate(true)
	if interaction_snapshot.is_empty():
		_refresh_interaction_visibility()
		return
	if interaction_title != null:
		interaction_title.text = String(
			interaction_snapshot.get("title", "Объект")
		)
	if interaction_details != null:
		var distance_m: float = float(
			interaction_snapshot.get("distance_m", 0.0)
		)
		var details: String = String(
			interaction_snapshot.get("details", "")
		)
		interaction_details.text = "%s\nДистанция: %.1f м" % [details, distance_m]
	if interaction_prompt != null:
		interaction_prompt.text = String(
			interaction_snapshot.get("prompt", "E — взаимодействовать")
		)
	_refresh_interaction_visibility()


func _refresh_interaction_visibility() -> void:
	var gameplay_visible: bool = (
		not menu_visible
		and not spectator_mode
		and pointer_captured
		and player != null
		and player.get_camera_mode() == "first_person"
	)
	if crosshair != null:
		crosshair.visible = gameplay_visible
	if interaction_panel != null:
		interaction_panel.visible = (
			gameplay_visible and not interaction_snapshot.is_empty()
		)


func is_menu_visible() -> bool:
	return menu_visible


func _run_command(command_line: String) -> void:
	if main_controller != null and main_controller.has_method("execute_runtime_command"):
		main_controller.execute_runtime_command(command_line)


func _on_camera_mode_pressed() -> void:
	_run_command("player.camera.toggle")


func _on_controller_toggle_pressed() -> void:
	_run_command("player.controller.toggle")


func _on_controller_test_pressed() -> void:
	_run_command("test.controller")


func _on_streaming_test_pressed() -> void:
	_run_command("test.terrain_streaming")


func _on_place_beacon_pressed() -> void:
	_run_command("world.beacon.place")


func _on_remove_beacon_pressed() -> void:
	_run_command("world.beacon.remove_nearest")


func _on_toggle_markers_pressed() -> void:
	_run_command("world.beacon.markers.toggle")


func _on_save_world_pressed() -> void:
	_run_command("world.save")


func _on_migration_test_pressed() -> void:
	_run_command("test.entity_migration")


func _on_persistence_test_pressed() -> void:
	_run_command("test.persistence_roundtrip")


func _on_diagnostic_pressed() -> void:
	_run_command("diagnostics.save")


func _on_item_lab_pressed() -> void:
	_run_command("item.lab.open")


func _on_random_spawn_pressed() -> void:
	_run_command("player.spawn.random")


func _on_clear_world_pressed() -> void:
	_run_command("world.persistence.clear confirm")


func _on_close_pressed() -> void:
	_run_command("ui.menu.toggle")

func update_values(
	spectator_enabled: bool,
	mouse_captured: bool,
	_player_position: Vector3,
	active_position: Vector3
) -> void:
	if moon_world == null or info_label == null:
		return
	spectator_mode = spectator_enabled
	pointer_captured = mouse_captured
	_refresh_interaction_visibility()
	var mode_text: String = "СПЕКТАТОР" if spectator_enabled else "ПЕРСОНАЖ"
	var altitude: float = moon_world.get_altitude(active_position)
	var direction := active_position.normalized()
	var latitude: float = rad_to_deg(asin(clampf(direction.y, -1.0, 1.0)))
	var longitude: float = rad_to_deg(atan2(direction.z, direction.x))
	var capture_text: String = "захвачена" if mouse_captured else "свободна"
	var partition_text: String = (
		zone_manager.get_runtime_summary() if zone_manager != null else "инициализация"
	)
	var entity_text: String = (
		entity_registry.get_runtime_summary() if entity_registry != null else "инициализация"
	)
	var persistence_text: String = (
		persistence.get_runtime_summary() if persistence != null else "инициализация"
	)
	var terrain_streaming_text: String = moon_world.get_terrain_streaming_summary()
	var extra_text: String = ""
	if spectator_enabled and spectator != null:
		extra_text = "\nСкорость спектатора: %s м/с" % _format_number(
			spectator.get_movement_speed()
		)
	info_label.text = (
		(
			"Режим: %s   |   мышь: %s   |   %s %s\n"
			+ "Контроллер: %s   |   Камера: %s\n"
			+ "Тест контроллера: %s\n"
			+ "Terrain streaming: %s\n"
			+ "Тест streaming: %s\n"
			+ "Разбиение: %s\n"
			+ "Сущности: %s\n"
			+ "Хранилище: %s\n"
			+ "Навигационные метки: %s\n"
			+ "Тест миграции: %s\n"
			+ "Тест persistence: %s\n"
			+ "Последнее действие: %s\n"
			+ "World manifest: %s\n"
			+ "Диагностика: %s\n"
			+ "LOD: %s\n"
			+ "Стек: %s\n"
			+ "Материал: %s   Регион: %s\n"
			+ "Высота: %s м   Широта: %.4f°   Долгота: %.4f°%s"
		)
		% [
			mode_text,
			capture_text,
			main_controller.get_display_mode_name(),
			main_controller.get_display_resolution_name(),
			player.get_controller_display_name(),
			player.get_camera_mode_display_name(),
			main_controller.get_last_controller_test_result(),
			terrain_streaming_text,
			main_controller.get_last_terrain_streaming_test_result(),
			partition_text,
			entity_text,
			persistence_text,
			main_controller.get_beacon_marker_summary(),
			main_controller.get_last_mini_test_result(),
			main_controller.get_last_persistence_test_result(),
			main_controller.get_last_action_result(),
			persistence.get_manifest_path() if persistence != null else "-",
			main_controller.get_last_diagnostic_path(),
			moon_world.get_lod_name(),
			moon_world.get_layer_stack_name(),
			moon_world.get_surface_style_name(),
			moon_world.get_region_name(direction),
			_format_number(altitude),
			latitude,
			longitude,
			extra_text,
		]
	)


func _update_precision_label() -> void:
	var test_value := Vector3(1_000_000_000.125, 0.0, 0.0)
	var double_precision_detected: bool = (
		absf(test_value.x - 1_000_000_000.125) < 0.01
	)
	if double_precision_detected:
		precision_label.text = "✓ Double precision обнаружена   Радиус: 1 737 400 м"
		precision_label.modulate = Color(0.46, 0.92, 0.58)
	else:
		precision_label.text = "⚠ Запущена single-сборка. Нужен Godot precision=double."
		precision_label.modulate = Color(1.0, 0.52, 0.30)


func _format_number(value: float) -> String:
	var absolute_value: float = absf(value)
	if absolute_value >= 1_000_000.0:
		return "%.2f млн" % (value / 1_000_000.0)
	if absolute_value >= 1000.0:
		return "%.1f тыс." % (value / 1000.0)
	return "%.1f" % value

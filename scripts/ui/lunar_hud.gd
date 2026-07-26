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
var menu_visible: bool = true


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
	title.text = "REAL SCALE PROCEDURAL MOON — ASYNC TERRAIN STREAMING"
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
		"C — первое/третье лицо   J — Lunar EVA/Jetpack   F12 — тест контроллера\n"
		+ "K — тест фоновой генерации и staged commit\n"
		+ "Lunar EVA: WASD, Shift, Space   Jetpack: WASD, Space/Ctrl, Shift\n"
		+ "B — поставить Survey Beacon   Delete — удалить ближайший маяк\n"
		+ "Ctrl+S — сохранить мир   F10 — тест persistence   F7 — миграция\n"
		+ "F9 — диагностика   F3 — спектатор   T — телепорт из спектатора\n"
		+ "F2 — LOD follow   F4 — цвета LOD   V — материал\n"
		+ "F8 — разрешение   F11 — полный экран   F6/R — случайная точка"
	)
	help_label.add_theme_font_size_override("font_size", 13)
	help_label.modulate = Color(0.78, 0.82, 0.90)
	vertical.add_child(help_label)

	var controller_row := HBoxContainer.new()
	controller_row.add_theme_constant_override("separation", 8)
	vertical.add_child(controller_row)
	_add_button(controller_row, "Камера 1/3 лицо (C)", _on_camera_mode_pressed)
	_add_button(controller_row, "Lunar EVA / Jetpack (J)", _on_controller_toggle_pressed)
	_add_button(controller_row, "Тест контроллера (F12)", _on_controller_test_pressed)

	var streaming_row := HBoxContainer.new()
	streaming_row.add_theme_constant_override("separation", 8)
	vertical.add_child(streaming_row)
	_add_button(streaming_row, "Тест фоновой генерации (K)", _on_streaming_test_pressed)
	_add_button(streaming_row, "Сохранить диагностику (F9)", _on_diagnostic_pressed)

	var placement_row := HBoxContainer.new()
	placement_row.add_theme_constant_override("separation", 8)
	vertical.add_child(placement_row)
	_add_button(placement_row, "Поставить маяк (B)", _on_place_beacon_pressed)
	_add_button(placement_row, "Удалить ближайший (Delete)", _on_remove_beacon_pressed)
	_add_button(placement_row, "Сохранить мир (Ctrl+S)", _on_save_world_pressed)

	var test_row := HBoxContainer.new()
	test_row.add_theme_constant_override("separation", 8)
	vertical.add_child(test_row)
	_add_button(test_row, "Тест миграции (F7)", _on_migration_test_pressed)
	_add_button(test_row, "Тест сохранения (F10)", _on_persistence_test_pressed)

	var world_row := HBoxContainer.new()
	world_row.add_theme_constant_override("separation", 8)
	vertical.add_child(world_row)
	_add_button(world_row, "Случайная точка (F6/R)", _on_random_spawn_pressed)
	_add_button(world_row, "Очистить постоянный слой", _on_clear_world_pressed)
	_add_button(world_row, "Закрыть меню (F1/Esc)", _on_close_pressed)

	compact_hint = Label.new()
	compact_hint.text = "F1/Esc — меню | C — камера | J — контроллер | K — streaming test | B — маяк"
	compact_hint.position = Vector2(18.0, 18.0)
	compact_hint.add_theme_font_size_override("font_size", 15)
	compact_hint.modulate = Color(0.90, 0.93, 1.0, 0.92)
	add_child(compact_hint)

	var capture_hint := Label.new()
	capture_hint.text = "Клик по окну возвращает управление мышью"
	capture_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	capture_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	capture_hint.position = Vector2(0.0, -40.0)
	capture_hint.size = Vector2(0.0, 32.0)
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


func is_menu_visible() -> bool:
	return menu_visible


func _on_camera_mode_pressed() -> void:
	main_controller.toggle_player_camera()


func _on_controller_toggle_pressed() -> void:
	main_controller.toggle_player_controller()


func _on_controller_test_pressed() -> void:
	main_controller.run_controller_mini_test()


func _on_streaming_test_pressed() -> void:
	main_controller.run_terrain_streaming_mini_test()


func _on_place_beacon_pressed() -> void:
	main_controller.place_survey_beacon()


func _on_remove_beacon_pressed() -> void:
	main_controller.remove_nearest_survey_beacon()


func _on_save_world_pressed() -> void:
	main_controller.save_world_now()


func _on_migration_test_pressed() -> void:
	main_controller.run_entity_migration_mini_test()


func _on_persistence_test_pressed() -> void:
	main_controller.run_persistence_mini_test()


func _on_diagnostic_pressed() -> void:
	main_controller.save_diagnostic_snapshot()


func _on_random_spawn_pressed() -> void:
	main_controller.random_spawn()


func _on_clear_world_pressed() -> void:
	main_controller.clear_persistent_world()


func _on_close_pressed() -> void:
	main_controller.toggle_menu()


func update_values(
	spectator_enabled: bool,
	mouse_captured: bool,
	_player_position: Vector3,
	active_position: Vector3
) -> void:
	if moon_world == null or info_label == null:
		return
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

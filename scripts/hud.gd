extends CanvasLayer

var main_controller
var moon_world
var player
var spectator

var info_label: Label
var help_label: Label
var precision_label: Label


func setup(
	main_reference: Node,
	moon_reference,
	player_reference,
	spectator_reference
) -> void:
	main_controller = main_reference
	moon_world = moon_reference
	player = player_reference
	spectator = spectator_reference

	var panel := PanelContainer.new()
	panel.position = Vector2(18.0, 18.0)
	panel.size = Vector2(590.0, 348.0)
	add_child(panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.018, 0.022, 0.035, 0.88)
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

	var vertical := VBoxContainer.new()
	vertical.add_theme_constant_override("separation", 5)
	margin.add_child(vertical)

	var title := Label.new()
	title.text = "REAL SCALE PROCEDURAL MOON"
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
		"WASD — движение   Shift — ускорение   Space/Ctrl — вверх/вниз\n"
		+ "Q/E — крен спектатора   H — выровнять горизонт\n"
		+ "T — персонаж на поверхность под спектатором\n"
		+ "F3 — персонаж/спектатор   F6 или R — случайная точка\n"
		+ "Колесо — скорость спектатора   Tab/Esc — захват курсора"
	)
	help_label.add_theme_font_size_override("font_size", 13)
	help_label.modulate = Color(0.78, 0.82, 0.90)
	vertical.add_child(help_label)

	var random_spawn_button := Button.new()
	random_spawn_button.text = "Случайная точка Луны  (F6 / R)"
	random_spawn_button.pressed.connect(_on_random_spawn_pressed)
	vertical.add_child(random_spawn_button)

	var capture_hint := Label.new()
	capture_hint.text = "Клик по окну возвращает управление мышью"
	capture_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	capture_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	capture_hint.position = Vector2(0.0, -40.0)
	capture_hint.size = Vector2(0.0, 32.0)
	capture_hint.add_theme_font_size_override("font_size", 15)
	add_child(capture_hint)

	_update_precision_label()


func _on_random_spawn_pressed() -> void:
	if main_controller != null:
		main_controller.random_spawn()


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

	var extra_text: String = ""
	if spectator_enabled and spectator != null:
		extra_text = "\nСкорость спектатора: %s м/с" % _format_number(
			spectator.get_movement_speed()
		)

	info_label.text = (
		(
			"Режим: %s   |   мышь: %s\n"
			+ "LOD: %s\n"
			+ "Детализация: %s\n"
			+ "Регион: %s\n"
			+ "Высота: %s м\n"
			+ "Широта: %.4f°   Долгота: %.4f°%s"
		)
		% [
			mode_text,
			capture_text,
			moon_world.get_lod_name(),
			moon_world.get_detail_name(),
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
		precision_label.text = (
			"✓ Double precision обнаружена   Радиус: 1 737 400 м"
		)
		precision_label.modulate = Color(0.46, 0.92, 0.58)
	else:
		precision_label.text = (
			"⚠ Запущена single-сборка. Нужен Godot precision=double."
		)
		precision_label.modulate = Color(1.0, 0.52, 0.30)


func _format_number(value: float) -> String:
	var absolute_value: float = absf(value)

	if absolute_value >= 1_000_000.0:
		return "%.2f млн" % (value / 1_000_000.0)
	if absolute_value >= 1000.0:
		return "%.1f тыс." % (value / 1000.0)

	return "%.1f" % value

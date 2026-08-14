extends CanvasLayer

var panel: PanelContainer
var label: Label
var minimize_button: Button
var close_button: Button
var _content: VBoxContainer
var _minimized: bool = true
var _overlay_visible: bool = false


func setup() -> void:
	layer = 90
	panel = PanelContainer.new()
	panel.name = "PlanetaryArchitecturePanel"
	panel.position = Vector2(18.0, 18.0)
	panel.custom_minimum_size = Vector2(260.0, 0.0)
	panel.visible = false
	add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.022, 0.035, 0.90)
	style.border_color = Color(0.20, 0.44, 0.62, 0.92)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", style)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 6)
	panel.add_child(_content)

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_PASS
	_content.add_child(header)

	var title := Label.new()
	title.text = "MVP DEBUG"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 13)
	header.add_child(title)

	minimize_button = Button.new()
	minimize_button.text = "□"
	minimize_button.tooltip_text = "Свернуть/развернуть debug HUD"
	minimize_button.focus_mode = Control.FOCUS_NONE
	minimize_button.custom_minimum_size = Vector2(34.0, 26.0)
	minimize_button.pressed.connect(_toggle_minimized)
	header.add_child(minimize_button)

	close_button = Button.new()
	close_button.text = "×"
	close_button.tooltip_text = "Скрыть debug HUD (F1 — показать)"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(34.0, 26.0)
	close_button.pressed.connect(_hide_overlay)
	header.add_child(close_button)

	label = Label.new()
	label.name = "PlanetaryArchitectureLabel"
	label.add_theme_font_size_override("font_size", 15)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.visible = false
	_content.add_child(label)
	set_process_input(true)


func _toggle_minimized() -> void:
	_set_minimized(not _minimized)


func _set_minimized(value: bool) -> void:
	_minimized = value
	if label != null:
		label.visible = not value
	if panel != null:
		panel.custom_minimum_size = Vector2(260.0, 0.0) if value else Vector2(620.0, 0.0)
	if minimize_button != null:
		minimize_button.text = "□" if value else "—"


func _hide_overlay() -> void:
	_overlay_visible = false
	if panel != null:
		panel.visible = false


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode != KEY_F1 and key_event.physical_keycode != KEY_F1:
		return
	_overlay_visible = not _overlay_visible
	if panel != null:
		panel.visible = _overlay_visible
	get_viewport().set_input_as_handled()


func show_moon_mode(distance_m: float) -> void:
	label.text = (
		"АРХИТЕКТУРНЫЙ ТЕСТ: ЗЕМЛЯ + ЛУНА\n"
		+ "Обычный режим Луны v15.2\n"
		+ "Расстояние между центрами: %.1f км\n"
		+ "~ — консоль | space.mode.toggle — включить общее пространство"
	) % (distance_m / 1000.0)


func show_shared_space_mode(
	celestial_system,
	earth_world,
	moon_world,
	explorer,
	nearest_body_id: String,
	distance_m: float,
	atmosphere_manager,
	visible_body_ids: Array[String]
) -> void:
	var space_position: Vector3 = explorer.get_world_position()
	var earth_only: bool = (
		visible_body_ids.size() == 1 and visible_body_ids.has("earth")
	)
	var earth_local: Vector3 = celestial_system.to_body_local(space_position, "earth")
	var moon_local: Vector3 = (
		Vector3.ZERO
		if earth_only
		else celestial_system.to_body_local(space_position, "moon")
	)
	var earth_surface_distance: float = (
		earth_world.get_altitude(earth_local)
		if earth_only
		else celestial_system.get_surface_distance("earth", space_position)
	)
	var moon_surface_distance: float = (
		0.0
		if earth_only
		else celestial_system.get_surface_distance("moon", space_position)
	)
	var body_description: String
	var local_description: String
	if nearest_body_id == "earth":
		var earth_direction: Vector3 = (
			earth_local.normalized()
			if earth_local.length_squared() > 1.0
			else Vector3.UP
		)
		var state: Dictionary = earth_world.get_surface_state(earth_direction, 0)
		body_description = (
			"Земля | высота %.1f м | биом %s | LOD %s | debug %s"
			% [
				earth_world.get_altitude(earth_local),
				earth_world.get_biome_name_at(earth_direction),
				earth_world.current_lod_tier,
				earth_world.get_debug_view_name(),
			]
		)
		local_description = (
			"Снег %.2f | деревья %.2f | трава %.2f | камни %.2f | hint-склон %.1f°"
			% [
				float(state.get("snow_mask", 0.0)),
				float(state.get("tree_density", 0.0)),
				float(state.get("grass_density", 0.0)),
				float(state.get("rock_density", 0.0)),
				float(state.get("slope_hint_deg", 0.0)),
			]
		)
	else:
		var moon_direction: Vector3 = (
			moon_local.normalized()
			if moon_local.length_squared() > 1.0
			else Vector3.UP
		)
		body_description = (
			"Луна | высота %.1f м | регион %s | LOD %s"
			% [
				moon_world.get_altitude(moon_local),
				moon_world.get_region_name(moon_direction),
				moon_world.get_lod_name(),
			]
		)
		local_description = "Лунная генерация работает исходным конвейером v15.2"

	var atmosphere_description: String = "Атмосфера: отсутствует в текущей зоне"
	if atmosphere_manager != null:
		var atmosphere_summary: Dictionary = atmosphere_manager.get_runtime_summary()
		if bool(atmosphere_summary.get("active", false)):
			atmosphere_description = (
				"Атмосфера %s | высота %.1f м | интенсивность %.2f | плагины %s"
				% [
					String(atmosphere_summary.get("body_id", "unknown")),
					float(atmosphere_summary.get("altitude_m", 0.0)),
					float(atmosphere_summary.get("intensity", 0.0)),
					_join_strings(atmosphere_summary.get("plugins", [])),
				]
			)

	var statistics: Dictionary = earth_world.get_local_mesh_statistics()
	var world_title: String = (
		"МИР: ЗЕМЛЯ"
		if earth_only
		else "ЕДИНОЕ ПРОСТРАНСТВО: ЗЕМЛЯ + ЛУНА"
	)
	var distance_description: String = (
		"До процедурной поверхности Земли %.3f км"
		% (earth_surface_distance / 1000.0)
		if earth_only
		else "До поверхности: Луна %.1f км | Земля %.1f км | центры %.1f км" % [
			moon_surface_distance / 1000.0,
			earth_surface_distance / 1000.0,
			distance_m / 1000.0,
		]
	)
	var coordinate_description: String = _coordinate_description(
		earth_world,
		explorer,
		earth_local,
		space_position,
		earth_only
	)
	var controls_description: String = (
		"WASD — движение | мышь — обзор | H — горизонт | F1 — debug HUD"
		if explorer.has_method("is_network_replica_mode") and explorer.is_network_replica_mode()
		else "WASD/Q/E — движение и крен | Shift — ускорение | колесо — скорость | H — горизонт | F1 — debug HUD"
	)
	label.text = (
		"%s\n"
		+ "%s\n"
		+ "%s\n"
		+ "%s\n"
		+ "%s\n"
		+ "%s\n"
		+ "Патч Земли: min %.1f м | max %.1f м | перепад %.1f м | geom-склон max %.1f°\n"
		+ "~ — консоль | earth.teleport.biome <name> | space.teleport.body <id>\n"
		+ "%s"
	) % [
		world_title,
		body_description,
		coordinate_description,
		distance_description,
		local_description,
		atmosphere_description,
		float(statistics.get("minimum_elevation_m", 0.0)),
		float(statistics.get("maximum_elevation_m", 0.0)),
		float(statistics.get("relief_range_m", 0.0)),
		float(statistics.get("maximum_geometric_slope_deg", 0.0)),
		controls_description,
	]


func _coordinate_description(
	earth_world,
	explorer,
	earth_local: Vector3,
	space_position: Vector3,
	earth_only: bool
) -> String:
	var network_replica: bool = (
		explorer.has_method("is_network_replica_mode")
		and explorer.is_network_replica_mode()
	)
	if earth_only:
		var spawn_direction: Vector3 = earth_world.get_canonical_spawn_direction()
		var spawn_altitude: float = earth_world.get_canonical_spawn_altitude_m()
		var spawn_position: Vector3 = (
			earth_world.get_surface_point(spawn_direction)
			+ spawn_direction * spawn_altitude
		)
		var east: Vector3 = Vector3.UP.cross(spawn_direction)
		if east.length_squared() < 0.000001:
			east = Vector3.RIGHT.cross(spawn_direction)
		east = east.normalized()
		var north: Vector3 = spawn_direction.cross(east).normalized()
		var offset: Vector3 = earth_local - spawn_position
		var local_x: float = offset.dot(east)
		var local_z: float = offset.dot(north)
		return "%s | MVP локально X/Z: %.2f / %.2f м | frame %s" % [
			"СЕТЬ: authoritative replica" if network_replica else "ЛОКАЛЬНЫЙ observer",
			local_x,
			local_z,
			String(explorer.get_reference_frame_id()),
		]
	return "Скорость %.1f м/с | root координаты: [%.1f, %.1f, %.1f] км" % [
		explorer.get_movement_speed(),
		space_position.x / 1000.0,
		space_position.y / 1000.0,
		space_position.z / 1000.0,
	]


func _join_strings(values) -> String:
	var parts := PackedStringArray()
	if values is Array:
		for value in values:
			parts.append(String(value))
	return ", ".join(parts)

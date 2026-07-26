extends CanvasLayer

var panel: PanelContainer
var label: Label


func setup() -> void:
	layer = 90
	panel = PanelContainer.new()
	panel.name = "PlanetaryArchitecturePanel"
	panel.position = Vector2(18.0, 18.0)
	panel.custom_minimum_size = Vector2(620.0, 0.0)
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
	label = Label.new()
	label.name = "PlanetaryArchitectureLabel"
	label.add_theme_font_size_override("font_size", 15)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(label)


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
	var earth_surface_distance: float = celestial_system.get_surface_distance(
		"earth",
		space_position
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
		"До поверхности Земли %.1f км"
		% (earth_surface_distance / 1000.0)
		if earth_only
		else "До поверхности: Луна %.1f км | Земля %.1f км | центры %.1f км" % [
			moon_surface_distance / 1000.0,
			earth_surface_distance / 1000.0,
			distance_m / 1000.0,
		]
	)
	label.text = (
		"%s\n"
		+ "%s\n"
		+ "Скорость %.1f м/с | координаты: [%.1f, %.1f, %.1f] км\n"
		+ "%s\n"
		+ "%s\n"
		+ "%s\n"
		+ "Патч Земли: min %.1f м | max %.1f м | перепад %.1f м | geom-склон max %.1f°\n"
		+ "~ — консоль | earth.teleport.biome <name> | space.teleport.body <id>\n"
		+ "WASD/Q/E — движение и крен | Shift — ускорение | колесо — скорость | H — горизонт"
	) % [
		world_title,
		body_description,
		explorer.get_movement_speed(),
		space_position.x / 1000.0,
		space_position.y / 1000.0,
		space_position.z / 1000.0,
		distance_description,
		local_description,
		atmosphere_description,
		float(statistics.get("minimum_elevation_m", 0.0)),
		float(statistics.get("maximum_elevation_m", 0.0)),
		float(statistics.get("relief_range_m", 0.0)),
		float(statistics.get("maximum_geometric_slope_deg", 0.0)),
	]


func _join_strings(values) -> String:
	var parts := PackedStringArray()
	if values is Array:
		for value in values:
			parts.append(String(value))
	return ", ".join(parts)

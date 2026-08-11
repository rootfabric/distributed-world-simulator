extends Node2D

const Probes = preload("res://scripts/research/ecology/plant_render_description_probes_v1.gd")
const RendererProfile = preload("res://scripts/research/ecology/plant_renderer_profile_v1.gd")

var environment_index := 0
var profile_index := 0
var zoom := 1.0
var results: Dictionary = {}
var status_label: Label

func _ready() -> void:
	results = Probes.run_all()
	status_label = get_node("UI/Panel/Status") as Label
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_E:
		environment_index = (environment_index + 1) % Probes.ENVIRONMENT_ORDER.size()
		_refresh()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_Q:
		environment_index = (environment_index - 1 + Probes.ENVIRONMENT_ORDER.size()) % Probes.ENVIRONMENT_ORDER.size()
		_refresh()
	elif event.is_action_pressed("ui_right") or (event is InputEventKey and event.pressed and event.keycode == KEY_D):
		profile_index = (profile_index + 1) % RendererProfile.PROFILE_ORDER.size()
		_refresh()
	elif event.is_action_pressed("ui_left") or (event is InputEventKey and event.pressed and event.keycode == KEY_A):
		profile_index = (profile_index - 1 + RendererProfile.PROFILE_ORDER.size()) % RendererProfile.PROFILE_ORDER.size()
		_refresh()
	elif event.is_action_pressed("ui_up"):
		zoom = minf(2.6, zoom * 1.15)
		_refresh()
	elif event.is_action_pressed("ui_down"):
		zoom = maxf(0.40, zoom / 1.15)
		_refresh()

func _refresh() -> void:
	if status_label != null:
		status_label.text = _status_text()
	queue_redraw()

func _draw() -> void:
	if results.is_empty():
		return
	var environment_name := Probes.ENVIRONMENT_ORDER[environment_index]
	var profile_id := RendererProfile.PROFILE_ORDER[profile_index]
	var item: Dictionary = results[environment_name]
	var description: Dictionary = item["render_description"]
	var materialization: Dictionary = item["materializations"][profile_id]
	var viewport_size := get_viewport_rect().size
	var origin := Vector2(viewport_size.x * 0.38, viewport_size.y * 0.88)
	var height := maxf(0.1, float(description["bounds"]["height_m"]))
	var pixels_per_meter := minf(155.0, viewport_size.y * 0.68 / height) * zoom
	draw_line(Vector2(20.0, origin.y), Vector2(viewport_size.x * 0.70, origin.y), Color(0.32, 0.32, 0.32), 1.0)
	match profile_id:
		"DEBUG_SKELETON":
			_draw_branches(description, origin, pixels_per_meter, false, false)
		"BRANCH_TUBES":
			_draw_branches(description, origin, pixels_per_meter, true, false)
		"BRANCH_LEAF_INSTANCED":
			_draw_branches(description, origin, pixels_per_meter, true, false)
			_draw_foliage(description, origin, pixels_per_meter, 0.70)
		"CANOPY_APPROXIMATION":
			_draw_branches(description, origin, pixels_per_meter, true, true)
			_draw_canopy(description, origin, pixels_per_meter, true)
		"FULL_PROCEDURAL":
			_draw_canopy(description, origin, pixels_per_meter, false)
			_draw_branches(description, origin, pixels_per_meter, true, false)
			_draw_foliage(description, origin, pixels_per_meter, 1.0)
		"IMPOSTOR_BILLBOARD":
			_draw_impostor(description, origin, pixels_per_meter)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(viewport_size.x * 0.72, viewport_size.y * 0.18), "PROFILE MATERIALIZATION", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.82, 0.82, 0.82))
	draw_string(font, Vector2(viewport_size.x * 0.72, viewport_size.y * 0.23), "%s" % profile_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.55, 0.90, 0.62))
	draw_string(font, Vector2(viewport_size.x * 0.72, viewport_size.y * 0.29), "branches %d" % int(materialization["branch_primitive_count"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.8, 0.8))
	draw_string(font, Vector2(viewport_size.x * 0.72, viewport_size.y * 0.33), "foliage %d" % int(materialization["foliage_instance_count"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.8, 0.8))
	draw_string(font, Vector2(viewport_size.x * 0.72, viewport_size.y * 0.37), "canopy %d   impostor %d" % [int(materialization["canopy_primitive_count"]), int(materialization["impostor_count"])], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.8, 0.8))

func _draw_branches(description: Dictionary, origin: Vector2, ppm: float, tubes: bool, trunk_only: bool) -> void:
	for branch in Array(description["branches"]):
		if trunk_only and not bool(branch["main_axis"]):
			continue
		var a := _vec3(Array(branch["start"]))
		var b := _vec3(Array(branch["end"]))
		var width := 2.0
		if tubes:
			width = maxf(2.0, float(branch["radius_start_m"]) * ppm * 1.5)
		var color := Color(0.72, 0.78, 0.80) if bool(branch["main_axis"]) else Color(0.45, 0.72, 0.45)
		draw_line(origin + Vector2(a.x, -a.y) * ppm, origin + Vector2(b.x, -b.y) * ppm, color, width, true)

func _draw_foliage(description: Dictionary, origin: Vector2, ppm: float, fraction: float) -> void:
	var anchors: Array = description["foliage_anchors"]
	var count := clampi(int(ceil(float(anchors.size()) * fraction)), 0, anchors.size())
	for index in range(count):
		var anchor: Dictionary = anchors[index]
		var p := _vec3(Array(anchor["position"]))
		var size := maxf(2.5, float(anchor["size_m"]) * ppm * 0.62)
		var center := origin + Vector2(p.x, -p.y) * ppm
		draw_circle(center, size, Color(0.30, 0.78, 0.40, 0.82))
		if bool(anchor["bud"]):
			draw_circle(center, maxf(1.5, size * 0.32), Color(0.88, 0.76, 0.34, 0.95))

func _draw_canopy(description: Dictionary, origin: Vector2, ppm: float, filled: bool) -> void:
	var canopy: Dictionary = description["canopy"]
	var center3 := _vec3(Array(canopy["center"]))
	var center := origin + Vector2(center3.x, -center3.y) * ppm
	var radii := Vector2(float(canopy["radius_xz_m"]) * ppm, float(canopy["height_m"]) * ppm * 0.5)
	var color := Color(0.24, 0.63, 0.32, 0.22 if filled else 0.08)
	_draw_ellipse(center, radii, color)

func _draw_impostor(description: Dictionary, origin: Vector2, ppm: float) -> void:
	var height := float(description["bounds"]["height_m"]) * ppm
	var radius := maxf(0.16, float(description["canopy"]["radius_xz_m"])) * ppm
	var rect := Rect2(origin + Vector2(-radius, -height), Vector2(radius * 2.0, height))
	draw_rect(rect, Color(0.16, 0.42, 0.22, 0.20), true)
	draw_rect(rect, Color(0.42, 0.78, 0.48, 0.78), false, 2.0)
	_draw_canopy(description, origin, ppm, true)

func _draw_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(40):
		var angle := TAU * float(i) / 40.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)

func _status_text() -> String:
	if results.is_empty():
		return "ECO.PH5 loading..."
	var environment_name := Probes.ENVIRONMENT_ORDER[environment_index]
	var profile_id := RendererProfile.PROFILE_ORDER[profile_index]
	var item: Dictionary = results[environment_name]
	var graph: Dictionary = item["growth_graph"]
	var description: Dictionary = item["render_description"]
	var materialization: Dictionary = item["materializations"][profile_id]
	return "\n".join(PackedStringArray([
		"ECO.PH5 — Extensible Procedural Visual Materialization Lab",
		"Environment %d/%d: %s    [Q/E] environment    [A/D or arrows] profile    [Up/Down] zoom" % [environment_index + 1, Probes.ENVIRONMENT_ORDER.size(), environment_name],
		"Profile %d/%d: %s" % [profile_index + 1, RendererProfile.PROFILE_ORDER.size(), profile_id],
		"Derived presentation only — renderer/profile/LOD cannot modify GrowthGraph or ecology truth",
		"growth_graph_hash=%s" % String(graph["graph_hash"]),
		"render_description_hash=%s" % String(description["render_description_hash"]),
		"materialization_hash=%s" % String(materialization["materialization_hash"]),
		"branches=%d foliage_anchors=%d canopy_radius=%.3fm height=%.3fm" % [Array(description["branches"]).size(), Array(description["foliage_anchors"]).size(), float(description["canopy"]["radius_xz_m"]), float(description["bounds"]["height_m"])],
	]))

func _vec3(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

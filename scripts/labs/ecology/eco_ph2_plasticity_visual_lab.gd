extends Node2D

const Probes = preload("res://scripts/research/ecology/plant_environment_coupled_development_probes_v1.gd")

var probe_index := 0
var zoom := 1.0
var results: Dictionary = {}
var status_label: Label

func _ready() -> void:
	results = Probes.run_all()
	status_label = get_node("UI/Status") as Label
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_right") or (event is InputEventKey and event.pressed and event.keycode == KEY_E):
		probe_index = (probe_index + 1) % Probes.PROBE_ORDER.size()
		_refresh()
	elif event.is_action_pressed("ui_left") or (event is InputEventKey and event.pressed and event.keycode == KEY_Q):
		probe_index = (probe_index - 1 + Probes.PROBE_ORDER.size()) % Probes.PROBE_ORDER.size()
		_refresh()
	elif event.is_action_pressed("ui_up"):
		zoom = minf(2.5, zoom * 1.15)
		_refresh()
	elif event.is_action_pressed("ui_down"):
		zoom = maxf(0.45, zoom / 1.15)
		_refresh()

func _refresh() -> void:
	if status_label != null:
		status_label.text = _status_text()
	queue_redraw()

func _draw() -> void:
	if results.is_empty():
		return
	var name := Probes.PROBE_ORDER[probe_index]
	var graph: Dictionary = results[name]["growth_graph"]
	var viewport_size := get_viewport_rect().size
	var front_origin := Vector2(viewport_size.x * 0.25, viewport_size.y * 0.82)
	var top_origin := Vector2(viewport_size.x * 0.72, viewport_size.y * 0.54)
	var pixels_per_meter := 105.0 * zoom
	draw_line(Vector2(20.0, front_origin.y), Vector2(viewport_size.x * 0.48, front_origin.y), Color(0.35, 0.35, 0.35), 1.0)
	draw_circle(top_origin, 3.0, Color(0.7, 0.7, 0.7))
	for segment in Array(graph["segments"]):
		var s: Dictionary = segment
		var a := _vec3(Array(s["start"]))
		var b := _vec3(Array(s["end"]))
		var width := 3.0 if bool(s["main_axis"]) else 1.7
		var color := Color(0.78, 0.84, 0.87) if bool(s["main_axis"]) else Color(0.48, 0.78, 0.52)
		draw_line(front_origin + Vector2(a.x, -a.y) * pixels_per_meter, front_origin + Vector2(b.x, -b.y) * pixels_per_meter, color, width, true)
		draw_line(top_origin + Vector2(a.x, a.z) * pixels_per_meter, top_origin + Vector2(b.x, b.z) * pixels_per_meter, color, width, true)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(front_origin.x - 90.0, 36.0), "FRONT PROJECTION", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.8, 0.8))
	draw_string(font, Vector2(top_origin.x - 70.0, 36.0), "TOP PROJECTION", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.8, 0.8))

func _status_text() -> String:
	var name := Probes.PROBE_ORDER[probe_index]
	var result: Dictionary = results[name]
	var traits: Dictionary = result["realized_development_traits"]
	var response: Dictionary = result["response"]
	var graph: Dictionary = result["growth_graph"]
	var m: Dictionary = graph["metrics"]
	return "\n".join(PackedStringArray([
		"ECO.PH2 — Environment-Coupled Development / Plasticity Lab",
		"Probe %d/%d: %s    [Q/E or arrows] switch    [Up/Down] zoom" % [probe_index + 1, Probes.PROBE_ORDER.size(), name],
		"Same genome + inherited development traits + IndividualSeed; only EnvironmentSample changes",
		"genome=%s" % String(result["genome_checksum"]),
		"inherited_traits=%s" % String(result["inherited_traits_checksum"]),
		"phenotype_hash=%s" % String(result["phenotype_hash"]),
		"response shade=%.3f light=%.3f drought=%.3f nutrient=%.3f flood=%.3f" % [float(response["shade_elongation"]), float(response["light_branching"]), float(response["drought_suppression"]), float(response["nutrient_growth"]), float(response["flood_suppression"])],
		"realized H=%.2f internode=%.2f apical=%.2f branch_p=%.2f angle=%.1f ratio=%.2f spread=%.2f" % [float(traits["max_height_m"]), float(traits["internode_length_m"]), float(traits["apical_dominance"]), float(traits["branch_probability"]), float(traits["branch_angle_deg"]), float(traits["branch_length_ratio"]), float(traits["crown_spread_m"])],
		"graph segments=%d branches=%d height=%.3fm radius=%.3fm" % [int(m["segment_count"]), int(m["lateral_branch_count"]), float(m["height_m"]), float(m["horizontal_radius_m"])],
	]))

func _vec3(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

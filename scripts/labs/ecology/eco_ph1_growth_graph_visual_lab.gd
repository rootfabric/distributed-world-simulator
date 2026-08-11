extends Node2D

const Probes = preload("res://scripts/research/ecology/plant_growth_graph_controlled_probes_v1.gd")

const PROBE_ORDER: Array[String] = [
	"BASE",
	"APICAL_LOW",
	"APICAL_HIGH",
	"BRANCH_LOW",
	"BRANCH_HIGH",
	"ANGLE_NARROW",
	"ANGLE_WIDE",
	"INTERNODE_SHORT",
	"INTERNODE_LONG",
]

var probe_index := 0
var zoom := 1.0
var current_graph: Dictionary = {}
var current_traits: Dictionary = {}
var status_label: Label

func _ready() -> void:
	status_label = get_node("UI/Status") as Label
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_right") or (event is InputEventKey and event.pressed and event.keycode == KEY_E):
		probe_index = (probe_index + 1) % PROBE_ORDER.size()
		_refresh()
	elif event.is_action_pressed("ui_left") or (event is InputEventKey and event.pressed and event.keycode == KEY_Q):
		probe_index = (probe_index - 1 + PROBE_ORDER.size()) % PROBE_ORDER.size()
		_refresh()
	elif event.is_action_pressed("ui_up"):
		zoom = minf(2.5, zoom * 1.15)
		_refresh()
	elif event.is_action_pressed("ui_down"):
		zoom = maxf(0.45, zoom / 1.15)
		_refresh()

func _refresh() -> void:
	var probes := Probes.make_probes()
	var name := PROBE_ORDER[probe_index]
	current_traits = Dictionary(probes[name])
	current_graph = Probes.Skeleton.build(current_traits, Probes.DEFAULT_INDIVIDUAL_SEED)
	if status_label != null:
		status_label.text = _status_text(name)
	queue_redraw()

func _draw() -> void:
	if current_graph.is_empty():
		return
	var viewport_size := get_viewport_rect().size
	var front_origin := Vector2(viewport_size.x * 0.25, viewport_size.y * 0.82)
	var top_origin := Vector2(viewport_size.x * 0.72, viewport_size.y * 0.54)
	var pixels_per_meter := 105.0 * zoom
	# Diagnostic axes only. GrowthGraph remains the only geometry input.
	draw_line(Vector2(20.0, front_origin.y), Vector2(viewport_size.x * 0.48, front_origin.y), Color(0.35, 0.35, 0.35), 1.0)
	draw_circle(top_origin, 3.0, Color(0.7, 0.7, 0.7))
	for segment in Array(current_graph["segments"]):
		var s: Dictionary = segment
		var a := _vec3(Array(s["start"]))
		var b := _vec3(Array(s["end"]))
		var width := 3.0 if bool(s["main_axis"]) else 1.7
		var color := Color(0.78, 0.84, 0.87) if bool(s["main_axis"]) else Color(0.48, 0.78, 0.52)
		var fa := front_origin + Vector2(a.x, -a.y) * pixels_per_meter
		var fb := front_origin + Vector2(b.x, -b.y) * pixels_per_meter
		var ta := top_origin + Vector2(a.x, a.z) * pixels_per_meter
		var tb := top_origin + Vector2(b.x, b.z) * pixels_per_meter
		draw_line(fa, fb, color, width, true)
		draw_line(ta, tb, color, width, true)
	_draw_titles(front_origin, top_origin)

func _draw_titles(front_origin: Vector2, top_origin: Vector2) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(front_origin.x - 90.0, 36.0), "FRONT PROJECTION", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.8, 0.8))
	draw_string(font, Vector2(top_origin.x - 70.0, 36.0), "TOP PROJECTION", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.8, 0.8))

func _status_text(name: String) -> String:
	var m: Dictionary = current_graph.get("metrics", {})
	return "\n".join(PackedStringArray([
		"ECO.PH1 — Deterministic GrowthGraph Skeleton Lab",
		"Probe %d/%d: %s    [Q/E or arrows] switch    [Up/Down] zoom" % [probe_index + 1, PROBE_ORDER.size(), name],
		"Derived GrowthGraph only — no mesh asset, no TREE/BUSH/GRASS canonical type",
		"individual_seed=%d" % Probes.DEFAULT_INDIVIDUAL_SEED,
		"graph_hash=%s" % String(current_graph.get("graph_hash", "")),
		"segments=%d main=%d lateral=%d branches=%d" % [int(m.get("segment_count",0)), int(m.get("main_axis_segment_count",0)), int(m.get("lateral_segment_count",0)), int(m.get("lateral_branch_count",0))],
		"height=%.3fm radius=%.3fm total_length=%.3fm mean_branch_angle=%.2f°" % [float(m.get("height_m",0.0)), float(m.get("horizontal_radius_m",0.0)), float(m.get("total_length_m",0.0)), float(m.get("mean_lateral_angle_deg",0.0))],
		"traits: H=%.2f internode=%.2f apical=%.2f branch_p=%.2f angle=%.1f ratio=%.2f depth=%d spread=%.2f" % [float(current_traits.get("max_height_m",0.0)), float(current_traits.get("internode_length_m",0.0)), float(current_traits.get("apical_dominance",0.0)), float(current_traits.get("branch_probability",0.0)), float(current_traits.get("branch_angle_deg",0.0)), float(current_traits.get("branch_length_ratio",0.0)), int(current_traits.get("branching_depth",0)), float(current_traits.get("crown_spread_m",0.0))],
	]))

func _vec3(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

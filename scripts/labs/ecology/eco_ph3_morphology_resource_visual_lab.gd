extends Node2D

const Probes = preload("res://scripts/research/ecology/plant_morphology_resource_probes_v1.gd")

const CASE_ORDER: Array[String] = [
	"REFERENCE/BASE",
	"SHADE/HEIGHT_LOW", "SHADE/HEIGHT_HIGH",
	"SUN/CROWN_NARROW", "SUN/CROWN_WIDE",
	"DRY/CROWN_NARROW", "DRY/CROWN_WIDE",
	"SUN/BRANCH_LOW", "SUN/BRANCH_HIGH",
	"REFERENCE/GIANT_DENSE",
]

var case_index := 0
var zoom := 0.9
var suite: Dictionary = {}
var status_label: Label

func _ready() -> void:
	suite = Probes.run_suite()
	status_label = get_node("UI/Status") as Label
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_right") or (event is InputEventKey and event.pressed and event.keycode == KEY_E):
		case_index = (case_index + 1) % CASE_ORDER.size()
		_refresh()
	elif event.is_action_pressed("ui_left") or (event is InputEventKey and event.pressed and event.keycode == KEY_Q):
		case_index = (case_index - 1 + CASE_ORDER.size()) % CASE_ORDER.size()
		_refresh()
	elif event.is_action_pressed("ui_up"):
		zoom = minf(2.2, zoom * 1.12)
		_refresh()
	elif event.is_action_pressed("ui_down"):
		zoom = maxf(0.35, zoom / 1.12)
		_refresh()

func _refresh() -> void:
	if status_label != null:
		status_label.text = _status_text()
	queue_redraw()

func _draw() -> void:
	if suite.is_empty():
		return
	var key := CASE_ORDER[case_index]
	var item: Dictionary = suite[key]
	var graph: Dictionary = item["phenotype"]["growth_graph"]
	var coupling: Dictionary = item["coupling"]
	var viewport_size := get_viewport_rect().size
	var origin := Vector2(viewport_size.x * 0.27, viewport_size.y * 0.84)
	var ppm := 58.0 * zoom
	draw_line(Vector2(18.0, origin.y), Vector2(viewport_size.x * 0.52, origin.y), Color(0.32, 0.32, 0.32), 1.0)
	for segment in Array(graph["segments"]):
		var s: Dictionary = segment
		var a := _vec3(Array(s["start"]))
		var b := _vec3(Array(s["end"]))
		var width := 3.0 if bool(s["main_axis"]) else 1.7
		var color := Color(0.80, 0.84, 0.87) if bool(s["main_axis"]) else Color(0.48, 0.78, 0.52)
		draw_line(origin + Vector2(a.x, -a.y) * ppm, origin + Vector2(b.x, -b.y) * ppm, color, width, true)
	_draw_ledger(Vector2(viewport_size.x * 0.58, 250.0), coupling)

func _draw_ledger(origin: Vector2, c: Dictionary) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, origin + Vector2(0, -38), "MORPHOLOGY RESOURCE LEDGER", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.85, 0.85, 0.85))
	var rows := [
		["height light", float(c["height_light_access_benefit"]), true],
		["crown light", float(c["crown_light_capture_benefit"]), true],
		["branch light", float(c["branch_light_capture_benefit"]), true],
		["structure", float(c["structural_cost"]), false],
		["branch maint", float(c["branch_maintenance_cost"]), false],
		["branch build", float(c["branch_construction_cost"]), false],
		["crown water", float(c["crown_water_cost"]), false],
	]
	var y := 0.0
	for row in rows:
		var label := String(row[0])
		var value := float(row[1])
		var benefit := bool(row[2])
		var bar_len := minf(250.0, value * 150.0)
		var color := Color(0.40, 0.78, 0.48) if benefit else Color(0.84, 0.50, 0.42)
		draw_string(font, origin + Vector2(0, y), "%s  %.3f" % [label, value], HORIZONTAL_ALIGNMENT_LEFT, 140, 14, Color(0.82, 0.82, 0.82))
		draw_rect(Rect2(origin + Vector2(150, y - 12), Vector2(bar_len, 9)), color)
		y += 28.0
	var delta := float(c["morphology_delta"])
	draw_string(font, origin + Vector2(0, y + 14), "morphology delta = %+.3f" % delta, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.90, 0.90, 0.90))

func _status_text() -> String:
	if suite.is_empty():
		return "ECO.PH3 loading..."
	var key := CASE_ORDER[case_index]
	var item: Dictionary = suite[key]
	var c: Dictionary = item["coupling"]
	var m: Dictionary = item["phenotype"]["growth_graph"]["metrics"]
	return "\n".join(PackedStringArray([
		"ECO.PH3 — Morphology-to-Resource Coupling Lab",
		"Case %d/%d: %s    [Q/E or arrows] switch    [Up/Down] zoom" % [case_index + 1, CASE_ORDER.size(), key],
		"Accepted P1 resource result + derived morphology ledger; renderer remains non-canonical",
		"graph height=%.2fm radius=%.2fm length=%.2fm branches=%d" % [float(m["height_m"]), float(m["horizontal_radius_m"]), float(m["total_length_m"]), int(m["lateral_branch_count"])],
		"benefit=%.3f cost=%.3f morphology_delta=%+.3f" % [float(c["morphology_benefit"]), float(c["morphology_cost"]), float(c["morphology_delta"])],
		"base_net=%+.3f coupled_net=%+.3f" % [float(c["base_net_resource_balance"]), float(c["coupled_net_resource_balance"])],
		"coupling_hash=%s" % String(c["coupling_hash"]),
	]))

func _vec3(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

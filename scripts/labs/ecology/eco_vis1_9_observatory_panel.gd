extends Control

const ObservatoryModel = preload("res://scripts/labs/ecology/eco_vis1_9_observatory_model.gd")

var _summary := {}
var _visible_observatory := true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func set_observatory_data(history: Array[Dictionary], selected_generation: int) -> void:
	_summary = ObservatoryModel.summarize(history, selected_generation)
	queue_redraw()

func set_observatory_visible(enabled: bool) -> void:
	_visible_observatory = enabled
	visible = enabled
	if enabled:
		queue_redraw()

func get_observatory_summary() -> Dictionary:
	return _summary.duplicate(true)

func _draw() -> void:
	if not _visible_observatory:
		return
	var panel_rect := Rect2(Vector2.ZERO, size)
	draw_rect(panel_rect, Color(0.035, 0.045, 0.055, 0.92), true)
	draw_rect(panel_rect, Color(0.42, 0.46, 0.50, 0.85), false, 1.0)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(12.0, 22.0), "VIS1.9 — EVOLUTION OBSERVATORY", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(0.95, 0.96, 0.97))
	var selected: Dictionary = _summary.get("selected", {})
	if not selected.is_empty():
		var selected_text := "G%d  reps=%d  +%d/-%d  fitness=%.3f  genomes=%d  alpha/beta=%d/%d" % [
			int(selected.get("generation", 0)),
			int(selected.get("visual_count", 0)),
			int(selected.get("birth_count", 0)),
			int(selected.get("death_count", 0)),
			float(selected.get("mean_fitness", 0.0)),
			int(selected.get("unique_genomes", 0)),
			int(selected.get("alpha_count", 0)),
			int(selected.get("beta_count", 0)),
		]
		draw_string(font, Vector2(12.0, 42.0), selected_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(0.84, 0.87, 0.90))

	var points: Array = _summary.get("points", [])
	var ranges: Dictionary = _summary.get("ranges", {})
	var left := 12.0
	var width := maxf(40.0, size.x - 24.0)
	var chart_height := 55.0
	var gap := 9.0
	var top := 56.0
	_draw_chart(Rect2(left, top, width, chart_height), points, ranges.get("visual_count", {}), "POPULATION", "visual_count", "", Color(0.30, 0.88, 0.46), Color.TRANSPARENT)
	top += chart_height + gap
	_draw_chart(Rect2(left, top, width, chart_height), points, ranges.get("turnover", {}), "BIRTHS / DEATHS", "birth_count", "death_count", Color(0.95, 0.78, 0.20), Color(0.95, 0.30, 0.25))
	top += chart_height + gap
	_draw_chart(Rect2(left, top, width, chart_height), points, ranges.get("mean_fitness", {}), "MEAN FITNESS", "mean_fitness", "", Color(0.30, 0.76, 1.00), Color.TRANSPARENT)
	top += chart_height + gap
	_draw_chart(Rect2(left, top, width, chart_height), points, ranges.get("unique_genomes", {}), "GENETIC DIVERSITY", "unique_genomes", "", Color(0.80, 0.52, 1.00), Color.TRANSPARENT)
	top += chart_height + gap
	_draw_chart(Rect2(left, top, width, chart_height), points, ranges.get("composition", {}), "ALPHA / BETA", "alpha_count", "beta_count", Color(0.42, 1.00, 0.62), Color(0.34, 0.72, 0.98))

func _draw_chart(rect: Rect2, points: Array, value_range: Dictionary, label: String, key_a: String, key_b: String, color_a: Color, color_b: Color) -> void:
	draw_rect(rect, Color(0.07, 0.085, 0.10, 0.78), true)
	draw_rect(rect, Color(0.28, 0.31, 0.34, 0.70), false, 1.0)
	var font := ThemeDB.fallback_font
	draw_string(font, rect.position + Vector2(6.0, 14.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(0.80, 0.83, 0.86))
	if points.size() < 2:
		return
	var minimum := float(value_range.get("min", 0.0))
	var maximum := float(value_range.get("max", 1.0))
	var plot := Rect2(rect.position + Vector2(6.0, 18.0), Vector2(rect.size.x - 12.0, rect.size.y - 23.0))
	_draw_series(plot, points, key_a, minimum, maximum, color_a)
	if not key_b.is_empty():
		_draw_series(plot, points, key_b, minimum, maximum, color_b)
	var first_generation := int(Dictionary(points.front()).get("generation", 0))
	var last_generation := int(Dictionary(points.back()).get("generation", 0))
	draw_string(font, rect.position + Vector2(rect.size.x - 88.0, 14.0), "G%d..G%d" % [first_generation, last_generation], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, Color(0.65, 0.68, 0.72))

func _draw_series(rect: Rect2, points: Array, key: String, minimum: float, maximum: float, color: Color) -> void:
	if color.a <= 0.0:
		return
	var denominator := maxf(0.000001, maximum - minimum)
	var previous := Vector2.ZERO
	var have_previous := false
	for index in range(points.size()):
		var point: Dictionary = points[index]
		var x := rect.position.x + rect.size.x * float(index) / float(maxi(1, points.size() - 1))
		var normalized := clampf((float(point.get(key, 0.0)) - minimum) / denominator, 0.0, 1.0)
		var y := rect.position.y + rect.size.y * (1.0 - normalized)
		var current := Vector2(x, y)
		if have_previous:
			draw_line(previous, current, color, 1.6, true)
		previous = current
		have_previous = true

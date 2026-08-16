extends Control

const ComparisonModel = preload("res://scripts/labs/ecology/eco_vis2_1_comparison_model.gd")

var _summary := {}

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func set_comparison_data(control_trace: Array, treatment_trace: Array, fork_generation: int, strict: bool = true) -> bool:
	_summary = ComparisonModel.summarize(control_trace, treatment_trace, fork_generation, strict)
	queue_redraw()
	return bool(_summary.get("success", false))

func get_comparison_summary() -> Dictionary:
	return _summary.duplicate(true)

func _draw() -> void:
	var panel_rect := Rect2(Vector2.ZERO, size)
	draw_rect(panel_rect, Color(0.035, 0.045, 0.055, 0.94), true)
	draw_rect(panel_rect, Color(0.42, 0.46, 0.50, 0.85), false, 1.0)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(12.0, 22.0), "VIS2.1 — CONTROL vs TREATMENT", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(0.95, 0.96, 0.97))
	if not bool(_summary.get("success", false)):
		var error_text := String(_summary.get("error", "No comparison data"))
		draw_string(font, Vector2(12.0, 44.0), error_text, HORIZONTAL_ALIGNMENT_LEFT, maxf(40.0, size.x - 24.0), 12, Color(0.95, 0.48, 0.42))
		return

	var points: Array = _summary.get("points", [])
	var ranges: Dictionary = _summary.get("ranges", {})
	var fork_generation := int(_summary.get("fork_generation", -1))
	var summary_hash := String(_summary.get("summary_hash", ""))
	var status_text := "fork=G%d  paired=%d  hash=%s" % [fork_generation, int(_summary.get("source_pair_count", 0)), summary_hash.left(10)]
	draw_string(font, Vector2(12.0, 41.0), status_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(0.78, 0.81, 0.84))
	draw_string(font, Vector2(maxf(12.0, size.x - 174.0), 41.0), "C  /  T  /  Δ", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(0.72, 0.76, 0.80))

	var left := 12.0
	var width := maxf(40.0, size.x - 24.0)
	var chart_height := 55.0
	var gap := 9.0
	var top := 52.0
	_draw_chart(Rect2(left, top, width, chart_height), points, ranges.get("population", {}), "POPULATION", "control_population", "treatment_population", "delta_population", Color(0.36, 0.78, 1.00), Color(0.96, 0.63, 0.26), Color(0.86, 0.88, 0.90))
	top += chart_height + gap
	_draw_chart(Rect2(left, top, width, chart_height), points, ranges.get("mean_fitness", {}), "MEAN FITNESS", "control_mean_fitness", "treatment_mean_fitness", "delta_mean_fitness", Color(0.36, 0.78, 1.00), Color(0.96, 0.63, 0.26), Color(0.86, 0.88, 0.90))
	top += chart_height + gap
	_draw_chart(Rect2(left, top, width, chart_height), points, ranges.get("genetic_diversity", {}), "GENETIC DIVERSITY", "control_unique_genomes", "treatment_unique_genomes", "delta_unique_genomes", Color(0.36, 0.78, 1.00), Color(0.96, 0.63, 0.26), Color(0.86, 0.88, 0.90))
	top += chart_height + gap
	_draw_chart(Rect2(left, top, width, chart_height), points, ranges.get("mortality", {}), "MORTALITY", "control_deaths", "treatment_deaths", "delta_deaths", Color(0.36, 0.78, 1.00), Color(0.96, 0.63, 0.26), Color(0.86, 0.88, 0.90))
	top += chart_height + gap
	_draw_chart(Rect2(left, top, width, chart_height), points, ranges.get("alpha_share", {}), "ALPHA SHARE", "control_alpha_share", "treatment_alpha_share", "delta_alpha_share", Color(0.36, 0.78, 1.00), Color(0.96, 0.63, 0.26), Color(0.86, 0.88, 0.90))

func _draw_chart(rect: Rect2, points: Array, value_range: Dictionary, label: String, control_key: String, treatment_key: String, delta_key: String, control_color: Color, treatment_color: Color, delta_color: Color) -> void:
	draw_rect(rect, Color(0.07, 0.085, 0.10, 0.80), true)
	draw_rect(rect, Color(0.28, 0.31, 0.34, 0.70), false, 1.0)
	var font := ThemeDB.fallback_font
	draw_string(font, rect.position + Vector2(6.0, 14.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(0.80, 0.83, 0.86))
	if points.size() < 2:
		return
	var minimum := float(value_range.get("min", 0.0))
	var maximum := float(value_range.get("max", 1.0))
	var plot := Rect2(rect.position + Vector2(6.0, 18.0), Vector2(rect.size.x - 12.0, rect.size.y - 23.0))
	_draw_series(plot, points, control_key, minimum, maximum, control_color, 1.5)
	_draw_series(plot, points, treatment_key, minimum, maximum, treatment_color, 1.5)
	_draw_series(plot, points, delta_key, minimum, maximum, delta_color, 1.1)
	var first_generation := int(Dictionary(points.front()).get("generation", 0))
	var last_generation := int(Dictionary(points.back()).get("generation", 0))
	draw_string(font, rect.position + Vector2(rect.size.x - 88.0, 14.0), "G%d..G%d" % [first_generation, last_generation], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, Color(0.65, 0.68, 0.72))

func _draw_series(rect: Rect2, points: Array, key: String, minimum: float, maximum: float, color: Color, line_width: float) -> void:
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
			draw_line(previous, current, color, line_width, true)
		previous = current
		have_previous = true

extends Control

const STAGE := "ECO.VIS2.2-C"
const MODE := "REPLICATED_EFFECT_OBSERVATORY"
const EXPECTED_AGGREGATE_STAGE := "ECO.VIS2.2-B"
const MAX_SERIES_POINTS := 64

var _summary: Dictionary = {}
var _selected_replicate := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(500.0, 330.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func set_observatory_data(aggregate_summary: Dictionary, selected_replicate_index: int = 0) -> bool:
	var validation := _validate_summary(aggregate_summary, selected_replicate_index)
	if not bool(validation.get("success", false)):
		return false
	_summary = aggregate_summary.duplicate(true)
	_selected_replicate = selected_replicate_index
	queue_redraw()
	return true


func select_replicate(replicate_index: int) -> bool:
	if not bool(_summary.get("success", false)):
		return false
	var replicate_count := int(_summary.get("replicate_count", 0))
	if replicate_index < 0 or replicate_index >= replicate_count:
		return false
	_selected_replicate = replicate_index
	queue_redraw()
	return true


func selected_replicate() -> int:
	return _selected_replicate


func get_observatory_summary() -> Dictionary:
	return _summary.duplicate(true)


func get_presentation_state() -> Dictionary:
	if not bool(_summary.get("success", false)):
		return {
			"success": false,
			"stage": STAGE,
			"mode": MODE,
		}
	var points: Array = _summary.get("points", [])
	var latest: Dictionary = {} if points.is_empty() else Dictionary(points.back())
	var selected_identity := _selected_identity(latest)
	return {
		"success": true,
		"stage": STAGE,
		"mode": MODE,
		"fork_generation": int(_summary.get("fork_generation", -1)),
		"replicate_count": int(_summary.get("replicate_count", 0)),
		"selected_replicate": _selected_replicate,
		"point_count": points.size(),
		"oldest_generation": int(_summary.get("oldest_generation", -1)),
		"latest_generation": int(_summary.get("latest_generation", -1)),
		"aggregate_series_hash": String(_summary.get("series_hash", "")),
		"aggregate_point_hash": String(latest.get("point_hash", "")),
		"treatment_experiment_id": String(latest.get("treatment_experiment_id", "")),
		"selected_root": String(selected_identity.get("root", "")),
		"selected_pair_hash": String(selected_identity.get("pair_hash", "")),
		"selected_population_delta": int(selected_identity.get("delta_population", 0)),
		"selected_fitness_delta": float(selected_identity.get("delta_mean_fitness", 0.0)),
		"selected_unique_genomes_delta": int(selected_identity.get("delta_unique_genomes", 0)),
		"aggregate_mean_population_delta": float(latest.get("mean_population_delta", 0.0)),
		"aggregate_median_population_delta": float(latest.get("median_population_delta", 0.0)),
		"aggregate_min_population_delta": int(latest.get("min_population_delta", 0)),
		"aggregate_max_population_delta": int(latest.get("max_population_delta", 0)),
		"aggregate_mean_fitness_delta": float(latest.get("mean_fitness_delta", 0.0)),
		"aggregate_median_fitness_delta": float(latest.get("median_fitness_delta", 0.0)),
		"aggregate_min_fitness_delta": float(latest.get("min_fitness_delta", 0.0)),
		"aggregate_max_fitness_delta": float(latest.get("max_fitness_delta", 0.0)),
		"population_positive_count": int(latest.get("population_positive_count", 0)),
		"population_zero_count": int(latest.get("population_zero_count", 0)),
		"population_negative_count": int(latest.get("population_negative_count", 0)),
		"population_effect_direction": String(latest.get("population_effect_direction", "")),
		"population_consensus_fraction": float(latest.get("population_consensus_fraction", 0.0)),
		"fitness_positive_count": int(latest.get("fitness_positive_count", 0)),
		"fitness_zero_count": int(latest.get("fitness_zero_count", 0)),
		"fitness_negative_count": int(latest.get("fitness_negative_count", 0)),
		"fitness_effect_direction": String(latest.get("fitness_effect_direction", "")),
		"fitness_consensus_fraction": float(latest.get("fitness_consensus_fraction", 0.0)),
	}


func _draw() -> void:
	var panel_rect := Rect2(Vector2.ZERO, size)
	draw_rect(panel_rect, Color(0.028, 0.038, 0.050, 0.95), true)
	draw_rect(panel_rect, Color(0.34, 0.43, 0.50, 0.90), false, 1.0)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(12.0, 22.0), "VIS2.2 — REPLICATED CAUSAL EFFECT", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(0.95, 0.97, 0.98))

	if not bool(_summary.get("success", false)):
		draw_string(font, Vector2(12.0, 45.0), "No replicated aggregate data", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(0.92, 0.50, 0.44))
		return

	var state := get_presentation_state()
	var status := "fork=G%d  G%d..G%d  n=%d  selected=R%d  hash=%s" % [
		int(state.get("fork_generation", -1)),
		int(state.get("oldest_generation", -1)),
		int(state.get("latest_generation", -1)),
		int(state.get("replicate_count", 0)),
		int(state.get("selected_replicate", 0)),
		String(state.get("aggregate_series_hash", "")).left(10),
	]
	draw_string(font, Vector2(12.0, 42.0), status, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(0.76, 0.81, 0.85))

	var pop_status := "POP Δ  selected=%+d  mean=%+.2f  range=[%+d,%+d]  sign +/0/- = %d/%d/%d" % [
		int(state.get("selected_population_delta", 0)),
		float(state.get("aggregate_mean_population_delta", 0.0)),
		int(state.get("aggregate_min_population_delta", 0)),
		int(state.get("aggregate_max_population_delta", 0)),
		int(state.get("population_positive_count", 0)),
		int(state.get("population_zero_count", 0)),
		int(state.get("population_negative_count", 0)),
	]
	draw_string(font, Vector2(12.0, 60.0), pop_status, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(0.85, 0.88, 0.91))
	var fit_status := "FIT Δ  selected=%+.4f  mean=%+.4f  consensus=%s %.0f%%  experiment=%s" % [
		float(state.get("selected_fitness_delta", 0.0)),
		float(state.get("aggregate_mean_fitness_delta", 0.0)),
		String(state.get("fitness_effect_direction", "")),
		float(state.get("fitness_consensus_fraction", 0.0)) * 100.0,
		String(state.get("treatment_experiment_id", "")),
	]
	draw_string(font, Vector2(12.0, 77.0), fit_status, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(0.85, 0.88, 0.91))

	var points: Array = _summary.get("points", [])
	var left := 12.0
	var width := maxf(80.0, size.x - 24.0)
	var top := 90.0
	var chart_height := maxf(82.0, (size.y - 112.0) * 0.45)
	_draw_effect_chart(
		Rect2(left, top, width, chart_height),
		points,
		"POPULATION EFFECT (Treatment - Control)",
		"min_population_delta",
		"max_population_delta",
		"mean_population_delta",
		"delta_population"
	)
	top += chart_height + 10.0
	_draw_effect_chart(
		Rect2(left, top, width, chart_height),
		points,
		"MEAN FITNESS EFFECT (Treatment - Control)",
		"min_fitness_delta",
		"max_fitness_delta",
		"mean_fitness_delta",
		"delta_mean_fitness"
	)


func _draw_effect_chart(
	rect: Rect2,
	points: Array,
	label: String,
	min_key: String,
	max_key: String,
	mean_key: String,
	selected_identity_key: String
) -> void:
	draw_rect(rect, Color(0.055, 0.072, 0.088, 0.88), true)
	draw_rect(rect, Color(0.25, 0.32, 0.38, 0.78), false, 1.0)
	var font := ThemeDB.fallback_font
	draw_string(font, rect.position + Vector2(7.0, 15.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(0.82, 0.86, 0.89))
	if points.is_empty():
		return

	var minimum := 0.0
	var maximum := 0.0
	for point_variant in points:
		if typeof(point_variant) != TYPE_DICTIONARY:
			continue
		var point: Dictionary = point_variant
		minimum = minf(minimum, float(point.get(min_key, 0.0)))
		maximum = maxf(maximum, float(point.get(max_key, 0.0)))
		minimum = minf(minimum, float(point.get(mean_key, 0.0)))
		maximum = maxf(maximum, float(point.get(mean_key, 0.0)))
		var identity := _identity_for_point(point, _selected_replicate)
		minimum = minf(minimum, float(identity.get(selected_identity_key, 0.0)))
		maximum = maxf(maximum, float(identity.get(selected_identity_key, 0.0)))
	if is_equal_approx(minimum, maximum):
		minimum -= 1.0
		maximum += 1.0
	else:
		var padding := maxf(0.000001, (maximum - minimum) * 0.08)
		minimum -= padding
		maximum += padding

	var plot := Rect2(rect.position + Vector2(7.0, 21.0), Vector2(maxf(20.0, rect.size.x - 14.0), maxf(20.0, rect.size.y - 28.0)))
	var denominator := maxf(0.000000001, maximum - minimum)
	var zero_y := plot.position.y + plot.size.y * (1.0 - clampf((0.0 - minimum) / denominator, 0.0, 1.0))
	draw_line(Vector2(plot.position.x, zero_y), Vector2(plot.end.x, zero_y), Color(0.58, 0.62, 0.66, 0.55), 1.0, true)

	if points.size() >= 2:
		var polygon := PackedVector2Array()
		for index in range(points.size()):
			var point: Dictionary = points[index]
			polygon.append(_chart_point(plot, index, points.size(), float(point.get(max_key, 0.0)), minimum, maximum))
		for reverse_index in range(points.size() - 1, -1, -1):
			var point: Dictionary = points[reverse_index]
			polygon.append(_chart_point(plot, reverse_index, points.size(), float(point.get(min_key, 0.0)), minimum, maximum))
		if polygon.size() >= 3:
			draw_colored_polygon(polygon, Color(0.28, 0.66, 0.92, 0.15))

	_draw_point_series(plot, points, mean_key, "", minimum, maximum, Color(0.35, 0.82, 1.0, 0.95), 2.0)
	_draw_point_series(plot, points, "", selected_identity_key, minimum, maximum, Color(1.0, 0.68, 0.24, 0.98), 1.7)
	var first_generation := int(Dictionary(points.front()).get("generation", 0))
	var last_generation := int(Dictionary(points.back()).get("generation", 0))
	draw_string(font, rect.position + Vector2(rect.size.x - 102.0, 15.0), "G%d..G%d" % [first_generation, last_generation], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, Color(0.64, 0.69, 0.73))


func _draw_point_series(
	plot: Rect2,
	points: Array,
	point_key: String,
	identity_key: String,
	minimum: float,
	maximum: float,
	color: Color,
	line_width: float
) -> void:
	var previous := Vector2.ZERO
	var have_previous := false
	for index in range(points.size()):
		var point: Dictionary = points[index]
		var value := 0.0
		if not point_key.is_empty():
			value = float(point.get(point_key, 0.0))
		else:
			value = float(_identity_for_point(point, _selected_replicate).get(identity_key, 0.0))
		var current := _chart_point(plot, index, points.size(), value, minimum, maximum)
		if have_previous:
			draw_line(previous, current, color, line_width, true)
		previous = current
		have_previous = true


func _chart_point(plot: Rect2, index: int, count: int, value: float, minimum: float, maximum: float) -> Vector2:
	var x := plot.position.x
	if count > 1:
		x += plot.size.x * float(index) / float(count - 1)
	var normalized := clampf((value - minimum) / maxf(0.000000001, maximum - minimum), 0.0, 1.0)
	var y := plot.position.y + plot.size.y * (1.0 - normalized)
	return Vector2(x, y)


func _selected_identity(point: Dictionary) -> Dictionary:
	return _identity_for_point(point, _selected_replicate)


static func _identity_for_point(point: Dictionary, replicate_index: int) -> Dictionary:
	for identity_variant in Array(point.get("replicate_identities", [])):
		if typeof(identity_variant) != TYPE_DICTIONARY:
			continue
		var identity: Dictionary = identity_variant
		if int(identity.get("replicate_index", -1)) == replicate_index:
			return identity
	return {}


static func _validate_summary(summary: Dictionary, selected_replicate_index: int) -> Dictionary:
	if not bool(summary.get("success", false)):
		return {"success": false, "reason": "AGGREGATE_NOT_SUCCESSFUL"}
	if String(summary.get("stage", "")) != EXPECTED_AGGREGATE_STAGE:
		return {"success": false, "reason": "INVALID_AGGREGATE_STAGE"}
	var replicate_count := int(summary.get("replicate_count", 0))
	if replicate_count < 2 or replicate_count > 16:
		return {"success": false, "reason": "INVALID_REPLICATE_COUNT"}
	if selected_replicate_index < 0 or selected_replicate_index >= replicate_count:
		return {"success": false, "reason": "INVALID_SELECTED_REPLICATE"}
	var series_hash := String(summary.get("series_hash", ""))
	if series_hash.length() != 64:
		return {"success": false, "reason": "INVALID_SERIES_HASH"}
	var points: Array = summary.get("points", [])
	if points.size() > MAX_SERIES_POINTS:
		return {"success": false, "reason": "AGGREGATE_SERIES_UNBOUNDED"}
	if int(summary.get("point_count", points.size())) != points.size():
		return {"success": false, "reason": "POINT_COUNT_MISMATCH"}
	var previous_generation := -1
	for point_variant in points:
		if typeof(point_variant) != TYPE_DICTIONARY:
			return {"success": false, "reason": "INVALID_AGGREGATE_POINT"}
		var point: Dictionary = point_variant
		if int(point.get("replicate_count", 0)) != replicate_count:
			return {"success": false, "reason": "POINT_REPLICATE_COUNT_MISMATCH"}
		var generation := int(point.get("generation", -1))
		if generation < 0 or (previous_generation >= 0 and generation <= previous_generation):
			return {"success": false, "reason": "NON_MONOTONIC_GENERATION"}
		previous_generation = generation
		var identities: Array = point.get("replicate_identities", [])
		if identities.size() != replicate_count:
			return {"success": false, "reason": "IDENTITY_COUNT_MISMATCH"}
		var seen := {}
		for identity_variant in identities:
			if typeof(identity_variant) != TYPE_DICTIONARY:
				return {"success": false, "reason": "INVALID_REPLICATE_IDENTITY"}
			var replicate_index := int(Dictionary(identity_variant).get("replicate_index", -1))
			if replicate_index < 0 or replicate_index >= replicate_count or seen.has(replicate_index):
				return {"success": false, "reason": "INVALID_REPLICATE_IDENTITY_INDEX"}
			seen[replicate_index] = true
		if not seen.has(selected_replicate_index):
			return {"success": false, "reason": "SELECTED_REPLICATE_MISSING"}
	return {"success": true}

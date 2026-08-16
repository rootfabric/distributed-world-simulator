extends Control

const VIS20_ExperimentModel = preload("res://scripts/labs/ecology/eco_vis2_0_experiment_model.gd")

var _state := {}
var _probe := {}
var _events: Array[Dictionary] = []
var _panel_visible := true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func set_experiment_data(state: Dictionary, probe: Dictionary, events: Array[Dictionary]) -> void:
	_state = state.duplicate(true)
	_probe = probe.duplicate(true)
	_events = events.duplicate(true)
	queue_redraw()

func set_experiment_panel_visible(enabled: bool) -> void:
	_panel_visible = enabled
	visible = enabled
	if enabled:
		queue_redraw()

func _draw() -> void:
	if not _panel_visible:
		return
	var profile := String(_state.get("profile", "BASELINE"))
	var intensity := float(_state.get("intensity", 0.0))
	var accent := VIS20_ExperimentModel.profile_color(profile, intensity)
	var panel_rect := Rect2(Vector2.ZERO, size)
	draw_rect(panel_rect, Color(0.035, 0.045, 0.055, 0.92), true)
	draw_rect(panel_rect, accent.darkened(0.20), false, 2.0)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(12.0, 22.0), "VIS2.0 — EVOLUTION EXPERIMENT", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(0.95, 0.96, 0.97))
	draw_string(font, Vector2(12.0, 43.0), "%s  intensity=%d%%  effective=G%d  epoch=%d" % [
		profile,
		int(round(intensity * 100.0)),
		int(_state.get("effective_generation", 0)),
		int(_state.get("epoch", 0)),
	], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, accent)
	var baseline: Dictionary = _probe.get("baseline", {})
	var experimental: Dictionary = _probe.get("experimental", {})
	if not baseline.is_empty() and not experimental.is_empty():
		var probe_text := "probe m %.2f→%.2f  light %.2f→%.2f  nut %.2f→%.2f  flood %.2f→%.2f  T %.1f→%.1f" % [
			float(baseline.get("soil_moisture", 0.0)), float(experimental.get("soil_moisture", 0.0)),
			float(baseline.get("sunlight", 0.0)), float(experimental.get("sunlight", 0.0)),
			float(baseline.get("nutrients", 0.0)), float(experimental.get("nutrients", 0.0)),
			float(baseline.get("flood_frequency", 0.0)), float(experimental.get("flood_frequency", 0.0)),
			float(baseline.get("temperature_c", 0.0)), float(experimental.get("temperature_c", 0.0)),
		]
		draw_string(font, Vector2(12.0, 64.0), probe_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(0.82, 0.85, 0.88))
	draw_string(font, Vector2(12.0, 84.0), "1 baseline | 2 drought | 3 flood | 4 nutrient | 5 shade | -/+ intensity | I panel", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, Color(0.70, 0.74, 0.78))
	var start := maxi(0, _events.size() - 4)
	var y := 107.0
	for index in range(start, _events.size()):
		var event: Dictionary = _events[index]
		var event_profile := String(event.get("profile", "BASELINE"))
		var event_color := VIS20_ExperimentModel.profile_color(event_profile, float(event.get("intensity", 0.0)))
		var text := "G%d  %s  %3d%%  %s" % [
			int(event.get("effective_generation", 0)),
			event_profile,
			int(round(float(event.get("intensity", 0.0)) * 100.0)),
			String(event.get("reason", "INTERVENTION")),
		]
		draw_string(font, Vector2(12.0, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, event_color)
		y += 18.0

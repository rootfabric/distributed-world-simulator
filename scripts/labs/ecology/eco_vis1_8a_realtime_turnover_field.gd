extends "res://scripts/labs/ecology/eco_vis1_7_temporal_evolution_field.gd"

const RealtimeModel = preload("res://scripts/labs/ecology/eco_vis1_8a_realtime_turnover_model.gd")
const RealtimeRenderer = preload("res://scripts/labs/ecology/eco_vis1_8a_realtime_proxy_renderer.gd")
const TimelineBridge = preload("res://scripts/labs/ecology/eco_vis1_7_temporal_evolution_bridge.gd")

const VIS1_8A_R1_STAGE := "ECO.VIS1.8A-R1"
const VIS18R_MODE := "REALTIME_TURNOVER_PROXY_PRESENTATION"
const VIS18R_PLAY_INTERVAL_SECONDS := 1.15

var _vis18r_model := RealtimeModel.new()
var _vis18r_renderer := RealtimeRenderer.new()
var _vis18r_generation := 0
var _vis18r_playing := false
var _vis18r_play_accumulator := 0.0
var _vis18r_field_hash := ""
var _vis18r_turnover_hash := ""
var _vis18r_current_visual_count := 0
var _vis18r_current_births := 0
var _vis18r_current_deaths := 0
var _vis18r_current_survivors := 0
var _vis18r_represented_biomass_kg := 0.0
var _vis18r_cumulative_births := 0
var _vis18r_cumulative_deaths := 0
var _vis18r_last_apply_ms := 0.0
var _vis18r_ph5_rebuilds_during_turnover := 0


func _ready() -> void:
	# VIS1.7 is already proven responsive, so keep one detailed PH5 baseline only.
	_vis17_generation = 0
	_vis17_playing = false
	super._ready()
	_vis17_playing = false
	_vis17_generation = 0
	_vis18r_model.capture_founders(self, _ph5_root, _spatial_snapshot)
	_apply_vis18r_generation(0)
	if is_instance_valid(_controls_label):
		_controls_label.text = "WASD move | Q/E down/up | Shift boost | mouse look | Esc capture | Home reset | Left/Right generation | Space play/pause | R generation 0 | F1-F5 diagnostics\nVIS1.8A-R1: generation 0 keeps detailed PH5; turnover generations use lightweight genome/environment-derived tree proxies so camera/input never wait for whole-field PH5 rebuild"
	_update_vis18r_title()
	_update_status()


func _process(delta: float) -> void:
	# Parent processing keeps camera movement alive. Parent autoplay must stay disabled.
	_vis17_playing = false
	super._process(delta)
	_vis17_playing = false
	_vis18r_renderer.advance_animations(delta)
	if not _vis18r_playing:
		return
	_vis18r_play_accumulator += delta
	if _vis18r_play_accumulator < VIS18R_PLAY_INTERVAL_SECONDS:
		return
	_vis18r_play_accumulator = 0.0
	if _vis18r_generation >= TimelineBridge.MAX_GENERATION:
		_vis18r_playing = false
		_update_vis18r_title()
		_update_status()
		return
	set_realtime_turnover_generation(_vis18r_generation + 1)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			match key_event.keycode:
				KEY_LEFT:
					_vis18r_playing = false
					set_realtime_turnover_generation(_vis18r_generation - 1)
					get_viewport().set_input_as_handled()
					return
				KEY_RIGHT:
					_vis18r_playing = false
					set_realtime_turnover_generation(_vis18r_generation + 1)
					get_viewport().set_input_as_handled()
					return
				KEY_SPACE:
					_vis18r_playing = not _vis18r_playing
					_vis18r_play_accumulator = 0.0
					_update_vis18r_title()
					_update_status()
					get_viewport().set_input_as_handled()
					return
				KEY_R:
					_vis18r_playing = false
					set_realtime_turnover_generation(0)
					get_viewport().set_input_as_handled()
					return
	super._unhandled_input(event)


func set_realtime_turnover_generation(generation: int) -> void:
	var clamped := clampi(generation, 0, TimelineBridge.MAX_GENERATION)
	if clamped == _vis18r_generation and _vis18r_field_hash.length() == 64:
		_update_vis18r_title()
		_update_status()
		return
	_vis18r_generation = clamped
	_vis18r_play_accumulator = 0.0
	_apply_vis18r_generation(clamped)
	_update_vis18r_title()
	_update_status()


func set_evolution_generation(generation: int) -> void:
	set_realtime_turnover_generation(generation)


func get_evolution_generation() -> int:
	return _vis18r_generation


func get_realtime_turnover_state() -> Dictionary:
	return {
		"stage": VIS1_8A_R1_STAGE,
		"mode": VIS18R_MODE,
		"generation": _vis18r_generation,
		"max_generation": TimelineBridge.MAX_GENERATION,
		"playing": _vis18r_playing,
		"play_interval_seconds": VIS18R_PLAY_INTERVAL_SECONDS,
		"founder_count": _vis18r_model.founder_count,
		"visual_count": _vis18r_current_visual_count,
		"birth_count": _vis18r_current_births,
		"death_count": _vis18r_current_deaths,
		"survivor_count": _vis18r_current_survivors,
		"represented_biomass_kg": _vis18r_represented_biomass_kg,
		"cumulative_births": _vis18r_cumulative_births,
		"cumulative_deaths": _vis18r_cumulative_deaths,
		"field_hash": _vis18r_field_hash,
		"turnover_hash": _vis18r_turnover_hash,
		"last_apply_ms": _vis18r_last_apply_ms,
		"last_simulation_ms": _vis18r_model.last_simulation_ms,
		"preview_build_count": _vis18r_renderer.preview_build_count,
		"ph5_rebuilds_during_turnover": _vis18r_ph5_rebuilds_during_turnover,
		"active_animations": _vis18r_renderer.animations.size(),
		"presentation_mode": "PH5_BASELINE" if _vis18r_generation == 0 else "REALTIME_PROXY",
		"canonical_population_truth": false,
		"canonical_timeline_truth": false,
	}


func get_evolution_state() -> Dictionary:
	return get_realtime_turnover_state()


func get_population_field_hash() -> String:
	return _vis18r_field_hash


func get_ph5_projection_hash() -> String:
	return _vis18r_field_hash


func get_population_field_summary() -> Dictionary:
	var summary := super.get_population_field_summary()
	var state := get_realtime_turnover_state()
	for key in state.keys():
		summary[key] = state[key]
	return summary


func _apply_vis18r_generation(generation: int) -> void:
	var started := Time.get_ticks_usec()
	_vis18r_model.ensure_generation(self, generation, _spatial_snapshot)
	var generation_map := _vis18r_model.generation_map(generation)
	if generation_map.is_empty():
		return
	if generation == 0:
		_vis18r_renderer.show_generation_zero(_ph5_root)
		_apply_generation_zero_summary(generation_map)
	else:
		var render_summary := _vis18r_renderer.show_realtime_generation(self, _ph5_root, generation, generation_map)
		_vis18r_current_visual_count = int(render_summary.get("visual_count", 0))
		_vis18r_current_births = int(render_summary.get("birth_count", 0))
		_vis18r_current_deaths = int(render_summary.get("death_count", 0))
		_vis18r_current_survivors = int(render_summary.get("survivor_count", 0))
		_vis18r_represented_biomass_kg = float(render_summary.get("represented_biomass_kg", 0.0))
		_vis18r_field_hash = String(render_summary.get("field_hash", ""))
		_vis18r_turnover_hash = String(render_summary.get("turnover_hash", ""))
		_vis18r_cumulative_births = _vis18r_model.cumulative_event_count(generation, "birth_count")
		_vis18r_cumulative_deaths = _vis18r_model.cumulative_event_count(generation, "death_count")
	_vis18r_last_apply_ms = float(Time.get_ticks_usec() - started) / 1000.0


func _apply_generation_zero_summary(generation_map: Dictionary) -> void:
	_vis18r_current_visual_count = 0
	_vis18r_current_births = 0
	_vis18r_current_deaths = 0
	_vis18r_current_survivors = 0
	_vis18r_represented_biomass_kg = 0.0
	var field_tokens := PackedStringArray([VIS1_8A_R1_STAGE, "generation=0"])
	var turnover_tokens := PackedStringArray([VIS1_8A_R1_STAGE, "turnover=0"])
	var keys := generation_map.keys()
	keys.sort()
	for key_variant in keys:
		var state: Dictionary = generation_map[key_variant]
		var records: Array = state.get("records", [])
		var transition: Dictionary = state.get("transition", {})
		_vis18r_current_visual_count += records.size()
		_vis18r_current_survivors += records.size()
		for record_variant in records:
			if typeof(record_variant) != TYPE_DICTIONARY:
				continue
			var record: Dictionary = record_variant
			_vis18r_represented_biomass_kg += float(record.get("represented_biomass_kg", 0.0))
			field_tokens.append("%s|%.9f|%.9f" % [String(record.get("stable_id", "")), float(record.get("world_x", 0.0)), float(record.get("world_z", 0.0))])
		turnover_tokens.append(String(transition.get("turnover_hash", "")))
	_vis18r_cumulative_births = 0
	_vis18r_cumulative_deaths = 0
	_vis18r_field_hash = "\n".join(field_tokens).sha256_text()
	_vis18r_turnover_hash = "\n".join(turnover_tokens).sha256_text()


func _update_vis18r_title() -> void:
	var title := get_node_or_null("HUD/Margin/Panel/VBox/Title") as Label
	if title == null:
		return
	var play_label := "PLAY" if _vis18r_playing else "PAUSE"
	var presentation := "PH5" if _vis18r_generation == 0 else "REALTIME"
	title.text = "ECO.VIS1.8A-R1 — %s G%d — reps=%d +%d/-%d — %s" % [
		play_label, _vis18r_generation, _vis18r_current_visual_count,
		_vis18r_current_births, _vis18r_current_deaths, presentation,
	]


func _update_status() -> void:
	super._update_status()
	var status := get_node_or_null("HUD/Margin/Panel/VBox/Status") as Label
	if status == null:
		return
	var hash_preview := _vis18r_field_hash.substr(0, 12) if _vis18r_field_hash.length() == 64 else "pending"
	status.text += "\nVIS1.8A-R1=ACTIVE generation=%d/%d %s | reps=%d founders=%d births=%d deaths=%d survivors=%d | cumulative +%d/-%d" % [
		_vis18r_generation, TimelineBridge.MAX_GENERATION, "PLAY" if _vis18r_playing else "PAUSE",
		_vis18r_current_visual_count, _vis18r_model.founder_count, _vis18r_current_births,
		_vis18r_current_deaths, _vis18r_current_survivors, _vis18r_cumulative_births, _vis18r_cumulative_deaths,
	]
	status.text += "\nrealtime presentation=%s | represented=%.3fkg | sim=%.2fms apply=%.2fms animations=%d preview_builds=%d PH5_turnover_rebuilds=%d | field=%s | canonical_population_truth=OFF" % [
		"PH5_BASELINE" if _vis18r_generation == 0 else "REALTIME_PROXY",
		_vis18r_represented_biomass_kg, _vis18r_model.last_simulation_ms, _vis18r_last_apply_ms,
		_vis18r_renderer.animations.size(), _vis18r_renderer.preview_build_count,
		_vis18r_ph5_rebuilds_during_turnover, hash_preview,
	]

extends "res://scripts/labs/ecology/eco_vis1_8a_realtime_turnover_field.gd"

const ContinuousModel = preload("res://scripts/labs/ecology/eco_vis1_8b_continuous_turnover_model.gd")

const VIS1_8B_STAGE := "ECO.VIS1.8B"
const VIS18B_MODE := "CONTINUOUS_ROLLING_TURNOVER_PLAYBACK"
const VIS18B_MAX_GENERATION := 1000000
const VIS18B_PLAY_INTERVAL_SECONDS := 0.95

var _vis18b_rewind_clamped := false


func _vis18r_stage_label() -> String:
	return VIS1_8B_STAGE


func _vis18r_mode_label() -> String:
	return VIS18B_MODE


func _vis18r_max_generation() -> int:
	return VIS18B_MAX_GENERATION


func _vis18r_play_interval_seconds() -> float:
	return VIS18B_PLAY_INTERVAL_SECONDS


func _ready() -> void:
	_vis18r_model = ContinuousModel.new()
	super._ready()
	if is_instance_valid(_controls_label):
		_controls_label.text = "WASD move | Q/E down/up | Shift boost | mouse look | Esc capture | Home reset | Left/Right generation | Space play/pause | R restart from generation 0 | F1-F5 diagnostics\nVIS1.8B: continuous turnover can advance beyond G12; only the latest 32 generations stay rewindable in memory, while R deterministically restarts from founders"
	_update_vis18r_title()
	_update_status()


func set_realtime_turnover_generation(generation: int) -> void:
	var target := clampi(generation, 0, _vis18r_max_generation())
	_vis18b_rewind_clamped = false
	var continuous_model := _vis18r_model as ContinuousModel
	if target == 0 and _vis18r_generation != 0:
		continuous_model.restart_from_founders()
	elif target > 0 and target < _vis18r_generation and not continuous_model.is_generation_cached(target):
		target = continuous_model.oldest_rewind_generation()
		_vis18b_rewind_clamped = true
	if target == _vis18r_generation and _vis18r_field_hash.length() == 64:
		_update_vis18r_title()
		_update_status()
		return
	_vis18r_generation = target
	_vis18r_play_accumulator = 0.0
	_apply_vis18r_generation(target)
	_update_vis18r_title()
	_update_status()


func get_realtime_turnover_state() -> Dictionary:
	var state := super.get_realtime_turnover_state()
	var continuous_model := _vis18r_model as ContinuousModel
	var stats := continuous_model.stats_for_generation(_vis18r_generation)
	state["stage"] = VIS1_8B_STAGE
	state["mode"] = VIS18B_MODE
	state["continuous"] = true
	state["cache_window"] = ContinuousModel.ROLLING_CACHE_WINDOW
	state["cached_generation_count"] = continuous_model.cached_generation_count()
	state["oldest_rewind_generation"] = continuous_model.oldest_rewind_generation()
	state["max_simulated_generation"] = continuous_model.max_cached_generation
	state["rewind_clamped"] = _vis18b_rewind_clamped
	state["history_point_count"] = continuous_model.recent_history().size()
	state["mean_fitness"] = float(stats.get("mean_fitness", 0.0))
	state["unique_genomes"] = int(stats.get("unique_genomes", 0))
	state["alpha_count"] = int(stats.get("alpha_count", 0))
	state["beta_count"] = int(stats.get("beta_count", 0))
	state["peak_visual_count"] = continuous_model.peak_visual_count
	return state


func get_continuous_history() -> Array[Dictionary]:
	return (_vis18r_model as ContinuousModel).recent_history()


func _update_vis18r_title() -> void:
	var title := get_node_or_null("HUD/Margin/Panel/VBox/Title") as Label
	if title == null:
		return
	var play_label := "PLAY" if _vis18r_playing else "PAUSE"
	var presentation := "PH5" if _vis18r_generation == 0 else "REALTIME"
	title.text = "ECO.VIS1.8B — %s G%d — reps=%d +%d/-%d — %s CONTINUOUS" % [
		play_label, _vis18r_generation, _vis18r_current_visual_count,
		_vis18r_current_births, _vis18r_current_deaths, presentation,
	]


func _update_status() -> void:
	super._update_status()
	var status := get_node_or_null("HUD/Margin/Panel/VBox/Status") as Label
	if status == null or not (_vis18r_model is ContinuousModel):
		return
	var continuous_model := _vis18r_model as ContinuousModel
	var stats := continuous_model.stats_for_generation(_vis18r_generation)
	var rewind_label := "G0" if _vis18r_generation == 0 else "G%d..G%d" % [continuous_model.oldest_rewind_generation(), continuous_model.max_cached_generation]
	status.text += "\nVIS1.8B=ACTIVE continuous=ON | rolling_cache=%d/%d rewind=%s | history=%d/%d | peak_reps=%d" % [
		continuous_model.cached_generation_count(), ContinuousModel.ROLLING_CACHE_WINDOW + 1,
		rewind_label, continuous_model.recent_history().size(), ContinuousModel.HISTORY_WINDOW,
		continuous_model.peak_visual_count,
	]
	status.text += "\ntrend current: mean_fitness=%.3f unique_genomes=%d alpha=%d beta=%d | G12_limit=REMOVED | canonical_population_truth=OFF canonical_timeline_truth=OFF" % [
		float(stats.get("mean_fitness", 0.0)), int(stats.get("unique_genomes", 0)),
		int(stats.get("alpha_count", 0)), int(stats.get("beta_count", 0)),
	]
	var tail := _vis18b_history_tail(continuous_model.recent_history(), 8)
	if not tail.is_empty():
		status.text += "\nrecent evolution: %s" % tail
	if _vis18b_rewind_clamped:
		status.text += "\nrewind note: requested generation was evicted from the rolling cache; clamped to oldest cached generation. Press R for deterministic restart at G0."


func _vis18b_history_tail(history: Array[Dictionary], limit: int) -> String:
	if history.is_empty() or limit <= 0:
		return ""
	var start := maxi(0, history.size() - limit)
	var tokens := PackedStringArray()
	for index in range(start, history.size()):
		var point: Dictionary = history[index]
		tokens.append("G%d:%d(+%d/-%d) f%.2f" % [
			int(point.get("generation", 0)), int(point.get("visual_count", 0)),
			int(point.get("birth_count", 0)), int(point.get("death_count", 0)),
			float(point.get("mean_fitness", 0.0)),
		])
	return " | ".join(tokens)

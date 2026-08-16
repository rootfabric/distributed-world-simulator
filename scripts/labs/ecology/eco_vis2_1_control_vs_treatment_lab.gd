extends "res://scripts/labs/ecology/eco_vis2_0_evolution_experiment_lab.gd"

const ControlRunner = preload("res://scripts/labs/ecology/eco_vis2_1_control_branch_runner.gd")
const TreatmentRunner = preload("res://scripts/labs/ecology/eco_vis2_1_treatment_branch_runner.gd")
const TraceAdapter = preload("res://scripts/labs/ecology/eco_vis2_1_trace_adapter.gd")
const ComparisonModel = preload("res://scripts/labs/ecology/eco_vis2_1_comparison_model.gd")
const ComparisonPanel = preload("res://scripts/labs/ecology/eco_vis2_1_comparison_panel.gd")

const VIS21_STAGE := "ECO.VIS2.1"
const VIS21_MODE := "CONTROL_VS_TREATMENT"
const VIS21_DEFAULT_TREATMENT := VIS20_ExperimentModel.PROFILE_DROUGHT
const VIS21_DEFAULT_INTENSITY := 1.0
const VIS21_INTENSITY_STEP := 0.10
const VIS21_SERIES_WINDOW := 64
const VIS21_BRANCH_CACHE_WINDOW := 64

var _vis21_paired := false
var _vis21_fork_generation := -1
var _vis21_fork_map: Dictionary = {}
var _vis21_fork_history: Array[Dictionary] = []
var _vis21_common_root := ""
var _vis21_control = ControlRunner.new()
var _vis21_treatment = TreatmentRunner.new()
var _vis21_treatment_profile := VIS21_DEFAULT_TREATMENT
var _vis21_treatment_intensity := VIS21_DEFAULT_INTENSITY
var _vis21_treatment_schedule: Array[Dictionary] = []
var _vis21_simulated_generation := -1
var _vis21_comparison_summary: Dictionary = {}
var _vis21_control_trace: Array[Dictionary] = []
var _vis21_treatment_trace: Array[Dictionary] = []
var _vis21_layer: CanvasLayer
var _vis21_panel: Control
var _vis21_last_node_count := 0
var _vis21_peak_node_count := 0
var _vis21_comparison_rebuild_input_count := 0


func _ready() -> void:
	super._ready()
	if _vis21_treatment.get_parent() == null:
		_vis21_treatment.name = "VIS21TreatmentDataRunner"
		add_child(_vis21_treatment)
	_create_vis21_comparison_panel()
	_vis20_profile = VIS20_ExperimentModel.PROFILE_BASELINE
	_vis20_intensity = 0.0
	_vis20_effective_generation = 0
	_vis20_apply_visual_cue()
	if is_instance_valid(_controls_label):
		_controls_label.text = "WASD move | Q/E down/up | Shift boost | mouse look | Esc capture | Left/Right generation | Space play/pause | F fork | R restart fork | O observatory | PgUp/PgDn inspect | 2 drought | 3 flood | 4 nutrient | 5 shade | -/+ treatment intensity | I VIS2.0 panel | F1-F5 diagnostics\nVIS2.1: before F the visible world remains BASELINE; after F CONTROL is data-only and TREATMENT is the single visible realtime population."
	_update_vis18r_title()
	_update_status()


func _process(delta: float) -> void:
	if not _vis21_paired:
		super._process(delta)
		return

	var requested_playing := _vis18r_playing
	_vis18r_playing = false
	super._process(delta)
	# Paired mode never materializes progressive VIS1.9 PH5; Treatment stays on realtime proxies.
	_clear_vis19_progressive_detail()
	_vis19_detail_accumulator = 0.0
	_vis18r_playing = requested_playing
	_track_vis21_node_count()
	if not requested_playing:
		return

	_vis18r_play_accumulator += delta
	if _vis18r_play_accumulator < _vis18r_play_interval_seconds():
		return
	_vis18r_play_accumulator = 0.0
	var result := advance_paired_to(_vis18r_generation + 1)
	if not bool(result.get("success", false)):
		_vis18r_playing = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			match key_event.keycode:
				KEY_F:
					if not _vis21_paired:
						begin_paired_experiment()
					get_viewport().set_input_as_handled()
					return
				KEY_2:
					set_treatment(VIS20_ExperimentModel.PROFILE_DROUGHT, _vis21_treatment_intensity)
					get_viewport().set_input_as_handled()
					return
				KEY_3:
					set_treatment(VIS20_ExperimentModel.PROFILE_FLOOD, _vis21_treatment_intensity)
					get_viewport().set_input_as_handled()
					return
				KEY_4:
					set_treatment(VIS20_ExperimentModel.PROFILE_NUTRIENT, _vis21_treatment_intensity)
					get_viewport().set_input_as_handled()
					return
				KEY_5:
					set_treatment(VIS20_ExperimentModel.PROFILE_SHADE, _vis21_treatment_intensity)
					get_viewport().set_input_as_handled()
					return
				KEY_MINUS:
					set_treatment(_vis21_treatment_profile, _vis21_treatment_intensity - VIS21_INTENSITY_STEP)
					get_viewport().set_input_as_handled()
					return
				KEY_EQUAL:
					set_treatment(_vis21_treatment_profile, _vis21_treatment_intensity + VIS21_INTENSITY_STEP)
					get_viewport().set_input_as_handled()
					return
				KEY_LEFT:
					if _vis21_paired:
						_vis18r_playing = false
						set_realtime_turnover_generation(_vis18r_generation - 1)
						get_viewport().set_input_as_handled()
						return
				KEY_RIGHT:
					if _vis21_paired:
						_vis18r_playing = false
						advance_paired_to(_vis18r_generation + 1)
						get_viewport().set_input_as_handled()
						return
				KEY_SPACE:
					if _vis21_paired:
						_vis18r_playing = not _vis18r_playing
						_vis18r_play_accumulator = 0.0
						_update_vis18r_title()
						_update_status()
						get_viewport().set_input_as_handled()
						return
				KEY_R:
					if _vis21_paired:
						_vis18r_playing = false
						restart_paired_from_fork()
						get_viewport().set_input_as_handled()
						return
	super._unhandled_input(event)


func sample_environment_at(x: float, z: float) -> Dictionary:
	if _vis21_paired:
		return _vis21_treatment.sample_environment_for_generation(_vis18r_generation, x, z)
	return super.sample_environment_at(x, z)


func sample_environment_context_at(x: float, z: float) -> Dictionary:
	if not _vis21_paired:
		return super.sample_environment_context_at(x, z)
	var baseline := super.sample_environment_context_at(x, z)
	baseline["environment"] = sample_environment_at(x, z)
	baseline["experiment_profile"] = _vis21_experiment_for_generation(_vis18r_generation)
	baseline["experiment_intensity"] = _vis21_intensity_for_generation(_vis18r_generation)
	return baseline


func begin_paired_experiment() -> Dictionary:
	if _vis21_paired:
		return {"success": true, "generation": _vis21_fork_generation}
	if _vis20_profile != VIS20_ExperimentModel.PROFILE_BASELINE:
		return {"success": false, "reason": "SOURCE_NOT_BASELINE"}

	_vis18r_playing = false
	var source_model := _vis18r_model as RefCounted
	if source_model == null:
		return {"success": false, "reason": "SOURCE_MODEL_MISSING"}

	var fork_generation := _vis18r_generation
	var captured_map: Dictionary = Dictionary(source_model.call("generation_map", fork_generation)).duplicate(true)
	if captured_map.is_empty():
		return {"success": false, "reason": "EMPTY_FORK_MAP"}
	var captured_history: Array[Dictionary] = []
	for point_variant in get_continuous_history():
		if typeof(point_variant) == TYPE_DICTIONARY:
			captured_history.append(Dictionary(point_variant).duplicate(true))

	_vis21_fork_generation = fork_generation
	_vis21_fork_map = captured_map.duplicate(true)
	_vis21_fork_history = captured_history.duplicate(true)
	_vis21_common_root = ControlRunner.derive_common_random_seed_hash(_vis21_fork_generation, _vis21_fork_map)

	var control_result: Dictionary = _vis21_control.configure_from_fork(
		_vis21_fork_generation, _vis21_fork_map, _vis21_fork_history
	)
	if not bool(control_result.get("success", false)):
		return {"success": false, "reason": "CONTROL_CONFIGURE_FAILED", "detail": control_result}
	if _vis21_control.common_random_seed_hash() != _vis21_common_root:
		return {"success": false, "reason": "CONTROL_ROOT_MISMATCH"}

	var treatment_result: Dictionary = _vis21_treatment.configure_from_fork(
		_vis21_fork_generation,
		_vis21_fork_map,
		_vis21_fork_history,
		_vis21_treatment_profile,
		_vis21_treatment_intensity,
		_vis21_common_root
	)
	if not bool(treatment_result.get("success", false)):
		return {"success": false, "reason": "TREATMENT_CONFIGURE_FAILED", "detail": treatment_result}
	if _vis21_treatment.common_random_seed_hash() != _vis21_control.common_random_seed_hash():
		return {"success": false, "reason": "COMMON_ROOT_MISMATCH"}

	_vis21_treatment_schedule = [{
		"effective_generation": _vis21_fork_generation + 1,
		"experiment_id": _vis21_treatment_profile,
		"intensity": _vis21_treatment_intensity,
	}]
	_vis21_simulated_generation = _vis21_fork_generation
	_vis21_paired = true
	_clear_vis19_progressive_detail()
	_vis19_detail_generation = -1
	_rebuild_vis21_comparison()
	if not bool(_vis21_comparison_summary.get("success", false)):
		_vis21_paired = false
		return {"success": false, "reason": "FORK_COMPARISON_FAILED", "detail": _vis21_comparison_summary}

	var fork_point := _vis21_point_for_generation(_vis21_comparison_summary.get("points", []), _vis21_fork_generation)
	if fork_point.is_empty() or not _vis21_zero_deltas(fork_point):
		_vis21_paired = false
		return {"success": false, "reason": "FORK_DELTA_NONZERO"}

	_render_vis21_generation(_vis21_fork_generation)
	_update_vis18r_title()
	_update_status()
	return {
		"success": true,
		"fork_generation": _vis21_fork_generation,
		"common_random_seed_hash": _vis21_common_root,
		"field_hash": String(fork_point.get("control_field_hash", "")),
	}


func advance_paired_to(target_generation: int) -> Dictionary:
	if not _vis21_paired:
		return {"success": false, "reason": "NOT_PAIRED"}
	if target_generation < _vis21_fork_generation:
		return {"success": false, "reason": "BEFORE_FORK"}
	if target_generation > _vis21_simulated_generation:
		for next_generation in range(_vis21_simulated_generation + 1, target_generation + 1):
			var control_result: Dictionary = _vis21_control.advance_to(next_generation)
			if not bool(control_result.get("success", false)):
				return {"success": false, "reason": "CONTROL_ADVANCE_FAILED", "detail": control_result}
			var treatment_result: Dictionary = _vis21_treatment.advance_to(next_generation)
			if not bool(treatment_result.get("success", false)):
				return {"success": false, "reason": "TREATMENT_ADVANCE_FAILED", "detail": treatment_result}
			if _vis21_control.generation_map(next_generation).is_empty():
				return {"success": false, "reason": "CONTROL_GENERATION_NOT_CACHED", "generation": next_generation}
			if _vis21_treatment.generation_map(next_generation).is_empty():
				return {"success": false, "reason": "TREATMENT_GENERATION_NOT_CACHED", "generation": next_generation}
			_vis21_simulated_generation = next_generation
			var prune_result := _prune_vis21_branch_caches(next_generation)
			if not bool(prune_result.get("success", false)):
				return prune_result

	var visible_target := clampi(
		target_generation,
		_oldest_paired_rewind_generation(),
		_vis21_simulated_generation
	)
	_vis18r_generation = visible_target
	_vis18r_play_accumulator = 0.0
	_clear_vis19_progressive_detail()
	_render_vis21_generation(visible_target)
	_rebuild_vis21_comparison()
	_update_vis18r_title()
	_update_status()
	return {"success": bool(_vis21_comparison_summary.get("success", false)), "generation": visible_target}

func set_realtime_turnover_generation(generation: int) -> void:
	if not _vis21_paired:
		super.set_realtime_turnover_generation(generation)
		return
	var target := clampi(
		generation,
		_oldest_paired_rewind_generation(),
		_vis21_simulated_generation
	)
	advance_paired_to(target)

func restart_paired_from_fork() -> Dictionary:
	if not _vis21_paired:
		return {"success": false, "reason": "NOT_PAIRED"}
	var root_before := _vis21_common_root
	var control_result: Dictionary = _vis21_control.restart_from_fork()
	var treatment_result: Dictionary = _vis21_treatment.restart_from_fork()
	if not bool(control_result.get("success", false)) or not bool(treatment_result.get("success", false)):
		return {"success": false, "reason": "RESTART_FAILED"}
	if _vis21_control.common_random_seed_hash() != root_before or _vis21_treatment.common_random_seed_hash() != root_before:
		return {"success": false, "reason": "ROOT_CHANGED_ON_RESTART"}
	_vis21_simulated_generation = _vis21_fork_generation
	_vis18r_generation = _vis21_fork_generation
	_vis18r_play_accumulator = 0.0
	_clear_vis19_progressive_detail()
	_render_vis21_generation(_vis21_fork_generation)
	_rebuild_vis21_comparison()
	_update_vis18r_title()
	_update_status()
	return {"success": true, "generation": _vis21_fork_generation, "common_random_seed_hash": root_before}


func set_treatment(profile: String, intensity: float) -> Dictionary:
	var normalized_profile := VIS20_ExperimentModel.normalize_profile(profile)
	if normalized_profile not in TreatmentRunner.TREATMENT_PROFILES:
		return {"success": false, "reason": "INVALID_TREATMENT_EXPERIMENT"}
	var normalized_intensity := VIS20_ExperimentModel.normalize_intensity(normalized_profile, intensity)
	_vis21_treatment_profile = normalized_profile
	_vis21_treatment_intensity = normalized_intensity
	if not _vis21_paired:
		_update_status()
		return {"success": true, "effective_generation": -1, "experiment_id": normalized_profile, "intensity": normalized_intensity}

	if _vis18r_generation < _vis21_simulated_generation:
		var rewind_result: Dictionary = _vis21_treatment.rewind_to_cached_generation(_vis18r_generation)
		if not bool(rewind_result.get("success", false)):
			return rewind_result
		_vis21_simulated_generation = _vis18r_generation

	var root_before := _vis21_common_root
	var result: Dictionary = _vis21_treatment.set_experiment(normalized_profile, normalized_intensity)
	if not bool(result.get("success", false)):
		return result
	if _vis21_treatment.common_random_seed_hash() != root_before or _vis21_control.common_random_seed_hash() != root_before:
		return {"success": false, "reason": "ROOT_CHANGED_ON_TREATMENT_SWITCH"}

	var effective_generation := int(result.get("effective_generation", _vis18r_generation + 1))
	var retained: Array[Dictionary] = []
	for entry in _vis21_treatment_schedule:
		if int(entry.get("effective_generation", 0)) < effective_generation:
			retained.append(entry.duplicate(true))
	retained.append({
		"effective_generation": effective_generation,
		"experiment_id": normalized_profile,
		"intensity": normalized_intensity,
	})
	_vis21_treatment_schedule = retained
	_rebuild_vis21_comparison()
	_vis21_apply_visual_cue()
	_update_vis18r_title()
	_update_status()
	return result


func get_vis21_state() -> Dictionary:
	var control_map := _vis21_control.generation_map(_vis18r_generation) if _vis21_paired else {}
	var treatment_map := _vis21_treatment.generation_map(_vis18r_generation) if _vis21_paired else {}
	return {
		"stage": VIS21_STAGE,
		"mode": VIS21_MODE,
		"paired": _vis21_paired,
		"fork_generation": _vis21_fork_generation,
		"paired_generation": _vis18r_generation,
		"simulated_generation": _vis21_simulated_generation,
		"common_random_seed_hash": _vis21_common_root,
		"control_map": control_map,
		"treatment_map": treatment_map,
		"control_trace_count": _vis21_control_trace.size(),
		"treatment_trace_count": _vis21_treatment_trace.size(),
		"control_cached_generation_count": _vis21_control.cached_generation_count(),
		"treatment_cached_generation_count": _vis21_treatment.cached_generation_count(),
		"control_cached_trace_point_count": _vis21_control.cached_trace_point_count(),
		"treatment_cached_trace_point_count": _vis21_treatment.cached_trace_point_count(),
		"control_oldest_cached_generation": _vis21_control.oldest_cached_generation(),
		"treatment_oldest_cached_generation": _vis21_treatment.oldest_cached_generation(),
		"oldest_paired_rewind_generation": _oldest_paired_rewind_generation(),
		"comparison_point_count": int(_vis21_comparison_summary.get("point_count", 0)),
		"comparison_rebuild_input_count": _vis21_comparison_rebuild_input_count,
		"treatment_profile": _vis21_treatment_profile,
		"treatment_intensity": _vis21_treatment_intensity,
		"control_data_only": true,
		"visible_population_fields": 1,
		"whole_field_ph5_rebuilds": _vis18r_ph5_rebuilds_during_turnover,
		"progressive_ph5_count": _vis19_detail_nodes.size(),
		"treatment_runner_in_tree": is_instance_valid(_vis21_treatment) and _vis21_treatment.get_parent() == self and _vis21_treatment.is_inside_tree(),
		"treatment_runner_child_count": _vis21_treatment.get_child_count() if is_instance_valid(_vis21_treatment) else -1,
		"scene_node_count": get_tree().get_node_count() if get_tree() != null else 0,
		"peak_scene_node_count": _vis21_peak_node_count,
	}


func get_vis21_comparison_summary() -> Dictionary:
	return _vis21_comparison_summary.duplicate(true)


func get_vis21_canonical_traces() -> Dictionary:
	return {
		"control": _vis21_control_trace.duplicate(true),
		"treatment": _vis21_treatment_trace.duplicate(true),
	}


func get_vis21_control_runner() -> RefCounted:
	return _vis21_control


func get_vis21_treatment_runner() -> Node:
	return _vis21_treatment


func _prune_vis21_branch_caches(generation: int) -> Dictionary:
	var floor_generation := maxi(
		_vis21_fork_generation,
		generation - VIS21_BRANCH_CACHE_WINDOW + 1
	)
	var control_prune: Dictionary = _vis21_control.prune_before(floor_generation)
	if not bool(control_prune.get("success", false)):
		return {"success": false, "reason": "CONTROL_PRUNE_FAILED", "detail": control_prune}
	var treatment_prune: Dictionary = _vis21_treatment.prune_before(floor_generation)
	if not bool(treatment_prune.get("success", false)):
		return {"success": false, "reason": "TREATMENT_PRUNE_FAILED", "detail": treatment_prune}
	return {"success": true, "floor_generation": floor_generation}


func _oldest_paired_rewind_generation() -> int:
	if not _vis21_paired:
		return _vis21_fork_generation
	var control_oldest := _vis21_control.oldest_cached_generation()
	var treatment_oldest := _vis21_treatment.oldest_cached_generation()
	if control_oldest < 0 or treatment_oldest < 0:
		return _vis21_fork_generation
	return maxi(control_oldest, treatment_oldest)


func _rebuild_vis21_comparison() -> void:
	_vis21_control_trace.clear()
	_vis21_treatment_trace.clear()
	_vis21_comparison_rebuild_input_count = 0
	if not _vis21_paired:
		_vis21_comparison_summary = {}
		return

	var generations: Array[int] = [_vis21_fork_generation]
	if _vis21_simulated_generation > _vis21_fork_generation:
		var post_fork_start := maxi(
			_vis21_fork_generation + 1,
			_vis21_simulated_generation - (VIS21_SERIES_WINDOW - 2)
		)
		post_fork_start = maxi(post_fork_start, _oldest_paired_rewind_generation())
		for generation in range(post_fork_start, _vis21_simulated_generation + 1):
			generations.append(generation)
	_vis21_comparison_rebuild_input_count = generations.size()

	for generation in generations:
		var control_map := _vis21_control.generation_map(generation)
		var treatment_map := _vis21_treatment.generation_map(generation)
		if control_map.is_empty() or treatment_map.is_empty():
			_vis21_comparison_summary = {
				"success": false,
				"error_code": "PAIR_GENERATION_NOT_AVAILABLE",
				"generation": generation,
			}
			return
		var control_environment := _vis21_control.baseline_environment_sample_at(0.0, 0.0)
		var treatment_environment := _vis21_treatment.sample_environment_for_generation(generation, 0.0, 0.0)
		var control_point := TraceAdapter.from_generation_map(
			generation,
			control_map,
			ControlRunner.BRANCH_ID,
			ControlRunner.EXPERIMENT_ID,
			String(control_environment.get("environment_revision", ""))
		)
		var treatment_point := TraceAdapter.from_generation_map(
			generation,
			treatment_map,
			TreatmentRunner.BRANCH_ID,
			_vis21_experiment_for_generation(generation),
			String(treatment_environment.get("environment_revision", ""))
		)
		if control_point.is_empty() or treatment_point.is_empty():
			_vis21_comparison_summary = {
				"success": false,
				"error_code": "CANONICAL_TRACE_ADAPTER_FAILED",
				"generation": generation,
			}
			return
		_vis21_control_trace.append(control_point)
		_vis21_treatment_trace.append(treatment_point)

	_vis21_comparison_summary = ComparisonModel.summarize(
		_vis21_control_trace,
		_vis21_treatment_trace,
		_vis21_fork_generation,
		true
	)
	if is_instance_valid(_vis21_panel):
		_vis21_panel.call("set_comparison_data", _vis21_control_trace, _vis21_treatment_trace, _vis21_fork_generation, true)

func _render_vis21_generation(generation: int) -> void:
	var generation_map := _vis21_treatment.generation_map(generation)
	if generation_map.is_empty():
		return
	if generation == 0:
		_vis18r_renderer.show_generation_zero(_ph5_root)
		_apply_generation_zero_summary(generation_map)
	else:
		var render_summary: Dictionary = _vis18r_renderer.show_realtime_generation(self, _ph5_root, generation, generation_map)
		_vis18r_current_visual_count = int(render_summary.get("visual_count", 0))
		_vis18r_current_births = int(render_summary.get("birth_count", 0))
		_vis18r_current_deaths = int(render_summary.get("death_count", 0))
		_vis18r_current_survivors = int(render_summary.get("survivor_count", 0))
		_vis18r_represented_biomass_kg = float(render_summary.get("represented_biomass_kg", 0.0))
		_vis18r_turnover_hash = String(render_summary.get("turnover_hash", ""))
	var point := TraceAdapter.from_generation_map(
		generation,
		generation_map,
		TreatmentRunner.BRANCH_ID,
		_vis21_experiment_for_generation(generation),
		String(_vis21_treatment.sample_environment_for_generation(generation, 0.0, 0.0).get("environment_revision", ""))
	)
	_vis18r_field_hash = String(point.get("field_hash", ""))
	_vis18r_cumulative_births = 0
	_vis18r_cumulative_deaths = 0
	for trace_point in _vis21_treatment_trace:
		_vis18r_cumulative_births += int(trace_point.get("birth_count", 0))
		_vis18r_cumulative_deaths += int(trace_point.get("death_count", 0))


func _vis21_experiment_for_generation(generation: int) -> String:
	if generation <= _vis21_fork_generation:
		return VIS20_ExperimentModel.PROFILE_BASELINE
	var result := _vis21_treatment_profile
	for entry in _vis21_treatment_schedule:
		if int(entry.get("effective_generation", 0)) <= generation:
			result = String(entry.get("experiment_id", result))
	return result


func _vis21_intensity_for_generation(generation: int) -> float:
	if generation <= _vis21_fork_generation:
		return 0.0
	var result := _vis21_treatment_intensity
	for entry in _vis21_treatment_schedule:
		if int(entry.get("effective_generation", 0)) <= generation:
			result = float(entry.get("intensity", result))
	return result


func _create_vis21_comparison_panel() -> void:
	_vis21_layer = CanvasLayer.new()
	_vis21_layer.name = "VIS21ComparisonLayer"
	_vis21_layer.layer = 22
	add_child(_vis21_layer)
	_vis21_panel = ComparisonPanel.new()
	_vis21_panel.name = "ControlTreatmentComparison"
	_vis21_panel.position = Vector2(1018.0, 78.0)
	_vis21_panel.size = Vector2(404.0, 370.0)
	_vis21_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vis21_layer.add_child(_vis21_panel)


func _vis21_apply_visual_cue() -> void:
	var light := get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if light == null:
		return
	match _vis21_treatment_profile:
		VIS20_ExperimentModel.PROFILE_DROUGHT:
			light.light_color = Color(1.0, 0.84, 0.64)
			light.light_energy = 1.15 + 0.22 * _vis21_treatment_intensity
		VIS20_ExperimentModel.PROFILE_FLOOD:
			light.light_color = Color(0.72, 0.86, 1.0)
			light.light_energy = 1.05
		VIS20_ExperimentModel.PROFILE_NUTRIENT:
			light.light_color = Color(0.86, 1.0, 0.82)
			light.light_energy = 1.14
		VIS20_ExperimentModel.PROFILE_SHADE:
			light.light_color = Color(0.72, 0.78, 0.90)
			light.light_energy = maxf(0.48, 1.15 * (1.0 - 0.48 * _vis21_treatment_intensity))


func _track_vis21_node_count() -> void:
	if get_tree() == null:
		return
	_vis21_last_node_count = get_tree().get_node_count()
	_vis21_peak_node_count = maxi(_vis21_peak_node_count, _vis21_last_node_count)


func _vis21_point_for_generation(points: Array, generation: int) -> Dictionary:
	for point_variant in points:
		if typeof(point_variant) == TYPE_DICTIONARY and int(Dictionary(point_variant).get("generation", -1)) == generation:
			return Dictionary(point_variant)
	return {}


func _vis21_zero_deltas(point: Dictionary) -> bool:
	return (
		int(point.get("delta_population", 0)) == 0
		and int(point.get("delta_deaths", 0)) == 0
		and int(point.get("delta_survivors", 0)) == 0
		and absf(float(point.get("delta_mean_fitness", 0.0))) <= 0.000000001
		and int(point.get("delta_unique_genomes", 0)) == 0
		and absf(float(point.get("delta_alpha_share", 0.0))) <= 0.000000001
	)


func _update_vis18r_title() -> void:
	if not _vis21_paired:
		super._update_vis18r_title()
		return
	var title := get_node_or_null("HUD/Margin/Panel/VBox/Title") as Label
	if title == null:
		return
	title.text = "ECO.VIS2.1 — %s fork=G%d paired=G%d — %s %d%% — reps=%d" % [
		"PLAY" if _vis18r_playing else "PAUSE",
		_vis21_fork_generation,
		_vis18r_generation,
		_vis21_treatment_profile,
		int(round(_vis21_treatment_intensity * 100.0)),
		_vis18r_current_visual_count,
	]


func _update_status() -> void:
	super._update_status()
	var status := get_node_or_null("HUD/Margin/Panel/VBox/Status") as Label
	if status == null:
		return
	if not _vis21_paired:
		status.text += "\nVIS2.1=READY treatment=%s %d%% | F forks the current BASELINE generation; 2/3/4/5 select treatment without altering pre-fork world." % [
			_vis21_treatment_profile,
			int(round(_vis21_treatment_intensity * 100.0)),
		]
		return
	var points: Array = _vis21_comparison_summary.get("points", [])
	var current := _vis21_point_for_generation(points, _vis18r_generation)
	status.text += "\nVIS2.1=PAIRED fork=G%d paired=G%d treatment=%s %d%% root=%s" % [
		_vis21_fork_generation,
		_vis18r_generation,
		_vis21_treatment_profile,
		int(round(_vis21_treatment_intensity * 100.0)),
		_vis21_common_root.left(12),
	]
	if not current.is_empty():
		status.text += "\nCONTROL reps=%d fitness=%.3f genomes=%d | TREATMENT reps=%d fitness=%.3f genomes=%d" % [
			int(current.get("control_population", 0)),
			float(current.get("control_mean_fitness", 0.0)),
			int(current.get("control_unique_genomes", 0)),
			int(current.get("treatment_population", 0)),
			float(current.get("treatment_mean_fitness", 0.0)),
			int(current.get("treatment_unique_genomes", 0)),
		]
		status.text += "\nDELTA population=%+d fitness=%+.4f genomes=%+d deaths=%+d alpha_share=%+.4f | CONTROL=data-only visible_fields=1 progressive_PH5=OFF" % [
			int(current.get("delta_population", 0)),
			float(current.get("delta_mean_fitness", 0.0)),
			int(current.get("delta_unique_genomes", 0)),
			int(current.get("delta_deaths", 0)),
			float(current.get("delta_alpha_share", 0.0)),
		]

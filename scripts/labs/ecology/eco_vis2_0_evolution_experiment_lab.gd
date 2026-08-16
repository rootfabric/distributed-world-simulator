extends "res://scripts/labs/ecology/eco_vis1_9_evolution_observatory.gd"

const VIS20_ExperimentModel = preload("res://scripts/labs/ecology/eco_vis2_0_experiment_model.gd")
const VIS20_ExperimentPanel = preload("res://scripts/labs/ecology/eco_vis2_0_experiment_panel.gd")

const VIS2_0_STAGE := "ECO.VIS2.0"
const VIS20_MODE := "CONTROLLED_ENVIRONMENT_EVOLUTION_EXPERIMENT"
const VIS20_DEFAULT_INTENSITY := 0.75
const VIS20_INTENSITY_STEP := 0.10

var _vis20_profile := VIS20_ExperimentModel.PROFILE_BASELINE
var _vis20_intensity := 0.0
var _vis20_epoch := 0
var _vis20_effective_generation := 0
var _vis20_events: Array[Dictionary] = []
var _vis20_branch_truncations := 0
var _vis20_experiment_layer: CanvasLayer
var _vis20_experiment_panel: Control
var _vis20_panel_visible := true
var _vis20_last_panel_generation := -1

func sample_environment_at(x: float, z: float) -> Dictionary:
	var baseline := super.sample_environment_at(x, z)
	return VIS20_ExperimentModel.apply(baseline, _vis20_profile, _vis20_intensity, _vis20_epoch)

func sample_environment_context_at(x: float, z: float) -> Dictionary:
	var context := super.sample_environment_context_at(x, z)
	var baseline: Dictionary = context.get("environment", {})
	context["environment"] = VIS20_ExperimentModel.apply(baseline, _vis20_profile, _vis20_intensity, _vis20_epoch)
	context["experiment_profile"] = _vis20_profile
	context["experiment_intensity"] = _vis20_intensity
	return context

func _ready() -> void:
	super._ready()
	_create_vis20_experiment_panel()
	_vis20_record_event(0, "INITIAL")
	_vis20_apply_visual_cue()
	_vis20_refresh_panel()
	if is_instance_valid(_controls_label):
		_controls_label.text = "WASD move | Q/E down/up | Shift boost | mouse look | Esc capture | Left/Right generation | Space play/pause | R restart G0 | O observatory | PgUp/PgDn inspect | 1 baseline | 2 drought | 3 flood | 4 nutrient | 5 shade | -/+ intensity | I experiment panel | F1-F5 diagnostics\nVIS2.0: interventions alter lab-derived EnvironmentSample for future turnover/selection; existing history and canonical VIS1.2 environment remain read-only"
	_update_vis18r_title()
	_update_status()

func _process(delta: float) -> void:
	var generation_before := _vis18r_generation
	super._process(delta)
	if _vis18r_generation != generation_before or _vis20_last_panel_generation != _vis18r_generation:
		_vis20_refresh_panel()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			match key_event.keycode:
				KEY_1:
					set_experiment_profile(VIS20_ExperimentModel.PROFILE_BASELINE, 0.0)
					get_viewport().set_input_as_handled()
					return
				KEY_2:
					_vis20_select_profile(VIS20_ExperimentModel.PROFILE_DROUGHT)
					get_viewport().set_input_as_handled()
					return
				KEY_3:
					_vis20_select_profile(VIS20_ExperimentModel.PROFILE_FLOOD)
					get_viewport().set_input_as_handled()
					return
				KEY_4:
					_vis20_select_profile(VIS20_ExperimentModel.PROFILE_NUTRIENT)
					get_viewport().set_input_as_handled()
					return
				KEY_5:
					_vis20_select_profile(VIS20_ExperimentModel.PROFILE_SHADE)
					get_viewport().set_input_as_handled()
					return
				KEY_MINUS:
					set_experiment_intensity(_vis20_intensity - VIS20_INTENSITY_STEP)
					get_viewport().set_input_as_handled()
					return
				KEY_EQUAL:
					set_experiment_intensity(_vis20_intensity + VIS20_INTENSITY_STEP)
					get_viewport().set_input_as_handled()
					return
				KEY_I:
					_vis20_panel_visible = not _vis20_panel_visible
					if is_instance_valid(_vis20_experiment_panel):
						_vis20_experiment_panel.call("set_experiment_panel_visible", _vis20_panel_visible)
					get_viewport().set_input_as_handled()
					return
	super._unhandled_input(event)

func set_realtime_turnover_generation(generation: int) -> void:
	var previous_generation := _vis18r_generation
	super.set_realtime_turnover_generation(generation)
	if _vis18r_generation == 0 and previous_generation != 0:
		_vis20_events.clear()
		_vis20_epoch += 1
		_vis20_effective_generation = 0 if _vis20_profile == VIS20_ExperimentModel.PROFILE_BASELINE else 1
		_vis20_record_event(_vis20_effective_generation, "RESTART")
		_vis20_apply_visual_cue()
	_vis20_refresh_panel()

func set_experiment_profile(profile: String, intensity: float = -1.0) -> void:
	var normalized_profile := VIS20_ExperimentModel.normalize_profile(profile)
	var requested_intensity := intensity
	if requested_intensity < 0.0:
		requested_intensity = VIS20_DEFAULT_INTENSITY if normalized_profile != VIS20_ExperimentModel.PROFILE_BASELINE else 0.0
	var normalized_intensity := VIS20_ExperimentModel.normalize_intensity(normalized_profile, requested_intensity)
	if normalized_profile == _vis20_profile and absf(normalized_intensity - _vis20_intensity) <= 0.000001:
		return
	_vis20_prepare_experiment_branch()
	_vis20_profile = normalized_profile
	_vis20_intensity = normalized_intensity
	_vis20_epoch += 1
	_vis20_effective_generation = _vis18r_generation + 1 if _vis20_profile != VIS20_ExperimentModel.PROFILE_BASELINE else _vis18r_generation
	_vis20_record_event(_vis20_effective_generation, "INTERVENTION")
	_vis20_after_intervention_change()

func set_experiment_intensity(intensity: float) -> void:
	if _vis20_profile == VIS20_ExperimentModel.PROFILE_BASELINE:
		return
	var normalized := VIS20_ExperimentModel.normalize_intensity(_vis20_profile, intensity)
	if absf(normalized - _vis20_intensity) <= 0.000001:
		return
	_vis20_prepare_experiment_branch()
	_vis20_intensity = normalized
	_vis20_epoch += 1
	_vis20_effective_generation = _vis18r_generation + 1
	_vis20_record_event(_vis20_effective_generation, "INTENSITY")
	_vis20_after_intervention_change()

func get_experiment_state() -> Dictionary:
	return {
		"stage": VIS2_0_STAGE,
		"mode": VIS20_MODE,
		"profile": _vis20_profile,
		"intensity": _vis20_intensity,
		"epoch": _vis20_epoch,
		"effective_generation": _vis20_effective_generation,
		"current_generation": _vis18r_generation,
		"playing": _vis18r_playing,
		"event_count": _vis20_events.size(),
		"branch_truncations": _vis20_branch_truncations,
		"panel_visible": _vis20_panel_visible,
		"canonical_environment_truth": false,
		"canonical_population_truth": false,
		"canonical_timeline_truth": false,
	}

func get_experiment_events() -> Array[Dictionary]:
	return _vis20_events.duplicate(true)

func get_experiment_probe(x: float, z: float) -> Dictionary:
	var baseline := _vis20_baseline_sample_at(x, z)
	var experimental := VIS20_ExperimentModel.apply(baseline, _vis20_profile, _vis20_intensity, _vis20_epoch)
	return {
		"world_x": x,
		"world_z": z,
		"baseline": baseline.duplicate(true),
		"experimental": experimental.duplicate(true),
		"delta": VIS20_ExperimentModel.delta(baseline, experimental),
	}

func _vis20_baseline_sample_at(x: float, z: float) -> Dictionary:
	return super.sample_environment_at(x, z)

func _vis20_select_profile(profile: String) -> void:
	var intensity := _vis20_intensity
	if intensity <= 0.000001:
		intensity = VIS20_DEFAULT_INTENSITY
	set_experiment_profile(profile, intensity)

func _vis20_prepare_experiment_branch() -> void:
	var state := get_realtime_turnover_state()
	var max_simulated := int(state.get("max_simulated_generation", _vis18r_generation))
	if max_simulated <= _vis18r_generation:
		return
	var result := VIS20_ExperimentModel.truncate_future(_vis18r_model, _vis18r_generation)
	if bool(result.get("success", false)) and int(result.get("removed_generations", 0)) > 0:
		_vis20_branch_truncations += 1
		_vis19_selected_generation = _vis18r_generation
		_vis19_follow_live = true
		_refresh_vis19_observatory(true)

func _vis20_after_intervention_change() -> void:
	_vis20_apply_visual_cue()
	if _vis18r_generation > 0:
		_apply_vis18r_generation(_vis18r_generation)
	_reset_vis19_detail_queue()
	_refresh_vis19_observatory(true)
	_vis20_refresh_panel()
	_update_vis18r_title()
	_update_status()

func _vis20_record_event(effective_generation: int, reason: String) -> void:
	_vis20_events.append({
		"event_index": _vis20_events.size(),
		"set_at_generation": _vis18r_generation,
		"effective_generation": maxi(0, effective_generation),
		"profile": _vis20_profile,
		"intensity": _vis20_intensity,
		"epoch": _vis20_epoch,
		"reason": reason,
	})
	while _vis20_events.size() > 32:
		_vis20_events.pop_front()

func _create_vis20_experiment_panel() -> void:
	_vis20_experiment_layer = CanvasLayer.new()
	_vis20_experiment_layer.name = "VIS20ExperimentLayer"
	_vis20_experiment_layer.layer = 21
	add_child(_vis20_experiment_layer)
	_vis20_experiment_panel = VIS20_ExperimentPanel.new()
	_vis20_experiment_panel.name = "EvolutionExperiment"
	_vis20_experiment_panel.position = Vector2(18.0, 690.0)
	_vis20_experiment_panel.size = Vector2(570.0, 190.0)
	_vis20_experiment_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vis20_experiment_layer.add_child(_vis20_experiment_panel)

func _vis20_refresh_panel() -> void:
	_vis20_last_panel_generation = _vis18r_generation
	if not is_instance_valid(_vis20_experiment_panel):
		return
	var probe_x := 0.0
	var probe_z := 0.0
	if is_instance_valid(_camera):
		probe_x = _camera.global_position.x
		probe_z = _camera.global_position.z
	_vis20_experiment_panel.call("set_experiment_data", get_experiment_state(), get_experiment_probe(probe_x, probe_z), _vis20_events)

func _vis20_apply_visual_cue() -> void:
	var light := get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if light == null:
		return
	match _vis20_profile:
		VIS20_ExperimentModel.PROFILE_DROUGHT:
			light.light_color = Color(1.0, 0.84, 0.64)
			light.light_energy = 1.15 + 0.22 * _vis20_intensity
		VIS20_ExperimentModel.PROFILE_FLOOD:
			light.light_color = Color(0.72, 0.86, 1.0)
			light.light_energy = 1.05
		VIS20_ExperimentModel.PROFILE_NUTRIENT:
			light.light_color = Color(0.86, 1.0, 0.82)
			light.light_energy = 1.14
		VIS20_ExperimentModel.PROFILE_SHADE:
			light.light_color = Color(0.72, 0.78, 0.90)
			light.light_energy = maxf(0.48, 1.15 * (1.0 - 0.48 * _vis20_intensity))
		_:
			light.light_color = Color.WHITE
			light.light_energy = 1.15

func _update_vis18r_title() -> void:
	var title := get_node_or_null("HUD/Margin/Panel/VBox/Title") as Label
	if title == null:
		return
	var play_label := "PLAY" if _vis18r_playing else "PAUSE"
	var experiment_label := _vis20_profile if _vis20_profile != VIS20_ExperimentModel.PROFILE_BASELINE else "BASELINE"
	title.text = "%s — %s G%d — %s %d%% — reps=%d +%d/-%d" % [
		VIS2_0_STAGE,
		play_label,
		_vis18r_generation,
		experiment_label,
		int(round(_vis20_intensity * 100.0)),
		_vis18r_current_visual_count,
		_vis18r_current_births,
		_vis18r_current_deaths,
	]

func _update_status() -> void:
	super._update_status()
	var status := get_node_or_null("HUD/Margin/Panel/VBox/Status") as Label
	if status == null:
		return
	status.text += "\nVIS2.0=ACTIVE experiment=%s intensity=%d%% set_at=G%d effective=G%d epoch=%d branch_truncations=%d | canonical_environment_truth=OFF" % [
		_vis20_profile,
		int(round(_vis20_intensity * 100.0)),
		_vis18r_generation,
		_vis20_effective_generation,
		_vis20_epoch,
		_vis20_branch_truncations,
	]
	status.text += "\nexperiment controls: 1 BASELINE | 2 DROUGHT | 3 FLOOD | 4 NUTRIENT_PULSE | 5 SHADE | -/+ intensity | I panel | interventions branch only future cached generations; observatory history before intervention stays intact"

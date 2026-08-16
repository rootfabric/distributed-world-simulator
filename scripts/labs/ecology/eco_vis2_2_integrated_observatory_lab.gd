extends "res://scripts/labs/ecology/eco_vis2_1v_treatment_realtime_lod_lab.gd"

const VIS22D_PairSet = preload("res://scripts/labs/ecology/eco_vis2_2_replicate_pair_set.gd")
const VIS22D_AggregateModel = preload("res://scripts/labs/ecology/eco_vis2_2_aggregate_effect_model.gd")
const VIS22D_PairTraceAdapter = preload("res://scripts/labs/ecology/eco_vis2_2_pair_trace_adapter.gd")
const VIS22D_ObservatoryPanel = preload("res://scripts/labs/ecology/eco_vis2_2_observatory_panel.gd")
const VIS22D_TraceAdapter = preload("res://scripts/labs/ecology/eco_vis2_1_trace_adapter.gd")
const VIS22D_TreatmentRunner = preload("res://scripts/labs/ecology/eco_vis2_1_treatment_branch_runner.gd")
const VIS22D_ExperimentModel = preload("res://scripts/labs/ecology/eco_vis2_0_experiment_model.gd")

const VIS22D_STAGE := "ECO.VIS2.2-D"
const VIS22D_MODE := "INTEGRATED_REPLICATED_CAUSAL_OBSERVATORY"
const VIS22D_DEFAULT_REPLICATE_COUNT := 8
const VIS22D_MIN_REPLICATE_COUNT := 2
const VIS22D_MAX_REPLICATE_COUNT := 16

var _vis22d_active := false
var _vis22d_pair_set: Node = null
var _vis22d_aggregate = null
var _vis22d_panel_layer: CanvasLayer = null
var _vis22d_panel: Control = null
var _vis22d_fork_generation := -1
var _vis22d_generation := -1
var _vis22d_selected_replicate := 0
var _vis22d_replicate_count := VIS22D_DEFAULT_REPLICATE_COUNT
var _vis22d_treatment_profile := VIS22D_ExperimentModel.PROFILE_DROUGHT
var _vis22d_treatment_intensity := 1.0
var _vis22d_last_selected_field_hash := ""


func _ready() -> void:
	super._ready()

	# VIS2.2-D does not use the single-pair VIS2.1 Treatment runner. It is created by
	# the inherited class initializer before _ready(), so retire that one valid runner
	# explicitly after parent setup. The D scene itself directly instances VIS2.0 and
	# therefore never creates an intermediate scripted PackedScene state.
	if is_instance_valid(_vis21_treatment):
		var inherited_runner: Node = _vis21_treatment
		_vis21_treatment = null
		inherited_runner.free()

	if is_instance_valid(_vis21_panel):
		_vis21_panel.visible = false

	if is_instance_valid(_controls_label):
		_controls_label.text = "WASD move | Q/E down/up | Shift boost | mouse look | Esc capture | F fork replicated experiment | Right next generation | Space play/pause | R restart fork | [ / ] selected replicate | 2 drought | 3 flood | 4 nutrient | 5 shade | -/+ intensity\nVIS2.2-D: all replicates are data-only except one selected TREATMENT realtime LOD world; selection is presentation-only."
	_update_vis18r_title()
	_update_status()


func _exit_tree() -> void:
	_vis22d_release_owned_state()
	super._exit_tree()


func _process(delta: float) -> void:
	if not _vis22d_active:
		super._process(delta)
		return

	_clear_vis19_progressive_detail()
	_vis19_detail_accumulator = 0.0
	if not _vis18r_playing:
		return

	_vis18r_play_accumulator += delta
	if _vis18r_play_accumulator < _vis18r_play_interval_seconds():
		return
	_vis18r_play_accumulator = 0.0
	var result := advance_replicated_to(_vis22d_generation + 1)
	if not bool(result.get("success", false)):
		_vis18r_playing = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			if not _vis22d_active and key_event.keycode == KEY_F:
				begin_replicated_experiment()
				get_viewport().set_input_as_handled()
				return
			if _vis22d_active:
				match key_event.keycode:
					KEY_F, KEY_I, KEY_LEFT:
						get_viewport().set_input_as_handled()
						return
					KEY_RIGHT:
						_vis18r_playing = false
						advance_replicated_to(_vis22d_generation + 1)
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
						restart_replicated_from_fork()
						get_viewport().set_input_as_handled()
						return
					KEY_BRACKETLEFT:
						select_replicate((_vis22d_selected_replicate - 1 + _vis22d_replicate_count) % _vis22d_replicate_count)
						get_viewport().set_input_as_handled()
						return
					KEY_BRACKETRIGHT:
						select_replicate((_vis22d_selected_replicate + 1) % _vis22d_replicate_count)
						get_viewport().set_input_as_handled()
						return
					KEY_2:
						set_replicated_treatment(VIS22D_ExperimentModel.PROFILE_DROUGHT, _vis22d_treatment_intensity)
						get_viewport().set_input_as_handled()
						return
					KEY_3:
						set_replicated_treatment(VIS22D_ExperimentModel.PROFILE_FLOOD, _vis22d_treatment_intensity)
						get_viewport().set_input_as_handled()
						return
					KEY_4:
						set_replicated_treatment(VIS22D_ExperimentModel.PROFILE_NUTRIENT, _vis22d_treatment_intensity)
						get_viewport().set_input_as_handled()
						return
					KEY_5:
						set_replicated_treatment(VIS22D_ExperimentModel.PROFILE_SHADE, _vis22d_treatment_intensity)
						get_viewport().set_input_as_handled()
						return
					KEY_MINUS:
						set_replicated_treatment(_vis22d_treatment_profile, _vis22d_treatment_intensity - 0.10)
						get_viewport().set_input_as_handled()
						return
					KEY_EQUAL:
						set_replicated_treatment(_vis22d_treatment_profile, _vis22d_treatment_intensity + 0.10)
						get_viewport().set_input_as_handled()
						return
	super._unhandled_input(event)


func set_replicate_count_for_next_fork(replicate_count: int) -> bool:
	if _vis22d_active:
		return false
	if replicate_count < VIS22D_MIN_REPLICATE_COUNT or replicate_count > VIS22D_MAX_REPLICATE_COUNT:
		return false
	_vis22d_replicate_count = replicate_count
	_update_status()
	return true


func begin_replicated_experiment() -> Dictionary:
	if _vis22d_active:
		return {"success": true, "fork_generation": _vis22d_fork_generation}
	if _vis20_profile != VIS22D_ExperimentModel.PROFILE_BASELINE:
		return {"success": false, "reason": "SOURCE_NOT_BASELINE"}

	_vis18r_playing = false
	var source_model := _vis18r_model as RefCounted
	if source_model == null:
		return {"success": false, "reason": "SOURCE_MODEL_MISSING"}

	var fork_generation := _vis18r_generation
	var fork_map: Dictionary = Dictionary(source_model.call("generation_map", fork_generation)).duplicate(true)
	if fork_map.is_empty():
		return {"success": false, "reason": "EMPTY_FORK_MAP"}
	var fork_history: Array[Dictionary] = []
	for point_variant in get_continuous_history():
		if typeof(point_variant) == TYPE_DICTIONARY:
			fork_history.append(Dictionary(point_variant).duplicate(true))

	_vis22d_release_pair_set_only()
	_vis22d_pair_set = VIS22D_PairSet.new()
	_vis22d_pair_set.name = "VIS22DReplicatePairSet"
	add_child(_vis22d_pair_set)
	var pair_result: Dictionary = _vis22d_pair_set.configure_from_fork(
		fork_generation,
		fork_map,
		fork_history,
		_vis22d_replicate_count,
		_vis22d_treatment_profile,
		_vis22d_treatment_intensity
	)
	if not bool(pair_result.get("success", false)):
		_vis22d_release_pair_set_only()
		return {"success": false, "reason": "PAIR_SET_CONFIGURE_FAILED", "detail": pair_result}

	_vis22d_aggregate = VIS22D_AggregateModel.new()
	var aggregate_config: Dictionary = _vis22d_aggregate.configure(fork_generation, _vis22d_replicate_count)
	if not bool(aggregate_config.get("success", false)):
		_vis22d_release_pair_set_only()
		_vis22d_aggregate = null
		return {"success": false, "reason": "AGGREGATE_CONFIGURE_FAILED", "detail": aggregate_config}

	var fork_inputs := VIS22D_PairTraceAdapter.build_generation_inputs(
		_vis22d_pair_set,
		fork_generation,
		_vis22d_treatment_profile
	)
	if not bool(fork_inputs.get("success", false)):
		_vis22d_release_pair_set_only()
		_vis22d_aggregate = null
		return {"success": false, "reason": "FORK_CANONICAL_INPUT_FAILED", "detail": fork_inputs}
	var append_result: Dictionary = _vis22d_aggregate.append_generation(fork_inputs.get("pairs", []))
	if not bool(append_result.get("success", false)):
		_vis22d_release_pair_set_only()
		_vis22d_aggregate = null
		return {"success": false, "reason": "FORK_AGGREGATE_FAILED", "detail": append_result}

	_vis22d_active = true
	_vis22d_fork_generation = fork_generation
	_vis22d_generation = fork_generation
	_vis22d_selected_replicate = 0
	_vis18r_generation = fork_generation
	_vis18r_play_accumulator = 0.0
	_vis21_paired = false
	_clear_vis19_progressive_detail()
	_vis19_detail_generation = -1
	_hide_vis20_source_panel()
	_vis22d_create_panel_if_needed()
	_vis22d_refresh_panel()
	_vis22d_render_selected_generation()
	_vis21_apply_visual_cue()
	_update_vis18r_title()
	_update_status()
	return {
		"success": true,
		"stage": VIS22D_STAGE,
		"fork_generation": _vis22d_fork_generation,
		"replicate_count": _vis22d_replicate_count,
		"selected_replicate": _vis22d_selected_replicate,
		"aggregate_series_hash": _vis22d_aggregate.series_hash(),
		"replicate_roots": _vis22d_pair_set.replicate_roots(),
	}


func advance_replicated_to(target_generation: int) -> Dictionary:
	if not _vis22d_active or not is_instance_valid(_vis22d_pair_set) or _vis22d_aggregate == null:
		return {"success": false, "reason": "NOT_ACTIVE"}
	if target_generation < _vis22d_generation:
		return {"success": false, "reason": "BACKWARD_ADVANCE_NOT_SUPPORTED"}
	if target_generation == _vis22d_generation:
		return {"success": true, "generation": _vis22d_generation, "advanced": 0}

	for generation in range(_vis22d_generation + 1, target_generation + 1):
		var pair_result: Dictionary = _vis22d_pair_set.advance_to(generation)
		if not bool(pair_result.get("success", false)):
			return {"success": false, "reason": "PAIR_ADVANCE_FAILED", "generation": generation, "detail": pair_result}
		var inputs := VIS22D_PairTraceAdapter.build_generation_inputs(
			_vis22d_pair_set,
			generation,
			_vis22d_treatment_profile
		)
		if not bool(inputs.get("success", false)):
			return {"success": false, "reason": "CANONICAL_INPUT_FAILED", "generation": generation, "detail": inputs}
		var aggregate_result: Dictionary = _vis22d_aggregate.append_generation(inputs.get("pairs", []))
		if not bool(aggregate_result.get("success", false)):
			return {"success": false, "reason": "AGGREGATE_APPEND_FAILED", "generation": generation, "detail": aggregate_result}
		_vis22d_generation = generation

	_vis18r_generation = _vis22d_generation
	_vis18r_play_accumulator = 0.0
	_clear_vis19_progressive_detail()
	_vis22d_refresh_panel()
	_vis22d_render_selected_generation()
	_update_vis18r_title()
	_update_status()
	return {
		"success": true,
		"generation": _vis22d_generation,
		"advanced": target_generation - (_vis22d_generation - (target_generation - _vis22d_generation)),
		"aggregate_series_hash": _vis22d_aggregate.series_hash(),
	}


func select_replicate(replicate_index: int) -> Dictionary:
	if not _vis22d_active or not is_instance_valid(_vis22d_pair_set) or _vis22d_aggregate == null:
		return {"success": false, "reason": "NOT_ACTIVE"}
	if replicate_index < 0 or replicate_index >= _vis22d_replicate_count:
		return {"success": false, "reason": "INVALID_REPLICATE"}
	var aggregate_hash_before := _vis22d_aggregate.series_hash()
	var roots_before: Array[String] = _vis22d_pair_set.replicate_roots()
	var generation_before := _vis22d_generation

	_vis22d_selected_replicate = replicate_index
	if is_instance_valid(_vis22d_panel):
		if not bool(_vis22d_panel.call("select_replicate", replicate_index)):
			return {"success": false, "reason": "PANEL_SELECTION_REJECTED"}
	_vis22d_render_selected_generation()
	_update_vis18r_title()
	_update_status()

	if _vis22d_aggregate.series_hash() != aggregate_hash_before:
		return {"success": false, "reason": "AGGREGATE_MUTATED_BY_SELECTION"}
	if _vis22d_pair_set.replicate_roots() != roots_before:
		return {"success": false, "reason": "ROOTS_MUTATED_BY_SELECTION"}
	if _vis22d_generation != generation_before:
		return {"success": false, "reason": "GENERATION_MUTATED_BY_SELECTION"}
	return {
		"success": true,
		"selected_replicate": _vis22d_selected_replicate,
		"generation": _vis22d_generation,
		"aggregate_series_hash": aggregate_hash_before,
		"selected_field_hash": _vis22d_last_selected_field_hash,
	}


func set_replicated_treatment(profile: String, intensity: float) -> Dictionary:
	var normalized_profile := VIS22D_ExperimentModel.normalize_profile(profile)
	if normalized_profile not in VIS22D_TreatmentRunner.TREATMENT_PROFILES:
		return {"success": false, "reason": "INVALID_TREATMENT_EXPERIMENT"}
	var normalized_intensity := VIS22D_ExperimentModel.normalize_intensity(normalized_profile, intensity)
	_vis22d_treatment_profile = normalized_profile
	_vis22d_treatment_intensity = normalized_intensity
	if not _vis22d_active:
		_update_status()
		return {"success": true, "effective_generation": -1, "experiment_id": normalized_profile, "intensity": normalized_intensity}
	var result: Dictionary = _vis22d_pair_set.set_treatment(normalized_profile, normalized_intensity)
	if not bool(result.get("success", false)):
		return result
	_vis21_apply_visual_cue()
	_update_vis18r_title()
	_update_status()
	return result


func restart_replicated_from_fork() -> Dictionary:
	if not _vis22d_active or not is_instance_valid(_vis22d_pair_set):
		return {"success": false, "reason": "NOT_ACTIVE"}
	var roots_before: Array[String] = _vis22d_pair_set.replicate_roots()
	var restart_result: Dictionary = _vis22d_pair_set.restart_all_from_fork()
	if not bool(restart_result.get("success", false)):
		return restart_result
	if _vis22d_pair_set.replicate_roots() != roots_before:
		return {"success": false, "reason": "ROOTS_CHANGED_ON_RESTART"}

	_vis22d_aggregate = VIS22D_AggregateModel.new()
	var config: Dictionary = _vis22d_aggregate.configure(_vis22d_fork_generation, _vis22d_replicate_count)
	if not bool(config.get("success", false)):
		return config
	var fork_inputs := VIS22D_PairTraceAdapter.build_generation_inputs(
		_vis22d_pair_set,
		_vis22d_fork_generation,
		_vis22d_treatment_profile
	)
	if not bool(fork_inputs.get("success", false)):
		return fork_inputs
	var append_result: Dictionary = _vis22d_aggregate.append_generation(fork_inputs.get("pairs", []))
	if not bool(append_result.get("success", false)):
		return append_result

	_vis22d_generation = _vis22d_fork_generation
	_vis18r_generation = _vis22d_generation
	_vis18r_play_accumulator = 0.0
	_clear_vis19_progressive_detail()
	_vis22d_refresh_panel()
	_vis22d_render_selected_generation()
	_update_vis18r_title()
	_update_status()
	return {
		"success": true,
		"generation": _vis22d_generation,
		"replicate_roots": roots_before,
		"aggregate_series_hash": _vis22d_aggregate.series_hash(),
	}


func sample_environment_at(world_x: float, world_z: float) -> Dictionary:
	if _vis22d_active and is_instance_valid(_vis22d_pair_set):
		var treatment = _vis22d_pair_set.treatment_runner(_vis22d_selected_replicate)
		if treatment != null:
			return treatment.sample_environment_for_generation(_vis22d_generation, world_x, world_z)
	return super.sample_environment_at(world_x, world_z)


func sample_environment_context_at(world_x: float, world_z: float) -> Dictionary:
	if not _vis22d_active:
		return super.sample_environment_context_at(world_x, world_z)
	var result := super.sample_environment_context_at(world_x, world_z)
	result["environment"] = sample_environment_at(world_x, world_z)
	result["experiment_profile"] = VIS22D_ExperimentModel.PROFILE_BASELINE if _vis22d_generation <= _vis22d_fork_generation else _vis22d_treatment_profile
	result["experiment_intensity"] = 0.0 if _vis22d_generation <= _vis22d_fork_generation else _vis22d_treatment_intensity
	result["replicate_index"] = _vis22d_selected_replicate
	return result


func get_vis22d_state() -> Dictionary:
	var aggregate_summary := {}
	var aggregate_hash := ""
	if _vis22d_aggregate != null:
		aggregate_summary = Dictionary(_vis22d_aggregate.summary()).duplicate(true)
		aggregate_hash = String(_vis22d_aggregate.series_hash())
	var panel_state := {}
	if is_instance_valid(_vis22d_panel):
		panel_state = Dictionary(_vis22d_panel.call("get_presentation_state")).duplicate(true)
	var lod := {}
	if _vis18r_renderer != null:
		lod = Dictionary(_vis18r_renderer.call("lod_summary")).duplicate(true)
	return {
		"success": _vis22d_active,
		"stage": VIS22D_STAGE,
		"mode": VIS22D_MODE,
		"active": _vis22d_active,
		"fork_generation": _vis22d_fork_generation,
		"generation": _vis22d_generation,
		"replicate_count": _vis22d_replicate_count,
		"selected_replicate": _vis22d_selected_replicate,
		"treatment_profile": _vis22d_treatment_profile,
		"treatment_intensity": _vis22d_treatment_intensity,
		"aggregate_series_hash": aggregate_hash,
		"aggregate_point_count": int(aggregate_summary.get("point_count", 0)),
		"aggregate_oldest_generation": int(aggregate_summary.get("oldest_generation", -1)),
		"aggregate_latest_generation": int(aggregate_summary.get("latest_generation", -1)),
		"selected_field_hash": _vis22d_last_selected_field_hash,
		"replicate_roots": _vis22d_pair_set.replicate_roots() if is_instance_valid(_vis22d_pair_set) else [],
		"common_oldest_cached_generation": _vis22d_pair_set.common_oldest_cached_generation() if is_instance_valid(_vis22d_pair_set) else -1,
		"visible_population_fields": 1 if _vis22d_active else 0,
		"control_data_only": _vis22d_active,
		"nonselected_treatments_data_only": _vis22d_active,
		"whole_field_ph5_rebuilds": _vis18r_ph5_rebuilds_during_turnover,
		"progressive_ph5_count": _vis19_detail_nodes.size(),
		"realtime_lod": lod,
		"panel_state": panel_state,
		"source_vis20_panel_hidden_after_fork": _vis22d_active and is_instance_valid(_vis20_experiment_panel) and not _vis20_experiment_panel.visible,
	}


func _vis22d_render_selected_generation() -> void:
	if not _vis22d_active or not is_instance_valid(_vis22d_pair_set) or _vis18r_renderer == null:
		return
	var generation_map: Dictionary = _vis22d_pair_set.treatment_generation_map(
		_vis22d_selected_replicate,
		_vis22d_generation
	)
	if generation_map.is_empty():
		return
	var render_summary: Dictionary = _vis18r_renderer.show_realtime_generation(
		self,
		_ph5_root,
		_vis22d_generation,
		generation_map
	)
	_vis18r_current_visual_count = int(render_summary.get("visual_count", 0))
	_vis18r_current_births = int(render_summary.get("birth_count", 0))
	_vis18r_current_deaths = int(render_summary.get("death_count", 0))
	_vis18r_current_survivors = int(render_summary.get("survivor_count", 0))
	_vis18r_represented_biomass_kg = float(render_summary.get("represented_biomass_kg", 0.0))
	_vis18r_turnover_hash = String(render_summary.get("turnover_hash", ""))
	var treatment = _vis22d_pair_set.treatment_runner(_vis22d_selected_replicate)
	var environment_revision := ""
	if treatment != null:
		environment_revision = String(treatment.sample_environment_for_generation(_vis22d_generation, 0.0, 0.0).get("environment_revision", ""))
	var experiment_id := VIS22D_ExperimentModel.PROFILE_BASELINE if _vis22d_generation <= _vis22d_fork_generation else _vis22d_treatment_profile
	var point := VIS22D_TraceAdapter.from_generation_map(
		_vis22d_generation,
		generation_map,
		VIS22D_TreatmentRunner.BRANCH_ID,
		experiment_id,
		environment_revision
	)
	_vis22d_last_selected_field_hash = String(point.get("field_hash", ""))
	_vis18r_field_hash = _vis22d_last_selected_field_hash


func _vis22d_create_panel_if_needed() -> void:
	if is_instance_valid(_vis22d_panel):
		return
	_vis22d_panel_layer = CanvasLayer.new()
	_vis22d_panel_layer.name = "VIS22DObservatoryLayer"
	_vis22d_panel_layer.layer = 24
	add_child(_vis22d_panel_layer)
	_vis22d_panel = VIS22D_ObservatoryPanel.new()
	_vis22d_panel.name = "ReplicatedCausalObservatory"
	_vis22d_panel.position = Vector2(840.0, 72.0)
	_vis22d_panel.size = Vector2(570.0, 410.0)
	_vis22d_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vis22d_panel_layer.add_child(_vis22d_panel)


func _vis22d_refresh_panel() -> void:
	if _vis22d_aggregate == null:
		return
	_vis22d_create_panel_if_needed()
	if is_instance_valid(_vis22d_panel):
		_vis22d_panel.call("set_observatory_data", _vis22d_aggregate.summary(), _vis22d_selected_replicate)


func _vis22d_release_pair_set_only() -> void:
	if is_instance_valid(_vis22d_pair_set):
		var pair_set: Node = _vis22d_pair_set
		_vis22d_pair_set = null
		pair_set.free()


func _vis22d_release_owned_state() -> void:
	_vis22d_release_pair_set_only()
	_vis22d_aggregate = null
	if is_instance_valid(_vis22d_panel_layer):
		var layer: CanvasLayer = _vis22d_panel_layer
		_vis22d_panel = null
		_vis22d_panel_layer = null
		layer.free()
	_vis22d_active = false
	_vis22d_fork_generation = -1
	_vis22d_generation = -1
	_vis22d_last_selected_field_hash = ""


func _update_vis18r_title() -> void:
	if not _vis22d_active:
		super._update_vis18r_title()
		var title_ready := get_node_or_null("HUD/Margin/Panel/VBox/Title") as Label
		if title_ready != null:
			title_ready.text = title_ready.text.replace("ECO.VIS2.1-V", VIS22D_STAGE).replace("ECO.VIS2.1", VIS22D_STAGE).replace("ECO.VIS2.0", VIS22D_STAGE)
		return
	var title := get_node_or_null("HUD/Margin/Panel/VBox/Title") as Label
	if title == null:
		return
	title.text = "%s — %s fork=G%d G%d — R%d/%d — %s %d%% — reps=%d" % [
		VIS22D_STAGE,
		"PLAY" if _vis18r_playing else "PAUSE",
		_vis22d_fork_generation,
		_vis22d_generation,
		_vis22d_selected_replicate,
		_vis22d_replicate_count,
		_vis22d_treatment_profile,
		int(round(_vis22d_treatment_intensity * 100.0)),
		_vis18r_current_visual_count,
	]


func _update_status() -> void:
	super._update_status()
	var status := get_node_or_null("HUD/Margin/Panel/VBox/Status") as Label
	if status == null:
		return
	if not _vis22d_active:
		status.text += "\nVIS2.2-D=READY replicates=%d | F creates replicated causal fork; only selected TREATMENT becomes visible." % _vis22d_replicate_count
		return
	var aggregate_hash := _vis22d_aggregate.series_hash() if _vis22d_aggregate != null else ""
	var lod := {}
	if _vis18r_renderer != null:
		lod = Dictionary(_vis18r_renderer.call("lod_summary"))
	status.text += "\nVIS2.2-D n=%d selected=R%d | aggregate=%s | visible_fields=1 | Control+nonselected Treatment=data-only" % [
		_vis22d_replicate_count,
		_vis22d_selected_replicate,
		aggregate_hash.left(10),
	]
	status.text += "\nLOD=%s near<=%.0fm mid=%.0f..%.0fm far>=%.0fm | [/] changes presentation only" % [
		"ACTIVE" if bool(lod.get("enabled", false)) else "READY",
		float(lod.get("near_lod_end_m", 110.0)),
		float(lod.get("mid_lod_begin_m", 75.0)),
		float(lod.get("mid_lod_end_m", 240.0)),
		float(lod.get("far_lod_begin_m", 190.0)),
	]

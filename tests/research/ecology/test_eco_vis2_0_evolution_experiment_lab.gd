extends SceneTree

const VIS20_FieldScript = preload("res://scripts/labs/ecology/eco_vis2_0_evolution_experiment_lab.gd")
const VIS20_Model = preload("res://scripts/labs/ecology/eco_vis2_0_experiment_model.gd")
const VIS20_PanelScript = preload("res://scripts/labs/ecology/eco_vis2_0_experiment_panel.gd")
const VIS20_EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const VIS20_Scene = preload("res://scenes/labs/ecology/eco_vis2_0_evolution_experiment_lab.tscn")

var _assertions := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := VIS20_Scene.instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame
	_check(scene.get_script() == VIS20_FieldScript, "VIS2.0 scene script attached")
	var snapshot_before: Dictionary = scene.get_spatial_snapshot()
	var snapshot_hash := String(snapshot_before.get("snapshot_hash", ""))
	_check(snapshot_hash.length() == 64, "canonical spatial snapshot available")
	var initial: Dictionary = scene.get_experiment_state()
	_check(String(initial.get("stage", "")) == "ECO.VIS2.0", "stage")
	_check(String(initial.get("profile", "")) == VIS20_Model.PROFILE_BASELINE, "initial experiment is baseline")
	_check(float(initial.get("intensity", -1.0)) == 0.0, "baseline intensity is zero")
	var experiment_panel := scene.get_node_or_null("VIS20ExperimentLayer/EvolutionExperiment") as Control
	_check(experiment_panel != null, "experiment panel exists")
	if experiment_panel != null:
		_check(experiment_panel.get_script() == VIS20_PanelScript, "experiment panel script attached")
		_check(experiment_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "experiment panel cannot steal spectator mouse")
	var baseline_probe: Dictionary = scene.get_experiment_probe(140.0, 85.0)
	var baseline_sample: Dictionary = baseline_probe.get("baseline", {})
	var initial_sample: Dictionary = baseline_probe.get("experimental", {})
	_check(bool(VIS20_EnvironmentSample.validate(baseline_sample).get("success", false)), "baseline probe valid")
	_check(String(baseline_sample.get("checksum", "")) == String(initial_sample.get("checksum", "")), "baseline profile preserves source EnvironmentSample")
	print("ECO.VIS2.0 smoke progress: baseline_checked")

	scene.set_experiment_profile(VIS20_Model.PROFILE_DROUGHT, 0.90)
	var drought_probe: Dictionary = scene.get_experiment_probe(140.0, 85.0)
	var drought_sample: Dictionary = drought_probe.get("experimental", {})
	_check(bool(VIS20_EnvironmentSample.validate(drought_sample).get("success", false)), "drought sample valid")
	_check(float(drought_sample.get("soil_moisture", 1.0)) < float(baseline_sample.get("soil_moisture", 0.0)), "drought reduces moisture")
	_check(float(drought_sample.get("flood_frequency", 1.0)) <= float(baseline_sample.get("flood_frequency", 0.0)), "drought reduces flood frequency")
	_check(float(drought_sample.get("temperature_c", 0.0)) > float(baseline_sample.get("temperature_c", 0.0)), "drought raises temperature")
	_check(String(drought_sample.get("checksum", "")) != String(baseline_sample.get("checksum", "")), "experiment produces distinct EnvironmentSample checksum")
	scene.set_realtime_turnover_generation(8)
	await process_frame
	var drought_hash: String = String(scene.get_population_field_hash())
	var drought_state: Dictionary = scene.get_realtime_turnover_state()
	_check(int(drought_state.get("max_simulated_generation", -1)) == 8, "drought trajectory reaches G8")
	_check(int(drought_state.get("ph5_rebuilds_during_turnover", -1)) == 0, "drought trajectory keeps whole-field PH5 rebuild disabled")
	print("ECO.VIS2.0 smoke progress: drought_checked")

	scene.set_realtime_turnover_generation(0)
	scene.set_experiment_profile(VIS20_Model.PROFILE_BASELINE, 0.0)
	scene.set_realtime_turnover_generation(8)
	await process_frame
	var baseline_hash: String = String(scene.get_population_field_hash())
	_check(baseline_hash.length() == 64, "baseline experiment field hash")
	_check(drought_hash != baseline_hash, "controlled drought changes population trajectory")

	scene.set_realtime_turnover_generation(0)
	scene.set_experiment_profile(VIS20_Model.PROFILE_DROUGHT, 0.90)
	scene.set_realtime_turnover_generation(8)
	await process_frame
	_check(scene.get_population_field_hash() == drought_hash, "same drought experiment replays deterministically from founders")
	print("ECO.VIS2.0 smoke progress: deterministic_replay_checked")

	scene.set_realtime_turnover_generation(14)
	scene.set_realtime_turnover_generation(10)
	var max_before_branch := int(scene.get_realtime_turnover_state().get("max_simulated_generation", -1))
	_check(max_before_branch >= 14, "future cache exists before experimental branch")
	scene.set_experiment_profile(VIS20_Model.PROFILE_FLOOD, 0.80)
	var branch_state: Dictionary = scene.get_experiment_state()
	_check(int(branch_state.get("branch_truncations", 0)) > 0, "changing experiment from rewind point truncates cached future")
	_check(int(scene.get_realtime_turnover_state().get("max_simulated_generation", -1)) == 10, "future cache truncated at intervention generation")
	var flood_probe: Dictionary = scene.get_experiment_probe(140.0, 85.0)
	var flood_sample: Dictionary = flood_probe.get("experimental", {})
	_check(float(flood_sample.get("soil_moisture", 0.0)) > float(baseline_sample.get("soil_moisture", 0.0)), "flood raises moisture")
	_check(float(flood_sample.get("flood_frequency", 0.0)) > float(baseline_sample.get("flood_frequency", 0.0)), "flood raises flood frequency")
	scene.set_realtime_turnover_generation(11)
	await process_frame
	_check(int(scene.get_realtime_turnover_state().get("max_simulated_generation", -1)) == 11, "branched flood trajectory continues from intervention point")
	_check(scene.get_experiment_events().size() > 0, "experiment event log populated")
	print("ECO.VIS2.0 smoke progress: branching_checked")

	var toggle_panel := InputEventKey.new()
	toggle_panel.keycode = KEY_I
	toggle_panel.pressed = true
	scene._unhandled_input(toggle_panel)
	_check(not bool(scene.get_experiment_state().get("panel_visible", true)), "I hides experiment panel")
	scene._unhandled_input(toggle_panel)
	_check(bool(scene.get_experiment_state().get("panel_visible", false)), "I restores experiment panel")
	var observatory: Dictionary = scene.get_observatory_state()
	_check(int(observatory.get("history_point_count", 0)) > 0, "VIS1.9 observatory remains active under experiment lab")
	var snapshot_after: Dictionary = scene.get_spatial_snapshot()
	_check(String(snapshot_after.get("snapshot_hash", "")) == snapshot_hash, "canonical VIS1.2 snapshot remains unchanged")
	print("ECO.VIS2.0 smoke progress: observability_checked")

	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	scene._unhandled_input(space)
	scene._process(0.02)
	_check(bool(scene.get_realtime_turnover_state().get("playing", false)), "Space keeps continuous playback available in experiment lab")
	_check(int(scene.get_realtime_turnover_state().get("ph5_rebuilds_during_turnover", -1)) == 0, "experiment playback never enables whole-field PH5 rebuild")
	print("ECO.VIS2.0 smoke progress: playback_checked")

	scene.queue_free()
	await process_frame
	print("ECO.VIS2.0 headless scene smoke: PASS (%d assertions)" % _assertions)
	quit(0)

func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		return
	push_error("ECO.VIS2.0 assertion failed: %s" % label)
	quit(1)

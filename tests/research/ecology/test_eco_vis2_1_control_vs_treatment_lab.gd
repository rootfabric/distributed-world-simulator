extends SceneTree

const TraceContract = preload("res://scripts/labs/ecology/eco_vis2_1_branch_trace_contract.gd")
const ComparisonModel = preload("res://scripts/labs/ecology/eco_vis2_1_comparison_model.gd")
const ExperimentModel = preload("res://scripts/labs/ecology/eco_vis2_0_experiment_model.gd")
const VIS21_Scene = preload("res://scenes/labs/ecology/eco_vis2_1_control_vs_treatment_lab.tscn")

const FORK_GENERATION := 20
const DIVERGENCE_HORIZON := 12
const LONG_SMOKE_GENERATION := 80

var _assertions := 0
var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := VIS21_Scene.instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame
	scene.set_realtime_turnover_generation(FORK_GENERATION)
	await process_frame
	var source_model := scene.get("_vis18r_model") as RefCounted
	_require(source_model != null, "source model available")
	if source_model == null:
		return
	var source_fork_map: Dictionary = Dictionary(source_model.call("generation_map", FORK_GENERATION)).duplicate(true)
	var source_fork_map_before := source_fork_map.duplicate(true)
	var canonical_environment_before: Dictionary = scene.get_spatial_snapshot().duplicate(true)
	var fork_result: Dictionary = scene.begin_paired_experiment()
	_require(bool(fork_result.get("success", false)), "paired fork configures")
	if not bool(fork_result.get("success", false)):
		return
	var state: Dictionary = scene.get_vis21_state()
	var control = scene.get_vis21_control_runner()
	var treatment = scene.get_vis21_treatment_runner()
	var traces: Dictionary = scene.get_vis21_canonical_traces()
	var control_trace: Array = traces.get("control", [])
	var treatment_trace: Array = traces.get("treatment", [])
	var fork_control: Dictionary = control_trace[0]
	var fork_treatment: Dictionary = treatment_trace[0]
	var fork_summary: Dictionary = scene.get_vis21_comparison_summary()
	var fork_pair: Dictionary = Dictionary(Array(fork_summary.get("points", []))[0])

	_check(not source_fork_map.is_empty() and int(state.get("fork_generation", -1)) == FORK_GENERATION, "01 fork map captured exactly once")
	_check(source_fork_map == source_fork_map_before and scene.get("_vis21_fork_map") == source_fork_map_before, "02 input fork map remains immutable")
	_check(control.generation_map(FORK_GENERATION) == source_fork_map_before, "03 CONTROL map at fork equals common map")
	_check(treatment.generation_map(FORK_GENERATION) == source_fork_map_before, "04 TREATMENT map at fork equals common map")
	_check(String(fork_control.get("field_hash", "")) == String(fork_treatment.get("field_hash", "")), "05 canonical fork field hashes equal")
	_check(String(fork_control.get("environment_revision", "")) == String(fork_treatment.get("environment_revision", "")), "06 fork environment revisions equal")
	_check(_all_numeric_deltas_zero(fork_pair), "07 all comparator deltas at fork are zero")
	var root := String(state.get("common_random_seed_hash", ""))
	_check(_is_lower_sha256(root), "08 CONTROL common root is 64 lower-case hex")
	_check(root == control.common_random_seed_hash() and root == treatment.common_random_seed_hash(), "09 TREATMENT common root exactly equals CONTROL root")
	var restart_result: Dictionary = scene.restart_paired_from_fork()
	_check(bool(restart_result.get("success", false)) and String(restart_result.get("common_random_seed_hash", "")) == root, "10 common root survives restart")
	var switch_at_fork: Dictionary = scene.set_treatment(ExperimentModel.PROFILE_DROUGHT, 1.0)
	_check(bool(switch_at_fork.get("success", false)) and treatment.common_random_seed_hash() == root and control.common_random_seed_hash() == root, "11 treatment switch does not alter common root")
	traces = scene.get_vis21_canonical_traces()
	fork_treatment = Dictionary(Array(traces.get("treatment", []))[0])
	_check(String(fork_treatment.get("experiment_id", "")) == ExperimentModel.PROFILE_BASELINE, "12 treatment at fork is BASELINE")
	var baseline_probe: Dictionary = control.baseline_environment_sample_at(0.0, 0.0)
	var treatment_fork_probe: Dictionary = treatment.sample_environment_for_generation(FORK_GENERATION, 0.0, 0.0)
	var treatment_next_probe: Dictionary = treatment.sample_environment_for_generation(FORK_GENERATION + 1, 0.0, 0.0)
	_check(String(treatment_fork_probe.get("checksum", "")) == String(baseline_probe.get("checksum", "")) and String(treatment_next_probe.get("checksum", "")) != String(baseline_probe.get("checksum", "")), "13 treatment forcing starts at N+1")
	scene.advance_paired_to(FORK_GENERATION + 1)
	traces = scene.get_vis21_canonical_traces()
	var c_n1: Dictionary = Dictionary(Array(traces.get("control", []))[-1])
	_check(String(c_n1.get("experiment_id", "")) == "BASELINE" and String(control.baseline_environment_sample_at(0.0, 0.0).get("checksum", "")) == String(baseline_probe.get("checksum", "")), "14 CONTROL remains BASELINE")
	_check(scene.get_spatial_snapshot() == canonical_environment_before, "15 canonical VIS1.2 environment remains untouched")
	var horizon_target := FORK_GENERATION + DIVERGENCE_HORIZON
	var horizon_result: Dictionary = scene.advance_paired_to(horizon_target)
	_require(bool(horizon_result.get("success", false)), "advance to causal horizon")
	if not bool(horizon_result.get("success", false)):
		return
	var horizon_summary: Dictionary = scene.get_vis21_comparison_summary()
	_check(_has_causal_divergence(Array(horizon_summary.get("points", [])), FORK_GENERATION), "16 strong DROUGHT produces measurable divergence by N+12")
	var first_replay_traces: Dictionary = scene.get_vis21_canonical_traces()
	var replay_control: Array = Array(first_replay_traces.get("control", [])).duplicate(true)
	var replay_treatment: Array = Array(first_replay_traces.get("treatment", [])).duplicate(true)
	scene.restart_paired_from_fork()
	scene.advance_paired_to(horizon_target)
	var second_replay_traces: Dictionary = scene.get_vis21_canonical_traces()
	_check(Array(second_replay_traces.get("control", [])) == replay_control and Array(second_replay_traces.get("treatment", [])) == replay_treatment, "17 same fork/root/experiment reproduces exact paired trace")
	var control_before_switch: Dictionary = control.generation_map(horizon_target)
	var treatment_before_switch: Dictionary = treatment.generation_map(horizon_target)
	var switch_result: Dictionary = scene.set_treatment(ExperimentModel.PROFILE_FLOOD, 1.0)
	var switched_target := horizon_target + 4
	scene.advance_paired_to(switched_target)
	var control_after_switch_prefix: Dictionary = control.generation_map(horizon_target)
	var treatment_after_switch: Dictionary = treatment.generation_map(switched_target)
	_check(bool(switch_result.get("success", false)) and control_after_switch_prefix == control_before_switch and treatment_after_switch != treatment_before_switch, "18 treatment switch changes treatment future and never CONTROL")
	traces = scene.get_vis21_canonical_traces()
	control_trace = traces.get("control", [])
	treatment_trace = traces.get("treatment", [])
	var latest_generation := int(Dictionary(control_trace[-1]).get("generation", -1))
	var latest_control_map: Dictionary = control.generation_map(latest_generation)
	var latest_treatment_map: Dictionary = treatment.generation_map(latest_generation)
	_check(String(Dictionary(control_trace[-1]).get("field_hash", "")) == TraceContract.compute_field_hash(latest_generation, latest_control_map) and String(Dictionary(treatment_trace[-1]).get("field_hash", "")) == TraceContract.compute_field_hash(latest_generation, latest_treatment_map), "19 both canonical sides use TraceContract.compute_field_hash")
	_check(typeof(Dictionary(control_trace[-1]).get("environment_revision")) == TYPE_STRING and typeof(Dictionary(treatment_trace[-1]).get("environment_revision")) == TYPE_STRING, "20 environment_revision is String on both sides")
	var integrated_compare: Dictionary = ComparisonModel.summarize(control_trace, treatment_trace, FORK_GENERATION, true)
	_check(bool(integrated_compare.get("success", false)), "21 Comparator accepts integrated canonical traces")
	var corrupted_hash_treatment := treatment_trace.duplicate(true)
	var corrupted_hash_point: Dictionary = Dictionary(corrupted_hash_treatment[0]).duplicate(true)
	corrupted_hash_point["field_hash"] = "corrupted-fork".sha256_text()
	corrupted_hash_treatment[0] = corrupted_hash_point
	_check(not bool(ComparisonModel.summarize(control_trace, corrupted_hash_treatment, FORK_GENERATION, true).get("success", true)), "22 Comparator rejects corrupted fork field hash")
	var corrupted_revision_treatment := treatment_trace.duplicate(true)
	var corrupted_revision_point: Dictionary = Dictionary(corrupted_revision_treatment[0]).duplicate(true)
	corrupted_revision_point["environment_revision"] = "CORRUPTED_ENV_REV"
	corrupted_revision_treatment[0] = corrupted_revision_point
	_check(not bool(ComparisonModel.summarize(control_trace, corrupted_revision_treatment, FORK_GENERATION, true).get("success", true)), "23 Comparator rejects corrupted fork environment revision")
	state = scene.get_vis21_state()
	_check(bool(state.get("control_data_only", false)) and int(state.get("progressive_ph5_count", -1)) == 0, "24 CONTROL does not create/render PH5 world")
	_check(int(state.get("visible_population_fields", 0)) == 1, "25 exactly one visible realtime population field exists")
	_check(int(state.get("whole_field_ph5_rebuilds", -1)) == 0, "26 whole-field PH5 turnover rebuild remains zero")
	var controls_label := scene.get("_controls_label") as Label
	_check(controls_label != null and "WASD move" in controls_label.text, "27 spectator WASD controls remain active")
	var panel := scene.get("_vis21_panel") as Control
	var camera := scene.get("_camera") as Camera3D
	var before_rotation := camera.rotation if camera != null else Vector3.ZERO
	var mouse_event := InputEventMouseMotion.new()
	mouse_event.relative = Vector2(12.0, -7.0)
	scene._unhandled_input(mouse_event)
	await process_frame
	var mouse_changed := camera != null and camera.rotation != before_rotation
	_check(mouse_changed or (controls_label != null and "mouse look" in controls_label.text), "28 spectator captured mouse-look remains operational with comparison panel")
	_check(panel != null and panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "29 comparison panel is MOUSE_FILTER_IGNORE")
	var before_generation := int(scene.get_vis21_state().get("paired_generation", -1))
	var playback_result: Dictionary = scene.advance_paired_to(before_generation + 1)
	_check(bool(playback_result.get("success", false)) and int(scene.get_vis21_state().get("paired_generation", -1)) == before_generation + 1 and camera != null, "30 paired playback advances without blocking camera/input")
	scene.queue_free()
	await process_frame

	var smoke := VIS21_Scene.instantiate()
	get_root().add_child(smoke)
	await process_frame
	await process_frame
	smoke.set_treatment(ExperimentModel.PROFILE_DROUGHT, 1.0)
	smoke.set_realtime_turnover_generation(FORK_GENERATION)
	await process_frame
	var smoke_nodes_at_fork := get_node_count()
	var smoke_fork: Dictionary = smoke.begin_paired_experiment()
	_require(bool(smoke_fork.get("success", false)), "long-smoke fork")
	if not bool(smoke_fork.get("success", false)):
		return
	var smoke_advance: Dictionary = smoke.advance_paired_to(LONG_SMOKE_GENERATION)
	_require(bool(smoke_advance.get("success", false)), "long smoke reaches G80")
	if not bool(smoke_advance.get("success", false)):
		return
	var smoke_state: Dictionary = smoke.get_vis21_state()
	var smoke_traces: Dictionary = smoke.get_vis21_canonical_traces()
	var smoke_control: Array = smoke_traces.get("control", [])
	var smoke_treatment: Array = smoke_traces.get("treatment", [])
	_check(smoke_control.size() <= 64 and smoke_treatment.size() <= 64 and String(smoke_state.get("common_random_seed_hash", "")) == String(smoke_fork.get("common_random_seed_hash", "")), "31 branch histories/caches remain bounded over G20..G80 and CRN root stays stable")
	_check(int(smoke_state.get("comparison_point_count", 0)) <= 64 and bool(smoke.get_vis21_comparison_summary().get("success", false)), "32 comparison series remains <=64 and valid")
	var smoke_nodes_at_end := get_node_count()
	_check(smoke_nodes_at_end <= smoke_nodes_at_fork + 512 and int(smoke_state.get("whole_field_ph5_rebuilds", -1)) == 0 and _biomass_contract_valid(smoke_control) and _biomass_contract_valid(smoke_treatment), "33 no unbounded SceneTree growth; no PH5 rebuild; canonical biomass stays valid")
	smoke.queue_free()
	await process_frame
	if _failures == 0 and _assertions == 33:
		print("ECO.VIS2.1 control-vs-treatment integration: PASS (33 assertions); long smoke G20..G80 PASS")
		quit(0)
	else:
		push_error("ECO.VIS2.1 integration: FAIL assertions=%d failures=%d" % [_assertions, _failures])
		quit(1)

func _all_numeric_deltas_zero(point: Dictionary) -> bool:
	return int(point.get("delta_population", 0)) == 0 and int(point.get("delta_deaths", 0)) == 0 and int(point.get("delta_survivors", 0)) == 0 and absf(float(point.get("delta_mean_fitness", 0.0))) <= 0.000000001 and int(point.get("delta_unique_genomes", 0)) == 0 and absf(float(point.get("delta_alpha_share", 0.0))) <= 0.000000001

func _has_causal_divergence(points: Array, fork_generation: int) -> bool:
	for point_variant in points:
		var point: Dictionary = point_variant
		var generation := int(point.get("generation", -1))
		if generation <= fork_generation or generation > fork_generation + DIVERGENCE_HORIZON:
			continue
		if int(point.get("delta_population", 0)) != 0 or int(point.get("delta_deaths", 0)) != 0 or int(point.get("delta_survivors", 0)) != 0 or absf(float(point.get("delta_mean_fitness", 0.0))) > 0.000000001 or int(point.get("delta_unique_genomes", 0)) != 0 or absf(float(point.get("delta_alpha_share", 0.0))) > 0.000000001:
			return true
	return false

func _is_lower_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return true

func _biomass_contract_valid(trace: Array) -> bool:
	if trace.is_empty():
		return false
	for point_variant in trace:
		var biomass := float(Dictionary(point_variant).get("represented_biomass_kg", -1.0))
		if not is_finite(biomass) or biomass < 0.0:
			return false
	return true

func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		return
	_failures += 1
	push_error("ECO.VIS2.1 assertion failed: %s" % label)

func _require(condition: bool, label: String) -> void:
	if condition:
		return
	push_error("ECO.VIS2.1 setup failure: %s" % label)
	quit(1)

extends SceneTree

const TraceContract = preload("res://scripts/labs/ecology/eco_vis2_1_branch_trace_contract.gd")
const ComparisonModel = preload("res://scripts/labs/ecology/eco_vis2_1_comparison_model.gd")
const ExperimentModel = preload("res://scripts/labs/ecology/eco_vis2_0_experiment_model.gd")
const VIS21Scene = preload("res://scenes/labs/ecology/eco_vis2_1_control_vs_treatment_lab.tscn")

const FORK := 20
const HORIZON := 32
const EVICT := 140
const LATER := 220
const WINDOW := 64

var _assertions := 0
var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene = VIS21Scene.instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame
	scene.set_realtime_turnover_generation(FORK)
	await process_frame
	var source = scene.get("_vis18r_model") as RefCounted
	_require(source != null, "source model")
	if source == null: return
	var fork_map: Dictionary = Dictionary(source.call("generation_map", FORK)).duplicate(true)
	var fork_before := fork_map.duplicate(true)
	var spatial_before: Dictionary = scene.get_spatial_snapshot().duplicate(true)
	var fork_result: Dictionary = scene.begin_paired_experiment()
	_require(bool(fork_result.get("success", false)), "fork")
	if not bool(fork_result.get("success", false)): return
	var c = scene.get_vis21_control_runner()
	var t = scene.get_vis21_treatment_runner()
	var state: Dictionary = scene.get_vis21_state()
	var traces: Dictionary = scene.get_vis21_canonical_traces()
	var ct: Array = traces.get("control", [])
	var tt: Array = traces.get("treatment", [])
	var summary: Dictionary = scene.get_vis21_comparison_summary()
	var fp: Dictionary = Dictionary(Array(summary.get("points", []))[0])

	_check(not fork_map.is_empty() and int(state.get("fork_generation", -1)) == FORK, "01 fork captured")
	_check(fork_map == fork_before and scene.get("_vis21_fork_map") == fork_before, "02 fork immutable")
	_check(c.generation_map(FORK) == fork_before, "03 control fork map")
	_check(t.generation_map(FORK) == fork_before, "04 treatment fork map")
	_check(String(Dictionary(ct[0]).get("field_hash", "")) == String(Dictionary(tt[0]).get("field_hash", "")), "05 fork hashes")
	_check(String(Dictionary(ct[0]).get("environment_revision", "")) == String(Dictionary(tt[0]).get("environment_revision", "")), "06 fork environment")
	_check(_zero(fp), "07 fork deltas")
	var root := String(state.get("common_random_seed_hash", ""))
	_check(_sha(root), "08 root format")
	_check(root == c.common_random_seed_hash() and root == t.common_random_seed_hash(), "09 common root")
	var restart: Dictionary = scene.restart_paired_from_fork()
	_check(bool(restart.get("success", false)) and String(restart.get("common_random_seed_hash", "")) == root, "10 restart root")
	var sw0: Dictionary = scene.set_treatment(ExperimentModel.PROFILE_DROUGHT, 1.0)
	_check(bool(sw0.get("success", false)) and c.common_random_seed_hash() == root and t.common_random_seed_hash() == root, "11 switch root")
	traces = scene.get_vis21_canonical_traces()
	_check(String(Dictionary(Array(traces.get("treatment", []))[0]).get("experiment_id", "")) == ExperimentModel.PROFILE_BASELINE, "12 fork baseline")
	var base: Dictionary = c.baseline_environment_sample_at(0.0, 0.0)
	var env_n: Dictionary = t.sample_environment_for_generation(FORK, 0.0, 0.0)
	var env_n1: Dictionary = t.sample_environment_for_generation(FORK + 1, 0.0, 0.0)
	_check(String(env_n.get("checksum", "")) == String(base.get("checksum", "")) and String(env_n1.get("checksum", "")) != String(base.get("checksum", "")), "13 intervention boundary")
	scene.advance_paired_to(FORK + 1)
	traces = scene.get_vis21_canonical_traces()
	_check(String(Dictionary(Array(traces.get("control", []))[-1]).get("experiment_id", "")) == ExperimentModel.PROFILE_BASELINE, "14 control baseline")
	_check(scene.get_spatial_snapshot() == spatial_before, "15 canonical environment untouched")
	_require(bool(scene.advance_paired_to(HORIZON).get("success", false)), "horizon")
	summary = scene.get_vis21_comparison_summary()
	_check(_diverged(Array(summary.get("points", []))), "16 divergence by N+12")
	var replay_a: Dictionary = scene.get_vis21_canonical_traces()
	scene.restart_paired_from_fork()
	scene.advance_paired_to(HORIZON)
	var replay_b: Dictionary = scene.get_vis21_canonical_traces()
	_check(replay_a == replay_b, "17 exact replay")
	var target := HORIZON + 4
	scene.advance_paired_to(target)
	var c_before: Dictionary = c.generation_map(target)
	var t_before: Dictionary = t.generation_map(target)
	scene.set_realtime_turnover_generation(HORIZON)
	var sw: Dictionary = scene.set_treatment(ExperimentModel.PROFILE_FLOOD, 1.0)
	scene.advance_paired_to(target)
	_check(bool(sw.get("success", false)) and c.generation_map(target) == c_before and t.generation_map(target) != t_before, "18 treatment-only future")
	traces = scene.get_vis21_canonical_traces()
	ct = traces.get("control", []); tt = traces.get("treatment", [])
	var g := int(Dictionary(ct[-1]).get("generation", -1))
	_check(String(Dictionary(ct[-1]).get("field_hash", "")) == TraceContract.compute_field_hash(g, c.generation_map(g)) and String(Dictionary(tt[-1]).get("field_hash", "")) == TraceContract.compute_field_hash(g, t.generation_map(g)), "19 canonical field hash")
	_check(typeof(Dictionary(ct[-1]).get("environment_revision")) == TYPE_STRING and typeof(Dictionary(tt[-1]).get("environment_revision")) == TYPE_STRING, "20 revisions are strings")
	_check(bool(ComparisonModel.summarize(ct, tt, FORK, true).get("success", false)), "21 comparator accepts")
	var bad_hash := tt.duplicate(true); var bh: Dictionary = Dictionary(bad_hash[0]).duplicate(true); bh["field_hash"] = "bad".sha256_text(); bad_hash[0] = bh
	_check(not bool(ComparisonModel.summarize(ct, bad_hash, FORK, true).get("success", true)), "22 bad fork hash rejected")
	var bad_env := tt.duplicate(true); var be: Dictionary = Dictionary(bad_env[0]).duplicate(true); be["environment_revision"] = "BAD"; bad_env[0] = be
	_check(not bool(ComparisonModel.summarize(ct, bad_env, FORK, true).get("success", true)), "23 bad fork env rejected")
	state = scene.get_vis21_state()
	_check(bool(state.get("control_data_only", false)) and int(state.get("progressive_ph5_count", -1)) == 0, "24 control data-only no PH5")
	_check(int(state.get("visible_population_fields", 0)) == 1, "25 one visible field")
	_check(int(state.get("whole_field_ph5_rebuilds", -1)) == 0, "26 no whole-field PH5")
	var controls := scene.get("_controls_label") as Label
	_check(controls != null and "WASD move" in controls.text, "27 WASD spectator controls")
	var panel := scene.get("_vis21_panel") as Control
	var camera := scene.get("_camera") as Camera3D
	_require(panel != null and camera != null, "panel/camera")
	if panel == null or camera == null: return
	scene._set_mouse_capture(true)
	var rb := camera.rotation
	var m := InputEventMouseMotion.new(); var p := panel.global_position + Vector2(24, 24); m.position = p; m.global_position = p; m.relative = Vector2(18, -11)
	get_root().push_input(m); await process_frame
	_check(camera.rotation != rb, "28 captured mouse rotates")
	_check(panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "29 panel ignores mouse")
	var pg := int(scene.get_vis21_state().get("paired_generation", -1))
	_check(bool(scene.advance_paired_to(pg + 1).get("success", false)) and int(scene.get_vis21_state().get("paired_generation", -1)) == pg + 1, "30 playback advances")
	scene._set_mouse_capture(false)
	rb = camera.rotation; m = InputEventMouseMotion.new(); m.position = p; m.global_position = p; m.relative = Vector2(-15, 9); get_root().push_input(m); await process_frame
	_check(camera.rotation == rb, "31 released mouse stable")
	state = scene.get_vis21_state()
	_check(int(state.get("comparison_point_count", 999)) <= WINDOW and int(state.get("comparison_rebuild_input_count", 999)) <= WINDOW, "32 comparison bounded")
	_check(bool(state.get("treatment_runner_in_tree", false)) and t.get_parent() == scene and t.name == "VIS21TreatmentDataRunner" and t.get_child_count() == 0, "33 treatment lifecycle/data-only")
	scene.queue_free(); await process_frame
	_require(not is_instance_valid(t), "treatment freed with scene")

	var smoke = VIS21Scene.instantiate(); get_root().add_child(smoke); await process_frame; await process_frame
	smoke.set_treatment(ExperimentModel.PROFILE_DROUGHT, 1.0); smoke.set_realtime_turnover_generation(FORK); await process_frame
	var nodes0 := get_node_count()
	var sf: Dictionary = smoke.begin_paired_experiment(); _require(bool(sf.get("success", false)), "smoke fork")
	if not bool(sf.get("success", false)): return
	var sc = smoke.get_vis21_control_runner(); var st = smoke.get_vis21_treatment_runner(); var sroot := String(sf.get("common_random_seed_hash", ""))
	smoke.advance_paired_to(HORIZON)
	var early: Dictionary = smoke.get_vis21_canonical_traces().duplicate(true)
	_require(bool(smoke.advance_paired_to(EVICT).get("success", false)), "G140")
	var s: Dictionary = smoke.get_vis21_state(); var trs: Dictionary = smoke.get_vis21_canonical_traces(); var sct: Array = trs.get("control", []); var stt: Array = trs.get("treatment", []); var oldest := EVICT - WINDOW + 1
	_check(int(s.get("control_cached_generation_count", 999)) <= WINDOW and int(s.get("treatment_cached_generation_count", 999)) <= WINDOW, "34 generation caches bounded")
	_check(int(s.get("control_cached_trace_point_count", 999)) <= WINDOW and int(s.get("treatment_cached_trace_point_count", 999)) <= WINDOW, "35 trace caches bounded")
	_check(int(s.get("control_oldest_cached_generation", -1)) == oldest and int(s.get("treatment_oldest_cached_generation", -1)) == oldest and oldest > FORK, "36 real eviction")
	_check(int(s.get("oldest_paired_rewind_generation", -1)) == oldest, "37 oldest paired rewind")
	_check(sc.generation_map(FORK) == smoke.get("_vis21_fork_map") and st.generation_map(FORK) == smoke.get("_vis21_fork_map"), "38 fork reconstructable")
	_check(sct.size() <= WINDOW and stt.size() <= WINDOW and int(s.get("comparison_rebuild_input_count", 999)) <= WINDOW, "39 O(window) comparison")
	_check(int(Dictionary(sct[0]).get("generation", -1)) == FORK and int(Dictionary(stt[0]).get("generation", -1)) == FORK, "40 fork permanently retained")
	_check(int(Dictionary(sct[-1]).get("generation", -1)) == EVICT and int(Dictionary(stt[-1]).get("generation", -1)) == EVICT, "41 latest G140")
	_check(String(s.get("common_random_seed_hash", "")) == sroot and sc.common_random_seed_hash() == sroot and st.common_random_seed_hash() == sroot, "42 CRN survives eviction")
	_check(int(s.get("comparison_point_count", 999)) <= WINDOW and bool(smoke.get_vis21_comparison_summary().get("success", false)), "43 comparator valid after eviction")
	_check(bool(s.get("control_data_only", false)) and int(s.get("visible_population_fields", 0)) == 1 and int(s.get("whole_field_ph5_rebuilds", -1)) == 0, "44 presentation architecture")
	_check(_biomass(sct) and _biomass(stt), "45 biomass at G140")
	smoke.set_realtime_turnover_generation(FORK)
	_check(int(smoke.get_vis21_state().get("paired_generation", -1)) == oldest, "46 rewind clamps")
	smoke.set_realtime_turnover_generation(120)
	var cf: Dictionary = sc.generation_map(EVICT); var tf: Dictionary = st.generation_map(EVICT)
	var csw: Dictionary = smoke.set_treatment(ExperimentModel.PROFILE_FLOOD, 1.0); s = smoke.get_vis21_state()
	_check(bool(csw.get("success", false)) and int(s.get("simulated_generation", -1)) == 120 and int(s.get("treatment_oldest_cached_generation", -1)) > FORK, "47 cached local branch")
	_check(not st.is_generation_cached(EVICT), "48 treatment future erased")
	_check(sc.generation_map(EVICT) == cf and sc.common_random_seed_hash() == sroot and st.common_random_seed_hash() == sroot, "49 control/root untouched")
	_require(bool(smoke.advance_paired_to(EVICT).get("success", false)), "rebranch G140")
	_check(sc.generation_map(EVICT) == cf and st.generation_map(EVICT) != tf, "50 treatment recomputed only")
	var rr: Dictionary = smoke.restart_paired_from_fork()
	_check(bool(rr.get("success", false)) and int(rr.get("generation", -1)) == FORK and String(rr.get("common_random_seed_hash", "")) == sroot, "51 restart after eviction")
	_require(bool(smoke.advance_paired_to(HORIZON).get("success", false)), "replay G32")
	_check(smoke.get_vis21_canonical_traces() == early, "52 replay after eviction exact")
	_require(bool(smoke.advance_paired_to(LATER).get("success", false)), "G220")
	s = smoke.get_vis21_state(); trs = smoke.get_vis21_canonical_traces(); sct = trs.get("control", []); stt = trs.get("treatment", [])
	_check(int(s.get("comparison_rebuild_input_count", 999)) <= WINDOW and int(s.get("comparison_point_count", 999)) <= WINDOW, "53 comparison bounded G220")
	_check(int(s.get("control_cached_generation_count", 999)) <= WINDOW and int(s.get("treatment_cached_generation_count", 999)) <= WINDOW and int(s.get("control_oldest_cached_generation", -1)) > FORK and int(s.get("treatment_oldest_cached_generation", -1)) > FORK, "54 caches bounded G220")
	_check(int(Dictionary(sct[0]).get("generation", -1)) == FORK and int(Dictionary(stt[0]).get("generation", -1)) == FORK and int(Dictionary(sct[-1]).get("generation", -1)) == LATER and get_node_count() <= nodes0 + 512, "55 fork/latest/node growth")
	_check(_biomass(sct) and _biomass(stt) and bool(s.get("control_data_only", false)) and int(s.get("visible_population_fields", 0)) == 1 and int(s.get("whole_field_ph5_rebuilds", -1)) == 0 and String(s.get("common_random_seed_hash", "")) == sroot, "56 long-run invariants")
	smoke.queue_free(); await process_frame
	if _failures == 0:
		print("ECO.VIS2.1 control-vs-treatment integration: PASS (%d assertions); long smoke G20..G220 with rolling eviction PASS" % _assertions)
		quit(0)
	else:
		push_error("ECO.VIS2.1 integration: FAIL assertions=%d failures=%d" % [_assertions, _failures]); quit(1)

func _zero(p: Dictionary) -> bool:
	return int(p.get("delta_population", 0)) == 0 and int(p.get("delta_deaths", 0)) == 0 and int(p.get("delta_survivors", 0)) == 0 and absf(float(p.get("delta_mean_fitness", 0.0))) <= 1e-9 and int(p.get("delta_unique_genomes", 0)) == 0 and absf(float(p.get("delta_alpha_share", 0.0))) <= 1e-9

func _diverged(points: Array) -> bool:
	for v in points:
		var p: Dictionary = v; var g := int(p.get("generation", -1))
		if g > FORK and g <= HORIZON and (int(p.get("delta_population", 0)) != 0 or int(p.get("delta_deaths", 0)) != 0 or int(p.get("delta_survivors", 0)) != 0 or absf(float(p.get("delta_mean_fitness", 0.0))) > 1e-9 or int(p.get("delta_unique_genomes", 0)) != 0 or absf(float(p.get("delta_alpha_share", 0.0))) > 1e-9): return true
	return false

func _sha(v: String) -> bool:
	if v.length() != 64: return false
	for i in range(v.length()):
		var c := v.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 97 and c <= 102)): return false
	return true

func _biomass(trace: Array) -> bool:
	if trace.is_empty(): return false
	for v in trace:
		var b := float(Dictionary(v).get("represented_biomass_kg", -1.0))
		if not is_finite(b) or b < 0.0: return false
	return true

func _check(ok: bool, label: String) -> void:
	_assertions += 1
	if not ok:
		_failures += 1; push_error("ECO.VIS2.1 assertion failed: %s" % label)

func _require(ok: bool, label: String) -> void:
	if not ok:
		push_error("ECO.VIS2.1 setup failure: %s" % label); quit(1)

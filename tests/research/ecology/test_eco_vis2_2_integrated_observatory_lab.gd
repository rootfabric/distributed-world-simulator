extends SceneTree

const VIS22DScene = preload("res://scenes/labs/ecology/eco_vis2_2_integrated_observatory_lab.tscn")
const ExperimentModel = preload("res://scripts/labs/ecology/eco_vis2_0_experiment_model.gd")

const FORK_GENERATION := 20
const TARGET_GENERATION := 34
const REPLICATES := 4

var _assertions := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene = VIS22DScene.instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame

	_check(bool(scene.call("set_replicate_count_for_next_fork", REPLICATES)), "test replicate count accepted")
	scene.call("set_realtime_turnover_generation", FORK_GENERATION)
	await process_frame

	var source_model = scene.get("_vis18r_model") as RefCounted
	_require(source_model != null, "canonical VIS2.0 source available")
	if source_model == null:
		_finish()
		return
	var source_fork_map: Dictionary = Dictionary(source_model.call("generation_map", FORK_GENERATION)).duplicate(true)
	var source_snapshot_before: Dictionary = scene.call("get_spatial_snapshot").duplicate(true)

	var begin_result: Dictionary = scene.call("begin_replicated_experiment")
	_require_result(begin_result, "replicated experiment begins")
	if _failures > 0:
		_finish()
		return

	var fork_state: Dictionary = scene.call("get_vis22d_state")
	_check(bool(fork_state.get("active", false)), "D active after fork")
	_check(String(fork_state.get("stage", "")) == "ECO.VIS2.2-D", "D stage identity")
	_check(int(fork_state.get("fork_generation", -1)) == FORK_GENERATION, "fork generation retained")
	_check(int(fork_state.get("generation", -1)) == FORK_GENERATION, "visible generation starts at fork")
	_check(int(fork_state.get("replicate_count", 0)) == REPLICATES, "replicate count")
	_check(int(fork_state.get("selected_replicate", -1)) == 0, "R0 initially selected")
	_check(int(fork_state.get("visible_population_fields", 0)) == 1, "exactly one visible population field")
	_check(bool(fork_state.get("control_data_only", false)), "all Controls data-only")
	_check(bool(fork_state.get("nonselected_treatments_data_only", false)), "nonselected Treatments data-only")
	_check(int(fork_state.get("progressive_ph5_count", -1)) == 0, "progressive PH5 absent")
	_check(int(fork_state.get("whole_field_ph5_rebuilds", -1)) == 0, "whole-field PH5 rebuild absent")
	_check(String(fork_state.get("aggregate_series_hash", "")).length() == 64, "fork aggregate hash")
	_check(int(fork_state.get("aggregate_point_count", 0)) == 1, "fork aggregate contains one point")
	_check(Array(fork_state.get("replicate_roots", [])).size() == REPLICATES, "all replicate roots exposed")
	_check(bool(fork_state.get("source_vis20_panel_hidden_after_fork", false)), "source VIS2.0 panel hidden")
	var fork_lod: Dictionary = fork_state.get("realtime_lod", {})
	_check(bool(fork_lod.get("enabled", false)), "realtime LOD enabled")
	_check(int(fork_lod.get("live_proxy_count", 0)) > 0, "selected Treatment has live proxies")
	_check(int(fork_lod.get("near_tier_count", -1)) == int(fork_lod.get("live_proxy_count", 0)), "near tier count matches proxies")
	_check(int(fork_lod.get("mid_tier_count", -1)) == int(fork_lod.get("live_proxy_count", 0)), "mid tier count matches proxies")
	_check(int(fork_lod.get("far_tier_count", -1)) == int(fork_lod.get("live_proxy_count", 0)), "far tier count matches proxies")

	var roots_before: Array = fork_state.get("replicate_roots", []).duplicate(true)
	var fork_aggregate_hash := String(fork_state.get("aggregate_series_hash", ""))
	var restart_fork_hash := fork_aggregate_hash
	_require_result(scene.call("advance_replicated_to", TARGET_GENERATION), "replicated experiment advances")
	if _failures > 0:
		_finish()
		return

	var advanced: Dictionary = scene.call("get_vis22d_state")
	_check(int(advanced.get("generation", -1)) == TARGET_GENERATION, "advanced generation visible")
	_check(int(advanced.get("aggregate_latest_generation", -1)) == TARGET_GENERATION, "aggregate latest generation")
	_check(int(advanced.get("aggregate_point_count", 0)) == TARGET_GENERATION - FORK_GENERATION + 1, "aggregate point count contiguous")
	_check(String(advanced.get("aggregate_series_hash", "")) != fork_aggregate_hash, "aggregate hash advances")
	_check(Array(advanced.get("replicate_roots", [])) == roots_before, "roots stable during advance")
	_check(source_fork_map == Dictionary(source_model.call("generation_map", FORK_GENERATION)), "canonical fork map remains immutable")
	_check(source_snapshot_before == scene.call("get_spatial_snapshot"), "canonical VIS2.0 source snapshot unchanged")

	var aggregate_before_selection := String(advanced.get("aggregate_series_hash", ""))
	var generation_before_selection := int(advanced.get("generation", -1))
	var field_r0 := String(advanced.get("selected_field_hash", ""))
	_require_result(scene.call("select_replicate", 3), "select R3")
	var r3: Dictionary = scene.call("get_vis22d_state")
	_check(int(r3.get("selected_replicate", -1)) == 3, "R3 selected")
	_check(String(r3.get("aggregate_series_hash", "")) == aggregate_before_selection, "R3 selection cannot mutate aggregate hash")
	_check(Array(r3.get("replicate_roots", [])) == roots_before, "R3 selection cannot mutate roots")
	_check(int(r3.get("generation", -1)) == generation_before_selection, "R3 selection cannot mutate generation")
	_check(String(r3.get("selected_field_hash", "")).length() == 64, "R3 selected field hash available")
	var panel_r3: Dictionary = r3.get("panel_state", {})
	_check(int(panel_r3.get("selected_replicate", -1)) == 3, "panel tracks R3")
	_check(String(panel_r3.get("aggregate_series_hash", "")) == aggregate_before_selection, "panel sees same aggregate hash")

	_require_result(scene.call("select_replicate", 1), "select R1")
	var r1: Dictionary = scene.call("get_vis22d_state")
	_check(int(r1.get("selected_replicate", -1)) == 1, "R1 selected")
	_check(String(r1.get("aggregate_series_hash", "")) == aggregate_before_selection, "R1 selection cannot mutate aggregate hash")
	_check(Array(r1.get("replicate_roots", [])) == roots_before, "R1 selection cannot mutate roots")
	_check(int(r1.get("visible_population_fields", 0)) == 1, "selection still renders one population field")
	_check(String(r1.get("selected_field_hash", "")).length() == 64, "R1 selected field hash available")
	_check(field_r0.length() == 64, "R0 selected field hash available")

	var treatment_switch: Dictionary = scene.call("set_replicated_treatment", ExperimentModel.PROFILE_FLOOD, 1.0)
	_require_result(treatment_switch, "Treatment switches to FLOOD")
	_require_result(scene.call("advance_replicated_to", TARGET_GENERATION + 5), "FLOOD generations advance")
	var flooded: Dictionary = scene.call("get_vis22d_state")
	_check(String(flooded.get("treatment_profile", "")) == ExperimentModel.PROFILE_FLOOD, "D reports FLOOD")
	_check(int(flooded.get("aggregate_latest_generation", -1)) == TARGET_GENERATION + 5, "FLOOD aggregate advances")
	_check(Array(flooded.get("replicate_roots", [])) == roots_before, "Treatment switch preserves roots")
	_check(int(flooded.get("visible_population_fields", 0)) == 1, "FLOOD still one visible world")

	_require_result(scene.call("restart_replicated_from_fork"), "replicated experiment restarts")
	var restarted: Dictionary = scene.call("get_vis22d_state")
	_check(int(restarted.get("generation", -1)) == FORK_GENERATION, "restart returns to fork")
	_check(int(restarted.get("aggregate_point_count", 0)) == 1, "restart aggregate contains fork only")
	_check(Array(restarted.get("replicate_roots", [])) == roots_before, "restart preserves replicate roots")
	_check(String(restarted.get("aggregate_series_hash", "")) == restart_fork_hash, "restart reproduces deterministic fork aggregate hash")
	_check(int(restarted.get("selected_replicate", -1)) == 1, "restart preserves presentation selection")
	_check(int(restarted.get("visible_population_fields", 0)) == 1, "restart still one visible field")

	var pair_set_ref: Node = scene.get_node_or_null("VIS22DReplicatePairSet")
	var panel_ref: Node = scene.get_node_or_null("VIS22DObservatoryLayer/ReplicatedCausalObservatory")
	_check(is_instance_valid(pair_set_ref), "PairSet is owned by D scene")
	_check(is_instance_valid(panel_ref), "Observatory panel is owned by D scene")

	scene.free()
	await process_frame
	await process_frame
	_check(not is_instance_valid(pair_set_ref), "PairSet freed with D scene")
	_check(not is_instance_valid(panel_ref), "Observatory panel freed with D scene")
	_finish()


func _require_result(result: Dictionary, label: String) -> void:
	var success := bool(result.get("success", false))
	_check(success, "%s%s" % [label, "" if success else " -> %s" % var_to_str(result)])
	if not success:
		quit(1)


func _require(condition: bool, label: String) -> void:
	_check(condition, label)
	if not condition:
		quit(1)


func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		return
	_failures += 1
	push_error("ECO.VIS2.2-D assertion failed: %s" % label)


func _finish() -> void:
	if _failures == 0:
		print("ECO.VIS2.2-D integrated observatory lab: PASS (%d assertions)" % _assertions)
		quit(0)
	else:
		push_error("ECO.VIS2.2-D integrated observatory lab: FAIL (%d failures / %d assertions)" % [_failures, _assertions])
		quit(1)

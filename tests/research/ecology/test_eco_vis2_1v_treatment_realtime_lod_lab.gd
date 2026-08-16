extends SceneTree

const ExperimentModel = preload("res://scripts/labs/ecology/eco_vis2_0_experiment_model.gd")
const LODRenderer = preload("res://scripts/labs/ecology/eco_vis2_1v_realtime_lod_renderer.gd")
const VIS21VScene = preload("res://scenes/labs/ecology/eco_vis2_1v_treatment_realtime_lod_lab.tscn")

const FORK := 20
const TARGET := 32
const EPS := 0.000001

var _assertions := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene = VIS21VScene.instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame

	var renderer = scene.get("_vis18r_renderer") as RefCounted
	_check(renderer != null and renderer.get_script() == LODRenderer, "custom realtime LOD renderer installed")
	_check(String(scene.get_vis21v_state().get("stage", "")) == "ECO.VIS2.1-V", "VIS2.1-V stage")

	var treatment_result: Dictionary = scene.set_treatment(ExperimentModel.PROFILE_DROUGHT, 1.0)
	_check(bool(treatment_result.get("success", false)), "pre-fork Treatment selected")
	scene.set_realtime_turnover_generation(FORK)
	await process_frame
	var fork_result: Dictionary = scene.begin_paired_experiment()
	_require(bool(fork_result.get("success", false)), "paired fork")
	if not bool(fork_result.get("success", false)):
		return
	_check(bool(scene.get_vis21v_state().get("source_vis20_panel_hidden_after_fork", false)), "legacy VIS2.0 source panel hidden after fork")

	_require(bool(scene.advance_paired_to(FORK + 1).get("success", false)), "first paired generation")
	await process_frame
	var state: Dictionary = scene.get_vis21v_state()
	var lod: Dictionary = state.get("realtime_lod", {})
	_check(bool(lod.get("enabled", false)), "realtime LOD enabled")
	_check(absf(float(lod.get("near_lod_end_m", 0.0)) - 110.0) <= EPS, "near threshold")
	_check(absf(float(lod.get("mid_lod_begin_m", 0.0)) - 75.0) <= EPS and absf(float(lod.get("mid_lod_end_m", 0.0)) - 240.0) <= EPS, "mid thresholds")
	_check(absf(float(lod.get("far_lod_begin_m", 0.0)) - 190.0) <= EPS, "far threshold")
	var live := int(lod.get("live_proxy_count", 0))
	_check(live > 0, "live Treatment proxies")
	_check(int(lod.get("near_tier_count", -1)) == live and int(lod.get("mid_tier_count", -1)) == live and int(lod.get("far_tier_count", -1)) == live, "three LOD tiers per live proxy")

	var nodes_by_id: Dictionary = renderer.get("nodes_by_id")
	_require(not nodes_by_id.is_empty(), "renderer proxy registry")
	if nodes_by_id.is_empty():
		return
	var sample := nodes_by_id.values()[0] as Node3D
	_require(is_instance_valid(sample), "sample Treatment proxy")
	if not is_instance_valid(sample):
		return
	var trunk := sample.get_node_or_null("Trunk") as GeometryInstance3D
	var canopy := sample.get_node_or_null("Canopy") as GeometryInstance3D
	var mid := sample.get_node_or_null("MidCanopy") as GeometryInstance3D
	var far := sample.get_node_or_null("FarCanopy") as GeometryInstance3D
	_check(trunk != null and canopy != null and mid != null and far != null, "near/mid/far geometry exists")
	if trunk != null and canopy != null and mid != null and far != null:
		_check(absf(trunk.visibility_range_end - 110.0) <= EPS and absf(canopy.visibility_range_end - 110.0) <= EPS, "near geometry range")
		_check(absf(mid.visibility_range_begin - 75.0) <= EPS and absf(mid.visibility_range_end - 240.0) <= EPS, "mid geometry range")
		_check(absf(far.visibility_range_begin - 190.0) <= EPS, "far geometry range")
		_check(String(trunk.get_meta("realtime_lod_tier", "")) == "NEAR" and String(mid.get_meta("realtime_lod_tier", "")) == "MID" and String(far.get_meta("realtime_lod_tier", "")) == "FAR", "tier metadata")
	_check(bool(sample.get_meta("vis21v_realtime_lod", false)), "proxy marked realtime LOD")

	var traces_before: Dictionary = scene.get_vis21_canonical_traces()
	var camera := scene.get("_camera") as Camera3D
	_require(camera != null, "spectator camera")
	if camera == null:
		return
	var position_before := camera.global_position
	camera.global_position = sample.global_position + Vector3(0.0, 8.0, 25.0)
	await process_frame
	camera.global_position = sample.global_position + Vector3(0.0, 25.0, 150.0)
	await process_frame
	camera.global_position = sample.global_position + Vector3(0.0, 55.0, 320.0)
	await process_frame
	_check(scene.get_vis21_canonical_traces() == traces_before, "camera-driven LOD never mutates simulation traces")
	camera.global_position = position_before

	_require(bool(scene.advance_paired_to(TARGET).get("success", false)), "paired progression with realtime LOD")
	state = scene.get_vis21v_state()
	lod = state.get("realtime_lod", {})
	_check(int(state.get("paired_generation", -1)) == TARGET, "paired generation reaches target")
	_check(bool(state.get("control_data_only", false)) and int(state.get("visible_population_fields", 0)) == 1, "CONTROL remains data-only and one world rendered")
	_check(int(state.get("whole_field_ph5_rebuilds", -1)) == 0 and int(state.get("progressive_ph5_count", -1)) == 0, "no whole-field/progressive PH5 after fork")
	_check(int(lod.get("live_proxy_count", 0)) == int(lod.get("mid_tier_count", -1)) and int(lod.get("live_proxy_count", 0)) == int(lod.get("far_tier_count", -1)), "LOD tiers track turnover proxy population")
	_check(String(state.get("common_random_seed_hash", "")).length() == 64, "causal CRN retained")

	# The renderer is RefCounted and owns its mesh/material resources. This smoke keeps
	# an explicit local renderer reference for introspection, so release that final
	# reference before quit; otherwise Godot correctly reports the renderer resources
	# as still in use even though the scene itself has already been queue_free()'d.
	if renderer != null:
		renderer.call("clear_preview")
	await process_frame
	scene.queue_free()
	await process_frame
	renderer = null
	nodes_by_id.clear()
	await process_frame
	if _failures == 0:
		print("ECO.VIS2.1-V Treatment realtime LOD: PASS (%d assertions)" % _assertions)
		quit(0)
	else:
		push_error("ECO.VIS2.1-V Treatment realtime LOD: FAIL assertions=%d failures=%d" % [_assertions, _failures])
		quit(1)


func _check(ok: bool, label: String) -> void:
	_assertions += 1
	if not ok:
		_failures += 1
		push_error("ECO.VIS2.1-V assertion failed: %s" % label)


func _require(ok: bool, label: String) -> void:
	if not ok:
		push_error("ECO.VIS2.1-V setup failure: %s" % label)
		quit(1)

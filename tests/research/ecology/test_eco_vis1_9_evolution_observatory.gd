extends SceneTree

const ObservatoryFieldScript = preload("res://scripts/labs/ecology/eco_vis1_9_evolution_observatory.gd")
const ObservatoryPanelScript = preload("res://scripts/labs/ecology/eco_vis1_9_observatory_panel.gd")
const ObservatoryModel = preload("res://scripts/labs/ecology/eco_vis1_9_observatory_model.gd")
const ObservatoryScene = preload("res://scenes/labs/ecology/eco_vis1_9_evolution_observatory.tscn")

var _assertions := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := ObservatoryScene.instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame
	_check(scene.get_script() == ObservatoryFieldScript, "VIS1.9 scene script attached")
	var initial: Dictionary = scene.get_observatory_state()
	_check(String(initial.get("stage", "")) == "ECO.VIS1.9", "stage")
	_check(String(initial.get("mode", "")) == "EVOLUTION_OBSERVATORY_PROGRESSIVE_DETAIL", "mode")
	_check(int(initial.get("whole_field_ph5_rebuilds", -1)) == 0, "whole-field PH5 rebuild counter stays zero")
	var panel := scene.get_node_or_null("VIS19ObservatoryLayer/EvolutionObservatory") as Control
	_check(panel != null, "observatory panel exists")
	if panel != null:
		_check(panel.get_script() == ObservatoryPanelScript, "observatory panel script attached")
		_check(panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "observatory panel cannot steal spectator mouse")
	print("ECO.VIS1.9 smoke progress: initial_observatory_checked")

	scene.set_realtime_turnover_generation(20)
	await process_frame
	var summary: Dictionary = scene.get_observatory_summary()
	_check(int(summary.get("point_count", 0)) >= 20, "history contains long-running evolution points")
	_check(String(summary.get("history_hash", "")).length() == 64, "history hash")
	var selected: Dictionary = summary.get("selected", {})
	_check(int(selected.get("generation", -1)) == 20, "live selected generation follows current generation")
	var ranges: Dictionary = summary.get("ranges", {})
	for key in ["visual_count", "turnover", "mean_fitness", "unique_genomes", "composition"]:
		_check(ranges.has(key), "observatory range %s" % key)
	var repeat_summary := ObservatoryModel.summarize(scene.get_continuous_history(), 20)
	_check(String(repeat_summary.get("history_hash", "")) == String(summary.get("history_hash", "")), "observatory history deterministic")
	print("ECO.VIS1.9 smoke progress: history_checked")

	for _index in range(3):
		scene._process(0.20)
		await process_frame
	var paused_state: Dictionary = scene.get_observatory_state()
	_check(int(paused_state.get("progressive_detail_count", 0)) > 0, "paused mode builds progressive PH5 detail")
	_check(int(paused_state.get("progressive_detail_count", 0)) <= int(paused_state.get("progressive_detail_limit", 0)), "progressive PH5 detail stays bounded")
	_check(int(paused_state.get("whole_field_ph5_rebuilds", -1)) == 0, "progressive detail never triggers whole-field PH5 rebuild")
	var detail_root := scene.get_node_or_null("SpatialEcologyProjection/VIS19ProgressivePH5Detail") as Node3D
	_check(detail_root != null, "progressive PH5 detail root exists")
	if detail_root != null and detail_root.get_child_count() > 0:
		var detail := detail_root.get_child(0) as Node3D
		_check(bool(detail.get_meta("vis19_progressive_ph5", false)), "progressive detail tagged as PH5")
		_check(String(detail.get_meta("geometry_hash", "")).length() == 64, "progressive PH5 geometry hash")
	print("ECO.VIS1.9 smoke progress: progressive_detail_checked")

	var page_up := InputEventKey.new()
	page_up.keycode = KEY_PAGEUP
	page_up.pressed = true
	scene._unhandled_input(page_up)
	var inspected: Dictionary = scene.get_observatory_state()
	_check(not bool(inspected.get("follow_live", true)), "PageUp leaves live-follow mode")
	_check(int(inspected.get("selected_generation", 999999)) < 20, "PageUp selects older generation")

	var toggle := InputEventKey.new()
	toggle.keycode = KEY_O
	toggle.pressed = true
	scene._unhandled_input(toggle)
	_check(not bool(scene.get_observatory_state().get("visible", true)), "O hides observatory")
	scene._unhandled_input(toggle)
	_check(bool(scene.get_observatory_state().get("visible", false)), "O restores observatory")
	print("ECO.VIS1.9 smoke progress: inspection_controls_checked")

	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	scene._unhandled_input(space)
	scene._process(0.02)
	var playing: Dictionary = scene.get_realtime_turnover_state()
	_check(bool(playing.get("playing", false)), "Space enables playback")
	_check(int(scene.get_observatory_state().get("progressive_detail_count", -1)) == 0, "playback clears progressive PH5 detail")
	_check(int(playing.get("ph5_rebuilds_during_turnover", -1)) == 0, "playback still avoids whole-field PH5 rebuild")
	print("ECO.VIS1.9 smoke progress: playback_checked")

	scene.queue_free()
	await process_frame
	print("ECO.VIS1.9 headless scene smoke: PASS (%d assertions)" % _assertions)
	quit(0)

func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		return
	push_error("ECO.VIS1.9 assertion failed: %s" % label)
	quit(1)

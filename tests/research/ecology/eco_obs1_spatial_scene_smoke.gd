extends SceneTree

const SCENE := preload("res://scenes/labs/ecology/eco_obs1_spatial_observer_lab.tscn")
const Snapshot = preload("res://scripts/research/ecology/eco_obs1_spatial_snapshot_v1.gd")

var assertion_count := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var lab = SCENE.instantiate()
	root.add_child(lab)
	await process_frame
	var failure := _assert(not lab.timeline.is_empty(), "scene creates spatial timeline")
	if not failure.is_empty(): return _fail(failure)
	var initial: Dictionary = lab.current_snapshot()
	failure = _assert(bool(Snapshot.validate(initial).get("success", false)), "initial spatial scene snapshot validates")
	if not failure.is_empty(): return _fail(failure)
	var source_hash: String = lab.current_source_hash()
	failure = _assert(source_hash == String(initial["source_result_hash"]), "scene exposes exact P3.3 source hash")
	if not failure.is_empty(): return _fail(failure)
	failure = _assert(lab.patches_root.get_child_count() == int(Array(initial["patches"]).size()), "scene patch proxies match snapshot patches")
	if not failure.is_empty(): return _fail(failure)
	failure = _assert(lab.flows_root.get_child_count() == int(Array(initial["edges"]).size()), "scene flow proxies match snapshot edges")
	if not failure.is_empty(): return _fail(failure)
	failure = _assert(lab.title_label.text.contains("Spatial Ecology Observer"), "scene displays spatial observer title")
	if not failure.is_empty(): return _fail(failure)
	lab.step_forward()
	await process_frame
	failure = _assert(lab.current_frame_index() == 1, "Step changes observer frame index")
	if not failure.is_empty(): return _fail(failure)
	failure = _assert(lab.current_source_hash() != source_hash, "Step selects next immutable P3.3 snapshot")
	if not failure.is_empty(): return _fail(failure)
	failure = _assert(float(lab.current_snapshot()["dispersal_fraction"]) > 0.0, "Step exposes higher dispersal fixture")
	if not failure.is_empty(): return _fail(failure)
	lab.play()
	failure = _assert(lab.is_playing(), "Play toggles spatial observer playback")
	if not failure.is_empty(): return _fail(failure)
	lab.pause()
	failure = _assert(not lab.is_playing(), "Pause toggles spatial observer playback")
	if not failure.is_empty(): return _fail(failure)
	var current: Dictionary = lab.current_snapshot()
	current["total_final_biomass_kg"] = 9999.0
	failure = _assert(float(lab.current_snapshot()["total_final_biomass_kg"]) != 9999.0, "current_snapshot returns defensive copy")
	if not failure.is_empty(): return _fail(failure)
	print("ECO.OBS1.2 Spatial Scene Smoke: PASS (%d assertions)" % assertion_count)
	print("initial_source_hash=%s" % source_hash)
	quit(0)

func _assert(condition: bool, message: String) -> String:
	assertion_count += 1
	return "" if condition else "ASSERTION FAILED: " + message

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

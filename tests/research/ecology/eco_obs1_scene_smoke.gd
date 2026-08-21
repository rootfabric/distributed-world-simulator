extends SceneTree

const SCENE := preload("res://scenes/labs/ecology/eco_obs1_patch_observer_lab.tscn")
const Snapshot = preload("res://scripts/research/ecology/eco_obs1_snapshot_v1.gd")

var assertion_count := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var lab = SCENE.instantiate()
	root.add_child(lab)
	await process_frame
	var failure := _assert(not lab.timeline.is_empty(), "scene creates timeline")
	if not failure.is_empty(): return _fail(failure)
	var initial: Dictionary = lab.current_snapshot()
	failure = _assert(bool(Snapshot.validate(initial).get("success", false)), "initial scene snapshot validates")
	if not failure.is_empty(): return _fail(failure)
	var source_hash: String = lab.current_source_hash()
	failure = _assert(source_hash == String(initial["source_result_hash"]), "scene exposes exact source hash")
	if not failure.is_empty(): return _fail(failure)
	failure = _assert(lab.plants_root.get_child_count() == int(initial["active_plant_count"]), "low-poly proxies match active plants")
	if not failure.is_empty(): return _fail(failure)
	lab.step_forward()
	await process_frame
	failure = _assert(lab.current_frame_index() == 1, "Step changes only observer frame index")
	if not failure.is_empty(): return _fail(failure)
	failure = _assert(lab.current_source_hash() != source_hash, "Step selects the next immutable source snapshot")
	if not failure.is_empty(): return _fail(failure)
	lab.play()
	failure = _assert(lab.is_playing(), "Play toggles observer playback")
	if not failure.is_empty(): return _fail(failure)
	lab.pause()
	failure = _assert(not lab.is_playing(), "Pause toggles observer playback")
	if not failure.is_empty(): return _fail(failure)
	var current: Dictionary = lab.current_snapshot()
	current["total_biomass_kg"] = 9999.0
	failure = _assert(float(lab.current_snapshot()["total_biomass_kg"]) != 9999.0, "current_snapshot returns defensive copy")
	if not failure.is_empty(): return _fail(failure)
	print("ECO.OBS1 Scene Smoke: PASS (%d assertions)" % assertion_count)
	print("initial_source_hash=%s" % source_hash)
	quit(0)

func _assert(condition: bool, message: String) -> String:
	assertion_count += 1
	return "" if condition else "ASSERTION FAILED: " + message

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

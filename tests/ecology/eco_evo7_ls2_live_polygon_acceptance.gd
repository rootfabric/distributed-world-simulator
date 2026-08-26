extends SceneTree

const PolygonScene = preload("res://scenes/labs/ecology/eco_evo7_live_ecology_polygon.tscn")
var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var lab = PolygonScene.instantiate()
	root.add_child(lab)
	await process_frame
	await process_frame
	_check(bool(lab.get("ready_success")), "LS2 polygon initializes from real Earth + LS1")
	if not bool(lab.get("ready_success")):
		_finish(); return

	var snapshot: Dictionary = lab.get_snapshot()
	_check(int(snapshot.get("generation", -1)) == 0, "polygon starts at generation zero")
	_check(Array(snapshot.get("zones", [])).size() == 3, "polygon exposes exactly three live zones")
	_check(int(snapshot.get("population_size", 0)) == 12, "polygon displays twelve LS1 plants per zone")
	_check(int(lab.get_visual_plant_count()) == 36, "polygon materializes 36 plants")
	for key in ["world_write", "ecology_write", "persistence_write", "network_replication_write", "xfer_authority", "alternate_mutation_authority"]:
		_check(not bool(Dictionary(snapshot.get("authorities", {})).get(key, true)), "polygon inherited LS1 fail-closed authority %s" % key)

	for button_name in ["StartPauseButton", "Step1Button", "Step10Button", "Step100Button", "ResetSameSeedButton", "EvolutionToggleButton"]:
		_check(lab.find_child(button_name, true, false) is Button, "polygon has control button %s" % button_name)
	var hud = lab.find_child("PolygonHUD", true, false)
	_check(hud is Label, "polygon has HUD")
	if hud is Label:
		var text := String(hud.text).to_lower()
		for token in ["generation", "moisture", "sunlight", "water_sat", "fitness", "lai", "root_m", "dominant_lineage"]:
			_check(text.contains(token), "HUD exposes %s" % token)

	var earth_before: Dictionary = lab.get_live_earth_sample()
	_check(lab.step_now(1), "+1 generation executes synchronously for test")
	var gen1: Dictionary = lab.get_snapshot()
	_check(int(gen1.get("generation", -1)) == 1, "+1 changes generation 0 -> 1")
	_check(int(lab.get_visual_plant_count()) == 36, "visual materializer rebuild keeps 36 plants")

	lab.set_evolution_enabled(false)
	var off_before: Dictionary = lab.get_snapshot()
	_check(not bool(off_before.get("evolution_enabled", true)), "Evolution ON/OFF control disables evolution")
	_check(lab.step_now(1), "evolution-off observation step executes")
	var off_after: Dictionary = lab.get_snapshot()
	for zone_index in 3:
		_check(String(off_before["zones"][zone_index]["population_hash"]) == String(off_after["zones"][zone_index]["population_hash"]), "evolution OFF freezes zone %d heritable population" % zone_index)

	lab.reset_same_seed()
	var reset: Dictionary = lab.get_snapshot()
	_check(int(reset.get("generation", -1)) == 0, "Reset same seed returns generation zero")
	_check(bool(reset.get("evolution_enabled", false)), "Reset same seed restores evolution ON")
	_check(int(lab.get_visual_plant_count()) == 36, "reset rematerializes 36 plants")

	lab.queue_generations(100)
	_check(int(lab.get_pending_generations()) == 100, "+100 queues exactly 100 generations without blocking UI")
	lab.clear_pending_generations()
	_check(int(lab.get_pending_generations()) == 0, "pending generation queue can be cleared")
	lab.set_running(true)
	_check(bool(lab.is_running()), "Start button state enables continuous evolution")
	lab.set_running(false)
	_check(not bool(lab.is_running()), "Pause button state stops continuous evolution")

	var denied: Dictionary = lab.request_authoritative_write("world", {"attempt": true})
	_check(not bool(denied.get("success", true)) and String(denied.get("error_code", "")) == "ECO_SHADOW_WRITE_FORBIDDEN", "polygon authoritative write fails closed")
	var earth_after: Dictionary = lab.get_live_earth_sample()
	_check(earth_after == earth_before, "polygon/session leave production Earth pipeline sample unchanged")
	_source_guard()
	lab.queue_free()
	_finish()

func _source_guard() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_live_ecology_polygon.gd").to_lower()
	_check(source.contains("procedural_earth_world.gd"), "LS2 imports real ProceduralEarthWorld")
	_check(source.contains("eco_evo7_live_shadow_evolution_session_v1.gd"), "LS2 consumes LS1 session")
	_check(not source.contains("reproduce_bundle("), "LS2 presentation adds no mutation call site")
	_check(not source.contains("fileaccess."), "LS2 presentation has no file/persistence access")
	_check(not source.contains("diraccess."), "LS2 presentation has no directory/persistence access")
	_check(not source.contains("multiplayer"), "LS2 presentation activates no network path")
	_check(source.contains("+100 generations"), "LS2 exposes +100 generation control")
	_check(source.contains("evolution: on"), "LS2 exposes evolution toggle")

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO7 LS2 Live Ecology Polygon: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 LS2 FAIL: %s" % failure)
	print("ECO.EVO7 LS2 Live Ecology Polygon: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)

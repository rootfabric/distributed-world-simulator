extends SceneTree

const ContinuousFieldScript = preload("res://scripts/labs/ecology/eco_vis1_8b_continuous_population_field.gd")
const ContinuousScene = preload("res://scenes/labs/ecology/eco_vis1_8b_continuous_population_field.tscn")

var _assertions := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := ContinuousScene.instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame
	_check(scene.get_script() == ContinuousFieldScript, "VIS1.8B scene script attached")
	var initial: Dictionary = scene.get_realtime_turnover_state()
	_check(String(initial.get("stage", "")) == "ECO.VIS1.8B", "stage")
	_check(String(initial.get("mode", "")) == "CONTINUOUS_ROLLING_TURNOVER_PLAYBACK", "mode")
	_check(bool(initial.get("continuous", false)), "continuous mode")
	_check(int(initial.get("generation", -1)) == 0, "generation 0")
	_check(int(initial.get("founder_count", 0)) == 53, "53 founders")
	_check(int(initial.get("visual_count", 0)) == 53, "53 initial representatives")
	_check(int(initial.get("max_generation", 0)) > 12, "generation ceiling extends beyond VIS1.7")
	_check(absf(float(initial.get("represented_biomass_kg", 0.0)) - 11.0) < 0.000001, "generation 0 biomass conserved")
	print("ECO.VIS1.8B smoke progress: generation0_checked")

	scene.set_realtime_turnover_generation(1)
	await process_frame
	var generation1: Dictionary = scene.get_realtime_turnover_state()
	var generation1_hash := String(generation1.get("field_hash", ""))
	_check(generation1_hash.length() == 64, "generation 1 hash")

	scene.set_realtime_turnover_generation(13)
	await process_frame
	var generation13: Dictionary = scene.get_realtime_turnover_state()
	_check(int(generation13.get("generation", -1)) == 13, "generation 13 reachable")
	_check(String(generation13.get("presentation_mode", "")) == "REALTIME_PROXY", "generation 13 realtime proxy")
	_check(int(generation13.get("birth_count", 0)) > 0, "generation 13 births")
	_check(int(generation13.get("death_count", 0)) > 0, "generation 13 deaths")
	_check(int(generation13.get("ph5_rebuilds_during_turnover", -1)) == 0, "no PH5 rebuild past generation 12")
	_check(absf(float(generation13.get("represented_biomass_kg", 0.0)) - 11.0) < 0.000001, "generation 13 biomass conserved")
	print("ECO.VIS1.8B smoke progress: beyond_g12_checked")

	# Autoplay must cross the former G12 boundary.
	scene.set_realtime_turnover_generation(12)
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	scene._unhandled_input(space)
	_check(bool(scene.get_realtime_turnover_state().get("playing", false)), "Space enables continuous autoplay")
	scene._process(1.0)
	var auto_state: Dictionary = scene.get_realtime_turnover_state()
	_check(int(auto_state.get("generation", -1)) == 13, "autoplay crosses generation 12")
	_check(bool(auto_state.get("playing", false)), "autoplay remains active after generation 12")
	print("ECO.VIS1.8B smoke progress: autoplay_checked")

	# Build enough generations to force rolling-cache eviction.
	scene.set_realtime_turnover_generation(45)
	await process_frame
	var generation45: Dictionary = scene.get_realtime_turnover_state()
	_check(int(generation45.get("generation", -1)) == 45, "generation 45 reachable")
	_check(int(generation45.get("cached_generation_count", 999)) <= 33, "rolling cache bounded")
	_check(int(generation45.get("oldest_rewind_generation", 0)) > 1, "rolling cache evicts old generations")
	_check(int(generation45.get("history_point_count", 0)) <= 64, "compact history bounded")
	_check(int(generation45.get("history_point_count", 0)) > 12, "history spans beyond original temporal limit")
	_check(int(generation45.get("peak_visual_count", 0)) > 0, "peak population tracked")
	_check(float(generation45.get("mean_fitness", 0.0)) > 0.0, "mean fitness tracked")
	_check(int(generation45.get("alpha_count", 0)) > 0, "alpha composition tracked")
	_check(int(generation45.get("beta_count", 0)) > 0, "beta composition tracked")
	_check(absf(float(generation45.get("represented_biomass_kg", 0.0)) - 11.0) < 0.000001, "generation 45 biomass conserved")
	_check(int(generation45.get("ph5_rebuilds_during_turnover", -1)) == 0, "long run avoids PH5 rebuilds")
	print("ECO.VIS1.8B smoke progress: rolling_cache_checked")

	# Rewind below cache floor must clamp instead of forcing a long synchronous replay.
	var floor_generation := int(generation45.get("oldest_rewind_generation", 0))
	scene.set_realtime_turnover_generation(1)
	var clamped: Dictionary = scene.get_realtime_turnover_state()
	_check(int(clamped.get("generation", -1)) == floor_generation, "evicted rewind clamps to oldest cached generation")
	_check(bool(clamped.get("rewind_clamped", false)), "rewind clamp reported")

	# R/reset gives a deterministic replay path from founders.
	scene.set_realtime_turnover_generation(0)
	var reset: Dictionary = scene.get_realtime_turnover_state()
	_check(int(reset.get("generation", -1)) == 0, "restart returns generation 0")
	_check(int(reset.get("max_simulated_generation", -1)) == 0, "restart resets rolling history")
	scene.set_realtime_turnover_generation(1)
	await process_frame
	var replay1: Dictionary = scene.get_realtime_turnover_state()
	_check(String(replay1.get("field_hash", "")) == generation1_hash, "generation 1 deterministic after restart")
	_check(scene.get_spatial_snapshot() == scene.get_spatial_snapshot().duplicate(true), "canonical snapshot remains stable")
	print("ECO.VIS1.8B smoke progress: restart_determinism_checked")

	scene.queue_free()
	await process_frame
	print("ECO.VIS1.8B headless scene smoke: PASS (%d assertions)" % _assertions)
	quit(0)


func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		return
	push_error("ECO.VIS1.8B assertion failed: %s" % label)
	quit(1)

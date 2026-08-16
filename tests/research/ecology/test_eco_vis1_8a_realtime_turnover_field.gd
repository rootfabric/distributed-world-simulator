extends SceneTree

const RealtimeFieldScript = preload("res://scripts/labs/ecology/eco_vis1_8a_realtime_turnover_field.gd")
const RealtimeScene = preload("res://scenes/labs/ecology/eco_vis1_8a_realtime_turnover_field.tscn")

var _assertions := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := RealtimeScene.instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame
	_check(scene.get_script() == RealtimeFieldScript, "VIS1.8A-R1 scene script attached")
	var initial: Dictionary = scene.get_realtime_turnover_state()
	_check(String(initial.get("stage", "")) == "ECO.VIS1.8A-R1", "stage")
	_check(String(initial.get("mode", "")) == "REALTIME_TURNOVER_PROXY_PRESENTATION", "mode")
	_check(int(initial.get("generation", -1)) == 0, "generation 0")
	_check(int(initial.get("founder_count", 0)) == 53, "53 founders")
	_check(int(initial.get("visual_count", 0)) == 53, "53 generation-zero representatives")
	_check(String(initial.get("presentation_mode", "")) == "PH5_BASELINE", "generation zero keeps PH5")
	_check(int(initial.get("ph5_rebuilds_during_turnover", -1)) == 0, "no turnover PH5 rebuilds initially")
	_check(absf(float(initial.get("represented_biomass_kg", 0.0)) - 11.0) < 0.000001, "generation zero biomass conserved")
	_check(not bool(initial.get("canonical_population_truth", true)), "population truth remains derived")
	_check(not bool(initial.get("canonical_timeline_truth", true)), "timeline truth remains derived")
	print("ECO.VIS1.8A-R1 smoke progress: generation0_checked")

	var snapshot_before: Dictionary = scene.get_spatial_snapshot().duplicate(true)
	scene.set_realtime_turnover_generation(1)
	await process_frame
	var generation1: Dictionary = scene.get_realtime_turnover_state()
	_check(int(generation1.get("generation", -1)) == 1, "generation 1 applied")
	_check(String(generation1.get("presentation_mode", "")) == "REALTIME_PROXY", "turnover uses realtime proxy presentation")
	_check(int(generation1.get("birth_count", 0)) > 0, "generation 1 births visible")
	_check(int(generation1.get("death_count", 0)) > 0, "generation 1 deaths visible")
	_check(int(generation1.get("survivor_count", 0)) > 0, "generation 1 survivors visible")
	_check(int(generation1.get("visual_count", 0)) == int(generation1.get("survivor_count", 0)) + int(generation1.get("birth_count", 0)), "count equals survivors plus births")
	_check(int(generation1.get("ph5_rebuilds_during_turnover", -1)) == 0, "generation 1 avoids whole-field PH5 rebuild")
	_check(int(generation1.get("preview_build_count", 0)) >= 1, "preview built")
	_check(absf(float(generation1.get("represented_biomass_kg", 0.0)) - 11.0) < 0.000001, "generation 1 biomass conserved")
	_check(String(generation1.get("field_hash", "")).length() == 64, "generation 1 field hash")
	_check(String(generation1.get("turnover_hash", "")).length() == 64, "generation 1 turnover hash")
	var ph5_root := scene.get_node_or_null("SpatialEcologyProjection/PH5PlantGeometry") as Node3D
	_check(ph5_root != null and not ph5_root.visible, "detailed PH5 hidden while realtime turnover preview is active")
	var preview_root := scene.get_node_or_null("SpatialEcologyProjection/VIS18RealtimePreview") as Node3D
	_check(preview_root != null and preview_root.visible, "realtime preview visible")
	_check(int(generation1.get("active_animations", 0)) > 0, "birth/death animation active")
	print("ECO.VIS1.8A-R1 smoke progress: realtime_generation_checked")

	var hash_generation1 := String(generation1.get("field_hash", ""))
	scene.set_realtime_turnover_generation(2)
	await process_frame
	var generation2: Dictionary = scene.get_realtime_turnover_state()
	_check(int(generation2.get("generation", -1)) == 2, "generation 2 applied")
	_check(String(generation2.get("field_hash", "")) != hash_generation1, "field changes between generations")
	_check(int(generation2.get("ph5_rebuilds_during_turnover", -1)) == 0, "generation 2 still avoids PH5 rebuild")
	_check(absf(float(generation2.get("represented_biomass_kg", 0.0)) - 11.0) < 0.000001, "generation 2 biomass conserved")
	var hash_generation2 := String(generation2.get("field_hash", ""))

	scene.set_realtime_turnover_generation(1)
	await process_frame
	var generation1_rewind: Dictionary = scene.get_realtime_turnover_state()
	_check(String(generation1_rewind.get("field_hash", "")) == hash_generation1, "rewind generation 1 deterministic")
	scene.set_realtime_turnover_generation(2)
	await process_frame
	var generation2_rewind: Dictionary = scene.get_realtime_turnover_state()
	_check(String(generation2_rewind.get("field_hash", "")) == hash_generation2, "rewind generation 2 deterministic")
	_check(scene.get_spatial_snapshot() == snapshot_before, "canonical spatial snapshot unchanged")
	print("ECO.VIS1.8A-R1 smoke progress: determinism_checked")

	# Space must enable the cheap autoplay path; advance it explicitly without waiting wall-clock time.
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	scene._unhandled_input(space)
	_check(bool(scene.get_realtime_turnover_state().get("playing", false)), "Space enables realtime autoplay")
	var before_auto: int = int(scene.get_evolution_generation())
	scene._process(1.20)
	var after_auto: int = int(scene.get_evolution_generation())
	_check(after_auto == mini(before_auto + 1, 12), "autoplay advances generation without full PH5 rebuild")
	_check(int(scene.get_realtime_turnover_state().get("ph5_rebuilds_during_turnover", -1)) == 0, "autoplay PH5 rebuild count remains zero")
	print("ECO.VIS1.8A-R1 smoke progress: autoplay_checked")

	scene.queue_free()
	await process_frame
	print("ECO.VIS1.8A-R1 headless scene smoke: PASS (%d assertions)" % _assertions)
	quit(0)


func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		return
	push_error("ECO.VIS1.8A-R1 assertion failed: %s" % label)
	quit(1)

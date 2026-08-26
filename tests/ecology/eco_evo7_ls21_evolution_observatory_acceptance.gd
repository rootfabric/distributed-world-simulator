extends SceneTree

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const Session = preload("res://scripts/ecology/shadow/eco_evo7_live_shadow_evolution_session_v1.gd")
const Observatory = preload("res://scripts/ecology/shadow/eco_evo7_evolution_observatory_v1.gd")

const SEED := 20260826
const RUN_GENERATIONS := 12
var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var world = EarthWorld.new()
	root.add_child(world)
	_check(world.setup(null), "real Earth initializes")
	var session = Session.new()
	_check(session.setup(world, SEED), "LS1 session initializes")
	var gen0 := session.get_snapshot()
	var obs = Observatory.new()
	_check(obs.setup(gen0), "LS2.1 observatory initializes from generation zero")
	var initial := obs.get_latest()
	_check(int(initial.get("generation", -1)) == 0, "observatory records generation zero")
	_check(obs.get_history_size() == 1, "history starts with one record")
	for zone_value in Array(initial.get("zones", [])):
		var zone: Dictionary = zone_value
		_check(int(zone.get("lineage_richness", 0)) == 12, "generation zero preserves twelve founder lineages")
		_check(absf(float(zone.get("shannon_entropy", 0.0)) - log(12.0)) < 0.000001, "generation zero entropy equals ln(12)")
		_check(int(zone.get("fixation_generation", -1)) == -1, "generation zero is not fixed")
		_check(float(zone.get("fitness_balance_error", 1.0)) < 0.000001, "fitness decomposition reconstructs fitness")
		var moments: Dictionary = zone.get("trait_moments", {})
		for field in ["fitness", "leaf_area_index_proxy", "realized_root_depth_m", "root_shoot_ratio", "realized_height_m"]:
			_check(Dictionary(moments.get(field, {})).has("variance"), "trait variance exists for %s" % field)

	for generation in RUN_GENERATIONS:
		var snap := session.step_generations(1)
		_check(not snap.is_empty(), "session advances generation %d" % (generation + 1))
		if snap.is_empty():
			_finish(); return
		_check(obs.record_snapshot(snap), "observatory records generation %d" % (generation + 1))

	var final_entry := obs.get_latest()
	_check(int(final_entry.get("generation", -1)) == RUN_GENERATIONS, "observatory reaches generation 12")
	_check(obs.get_history_size() == RUN_GENERATIONS + 1, "history stores every generation")
	var richness_changed_zones := 0
	for zone_index in 3:
		var zone: Dictionary = final_entry["zones"][zone_index]
		if int(zone.get("lineage_richness", 12)) < 12:
			richness_changed_zones += 1
		_check(int(zone.get("lineage_richness", 0)) >= 1 and int(zone.get("lineage_richness", 0)) <= 12, "final lineage richness is bounded")
		_check(float(zone.get("shannon_entropy", -1.0)) >= 0.0 and float(zone.get("shannon_entropy", 99.0)) <= log(12.0) + 0.000001, "lineage entropy remains bounded")
		_check(float(zone.get("fitness_balance_error", 1.0)) < 0.000001, "final fitness decomposition remains exact")
	_check(richness_changed_zones >= 1, "live selection changes lineage richness within twelve generations")

	# Exercise fixation-time accounting without asking the expensive integration run to
	# wait until fixation. This is a read-only observatory fixture derived from a real
	# LS1 snapshot; no biology or population state is mutated.
	var fixed_snapshot: Dictionary = session.get_snapshot().duplicate(true)
	fixed_snapshot["generation"] = 13
	for zone_index in 3:
		var zone: Dictionary = fixed_snapshot["zones"][zone_index]
		var members: Array = zone["members"]
		var winning := String(Dictionary(members[0])["lineage_id"])
		for member_index in members.size():
			Dictionary(members[member_index])["lineage_id"] = winning
		zone["dominant_lineage"] = winning
		zone["dominant_lineage_count"] = members.size()
		fixed_snapshot["zones"][zone_index] = zone
	_check(obs.record_snapshot(fixed_snapshot), "observatory accepts derived fixation accounting fixture")
	var fixed_entry := obs.get_latest()
	for zone_index in 3:
		_check(bool(fixed_entry["zones"][zone_index]["fixed"]), "observatory detects fixation")
		_check(obs.get_fixation_generation(zone_index) == 13, "observatory records first fixation generation")

	var replay_session = Session.new()
	_check(replay_session.setup(world, SEED), "same-seed replay session initializes")
	var replay_obs = Observatory.new()
	_check(replay_obs.setup(replay_session.get_snapshot()), "same-seed replay observatory initializes")
	for _i in 4:
		var replay_snap := replay_session.step_generations(1)
		_check(replay_obs.record_snapshot(replay_snap), "same-seed replay records")
	var reference_hash := String(obs.get_history()[4].get("observatory_hash", ""))
	var replay_hash := String(replay_obs.get_latest().get("observatory_hash", ""))
	_check(reference_hash == replay_hash, "same seed produces deterministic observatory history")

	_source_guard()
	world.queue_free()
	_finish()

func _source_guard() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/ecology/shadow/eco_evo7_evolution_observatory_v1.gd").to_lower()
	_check(not source.contains("reproduce_bundle("), "observatory has no reproduction call site")
	_check(not source.contains("fileaccess."), "observatory has no persistence/file access")
	_check(not source.contains("diraccess."), "observatory has no directory access")
	_check(not source.contains("multiplayer"), "observatory has no network path")
	var shadow_source := FileAccess.get_file_as_string("res://scripts/ecology/shadow/eco_evo7_live_world_shadow_v1.gd")
	_check(shadow_source.contains("var fitness := water_limited_resource + 0.35 * float(phenotype[\"establishment_capacity\"]) + 0.30 * water_match + shade_adaptation - drought_cost"), "LS2.1 does not alter fitness formula")
	_check(shadow_source.contains("\"fitness_establishment_term\""), "shadow exposes establishment contribution read-only")
	_check(shadow_source.contains("\"fitness_drought_cost\""), "shadow exposes drought contribution read-only")

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO7 LS2.1 Evolution Observatory: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 LS2.1 FAIL: %s" % failure)
	print("ECO.EVO7 LS2.1 Evolution Observatory: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)

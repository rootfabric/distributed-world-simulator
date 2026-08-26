extends SceneTree

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const Session = preload("res://scripts/ecology/shadow/eco_evo7_live_shadow_evolution_session_v1.gd")

const SEED := 20260826
var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var world = EarthWorld.new()
	world.name = "LS1AcceptanceEarth"
	root.add_child(world)
	_check(world.setup(null), "real ProceduralEarthWorld initializes")
	var center: Vector3 = world.get("surface_center_direction")
	var earth_state_before: Dictionary = world.pipeline.sample(center, 0).duplicate(true)

	var session = Session.new()
	_check(session.setup(world, SEED), "LS1 RAM-only session initializes from real Earth")
	var gen0 := session.get_snapshot()
	_check(not gen0.is_empty(), "generation zero snapshot exists")
	if gen0.is_empty():
		_finish(); return
	_check(String(gen0["mode"]) == Session.MODE, "LS1 declares SHADOW_RAM_ONLY")
	_check(int(gen0["generation"]) == 0, "LS1 begins at generation zero")
	_check(Array(gen0["zones"]).size() == 3, "LS1 uses exactly three live Earth zones")
	_check(int(gen0["population_size"]) == 12, "LS1 uses twelve plants per zone")
	for key in ["world_write", "ecology_write", "persistence_write", "network_replication_write", "xfer_authority", "alternate_mutation_authority"]:
		_check(not bool(Dictionary(gen0["authorities"]).get(key, true)), "LS1 forbids %s" % key)

	var zones0: Array = gen0["zones"]
	var initial_hash := String(gen0["initial_population_hash"])
	for zone_value in zones0:
		var z: Dictionary = zone_value
		_check(String(z["population_hash"]) == initial_hash, "all live zones receive exact copied founder population")
		_check(Array(z["members"]).size() == 12, "zone exposes twelve observable members")
	_check(float(zones0[2]["moisture"]) > float(zones0[0]["moisture"]) + 0.10, "regional live patch contains strong moisture gradient")
	_check(absf(float(zones0[2]["mean_fitness"]) - float(zones0[0]["mean_fitness"])) > 0.000001, "same founder pool has environment-dependent fitness")

	var gen1 := session.step_generations(1)
	_check(not gen1.is_empty() and int(gen1["generation"]) == 1, "one evolutionary generation advances")
	var pool_hashes: Array = gen1["first_candidate_pool_hashes"]
	_check(pool_hashes.size() == 3, "generation one records three candidate pool hashes")
	if pool_hashes.size() == 3:
		_check(String(pool_hashes[0]) == String(pool_hashes[1]) and String(pool_hashes[1]) == String(pool_hashes[2]), "first mutation candidate pool is identical across environments")
	var gen12 := session.step_generations(11)
	_check(not gen12.is_empty() and int(gen12["generation"]) == 12, "LS1 runs multi-generation live selection")
	var final_pop_hashes := {}
	for zone_value in Array(gen12["zones"]):
		final_pop_hashes[String(Dictionary(zone_value)["population_hash"])] = true
	_check(final_pop_hashes.size() >= 2, "live environmental selection diverges copied populations")
	_check(_zone_metric_spread(Array(gen12["zones"]), "mean_root_depth_m") > 0.01 or _zone_metric_spread(Array(gen12["zones"]), "mean_lai") > 0.01, "live selection creates measurable functional divergence")

	var replay = Session.new()
	_check(replay.setup(world, SEED), "same-seed replay session initializes")
	var replay12 := replay.step_generations(12)
	_check(String(replay12.get("state_hash", "")) == String(gen12.get("state_hash", "")), "same seed and live Earth replay deterministically")

	var off = Session.new()
	_check(off.setup(world, SEED), "evolution-off control initializes")
	var off0 := off.get_snapshot()
	off.set_evolution_enabled(false)
	var off5 := off.step_generations(5)
	_check(int(off5.get("generation", -1)) == 5, "evolution-off control still advances observation time")
	for zone_index in 3:
		_check(String(off5["zones"][zone_index]["population_hash"]) == String(off0["zones"][zone_index]["population_hash"]), "evolution OFF preserves exact heritable identities in zone %d" % zone_index)

	var reset := session.reset_same_seed()
	_check(int(reset.get("generation", -1)) == 0, "reset same seed returns generation zero")
	_check(String(reset.get("initial_population_hash", "")) == initial_hash, "reset same seed restores exact founder pool")
	var denied := session.request_authoritative_write("earth", {"forbidden": true})
	_check(not bool(denied.get("success", true)) and String(denied.get("error_code", "")) == "ECO_SHADOW_WRITE_FORBIDDEN", "LS1 authoritative write fails closed")
	var earth_state_after: Dictionary = world.pipeline.sample(center, 0)
	_check(earth_state_after == earth_state_before, "LS1 leaves production Earth sample unchanged")
	_source_guard()
	world.queue_free()
	_finish()

func _zone_metric_spread(zones: Array, field: String) -> float:
	var low := INF
	var high := -INF
	for zone_value in zones:
		var value := float(Dictionary(zone_value)[field])
		low = minf(low, value)
		high = maxf(high, value)
	return high - low

func _source_guard() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/ecology/shadow/eco_evo7_live_shadow_evolution_session_v1.gd")
	var lower := source.to_lower()
	_check(source.count("var child := LineageExtension.reproduce_bundle(") == 1, "LS1 has exactly one canonical reproduction call site")
	_check(source.contains("plant_mutation_lineage_extension_evo7_v1.gd"), "LS1 imports accepted EVO7 lineage extension")
	_check(not lower.contains("randomize("), "LS1 introduces no random RNG authority")
	_check(not lower.contains("randf("), "LS1 introduces no randf mutation path")
	_check(not lower.contains("randi("), "LS1 introduces no randi mutation path")
	_check(not lower.contains("fileaccess."), "LS1 session has no persistence/file writes")
	_check(not lower.contains("diraccess."), "LS1 session has no directory/persistence writes")
	var seed_start := source.find("func _mutation_seed")
	var seed_end := source.find("\nfunc ", seed_start + 1)
	var seed_section := source.substr(seed_start, seed_end - seed_start)
	var seed_code := PackedStringArray()
	for raw_line in seed_section.split("\n"):
		var line := String(raw_line).strip_edges()
		if not line.begins_with("##") and not line.begins_with("#"):
			seed_code.append(line)
	var seed_logic := "\n".join(seed_code).to_lower()
	_check(not seed_logic.contains("zone"), "mutation seed function contains no zone identity")
	_check(not seed_logic.contains("moisture"), "mutation seed function contains no moisture")
	_check(not seed_logic.contains("sunlight"), "mutation seed function contains no light")

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO7 LS1 Live Shadow Evolution Session: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 LS1 FAIL: %s" % failure)
	print("ECO.EVO7 LS1 Live Shadow Evolution Session: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)

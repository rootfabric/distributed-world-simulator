extends SceneTree

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const Session = preload("res://scripts/ecology/shadow/eco_evo7_live_shadow_evolution_session_v1.gd")
const Observer = preload("res://scripts/ecology/shadow/eco_evo7_ls21_divergence_observer_v1.gd")

const SEED := 20260826
const GENERATIONS := 12
var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var world = EarthWorld.new()
	world.name = "LS21AcceptanceEarth"
	root.add_child(world)
	_check(world.setup(null), "real ProceduralEarthWorld initializes")

	var session = Session.new()
	_check(session.setup(world, SEED), "LS2.1 source session initializes")
	var initial: Dictionary = session.get_snapshot()
	_check(not initial.is_empty(), "initial LS1/LS2 snapshot exists")
	if initial.is_empty():
		_finish(); return

	var baseline: Dictionary = Observer.observe(initial, initial)
	_check(not baseline.is_empty(), "observer accepts LS2 snapshot")
	if baseline.is_empty():
		_finish(); return
	_check(String(baseline.get("mode", "")) == Observer.MODE, "observer declares READ_ONLY_MEASUREMENT")
	_check(bool(baseline.get("initial_common_population", false)), "observer proves common founder population")
	_check(int(baseline.get("distinct_population_count", -1)) == 1, "generation zero has one heritable population identity")
	_check(not bool(baseline.get("heritable_population_diverged", true)), "generation zero has no heritable divergence")
	var baseline_env: Dictionary = baseline["environment"]
	_check(float(baseline_env.get("moisture_span", 0.0)) > 0.10, "observer exposes strong live moisture gradient")
	_check(Array(baseline.get("zones", [])).size() == 3, "observer exposes all three LS2 zones")
	_check(Array(baseline.get("pairwise", [])).size() == 3, "observer exposes all three zone pairs")

	var evolved: Dictionary = session.step_generations(GENERATIONS)
	_check(not evolved.is_empty() and int(evolved.get("generation", -1)) == GENERATIONS, "live evolution reaches measurement generation")
	var evolved_report: Dictionary = Observer.observe(initial, evolved)
	_check(not evolved_report.is_empty(), "observer measures evolved snapshot")
	if evolved_report.is_empty():
		_finish(); return
	_check(bool(evolved_report.get("candidate_pool_identity_observed", false)), "observer sees generation-one candidate pool identity evidence")
	_check(bool(evolved_report.get("candidate_pool_identity_equal", false)), "same candidate mutation pool was offered to all environments")
	_check(int(evolved_report.get("distinct_population_count", 0)) >= 2, "live environments produce at least two heritable population outcomes")
	_check(int(evolved_report.get("population_diverged_pair_count", 0)) >= 1, "at least one zone pair diverges heritably")
	_check(bool(evolved_report.get("heritable_population_diverged", false)), "observer classifies heritable divergence")
	_check(bool(evolved_report.get("realized_trait_diverged", false)), "observer detects realized functional divergence")
	_check(float(evolved_report.get("max_pairwise_trait_distance", 0.0)) > 0.001, "functional divergence is quantitatively non-zero")
	_check(not String(evolved_report.get("report_hash", "")).is_empty(), "measurement report has deterministic identity")
	for key in ["world_write", "ecology_write", "persistence_write", "network_replication_write", "xfer_authority", "mutation_authority"]:
		_check(not bool(Dictionary(evolved_report["authority"]).get(key, true)), "observer owns no %s" % key)

	var replay = Session.new()
	_check(replay.setup(world, SEED), "same-seed replay initializes")
	var replay_initial: Dictionary = replay.get_snapshot()
	var replay_evolved: Dictionary = replay.step_generations(GENERATIONS)
	var replay_report: Dictionary = Observer.observe(replay_initial, replay_evolved)
	_check(String(replay_evolved.get("state_hash", "")) == String(evolved.get("state_hash", "")), "underlying live evolution replay is exact")
	_check(String(replay_report.get("report_hash", "")) == String(evolved_report.get("report_hash", "")), "LS2.1 measurement replay is exact")

	var off = Session.new()
	_check(off.setup(world, SEED), "evolution-off control initializes")
	var off_initial: Dictionary = off.get_snapshot()
	off.set_evolution_enabled(false)
	var off_final: Dictionary = off.step_generations(GENERATIONS)
	var off_report: Dictionary = Observer.observe(off_initial, off_final)
	_check(int(off_final.get("generation", -1)) == GENERATIONS, "evolution-off control observes same time horizon")
	_check(int(off_report.get("distinct_population_count", -1)) == 1, "Evolution OFF keeps one heritable population across zones")
	_check(not bool(off_report.get("heritable_population_diverged", true)), "Evolution OFF is not misclassified as evolution")
	for zone_index in 3:
		_check(String(off_initial["zones"][zone_index]["population_hash"]) == String(off_final["zones"][zone_index]["population_hash"]), "Evolution OFF preserves zone %d bundle identities" % zone_index)

	print("ECO.EVO7 LS2.1 metrics generation=%d distinct_populations=%d diverged_pairs=%d mean_trait_distance=%.6f max_trait_distance=%.6f moisture_span=%.6f off_distinct_populations=%d report_hash=%s" % [
		GENERATIONS,
		int(evolved_report["distinct_population_count"]),
		int(evolved_report["population_diverged_pair_count"]),
		float(evolved_report["mean_pairwise_trait_distance"]),
		float(evolved_report["max_pairwise_trait_distance"]),
		float(Dictionary(evolved_report["environment"])["moisture_span"]),
		int(off_report["distinct_population_count"]),
		String(evolved_report["report_hash"]).substr(0, 16),
	])
	_source_guard()
	world.queue_free()
	_finish()

func _source_guard() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/ecology/shadow/eco_evo7_ls21_divergence_observer_v1.gd")
	var lower := source.to_lower()
	_check(not source.contains("reproduce_bundle("), "LS2.1 adds no reproduction call site")
	_check(not lower.contains("plant_mutation"), "LS2.1 imports no mutation authority")
	_check(not lower.contains("procedural_earth_world"), "LS2.1 observer cannot sample world directly")
	_check(not lower.contains("request_authoritative_write("), "LS2.1 observer cannot request authoritative writes")
	_check(not lower.contains("fileaccess."), "LS2.1 observer has no persistence/file access")
	_check(not lower.contains("diraccess."), "LS2.1 observer has no directory/persistence access")

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO7 LS2.1 Live Divergence Observer: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 LS2.1 FAIL: %s" % failure)
	print("ECO.EVO7 LS2.1 Live Divergence Observer: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)

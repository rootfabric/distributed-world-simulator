extends SceneTree

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const Observer = preload("res://scripts/ecology/shadow/eco_evo7_live_world_shadow_observer_v1.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var world = EarthWorld.new()
	world.name = "ShadowSmokeEarth"
	root.add_child(world)
	_check(world.setup(null), "real ProceduralEarthWorld initializes")
	_check(world.pipeline != null, "real Earth owns production rule pipeline")
	_check(world.earth_light != null, "real Earth owns EarthSun light")
	var observer = Observer.new()
	observer.name = "ShadowSmokeObserver"
	root.add_child(observer)
	_check(observer.setup(world, null), "shadow observer attaches to initialized real Earth")
	var first := observer.get_last_observation()
	_check(not first.is_empty(), "observer produces a live-world observation")
	if not first.is_empty():
		_check(String(first.get("mode", "")) == "SHADOW_READ_ONLY", "live observation remains shadow-only")
		_check(String(first.get("observation_hash", "")).length() == 64, "live observation has deterministic provenance hash")
		_check(String(first.get("live_state_hash", "")).length() == 64, "live Earth state is provenance-hashed")
		_check(Dictionary(first.get("environment_sample", {})).get("checksum", "").length() == 64, "live Earth maps to a validated EnvironmentSample")
		for key in ["world_write", "ecology_write", "persistence_write", "network_replication_write", "mutation_authority", "xfer_authority"]:
			_check(not bool(Dictionary(first.get("authorities", {})).get(key, true)), "runtime live shadow forbids %s" % key)
	var denied := observer.request_authoritative_write("earth", {"change": "forbidden"})
	_check(not bool(denied.get("success", true)), "runtime observer rejects authoritative write")
	var before_hash := String(first.get("observation_hash", ""))
	world.prepare_surface_region(world.get_canonical_spawn_direction(), false)
	var after := observer.get_last_observation()
	_check(not after.is_empty(), "earth_rebuilt signal refreshes live shadow observation")
	_check(String(after.get("observation_hash", "")).length() == 64, "refreshed live shadow stays provenance-hashed")
	_check(String(after.get("observation_hash", "")) != before_hash, "new observation identity records rebuild event without world writes")
	observer.queue_free()
	world.queue_free()
	_finish()

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO7 Live World Shadow Runtime Smoke: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 LIVE SHADOW RUNTIME FAIL: %s" % failure)
	print("ECO.EVO7 Live World Shadow Runtime Smoke: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)

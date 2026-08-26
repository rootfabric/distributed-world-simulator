extends SceneTree

## Acceptance for the first production-world-bound EVO7 shadow mode.
## Uses the production EarthRulePipeline (not research environment fixtures),
## proves deterministic live sampling, causal water response, and fail-closed authority.

const Shadow = preload("res://scripts/ecology/shadow/eco_evo7_live_world_shadow_v1.gd")
const Pipeline = preload("res://scripts/world/planetary/earth_rule_pipeline.gd")
const Morphology = preload("res://scripts/research/ecology/evo7_morphology_evolution_bridge_v1.gd")

const SEED := 20260823
const EARTH_RADIUS_M := 6371000.0
var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_authority_contract()
	var pipeline = Pipeline.new()
	_check(pipeline.setup(), "production EarthRulePipeline initializes")
	if not pipeline.get_validation_errors().is_empty():
		failures.append("production pipeline validation errors: %s" % str(pipeline.get_validation_errors()))
	var extremes := _find_land_extremes(pipeline)
	_check(not extremes.is_empty(), "deterministic production land samples found")
	if extremes.is_empty():
		_finish()
		return
	var dry_direction: Vector3 = extremes["dry_direction"]
	var wet_direction: Vector3 = extremes["wet_direction"]
	_check(float(extremes["wet_moisture"]) > float(extremes["dry_moisture"]) + 0.10, "production Earth contains materially distinct moisture conditions")

	var dry_obs := Shadow.observe_pipeline(pipeline, dry_direction, 12345.0, "shadow-dry", dry_direction * EARTH_RADIUS_M, 1.45)
	var dry_replay := Shadow.observe_pipeline(pipeline, dry_direction, 12345.0, "shadow-dry", dry_direction * EARTH_RADIUS_M, 1.45)
	var wet_obs := Shadow.observe_pipeline(pipeline, wet_direction, 12345.0, "shadow-wet", wet_direction * EARTH_RADIUS_M, 1.45)
	_check(bool(dry_obs.get("success", false)), "dry production observation succeeds")
	_check(bool(wet_obs.get("success", false)), "wet production observation succeeds")
	_check(bool(dry_replay.get("success", false)), "dry production observation replay succeeds")
	if not bool(dry_obs.get("success", false)) or not bool(wet_obs.get("success", false)):
		_finish()
		return
	var dry_detail: Dictionary = dry_obs["details"]
	var dry_replay_detail: Dictionary = dry_replay["details"]
	var wet_detail: Dictionary = wet_obs["details"]
	_check(String(dry_detail["observation_hash"]) == String(dry_replay_detail["observation_hash"]), "same live sample identity replays hash-identically")
	_check(String(dry_detail["live_state_hash"]) == String(dry_replay_detail["live_state_hash"]), "production live state hash is deterministic")
	_check(String(dry_detail["observation_hash"]) != String(wet_detail["observation_hash"]), "different live environment produces different observation identity")
	_check(float(dry_detail["canopy_adjusted_sunlight"]) <= float(dry_detail["open_sunlight"]), "canopy proxy cannot create light")
	_check(float(wet_detail["canopy_adjusted_sunlight"]) <= float(wet_detail["open_sunlight"]), "wet canopy proxy cannot create light")

	var ancestor := Morphology.default_ancestor_bundle(SEED)
	_check(not ancestor.is_empty(), "accepted EVO7 ancestor bundle is available")
	var ancestor_hash := String(ancestor.get("bundle_checksum", ""))
	var dry_eval := Shadow.evaluate_bundle_against_observation(ancestor, dry_detail)
	var dry_eval_replay := Shadow.evaluate_bundle_against_observation(ancestor, dry_replay_detail)
	var wet_eval := Shadow.evaluate_bundle_against_observation(ancestor, wet_detail)
	_check(bool(dry_eval.get("success", false)), "dry live-world shadow evaluation succeeds")
	_check(bool(wet_eval.get("success", false)), "wet live-world shadow evaluation succeeds")
	_check(bool(dry_eval_replay.get("success", false)), "dry shadow evaluation replay succeeds")
	_check(String(ancestor.get("bundle_checksum", "")) == ancestor_hash, "shadow evaluation cannot mutate candidate bundle")
	if bool(dry_eval.get("success", false)) and bool(wet_eval.get("success", false)):
		var dry_result: Dictionary = dry_eval["details"]
		var wet_result: Dictionary = wet_eval["details"]
		var dry_replay_result: Dictionary = dry_eval_replay["details"]
		_check(String(dry_result["shadow_result_hash"]) == String(dry_replay_result["shadow_result_hash"]), "same live observation + candidate replays shadow result hash-identically")
		_check(String(dry_result["evaluation_identity_tag"]) == String(wet_result["evaluation_identity_tag"]), "environment cannot re-roll EVO7 candidate realization identity")
		_check(int(dry_result["candidate_individual_seed"]) == int(wet_result["candidate_individual_seed"]), "environment cannot change candidate individual seed")
		_check(String(dry_result["environment_hash"]) != String(wet_result["environment_hash"]), "live dry/wet conditions change only environmental realization")
		_check(absf(float(dry_result["shadow_fitness"]) - float(wet_result["shadow_fitness"])) > 0.000001, "live dry/wet conditions causally change shadow fitness")
		_check(float(wet_result["water_satisfaction"]) > float(dry_result["water_satisfaction"]), "wetter production condition raises realized water satisfaction")
		_check(float(wet_result["effective_soil_moisture"]) > float(dry_result["effective_soil_moisture"]), "wetter production condition raises effective soil moisture")
		print("ECO.EVO7 LIVE SHADOW metrics dry(m=%.6f,water=%.6f,fitness=%.6f,lai=%.6f) wet(m=%.6f,water=%.6f,fitness=%.6f,lai=%.6f)" % [
			float(dry_detail["environment_sample"]["soil_moisture"]), float(dry_result["water_satisfaction"]), float(dry_result["shadow_fitness"]), float(dry_result["leaf_area_index_proxy"]),
			float(wet_detail["environment_sample"]["soil_moisture"]), float(wet_result["water_satisfaction"]), float(wet_result["shadow_fitness"]), float(wet_result["leaf_area_index_proxy"]),
		])

	_source_boundaries()
	_finish()

func _authority_contract() -> void:
	var config := Shadow.load_config()
	_check(not config.is_empty(), "live shadow config loads")
	_check(String(config.get("mode", "")) == Shadow.MODE, "live ecology mode is SHADOW_READ_ONLY")
	for key in ["world_write", "ecology_write", "persistence_write", "network_replication_write", "mutation_authority", "xfer_authority"]:
		_check(not bool(Dictionary(config.get("authority", {})).get(key, true)), "shadow config forbids authority %s" % key)
	_check(not bool(Dictionary(config.get("promotion", {})).get("authorized", true)), "shadow promotion remains unauthorized")
	var denied := Shadow.request_authoritative_write("world", {"attempt": true})
	_check(not bool(denied.get("success", true)) and String(denied.get("error_code", "")) == "ECO_SHADOW_WRITE_FORBIDDEN", "authoritative write request fails closed")
	var fff7 = JSON.parse_string(FileAccess.get_file_as_string("res://config/ecology/research/evo7_fff7_xfer_gate.v1.json"))
	_check(typeof(fff7) == TYPE_DICTIONARY, "FFF7 gate still parses")
	if typeof(fff7) == TYPE_DICTIONARY:
		_check(not bool(fff7.get("fff7_activation_authorized", true)), "FFF7 activation remains false")
		_check(not bool(fff7.get("xfer_authorized", true)), "XFER remains false")
		_check(not bool(fff7.get("production_ecology_authority_authorized", true)), "production ecology authority remains false")

func _find_land_extremes(pipeline) -> Dictionary:
	var dry_moisture := INF
	var wet_moisture := -INF
	var dry_direction := Vector3.ZERO
	var wet_direction := Vector3.ZERO
	for lat_deg in [-65.0, -45.0, -25.0, -5.0, 15.0, 35.0, 55.0, 70.0]:
		for lon_deg in [-165.0, -120.0, -75.0, -30.0, 15.0, 60.0, 105.0, 150.0]:
			var lat := deg_to_rad(lat_deg)
			var lon := deg_to_rad(lon_deg)
			var direction := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)).normalized()
			var state: Dictionary = pipeline.sample(direction, 0)
			if int(state.get("water_kind", 1)) != 0 or float(state.get("land_mask", 0.0)) < 0.55:
				continue
			var moisture := float(state.get("moisture", NAN))
			if not is_finite(moisture):
				continue
			if moisture < dry_moisture:
				dry_moisture = moisture
				dry_direction = direction
			if moisture > wet_moisture:
				wet_moisture = moisture
				wet_direction = direction
	if dry_direction.length_squared() < 0.5 or wet_direction.length_squared() < 0.5:
		return {}
	return {"dry_direction": dry_direction, "wet_direction": wet_direction, "dry_moisture": dry_moisture, "wet_moisture": wet_moisture}

func _source_boundaries() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/ecology/shadow/eco_evo7_live_world_shadow_v1.gd").to_lower()
	_check(not source.contains("reproduce_bundle("), "shadow source never invokes lineage mutation authority")
	_check(not source.contains("production_ecology_authority_authorized\": true"), "shadow source cannot promote production authority")
	_check(source.contains("waterfield.compute"), "shadow consumes accepted bounded water field")
	_check(source.contains("stable_evaluation_seed_tag"), "shadow preserves accepted bundle-only realization identity")
	var observer := FileAccess.get_file_as_string("res://scripts/ecology/shadow/eco_evo7_live_world_shadow_observer_v1.gd").to_lower()
	_check(observer.contains("earth_rebuilt"), "runtime shadow observer binds to live Earth rebuild events")
	_check(observer.contains("request_authoritative_write"), "runtime observer exposes explicit fail-closed write boundary")
	var app_source := FileAccess.get_file_as_string("res://scripts/app/planetary_app.gd")
	_check(app_source.contains("EcoEvo7LiveWorldShadowObserver"), "planetary runtime instantiates live ecology shadow observer")
	_check(app_source.contains("eco_live_world_shadow_observer.setup(earth_world, simulation_clock)"), "planetary runtime binds observer only after real Earth setup")

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO7 Live World Shadow R1: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 LIVE SHADOW FAIL: %s" % failure)
	print("ECO.EVO7 Live World Shadow R1: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)

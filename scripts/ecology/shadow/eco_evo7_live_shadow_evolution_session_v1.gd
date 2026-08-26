extends RefCounted

## ECO.EVO7 LS1 - RAM-only evolutionary session over live ProceduralEarthWorld.
##
## Three copies of one common founder population are evaluated against three
## deterministic land samples from one regional Earth sector. Selection may
## diverge those copies, but stochastic mutation identity NEVER includes zone,
## moisture, light, water, or any other environmental value.
##
## The only reproduction entry point is LineageExtension.reproduce_bundle().
## This class owns no world, persistence, network, XFER, or alternate mutation
## authority. All session state disappears with this RefCounted instance.

const Shadow = preload("res://scripts/ecology/shadow/eco_evo7_live_world_shadow_v1.gd")
const Morphology = preload("res://scripts/research/ecology/evo7_morphology_evolution_bridge_v1.gd")
const LineageExtension = preload("res://scripts/research/ecology/plant_mutation_lineage_extension_evo7_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_live_shadow_evolution_session.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-LS1.1"
const MODE := "SHADOW_RAM_ONLY"
const POPULATION_SIZE := 12
const OFFSPRING_PER_PARENT := 2
const ZONE_COUNT := 3
const PATCH_MAX_RADIUS_DEG := 20.0
const PATCH_RING_DEGREES := [0.0, 4.0, 8.0, 12.0, 16.0, 20.0]
const PATCH_AZIMUTH_SAMPLES := 12
const ZONE_LABELS := ["DRY EDGE", "MID PATCH", "WET EDGE"]
const AUTHORITY := {
	"world_write": false,
	"ecology_write": false,
	"persistence_write": false,
	"network_replication_write": false,
	"xfer_authority": false,
	"alternate_mutation_authority": false,
}

var earth_world
var session_seed := 0
var generation := 0
var evolution_enabled := true
var zones: Array[Dictionary] = []
var populations: Array = []
var mutation_policy: Dictionary = {}
var first_candidate_pool_hashes: Array[String] = []
var initial_state_hash := ""
var initial_population_hash := ""
var initialized := false

func setup(earth_world_ref, seed: int = 20260826) -> bool:
	earth_world = earth_world_ref
	session_seed = seed
	generation = 0
	evolution_enabled = true
	zones.clear()
	populations.clear()
	first_candidate_pool_hashes.clear()
	initialized = false
	if earth_world == null or earth_world.get("pipeline") == null:
		return false
	mutation_policy = _policy()
	if LineageExtension.policy_hash(mutation_policy).is_empty():
		return false
	zones = _select_live_zones()
	if zones.size() != ZONE_COUNT:
		return false
	var common_population := _founder_population()
	if common_population.size() != POPULATION_SIZE:
		return false
	initial_population_hash = _population_bundle_hash(common_population)
	for _zone_index in ZONE_COUNT:
		populations.append(_deep_population_copy(common_population))
	initialized = true
	var snapshot := get_snapshot()
	if snapshot.is_empty():
		initialized = false
		return false
	initial_state_hash = String(snapshot["state_hash"])
	return true

func set_evolution_enabled(value: bool) -> void:
	evolution_enabled = value

func is_evolution_enabled() -> bool:
	return evolution_enabled

func step_generations(count: int = 1) -> Dictionary:
	if not initialized or count < 1:
		return {}
	for _step in count:
		generation += 1
		if evolution_enabled:
			if not _evolve_one_generation():
				return {}
		else:
			if not _evaluate_without_evolution():
				return {}
	return get_snapshot()

func reset_same_seed() -> Dictionary:
	if earth_world == null:
		return {}
	var seed := session_seed
	if not setup(earth_world, seed):
		return {}
	return get_snapshot()

func get_snapshot() -> Dictionary:
	if not initialized:
		return {}
	var zone_snapshots: Array[Dictionary] = []
	for zone_index in ZONE_COUNT:
		var observation := _observe_zone(zone_index)
		if observation.is_empty():
			return {}
		var evaluated := _evaluate_population(populations[zone_index], observation)
		if evaluated.size() != POPULATION_SIZE:
			return {}
		zone_snapshots.append(_zone_snapshot(zone_index, observation, evaluated))
	var snapshot := {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"mode": MODE,
		"shadow_only": true,
		"session_seed": session_seed,
		"generation": generation,
		"evolution_enabled": evolution_enabled,
		"population_size": POPULATION_SIZE,
		"offspring_per_parent": OFFSPRING_PER_PARENT,
		"patch_max_radius_deg": PATCH_MAX_RADIUS_DEG,
		"mutation_policy_hash": LineageExtension.policy_hash(mutation_policy),
		"initial_population_hash": initial_population_hash,
		"first_candidate_pool_hashes": first_candidate_pool_hashes.duplicate(),
		"authorities": AUTHORITY.duplicate(true),
		"zones": zone_snapshots,
	}
	snapshot["state_hash"] = _snapshot_hash(snapshot)
	return snapshot

func request_authoritative_write(surface: String, payload: Dictionary = {}) -> Dictionary:
	return Shadow.request_authoritative_write(surface, payload)

func _evolve_one_generation() -> bool:
	var next_populations: Array = []
	var generation_pool_hashes: Array[String] = []
	for zone_index in ZONE_COUNT:
		var candidates: Array[Dictionary] = []
		var mutation_tokens := PackedStringArray()
		var current: Array = populations[zone_index]
		for parent_index in current.size():
			var parent_bundle: Dictionary = current[parent_index]
			for offspring_index in OFFSPRING_PER_PARENT:
				var mutation_seed := _mutation_seed(generation, parent_index, offspring_index)
				var child := LineageExtension.reproduce_bundle(
					parent_bundle, mutation_seed, offspring_index, mutation_policy)
				if child.is_empty():
					return false
				var child_bundle: Dictionary = child["bundle"]
				candidates.append(child_bundle)
				mutation_tokens.append(String(child["result_hash"]))
		var pool_hash := "|".join(mutation_tokens).sha256_text()
		generation_pool_hashes.append(pool_hash)
		var observation := _observe_zone(zone_index)
		if observation.is_empty():
			return false
		var evaluated := _evaluate_population(candidates, observation)
		if evaluated.size() != POPULATION_SIZE * OFFSPRING_PER_PARENT:
			return false
		evaluated.sort_custom(_rank_order)
		var selected: Array[Dictionary] = []
		for i in POPULATION_SIZE:
			selected.append(Dictionary(evaluated[i]["bundle"]).duplicate(true))
		next_populations.append(selected)
	populations = next_populations
	if generation == 1:
		first_candidate_pool_hashes = generation_pool_hashes
	return true

func _evaluate_without_evolution() -> bool:
	## Evolution OFF means environmental plasticity/fitness can be observed while
	## exact heritable bundle identities remain unchanged.
	for zone_index in ZONE_COUNT:
		var observation := _observe_zone(zone_index)
		if observation.is_empty():
			return false
		var evaluated := _evaluate_population(populations[zone_index], observation)
		if evaluated.size() != POPULATION_SIZE:
			return false
	return true

func _evaluate_population(population: Array, observation: Dictionary) -> Array[Dictionary]:
	var evaluated: Array[Dictionary] = []
	for bundle_value in population:
		var bundle: Dictionary = bundle_value
		var result := Shadow.evaluate_bundle_against_observation(bundle, observation)
		if not bool(result.get("success", false)):
			return []
		evaluated.append({
			"bundle": bundle,
			"result": Dictionary(result["details"]),
		})
	return evaluated

func _observe_zone(zone_index: int) -> Dictionary:
	var zone: Dictionary = zones[zone_index]
	var observation_id := "ls1-live-%d-g%06d" % [zone_index, generation]
	var result := Shadow.observe_earth_world(
		earth_world, Vector3(zone["direction"]), float(generation), observation_id)
	return Dictionary(result["details"]) if bool(result.get("success", false)) else {}

func _select_live_zones() -> Array[Dictionary]:
	var center: Vector3 = earth_world.get("surface_center_direction")
	if center.length_squared() < 0.5 and earth_world.has_method("get_canonical_spawn_direction"):
		center = earth_world.call("get_canonical_spawn_direction")
	center = center.normalized()
	var east := Vector3.UP.cross(center).normalized()
	if east.length_squared() < 0.5:
		east = Vector3.RIGHT.cross(center).normalized()
	var north := center.cross(east).normalized()
	var samples: Array[Dictionary] = []
	for radius_deg in PATCH_RING_DEGREES:
		var radius := deg_to_rad(float(radius_deg))
		var azimuth_count := 1 if float(radius_deg) == 0.0 else PATCH_AZIMUTH_SAMPLES
		for azimuth_index in azimuth_count:
			var azimuth := TAU * float(azimuth_index) / float(azimuth_count)
			var tangent := east * cos(azimuth) + north * sin(azimuth)
			var direction := (center * cos(radius) + tangent * sin(radius)).normalized()
			var state: Dictionary = earth_world.pipeline.sample(direction, 0)
			if int(state.get("water_kind", 1)) != 0 or float(state.get("land_mask", 0.0)) < 0.55:
				continue
			samples.append({
				"direction": direction,
				"moisture": float(state.get("moisture", 0.0)),
				"temperature_c": float(state.get("temperature_c", 0.0)),
				"tree_density": float(state.get("tree_density", 0.0)),
				"radius_deg": float(radius_deg),
				"azimuth_index": azimuth_index,
			})
	if samples.size() < ZONE_COUNT:
		return []
	samples.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if absf(float(a["moisture"]) - float(b["moisture"])) > 1e-12:
			return float(a["moisture"]) < float(b["moisture"])
		if absf(float(a["radius_deg"]) - float(b["radius_deg"])) > 1e-12:
			return float(a["radius_deg"]) < float(b["radius_deg"])
		return int(a["azimuth_index"]) < int(b["azimuth_index"])
	)
	var indexes := [0, samples.size() / 2, samples.size() - 1]
	var selected: Array[Dictionary] = []
	for i in ZONE_COUNT:
		var item: Dictionary = samples[int(indexes[i])].duplicate(true)
		item["zone_index"] = i
		item["label"] = ZONE_LABELS[i]
		selected.append(item)
	return selected

func _founder_population() -> Array[Dictionary]:
	var founders: Array[Dictionary] = []
	for index in POPULATION_SIZE:
		## Different lineage IDs, identical starting genes/traits. The exact same
		## founder bundles are copied into every live zone.
		var bundle := Morphology.default_ancestor_bundle(session_seed + index)
		if bundle.is_empty():
			return []
		founders.append(bundle)
	return founders

func _zone_snapshot(zone_index: int, observation: Dictionary, evaluated: Array[Dictionary]) -> Dictionary:
	var sums := {
		"fitness": 0.0, "water": 0.0, "lai": 0.0, "root": 0.0,
		"height": 0.0, "crown": 0.0, "crown_density": 0.0,
		"root_shoot": 0.0, "structural": 0.0,
	}
	var lineage_counts := {}
	var members: Array[Dictionary] = []
	for item in evaluated:
		var bundle: Dictionary = item["bundle"]
		var result: Dictionary = item["result"]
		var lineage_id := String(bundle["lineage"]["lineage_id"])
		lineage_counts[lineage_id] = int(lineage_counts.get(lineage_id, 0)) + 1
		sums["fitness"] += float(result["shadow_fitness"])
		sums["water"] += float(result["water_satisfaction"])
		sums["lai"] += float(result["leaf_area_index_proxy"])
		sums["root"] += float(result["realized_root_depth_m"])
		sums["height"] += float(result["realized_height_m"])
		sums["crown"] += float(result["realized_crown_radius_m"])
		sums["crown_density"] += float(result["realized_crown_density"])
		sums["root_shoot"] += float(result["root_shoot_ratio"])
		sums["structural"] += float(result["structural_investment"])
		members.append({
			"bundle_checksum": String(bundle["bundle_checksum"]),
			"lineage_id": lineage_id,
			"individual_id": String(bundle["lineage"]["individual_id"]),
			"individual_seed": int(bundle["individual_seed"]),
			"fitness": float(result["shadow_fitness"]),
			"water_satisfaction": float(result["water_satisfaction"]),
			"leaf_area_index_proxy": float(result["leaf_area_index_proxy"]),
			"realized_root_depth_m": float(result["realized_root_depth_m"]),
			"realized_height_m": float(result["realized_height_m"]),
			"realized_crown_radius_m": float(result["realized_crown_radius_m"]),
			"realized_crown_density": float(result["realized_crown_density"]),
			"root_shoot_ratio": float(result["root_shoot_ratio"]),
			"structural_investment": float(result["structural_investment"]),
			"phenotype_hash": String(result["phenotype_hash"]),
		})
	var n := float(evaluated.size())
	var dominant := _dominant_lineage(lineage_counts)
	var env: Dictionary = observation["environment_sample"]
	return {
		"zone_index": zone_index,
		"label": String(zones[zone_index]["label"]),
		"direction": observation["direction"],
		"observation_hash": String(observation["observation_hash"]),
		"live_state_hash": String(observation["live_state_hash"]),
		"moisture": float(env["soil_moisture"]),
		"sunlight": float(env["sunlight"]),
		"temperature_c": float(env["temperature_c"]),
		"mean_water_satisfaction": float(sums["water"]) / n,
		"mean_fitness": float(sums["fitness"]) / n,
		"mean_lai": float(sums["lai"]) / n,
		"mean_root_depth_m": float(sums["root"]) / n,
		"mean_height_m": float(sums["height"]) / n,
		"mean_crown_radius_m": float(sums["crown"]) / n,
		"mean_crown_density": float(sums["crown_density"]) / n,
		"mean_root_shoot_ratio": float(sums["root_shoot"]) / n,
		"mean_structural_investment": float(sums["structural"]) / n,
		"dominant_lineage": dominant["lineage_id"],
		"dominant_lineage_count": dominant["count"],
		"population_hash": _population_bundle_hash(populations[zone_index]),
		"members": members,
	}

func _dominant_lineage(counts: Dictionary) -> Dictionary:
	var keys := counts.keys()
	keys.sort()
	var best_id := ""
	var best_count := -1
	for key_value in keys:
		var key := String(key_value)
		var count := int(counts[key])
		if count > best_count:
			best_count = count
			best_id = key
	return {"lineage_id": best_id, "count": best_count}

func _policy() -> Dictionary:
	## Same accepted authority and a deliberately observable but valid mutation
	## policy. Only parameter values change; mutation implementation does not.
	var policy := LineageExtension.default_policy()
	policy["morphology_probability"] = 0.48
	policy["genome_policy"]["mutation_probability"] = 0.48
	policy["genome_policy"]["root_depth_m_step"] = 0.40
	policy["genome_policy"]["shade_tolerance_step"] = 0.10
	return policy

func _mutation_seed(next_generation: int, parent_index: int, offspring_index: int) -> int:
	## CAUSALITY FENCE: never add zone/environment to this token.
	return ("ECO.EVO7-LS1|%d|%d|%d|%d" % [
		session_seed, next_generation, parent_index, offspring_index]).hash()

func _deep_population_copy(population: Array[Dictionary]) -> Array[Dictionary]:
	var copy: Array[Dictionary] = []
	for bundle in population:
		copy.append(bundle.duplicate(true))
	return copy

func _population_bundle_hash(population: Array) -> String:
	var tokens := PackedStringArray()
	for bundle_value in population:
		tokens.append(String(Dictionary(bundle_value).get("bundle_checksum", "")))
	return "|".join(tokens).sha256_text()

func _rank_order(a: Dictionary, b: Dictionary) -> bool:
	var fa := float(Dictionary(a["result"])["shadow_fitness"])
	var fb := float(Dictionary(b["result"])["shadow_fitness"])
	if absf(fa - fb) > 1e-12:
		return fa > fb
	return String(Dictionary(a["bundle"])["bundle_checksum"]) < String(Dictionary(b["bundle"])["bundle_checksum"])

func _snapshot_hash(snapshot: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA, VERSION, REVISION, MODE,
		str(int(snapshot.get("session_seed", 0))),
		str(int(snapshot.get("generation", -1))),
		"evo=1" if bool(snapshot.get("evolution_enabled", false)) else "evo=0",
		String(snapshot.get("initial_population_hash", "")),
		String(snapshot.get("mutation_policy_hash", "")),
	])
	for zone_value in Array(snapshot.get("zones", [])):
		var zone: Dictionary = zone_value
		tokens.append("%d|%s|%.9f|%.9f|%.9f|%.9f|%.9f|%s" % [
			int(zone["zone_index"]), String(zone["population_hash"]),
			float(zone["moisture"]), float(zone["sunlight"]),
			float(zone["mean_water_satisfaction"]), float(zone["mean_fitness"]),
			float(zone["mean_lai"]), String(zone["dominant_lineage"]),
		])
	return "|".join(tokens).sha256_text()

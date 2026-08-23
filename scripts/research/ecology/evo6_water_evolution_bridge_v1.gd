extends RefCounted

## ECO.EVO6-WATER/R1 - strong water selection over the accepted P1B mutation lineage.
## No second mutation path: all inheritance/mutation is delegated to MutationKernel.

const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const MutationKernel = preload("res://scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd")
const WaterFitness = preload("res://scripts/research/ecology/evo6_water_fitness_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo6_water_evolution_bridge.v1"
const VERSION := "1.0.0"
const DEFAULT_LINEAGE_SEED := 20260823
const DEFAULT_GENERATIONS := 36
const DEFAULT_POPULATION_SIZE := 18
const DEFAULT_OFFSPRING_PER_PARENT := 4


static func default_mutation_policy() -> Dictionary:
	var policy: Dictionary = MutationKernel.default_policy().duplicate(true)
	policy["mutation_probability"] = 0.52
	policy["water_preference_step"] = 0.12
	policy["root_depth_m_step"] = 0.40
	policy["growth_rate_step"] = 0.0
	policy["shade_tolerance_step"] = 0.0
	policy["seed_dispersal_distance_m_step"] = 0.0
	return policy


static func default_scenarios() -> Array[Dictionary]:
	return [
		{
			"id": "flooded",
			"features": {"in_water": true, "water_dist_m": 0.0},
			"effective_conditions": {"soil_moisture_ppm": 1000000},
		},
		{
			"id": "riparian",
			"features": {"water_dist_m": 1.5},
			"effective_conditions": {"soil_moisture_ppm": 650000},
		},
		{
			"id": "mesic",
			"features": {"water_dist_m": 8.0},
			"effective_conditions": {"soil_moisture_ppm": 400000},
		},
		{
			"id": "dry",
			"features": {"water_dist_m": 20.0},
			"effective_conditions": {"soil_moisture_ppm": 180000},
		},
	]


static func run_all(
	lineage_seed: int = DEFAULT_LINEAGE_SEED,
	generations: int = DEFAULT_GENERATIONS,
	population_size: int = DEFAULT_POPULATION_SIZE,
	offspring_per_parent: int = DEFAULT_OFFSPRING_PER_PARENT,
	scenarios: Array[Dictionary] = []
) -> Dictionary:
	var effective_scenarios := default_scenarios() if scenarios.is_empty() else scenarios.duplicate(true)
	if generations <= 0 or population_size <= 1 or offspring_per_parent <= 0 or effective_scenarios.size() < 2:
		return {}
	var policy := default_mutation_policy()
	if not bool(MutationKernel.validate_policy(policy).get("success", false)):
		return {}
	var ancestor := PlantGenome.create_default()
	if not bool(PlantGenome.validate(ancestor).get("success", false)):
		return {}
	var ancestor_lineage := MutationKernel.create_ancestor(ancestor, lineage_seed)
	if ancestor_lineage.is_empty():
		return {}

	var results := {}
	for scenario in effective_scenarios:
		var scenario_result := _run_scenario(
			scenario,
			ancestor,
			ancestor_lineage,
			lineage_seed,
			generations,
			population_size,
			offspring_per_parent,
			policy
		)
		if scenario_result.is_empty():
			return {}
		results[String(scenario["id"])] = scenario_result

	var first_candidate_pool_hash := ""
	var common_first_candidate_pool := true
	var final_hashes := {}
	for scenario_id in results.keys():
		var result: Dictionary = results[scenario_id]
		var history: Array = result["history"]
		if history.size() < 2:
			return {}
		var pool_hash := String(history[1].get("candidate_pool_hash", ""))
		if first_candidate_pool_hash.is_empty():
			first_candidate_pool_hash = pool_hash
		elif pool_hash != first_candidate_pool_hash:
			common_first_candidate_pool = false
		final_hashes[String(scenario_id)] = String(result["final_population_hash"])

	var distinct_final_populations := {}
	for final_hash in final_hashes.values():
		distinct_final_populations[String(final_hash)] = true

	var payload := {
		"schema": SCHEMA,
		"version": VERSION,
		"lineage_seed": lineage_seed,
		"generations": generations,
		"population_size": population_size,
		"offspring_per_parent": offspring_per_parent,
		"policy_hash": MutationKernel.policy_hash(policy),
		"ancestor_genome_checksum": String(ancestor["checksum"]),
		"scenarios": results,
		"metrics": {
			"common_first_candidate_pool": common_first_candidate_pool,
			"distinct_final_populations": distinct_final_populations.size(),
			"water_causes_evolutionary_divergence": distinct_final_populations.size() > 1,
		},
	}
	payload["result_hash"] = _result_hash(payload)
	return payload


static func _run_scenario(
	scenario: Dictionary,
	ancestor: Dictionary,
	ancestor_lineage: Dictionary,
	lineage_seed: int,
	generations: int,
	population_size: int,
	offspring_per_parent: int,
	policy: Dictionary
) -> Dictionary:
	var population: Array[Dictionary] = []
	for _index in range(population_size):
		population.append({"genome": ancestor.duplicate(true), "lineage": ancestor_lineage.duplicate(true)})
	var history: Array[Dictionary] = []
	history.append({"generation": 0, "selected_population_hash": _population_hash(population), "summary": _summary(population, scenario)})
	var mutation_events := 0

	for generation in range(1, generations + 1):
		var candidates: Array[Dictionary] = []
		for parent_index in range(population.size()):
			var parent: Dictionary = population[parent_index]
			for child_index in range(offspring_per_parent):
				var offspring_index := generation * 100000 + parent_index * 100 + child_index
				var mutation_seed := ("EVO6-WATER|%d|%d|%d|%d" % [lineage_seed, generation, parent_index, child_index]).hash()
				var child := MutationKernel.reproduce(parent["genome"], parent["lineage"], mutation_seed, offspring_index, policy)
				if child.is_empty():
					return {}
				mutation_events += int(child.get("mutation_count", 0))
				var entry := {"genome": child["genome"], "lineage": child["lineage"]}
				entry["fitness"] = float(WaterFitness.evaluate(entry["genome"], scenario)["fitness"])
				candidates.append(entry)
		var candidate_pool_hash := _population_hash(candidates)
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var af := float(a.get("fitness", 0.0))
			var bf := float(b.get("fitness", 0.0))
			if absf(af - bf) > 0.000000000001:
				return af > bf
			var ak := "%s|%s" % [String(a["genome"].get("checksum", "")), String(a["lineage"].get("checksum", ""))]
			var bk := "%s|%s" % [String(b["genome"].get("checksum", "")), String(b["lineage"].get("checksum", ""))]
			return ak < bk
		)
		population = []
		for index in range(min(population_size, candidates.size())):
			population.append({"genome": candidates[index]["genome"], "lineage": candidates[index]["lineage"]})
		if population.size() != population_size:
			return {}
		history.append({
			"generation": generation,
			"candidate_pool_hash": candidate_pool_hash,
			"selected_population_hash": _population_hash(population),
			"summary": _summary(population, scenario),
		})

	return {
		"scenario_id": String(scenario["id"]),
		"surface_water": WaterFitness.water_availability(scenario),
		"initial": history[0]["summary"],
		"final": history.back()["summary"],
		"mutation_events": mutation_events,
		"history": history,
		"final_population_hash": _population_hash(population),
	}


static func _summary(population: Array[Dictionary], scenario: Dictionary) -> Dictionary:
	var water_preference_total := 0.0
	var root_depth_total := 0.0
	var fitness_total := 0.0
	var unique := {}
	for entry in population:
		var genome: Dictionary = entry["genome"]
		water_preference_total += float(genome.get("water_preference", 0.0))
		root_depth_total += float(genome.get("root_depth_m", 0.0))
		fitness_total += float(WaterFitness.evaluate(genome, scenario)["fitness"])
		unique[String(genome.get("checksum", ""))] = true
	var count := float(max(1, population.size()))
	return {
		"population_count": population.size(),
		"mean_water_preference": water_preference_total / count,
		"mean_root_depth_m": root_depth_total / count,
		"mean_fitness": fitness_total / count,
		"unique_genomes": unique.size(),
	}


static func _population_hash(population: Array) -> String:
	var tokens := PackedStringArray([SCHEMA, VERSION, "population"])
	for raw_entry in population:
		var entry: Dictionary = raw_entry
		tokens.append("%s|%s" % [String(entry["genome"].get("checksum", "")), String(entry["lineage"].get("checksum", ""))])
	return "|".join(tokens).sha256_text()


static func _result_hash(payload: Dictionary) -> String:
	var tokens := PackedStringArray([SCHEMA, VERSION, str(int(payload["lineage_seed"])), str(int(payload["generations"]))])
	var scenario_ids: Array = (payload["scenarios"] as Dictionary).keys()
	scenario_ids.sort()
	for scenario_id in scenario_ids:
		var scenario: Dictionary = payload["scenarios"][scenario_id]
		var final: Dictionary = scenario["final"]
		tokens.append("%s|%s|%.9f|%.9f|%.9f" % [
			String(scenario_id),
			String(scenario["final_population_hash"]),
			float(final["mean_water_preference"]),
			float(final["mean_root_depth_m"]),
			float(final["mean_fitness"]),
		])
	return "|".join(tokens).sha256_text()

extends RefCounted

## ECO.EVO7 FFF2 - morphology evolution bridge: heritable form axes under selection.
## Pattern proven by EVO6-WATER (evo6_water_evolution_bridge_v1): one shared
## generation-one mutation candidate pool across all environments, fitness-based
## deterministic selection, distinct final populations.
##
## Fitness for R1: PlantFunctionalPhenotype.net_resource_proxy (component preview of
## spec section 11). No environment feedback yet (FFF3+ adds light/water channels).
## All inheritance goes through plant_mutation_lineage_extension_evo7_v1, which
## delegates genome heredity to plant_mutation_lineage_kernel_v1 (single authority).

const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const ExtensionTraits = preload("res://scripts/research/ecology/plant_development_traits_extension_evo7_v1.gd")
const Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const CoupledDevelopment = preload("res://scripts/research/ecology/plant_environment_coupled_development_v1.gd")
const FunctionalPhenotype = preload("res://scripts/research/ecology/plant_functional_phenotype_v1.gd")
const LineageExtension = preload("res://scripts/research/ecology/plant_mutation_lineage_extension_evo7_v1.gd")
const Fixture = preload("res://scripts/research/ecology/synthetic_environment_fixture_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_morphology_evolution_bridge.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-FFF2.1"

const SCENARIO_NAMES: Array[String] = [
	"wet_lowland", "sunny_slope", "shaded_slope", "dry_ridge", "plateau",
]
const BASELINE_SCENARIO := "plateau"

## Per-trait thresholds for "geometry-distinct" mean feature vectors (G5 numeric form;
## the C-neutral visual gate arrives with the FFF6 lab).
const GEOMETRY_THRESHOLDS := {
	"realized_height_m": 0.25,
	"realized_crown_radius_m": 0.20,
	"realized_crown_density": 0.04,
	"leaf_area_index_proxy": 0.05,
	"realized_root_depth_m": 0.25,
	"realized_root_spread_m": 0.25,
	"structural_investment": 0.04,
}
const FEATURE_FIELDS: Array[String] = [
	"realized_height_m", "realized_crown_radius_m", "realized_crown_density",
	"leaf_area_index_proxy", "realized_root_depth_m", "realized_root_spread_m",
	"structural_investment",
]

static func default_ancestor_bundle(lineage_seed: int) -> Dictionary:
	## Reference ancestor: branched, crowned (the default deterministic seed grows a
	## branchless pole with zero crown radius, which cannot express crown axes).
	var genome := Genome.create_default()
	var dev_traits := Traits.create(
		"plant-development/evo7-ancestor-ref", 3.2, 0.32, 0.62, 0.9, 42.0, 0.78, 4, 6.0)
	var ext_traits := ExtensionTraits.create_default()
	return LineageExtension.create_ancestor_bundle(genome, dev_traits, ext_traits, lineage_seed)

static func run_all(
	lineage_seed := 20260823,
	generations := 24,
	population_size := 18,
	offspring_per_parent := 4
) -> Dictionary:
	if generations < 1 or population_size < 2 or offspring_per_parent < 1:
		return {}
	var policy := LineageExtension.default_policy()
	var policy_id := LineageExtension.policy_hash(policy)
	if policy_id.is_empty():
		return {}
	var ancestor_template := default_ancestor_bundle(lineage_seed)
	if ancestor_template.is_empty():
		return {}

	var scenario_results := {}
	var pool_hashes := PackedStringArray()
	for scenario_name in SCENARIO_NAMES:
		var scenario := _run_scenario(
			ancestor_template, scenario_name, lineage_seed, generations,
			population_size, offspring_per_parent, policy)
		if scenario.is_empty():
			return {}
		pool_hashes.append(String(scenario["first_candidate_pool_hash"]))
		scenario_results[scenario_name] = scenario

	var common_pool := pool_hashes[0]
	for pool_hash in pool_hashes:
		if pool_hash != common_pool:
			return {}

	var distinct_population_pairs := 0
	var geometry_distinct_pairs := 0
	var baseline_features: Dictionary = scenario_results[BASELINE_SCENARIO]["mean_features"]
	var scenarios_distinct_from_baseline := 0
	for i in SCENARIO_NAMES.size():
		for j in range(i + 1, SCENARIO_NAMES.size()):
			var a: String = SCENARIO_NAMES[i]
			var b: String = SCENARIO_NAMES[j]
			if String(scenario_results[a]["final_population_hash"]) != String(scenario_results[b]["final_population_hash"]):
				distinct_population_pairs += 1
			if _geometry_distinct(scenario_results[a]["mean_features"], scenario_results[b]["mean_features"]):
				geometry_distinct_pairs += 1
	for scenario_name in SCENARIO_NAMES:
		if scenario_name == BASELINE_SCENARIO:
			continue
		if _geometry_distinct(scenario_results[scenario_name]["mean_features"], baseline_features):
			scenarios_distinct_from_baseline += 1

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"lineage_seed": lineage_seed,
		"generations": generations,
		"population_size": population_size,
		"offspring_per_parent": offspring_per_parent,
		"evo7_policy_hash": policy_id,
		"common_first_candidate_pool_hash": common_pool,
		"scenarios": scenario_results,
		"distinct_final_population_pairs": distinct_population_pairs,
		"geometry_distinct_pairs": geometry_distinct_pairs,
		"scenarios_distinct_from_baseline": scenarios_distinct_from_baseline,
	}
	result["result_hash"] = _result_hash(result)
	return result

static func _run_scenario(
	ancestor_template: Dictionary,
	scenario_name: String,
	lineage_seed: int,
	generations: int,
	population_size: int,
	offspring_per_parent: int,
	policy: Dictionary
) -> Dictionary:
	var env := Fixture.control_point(scenario_name, lineage_seed)
	var population: Array[Dictionary] = []
	for index in population_size:
		var individual_seed := Contract.derive_individual_seed(
			String(ancestor_template["lineage"]["lineage_id"]), "evo7-gen0|%d" % index, index,
			String(ancestor_template["genome"]["version"]))
		var bundle: Dictionary = ancestor_template.duplicate(true)
		bundle["individual_seed"] = individual_seed
		bundle["bundle_checksum"] = LineageExtension.bundle_checksum(
			bundle["genome"], bundle["dev_traits"], bundle["ext_traits"], bundle["lineage"], individual_seed)
		population.append(_evaluate(bundle, env))

	var first_pool_hash := ""
	for generation in range(1, generations + 1):
		var candidates: Array[Dictionary] = []
		var candidate_hashes := PackedStringArray()
		for parent_index in population.size():
			var parent: Dictionary = population[parent_index]
			for offspring_index in offspring_per_parent:
				var mutation_seed := ("EVO7-MORPHO|%d|%d|%d|%d" % [lineage_seed, generation, parent_index, offspring_index]).hash()
				var child_result := LineageExtension.reproduce_bundle(parent["bundle"], mutation_seed, offspring_index, policy)
				if child_result.is_empty():
					return {}
				var evaluated := _evaluate(child_result["bundle"], env)
				evaluated["result_hash"] = String(child_result["result_hash"])
				candidates.append(evaluated)
				candidate_hashes.append(String(child_result["result_hash"]))
		if generation == 1:
			first_pool_hash = "|".join(candidate_hashes).sha256_text()
		candidates.sort_custom(_rank_order)
		population = candidates.slice(0, population_size)

	var feature_sums := {}
	for field_name in FEATURE_FIELDS:
		feature_sums[field_name] = 0.0
	var fitness_sum := 0.0
	var checksums := PackedStringArray()
	for individual in population:
		fitness_sum += float(individual["fitness"])
		checksums.append(String(individual["bundle"]["bundle_checksum"]))
		for field_name in FEATURE_FIELDS:
			feature_sums[field_name] += float(individual["features"][field_name])
	var mean_features := {}
	for field_name in FEATURE_FIELDS:
		mean_features[field_name] = snappedf(float(feature_sums[field_name]) / float(population.size()), 1e-9)

	var unique_checksums := {}
	for checksum in checksums:
		unique_checksums[checksum] = true
	var final_population_hash := "|".join(_sorted_copy(checksums)).sha256_text()

	return {
		"scenario": scenario_name,
		"environment_checksum": String(env["checksum"]),
		"first_candidate_pool_hash": first_pool_hash,
		"mean_features": mean_features,
		"mean_fitness": snappedf(fitness_sum / float(population.size()), 1e-9),
		"unique_bundles": unique_checksums.size(),
		"final_population_hash": final_population_hash,
	}

static func _evaluate(bundle: Dictionary, env: Dictionary) -> Dictionary:
	var envelope := Contract.create_seed_envelope(
		bundle["genome"], bundle["dev_traits"],
		String(bundle["lineage"]["lineage_id"]),
		"evo7-eval|%d" % int(bundle["individual_seed"]), 0, 1.25)
	var ph2 := CoupledDevelopment.realize(envelope, bundle["dev_traits"], env)
	var fp := FunctionalPhenotype.compile({
		"genome": bundle["genome"],
		"ph2_realized": ph2,
		"traits_extension": bundle["ext_traits"],
		"environment_sample": env,
		"age_fraction": 1.0,
	})
	if fp.is_empty():
		return {"bundle": bundle, "fitness": -999.0, "features": {}}
	var features := {}
	for field_name in FEATURE_FIELDS:
		features[field_name] = float(fp[field_name])
	return {"bundle": bundle, "fitness": float(fp["net_resource_proxy"]), "features": features}

static func _rank_order(a: Dictionary, b: Dictionary) -> bool:
	if float(a["fitness"]) != float(b["fitness"]):
		return float(a["fitness"]) > float(b["fitness"])
	return String(a["bundle"]["bundle_checksum"]) < String(b["bundle"]["bundle_checksum"])

static func _geometry_distinct(a: Dictionary, b: Dictionary) -> bool:
	for field_name in FEATURE_FIELDS:
		if absf(float(a[field_name]) - float(b[field_name])) >= float(GEOMETRY_THRESHOLDS[field_name]):
			return true
	return false

static func _sorted_copy(values: PackedStringArray) -> PackedStringArray:
	var copy := values.duplicate()
	copy.sort()
	return copy

static func _result_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA, VERSION, String(result.get("revision", "")),
		str(int(result.get("lineage_seed", 0))),
		str(int(result.get("generations", 0))),
		str(int(result.get("population_size", 0))),
		str(int(result.get("offspring_per_parent", 0))),
		String(result.get("evo7_policy_hash", "")),
		String(result.get("common_first_candidate_pool_hash", "")),
	])
	for scenario_name in SCENARIO_NAMES:
		var scenario: Dictionary = result.get("scenarios", {}).get(scenario_name, {})
		tokens.append("%s:%s:%s:%d" % [
			scenario_name,
			String(scenario.get("first_candidate_pool_hash", "")),
			String(scenario.get("final_population_hash", "")),
			int(scenario.get("unique_bundles", 0)),
		])
	return "|".join(tokens).sha256_text()

extends RefCounted

const Fixture = preload("res://scripts/research/ecology/synthetic_environment_fixture_v1.gd")
const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const MutationKernel = preload("res://scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd")
const LineageRecord = preload("res://scripts/research/ecology/plant_lineage_record_v1.gd")
const ResourceModel = preload("res://scripts/research/ecology/plant_resource_model_v1.gd")
const PatchSimulator = preload("res://scripts/research/ecology/single_plant_patch_simulator_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.p1b_spatial_selection_baseline.v1"
const VERSION := "1.0.0"
const EXPERIMENT_REVISION := "ECO.P1B-S2.1"
const DEFAULT_LINEAGE_SEED := 781223
const DEFAULT_GENERATIONS := 16
const DEFAULT_POPULATION_SIZE := 12
const DEFAULT_OFFSPRING_PER_PARENT := 3
const DEFAULT_EVAL_SEASONS := 16
const DEFAULT_SITES: Array[String] = ["floodplain", "sunny_slope", "shaded_slope", "dry_ridge"]
const TRAITS: Array[String] = ["water_preference", "root_depth_m", "growth_rate", "shade_tolerance", "seed_dispersal_distance_m"]

static func selection_mutation_policy() -> Dictionary:
	var policy := MutationKernel.default_policy()
	policy["mutation_probability"] = 0.24
	policy["water_preference_step"] = 0.045
	policy["root_depth_m_step"] = 0.18
	policy["growth_rate_step"] = 0.045
	policy["shade_tolerance_step"] = 0.045
	# Dispersal benefit is not modeled until a migration/dispersal checkpoint.
	# Keep the inherited trait stable here instead of selecting only on its cost.
	policy["seed_dispersal_distance_m_step"] = 0.0
	return policy

static func run(
	site_names: Array[String] = DEFAULT_SITES,
	generations: int = DEFAULT_GENERATIONS,
	population_size: int = DEFAULT_POPULATION_SIZE,
	offspring_per_parent: int = DEFAULT_OFFSPRING_PER_PARENT,
	eval_seasons: int = DEFAULT_EVAL_SEASONS,
	lineage_seed: int = DEFAULT_LINEAGE_SEED
) -> Dictionary:
	if site_names.size() < 2 or generations <= 0 or population_size < 4 or offspring_per_parent < 2 or eval_seasons <= 0:
		return {}
	for site_name in site_names:
		if not Fixture.CONTROL_POINTS.has(site_name):
			return {}
	var ancestor_genome := PlantGenome.create_default()
	var ancestor_lineage := MutationKernel.create_ancestor(ancestor_genome, lineage_seed)
	if ancestor_lineage.is_empty():
		return {}
	var founders := _create_founders(ancestor_genome, ancestor_lineage, population_size, lineage_seed)
	if founders.size() != population_size:
		return {}
	var site_results := {}
	for site_name in site_names:
		var environment := Fixture.control_point(site_name)
		var site_result := _run_site(site_name, environment, founders, generations, population_size, offspring_per_parent, eval_seasons)
		if site_result.is_empty():
			return {}
		site_results[site_name] = site_result
	var cross_environment_net := _cross_environment_net(site_names, site_results)
	var trait_divergence := _trait_divergence(site_names, site_results)
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"experiment_revision": EXPERIMENT_REVISION,
		"lineage_seed": lineage_seed,
		"generations": generations,
		"population_size": population_size,
		"offspring_per_parent": offspring_per_parent,
		"eval_seasons": eval_seasons,
		"ancestor_genome_checksum": String(ancestor_genome["checksum"]),
		"ancestor_lineage_checksum": String(ancestor_lineage["checksum"]),
		"mutation_policy_hash": MutationKernel.policy_hash(selection_mutation_policy()),
		"site_order": site_names.duplicate(),
		"sites": site_results,
		"cross_environment_net": cross_environment_net,
		"trait_divergence": trait_divergence,
	}
	result["result_hash"] = _result_hash(result)
	return result

static func _cross_environment_net(site_names: Array[String], site_results: Dictionary) -> Dictionary:
	var matrix := {}
	for population_site in site_names:
		var row := {}
		var population: Array = site_results[population_site]["final_population"]
		for environment_site in site_names:
			var environment := Fixture.control_point(environment_site)
			var total := 0.0
			for entry in population:
				var balance := ResourceModel.evaluate(environment, entry["genome"], PatchSimulator.DEFAULT_INITIAL_BIOMASS_KG_M2)
				if balance.is_empty():
					return {}
				total += float(balance["net_resource_balance"])
			row[environment_site] = total / float(population.size())
		matrix[population_site] = row
	return matrix

static func _trait_divergence(site_names: Array[String], site_results: Dictionary) -> Dictionary:
	var result := {}
	for trait_name in TRAITS:
		var minimum := INF
		var maximum := -INF
		for site_name in site_names:
			var value := float(site_results[site_name]["final"]["trait_means"][trait_name])
			minimum = minf(minimum, value)
			maximum = maxf(maximum, value)
		result[trait_name] = maximum - minimum
	return result

static func _create_founders(ancestor_genome: Dictionary, ancestor_lineage: Dictionary, population_size: int, lineage_seed: int) -> Array:
	var policy := MutationKernel.default_policy()
	policy["mutation_probability"] = 0.0
	var founders: Array = []
	for index in range(population_size):
		var reproduction := MutationKernel.reproduce(ancestor_genome, ancestor_lineage, lineage_seed + 1000 + index, index, policy)
		if reproduction.is_empty():
			return []
		founders.append({"genome": reproduction["genome"], "lineage": reproduction["lineage"]})
	return founders

static func _run_site(site_name: String, environment: Dictionary, founders: Array, generations: int, population_size: int, offspring_per_parent: int, eval_seasons: int) -> Dictionary:
	var population: Array = founders.duplicate(true)
	var history: Array = []
	var initial_summary := _population_summary(population, environment, eval_seasons)
	if initial_summary.is_empty():
		return {}
	history.append(initial_summary)
	for generation_index in range(1, generations + 1):
		var candidates: Array = []
		for parent_index in range(population.size()):
			var parent: Dictionary = population[parent_index]
			for child_index in range(offspring_per_parent):
				var mutation_seed := _mutation_seed(generation_index, parent["lineage"], child_index)
				var reproduction := MutationKernel.reproduce(parent["genome"], parent["lineage"], mutation_seed, child_index, selection_mutation_policy())
				if reproduction.is_empty():
					return {}
				var consequence := _selection_consequence(environment, reproduction["genome"])
				if consequence.is_empty():
					return {}
				candidates.append({
					"genome": reproduction["genome"],
					"lineage": reproduction["lineage"],
					"consequence": consequence,
					"mutation_count": int(reproduction["mutation_count"]),
					"mutation_event_hash": String(reproduction["mutation_event_hash"]),
				})
		var candidate_pool_hash := _candidate_pool_hash(candidates)
		candidates.sort_custom(_candidate_before)
		population = []
		for selected_index in range(population_size):
			var selected: Dictionary = candidates[selected_index]
			population.append({"genome": selected["genome"], "lineage": selected["lineage"]})
		var summary := _population_summary(population, environment, eval_seasons)
		if summary.is_empty():
			return {}
		summary["candidate_count"] = candidates.size()
		summary["candidate_pool_hash"] = candidate_pool_hash
		summary["selected_population_hash"] = _population_identity_hash(population)
		summary["generation"] = generation_index
		history.append(summary)
	var result := {
		"site": site_name,
		"environment_checksum": String(environment["checksum"]),
		"initial": history[0],
		"final": history[history.size() - 1],
		"history": history,
		"final_population": population,
		"final_population_hash": _population_identity_hash(population),
	}
	result["site_hash"] = _site_hash(result)
	return result

static func _candidate_before(a: Dictionary, b: Dictionary) -> bool:
	var ca: Dictionary = a["consequence"]
	var cb: Dictionary = b["consequence"]
	var av := float(ca["net_resource_balance"])
	var bv := float(cb["net_resource_balance"])
	if absf(av - bv) > 0.000000000001:
		return av > bv
	return String(a["lineage"]["checksum"]) < String(b["lineage"]["checksum"])

static func _selection_consequence(environment: Dictionary, genome: Dictionary) -> Dictionary:
	var balance := ResourceModel.evaluate(environment, genome, PatchSimulator.DEFAULT_INITIAL_BIOMASS_KG_M2)
	if balance.is_empty():
		return {}
	return {
		"net_resource_balance": float(balance["net_resource_balance"]),
		"viability_class": String(balance["viability_class"]),
		"dominant_limiting_factor": String(balance["dominant_limiting_factor"]),
		"balance_checksum": String(balance["checksum"]),
	}

static func _population_summary(population: Array, environment: Dictionary, eval_seasons: int) -> Dictionary:
	if population.is_empty():
		return {}
	var trait_sums := {}
	for trait_name in TRAITS:
		trait_sums[trait_name] = 0.0
	var total_recruitment := 0.0
	var total_biomass := 0.0
	var total_net := 0.0
	var productive_total := 0
	var tokens := PackedStringArray()
	for entry in population:
		var genome: Dictionary = entry["genome"]
		var lineage: Dictionary = entry["lineage"]
		if not bool(PlantGenome.validate(genome).get("success", false)) or not bool(LineageRecord.validate(lineage).get("success", false)):
			return {}
		var simulation := PatchSimulator.simulate(environment, genome, eval_seasons, PatchSimulator.DEFAULT_INITIAL_BIOMASS_KG_M2)
		if simulation.is_empty():
			return {}
		for trait_name in TRAITS:
			trait_sums[trait_name] = float(trait_sums[trait_name]) + float(genome[trait_name])
		total_recruitment += float(simulation["cumulative_recruitment_kg_m2"])
		total_biomass += float(simulation["final_biomass_kg_m2"])
		total_net += float(simulation["final_net_resource_balance"])
		productive_total += int(simulation["productive_seasons"])
		tokens.append("%s|%s|%s" % [String(lineage["checksum"]), String(genome["checksum"]), String(simulation["checksum"])])
	var trait_means := {}
	for trait_name in TRAITS:
		trait_means[trait_name] = float(trait_sums[trait_name]) / float(population.size())
	var result := {
		"population_count": population.size(),
		"trait_means": trait_means,
		"average_recruitment_kg_m2": total_recruitment / float(population.size()),
		"average_final_biomass_kg_m2": total_biomass / float(population.size()),
		"average_final_net_resource_balance": total_net / float(population.size()),
		"average_productive_seasons": float(productive_total) / float(population.size()),
	}
	result["summary_hash"] = "\n".join(tokens).sha256_text()
	return result

static func _mutation_seed(generation_index: int, parent_lineage: Dictionary, child_index: int) -> int:
	var payload := "%s|%d|%s|%d" % [EXPERIMENT_REVISION, generation_index, String(parent_lineage["individual_id"]), child_index]
	return int(payload.sha256_text().substr(0, 8).hex_to_int())

static func _candidate_pool_hash(candidates: Array) -> String:
	var tokens := PackedStringArray()
	for candidate in candidates:
		tokens.append("%s|%s|%s" % [
			String(candidate["lineage"]["checksum"]),
			String(candidate["genome"]["checksum"]),
			String(candidate["mutation_event_hash"]),
		])
	return "\n".join(tokens).sha256_text()

static func _population_identity_hash(population: Array) -> String:
	var tokens := PackedStringArray()
	for entry in population:
		tokens.append("%s|%s" % [String(entry["lineage"]["checksum"]), String(entry["genome"]["checksum"])])
	return "\n".join(tokens).sha256_text()

static func _site_hash(site: Dictionary) -> String:
	var tokens := PackedStringArray([
		EXPERIMENT_REVISION,
		String(site.get("site", "")),
		String(site.get("environment_checksum", "")),
		String(site.get("final_population_hash", "")),
	])
	var history: Array = site.get("history", [])
	for summary in history:
		tokens.append(_summary_token(summary))
	return "\n".join(tokens).sha256_text()

static func _result_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		EXPERIMENT_REVISION,
		str(int(result.get("lineage_seed", 0))),
		str(int(result.get("generations", 0))),
		str(int(result.get("population_size", 0))),
		str(int(result.get("offspring_per_parent", 0))),
		str(int(result.get("eval_seasons", 0))),
		String(result.get("ancestor_genome_checksum", "")),
		String(result.get("ancestor_lineage_checksum", "")),
		String(result.get("mutation_policy_hash", "")),
	])
	for site_name in result.get("site_order", []):
		tokens.append("%s=%s" % [String(site_name), String(result["sites"][site_name]["site_hash"])])
	var matrix: Dictionary = result.get("cross_environment_net", {})
	for population_site in result.get("site_order", []):
		for environment_site in result.get("site_order", []):
			tokens.append("cross:%s:%s=%s" % [population_site, environment_site, _format_float(float(matrix[population_site][environment_site]))])
	var divergence: Dictionary = result.get("trait_divergence", {})
	for trait_name in TRAITS:
		tokens.append("divergence:%s=%s" % [trait_name, _format_float(float(divergence.get(trait_name, 0.0)))])
	return "\n".join(tokens).sha256_text()

static func _summary_token(summary: Dictionary) -> String:
	var parts := PackedStringArray([
		str(int(summary.get("generation", 0))),
		_format_float(float(summary.get("average_recruitment_kg_m2", 0.0))),
		_format_float(float(summary.get("average_final_biomass_kg_m2", 0.0))),
		_format_float(float(summary.get("average_final_net_resource_balance", 0.0))),
		_format_float(float(summary.get("average_productive_seasons", 0.0))),
		String(summary.get("summary_hash", "")),
		String(summary.get("candidate_pool_hash", "")),
		String(summary.get("selected_population_hash", "")),
	])
	var means: Dictionary = summary.get("trait_means", {})
	for trait_name in TRAITS:
		parts.append("%s=%s" % [trait_name, _format_float(float(means.get(trait_name, 0.0)))])
	return "|".join(parts)

static func _format_float(value: float) -> String:
	return "%.9f" % value

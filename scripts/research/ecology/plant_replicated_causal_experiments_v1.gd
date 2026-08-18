extends RefCounted

const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const MutationKernel = preload("res://scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd")
const LineageRecord = preload("res://scripts/research/ecology/plant_lineage_record_v1.gd")
const ResourceModel = preload("res://scripts/research/ecology/plant_resource_model_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo2_replicated_causal_experiments.v1"
const VERSION := "1.0.0"
const PARENT_E2_5_ACCEPTED_AGGREGATE := "942ad54e7672c4f57874e1802b320c1b2a4aa74e43b05f7e285793ea4ec8b2a6"
const PARENT_E2_5_CODE_UNDER_TEST := "4c17a91957e392eabc04e136f9590773dbe54dd1"
const PARENT_E2_4_ACCEPTED_AGGREGATE := "ae2952de10ac721c8052694963b690d9f72af05d9c92e2fa4cd70e00f72fb2b5"
const PARENT_E2_4_PLAN_HASH := "f688eb014245d63483562376c3f5db8c08a85bdc35feb52428f5ff17753f82e0"
const E2_2_BAKE_HASH := "45496eb67aac5cc0a65babfeb0c49fa99616df17c2f7e8b9e8b95d04cb2b4e5b"
const E2_2_CATALOG_HASH := "5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219"
const E2_5_CONTROL_POLICY_HASH := "0e6481175af3658b2673a612717dd850b917ec5156260b37bd9ee29a9789dc4e"
const E2_5_TREATMENT_POLICY_HASH := "e2927ce7a8f6b3ab5f3d4942a2cc70ca3794e0d67c3e770e0301748967c14416"
const TARGET_CELLS: Array[String] = ["DRY", "WET"]
const REPLICATE_IDS: Array[String] = ["R01", "R02", "R03", "R04", "R05"]
const REQUIRED_POSITIVE_REPLICATES := 4
const REQUIRED_HOME_ADVANTAGE_REPLICATES := 4
const GENERATIONS := 10
const POPULATION_SIZE := 8
const OFFSPRING_PER_PARENT := 4
const EVALUATION_BIOMASS_KG_M2 := 0.05
const EPSILON := 0.000000001
const CENSORING_ALLOWED := false
const SIGNIFICANCE_CLAIMED := false
const CROSS_SEED_ROBUSTNESS_CLAIMED := false
const CANONICAL_SPECIES_DECLARED := false
const PRODUCTION_AUTHORITY_CLAIMED := false
const TRAITS: Array[String] = ["water_preference", "root_depth_m", "growth_rate", "shade_tolerance", "seed_dispersal_distance_m"]

const RESULT_FIELDS: Array[String] = [
	"schema", "version", "parent_e2_5_accepted_aggregate", "parent_e2_5_code_under_test",
	"parent_e2_4_accepted_aggregate", "parent_e2_4_plan_hash", "e2_2_bake_hash", "catalog_hash",
	"control_policy_hash", "treatment_policy_hash", "target_cells", "replicate_ids", "replicate_set_hash",
	"required_positive_replicates", "required_home_advantage_replicates", "generations", "population_size",
	"offspring_per_parent", "censoring_allowed", "all_replicates_retained", "significance_claimed",
	"cross_seed_robustness_claimed", "canonical_species_declared", "production_authority_claimed",
	"frozen_strategies", "environments", "replicates", "cell_aggregates", "aggregate_hash",
]
const STRATEGY_FIELDS: Array[String] = ["research_species_id", "source_lineage_id", "genome", "genome_checksum"]
const REPLICATE_FIELDS: Array[String] = ["replicate_id", "cells", "cross_environment", "replicate_hash"]
const CELL_FIELDS: Array[String] = [
	"cell_id", "environment_checksum", "initial_population_hash", "control", "treatment", "sorting_detected",
	"sorting_gain", "adaptation_gain", "classification", "positive_adaptation_effect", "home_value", "away_value",
	"home_advantage", "paired_hash",
]
const ARM_FIELDS: Array[String] = ["arm", "adaptation_enabled", "policy_hash", "initial", "final", "history", "selected_mutation_events", "final_population", "arm_hash"]
const SUMMARY_FIELDS: Array[String] = ["generation", "average_net_resource_balance", "best_net_resource_balance", "lineage_counts", "trait_means", "unique_genome_count", "novel_genome_count", "population_hash"]
const EVENT_FIELDS: Array[String] = ["generation", "research_species_id", "source_lineage_id", "individual_id", "parent_genome_checksum", "child_genome_checksum", "mutation_count", "mutation_event_hash"]
const AGGREGATE_FIELDS: Array[String] = [
	"cell_id", "replicate_count", "adaptation_gains", "mean_adaptation_gain", "median_adaptation_gain",
	"minimum_adaptation_gain", "maximum_adaptation_gain", "positive_adaptation_count", "nonpositive_adaptation_count",
	"home_advantage_count", "home_advantage_fail_count", "classification_counts", "replicated_signal_pass",
	"cell_aggregate_hash",
]


static func control_policy() -> Dictionary:
	var policy := treatment_policy()
	policy["mutation_probability"] = 0.0
	return policy


static func treatment_policy() -> Dictionary:
	return {
		"mutation_probability": 0.30,
		"water_preference_step": 0.055,
		"root_depth_m_step": 0.20,
		"growth_rate_step": 0.045,
		"shade_tolerance_step": 0.045,
		"seed_dispersal_distance_m_step": 0.0,
	}


static func run() -> Dictionary:
	var strategies := _frozen_strategies()
	var environments := _environments()
	if strategies.size() != 2 or environments.size() != TARGET_CELLS.size():
		return {}
	var control_policy_value := control_policy()
	var treatment_policy_value := treatment_policy()
	if MutationKernel.policy_hash(control_policy_value) != E2_5_CONTROL_POLICY_HASH:
		return {}
	if MutationKernel.policy_hash(treatment_policy_value) != E2_5_TREATMENT_POLICY_HASH:
		return {}
	var replicates: Array = []
	for replicate_id in REPLICATE_IDS:
		var replicate := _run_replicate(replicate_id, strategies, environments, control_policy_value, treatment_policy_value)
		if replicate.is_empty():
			return {}
		replicates.append(replicate)
	var cell_aggregates: Array = []
	for cell_id in TARGET_CELLS:
		var summary := _aggregate_cell(replicates, cell_id)
		if summary.is_empty():
			return {}
		cell_aggregates.append(summary)
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"parent_e2_5_accepted_aggregate": PARENT_E2_5_ACCEPTED_AGGREGATE,
		"parent_e2_5_code_under_test": PARENT_E2_5_CODE_UNDER_TEST,
		"parent_e2_4_accepted_aggregate": PARENT_E2_4_ACCEPTED_AGGREGATE,
		"parent_e2_4_plan_hash": PARENT_E2_4_PLAN_HASH,
		"e2_2_bake_hash": E2_2_BAKE_HASH,
		"catalog_hash": E2_2_CATALOG_HASH,
		"control_policy_hash": MutationKernel.policy_hash(control_policy_value),
		"treatment_policy_hash": MutationKernel.policy_hash(treatment_policy_value),
		"target_cells": TARGET_CELLS.duplicate(),
		"replicate_ids": REPLICATE_IDS.duplicate(),
		"replicate_set_hash": compute_replicate_set_hash(REPLICATE_IDS),
		"required_positive_replicates": REQUIRED_POSITIVE_REPLICATES,
		"required_home_advantage_replicates": REQUIRED_HOME_ADVANTAGE_REPLICATES,
		"generations": GENERATIONS,
		"population_size": POPULATION_SIZE,
		"offspring_per_parent": OFFSPRING_PER_PARENT,
		"censoring_allowed": CENSORING_ALLOWED,
		"all_replicates_retained": replicates.size() == REPLICATE_IDS.size(),
		"significance_claimed": SIGNIFICANCE_CLAIMED,
		"cross_seed_robustness_claimed": CROSS_SEED_ROBUSTNESS_CLAIMED,
		"canonical_species_declared": CANONICAL_SPECIES_DECLARED,
		"production_authority_claimed": PRODUCTION_AUTHORITY_CLAIMED,
		"frozen_strategies": strategies,
		"environments": environments,
		"replicates": replicates,
		"cell_aggregates": cell_aggregates,
	}
	result["aggregate_hash"] = compute_aggregate_hash(result)
	return result


static func validate_result(result: Dictionary) -> bool:
	if not _exact(result, RESULT_FIELDS):
		return false
	if String(result.get("schema", "")) != SCHEMA or String(result.get("version", "")) != VERSION:
		return false
	if String(result.get("parent_e2_5_accepted_aggregate", "")) != PARENT_E2_5_ACCEPTED_AGGREGATE or String(result.get("parent_e2_5_code_under_test", "")) != PARENT_E2_5_CODE_UNDER_TEST:
		return false
	if String(result.get("parent_e2_4_accepted_aggregate", "")) != PARENT_E2_4_ACCEPTED_AGGREGATE or String(result.get("parent_e2_4_plan_hash", "")) != PARENT_E2_4_PLAN_HASH:
		return false
	if String(result.get("e2_2_bake_hash", "")) != E2_2_BAKE_HASH or String(result.get("catalog_hash", "")) != E2_2_CATALOG_HASH:
		return false
	if String(result.get("control_policy_hash", "")) != E2_5_CONTROL_POLICY_HASH or String(result.get("treatment_policy_hash", "")) != E2_5_TREATMENT_POLICY_HASH:
		return false
	if Array(result.get("target_cells", [])) != TARGET_CELLS or Array(result.get("replicate_ids", [])) != REPLICATE_IDS:
		return false
	if String(result.get("replicate_set_hash", "")) != compute_replicate_set_hash(REPLICATE_IDS):
		return false
	if int(result.get("required_positive_replicates", -1)) != REQUIRED_POSITIVE_REPLICATES or int(result.get("required_home_advantage_replicates", -1)) != REQUIRED_HOME_ADVANTAGE_REPLICATES:
		return false
	if int(result.get("generations", -1)) != GENERATIONS or int(result.get("population_size", -1)) != POPULATION_SIZE or int(result.get("offspring_per_parent", -1)) != OFFSPRING_PER_PARENT:
		return false
	if bool(result.get("censoring_allowed", true)) or not bool(result.get("all_replicates_retained", false)):
		return false
	if bool(result.get("significance_claimed", true)) or bool(result.get("cross_seed_robustness_claimed", true)) or bool(result.get("canonical_species_declared", true)) or bool(result.get("production_authority_claimed", true)):
		return false
	if typeof(result.get("frozen_strategies")) != TYPE_ARRAY or Array(result["frozen_strategies"]) != _frozen_strategies():
		return false
	if typeof(result.get("environments")) != TYPE_DICTIONARY or Dictionary(result["environments"]) != _environments():
		return false
	if typeof(result.get("replicates")) != TYPE_ARRAY or Array(result["replicates"]).size() != REPLICATE_IDS.size():
		return false
	for index in range(REPLICATE_IDS.size()):
		var replicate_value = Array(result["replicates"])[index]
		if typeof(replicate_value) != TYPE_DICTIONARY:
			return false
		var replicate: Dictionary = replicate_value
		if not _replicate_shape_valid(replicate) or String(replicate["replicate_id"]) != REPLICATE_IDS[index]:
			return false
	if typeof(result.get("cell_aggregates")) != TYPE_ARRAY or Array(result["cell_aggregates"]).size() != TARGET_CELLS.size():
		return false
	for index in range(TARGET_CELLS.size()):
		var aggregate_value = Array(result["cell_aggregates"])[index]
		if typeof(aggregate_value) != TYPE_DICTIONARY:
			return false
		var aggregate: Dictionary = aggregate_value
		if not _aggregate_shape_valid(aggregate) or String(aggregate["cell_id"]) != TARGET_CELLS[index]:
			return false
	if String(result.get("aggregate_hash", "")) != compute_aggregate_hash(result):
		return false
	var expected := run()
	return not expected.is_empty() and expected == result


static func compute_replicate_set_hash(replicate_ids: Array[String]) -> String:
	return "\n".join(PackedStringArray([SCHEMA, VERSION, "replicate-set"] + replicate_ids)).sha256_text()


static func compute_aggregate_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA, VERSION, PARENT_E2_5_ACCEPTED_AGGREGATE, PARENT_E2_5_CODE_UNDER_TEST,
		PARENT_E2_4_ACCEPTED_AGGREGATE, PARENT_E2_4_PLAN_HASH, E2_2_BAKE_HASH, E2_2_CATALOG_HASH,
		String(result.get("control_policy_hash", "")), String(result.get("treatment_policy_hash", "")),
		String(result.get("replicate_set_hash", "")),
		"positive-threshold=%d" % int(result.get("required_positive_replicates", 0)),
		"home-threshold=%d" % int(result.get("required_home_advantage_replicates", 0)),
	])
	for value in Array(result.get("replicates", [])):
		tokens.append(String(Dictionary(value).get("replicate_hash", "")))
	for value in Array(result.get("cell_aggregates", [])):
		tokens.append(String(Dictionary(value).get("cell_aggregate_hash", "")))
	return "\n".join(tokens).sha256_text()


static func _run_replicate(replicate_id: String, strategies: Array, environments: Dictionary, control_policy_value: Dictionary, treatment_policy_value: Dictionary) -> Dictionary:
	if not replicate_id in REPLICATE_IDS:
		return {}
	var cells: Array = []
	var treatment_populations := {}
	for cell_id in TARGET_CELLS:
		var environment: Dictionary = Dictionary(environments[cell_id])
		var founders := _founders(strategies, cell_id)
		if founders.size() != POPULATION_SIZE:
			return {}
		var control := _run_arm(founders, environment, cell_id, replicate_id, "CONTROL", false, control_policy_value, strategies)
		var treatment := _run_arm(founders, environment, cell_id, replicate_id, "TREATMENT", true, treatment_policy_value, strategies)
		if control.is_empty() or treatment.is_empty():
			return {}
		if String(Dictionary(control["initial"])["population_hash"]) != String(Dictionary(treatment["initial"])["population_hash"]):
			return {}
		var sorting_detected := Dictionary(Dictionary(control["final"])["lineage_counts"]) != Dictionary(Dictionary(control["initial"])["lineage_counts"])
		var sorting_gain := float(Dictionary(control["final"])["average_net_resource_balance"]) - float(Dictionary(control["initial"])["average_net_resource_balance"])
		var adaptation_gain := float(Dictionary(treatment["final"])["average_net_resource_balance"]) - float(Dictionary(control["final"])["average_net_resource_balance"])
		var novel := int(Dictionary(treatment["final"])["novel_genome_count"]) > 0
		var classification := _classification(sorting_detected, novel, adaptation_gain)
		var cell := {
			"cell_id": cell_id,
			"environment_checksum": String(environment["checksum"]),
			"initial_population_hash": String(Dictionary(control["initial"])["population_hash"]),
			"control": control,
			"treatment": treatment,
			"sorting_detected": sorting_detected,
			"sorting_gain": sorting_gain,
			"adaptation_gain": adaptation_gain,
			"classification": classification,
			"positive_adaptation_effect": novel and adaptation_gain > EPSILON,
			"home_value": 0.0,
			"away_value": 0.0,
			"home_advantage": false,
		}
		cells.append(cell)
		treatment_populations[cell_id] = Array(treatment["final_population"]).duplicate(true)
	var cross := _cross_environment(treatment_populations, environments)
	if cross.is_empty():
		return {}
	for cell in cells:
		var cell_id := String(cell["cell_id"])
		var away_id := "WET" if cell_id == "DRY" else "DRY"
		cell["home_value"] = float(Dictionary(cross[cell_id])[cell_id])
		cell["away_value"] = float(Dictionary(cross[away_id])[cell_id])
		cell["home_advantage"] = float(cell["home_value"]) > float(cell["away_value"]) + EPSILON
		cell["paired_hash"] = _paired_hash(cell)
	var replicate := {"replicate_id": replicate_id, "cells": cells, "cross_environment": cross}
	replicate["replicate_hash"] = _replicate_hash(replicate)
	return replicate


static func _run_arm(founders: Array, environment: Dictionary, cell_id: String, replicate_id: String, arm_id: String, adaptation_enabled: bool, policy: Dictionary, strategies: Array) -> Dictionary:
	var population := founders.duplicate(true)
	var frozen_checksums := _frozen_checksums(strategies)
	var history: Array = []
	var initial := _summary(population, environment, 0, frozen_checksums)
	if initial.is_empty():
		return {}
	history.append(initial)
	var selected_events: Array = []
	for generation in range(1, GENERATIONS + 1):
		var candidates: Array = []
		for parent_index in range(population.size()):
			var parent: Dictionary = population[parent_index]
			for child_index in range(OFFSPRING_PER_PARENT):
				var offspring_index := parent_index * OFFSPRING_PER_PARENT + child_index
				var mutation_seed := _stable_seed(replicate_id, cell_id, generation, offspring_index, String(Dictionary(parent["lineage"])["checksum"]))
				var reproduction := MutationKernel.reproduce(Dictionary(parent["genome"]), Dictionary(parent["lineage"]), mutation_seed, offspring_index, policy)
				if reproduction.is_empty() or not bool(MutationKernel.validate_result(reproduction).get("success", false)):
					return {}
				var balance := ResourceModel.evaluate(environment, Dictionary(reproduction["genome"]), EVALUATION_BIOMASS_KG_M2)
				if balance.is_empty():
					return {}
				candidates.append({
					"research_species_id": String(parent["research_species_id"]),
					"source_lineage_id": String(parent["source_lineage_id"]),
					"frozen_genome_checksum": String(parent["frozen_genome_checksum"]),
					"genome": Dictionary(reproduction["genome"]),
					"lineage": Dictionary(reproduction["lineage"]),
					"net": float(balance["net_resource_balance"]),
					"mutation_count": int(reproduction["mutation_count"]),
					"mutation_event_hash": String(reproduction["mutation_event_hash"]),
					"parent_genome_checksum": String(reproduction["parent_genome_checksum"]),
				})
		candidates.sort_custom(_candidate_before)
		population = []
		for selected_index in range(POPULATION_SIZE):
			var selected: Dictionary = candidates[selected_index]
			population.append({
				"research_species_id": selected["research_species_id"],
				"source_lineage_id": selected["source_lineage_id"],
				"frozen_genome_checksum": selected["frozen_genome_checksum"],
				"genome": selected["genome"],
				"lineage": selected["lineage"],
			})
			if int(selected["mutation_count"]) > 0:
				selected_events.append({
					"generation": generation,
					"research_species_id": String(selected["research_species_id"]),
					"source_lineage_id": String(selected["source_lineage_id"]),
					"individual_id": String(Dictionary(selected["lineage"])["individual_id"]),
					"parent_genome_checksum": String(selected["parent_genome_checksum"]),
					"child_genome_checksum": String(Dictionary(selected["genome"])["checksum"]),
					"mutation_count": int(selected["mutation_count"]),
					"mutation_event_hash": String(selected["mutation_event_hash"]),
				})
		var summary := _summary(population, environment, generation, frozen_checksums)
		if summary.is_empty():
			return {}
		history.append(summary)
	var arm := {
		"arm": arm_id,
		"adaptation_enabled": adaptation_enabled,
		"policy_hash": MutationKernel.policy_hash(policy),
		"initial": initial,
		"final": history[history.size() - 1],
		"history": history,
		"selected_mutation_events": selected_events,
		"final_population": population,
	}
	arm["arm_hash"] = _arm_hash(arm)
	return arm


static func _founders(strategies: Array, cell_id: String) -> Array:
	if strategies.size() != 2 or POPULATION_SIZE % strategies.size() != 0:
		return []
	var copies := POPULATION_SIZE / strategies.size()
	var founders: Array = []
	for strategy_value in strategies:
		var strategy: Dictionary = strategy_value
		var genome: Dictionary = Dictionary(strategy["genome"])
		for local_index in range(copies):
			var context := "%s|%s|%s|%d" % [SCHEMA, cell_id, String(strategy["research_species_id"]), local_index]
			var seed_value := _stable_seed("FOUNDER", cell_id, 0, local_index, context)
			var individual_id := "eco-individual/%s" % context.sha256_text().substr(0, 24)
			var lineage := LineageRecord.create(
				String(strategy["source_lineage_id"]), individual_id, "", 0, local_index, seed_value, "",
				String(genome["checksum"]), ("founder|" + context).sha256_text()
			)
			if not bool(LineageRecord.validate(lineage).get("success", false)):
				return []
			founders.append({
				"research_species_id": String(strategy["research_species_id"]),
				"source_lineage_id": String(strategy["source_lineage_id"]),
				"frozen_genome_checksum": String(strategy["genome_checksum"]),
				"genome": genome.duplicate(true),
				"lineage": lineage,
			})
	founders.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var aid := String(a["research_species_id"])
		var bid := String(b["research_species_id"])
		if aid != bid:
			return aid < bid
		return String(Dictionary(a["lineage"])["checksum"]) < String(Dictionary(b["lineage"])["checksum"])
	)
	return founders


static func _summary(population: Array, environment: Dictionary, generation: int, frozen_checksums: Dictionary) -> Dictionary:
	if population.size() != POPULATION_SIZE:
		return {}
	var total_net := 0.0
	var best_net := -INF
	var counts := {}
	var trait_sums := {}
	for trait_name in TRAITS:
		trait_sums[trait_name] = 0.0
	var genomes := {}
	var novel := {}
	var tokens := PackedStringArray()
	for value in population:
		var entry: Dictionary = value
		var genome: Dictionary = entry.get("genome", {})
		var lineage: Dictionary = entry.get("lineage", {})
		if not bool(PlantGenome.validate(genome).get("success", false)) or not bool(LineageRecord.validate(lineage).get("success", false)):
			return {}
		if String(lineage.get("lineage_id", "")) != String(entry.get("source_lineage_id", "")):
			return {}
		var balance := ResourceModel.evaluate(environment, genome, EVALUATION_BIOMASS_KG_M2)
		if balance.is_empty():
			return {}
		var net := float(balance["net_resource_balance"])
		total_net += net
		best_net = maxf(best_net, net)
		var species_id := String(entry["research_species_id"])
		counts[species_id] = int(counts.get(species_id, 0)) + 1
		for trait_name in TRAITS:
			trait_sums[trait_name] = float(trait_sums[trait_name]) + float(genome[trait_name])
		var checksum := String(genome["checksum"])
		genomes[checksum] = true
		if not frozen_checksums.has(checksum):
			novel[checksum] = true
		tokens.append("%s|%s|%s|%s" % [species_id, String(lineage["checksum"]), checksum, String(balance["checksum"])])
	var means := {}
	for trait_name in TRAITS:
		means[trait_name] = float(trait_sums[trait_name]) / float(population.size())
	return {
		"generation": generation,
		"average_net_resource_balance": total_net / float(population.size()),
		"best_net_resource_balance": best_net,
		"lineage_counts": _sorted_counts(counts),
		"trait_means": means,
		"unique_genome_count": genomes.size(),
		"novel_genome_count": novel.size(),
		"population_hash": "\n".join(tokens).sha256_text(),
	}


static func _aggregate_cell(replicates: Array, cell_id: String) -> Dictionary:
	var gains: Array[float] = []
	var positive := 0
	var home := 0
	var classifications := {}
	for replicate_value in replicates:
		var cell := _cell(Dictionary(replicate_value), cell_id)
		if cell.is_empty():
			return {}
		var gain := float(cell["adaptation_gain"])
		gains.append(gain)
		if bool(cell["positive_adaptation_effect"]):
			positive += 1
		if bool(cell["home_advantage"]):
			home += 1
		var classification := String(cell["classification"])
		classifications[classification] = int(classifications.get(classification, 0)) + 1
	var sorted_gains := gains.duplicate()
	sorted_gains.sort()
	var total := 0.0
	for value in gains:
		total += value
	var aggregate := {
		"cell_id": cell_id,
		"replicate_count": gains.size(),
		"adaptation_gains": gains,
		"mean_adaptation_gain": total / float(gains.size()),
		"median_adaptation_gain": sorted_gains[sorted_gains.size() / 2],
		"minimum_adaptation_gain": sorted_gains[0],
		"maximum_adaptation_gain": sorted_gains[sorted_gains.size() - 1],
		"positive_adaptation_count": positive,
		"nonpositive_adaptation_count": gains.size() - positive,
		"home_advantage_count": home,
		"home_advantage_fail_count": gains.size() - home,
		"classification_counts": _sorted_counts(classifications),
		"replicated_signal_pass": positive >= REQUIRED_POSITIVE_REPLICATES and home >= REQUIRED_HOME_ADVANTAGE_REPLICATES,
	}
	aggregate["cell_aggregate_hash"] = _cell_aggregate_hash(aggregate)
	return aggregate


static func _cross_environment(populations: Dictionary, environments: Dictionary) -> Dictionary:
	var result := {}
	for home_id in TARGET_CELLS:
		if not populations.has(home_id):
			return {}
		var row := {}
		for eval_id in TARGET_CELLS:
			var total := 0.0
			var population: Array = populations[home_id]
			var environment: Dictionary = Dictionary(environments[eval_id])
			for value in population:
				var balance := ResourceModel.evaluate(environment, Dictionary(Dictionary(value)["genome"]), EVALUATION_BIOMASS_KG_M2)
				if balance.is_empty():
					return {}
				total += float(balance["net_resource_balance"])
			row[eval_id] = total / float(population.size())
		result[home_id] = row
	return result


static func _frozen_strategies() -> Array:
	var alpha := PlantGenome.create("genome/e22-alpha-late", 1.5, 0.54, 1.7, 0.34, 0.25, 0.65, 130, 16.0, 8.5)
	var beta := PlantGenome.create("genome/e22-beta", 0.8, 0.72, 0.6, 0.70, 0.28, 0.28, 360, 28.0, 3.0)
	if String(alpha.get("checksum", "")) != "ebed17aadaf721218d91af4c07bc1242700151fdad8d3f614b43e751de607383":
		return []
	if String(beta.get("checksum", "")) != "a4c391bd696aea19075f7b7ff42122401db65644b038d7983d89f18102e9eff6":
		return []
	var result: Array = [
		{"research_species_id": "eco-research-species/34b4de11b3cbb2eae9f73176", "source_lineage_id": "eco-lineage/e22-alpha", "genome": alpha, "genome_checksum": String(alpha["checksum"])},
		{"research_species_id": "eco-research-species/247a0b301db2781bfc317a13", "source_lineage_id": "eco-lineage/e22-beta", "genome": beta, "genome_checksum": String(beta["checksum"])},
	]
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["research_species_id"]) < String(b["research_species_id"]))
	return result


static func _environments() -> Dictionary:
	var dry := EnvironmentSample.create(240.0, -64.0, 24.0, 0.18, 0.98, 0.65, 0.01, 2404002, "eco-evo2-e2-4-dry")
	var wet := EnvironmentSample.create(240.0, -64.0, 18.0, 0.82, 0.78, 0.78, 0.22, 2404003, "eco-evo2-e2-4-wet")
	if String(dry.get("checksum", "")) != "45e23226bf205381aa1d1e85d987f0815714fcea674e4856d534f55f38e5588b":
		return {}
	if String(wet.get("checksum", "")) != "b9c6a58274ff30329a8cad3b02360a5c61036da19a4d8a0d422786bb469b7ec5":
		return {}
	return {"DRY": dry, "WET": wet}


static func _frozen_checksums(strategies: Array) -> Dictionary:
	var result := {}
	for value in strategies:
		result[String(Dictionary(value).get("genome_checksum", ""))] = true
	return result


static func _candidate_before(a: Dictionary, b: Dictionary) -> bool:
	var av := float(a["net"])
	var bv := float(b["net"])
	if absf(av - bv) > EPSILON:
		return av > bv
	var asid := String(a["research_species_id"])
	var bsid := String(b["research_species_id"])
	if asid != bsid:
		return asid < bsid
	return String(Dictionary(a["lineage"])["checksum"]) < String(Dictionary(b["lineage"])["checksum"])


static func _classification(sorting_detected: bool, novel_genomes: bool, net_advantage: float) -> String:
	if novel_genomes and net_advantage > EPSILON:
		return "ADAPTATION_DETECTED"
	if novel_genomes:
		return "ADAPTATION_NO_MEASURABLE_ADVANTAGE"
	if sorting_detected:
		return "SORTING_ONLY_RESPONSE"
	return "NO_RESPONSE"


static func _stable_seed(replicate_id: String, cell_id: String, generation: int, offspring_index: int, parent_checksum: String) -> int:
	var prefix := ("%s|%s|%s|%d|%d|%s" % [SCHEMA, replicate_id, cell_id, generation, offspring_index, parent_checksum]).sha256_text().substr(0, 8)
	return int(prefix.hex_to_int() & 0x7fffffff)


static func _cell(replicate: Dictionary, cell_id: String) -> Dictionary:
	for value in Array(replicate.get("cells", [])):
		if typeof(value) == TYPE_DICTIONARY and String(Dictionary(value).get("cell_id", "")) == cell_id:
			return Dictionary(value)
	return {}


static func _sorted_counts(counts: Dictionary) -> Dictionary:
	var keys: Array[String] = []
	for key in counts.keys():
		keys.append(String(key))
	keys.sort()
	var result := {}
	for key in keys:
		result[key] = int(counts[key])
	return result


static func _replicate_shape_valid(replicate: Dictionary) -> bool:
	if not _exact(replicate, REPLICATE_FIELDS) or not String(replicate.get("replicate_id", "")) in REPLICATE_IDS:
		return false
	if typeof(replicate.get("cells")) != TYPE_ARRAY or Array(replicate["cells"]).size() != TARGET_CELLS.size() or typeof(replicate.get("cross_environment")) != TYPE_DICTIONARY:
		return false
	for index in range(TARGET_CELLS.size()):
		var value = Array(replicate["cells"])[index]
		if typeof(value) != TYPE_DICTIONARY:
			return false
		var cell: Dictionary = value
		if not _cell_shape_valid(cell) or String(cell["cell_id"]) != TARGET_CELLS[index]:
			return false
	return String(replicate.get("replicate_hash", "")) == _replicate_hash(replicate)


static func _cell_shape_valid(cell: Dictionary) -> bool:
	if not _exact(cell, CELL_FIELDS):
		return false
	if not String(cell.get("cell_id", "")) in TARGET_CELLS:
		return false
	if typeof(cell.get("control")) != TYPE_DICTIONARY or typeof(cell.get("treatment")) != TYPE_DICTIONARY:
		return false
	if not _arm_shape_valid(Dictionary(cell["control"])) or not _arm_shape_valid(Dictionary(cell["treatment"])):
		return false
	return String(cell.get("paired_hash", "")) == _paired_hash(cell)


static func _arm_shape_valid(arm: Dictionary) -> bool:
	if not _exact(arm, ARM_FIELDS) or typeof(arm.get("initial")) != TYPE_DICTIONARY or typeof(arm.get("final")) != TYPE_DICTIONARY or typeof(arm.get("history")) != TYPE_ARRAY or typeof(arm.get("selected_mutation_events")) != TYPE_ARRAY or typeof(arm.get("final_population")) != TYPE_ARRAY:
		return false
	if not _exact(Dictionary(arm["initial"]), SUMMARY_FIELDS) or not _exact(Dictionary(arm["final"]), SUMMARY_FIELDS):
		return false
	for event_value in Array(arm["selected_mutation_events"]):
		if typeof(event_value) != TYPE_DICTIONARY or not _exact(Dictionary(event_value), EVENT_FIELDS):
			return false
	return String(arm.get("arm_hash", "")) == _arm_hash(arm)


static func _aggregate_shape_valid(aggregate: Dictionary) -> bool:
	if not _exact(aggregate, AGGREGATE_FIELDS) or not String(aggregate.get("cell_id", "")) in TARGET_CELLS:
		return false
	if int(aggregate.get("replicate_count", -1)) != REPLICATE_IDS.size() or typeof(aggregate.get("adaptation_gains")) != TYPE_ARRAY or Array(aggregate["adaptation_gains"]).size() != REPLICATE_IDS.size():
		return false
	if typeof(aggregate.get("classification_counts")) != TYPE_DICTIONARY:
		return false
	return String(aggregate.get("cell_aggregate_hash", "")) == _cell_aggregate_hash(aggregate)


static func _arm_hash(arm: Dictionary) -> String:
	var tokens := PackedStringArray([String(arm.get("arm", "")), "1" if bool(arm.get("adaptation_enabled", false)) else "0", String(arm.get("policy_hash", ""))])
	for value in Array(arm.get("history", [])):
		var summary: Dictionary = value
		tokens.append("g=%d|avg=%.12f|best=%.12f|novel=%d|pop=%s" % [int(summary.get("generation", 0)), float(summary.get("average_net_resource_balance", 0.0)), float(summary.get("best_net_resource_balance", 0.0)), int(summary.get("novel_genome_count", 0)), String(summary.get("population_hash", ""))])
	for event_value in Array(arm.get("selected_mutation_events", [])):
		var event: Dictionary = event_value
		tokens.append("event|%d|%s|%s|%s|%s|%d|%s" % [int(event["generation"]), String(event["research_species_id"]), String(event["source_lineage_id"]), String(event["parent_genome_checksum"]), String(event["child_genome_checksum"]), int(event["mutation_count"]), String(event["mutation_event_hash"])])
	return "\n".join(tokens).sha256_text()


static func _paired_hash(cell: Dictionary) -> String:
	return "\n".join(PackedStringArray([
		String(cell.get("cell_id", "")), String(cell.get("environment_checksum", "")), String(cell.get("initial_population_hash", "")),
		String(Dictionary(cell.get("control", {})).get("arm_hash", "")), String(Dictionary(cell.get("treatment", {})).get("arm_hash", "")),
		"sorting=" + ("1" if bool(cell.get("sorting_detected", false)) else "0"),
		"sorting_gain=%.12f" % float(cell.get("sorting_gain", 0.0)), "adaptation_gain=%.12f" % float(cell.get("adaptation_gain", 0.0)),
		String(cell.get("classification", "")), "positive=" + ("1" if bool(cell.get("positive_adaptation_effect", false)) else "0"),
		"home=%.12f" % float(cell.get("home_value", 0.0)), "away=%.12f" % float(cell.get("away_value", 0.0)),
		"home_advantage=" + ("1" if bool(cell.get("home_advantage", false)) else "0"),
	])).sha256_text()


static func _replicate_hash(replicate: Dictionary) -> String:
	var tokens := PackedStringArray([SCHEMA, VERSION, String(replicate.get("replicate_id", ""))])
	for value in Array(replicate.get("cells", [])):
		tokens.append(String(Dictionary(value).get("paired_hash", "")))
	var cross: Dictionary = replicate.get("cross_environment", {})
	for home_id in TARGET_CELLS:
		for eval_id in TARGET_CELLS:
			tokens.append("cross|%s|%s|%.12f" % [home_id, eval_id, float(Dictionary(cross.get(home_id, {})).get(eval_id, 0.0))])
	return "\n".join(tokens).sha256_text()


static func _cell_aggregate_hash(aggregate: Dictionary) -> String:
	var tokens := PackedStringArray([String(aggregate.get("cell_id", "")), str(int(aggregate.get("replicate_count", 0)))])
	for value in Array(aggregate.get("adaptation_gains", [])):
		tokens.append("gain=%.12f" % float(value))
	tokens.append("mean=%.12f" % float(aggregate.get("mean_adaptation_gain", 0.0)))
	tokens.append("median=%.12f" % float(aggregate.get("median_adaptation_gain", 0.0)))
	tokens.append("min=%.12f" % float(aggregate.get("minimum_adaptation_gain", 0.0)))
	tokens.append("max=%.12f" % float(aggregate.get("maximum_adaptation_gain", 0.0)))
	tokens.append("positive=%d" % int(aggregate.get("positive_adaptation_count", 0)))
	tokens.append("nonpositive=%d" % int(aggregate.get("nonpositive_adaptation_count", 0)))
	tokens.append("home=%d" % int(aggregate.get("home_advantage_count", 0)))
	tokens.append("home_fail=%d" % int(aggregate.get("home_advantage_fail_count", 0)))
	var classifications: Dictionary = aggregate.get("classification_counts", {})
	var keys: Array[String] = []
	for key in classifications.keys(): keys.append(String(key))
	keys.sort()
	for key in keys: tokens.append("class=%s|%d" % [key, int(classifications[key])])
	tokens.append("pass=" + ("1" if bool(aggregate.get("replicated_signal_pass", false)) else "0"))
	return "\n".join(tokens).sha256_text()


static func _exact(value: Dictionary, fields: Array[String]) -> bool:
	if value.keys().size() != fields.size():
		return false
	for field_name in fields:
		if not value.has(field_name):
			return false
	for key in value.keys():
		if not String(key) in fields:
			return false
	return true

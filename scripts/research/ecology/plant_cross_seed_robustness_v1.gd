extends RefCounted

const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const MutationKernel = preload("res://scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd")
const LineageRecord = preload("res://scripts/research/ecology/plant_lineage_record_v1.gd")
const ResourceModel = preload("res://scripts/research/ecology/plant_resource_model_v1.gd")
const Protocol = preload("res://scripts/research/ecology/plant_cross_seed_protocol_v1.gd")
const Evidence = preload("res://scripts/research/ecology/plant_cross_seed_evidence_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo2_cross_seed_robustness.v1"
const VERSION := "1.0.0"
const PARENT_E2_6_ACCEPTED_AGGREGATE := "1a4bcf1cffe65450a27037e9307bb5c7ac3cb8a98899918207107e367d9d5fbd"
const PARENT_E2_6_CODE_UNDER_TEST := "8ac37bfea0f36731407e1252db1a7c2a2305420e"
const PARENT_E2_6_REPLICATE_SET_HASH := "5e02d04d3d94f95f6e8e76f6387ee07c723d2e596046f6a65d65cd815abbc637"
const E2_5_CONTROL_POLICY_HASH := "0e6481175af3658b2673a612717dd850b917ec5156260b37bd9ee29a9789dc4e"
const E2_5_TREATMENT_POLICY_HASH := "e2927ce7a8f6b3ab5f3d4942a2cc70ca3794e0d67c3e770e0301748967c14416"
const E2_2_BAKE_HASH := "45496eb67aac5cc0a65babfeb0c49fa99616df17c2f7e8b9e8b95d04cb2b4e5b"
const E2_2_CATALOG_HASH := "5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219"
const TARGET_CELLS: Array[String] = ["DRY", "WET"]
const SEED_IDS: Array[String] = [
	"S01", "S02", "S03", "S04", "S05", "S06", "S07", "S08",
	"S09", "S10",
]
const REQUIRED_POSITIVE_SEEDS := 8
const REQUIRED_HOME_ADVANTAGE_SEEDS := 8
const REQUIRED_FULL_SEED_PASS := 7
const GENERATIONS := 10
const POPULATION_SIZE := 8
const OFFSPRING_PER_PARENT := 4
const EVALUATION_BIOMASS_KG_M2 := 0.05
const EPSILON := 0.000000001
const CENSORING_ALLOWED := false
const FORMAL_SIGNIFICANCE_CLAIMED := false
const CROSS_CATALOG_ROBUSTNESS_CLAIMED := false
const CANONICAL_SPECIES_DECLARED := false
const PRODUCTION_AUTHORITY_CLAIMED := false
const TRAITS: Array[String] = ["water_preference", "root_depth_m", "growth_rate", "shade_tolerance", "seed_dispersal_distance_m"]

const RESULT_FIELDS: Array[String] = [
	"schema", "version", "parent_e2_6_accepted_aggregate", "parent_e2_6_code_under_test", "parent_e2_6_replicate_set_hash",
	"e2_2_bake_hash", "catalog_hash", "control_policy_hash", "treatment_policy_hash", "target_cells", "seed_ids", "seed_ensemble_hash",
	"required_positive_seeds", "required_home_advantage_seeds", "required_full_seed_pass", "generations", "population_size", "offspring_per_parent",
	"censoring_allowed", "all_seeds_retained", "formal_significance_claimed", "cross_catalog_robustness_claimed", "canonical_species_declared",
	"production_authority_claimed", "frozen_strategies", "environments", "seed_results", "cell_aggregates", "full_seed_pass_count",
	"full_seed_fail_count", "bounded_cross_seed_robustness_pass", "aggregate_hash",
]
const STRATEGY_FIELDS: Array[String] = ["research_species_id", "source_lineage_id", "genome", "genome_checksum"]
const SEED_RESULT_FIELDS: Array[String] = ["seed_id", "cells", "cross_environment", "full_seed_pass", "seed_hash"]
const CELL_FIELDS: Array[String] = [
	"cell_id", "environment_checksum", "initial_population_hash", "control", "treatment", "sorting_detected", "sorting_gain", "adaptation_gain",
	"classification", "positive_adaptation_effect", "home_value", "away_value", "home_advantage", "paired_hash",
]
const ARM_FIELDS: Array[String] = ["arm", "adaptation_enabled", "policy_hash", "initial", "final", "final_population", "arm_hash"]
const SUMMARY_FIELDS: Array[String] = ["generation", "average_net_resource_balance", "best_net_resource_balance", "lineage_counts", "trait_means", "unique_genome_count", "novel_genome_count", "population_hash"]
const EVENT_FIELDS: Array[String] = ["generation", "research_species_id", "source_lineage_id", "individual_id", "parent_genome_checksum", "child_genome_checksum", "mutation_count", "mutation_event_hash"]
const AGGREGATE_FIELDS: Array[String] = [
	"cell_id", "seed_count", "adaptation_gains", "mean_adaptation_gain", "median_adaptation_gain", "q25_adaptation_gain", "q75_adaptation_gain",
	"minimum_adaptation_gain", "maximum_adaptation_gain", "positive_count", "null_count", "reversal_count", "home_advantage_count",
	"home_advantage_fail_count", "classification_counts", "leave_one_out_mean_values", "leave_one_out_min_mean", "max_leave_one_out_mean_shift",
	"robustness_pass", "cell_aggregate_hash",
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
	var strategies := Protocol.frozen_strategies()
	var environments := Protocol.environments()
	if strategies.size() != 2 or environments.size() != TARGET_CELLS.size():
		return {}
	var control_policy_value := control_policy()
	var treatment_policy_value := treatment_policy()
	if MutationKernel.policy_hash(control_policy_value) != E2_5_CONTROL_POLICY_HASH:
		return {}
	if MutationKernel.policy_hash(treatment_policy_value) != E2_5_TREATMENT_POLICY_HASH:
		return {}
	var seed_results: Array = []
	for seed_id in SEED_IDS:
		var seed_result := Protocol.run_seed(seed_id, strategies, environments, control_policy_value, treatment_policy_value)
		if seed_result.is_empty():
			return {}
		seed_results.append(seed_result)
	var cell_aggregates: Array = []
	for cell_id in TARGET_CELLS:
		var aggregate := Evidence.aggregate_cell(seed_results, cell_id)
		if aggregate.is_empty():
			return {}
		cell_aggregates.append(aggregate)
	var full_seed_pass_count := 0
	for seed_result in seed_results:
		if bool(Dictionary(seed_result).get("full_seed_pass", false)):
			full_seed_pass_count += 1
	var all_cells_pass := true
	for aggregate in cell_aggregates:
		if not bool(Dictionary(aggregate).get("robustness_pass", false)):
			all_cells_pass = false
	var bounded_pass := all_cells_pass and full_seed_pass_count >= REQUIRED_FULL_SEED_PASS
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"parent_e2_6_accepted_aggregate": PARENT_E2_6_ACCEPTED_AGGREGATE,
		"parent_e2_6_code_under_test": PARENT_E2_6_CODE_UNDER_TEST,
		"parent_e2_6_replicate_set_hash": PARENT_E2_6_REPLICATE_SET_HASH,
		"e2_2_bake_hash": E2_2_BAKE_HASH,
		"catalog_hash": E2_2_CATALOG_HASH,
		"control_policy_hash": MutationKernel.policy_hash(control_policy_value),
		"treatment_policy_hash": MutationKernel.policy_hash(treatment_policy_value),
		"target_cells": TARGET_CELLS.duplicate(),
		"seed_ids": SEED_IDS.duplicate(),
		"seed_ensemble_hash": compute_seed_ensemble_hash(SEED_IDS),
		"required_positive_seeds": REQUIRED_POSITIVE_SEEDS,
		"required_home_advantage_seeds": REQUIRED_HOME_ADVANTAGE_SEEDS,
		"required_full_seed_pass": REQUIRED_FULL_SEED_PASS,
		"generations": GENERATIONS,
		"population_size": POPULATION_SIZE,
		"offspring_per_parent": OFFSPRING_PER_PARENT,
		"censoring_allowed": CENSORING_ALLOWED,
		"all_seeds_retained": seed_results.size() == SEED_IDS.size(),
		"formal_significance_claimed": FORMAL_SIGNIFICANCE_CLAIMED,
		"cross_catalog_robustness_claimed": CROSS_CATALOG_ROBUSTNESS_CLAIMED,
		"canonical_species_declared": CANONICAL_SPECIES_DECLARED,
		"production_authority_claimed": PRODUCTION_AUTHORITY_CLAIMED,
		"frozen_strategies": strategies,
		"environments": environments,
		"seed_results": seed_results,
		"cell_aggregates": cell_aggregates,
		"full_seed_pass_count": full_seed_pass_count,
		"full_seed_fail_count": seed_results.size() - full_seed_pass_count,
		"bounded_cross_seed_robustness_pass": bounded_pass,
	}
	result["aggregate_hash"] = compute_aggregate_hash(result)
	return result


static func validate_result(result: Dictionary) -> bool:
	if not Evidence.exact_fields(result, RESULT_FIELDS):
		return false
	if String(result.get("schema", "")) != SCHEMA or String(result.get("version", "")) != VERSION:
		return false
	if String(result.get("parent_e2_6_accepted_aggregate", "")) != PARENT_E2_6_ACCEPTED_AGGREGATE or String(result.get("parent_e2_6_code_under_test", "")) != PARENT_E2_6_CODE_UNDER_TEST or String(result.get("parent_e2_6_replicate_set_hash", "")) != PARENT_E2_6_REPLICATE_SET_HASH:
		return false
	if String(result.get("e2_2_bake_hash", "")) != E2_2_BAKE_HASH or String(result.get("catalog_hash", "")) != E2_2_CATALOG_HASH:
		return false
	if String(result.get("control_policy_hash", "")) != E2_5_CONTROL_POLICY_HASH or String(result.get("treatment_policy_hash", "")) != E2_5_TREATMENT_POLICY_HASH:
		return false
	if Array(result.get("target_cells", [])) != TARGET_CELLS or Array(result.get("seed_ids", [])) != SEED_IDS:
		return false
	if String(result.get("seed_ensemble_hash", "")) != compute_seed_ensemble_hash(SEED_IDS):
		return false
	if int(result.get("required_positive_seeds", -1)) != REQUIRED_POSITIVE_SEEDS or int(result.get("required_home_advantage_seeds", -1)) != REQUIRED_HOME_ADVANTAGE_SEEDS or int(result.get("required_full_seed_pass", -1)) != REQUIRED_FULL_SEED_PASS:
		return false
	if int(result.get("generations", -1)) != GENERATIONS or int(result.get("population_size", -1)) != POPULATION_SIZE or int(result.get("offspring_per_parent", -1)) != OFFSPRING_PER_PARENT:
		return false
	if bool(result.get("censoring_allowed", true)) or not bool(result.get("all_seeds_retained", false)):
		return false
	if bool(result.get("formal_significance_claimed", true)) or bool(result.get("cross_catalog_robustness_claimed", true)) or bool(result.get("canonical_species_declared", true)) or bool(result.get("production_authority_claimed", true)):
		return false
	if not bool(result.get("bounded_cross_seed_robustness_pass", false)):
		return false
	if typeof(result.get("frozen_strategies")) != TYPE_ARRAY or Array(result["frozen_strategies"]) != Protocol.frozen_strategies():
		return false
	if typeof(result.get("environments")) != TYPE_DICTIONARY or Dictionary(result["environments"]) != Protocol.environments():
		return false
	if typeof(result.get("seed_results")) != TYPE_ARRAY or Array(result["seed_results"]).size() != SEED_IDS.size():
		return false
	for index in range(SEED_IDS.size()):
		var value = Array(result["seed_results"])[index]
		if typeof(value) != TYPE_DICTIONARY:
			return false
		var seed_result: Dictionary = value
		if not Evidence.seed_shape_valid(seed_result) or String(seed_result.get("seed_id", "")) != SEED_IDS[index]:
			return false
	if typeof(result.get("cell_aggregates")) != TYPE_ARRAY or Array(result["cell_aggregates"]).size() != TARGET_CELLS.size():
		return false
	for index in range(TARGET_CELLS.size()):
		var value = Array(result["cell_aggregates"])[index]
		if typeof(value) != TYPE_DICTIONARY:
			return false
		var aggregate: Dictionary = value
		if not Evidence.aggregate_shape_valid(aggregate) or String(aggregate.get("cell_id", "")) != TARGET_CELLS[index]:
			return false
	var pass_count := 0
	for seed_result in Array(result["seed_results"]):
		if bool(Dictionary(seed_result).get("full_seed_pass", false)):
			pass_count += 1
	if pass_count != int(result.get("full_seed_pass_count", -1)) or SEED_IDS.size() - pass_count != int(result.get("full_seed_fail_count", -1)):
		return false
	var strategies: Array = result["frozen_strategies"]
	var environments: Dictionary = result["environments"]
	for seed_value in Array(result["seed_results"]):
		if not Evidence.validate_seed_semantics(Dictionary(seed_value), strategies, environments):
			return false
	for index in range(TARGET_CELLS.size()):
		var expected_aggregate := Evidence.aggregate_cell(Array(result["seed_results"]), TARGET_CELLS[index])
		if expected_aggregate.is_empty() or expected_aggregate != Dictionary(Array(result["cell_aggregates"])[index]):
			return false
	var derived_bounded := pass_count >= REQUIRED_FULL_SEED_PASS
	for aggregate_value in Array(result["cell_aggregates"]):
		if not bool(Dictionary(aggregate_value).get("robustness_pass", false)):
			derived_bounded = false
	if derived_bounded != bool(result.get("bounded_cross_seed_robustness_pass", false)):
		return false
	return String(result.get("aggregate_hash", "")) == compute_aggregate_hash(result)


static func compute_seed_ensemble_hash(seed_ids: Array[String]) -> String:
	return "\n".join(PackedStringArray([SCHEMA, VERSION, "seed-ensemble"] + seed_ids)).sha256_text()


static func compute_aggregate_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA, VERSION, PARENT_E2_6_ACCEPTED_AGGREGATE, PARENT_E2_6_CODE_UNDER_TEST, PARENT_E2_6_REPLICATE_SET_HASH,
		E2_2_BAKE_HASH, E2_2_CATALOG_HASH, String(result.get("control_policy_hash", "")), String(result.get("treatment_policy_hash", "")),
		String(result.get("seed_ensemble_hash", "")), "positive=%d" % int(result.get("required_positive_seeds", 0)),
		"home=%d" % int(result.get("required_home_advantage_seeds", 0)), "seedpass=%d" % int(result.get("required_full_seed_pass", 0)),
	])
	for value in Array(result.get("seed_results", [])):
		tokens.append(String(Dictionary(value).get("seed_hash", "")))
	for value in Array(result.get("cell_aggregates", [])):
		tokens.append(String(Dictionary(value).get("cell_aggregate_hash", "")))
	tokens.append("full-pass=%d" % int(result.get("full_seed_pass_count", 0)))
	tokens.append("bounded-pass=" + ("1" if bool(result.get("bounded_cross_seed_robustness_pass", false)) else "0"))
	return "\n".join(tokens).sha256_text()


# Acceptance-only compatibility helpers keep the public research artifact compact
# while preserving deterministic hash/aggregation probes used by the checkpoint.
static func _cell(seed_result: Dictionary, cell_id: String) -> Dictionary:
	return Protocol.cell(seed_result, cell_id)

static func _paired_hash(cell: Dictionary) -> String:
	return Protocol.paired_hash(cell)

static func _seed_hash(seed_result: Dictionary) -> String:
	return Protocol.seed_hash(seed_result)

static func _aggregate_cell(seed_results: Array, cell_id: String) -> Dictionary:
	return Evidence.aggregate_cell(seed_results, cell_id)

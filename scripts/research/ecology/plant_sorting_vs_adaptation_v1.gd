extends RefCounted

const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const SpeciesCatalog = preload("res://scripts/research/ecology/plant_species_catalog_v1.gd")
const Matrix = preload("res://scripts/research/ecology/plant_environment_generalization_matrix_v1.gd")
const MutationKernel = preload("res://scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd")
const LineageRecord = preload("res://scripts/research/ecology/plant_lineage_record_v1.gd")
const ResourceModel = preload("res://scripts/research/ecology/plant_resource_model_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo2_sorting_vs_adaptation.v1"
const VERSION := "1.0.0"
const PARENT_E2_4_ACCEPTED_AGGREGATE := "ae2952de10ac721c8052694963b690d9f72af05d9c92e2fa4cd70e00f72fb2b5"
const PARENT_E2_4_CODE_UNDER_TEST := "0135aee461a107375cdb3e52e07e8c799145998b"
const PARENT_E2_4_PLAN_HASH := "f688eb014245d63483562376c3f5db8c08a85bdc35feb52428f5ff17753f82e0"
const TARGET_CELLS: Array[String] = ["DRY", "WET"]
const GENERATIONS := 10
const POPULATION_SIZE := 8
const OFFSPRING_PER_PARENT := 4
const EVALUATION_BIOMASS_KG_M2 := 0.05
const EPSILON := 0.000000001
const FULL_TRANSFER_CONTINUATION_CLAIMED := false
const CANONICAL_SPECIES_DECLARED := false
const PRODUCTION_AUTHORITY_CLAIMED := false
const ADAPTATION_CREATES_CANONICAL_SPECIES := false
const TRAITS: Array[String] = ["water_preference", "root_depth_m", "growth_rate", "shade_tolerance", "seed_dispersal_distance_m"]
const RESULT_FIELDS: Array[String] = ["schema", "version", "parent_e2_4_accepted_aggregate", "parent_e2_4_code_under_test", "parent_e2_4_plan_hash", "e2_2_bake_hash", "catalog_hash", "frozen_species_ids", "frozen_genome_checksums", "target_cells", "generations", "population_size", "offspring_per_parent", "control_policy_hash", "treatment_policy_hash", "full_transfer_continuation_claimed", "canonical_species_declared", "production_authority_claimed", "adaptation_creates_canonical_species", "cells", "cross_environment", "aggregate_hash"]
const CELL_FIELDS: Array[String] = ["cell_id", "environment_checksum", "initial_population_hash", "initial_lineage_counts", "control", "treatment", "sorting_detected", "adaptation_detected", "sorting_gain", "adaptation_gain", "classification", "paired_hash"]
const ARM_FIELDS: Array[String] = ["arm", "adaptation_enabled", "policy_hash", "initial", "final", "history", "selected_mutation_events", "final_population", "arm_hash"]
const SUMMARY_FIELDS: Array[String] = ["generation", "average_net_resource_balance", "best_net_resource_balance", "lineage_counts", "trait_means", "unique_genome_count", "novel_genome_count", "population_hash"]
const EVENT_FIELDS: Array[String] = ["generation", "research_species_id", "source_lineage_id", "individual_id", "parent_genome_checksum", "child_genome_checksum", "mutation_count", "mutation_event_hash"]


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


static func run(bake_export: Dictionary, matrix_result: Dictionary) -> Dictionary:
	if not Matrix.validate_result(bake_export, matrix_result):
		return {}
	if String(matrix_result.get("matrix_hash", "")) != PARENT_E2_4_ACCEPTED_AGGREGATE:
		return {}
	if String(matrix_result.get("plan_hash", "")) != PARENT_E2_4_PLAN_HASH:
		return {}
	var catalog_value = bake_export.get("species_catalog")
	if typeof(catalog_value) != TYPE_DICTIONARY:
		return {}
	var catalog: Dictionary = catalog_value
	if not SpeciesCatalog.validate_catalog(catalog):
		return {}
	if String(bake_export.get("bake_hash", "")) != preload("res://scripts/research/ecology/plant_frozen_catalog_transfer_v1.gd").ACCEPTED_E2_2_BAKE_HASH:
		return {}
	if String(catalog.get("catalog_hash", "")) != preload("res://scripts/research/ecology/plant_frozen_catalog_transfer_v1.gd").ACCEPTED_E2_2_CATALOG_HASH:
		return {}
	if Array(catalog.get("entries", [])).is_empty() or POPULATION_SIZE % Array(catalog["entries"]).size() != 0:
		return {}
	var control_policy_value := control_policy()
	var treatment_policy_value := treatment_policy()
	if not bool(MutationKernel.validate_policy(control_policy_value).get("success", false)) or not bool(MutationKernel.validate_policy(treatment_policy_value).get("success", false)):
		return {}
	var cells: Array = []
	var treatment_populations := {}
	var environments := {}
	for cell_id in TARGET_CELLS:
		var environment := _environment_for_cell(matrix_result, cell_id)
		if environment.is_empty():
			return {}
		var founders := _founders(catalog, cell_id)
		if founders.size() != POPULATION_SIZE:
			return {}
		var control := _run_arm(founders, environment, cell_id, "CONTROL", false, control_policy_value, catalog)
		var treatment := _run_arm(founders, environment, cell_id, "TREATMENT", true, treatment_policy_value, catalog)
		if control.is_empty() or treatment.is_empty():
			return {}
		var initial_counts: Dictionary = Dictionary(control["initial"]["lineage_counts"]).duplicate(true)
		if initial_counts != Dictionary(treatment["initial"]["lineage_counts"]):
			return {}
		if String(control["initial"]["population_hash"]) != String(treatment["initial"]["population_hash"]):
			return {}
		var sorting_detected := Dictionary(control["final"]["lineage_counts"]) != initial_counts
		var sorting_gain := float(control["final"]["average_net_resource_balance"]) - float(control["initial"]["average_net_resource_balance"])
		var adaptation_gain := float(treatment["final"]["average_net_resource_balance"]) - float(control["final"]["average_net_resource_balance"])
		var adaptation_detected := int(treatment["final"]["novel_genome_count"]) > 0 and adaptation_gain > EPSILON
		var classification := _classification(sorting_detected, int(treatment["final"]["novel_genome_count"]) > 0, adaptation_gain)
		var cell := {
			"cell_id": cell_id,
			"environment_checksum": String(environment["checksum"]),
			"initial_population_hash": String(control["initial"]["population_hash"]),
			"initial_lineage_counts": initial_counts,
			"control": control,
			"treatment": treatment,
			"sorting_detected": sorting_detected,
			"adaptation_detected": adaptation_detected,
			"sorting_gain": sorting_gain,
			"adaptation_gain": adaptation_gain,
			"classification": classification,
		}
		cell["paired_hash"] = _paired_hash(cell)
		cells.append(cell)
		treatment_populations[cell_id] = Array(treatment["final_population"]).duplicate(true)
		environments[cell_id] = environment.duplicate(true)
	var cross_environment := _cross_environment(treatment_populations, environments)
	if cross_environment.is_empty():
		return {}
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"parent_e2_4_accepted_aggregate": PARENT_E2_4_ACCEPTED_AGGREGATE,
		"parent_e2_4_code_under_test": PARENT_E2_4_CODE_UNDER_TEST,
		"parent_e2_4_plan_hash": PARENT_E2_4_PLAN_HASH,
		"e2_2_bake_hash": String(bake_export["bake_hash"]),
		"catalog_hash": String(catalog["catalog_hash"]),
		"frozen_species_ids": _frozen_species_ids(catalog),
		"frozen_genome_checksums": _frozen_genome_checksum_list(catalog),
		"target_cells": TARGET_CELLS.duplicate(),
		"generations": GENERATIONS,
		"population_size": POPULATION_SIZE,
		"offspring_per_parent": OFFSPRING_PER_PARENT,
		"control_policy_hash": MutationKernel.policy_hash(control_policy_value),
		"treatment_policy_hash": MutationKernel.policy_hash(treatment_policy_value),
		"full_transfer_continuation_claimed": FULL_TRANSFER_CONTINUATION_CLAIMED,
		"canonical_species_declared": CANONICAL_SPECIES_DECLARED,
		"production_authority_claimed": PRODUCTION_AUTHORITY_CLAIMED,
		"adaptation_creates_canonical_species": ADAPTATION_CREATES_CANONICAL_SPECIES,
		"cells": cells,
		"cross_environment": cross_environment,
	}
	result["aggregate_hash"] = compute_aggregate_hash(result)
	return result


static func validate_result(bake_export: Dictionary, matrix_result: Dictionary, result: Dictionary) -> bool:
	if not _exact(result, RESULT_FIELDS):
		return false
	if String(result.get("schema", "")) != SCHEMA or String(result.get("version", "")) != VERSION:
		return false
	if String(result.get("parent_e2_4_accepted_aggregate", "")) != PARENT_E2_4_ACCEPTED_AGGREGATE or String(result.get("parent_e2_4_code_under_test", "")) != PARENT_E2_4_CODE_UNDER_TEST or String(result.get("parent_e2_4_plan_hash", "")) != PARENT_E2_4_PLAN_HASH:
		return false
	if typeof(result.get("frozen_species_ids")) != TYPE_ARRAY or typeof(result.get("frozen_genome_checksums")) != TYPE_ARRAY:
		return false
	var catalog_value = bake_export.get("species_catalog")
	if typeof(catalog_value) != TYPE_DICTIONARY:
		return false
	var catalog: Dictionary = catalog_value
	if Array(result["frozen_species_ids"]) != _frozen_species_ids(catalog) or Array(result["frozen_genome_checksums"]) != _frozen_genome_checksum_list(catalog):
		return false
	if typeof(result.get("target_cells")) != TYPE_ARRAY or Array(result["target_cells"]) != TARGET_CELLS:
		return false
	if int(result.get("generations", -1)) != GENERATIONS or int(result.get("population_size", -1)) != POPULATION_SIZE or int(result.get("offspring_per_parent", -1)) != OFFSPRING_PER_PARENT:
		return false
	if bool(result.get("full_transfer_continuation_claimed", true)) or bool(result.get("canonical_species_declared", true)) or bool(result.get("production_authority_claimed", true)) or bool(result.get("adaptation_creates_canonical_species", true)):
		return false
	if typeof(result.get("cells")) != TYPE_ARRAY or Array(result["cells"]).size() != TARGET_CELLS.size() or typeof(result.get("cross_environment")) != TYPE_DICTIONARY:
		return false
	for index in range(TARGET_CELLS.size()):
		var cell_value = Array(result["cells"])[index]
		if typeof(cell_value) != TYPE_DICTIONARY:
			return false
		var cell: Dictionary = cell_value
		if not _exact(cell, CELL_FIELDS) or String(cell.get("cell_id", "")) != TARGET_CELLS[index]:
			return false
		if typeof(cell.get("control")) != TYPE_DICTIONARY or typeof(cell.get("treatment")) != TYPE_DICTIONARY:
			return false
		if not _arm_shape_valid(Dictionary(cell["control"])) or not _arm_shape_valid(Dictionary(cell["treatment"])):
			return false
		if String(cell.get("paired_hash", "")) != _paired_hash(cell):
			return false
	if String(result.get("aggregate_hash", "")) != compute_aggregate_hash(result):
		return false
	var expected := run(bake_export, matrix_result)
	return not expected.is_empty() and expected == result


static func compute_aggregate_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA, VERSION, PARENT_E2_4_ACCEPTED_AGGREGATE, PARENT_E2_4_CODE_UNDER_TEST, PARENT_E2_4_PLAN_HASH,
		String(result.get("e2_2_bake_hash", "")), String(result.get("catalog_hash", "")),
		"species=" + ",".join(PackedStringArray(result.get("frozen_species_ids", []))),
		"genomes=" + ",".join(PackedStringArray(result.get("frozen_genome_checksums", []))),
		String(result.get("control_policy_hash", "")), String(result.get("treatment_policy_hash", "")),
	])
	for value in Array(result.get("cells", [])):
		tokens.append(String(Dictionary(value).get("paired_hash", "")))
	var cross: Dictionary = result.get("cross_environment", {})
	for home_id in TARGET_CELLS:
		for eval_id in TARGET_CELLS:
			tokens.append("cross|%s|%s|%.12f" % [home_id, eval_id, float(Dictionary(cross.get(home_id, {})).get(eval_id, 0.0))])
	return "\n".join(tokens).sha256_text()


static func _run_arm(founders: Array, environment: Dictionary, cell_id: String, arm_id: String, adaptation_enabled: bool, policy: Dictionary, catalog: Dictionary) -> Dictionary:
	var population := founders.duplicate(true)
	var frozen_checksums := _frozen_checksums(catalog)
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
				var mutation_seed := _stable_seed(cell_id, generation, offspring_index, String(Dictionary(parent["lineage"])["checksum"]))
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


static func _founders(catalog: Dictionary, cell_id: String) -> Array:
	var entries: Array = catalog.get("entries", [])
	var copies := POPULATION_SIZE / entries.size()
	var founders: Array = []
	for entry_value in entries:
		var entry: Dictionary = entry_value
		var genome: Dictionary = Dictionary(entry["genome"]).duplicate(true)
		if not bool(PlantGenome.validate(genome).get("success", false)):
			return []
		for local_index in range(copies):
			var context := "%s|%s|%s|%s|%d" % [SCHEMA, cell_id, String(catalog["catalog_hash"]), String(entry["research_species_id"]), local_index]
			var seed_value := _stable_seed("founder", 0, local_index, context)
			var individual_id := "eco-individual/%s" % context.sha256_text().substr(0, 24)
			var event_hash := ("founder|" + context).sha256_text()
			var lineage := LineageRecord.create(String(entry["lineage_id"]), individual_id, "", 0, local_index, seed_value, "", String(genome["checksum"]), event_hash)
			if not bool(LineageRecord.validate(lineage).get("success", false)):
				return []
			founders.append({
				"research_species_id": String(entry["research_species_id"]),
				"source_lineage_id": String(entry["lineage_id"]),
				"frozen_genome_checksum": String(entry["genome_checksum"]),
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
		if typeof(value) != TYPE_DICTIONARY:
			return {}
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


static func _environment_for_cell(matrix_result: Dictionary, cell_id: String) -> Dictionary:
	for cell_value in Array(Dictionary(matrix_result["plan"]).get("cells", [])):
		var cell: Dictionary = cell_value
		if String(cell.get("cell_id", "")) != cell_id:
			continue
		if String(cell.get("mode", "")) != "STATIC" or Array(cell.get("phases", [])).size() != 1:
			return {}
		return Dictionary(Dictionary(Array(cell["phases"])[0]).get("environment", {})).duplicate(true)
	return {}


static func _cross_environment(populations: Dictionary, environments: Dictionary) -> Dictionary:
	var result := {}
	for home_id in TARGET_CELLS:
		if not populations.has(home_id):
			return {}
		var row := {}
		for eval_id in TARGET_CELLS:
			var total := 0.0
			var population: Array = populations[home_id]
			var environment: Dictionary = environments[eval_id]
			for value in population:
				var balance := ResourceModel.evaluate(environment, Dictionary(Dictionary(value)["genome"]), EVALUATION_BIOMASS_KG_M2)
				if balance.is_empty():
					return {}
				total += float(balance["net_resource_balance"])
			row[eval_id] = total / float(population.size())
		result[home_id] = row
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


static func _frozen_species_ids(catalog: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for value in Array(catalog.get("entries", [])):
		result.append(String(Dictionary(value).get("research_species_id", "")))
	result.sort()
	return result


static func _frozen_genome_checksum_list(catalog: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for value in Array(catalog.get("entries", [])):
		result.append(String(Dictionary(value).get("genome_checksum", "")))
	result.sort()
	return result


static func _frozen_checksums(catalog: Dictionary) -> Dictionary:
	var result := {}
	for value in Array(catalog.get("entries", [])):
		result[String(Dictionary(value).get("genome_checksum", ""))] = true
	return result


static func _sorted_counts(counts: Dictionary) -> Dictionary:
	var keys: Array[String] = []
	for key in counts.keys():
		keys.append(String(key))
	keys.sort()
	var result := {}
	for key in keys:
		result[key] = int(counts[key])
	return result


static func _stable_seed(cell_id: String, generation: int, offspring_index: int, parent_checksum: String) -> int:
	var prefix := ("%s|%s|%d|%d|%s" % [SCHEMA, cell_id, generation, offspring_index, parent_checksum]).sha256_text().substr(0, 8)
	return int(prefix.hex_to_int() & 0x7fffffff)


static func _arm_shape_valid(arm: Dictionary) -> bool:
	if not _exact(arm, ARM_FIELDS) or typeof(arm.get("initial")) != TYPE_DICTIONARY or typeof(arm.get("final")) != TYPE_DICTIONARY or typeof(arm.get("history")) != TYPE_ARRAY or typeof(arm.get("selected_mutation_events")) != TYPE_ARRAY or typeof(arm.get("final_population")) != TYPE_ARRAY:
		return false
	if not _exact(Dictionary(arm["initial"]), SUMMARY_FIELDS) or not _exact(Dictionary(arm["final"]), SUMMARY_FIELDS):
		return false
	for event_value in Array(arm["selected_mutation_events"]):
		if typeof(event_value) != TYPE_DICTIONARY or not _exact(Dictionary(event_value), EVENT_FIELDS):
			return false
	return String(arm.get("arm_hash", "")) == _arm_hash(arm)


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
		"adaptation=" + ("1" if bool(cell.get("adaptation_detected", false)) else "0"),
		"sorting_gain=%.12f" % float(cell.get("sorting_gain", 0.0)),
		"adaptation_gain=%.12f" % float(cell.get("adaptation_gain", 0.0)), String(cell.get("classification", "")),
	])).sha256_text()


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

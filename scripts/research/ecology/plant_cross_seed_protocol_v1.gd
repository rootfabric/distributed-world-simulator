extends RefCounted

const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const MutationKernel = preload("res://scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd")
const LineageRecord = preload("res://scripts/research/ecology/plant_lineage_record_v1.gd")
const ResourceModel = preload("res://scripts/research/ecology/plant_resource_model_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo2_cross_seed_robustness.v1"
const VERSION := "1.0.0"
const E2_5_CONTROL_POLICY_HASH := "0e6481175af3658b2673a612717dd850b917ec5156260b37bd9ee29a9789dc4e"
const E2_5_TREATMENT_POLICY_HASH := "e2927ce7a8f6b3ab5f3d4942a2cc70ca3794e0d67c3e770e0301748967c14416"
const TARGET_CELLS: Array[String] = ["DRY", "WET"]
const SEED_IDS: Array[String] = ["S01", "S02", "S03", "S04", "S05", "S06", "S07", "S08", "S09", "S10"]
const GENERATIONS := 10
const POPULATION_SIZE := 8
const OFFSPRING_PER_PARENT := 4
const EVALUATION_BIOMASS_KG_M2 := 0.05
const EPSILON := 0.000000001
const TRAITS: Array[String] = ["water_preference", "root_depth_m", "growth_rate", "shade_tolerance", "seed_dispersal_distance_m"]

static func run_seed(seed_id: String, strategies: Array, environments: Dictionary, control_policy_value: Dictionary, treatment_policy_value: Dictionary) -> Dictionary:
	if not seed_id in SEED_IDS:
		return {}
	var cells: Array = []
	var treatment_populations := {}
	for cell_id in TARGET_CELLS:
		var environment: Dictionary = Dictionary(environments[cell_id])
		var founders := founders(strategies, cell_id)
		if founders.size() != POPULATION_SIZE:
			return {}
		var control := _run_arm(founders, environment, cell_id, seed_id, "CONTROL", false, control_policy_value, strategies)
		var treatment := _run_arm(founders, environment, cell_id, seed_id, "TREATMENT", true, treatment_policy_value, strategies)
		if control.is_empty() or treatment.is_empty():
			return {}
		if String(Dictionary(control["initial"])["population_hash"]) != String(Dictionary(treatment["initial"])["population_hash"]):
			return {}
		var sorting_detected := Dictionary(Dictionary(control["final"])["lineage_counts"]) != Dictionary(Dictionary(control["initial"])["lineage_counts"])
		var sorting_gain := float(Dictionary(control["final"])["average_net_resource_balance"]) - float(Dictionary(control["initial"])["average_net_resource_balance"])
		var adaptation_gain := float(Dictionary(treatment["final"])["average_net_resource_balance"]) - float(Dictionary(control["final"])["average_net_resource_balance"])
		var novel := int(Dictionary(treatment["final"])["novel_genome_count"]) > 0
		var cell := {
			"cell_id": cell_id,
			"environment_checksum": String(environment["checksum"]),
			"initial_population_hash": String(Dictionary(control["initial"])["population_hash"]),
			"control": control,
			"treatment": treatment,
			"sorting_detected": sorting_detected,
			"sorting_gain": sorting_gain,
			"adaptation_gain": adaptation_gain,
			"classification": classification(sorting_detected, novel, adaptation_gain),
			"positive_adaptation_effect": novel and adaptation_gain > EPSILON,
			"home_value": 0.0,
			"away_value": 0.0,
			"home_advantage": false,
		}
		cells.append(cell)
		treatment_populations[cell_id] = Array(treatment["final_population"]).duplicate(true)
	var cross := cross_environment(treatment_populations, environments)
	if cross.is_empty():
		return {}
	var full_seed_pass := true
	for cell in cells:
		var cell_id := String(cell["cell_id"])
		var away_id := "WET" if cell_id == "DRY" else "DRY"
		cell["home_value"] = float(Dictionary(cross[cell_id])[cell_id])
		cell["away_value"] = float(Dictionary(cross[away_id])[cell_id])
		cell["home_advantage"] = float(cell["home_value"]) > float(cell["away_value"]) + EPSILON
		cell["paired_hash"] = paired_hash(cell)
		if not bool(cell["positive_adaptation_effect"]) or not bool(cell["home_advantage"]):
			full_seed_pass = false
	var result := {"seed_id": seed_id, "cells": cells, "cross_environment": cross, "full_seed_pass": full_seed_pass}
	result["seed_hash"] = seed_hash(result)
	return result


static func _run_arm(founders: Array, environment: Dictionary, cell_id: String, seed_id: String, arm_id: String, adaptation_enabled: bool, policy: Dictionary, strategies: Array) -> Dictionary:
	var population := founders.duplicate(true)
	var frozen_checksums := frozen_checksums(strategies)
	var initial := summary(population, environment, 0, frozen_checksums)
	if initial.is_empty():
		return {}
	for generation in range(1, GENERATIONS + 1):
		var candidates: Array = []
		for parent_index in range(population.size()):
			var parent: Dictionary = population[parent_index]
			for child_index in range(OFFSPRING_PER_PARENT):
				var offspring_index := parent_index * OFFSPRING_PER_PARENT + child_index
				var mutation_seed := _stable_seed(seed_id, cell_id, generation, offspring_index, String(Dictionary(parent["lineage"])["checksum"]))
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
	var final := summary(population, environment, GENERATIONS, frozen_checksums)
	if final.is_empty():
		return {}
	var arm := {
		"arm": arm_id,
		"adaptation_enabled": adaptation_enabled,
		"policy_hash": MutationKernel.policy_hash(policy),
		"initial": initial,
		"final": final,
		"final_population": population,
	}
	arm["arm_hash"] = arm_hash(arm)
	return arm

static func founders(strategies: Array, cell_id: String) -> Array:
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
			var lineage := LineageRecord.create(String(strategy["source_lineage_id"]), individual_id, "", 0, local_index, seed_value, "", String(genome["checksum"]), ("founder|" + context).sha256_text())
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


static func summary(population: Array, environment: Dictionary, generation: int, frozen_checksums: Dictionary) -> Dictionary:
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
		"lineage_counts": sorted_counts(counts),
		"trait_means": means,
		"unique_genome_count": genomes.size(),
		"novel_genome_count": novel.size(),
		"population_hash": "\n".join(tokens).sha256_text(),
	}


static func cross_environment(populations: Dictionary, environments: Dictionary) -> Dictionary:
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


static func frozen_strategies() -> Array:
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


static func environments() -> Dictionary:
	var dry := EnvironmentSample.create(240.0, -64.0, 24.0, 0.18, 0.98, 0.65, 0.01, 2404002, "eco-evo2-e2-4-dry")
	var wet := EnvironmentSample.create(240.0, -64.0, 18.0, 0.82, 0.78, 0.78, 0.22, 2404003, "eco-evo2-e2-4-wet")
	if String(dry.get("checksum", "")) != "45e23226bf205381aa1d1e85d987f0815714fcea674e4856d534f55f38e5588b":
		return {}
	if String(wet.get("checksum", "")) != "b9c6a58274ff30329a8cad3b02360a5c61036da19a4d8a0d422786bb469b7ec5":
		return {}
	return {"DRY": dry, "WET": wet}


static func frozen_checksums(strategies: Array) -> Dictionary:
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


static func classification(sorting_detected: bool, novel_genomes: bool, net_advantage: float) -> String:
	if novel_genomes and net_advantage > EPSILON:
		return "ADAPTATION_DETECTED"
	if novel_genomes:
		return "ADAPTATION_NO_MEASURABLE_ADVANTAGE"
	if sorting_detected:
		return "SORTING_ONLY_RESPONSE"
	return "NO_RESPONSE"


static func _stable_seed(seed_id: String, cell_id: String, generation: int, offspring_index: int, parent_checksum: String) -> int:
	var prefix := ("%s|%s|%s|%d|%d|%s" % [SCHEMA, seed_id, cell_id, generation, offspring_index, parent_checksum]).sha256_text().substr(0, 8)
	return int(prefix.hex_to_int() & 0x7fffffff)


static func cell(seed_result: Dictionary, cell_id: String) -> Dictionary:
	for value in Array(seed_result.get("cells", [])):
		if typeof(value) == TYPE_DICTIONARY and String(Dictionary(value).get("cell_id", "")) == cell_id:
			return Dictionary(value)
	return {}


static func sorted_counts(counts: Dictionary) -> Dictionary:
	var keys: Array[String] = []
	for key in counts.keys():
		keys.append(String(key))
	keys.sort()
	var result := {}
	for key in keys:
		result[key] = int(counts[key])
	return result


static func arm_hash(arm: Dictionary) -> String:
	var tokens := PackedStringArray([
		String(arm.get("arm", "")),
		"1" if bool(arm.get("adaptation_enabled", false)) else "0",
		String(arm.get("policy_hash", "")),
		summary_token(Dictionary(arm.get("initial", {}))),
		summary_token(Dictionary(arm.get("final", {}))),
	])
	for value in Array(arm.get("final_population", [])):
		var member: Dictionary = value
		tokens.append("final|%s|%s|%s|%s|%s" % [String(member.get("research_species_id", "")), String(member.get("source_lineage_id", "")), String(member.get("frozen_genome_checksum", "")), String(Dictionary(member.get("genome", {})).get("checksum", "")), String(Dictionary(member.get("lineage", {})).get("checksum", ""))])
	return "\n".join(tokens).sha256_text()


static func summary_token(summary: Dictionary) -> String:
	var counts: Dictionary = summary.get("lineage_counts", {})
	var count_keys: Array[String] = []
	for key in counts.keys(): count_keys.append(String(key))
	count_keys.sort()
	var count_tokens := PackedStringArray()
	for key in count_keys: count_tokens.append("%s:%d" % [key, int(counts[key])])
	var means: Dictionary = summary.get("trait_means", {})
	var mean_tokens := PackedStringArray()
	for trait_name in TRAITS: mean_tokens.append("%s:%.12f" % [trait_name, float(means.get(trait_name, 0.0))])
	return "g=%d|avg=%.12f|best=%.12f|counts=%s|means=%s|unique=%d|novel=%d|pop=%s" % [int(summary.get("generation", 0)), float(summary.get("average_net_resource_balance", 0.0)), float(summary.get("best_net_resource_balance", 0.0)), ";".join(count_tokens), ";".join(mean_tokens), int(summary.get("unique_genome_count", 0)), int(summary.get("novel_genome_count", 0)), String(summary.get("population_hash", ""))]

static func paired_hash(cell: Dictionary) -> String:
	return "\n".join(PackedStringArray([
		String(cell.get("cell_id", "")), String(cell.get("environment_checksum", "")), String(cell.get("initial_population_hash", "")),
		String(Dictionary(cell.get("control", {})).get("arm_hash", "")), String(Dictionary(cell.get("treatment", {})).get("arm_hash", "")),
		"sorting=" + ("1" if bool(cell.get("sorting_detected", false)) else "0"), "sorting_gain=%.12f" % float(cell.get("sorting_gain", 0.0)),
		"adaptation_gain=%.12f" % float(cell.get("adaptation_gain", 0.0)), String(cell.get("classification", "")),
		"positive=" + ("1" if bool(cell.get("positive_adaptation_effect", false)) else "0"), "home=%.12f" % float(cell.get("home_value", 0.0)),
		"away=%.12f" % float(cell.get("away_value", 0.0)), "home_advantage=" + ("1" if bool(cell.get("home_advantage", false)) else "0"),
	])).sha256_text()


static func seed_hash(seed_result: Dictionary) -> String:
	var tokens := PackedStringArray([SCHEMA, VERSION, String(seed_result.get("seed_id", ""))])
	for value in Array(seed_result.get("cells", [])):
		tokens.append(String(Dictionary(value).get("paired_hash", "")))
	var cross: Dictionary = seed_result.get("cross_environment", {})
	for home_id in TARGET_CELLS:
		for eval_id in TARGET_CELLS:
			tokens.append("cross|%s|%s|%.12f" % [home_id, eval_id, float(Dictionary(cross.get(home_id, {})).get(eval_id, 0.0))])
	tokens.append("full=" + ("1" if bool(seed_result.get("full_seed_pass", false)) else "0"))
	return "\n".join(tokens).sha256_text()

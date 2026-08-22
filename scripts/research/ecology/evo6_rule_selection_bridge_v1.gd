extends RefCounted

## ECO.EVO6/H1-H3 - generated rule fitness -> existing P1B mutation lineage.
## Research-only adapter. Mutation/inheritance remains owned by the accepted
## plant_mutation_lineage_kernel_v1.gd; this file only supplies EVO6 selection.

const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const MutationKernel = preload("res://scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo6_rule_selection_bridge.v1"
const VERSION := "1.0.0"
const EXPERIMENT_REVISION := "ECO.EVO6-H1H3.1"
const ARTIFACT_SCHEMA := "distributed_world_simulator.ecology.evo6_r31_generated_outcomes.v1"
const DEFAULT_GENERATIONS := 12
const DEFAULT_POPULATION_SIZE := 12
const DEFAULT_OFFSPRING_PER_PARENT := 3
const DEFAULT_LINEAGE_SEED := 20260823
const WATER_CLASS_THRESHOLD := 0.58
const GROWTH_CLASS_THRESHOLD := 0.65
const CLASS_KEYS := ["terrestrial/low", "terrestrial/tall", "amphibious/low", "amphibious/tall"]
const TRAITS := ["water_preference", "growth_rate", "root_depth_m", "shade_tolerance"]


static func default_mutation_policy() -> Dictionary:
	var policy: Dictionary = MutationKernel.default_policy().duplicate(true)
	policy["mutation_probability"] = 0.36
	policy["water_preference_step"] = 0.10
	policy["growth_rate_step"] = 0.10
	policy["root_depth_m_step"] = 0.20
	policy["shade_tolerance_step"] = 0.06
	policy["seed_dispersal_distance_m_step"] = 0.0
	return policy


static func load_artifact(path: String = "") -> Dictionary:
	var resolved_path := path
	if resolved_path.is_empty():
		resolved_path = OS.get_environment("EVO6_GENERATED_OUTCOMES_PATH")
	if resolved_path.is_empty():
		resolved_path = "res://validation/ecology/evo6_r31_generated_outcomes.v1.json"
	if not FileAccess.file_exists(resolved_path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(resolved_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary


static func selection_surface_digest(sites: Array) -> String:
	var ordered: Array = sites.duplicate(true)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("site_id", "")) < String(b.get("site_id", ""))
	)
	var tokens := PackedStringArray([ARTIFACT_SCHEMA, "1.0.0", "selection-surface-v1"])
	for raw_site in ordered:
		var site: Dictionary = raw_site
		tokens.append(String(site.get("site_id", "")))
		tokens.append(String(site.get("cell_key", "")))
		var surface: Dictionary = site.get("class_fitness", {})
		for class_key in CLASS_KEYS:
			tokens.append("%s=%.6f" % [class_key, float(surface.get(class_key, 0.0))])
	return "|".join(tokens).sha256_text()


static func validate_artifact(artifact: Dictionary) -> bool:
	if String(artifact.get("schema", "")) != ARTIFACT_SCHEMA:
		return false
	if String(artifact.get("version", "")) != "1.0.0":
		return false
	var digest := String(artifact.get("artifact_digest", ""))
	if digest.length() != 64:
		return false
	var sites = artifact.get("selection_sites", [])
	if typeof(sites) != TYPE_ARRAY or (sites as Array).is_empty():
		return false
	if String(artifact.get("selection_surface_digest", "")) != selection_surface_digest(sites as Array):
		return false
	for raw_site in sites as Array:
		if typeof(raw_site) != TYPE_DICTIONARY:
			return false
		var site: Dictionary = raw_site
		var surface = site.get("class_fitness", {})
		if typeof(surface) != TYPE_DICTIONARY:
			return false
		for class_key in CLASS_KEYS:
			if not (surface as Dictionary).has(class_key):
				return false
			var value = (surface as Dictionary)[class_key]
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
				return false
			if not is_finite(float(value)) or float(value) <= 0.0:
				return false
	return true


static func phenotype_class(genome: Dictionary) -> String:
	var root_type := "amphibious" if float(genome.get("water_preference", 0.0)) >= WATER_CLASS_THRESHOLD else "terrestrial"
	var form := "tall" if float(genome.get("growth_rate", 0.0)) >= GROWTH_CLASS_THRESHOLD else "low"
	return "%s/%s" % [root_type, form]


static func run(
	artifact: Dictionary,
	lineage_seed: int = DEFAULT_LINEAGE_SEED,
	generations: int = DEFAULT_GENERATIONS,
	population_size: int = DEFAULT_POPULATION_SIZE,
	offspring_per_parent: int = DEFAULT_OFFSPRING_PER_PARENT
) -> Dictionary:
	if not validate_artifact(artifact):
		return {}
	if generations <= 0 or population_size <= 1 or offspring_per_parent <= 0:
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

	var result_sites := {}
	var total_mutations := 0
	for raw_site in artifact["selection_sites"] as Array:
		var site: Dictionary = raw_site
		var site_result := _run_site(
			site,
			ancestor,
			ancestor_lineage,
			lineage_seed,
			generations,
			population_size,
			offspring_per_parent,
			policy
		)
		if site_result.is_empty():
			return {}
		result_sites[String(site["site_id"])] = site_result
		total_mutations += int(site_result["mutation_events"])

	var metrics := _aggregate_metrics(result_sites, ancestor)
	metrics["mutation_events_observed"] = total_mutations
	metrics["population_conserved"] = _populations_conserved(result_sites, population_size)
	metrics["common_first_candidate_pool"] = _common_first_candidate_pool(result_sites)
	metrics["rule_selection_effect"] = float(metrics["max_fitness_gain"]) > 0.000000001
	metrics["diversity_preserved"] = (
		int(metrics["unique_genomes"]) > 1
		and float(metrics["largest_genome_share"]) < 1.0
		and float(metrics["max_trait_variance"]) > 0.0
	)

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"experiment_revision": EXPERIMENT_REVISION,
		"artifact_digest": String(artifact["artifact_digest"]),
		"selection_surface_digest": String(artifact["selection_surface_digest"]),
		"rule_seed": String(artifact.get("seed", "")),
		"lineage_seed": lineage_seed,
		"generations": generations,
		"population_size": population_size,
		"offspring_per_parent": offspring_per_parent,
		"ancestor_genome_checksum": String(ancestor["checksum"]),
		"sites": result_sites,
		"metrics": metrics,
	}
	result["result_hash"] = _result_hash(result)
	return result


static func _run_site(
	site: Dictionary,
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
	var initial_summary := _summarize_population(population, site)
	history.append({
		"generation": 0,
		"selected_population_hash": _population_hash(population),
		"summary": initial_summary,
	})
	var mutation_events := 0

	for generation in range(1, generations + 1):
		var candidates: Array[Dictionary] = []
		for parent_index in range(population.size()):
			var parent: Dictionary = population[parent_index]
			for child_index in range(offspring_per_parent):
				var offspring_index := generation * 100000 + parent_index * 100 + child_index
				var mutation_seed := _mutation_seed(lineage_seed, generation, parent_index, child_index)
				var child := MutationKernel.reproduce(
					parent["genome"], parent["lineage"], mutation_seed, offspring_index, policy
				)
				if child.is_empty():
					return {}
				mutation_events += int(child.get("mutation_count", 0))
				var entry := {"genome": child["genome"], "lineage": child["lineage"]}
				entry["fitness"] = _fitness(entry["genome"], site)
				candidates.append(entry)
		var candidate_pool_hash := _population_hash(candidates)
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return _candidate_before(a, b)
		)
		population = []
		for index in range(min(population_size, candidates.size())):
			population.append({
				"genome": candidates[index]["genome"],
				"lineage": candidates[index]["lineage"],
			})
		if population.size() != population_size:
			return {}
		history.append({
			"generation": generation,
			"candidate_pool_hash": candidate_pool_hash,
			"selected_population_hash": _population_hash(population),
			"summary": _summarize_population(population, site),
		})

	return {
		"site_id": String(site["site_id"]),
		"cell_key": String(site["cell_key"]),
		"zone": String(site.get("zone", "")),
		"winner_class": String(site.get("winner_class", "")),
		"initial": initial_summary,
		"final": _summarize_population(population, site),
		"mutation_events": mutation_events,
		"history": history,
		"final_population": population,
		"final_population_hash": _population_hash(population),
	}


static func _fitness(genome: Dictionary, site: Dictionary) -> float:
	var surface: Dictionary = site["class_fitness"]
	return float(surface.get(phenotype_class(genome), 0.05))


static func _candidate_before(a: Dictionary, b: Dictionary) -> bool:
	var af := float(a.get("fitness", 0.0))
	var bf := float(b.get("fitness", 0.0))
	if absf(af - bf) > 0.000000000001:
		return af > bf
	var ak := "%s|%s" % [
		String(a["genome"].get("checksum", "")),
		String(a["lineage"].get("checksum", "")),
	]
	var bk := "%s|%s" % [
		String(b["genome"].get("checksum", "")),
		String(b["lineage"].get("checksum", "")),
	]
	return ak < bk


static func _mutation_seed(lineage_seed: int, generation: int, parent_index: int, child_index: int) -> int:
	return ("EVO6|%d|%d|%d|%d" % [lineage_seed, generation, parent_index, child_index]).hash()


static func _summarize_population(population: Array[Dictionary], site: Dictionary) -> Dictionary:
	var trait_means := {}
	var trait_variance := {}
	for trait_name in TRAITS:
		var values: Array[float] = []
		for entry in population:
			values.append(float(entry["genome"].get(trait_name, 0.0)))
		var mean := _mean(values)
		trait_means[trait_name] = mean
		var variance := 0.0
		for value in values:
			variance += (value - mean) * (value - mean)
		trait_variance[trait_name] = variance / float(max(1, values.size()))

	var class_counts := {}
	var genome_counts := {}
	var fitness_total := 0.0
	for entry in population:
		var class_key := phenotype_class(entry["genome"])
		class_counts[class_key] = int(class_counts.get(class_key, 0)) + 1
		var checksum := String(entry["genome"].get("checksum", ""))
		genome_counts[checksum] = int(genome_counts.get(checksum, 0)) + 1
		fitness_total += _fitness(entry["genome"], site)
	var largest := 0
	for count in genome_counts.values():
		largest = max(largest, int(count))
	return {
		"population_count": population.size(),
		"average_fitness": fitness_total / float(max(1, population.size())),
		"trait_means": trait_means,
		"trait_variance": trait_variance,
		"class_counts": class_counts,
		"unique_genomes": genome_counts.size(),
		"largest_genome_share": float(largest) / float(max(1, population.size())),
		"phenotype_entropy": _entropy(class_counts, population.size()),
	}


static func _aggregate_metrics(sites: Dictionary, ancestor: Dictionary) -> Dictionary:
	var aggregate_genomes := {}
	var aggregate_classes := {}
	var trait_values := {}
	for trait_name in TRAITS:
		trait_values[trait_name] = []
	var max_fitness_gain := 0.0
	var total := 0
	for site_result in sites.values():
		var site: Dictionary = site_result
		max_fitness_gain = max(
			max_fitness_gain,
			float(site["final"]["average_fitness"]) - float(site["initial"]["average_fitness"])
		)
		for entry in site["final_population"] as Array:
			total += 1
			var genome: Dictionary = entry["genome"]
			var checksum := String(genome.get("checksum", ""))
			aggregate_genomes[checksum] = int(aggregate_genomes.get(checksum, 0)) + 1
			var class_key := phenotype_class(genome)
			aggregate_classes[class_key] = int(aggregate_classes.get(class_key, 0)) + 1
			for trait_name in TRAITS:
				(trait_values[trait_name] as Array).append(float(genome.get(trait_name, 0.0)))
	var largest := 0
	for count in aggregate_genomes.values():
		largest = max(largest, int(count))
	var variances := {}
	var max_variance := 0.0
	for trait_name in TRAITS:
		var values: Array = trait_values[trait_name]
		var mean := 0.0
		for value in values:
			mean += float(value)
		mean /= float(max(1, values.size()))
		var variance := 0.0
		for value in values:
			variance += (float(value) - mean) * (float(value) - mean)
		variance /= float(max(1, values.size()))
		variances[trait_name] = variance
		max_variance = max(max_variance, variance)
	return {
		"unique_genomes": aggregate_genomes.size(),
		"largest_genome_share": float(largest) / float(max(1, total)),
		"phenotype_entropy": _entropy(aggregate_classes, total),
		"trait_variance": variances,
		"max_trait_variance": max_variance,
		"max_fitness_gain": max_fitness_gain,
		"ancestor_class": phenotype_class(ancestor),
	}


static func _populations_conserved(sites: Dictionary, expected: int) -> bool:
	for site in sites.values():
		if int((site as Dictionary)["final"]["population_count"]) != expected:
			return false
	return true


static func _common_first_candidate_pool(sites: Dictionary) -> bool:
	var hashes := {}
	for site in sites.values():
		var history: Array = (site as Dictionary)["history"]
		if history.size() < 2:
			return false
		hashes[String((history[1] as Dictionary).get("candidate_pool_hash", ""))] = true
	return hashes.size() == 1


static func _population_hash(population: Array) -> String:
	var tokens: Array[String] = []
	for raw_entry in population:
		var entry: Dictionary = raw_entry
		tokens.append("%s:%s" % [
			String(entry["genome"].get("checksum", "")),
			String(entry["lineage"].get("checksum", "")),
		])
	tokens.sort()
	return "|".join(PackedStringArray(tokens)).sha256_text()


static func _result_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		EXPERIMENT_REVISION,
		String(result.get("artifact_digest", "")),
		String(result.get("rule_seed", "")),
		String(result.get("selection_surface_digest", "")),
		str(int(result.get("lineage_seed", 0))),
		str(int(result.get("generations", 0))),
		str(int(result.get("population_size", 0))),
	])
	var site_ids := (result["sites"] as Dictionary).keys()
	site_ids.sort()
	for site_id in site_ids:
		var site: Dictionary = result["sites"][site_id]
		tokens.append(String(site_id))
		tokens.append(String(site["final_population_hash"]))
	return "|".join(tokens).sha256_text()


static func _entropy(counts: Dictionary, total: int) -> float:
	if total <= 0 or counts.size() <= 1:
		return 0.0
	var entropy := 0.0
	for count in counts.values():
		var p := float(count) / float(total)
		if p > 0.0:
			entropy -= p * log(p)
	return entropy / log(float(CLASS_KEYS.size()))


static func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())

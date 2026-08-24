extends RefCounted

## ECO.EVO7 FFF5 Experiment D: vegetation creates a soil legacy, source plants are
## removed, then one identical descendant candidate stream is selected on modified
## vs pristine soil. Different descendants prove temporal ecological memory.
##
## CAUSALITY FENCE: modified/pristine may differ in EnvironmentSample only. The
## development reproduction_event used to derive individual_seed is deliberately
## mode-independent, so stochastic skeleton identity cannot create a fake legacy
## effect. Same candidate + same generation/parent/offspring => same realization
## seed in both counterfactual modes.
const Morphology = preload("res://scripts/research/ecology/evo7_morphology_evolution_bridge_v1.gd")
const LineageExtension = preload("res://scripts/research/ecology/plant_mutation_lineage_extension_evo7_v1.gd")
const Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const CoupledDevelopment = preload("res://scripts/research/ecology/plant_environment_coupled_development_v1.gd")
const FunctionalPhenotype = preload("res://scripts/research/ecology/plant_functional_phenotype_v1.gd")
const EnvSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const EffectV3 = preload("res://scripts/research/ecology/plant_environment_effect_v3.gd")
const Legacy = preload("res://scripts/research/ecology/soil_legacy_field_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_soil_memory_bridge.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-FFF5.2"
const EVALUATION_IDENTITY_RULE := "MODE_INDEPENDENT_V1"
const SOURCE_PLANTS := 12
const FEATURE_FIELDS: Array[String] = ["leaf_area_index_proxy", "realized_root_depth_m", "root_shoot_ratio", "realized_height_m"]

static func evaluation_seed_tag(generation: int, parent_index: int, offspring_index: int) -> String:
	if generation < 0 or parent_index < 0 or offspring_index < 0:
		return ""
	return "fff5-eval|%d|%d|%d" % [generation, parent_index, offspring_index]

static func run_all(lineage_seed := 20260823, source_cycles := 8, generations := 18, population_size := 18, offspring_per_parent := 4) -> Dictionary:
	if source_cycles < 1 or generations < 2 or population_size < 2 or offspring_per_parent < 1: return {}
	var ancestor := Morphology.default_ancestor_bundle(lineage_seed)
	if ancestor.is_empty(): return {}
	var modified := _build_legacy(ancestor, lineage_seed, source_cycles)
	if modified.is_empty(): return {}
	var pristine := Legacy.create_pristine()
	var policy := LineageExtension.default_policy()
	policy["morphology_probability"] = 0.50
	policy["genome_policy"]["mutation_probability"] = 0.50
	if LineageExtension.policy_hash(policy).is_empty(): return {}
	var modified_result := _run_mode(ancestor, modified, lineage_seed, generations, population_size, offspring_per_parent, policy, "modified")
	var pristine_result := _run_mode(ancestor, pristine, lineage_seed, generations, population_size, offspring_per_parent, policy, "pristine")
	if modified_result.is_empty() or pristine_result.is_empty(): return {}
	if String(modified_result["first_candidate_pool_hash"]) != String(pristine_result["first_candidate_pool_hash"]): return {}
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"evaluation_identity_rule": EVALUATION_IDENTITY_RULE,
		"lineage_seed": lineage_seed,
		"source_cycles": source_cycles,
		"source_removed": true,
		"modified_soil": modified,
		"pristine_soil": pristine,
		"common_first_candidate_pool_hash": String(modified_result["first_candidate_pool_hash"]),
		"modified": modified_result,
		"pristine": pristine_result,
		"fitness_delta_modified_minus_pristine": snappedf(float(modified_result["mean_fitness"]) - float(pristine_result["mean_fitness"]), 1e-9),
	}
	result["result_hash"] = _result_hash(result)
	return result

static func _build_legacy(ancestor: Dictionary, seed: int, source_cycles: int) -> Dictionary:
	var state := Legacy.create_pristine()
	var env := EnvSample.create(0.0, 0.0, 20.0, 0.48, 0.82, 0.50, 0.02, seed, "ECO.EVO7-FFF5|source")
	for cycle in range(1, source_cycles + 1):
		var effects: Array = []
		for index in SOURCE_PLANTS:
			var fp := _functional(ancestor, env, "fff5-source|%d|%d" % [cycle, index])
			if fp.is_empty(): return {}
			var soil_binding := maxi(int(floor((float(fp["realized_root_depth_m"]) + float(fp["realized_root_spread_m"])) * 3500.0)), 0)
			var effect := EffectV3.create("source-%02d" % index, "legacy-cell", cycle, int(fp["shade_output_ppm"]), 0, 0, int(fp["litter_flux_ppm"]), soil_binding, String(fp["phenotype_hash"]))
			if effect.is_empty(): return {}
			effects.append(effect)
		state = Legacy.apply_cycle(state, effects)
		if state.is_empty(): return {}
	return state

static func _run_mode(ancestor: Dictionary, soil: Dictionary, lineage_seed: int, generations: int, population_size: int, offspring_per_parent: int, policy: Dictionary, mode: String) -> Dictionary:
	var population: Array[Dictionary] = []
	for index in population_size:
		var bundle: Dictionary = ancestor.duplicate(true)
		var individual_seed := Contract.derive_individual_seed(String(bundle["lineage"]["lineage_id"]), "evo7-fff5-gen0|%d" % index, index, String(bundle["genome"]["version"]))
		bundle["individual_seed"] = individual_seed
		bundle["bundle_checksum"] = LineageExtension.bundle_checksum(bundle["genome"], bundle["dev_traits"], bundle["ext_traits"], bundle["lineage"], individual_seed)
		population.append({"bundle": bundle, "fitness": 0.0})
	var first_pool_hash := ""
	for generation in range(1, generations + 1):
		var candidates: Array[Dictionary] = []
		var pool_tokens := PackedStringArray()
		for parent_index in population.size():
			var parent: Dictionary = population[parent_index]
			for offspring_index in offspring_per_parent:
				var mutation_seed := ("EVO7-FFF5|%d|%d|%d|%d" % [lineage_seed, generation, parent_index, offspring_index]).hash()
				var child := LineageExtension.reproduce_bundle(parent["bundle"], mutation_seed, offspring_index, policy)
				if child.is_empty(): return {}
				var evaluated := _evaluate(child["bundle"], soil, lineage_seed, generation, mode, parent_index, offspring_index)
				if evaluated.is_empty(): return {}
				candidates.append(evaluated)
				pool_tokens.append(String(child["result_hash"]))
		if generation == 1: first_pool_hash = "|".join(pool_tokens).sha256_text()
		candidates.sort_custom(_rank_order)
		population = candidates.slice(0, population_size)
	var checksums := PackedStringArray()
	var fitness_sum := 0.0
	var sums := {}
	for field_name in FEATURE_FIELDS: sums[field_name] = 0.0
	var economics_sum := 0.0
	for entry in population:
		checksums.append(String(entry["bundle"]["bundle_checksum"]))
		fitness_sum += float(entry["fitness"])
		economics_sum += float(entry["leaf_economics_proxy"])
		for field_name in FEATURE_FIELDS: sums[field_name] += float(entry["features"][field_name])
	checksums.sort()
	var means := {}
	for field_name in FEATURE_FIELDS: means[field_name] = snappedf(float(sums[field_name]) / float(population.size()), 1e-9)
	return {
		"mode": mode,
		"soil_state_hash": String(soil["state_hash"]),
		"first_candidate_pool_hash": first_pool_hash,
		"final_population_hash": "|".join(checksums).sha256_text(),
		"mean_fitness": snappedf(fitness_sum / float(population.size()), 1e-9),
		"mean_leaf_economics_proxy": snappedf(economics_sum / float(population.size()), 1e-9),
		"mean_features": means,
	}

static func _evaluate(bundle: Dictionary, soil: Dictionary, seed: int, generation: int, mode: String, parent_index: int, offspring_index: int) -> Dictionary:
	var retention := float(soil["retention_bonus_ppm"]) / 1000000.0
	var nutrient_bonus := float(soil["nutrient_bonus_ppm"]) / 1000000.0
	var establishment_bonus := float(soil["establishment_bonus_ppm"]) / 1000000.0
	var env := EnvSample.create(
		0.0, 0.0, 24.0,
		clampf(0.24 + retention * 0.90, 0.0, 1.0),
		0.88,
		clampf(0.20 + nutrient_bonus * 1.20, 0.0, 1.0),
		0.0,
		seed,
		"ECO.EVO7-FFF5|%s|g%d|p%d|o%d" % [mode, generation, parent_index, offspring_index]
	)
	var identity_tag := evaluation_seed_tag(generation, parent_index, offspring_index)
	if identity_tag.is_empty(): return {}
	var fp := _functional(bundle, env, identity_tag)
	if fp.is_empty(): return {}
	var economics := float(bundle["ext_traits"]["leaf_economics_proxy"])
	var fitness := float(fp["net_resource_proxy"]) + float(fp["establishment_capacity"]) * (0.35 + 1.10 * establishment_bonus) + economics * nutrient_bonus * 0.80
	var features := {}
	for field_name in FEATURE_FIELDS: features[field_name] = float(fp[field_name])
	return {"bundle": bundle, "fitness": snappedf(fitness, 1e-9), "leaf_economics_proxy": economics, "features": features}

static func _functional(bundle: Dictionary, env: Dictionary, seed_tag: String) -> Dictionary:
	var envelope := Contract.create_seed_envelope(bundle["genome"], bundle["dev_traits"], String(bundle["lineage"]["lineage_id"]), seed_tag, 0, 1.25)
	var ph2 := CoupledDevelopment.realize(envelope, bundle["dev_traits"], env)
	return FunctionalPhenotype.compile({"genome": bundle["genome"], "ph2_realized": ph2, "traits_extension": bundle["ext_traits"], "environment_sample": env, "age_fraction": 1.0})

static func _rank_order(a: Dictionary, b: Dictionary) -> bool:
	if float(a["fitness"]) != float(b["fitness"]): return float(a["fitness"]) > float(b["fitness"])
	return String(a["bundle"]["bundle_checksum"]) < String(b["bundle"]["bundle_checksum"])

static func _result_hash(result: Dictionary) -> String:
	return "|".join(PackedStringArray([
		SCHEMA,
		VERSION,
		REVISION,
		String(result.get("evaluation_identity_rule", "")),
		str(int(result["lineage_seed"])),
		str(int(result["source_cycles"])),
		String(result["modified_soil"]["state_hash"]),
		String(result["pristine_soil"]["state_hash"]),
		String(result["common_first_candidate_pool_hash"]),
		String(result["modified"]["final_population_hash"]),
		String(result["pristine"]["final_population_hash"]),
	])).sha256_text()

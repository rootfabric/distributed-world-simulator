extends RefCounted

## ECO.EVO7 FFF4 - morphology -> transpiration/root access -> bounded soil-water field -> selection.
## Candidate generation is environment-independent; all scenarios share the exact
## generation-one mutation pool. Only the evaluated water/texture surface differs.
const Morphology = preload("res://scripts/research/ecology/evo7_morphology_evolution_bridge_v1.gd")
const LineageExtension = preload("res://scripts/research/ecology/plant_mutation_lineage_extension_evo7_v1.gd")
const Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const CoupledDevelopment = preload("res://scripts/research/ecology/plant_environment_coupled_development_v1.gd")
const FunctionalPhenotype = preload("res://scripts/research/ecology/plant_functional_phenotype_v1.gd")
const EnvSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const WaterField = preload("res://scripts/research/ecology/soil_water_field_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_water_soil_feedback_bridge.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-FFF4.1"
const SCENARIOS := {
	"dry_sand": {"texture":"sand", "moisture_ppm":180000, "sunlight":0.95, "nutrients":0.25, "temperature_c":28.0, "flood":0.0},
	"mesic_loam": {"texture":"loam", "moisture_ppm":520000, "sunlight":0.82, "nutrients":0.55, "temperature_c":21.0, "flood":0.02},
	"riparian_loam": {"texture":"loam", "moisture_ppm":720000, "sunlight":0.86, "nutrients":0.62, "temperature_c":20.0, "flood":0.30},
	"wet_clay": {"texture":"clay", "moisture_ppm":900000, "sunlight":0.76, "nutrients":0.58, "temperature_c":19.0, "flood":0.55},
}
const FEATURE_FIELDS: Array[String] = [
	"realized_height_m", "realized_crown_radius_m", "realized_crown_density",
	"leaf_area_index_proxy", "realized_root_depth_m", "realized_root_spread_m",
	"root_shoot_ratio", "structural_investment",
]

static func run_all(lineage_seed := 20260823, generations := 28, population_size := 18, offspring_per_parent := 4) -> Dictionary:
	if generations < 2 or population_size < 2 or offspring_per_parent < 1:
		return {}
	var policy := LineageExtension.default_policy()
	policy["morphology_probability"] = 0.50
	policy["genome_policy"]["mutation_probability"] = 0.50
	policy["genome_policy"]["root_depth_m_step"] = 0.45
	if LineageExtension.policy_hash(policy).is_empty():
		return {}
	var ancestor := Morphology.default_ancestor_bundle(lineage_seed)
	if ancestor.is_empty():
		return {}
	var results := {}
	var common_pool := ""
	var names := PackedStringArray(SCENARIOS.keys())
	names.sort()
	for scenario_name in names:
		var scenario := _run_scenario(ancestor, scenario_name, SCENARIOS[scenario_name], lineage_seed,
			generations, population_size, offspring_per_parent, policy)
		if scenario.is_empty():
			return {}
		if common_pool.is_empty():
			common_pool = String(scenario["first_candidate_pool_hash"])
		elif common_pool != String(scenario["first_candidate_pool_hash"]):
			return {}
		results[scenario_name] = scenario
	var dry: Dictionary = results["dry_sand"]
	var mesic: Dictionary = results["mesic_loam"]
	var result := {
		"schema": SCHEMA, "version": VERSION, "revision": REVISION,
		"lineage_seed": lineage_seed, "generations": generations,
		"population_size": population_size, "offspring_per_parent": offspring_per_parent,
		"policy_hash": LineageExtension.policy_hash(policy),
		"common_first_candidate_pool_hash": common_pool,
		"scenarios": results,
		"dry_minus_mesic": {
			"leaf_area_index_proxy": snappedf(float(dry["mean_features"]["leaf_area_index_proxy"]) - float(mesic["mean_features"]["leaf_area_index_proxy"]), 1e-9),
			"realized_root_depth_m": snappedf(float(dry["mean_features"]["realized_root_depth_m"]) - float(mesic["mean_features"]["realized_root_depth_m"]), 1e-9),
			"root_shoot_ratio": snappedf(float(dry["mean_features"]["root_shoot_ratio"]) - float(mesic["mean_features"]["root_shoot_ratio"]), 1e-9),
			"realized_height_m": snappedf(float(dry["mean_features"]["realized_height_m"]) - float(mesic["mean_features"]["realized_height_m"]), 1e-9),
		},
	}
	result["result_hash"] = _result_hash(result, names)
	return result

static func _run_scenario(ancestor: Dictionary, scenario_name: String, cfg: Dictionary, lineage_seed: int,
		generations: int, population_size: int, offspring_per_parent: int, policy: Dictionary) -> Dictionary:
	var population: Array[Dictionary] = []
	for index in population_size:
		var bundle: Dictionary = ancestor.duplicate(true)
		var individual_seed := Contract.derive_individual_seed(String(bundle["lineage"]["lineage_id"]),
			"evo7-fff4-gen0|%d" % index, index, String(bundle["genome"]["version"]))
		bundle["individual_seed"] = individual_seed
		bundle["bundle_checksum"] = LineageExtension.bundle_checksum(bundle["genome"], bundle["dev_traits"],
			bundle["ext_traits"], bundle["lineage"], individual_seed)
		population.append({"bundle":bundle, "fitness":0.0})
	var first_pool_hash := ""
	var last_water_hash := ""
	var last_water_after := 0
	for generation in range(1, generations + 1):
		var candidates: Array[Dictionary] = []
		var pool_tokens := PackedStringArray()
		for parent_index in population.size():
			var parent: Dictionary = population[parent_index]
			for offspring_index in offspring_per_parent:
				var mutation_seed := ("EVO7-FFF4|%d|%d|%d|%d" % [lineage_seed, generation, parent_index, offspring_index]).hash()
				var child := LineageExtension.reproduce_bundle(parent["bundle"], mutation_seed, offspring_index, policy)
				if child.is_empty():
					return {}
				candidates.append({"bundle":child["bundle"], "mutation_result_hash":String(child["result_hash"])})
				pool_tokens.append(String(child["result_hash"]))
		if generation == 1:
			first_pool_hash = "|".join(pool_tokens).sha256_text()
		var evaluated := _evaluate_pool(candidates, scenario_name, cfg, lineage_seed, generation)
		if evaluated.is_empty():
			return {}
		last_water_hash = String(evaluated[0]["water_field_hash"])
		last_water_after = int(evaluated[0]["water_after_ppm"])
		evaluated.sort_custom(_rank_order)
		population = evaluated.slice(0, population_size)

	var sums := {}
	for field_name in FEATURE_FIELDS:
		sums[field_name] = 0.0
	var satisfaction_sum := 0.0
	var fitness_sum := 0.0
	var checksums := PackedStringArray()
	for entry in population:
		checksums.append(String(entry["bundle"]["bundle_checksum"]))
		fitness_sum += float(entry["fitness"])
		satisfaction_sum += float(entry["water_satisfaction"])
		for field_name in FEATURE_FIELDS:
			sums[field_name] += float(entry["features"][field_name])
	var means := {}
	for field_name in FEATURE_FIELDS:
		means[field_name] = snappedf(float(sums[field_name]) / float(population.size()), 1e-9)
	checksums.sort()
	return {
		"scenario": scenario_name,
		"texture": String(cfg["texture"]),
		"first_candidate_pool_hash": first_pool_hash,
		"final_population_hash": "|".join(checksums).sha256_text(),
		"mean_features": means,
		"mean_water_satisfaction": snappedf(satisfaction_sum / float(population.size()), 1e-9),
		"mean_fitness": snappedf(fitness_sum / float(population.size()), 1e-9),
		"final_water_field_hash": last_water_hash,
		"final_water_after_ppm": last_water_after,
	}

static func _evaluate_pool(candidates: Array[Dictionary], scenario_name: String, cfg: Dictionary,
		lineage_seed: int, generation: int) -> Array[Dictionary]:
	var base_env := _environment(cfg, lineage_seed, generation, scenario_name, float(cfg["moisture_ppm"]) / 1000000.0)
	var provisional: Array[Dictionary] = []
	var records: Array = []
	for index in candidates.size():
		var bundle: Dictionary = candidates[index]["bundle"]
		var fp := _functional(bundle, base_env, "fff4-base|%s|%d|%d" % [scenario_name, generation, index])
		if fp.is_empty():
			return []
		var identity := "c%04d" % index
		provisional.append({"identity":identity, "bundle":bundle, "base_fp":fp})
		records.append({
			"identity": identity, "cell_identity":"stand-0",
			"realized_root_depth_m":float(fp["realized_root_depth_m"]),
			"realized_root_spread_m":float(fp["realized_root_spread_m"]),
			"root_shoot_ratio":float(fp["root_shoot_ratio"]),
			"leaf_area_index_proxy":float(fp["leaf_area_index_proxy"]),
			"transpiration_demand_ppm":int(fp["transpiration_demand_ppm"]),
			"shade_output_ppm":int(fp["shade_output_ppm"]),
			"source_phenotype_hash":String(fp["phenotype_hash"]),
		})
	var water := WaterField.compute(int(cfg["moisture_ppm"]), String(cfg["texture"]), float(cfg["sunlight"]), records, generation)
	if water.is_empty():
		return []
	var evaluated: Array[Dictionary] = []
	for index in provisional.size():
		var item: Dictionary = provisional[index]
		var water_item: Dictionary = water["plant_water"][String(item["identity"])]
		var effective_moisture := float(water_item["effective_soil_moisture"])
		var derived_env := _environment(cfg, lineage_seed, generation, "%s|%s" % [scenario_name, String(item["identity"])], effective_moisture)
		var fp := _functional(item["bundle"], derived_env, "fff4-final|%s|%d|%d" % [scenario_name, generation, index])
		if fp.is_empty():
			return []
		var satisfaction := float(water_item["water_satisfaction"])
		var drought_penalty := (1.0 - satisfaction) * (0.35 + 0.18 * float(fp["leaf_area_index_proxy"]))
		var fitness := float(fp["net_resource_proxy"]) + 0.45 * float(fp["establishment_capacity"]) - drought_penalty
		var features := {}
		for field_name in FEATURE_FIELDS:
			features[field_name] = float(fp[field_name])
		evaluated.append({
			"bundle":item["bundle"], "fitness":snappedf(fitness, 1e-9), "features":features,
			"water_satisfaction":snappedf(satisfaction, 1e-9),
			"water_field_hash":String(water["field_hash"]), "water_after_ppm":int(water["water_after_ppm"]),
		})
	return evaluated

static func _functional(bundle: Dictionary, env: Dictionary, seed_tag: String) -> Dictionary:
	var envelope := Contract.create_seed_envelope(bundle["genome"], bundle["dev_traits"],
		String(bundle["lineage"]["lineage_id"]), seed_tag, 0, 1.25)
	var ph2 := CoupledDevelopment.realize(envelope, bundle["dev_traits"], env)
	return FunctionalPhenotype.compile({"genome":bundle["genome"], "ph2_realized":ph2,
		"traits_extension":bundle["ext_traits"], "environment_sample":env, "age_fraction":1.0})

static func _environment(cfg: Dictionary, seed: int, generation: int, revision_tag: String, moisture: float) -> Dictionary:
	return EnvSample.create(0.0, 0.0, float(cfg["temperature_c"]), clampf(moisture, 0.0, 1.0),
		float(cfg["sunlight"]), float(cfg["nutrients"]), float(cfg["flood"]), seed,
		"ECO.EVO7-FFF4|%s|g%d" % [revision_tag, generation])

static func _rank_order(a: Dictionary, b: Dictionary) -> bool:
	if float(a["fitness"]) != float(b["fitness"]):
		return float(a["fitness"]) > float(b["fitness"])
	return String(a["bundle"]["bundle_checksum"]) < String(b["bundle"]["bundle_checksum"])

static func _result_hash(result: Dictionary, names: PackedStringArray) -> String:
	var tokens := PackedStringArray([SCHEMA, VERSION, REVISION, str(int(result["lineage_seed"])),
		str(int(result["generations"])), String(result["policy_hash"]), String(result["common_first_candidate_pool_hash"])])
	for name in names:
		var scenario: Dictionary = result["scenarios"][name]
		tokens.append("%s:%s:%s:%s" % [name, String(scenario["first_candidate_pool_hash"]),
			String(scenario["final_population_hash"]), String(scenario["final_water_field_hash"])])
	return "|".join(tokens).sha256_text()
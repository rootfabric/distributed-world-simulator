extends SceneTree

const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const LineageRecord = preload("res://scripts/research/ecology/plant_lineage_record_v1.gd")
const MutationKernel = preload("res://scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd")
const Selection = preload("res://scripts/research/ecology/plant_spatial_selection_baseline_v1.gd")

const EXPECTED_RESULT_HASH := "a48df039415162a2e2b75fb9badc12ae35fd0cac9f459ae2ba9df88ab1280e80"
const EXPECTED_ALT_RESULT_HASH := "507bcc108d458b685d97b96268d18e307f3cdc36ae0530a75801cddf2e6b8521"
const EXPECTED_FIRST_CANDIDATE_POOL_HASH := "9e4b8eba9d7d6bf915de209814e6edba823f30675c6f2aefa6a209fff135f2fd"
const EXPECTED_SITE_HASHES := {
	"floodplain": "72b81dc3517b1fb83d4e399e8ad474cd861c58d2cd02180c25f35d3183ae2675",
	"sunny_slope": "8ebd42f98ebabc02734bc20a63d328f657c59927764e20c4afdb06818d129174",
	"shaded_slope": "2bd973a2836562924fb00bd40aaf652f759871abd275efe3460191a0c1a02878",
	"dry_ridge": "fdef2715804d2c2941e840ae0d1e9ee1275dd4796e781aa8cd4f677487f9ca32",
}

var assertions := 0
var failures: Array[String] = []
var result: Dictionary = {}
var alt_result: Dictionary = {}

func _init() -> void:
	_test_contract_boundaries()
	_run_baselines()
	_test_common_mutation_pool_then_environment_selection()
	_test_resource_consequence_improvement()
	_test_trait_divergence()
	_test_native_environment_advantage()
	_test_lineage_and_genome_integrity()
	_test_second_seed_preserves_phenomenon()
	_finish()

func _test_contract_boundaries() -> void:
	_check(String(Selection.EXPERIMENT_REVISION) == "ECO.P1B-S2.1", "P1B-S2 revision fixed")
	_check(Selection.DEFAULT_SITES == ["floodplain", "sunny_slope", "shaded_slope", "dry_ridge"], "diagnostic selection sites fixed")
	_check(Selection.DEFAULT_GENERATIONS == 16, "baseline generations fixed")
	_check(Selection.DEFAULT_POPULATION_SIZE == 12, "baseline population size fixed")
	_check(Selection.DEFAULT_OFFSPRING_PER_PARENT == 3, "baseline offspring count fixed")
	_check(Selection.DEFAULT_EVAL_SEASONS == 16, "accepted biomass observation window fixed")
	var policy := Selection.selection_mutation_policy()
	_check(bool(MutationKernel.validate_policy(policy).get("success", false)), "selection mutation policy validates")
	_check(_approx(float(policy["mutation_probability"]), 0.24), "selection mutation probability explicit")
	_check(_approx(float(policy["seed_dispersal_distance_m_step"]), 0.0), "dispersal mutation disabled until dispersal benefit exists")
	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_spatial_selection_baseline_v1.gd")
	for forbidden in ["biome_id", "biome ==", "DESERT_PLANT", "RIVER_PLANT", "FOREST_TREE", "species_class", "controlled_trait_probes_v1"]:
		_check(source.find(forbidden) < 0, "selection excludes predefined biome/species rule: %s" % forbidden)
	for forbidden in ["Camera3D", "CanvasLayer", "presentation_lod", "AuthorityRegion", "ENetMultiplayerPeer"]:
		_check(source.find(forbidden) < 0, "selection excludes presentation/authority input: %s" % forbidden)
	_check(source.find("ResourceModel.evaluate") >= 0, "selection ranking consumes accepted P1A ResourceModel")
	_check(source.find("PatchSimulator.simulate") >= 0, "population evidence consumes accepted P1A PatchSimulator")

func _run_baselines() -> void:
	result = Selection.run()
	alt_result = Selection.run(
		Selection.DEFAULT_SITES,
		Selection.DEFAULT_GENERATIONS,
		Selection.DEFAULT_POPULATION_SIZE,
		Selection.DEFAULT_OFFSPRING_PER_PARENT,
		Selection.DEFAULT_EVAL_SEASONS,
		Selection.DEFAULT_LINEAGE_SEED + 1
	)
	_check(not result.is_empty(), "default spatial-selection run builds")
	_check(not alt_result.is_empty(), "second-seed spatial-selection run builds")
	_check(String(result.get("schema", "")) == Selection.SCHEMA, "result schema")
	_check(String(result.get("version", "")) == Selection.VERSION, "result version")
	_check(String(result.get("experiment_revision", "")) == Selection.EXPERIMENT_REVISION, "result revision")
	_check(String(result.get("result_hash", "")) == EXPECTED_RESULT_HASH, "default fixed result hash")
	_check(String(alt_result.get("result_hash", "")) == EXPECTED_ALT_RESULT_HASH, "second-seed fixed result hash")
	_check(String(result.get("result_hash", "")) != String(alt_result.get("result_hash", "")), "different lineage seed changes evolved result")
	_check(String(result.get("ancestor_genome_checksum", "")) == String(PlantGenome.create_default()["checksum"]), "one accepted ancestor genotype seeds experiment")
	_check(int(result.get("generations", -1)) == Selection.DEFAULT_GENERATIONS, "generation count recorded")
	_check(int(result.get("population_size", -1)) == Selection.DEFAULT_POPULATION_SIZE, "population size recorded")
	_check(int(result.get("offspring_per_parent", -1)) == Selection.DEFAULT_OFFSPRING_PER_PARENT, "offspring count recorded")
	_check(int(result.get("eval_seasons", -1)) == Selection.DEFAULT_EVAL_SEASONS, "evaluation seasons recorded")

func _test_common_mutation_pool_then_environment_selection() -> void:
	var candidate_pool_hashes := {}
	var selected_hashes := {}
	var final_hashes := {}
	for site_name in Selection.DEFAULT_SITES:
		var site: Dictionary = result["sites"][site_name]
		_check(String(site["site_hash"]) == String(EXPECTED_SITE_HASHES[site_name]), "fixed site hash %s" % site_name)
		_check(Array(site["history"]).size() == Selection.DEFAULT_GENERATIONS + 1, "history includes founder plus generations %s" % site_name)
		var first_generation: Dictionary = site["history"][1]
		candidate_pool_hashes[String(first_generation["candidate_pool_hash"])] = true
		selected_hashes[String(first_generation["selected_population_hash"])] = true
		final_hashes[String(site["final_population_hash"])] = true
		_check(String(first_generation["candidate_pool_hash"]) == EXPECTED_FIRST_CANDIDATE_POOL_HASH, "same generation-one mutation pool %s" % site_name)
		_check(int(first_generation["candidate_count"]) == Selection.DEFAULT_POPULATION_SIZE * Selection.DEFAULT_OFFSPRING_PER_PARENT, "candidate count %s" % site_name)
	_check(candidate_pool_hashes.size() == 1, "all environments receive identical first mutation candidate pool")
	_check(selected_hashes.size() == Selection.DEFAULT_SITES.size(), "environment selects different generation-one populations")
	_check(final_hashes.size() == Selection.DEFAULT_SITES.size(), "spatial selection yields distinct final populations")

func _test_resource_consequence_improvement() -> void:
	for site_name in Selection.DEFAULT_SITES:
		var site: Dictionary = result["sites"][site_name]
		var initial: Dictionary = site["initial"]
		var final: Dictionary = site["final"]
		_check(float(final["average_final_net_resource_balance"]) > float(initial["average_final_net_resource_balance"]) + 0.20, "selection improves accepted net resource consequence %s" % site_name)
		_check(float(final["average_final_biomass_kg_m2"]) > float(initial["average_final_biomass_kg_m2"]), "selection improves observed biomass %s" % site_name)
		_check(float(final["average_recruitment_kg_m2"]) >= float(initial["average_recruitment_kg_m2"]), "selection does not reduce observed recruitment %s" % site_name)
		_check(int(final["population_count"]) == Selection.DEFAULT_POPULATION_SIZE, "population size conserved through baseline selection %s" % site_name)
	_check(float(result["sites"]["shaded_slope"]["final"]["average_final_net_resource_balance"]) > 0.0, "selection rescues shaded slope to positive average net")
	_check(float(result["sites"]["dry_ridge"]["final"]["average_final_net_resource_balance"]) > 0.0, "selection rescues dry ridge to positive average net")
	_check(float(result["sites"]["shaded_slope"]["final"]["average_recruitment_kg_m2"]) > 0.0, "shaded population gains actual recruitment")
	_check(float(result["sites"]["dry_ridge"]["final"]["average_recruitment_kg_m2"]) > 0.0, "dry population gains actual recruitment")

func _test_trait_divergence() -> void:
	var flood: Dictionary = result["sites"]["floodplain"]["final"]["trait_means"]
	var sunny: Dictionary = result["sites"]["sunny_slope"]["final"]["trait_means"]
	var shaded: Dictionary = result["sites"]["shaded_slope"]["final"]["trait_means"]
	var dry: Dictionary = result["sites"]["dry_ridge"]["final"]["trait_means"]
	_check(float(dry["root_depth_m"]) > float(flood["root_depth_m"]) + 0.70, "dry selection favors much deeper roots than floodplain")
	_check(float(flood["water_preference"]) > float(dry["water_preference"]) + 0.25, "wet vs dry selection separates water preference")
	_check(float(shaded["shade_tolerance"]) > float(sunny["shade_tolerance"]) + 0.15, "shaded selection favors greater shade tolerance than sunny slope")
	_check(float(flood["root_depth_m"]) < 0.35, "floodplain selection sheds unnecessary root cost")
	_check(float(dry["root_depth_m"]) > 0.90, "dry selection retains deeper root investment")
	var divergence: Dictionary = result["trait_divergence"]
	_check(float(divergence["water_preference"]) > 0.30, "water preference divergence measurable")
	_check(float(divergence["root_depth_m"]) > 0.85, "root-depth divergence measurable")
	_check(float(divergence["shade_tolerance"]) > 0.18, "shade-tolerance divergence measurable")
	_check(_approx(float(divergence["seed_dispersal_distance_m"]), 0.0), "dispersal remains neutral/frozen before migration benefit exists")
	for site_name in Selection.DEFAULT_SITES:
		_check(_approx(float(result["sites"][site_name]["final"]["trait_means"]["seed_dispersal_distance_m"]), 15.0), "dispersal trait not spuriously optimized %s" % site_name)

func _test_native_environment_advantage() -> void:
	var matrix: Dictionary = result["cross_environment_net"]
	for environment_site in Selection.DEFAULT_SITES:
		var native_value := float(matrix[environment_site][environment_site])
		for population_site in Selection.DEFAULT_SITES:
			if population_site == environment_site:
				continue
			_check(native_value > float(matrix[population_site][environment_site]) + 0.01, "native population best in %s versus %s" % [environment_site, population_site])

func _test_lineage_and_genome_integrity() -> void:
	var lineage_ids := {}
	for site_name in Selection.DEFAULT_SITES:
		var individuals := {}
		var population: Array = result["sites"][site_name]["final_population"]
		_check(population.size() == Selection.DEFAULT_POPULATION_SIZE, "final population materialized %s" % site_name)
		for entry in population:
			var genome: Dictionary = entry["genome"]
			var lineage: Dictionary = entry["lineage"]
			_check(bool(PlantGenome.validate(genome).get("success", false)), "final genome validates %s" % site_name)
			_check(bool(LineageRecord.validate(lineage).get("success", false)), "final lineage validates %s" % site_name)
			_check(int(lineage["generation"]) == Selection.DEFAULT_GENERATIONS + 1, "final generation exact %s" % site_name)
			_check(String(lineage["genome_checksum"]) == String(genome["checksum"]), "lineage binds genotype %s" % site_name)
			_check(not individuals.has(String(lineage["individual_id"])), "final individual unique within %s" % site_name)
			individuals[String(lineage["individual_id"])] = true
			lineage_ids[String(lineage["lineage_id"])] = true
	_check(lineage_ids.size() == 1, "all selected populations remain descendants of one ancestral lineage")

func _test_second_seed_preserves_phenomenon() -> void:
	for site_name in Selection.DEFAULT_SITES:
		var initial: Dictionary = alt_result["sites"][site_name]["initial"]
		var final: Dictionary = alt_result["sites"][site_name]["final"]
		_check(float(final["average_final_net_resource_balance"]) > float(initial["average_final_net_resource_balance"]) + 0.20, "second seed improves local resource consequence %s" % site_name)
	var flood: Dictionary = alt_result["sites"]["floodplain"]["final"]["trait_means"]
	var sunny: Dictionary = alt_result["sites"]["sunny_slope"]["final"]["trait_means"]
	var shaded: Dictionary = alt_result["sites"]["shaded_slope"]["final"]["trait_means"]
	var dry: Dictionary = alt_result["sites"]["dry_ridge"]["final"]["trait_means"]
	_check(float(dry["root_depth_m"]) > float(flood["root_depth_m"]) + 0.60, "second seed repeats dry-vs-wet root specialization")
	_check(float(flood["water_preference"]) > float(dry["water_preference"]) + 0.25, "second seed repeats water preference specialization")
	_check(float(shaded["shade_tolerance"]) > float(sunny["shade_tolerance"]) + 0.15, "second seed repeats shade specialization")
	var matrix: Dictionary = alt_result["cross_environment_net"]
	for environment_site in Selection.DEFAULT_SITES:
		var native_value := float(matrix[environment_site][environment_site])
		for population_site in Selection.DEFAULT_SITES:
			if population_site == environment_site:
				continue
			_check(native_value > float(matrix[population_site][environment_site]) + 0.01, "second seed native advantage %s versus %s" % [environment_site, population_site])

func _approx(a: float, b: float, tolerance: float = 0.000000001) -> bool:
	return absf(a - b) <= tolerance

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	print("ECO.P1B-S2 result_hash=%s" % String(result.get("result_hash", "")))
	print("ECO.P1B-S2 alt_result_hash=%s" % String(alt_result.get("result_hash", "")))
	print("ECO.P1B-S2 trait_divergence=%s" % str(result.get("trait_divergence", {})))
	print("ECO.P1B-S2 cross_environment_net=%s" % str(result.get("cross_environment_net", {})))
	if failures.is_empty():
		print("ECO.P1B-S2 Spatial Selection Baseline: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.P1B-S2 FAIL: %s" % failure)
	print("ECO.P1B-S2 Spatial Selection Baseline: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)

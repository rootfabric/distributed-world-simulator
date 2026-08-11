extends SceneTree

const Field = preload("res://scripts/research/ecology/plant_regional_population_field_v1.gd")
const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")

const EXPECTED_RESULT_HASH := "cbd2f4a65f2a06f8ee9feeea0d9eae90d37cd0ede15df1bd808ef52773089b56"
const EXPECTED_NEUTRAL_HASH := "b4d18ef35a2a77104fa18c8a3f3004a6f5898d572e57917429cc955cc7e2c5e6"
const EXPECTED_ALT_HASH := "ca81e0cfea0b05850470276fef10c880d3832613df9ff7f35d3c7395bd32589b"

var assertions := 0
var failures: Array[String] = []
var result: Dictionary
var neutral: Dictionary
var alternate: Dictionary

func _init() -> void:
	result = Field.run()
	neutral = Field.run(Field.DEFAULT_GRID_SIZE, Field.DEFAULT_GENERATIONS, Field.DEFAULT_POPULATION_SIZE, Field.DEFAULT_OFFSPRING_PER_PARENT, Field.DEFAULT_LINEAGE_SEED, true)
	alternate = Field.run(Field.DEFAULT_GRID_SIZE, Field.DEFAULT_GENERATIONS, Field.DEFAULT_POPULATION_SIZE, Field.DEFAULT_OFFSPRING_PER_PARENT, Field.ALT_LINEAGE_SEED, false)
	_test_contract_and_hashes()
	_test_single_ancestor_and_patch_population_identity()
	_test_selection_improves_field_resource_balance()
	_test_diagnostic_regions_are_observational()
	_test_regional_trait_divergence_over_time()
	_test_trait_environment_correlations()
	_test_neutral_control_separates_selection_signal()
	_test_alternate_seed_preserves_specialization()
	_test_first_generation_mutation_stream_is_environment_independent()
	_test_source_boundaries()
	_finish()

func _test_contract_and_hashes() -> void:
	_check(not result.is_empty(), "default field result exists")
	_check(not neutral.is_empty(), "neutral control exists")
	_check(not alternate.is_empty(), "alternate seed result exists")
	_check(String(result.get("schema", "")) == Field.SCHEMA, "schema exact")
	_check(String(result.get("version", "")) == Field.VERSION, "version exact")
	_check(String(result.get("experiment_revision", "")) == Field.EXPERIMENT_REVISION, "revision exact")
	_check(String(result.get("result_hash", "")) == EXPECTED_RESULT_HASH, "default result hash fixed")
	_check(String(neutral.get("result_hash", "")) == EXPECTED_NEUTRAL_HASH, "neutral result hash fixed")
	_check(String(alternate.get("result_hash", "")) == EXPECTED_ALT_HASH, "alternate result hash fixed")
	_check(String(result.get("result_hash", "")) != String(alternate.get("result_hash", "")), "alternate seed changes exact evolved field")
	_check(int(result.get("grid_size", 0)) == Field.DEFAULT_GRID_SIZE, "grid size recorded")
	_check(int(result.get("patch_count", 0)) == Field.DEFAULT_GRID_SIZE * Field.DEFAULT_GRID_SIZE, "patch count exact")
	_check(int(result.get("generations", 0)) == Field.DEFAULT_GENERATIONS, "generation count exact")
	_check(int(result.get("population_size", 0)) == Field.DEFAULT_POPULATION_SIZE, "population size exact")
	_check(int(result.get("offspring_per_parent", 0)) == Field.DEFAULT_OFFSPRING_PER_PARENT, "offspring count exact")
	_check(Array(result.get("history", [])).size() == Field.DEFAULT_GENERATIONS + 1, "field history complete")
	_check(Array(result.get("regional_history", [])).size() == Field.DEFAULT_GENERATIONS + 1, "regional history complete")
	_check(not bool(result.get("neutral_control", true)), "default uses real heterogeneous environment")
	_check(bool(neutral.get("neutral_control", false)), "neutral control recorded")

func _test_single_ancestor_and_patch_population_identity() -> void:
	var ancestor := PlantGenome.create_default()
	_check(String(result.get("ancestor_genome_checksum", "")) == String(ancestor["checksum"]), "one accepted ancestor genotype")
	var lineage_id := String(result.get("ancestor_lineage_id", ""))
	_check(not lineage_id.is_empty(), "ancestor lineage id exists")
	var unique_population_hashes := {}
	for patch in Array(result.get("patches", [])):
		_check(int(patch.get("lineage_id_count", 0)) == 1, "one lineage id inside patch %d" % int(patch["patch_index"]))
		_check(String(patch.get("lineage_id", "")) == lineage_id, "all patches preserve one ancestral lineage %d" % int(patch["patch_index"]))
		_check(_approx(float(patch["trait_means"]["seed_dispersal_distance_m"]), 15.0), "dispersal remains frozen before migration %d" % int(patch["patch_index"]))
		unique_population_hashes[String(patch["population_hash"])] = true
	_check(unique_population_hashes.size() > 40, "heterogeneous selection creates many distinct patch populations")
	_check(int(result["initial_field"]["individual_count"]) == Field.DEFAULT_GRID_SIZE * Field.DEFAULT_GRID_SIZE * Field.DEFAULT_POPULATION_SIZE, "initial field population count")
	_check(int(result["final_field"]["individual_count"]) == int(result["initial_field"]["individual_count"]), "population count conserved")

func _test_selection_improves_field_resource_balance() -> void:
	var initial_net := float(result["initial_field"]["average_net_resource_balance"])
	var final_net := float(result["final_field"]["average_net_resource_balance"])
	_check(initial_net < 0.0, "ancestor field begins net-negative on average")
	_check(final_net > 0.0, "evolved field becomes net-positive on average")
	_check(final_net > initial_net + 0.30, "selection produces large accepted resource improvement")
	var previous := -INF
	var unique_hashes := {}
	for summary in Array(result["history"]):
		var value := float(summary["average_net_resource_balance"])
		_check(value > previous - 0.000000001, "field average net is non-decreasing generation %d" % int(summary["generation"]))
		previous = value
		unique_hashes[String(summary["field_population_hash"])] = true
	_check(unique_hashes.size() == Field.DEFAULT_GENERATIONS + 1, "every generation changes field population identity")

func _test_diagnostic_regions_are_observational() -> void:
	var regions: Dictionary = result["diagnostic_regions"]["patches"]
	for region_name in Field.REGION_NAMES:
		_check(regions.has(region_name), "diagnostic region exists %s" % region_name)
		_check(Array(regions[region_name]).size() >= 12, "diagnostic region has enough patches %s" % region_name)
	var stats: Dictionary = result["regional_stats"]
	_check(float(stats["WET"]["mean_soil_moisture"]) > float(stats["DRY"]["mean_soil_moisture"]) + 0.25, "wet and dry diagnostics actually contrast moisture")
	_check(float(stats["SUNLIT"]["mean_sunlight"]) > float(stats["SHADED"]["mean_sunlight"]) + 0.25, "sunlit and shaded diagnostics actually contrast light")
	var initial_regions: Dictionary = result["regional_history"][0]["regions"]
	for trait_name in Field.TRAITS:
		var expected := float(PlantGenome.create_default()[trait_name])
		for region_name in Field.REGION_NAMES:
			_check(_approx(float(initial_regions[region_name]["traits"][trait_name]["mean"]), expected), "region labels do not alter founder trait %s %s" % [region_name, trait_name])

func _test_regional_trait_divergence_over_time() -> void:
	var mid: Dictionary = result["regional_history"][4]["regions"]
	var final_regions: Dictionary = result["regional_stats"]
	_check(float(mid["WET"]["traits"]["water_preference"]["mean"]) > float(mid["DRY"]["traits"]["water_preference"]["mean"]) + 0.04, "wet-dry water preference divergence visible mid-run")
	_check(float(mid["DRY"]["traits"]["root_depth_m"]["mean"]) > float(mid["WET"]["traits"]["root_depth_m"]["mean"]) + 0.10, "dry-wet root divergence visible mid-run")
	_check(float(final_regions["WET"]["traits"]["water_preference"]["mean"]) > float(final_regions["DRY"]["traits"]["water_preference"]["mean"]) + 0.075, "wet region evolves higher water preference")
	_check(float(final_regions["DRY"]["traits"]["root_depth_m"]["mean"]) > float(final_regions["WET"]["traits"]["root_depth_m"]["mean"]) + 0.20, "dry region evolves deeper roots")
	_check(float(final_regions["SHADED"]["traits"]["shade_tolerance"]["mean"]) > float(final_regions["SUNLIT"]["traits"]["shade_tolerance"]["mean"]) + 0.035, "shaded region evolves higher shade tolerance")
	_check(float(final_regions["DRY"]["traits"]["root_depth_m"]["variance"]) > 0.0, "dry region retains trait variance")
	_check(float(final_regions["WET"]["traits"]["water_preference"]["variance"]) > 0.0, "wet region retains trait variance")

func _test_trait_environment_correlations() -> void:
	var corr: Dictionary = result["correlations"]
	_check(float(corr["water_preference_vs_moisture"]) > 0.80, "water preference strongly tracks moisture")
	_check(float(corr["root_depth_vs_moisture"]) < -0.50, "root depth anti-correlates with moisture")
	_check(float(corr["shade_tolerance_vs_sunlight"]) < -0.40, "shade tolerance anti-correlates with sunlight")

func _test_neutral_control_separates_selection_signal() -> void:
	var real_corr: Dictionary = result["correlations"]
	var neutral_corr: Dictionary = neutral["correlations"]
	_check(float(real_corr["water_preference_vs_moisture"]) > float(neutral_corr["water_preference_vs_moisture"]) + 0.60, "real moisture selection exceeds neutral spatial noise")
	_check(absf(float(real_corr["root_depth_vs_moisture"])) > absf(float(neutral_corr["root_depth_vs_moisture"])) + 0.45, "real root-moisture signal exceeds neutral")
	_check(absf(float(real_corr["shade_tolerance_vs_sunlight"])) > absf(float(neutral_corr["shade_tolerance_vs_sunlight"])) + 0.20, "real shade signal exceeds neutral")
	var different_selected := 0
	for i in range(Array(result["patches"]).size()):
		var real_patch: Dictionary = result["patches"][i]
		var neutral_patch: Dictionary = neutral["patches"][i]
		_check(String(real_patch["first_candidate_pool_hash"]) == String(neutral_patch["first_candidate_pool_hash"]), "real and neutral share exact first mutation pool patch %d" % i)
		if String(real_patch["first_selected_population_hash"]) != String(neutral_patch["first_selected_population_hash"]):
			different_selected += 1
	_check(different_selected > 30, "heterogeneous environment changes first-generation selection in most patches")

func _test_alternate_seed_preserves_specialization() -> void:
	var corr: Dictionary = alternate["correlations"]
	_check(float(corr["water_preference_vs_moisture"]) > 0.80, "alternate seed preserves water specialization")
	_check(float(corr["root_depth_vs_moisture"]) < -0.45, "alternate seed preserves root specialization")
	_check(float(corr["shade_tolerance_vs_sunlight"]) < -0.40, "alternate seed preserves shade specialization")
	var regions: Dictionary = alternate["regional_stats"]
	_check(float(regions["WET"]["traits"]["water_preference"]["mean"]) > float(regions["DRY"]["traits"]["water_preference"]["mean"]) + 0.07, "alternate seed wet-dry water preference divergence")
	_check(float(regions["DRY"]["traits"]["root_depth_m"]["mean"]) > float(regions["WET"]["traits"]["root_depth_m"]["mean"]) + 0.12, "alternate seed dry-wet root divergence")
	_check(float(regions["SHADED"]["traits"]["shade_tolerance"]["mean"]) > float(regions["SUNLIT"]["traits"]["shade_tolerance"]["mean"]) + 0.03, "alternate seed shade divergence")

func _test_first_generation_mutation_stream_is_environment_independent() -> void:
	for i in range(Array(result["patches"]).size()):
		_check(not String(result["patches"][i]["first_candidate_pool_hash"]).is_empty(), "first candidate pool recorded patch %d" % i)
		_check(String(result["patches"][i]["first_candidate_pool_hash"]) == String(neutral["patches"][i]["first_candidate_pool_hash"]), "selection environment cannot alter generated candidates patch %d" % i)

func _test_source_boundaries() -> void:
	var path := "res://scripts/research/ecology/plant_regional_population_field_v1.gd"
	var source := FileAccess.get_file_as_string(path).to_lower()
	_check(not source.contains("biome"), "no biome logic in regional field source")
	_check(not source.contains("species"), "no species classes in regional field source")
	_check(not source.contains("camera"), "no camera/presentation input")
	_check(not source.contains("authority"), "no authority input")
	_check(not source.contains("network"), "no network input")
	_check(source.contains("resourcemodel.evaluate"), "selection delegates to accepted P1A resource model")
	_check(source.contains("neutral_control"), "neutral control is explicit research mode")

func _approx(a: float, b: float, tolerance: float = 0.000000001) -> bool:
	return absf(a - b) <= tolerance

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	print("ECO.P1B-S3 result_hash=%s" % String(result.get("result_hash", "")))
	print("ECO.P1B-S3 neutral_hash=%s" % String(neutral.get("result_hash", "")))
	print("ECO.P1B-S3 alt_result_hash=%s" % String(alternate.get("result_hash", "")))
	print("ECO.P1B-S3 correlations=%s" % str(result.get("correlations", {})))
	print("ECO.P1B-S3 regional_stats=%s" % str(result.get("regional_stats", {})))
	if failures.is_empty():
		print("ECO.P1B-S3 Regional Population Field: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.P1B-S3 FAIL: %s" % failure)
	print("ECO.P1B-S3 Regional Population Field: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)

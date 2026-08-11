extends SceneTree

const Competition = preload("res://scripts/research/ecology/plant_strategy_competition_baseline_v1.gd")
const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")

const EXPECTED_RESULT_HASH := "cf3bd5f417c9a49dd1c5eac0d93ea736b02ec0be25afd4945b1424a8dbde3928"
const EXPECTED_UNIFORM_HASH := "1c5128666314dfeec9ed09094931be58e76253f92bf9da50379a91eeb3b68a58"
const EXPECTED_ALT_HASH := "bded62e12ade0285c019d0dc2e4f77d0d6cb88431df7ade605160e0f18d82f8c"
const EXPECTED_FOUNDER_POOL_HASH := "77acaada39a39c54224b73f2548ebc228343e869264e45780d08419ebb6bee38"

var assertions := 0
var failures: Array[String] = []
var result: Dictionary
var uniform: Dictionary
var alternate: Dictionary

func _init() -> void:
	result = Competition.run()
	uniform = Competition.run(Competition.DEFAULT_GRID_SIZE, Competition.DEFAULT_FOUNDER_COUNT, Competition.DEFAULT_WINNERS_PER_PATCH, Competition.DEFAULT_EVALUATION_SEASONS, Competition.DEFAULT_FOUNDER_SEED, true)
	alternate = Competition.run(Competition.DEFAULT_GRID_SIZE, Competition.DEFAULT_FOUNDER_COUNT, Competition.DEFAULT_WINNERS_PER_PATCH, Competition.DEFAULT_EVALUATION_SEASONS, Competition.ALT_FOUNDER_SEED, false)
	_test_contract_hashes()
	_test_unlabeled_founder_pool()
	_test_shared_field_competition()
	_test_uniform_environment_control()
	_test_tradeoffs()
	_test_alternate_founder_seed()
	_test_source_boundaries()
	_finish()

func _test_contract_hashes() -> void:
	_check(not result.is_empty(), "default competition result exists")
	_check(not uniform.is_empty(), "uniform control exists")
	_check(not alternate.is_empty(), "alternate competition result exists")
	_check(String(result.get("schema", "")) == Competition.SCHEMA, "schema exact")
	_check(String(result.get("version", "")) == Competition.VERSION, "version exact")
	_check(String(result.get("experiment_revision", "")) == Competition.EXPERIMENT_REVISION, "revision exact")
	_check(String(result.get("result_hash", "")) == EXPECTED_RESULT_HASH, "default result hash fixed")
	_check(String(uniform.get("result_hash", "")) == EXPECTED_UNIFORM_HASH, "uniform result hash fixed")
	_check(String(alternate.get("result_hash", "")) == EXPECTED_ALT_HASH, "alternate result hash fixed")
	_check(String(result.get("founder_pool_hash", "")) == EXPECTED_FOUNDER_POOL_HASH, "founder pool hash fixed")
	_check(String(uniform.get("founder_pool_hash", "")) == EXPECTED_FOUNDER_POOL_HASH, "uniform uses exact same founder pool")
	_check(String(alternate.get("founder_pool_hash", "")) != EXPECTED_FOUNDER_POOL_HASH, "alternate seed changes founder pool")
	_check(not bool(result.get("uniform_control", true)), "default uses heterogeneous environment")
	_check(bool(uniform.get("uniform_control", false)), "uniform control recorded")

func _test_unlabeled_founder_pool() -> void:
	var founders := Competition.create_founder_pool()
	_check(founders.size() == Competition.DEFAULT_FOUNDER_COUNT, "exact founder count")
	var genomes := {}
	var lineages := {}
	for founder in founders:
		var genome: Dictionary = founder["genome"]
		_check(bool(PlantGenome.validate(genome).get("success", false)), "founder genome valid %d" % int(founder["founder_index"]))
		genomes[String(genome["checksum"])] = true
		lineages[String(founder["lineage"]["lineage_id"])] = true
		_check(_approx(float(genome["seed_dispersal_distance_m"]), 15.0), "dispersal remains frozen founder %d" % int(founder["founder_index"]))
	_check(genomes.size() == Competition.DEFAULT_FOUNDER_COUNT, "all founder genotypes unique")
	_check(lineages.size() == Competition.DEFAULT_FOUNDER_COUNT, "each ancestral genome has independent provenance lineage")
	var ranges: Dictionary = result["tradeoffs"]["trait_ranges"]
	_check(float(ranges["height_m"]["span"]) > 1.0, "height founder variation broad enough")
	_check(float(ranges["growth_rate"]["span"]) > 0.25, "growth founder variation broad enough")
	_check(float(ranges["root_depth_m"]["span"]) > 0.65, "root founder variation broad enough")
	_check(float(ranges["water_preference"]["span"]) > 0.24, "water preference variation broad enough")
	_check(float(ranges["shade_tolerance"]["span"]) > 0.28, "shade tolerance variation broad enough")
	_check(float(ranges["seed_count"]["span"]) >= 55.0, "seed count variation broad enough")
	_check(float(ranges["lifespan_years"]["span"]) > 3.5, "lifespan variation broad enough")

func _test_shared_field_competition() -> void:
	_check(int(result.get("patch_count", 0)) == 49, "49 heterogeneous competition patches")
	_check(int(result.get("founder_count", 0)) == 20, "20 unlabeled founders compete")
	_check(int(result.get("winners_per_patch", 0)) == 4, "four retained strategies per patch")
	var d: Dictionary = result["diversity"]
	_check(int(d["persistent_founders"]) >= 12, "many founder strategies survive somewhere in field")
	_check(int(d["top1_persistent_founders"]) >= 4, "multiple founders win at least one patch")
	_check(float(d["dominance_ratio"]) < 0.25, "no founder captures quarter of all retained slots")
	_check(float(d["top1_dominance_ratio"]) < 0.90, "no founder wins almost every heterogeneous patch")
	_check(float(d["shannon_winner_diversity"]) > 1.8, "winner diversity is substantial")
	_check(int(d["unique_patch_winner_sets"]) > 30, "competition composition changes strongly across map")
	var regions: Dictionary = result["region_competition"]
	_check(int(regions["WET"]["unique_winners"]) >= 12, "wet region admits broad strategy set")
	_check(int(regions["SHADED"]["unique_winners"]) >= 10, "shaded region admits broad strategy set")
	_check(int(regions["DRY"]["unique_winners"]) >= 4, "dry region retains multiple strategies")
	_check(int(regions["SUNLIT"]["unique_winners"]) >= 4, "sunlit region retains multiple strategies")
	var dry_set := _winner_set(regions["DRY"])
	var wet_set := _winner_set(regions["WET"])
	var shaded_set := _winner_set(regions["SHADED"])
	_check(dry_set != wet_set, "dry and wet competition compositions differ")
	_check(dry_set != shaded_set, "dry and shaded competition compositions differ")
	_check(wet_set != shaded_set, "wet and shaded competition compositions differ")

func _test_uniform_environment_control() -> void:
	var real: Dictionary = result["diversity"]
	var neutral: Dictionary = uniform["diversity"]
	_check(int(neutral["persistent_founders"]) == Competition.DEFAULT_WINNERS_PER_PATCH, "uniform field collapses to one repeated retained set")
	_check(int(neutral["top1_persistent_founders"]) == 1, "uniform field has one top winner")
	_check(int(neutral["unique_patch_winner_sets"]) == 1, "uniform field repeats exact winner composition")
	_check(_approx(float(neutral["top1_dominance_ratio"]), 1.0), "uniform top winner owns every patch")
	_check(float(real["shannon_winner_diversity"]) > float(neutral["shannon_winner_diversity"]) + 0.50, "heterogeneous environment increases global strategy diversity")
	_check(int(real["persistent_founders"]) >= int(neutral["persistent_founders"]) + 8, "heterogeneous niches retain many extra founders")
	for region_name in Competition.REGION_NAMES:
		_check(int(uniform["region_competition"][region_name]["unique_winners"]) == Competition.DEFAULT_WINNERS_PER_PATCH, "uniform region uses same four founders %s" % region_name)

func _test_tradeoffs() -> void:
	var t: Dictionary = result["tradeoffs"]
	_check(float(t["height_extra_cost"]) > 0.20, "greater height pays extra structural/maintenance cost")
	_check(float(t["root_extra_cost"]) > 0.25, "deeper roots pay extra root cost")
	_check(float(t["deep_root_dry_net_gain"]) > 0.10, "deep roots help in dry environment")
	_check(float(t["deep_root_flood_net_gain"]) < -0.25, "deep roots are costly in floodplain where not needed")
	_check(float(t["growth_extra_cost"]) > 0.12, "fast growth pays maintenance/allocation cost")
	_check(float(t["seed_extra_cost"]) > 0.05, "many seeds pay reproduction cost")
	_check(float(t["seed_recruitment_gain"]) > 0.005, "many seeds also gain recruitment under favourable conditions")
	_check(float(t["shade_shaded_gross_gain"]) > 0.20, "shade tolerance improves capture in shade")
	_check(float(t["shade_sunny_net_gain"]) < -0.10, "shade tolerance sacrifices sunny performance")
	_check(float(t["long_life_mortality_delta"]) < -0.01, "long lifespan reduces baseline turnover mortality")

func _test_alternate_founder_seed() -> void:
	_check(String(alternate["result_hash"]) != String(result["result_hash"]), "alternate founder seed changes exact competition result")
	var d: Dictionary = alternate["diversity"]
	_check(int(d["persistent_founders"]) >= 12, "alternate seed retains many founder strategies")
	_check(int(d["top1_persistent_founders"]) >= 5, "alternate seed has multiple top winners")
	_check(float(d["top1_dominance_ratio"]) < 0.80, "alternate seed avoids near-global top winner")
	_check(float(d["shannon_winner_diversity"]) > 1.9, "alternate seed preserves high winner diversity")
	_check(int(d["unique_patch_winner_sets"]) > 30, "alternate seed preserves spatially varied competition")

func _test_source_boundaries() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_strategy_competition_baseline_v1.gd").to_lower()
	_check(not source.contains("species"), "no predefined species classes")
	_check(not source.contains("biome"), "no biome rule")
	_check(not source.contains("fitness"), "no handwritten fitness score")
	_check(not source.contains("camera"), "no camera dependency")
	_check(not source.contains("authority"), "no authority dependency")
	_check(not source.contains("network"), "no network dependency")
	_check(not source.contains("migration"), "migration remains outside P1C-S1")
	_check(source.contains("patchsimulator.simulate"), "competition reads accepted P1A population consequences")
	_check(source.contains("resourcemodel.evaluate"), "competition reads accepted P1A resource consequences")
	_check(source.contains("uniform_control"), "uniform environment control explicit")

func _winner_set(region: Dictionary) -> String:
	var values: Array[int] = []
	for item in Array(region["winner_counts"]): values.append(int(item["founder_index"]))
	values.sort()
	return str(values)

func _approx(a: float, b: float, tolerance: float = 0.000000001) -> bool:
	return absf(a - b) <= tolerance

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition: failures.append(label)

func _finish() -> void:
	print("ECO.P1C-S1 result_hash=%s" % String(result.get("result_hash", "")))
	print("ECO.P1C-S1 uniform_hash=%s" % String(uniform.get("result_hash", "")))
	print("ECO.P1C-S1 alt_result_hash=%s" % String(alternate.get("result_hash", "")))
	print("ECO.P1C-S1 founder_pool_hash=%s" % String(result.get("founder_pool_hash", "")))
	print("ECO.P1C-S1 diversity=%s" % str(result.get("diversity", {})))
	print("ECO.P1C-S1 tradeoffs=%s" % str(result.get("tradeoffs", {})))
	if failures.is_empty():
		print("ECO.P1C-S1 Strategy Competition Baseline: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures: push_error("ECO.P1C-S1 FAIL: %s" % failure)
	print("ECO.P1C-S1 Strategy Competition Baseline: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)

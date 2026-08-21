extends SceneTree

const Dynamic = preload("res://scripts/research/ecology/plant_dynamic_abundance_competition_v1.gd")
const S1Competition = preload("res://scripts/research/ecology/plant_strategy_competition_baseline_v1.gd")

const EXPECTED_RESULT_HASH := "3e52c4e93fcdefba64607dd2c935ccbddba78db3f400d6a6ea51b23db766982b"
const EXPECTED_UNIFORM_HASH := "47f0e9c7573bf002151718a57c930d400682c3d86dbd3a8b96b8ddf48c4a01a2"
const EXPECTED_ALT_HASH := "4706d80289b1fc9918f1758ccabdbb62a76053739f3c7bccadcd282e797d572b"
const EXPECTED_FOUNDER_POOL_HASH := "77acaada39a39c54224b73f2548ebc228343e869264e45780d08419ebb6bee38"

var assertions := 0
var failures: Array[String] = []
var result: Dictionary
var uniform: Dictionary
var alternate: Dictionary

func _init() -> void:
	result = Dynamic.run()
	uniform = Dynamic.run(Dynamic.DEFAULT_GRID_SIZE, Dynamic.DEFAULT_FOUNDER_COUNT, Dynamic.DEFAULT_CYCLES, Dynamic.DEFAULT_SEASONS_PER_CYCLE, Dynamic.DEFAULT_FOUNDER_SEED, true)
	alternate = Dynamic.run(Dynamic.DEFAULT_GRID_SIZE, Dynamic.DEFAULT_FOUNDER_COUNT, Dynamic.DEFAULT_CYCLES, Dynamic.DEFAULT_SEASONS_PER_CYCLE, Dynamic.ALT_FOUNDER_SEED, false)
	_test_contract_hashes()
	_test_equal_founder_start_and_dynamic_history()
	_test_heterogeneous_dynamic_coexistence()
	_test_uniform_control()
	_test_regional_niche_structure()
	_test_alternate_seed()
	_test_source_boundaries()
	_finish()

func _test_contract_hashes() -> void:
	_check(not result.is_empty(), "default dynamic competition result exists")
	_check(not uniform.is_empty(), "uniform dynamic control exists")
	_check(not alternate.is_empty(), "alternate dynamic competition exists")
	_check(String(result.get("schema", "")) == Dynamic.SCHEMA, "schema exact")
	_check(String(result.get("version", "")) == Dynamic.VERSION, "version exact")
	_check(String(result.get("experiment_revision", "")) == Dynamic.EXPERIMENT_REVISION, "revision exact")
	_check(String(result.get("result_hash", "")) == EXPECTED_RESULT_HASH, "default result hash fixed")
	_check(String(uniform.get("result_hash", "")) == EXPECTED_UNIFORM_HASH, "uniform result hash fixed")
	_check(String(alternate.get("result_hash", "")) == EXPECTED_ALT_HASH, "alternate result hash fixed")
	_check(String(result.get("founder_pool_hash", "")) == EXPECTED_FOUNDER_POOL_HASH, "default founder pool matches accepted S1")
	_check(String(uniform.get("founder_pool_hash", "")) == EXPECTED_FOUNDER_POOL_HASH, "uniform uses exact same founder pool")
	_check(String(alternate.get("founder_pool_hash", "")) != EXPECTED_FOUNDER_POOL_HASH, "alternate seed changes founder pool")
	_check(not bool(result.get("uniform_control", true)), "default heterogeneous mode recorded")
	_check(bool(uniform.get("uniform_control", false)), "uniform control recorded")

func _test_equal_founder_start_and_dynamic_history() -> void:
	_check(int(result.get("patch_count", 0)) == 25, "dynamic baseline uses 25 patches")
	_check(int(result.get("founder_count", 0)) == 20, "all 20 S1 founders enter dynamic competition")
	_check(int(result.get("cycles", 0)) == 12, "default dynamic cycle count exact")
	_check(int(result.get("seasons_per_cycle", 0)) == 3, "accepted simulator seasons per cycle exact")
	_check(Array(result.get("history", [])).size() == 13, "cycle zero plus twelve dynamic states recorded")
	var initial: Dictionary = result["history"][0]
	_check(_approx(float(initial["total_biomass_kg_m2"]), 50.0), "initial field biomass equals equal founder start")
	_check(_approx(float(initial["global_top1_biomass_share"]), 0.05), "all founders start at equal 5 percent global share")
	_check(_approx(float(initial["shannon_biomass_diversity"]), log(20.0)), "initial Shannon diversity is exact equal-pool maximum")
	_check(int(initial["persistent_founders"]) == 20, "all founders present at cycle zero")
	var seen_hashes := {}
	for summary in Array(result["history"]):
		_check(float(summary["total_biomass_kg_m2"]) <= Dynamic.PATCH_SHARED_CAPACITY_KG_M2 * 25.0 + 0.000000001, "shared patch capacity bounds field biomass cycle %d" % int(summary["cycle"]))
		_check(float(summary["total_biomass_kg_m2"]) >= 0.0, "field biomass non-negative cycle %d" % int(summary["cycle"]))
		_check(float(summary["global_top1_biomass_share"]) >= 0.0 and float(summary["global_top1_biomass_share"]) <= 1.0, "global share bounded cycle %d" % int(summary["cycle"]))
		seen_hashes[String(summary["field_biomass_hash"])] = true
	_check(seen_hashes.size() == 13, "every dynamic cycle has distinct field abundance state")

func _test_heterogeneous_dynamic_coexistence() -> void:
	var g: Dictionary = result["global_abundance"]
	_check(float(g["total_biomass_kg_m2"]) > 60.0, "heterogeneous community retains substantial biomass")
	_check(int(g["effective_founders_1pct"]) >= 18, "at least eighteen founders retain >=1 percent global biomass")
	_check(int(g["effective_founders_2pct"]) >= 14, "at least fourteen founders retain >=2 percent global biomass")
	_check(int(g["effective_founders_5pct"]) >= 5, "multiple founders retain major >=5 percent shares")
	_check(float(g["top1_biomass_share"]) < 0.30, "frequent static winner does not become global biomass monopoly")
	_check(float(g["top1_patch_dominance_ratio"]) < 0.85, "no founder leads more than 85 percent of heterogeneous patches")
	_check(float(g["shannon_biomass_diversity"]) > 2.50, "dynamic heterogeneous abundance remains highly diverse")
	_check(float(g["top1_biomass_share"]) > 0.15, "competition produces real abundance asymmetry rather than frozen equal shares")

func _test_uniform_control() -> void:
	var real: Dictionary = result["global_abundance"]
	var neutral: Dictionary = uniform["global_abundance"]
	_check(_approx(float(neutral["top1_patch_dominance_ratio"]), 1.0), "uniform environment has same top founder on every patch")
	_check(int(real["effective_founders_1pct"]) >= int(neutral["effective_founders_1pct"]) + 7, "heterogeneous niches retain many more effective founders than uniform control")
	_check(float(real["shannon_biomass_diversity"]) > float(neutral["shannon_biomass_diversity"]) + 0.15, "heterogeneous field preserves more abundance diversity than uniform control")
	var uniform_top := int(uniform["regional_abundance"]["DRY"]["top_founder"])
	for region_name in S1Competition.REGION_NAMES:
		_check(int(uniform["regional_abundance"][region_name]["top_founder"]) == uniform_top, "uniform control repeats same regional top founder %s" % region_name)

func _test_regional_niche_structure() -> void:
	var regions: Dictionary = result["regional_abundance"]
	_check(int(regions["DRY"]["top_founder"]) != int(regions["WET"]["top_founder"]), "dry and wet regions select different abundance leaders")
	_check(float(regions["DRY"]["top_share"]) > 0.35, "dry region has a strong specialist leader")
	_check(float(regions["WET"]["top_share"]) < 0.15, "wet region remains broadly shared rather than monopolized")
	_check(float(regions["SHADED"]["top_share"]) < 0.30, "shade region remains multi-strategy")
	_check(float(regions["SUNLIT"]["top_share"]) < 0.40, "sunlit region avoids complete monopoly")
	var patch_top_founders := {}
	for patch in Array(result["patches"]):
		var top: Dictionary = patch["abundance"][0]
		patch_top_founders[int(top["founder_index"])] = true
	_check(patch_top_founders.size() >= 4, "at least four strategies lead some patch dynamically")

func _test_alternate_seed() -> void:
	_check(String(alternate["result_hash"]) != String(result["result_hash"]), "alternate founder pool changes exact dynamics")
	var g: Dictionary = alternate["global_abundance"]
	_check(int(g["effective_founders_1pct"]) >= 17, "alternate seed preserves broad effective founder set")
	_check(int(g["effective_founders_2pct"]) >= 14, "alternate seed preserves many substantial founders")
	_check(float(g["top1_biomass_share"]) < 0.25, "alternate seed avoids biomass monopoly")
	_check(float(g["top1_patch_dominance_ratio"]) < 0.60, "alternate seed has spatially distributed patch leadership")
	_check(float(g["shannon_biomass_diversity"]) > 2.50, "alternate seed preserves dynamic abundance diversity")
	var regional_tops := {}
	for region_name in S1Competition.REGION_NAMES:
		regional_tops[int(alternate["regional_abundance"][region_name]["top_founder"])] = true
	_check(regional_tops.size() >= 3, "alternate seed exposes at least three regional abundance leaders")

func _test_source_boundaries() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_dynamic_abundance_competition_v1.gd").to_lower()
	_check(not source.contains("species"), "no species classes")
	_check(not source.contains("biome"), "no biome rules")
	_check(not source.contains("fitness"), "no handwritten fitness score")
	_check(not source.contains("migration"), "no migration in P1C-S2")
	_check(not source.contains("camera"), "no presentation input")
	_check(not source.contains("authority"), "no authority input")
	_check(not source.contains("network"), "no network input")
	_check(source.contains("patchsimulator.simulate"), "dynamic abundance delegates growth/mortality/recruitment to accepted P1A simulator")
	_check(source.contains("patch_shared_capacity_kg_m2"), "shared-patch biomass capacity is explicit")
	_check(source.contains("uniform_control"), "uniform control remains explicit")

func _approx(a: float, b: float, tolerance: float = 0.000000001) -> bool:
	return absf(a - b) <= tolerance

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	print("ECO.P1C-S2 result_hash=%s" % String(result.get("result_hash", "")))
	print("ECO.P1C-S2 uniform_hash=%s" % String(uniform.get("result_hash", "")))
	print("ECO.P1C-S2 alt_result_hash=%s" % String(alternate.get("result_hash", "")))
	print("ECO.P1C-S2 founder_pool_hash=%s" % String(result.get("founder_pool_hash", "")))
	print("ECO.P1C-S2 global=%s" % str(result.get("global_abundance", {})))
	print("ECO.P1C-S2 uniform_global=%s" % str(uniform.get("global_abundance", {})))
	if failures.is_empty():
		print("ECO.P1C-S2 Dynamic Shared-Patch Abundance Competition: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.P1C-S2 FAIL: %s" % failure)
	print("ECO.P1C-S2 Dynamic Shared-Patch Abundance Competition: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)

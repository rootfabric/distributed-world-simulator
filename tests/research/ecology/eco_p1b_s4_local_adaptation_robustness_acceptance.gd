extends SceneTree

const Gate = preload("res://scripts/research/ecology/plant_local_adaptation_robustness_gate_v1.gd")

const EXPECTED_RUN_HASHES: Array[String] = [
	"b7b7da27158e35d5ab8fa16bc209526c7144e9f178d62aee91c8de9e107cd9a2",
	"68ba3c9bdfebc12b87f454e9d87e5865229d2198628904b473216928f2aa493e",
	"6592cf2c06276253d72779955f0ee9fd73d0a19f16d265c7690804e843152cab",
]
const EXPECTED_NEUTRAL_HASH := "175bbef1c085d0783bd0d48f23bbc9a865cc438ae09e15785d4e48cdf1cc27bf"
const EXPECTED_LONG_HASH := "7f68ed87e10fa7dd6f9f79c6d50d0a82cf4360e4a416dc481e0e6005bcfb44f3"
const EXPECTED_AGGREGATE_HASH := "2c37160726c73a9b6b479be67a3cedcd34a1247025b219d2b5ebddbec4e18f05"

var assertions := 0
var failures: Array[String] = []
var result: Dictionary

func _init() -> void:
	result = Gate.run()
	_test_contract_and_hashes()
	_test_multi_seed_robustness()
	_test_neutral_control()
	_test_long_horizon()
	_test_no_runaway_or_boundary_hugging()
	_test_source_boundaries()
	_finish()

func _test_contract_and_hashes() -> void:
	_check(not result.is_empty(), "robustness result exists")
	_check(String(result.get("schema", "")) == Gate.SCHEMA, "schema exact")
	_check(String(result.get("version", "")) == Gate.VERSION, "version exact")
	_check(String(result.get("experiment_revision", "")) == Gate.EXPERIMENT_REVISION, "revision exact")
	_check(int(result.get("grid_size", 0)) == Gate.GRID_SIZE, "grid exact")
	_check(int(result.get("generations", 0)) == Gate.GENERATIONS, "generation horizon exact")
	_check(int(result.get("long_generations", 0)) == Gate.LONG_GENERATIONS, "long horizon exact")
	_check(Array(result.get("runs", [])).size() == Gate.SEEDS.size(), "all robustness seeds executed")
	for i in range(EXPECTED_RUN_HASHES.size()):
		_check(String(result["runs"][i]["result_hash"]) == EXPECTED_RUN_HASHES[i], "seed result hash fixed %d" % i)
	_check(String(result["neutral"]["result_hash"]) == EXPECTED_NEUTRAL_HASH, "neutral hash fixed")
	_check(String(result["long_run"]["result_hash"]) == EXPECTED_LONG_HASH, "long-run hash fixed")
	_check(String(result.get("aggregate_hash", "")) == EXPECTED_AGGREGATE_HASH, "aggregate robustness hash fixed")

func _test_multi_seed_robustness() -> void:
	var unique_hashes := {}
	for run in Array(result["runs"]):
		unique_hashes[String(run["result_hash"])] = true
		_check(float(run["initial_average_net"]) < -0.15, "ancestor field begins net negative seed %d" % int(run["lineage_seed"]))
		_check(float(run["final_average_net"]) > 0.14, "adapted field ends positive seed %d" % int(run["lineage_seed"]))
		_check(float(run["final_average_net"]) > float(run["initial_average_net"]) + 0.33, "large resource improvement seed %d" % int(run["lineage_seed"]))
		_check(float(run["water_preference_vs_moisture"]) > 0.85, "water/moisture specialization robust seed %d" % int(run["lineage_seed"]))
		_check(float(run["root_depth_vs_moisture"]) < -0.52, "root/moisture sign robust seed %d" % int(run["lineage_seed"]))
		_check(float(run["shade_tolerance_vs_sunlight"]) < -0.33, "shade/light sign robust seed %d" % int(run["lineage_seed"]))
		_check(float(run["wet_minus_dry_water_preference"]) > 0.11, "wet-dry water divergence robust seed %d" % int(run["lineage_seed"]))
		_check(float(run["dry_minus_wet_root_depth_m"]) > 0.16, "dry-wet root divergence robust seed %d" % int(run["lineage_seed"]))
		_check(float(run["shaded_minus_sunlit_shade_tolerance"]) > 0.020, "shade divergence robust seed %d" % int(run["lineage_seed"]))
	_check(unique_hashes.size() == Gate.SEEDS.size(), "different evolution seeds produce different exact fields")
	var means: Dictionary = result["aggregate"]["means"]
	_check(float(means["water_preference_vs_moisture"]) > 0.89, "mean water specialization strong")
	_check(float(means["root_depth_vs_moisture"]) < -0.53, "mean root specialization strong")
	_check(float(means["shade_tolerance_vs_sunlight"]) < -0.41, "mean shade specialization strong")

func _test_neutral_control() -> void:
	var neutral: Dictionary = result["neutral"]
	var means: Dictionary = result["aggregate"]["means"]
	_check(bool(neutral["neutral_control"]), "neutral run explicitly marked")
	_check(absf(float(neutral["water_preference_vs_moisture"])) < 0.15, "neutral lacks water/moisture specialization")
	_check(absf(float(neutral["root_depth_vs_moisture"])) < 0.10, "neutral lacks root/moisture specialization")
	_check(absf(float(neutral["shade_tolerance_vs_sunlight"])) < 0.24, "neutral lacks shade/light specialization")
	_check(float(means["water_preference_vs_moisture"]) > float(neutral["water_preference_vs_moisture"]) + 0.93, "real water signal exceeds neutral")
	_check(absf(float(means["root_depth_vs_moisture"])) > absf(float(neutral["root_depth_vs_moisture"])) + 0.50, "real root signal exceeds neutral")
	_check(absf(float(means["shade_tolerance_vs_sunlight"])) > absf(float(neutral["shade_tolerance_vs_sunlight"])) + 0.18, "real shade signal exceeds neutral")

func _test_long_horizon() -> void:
	var long_run: Dictionary = result["long_run"]
	_check(int(result["long_generations"]) > int(result["generations"]), "long horizon is strictly longer")
	_check(float(long_run["final_average_net"]) > 0.24, "long-run resource state remains healthy")
	_check(float(long_run["water_preference_vs_moisture"]) > 0.88, "long-run water specialization persists")
	_check(float(long_run["root_depth_vs_moisture"]) < -0.58, "long-run root specialization persists")
	_check(float(long_run["shade_tolerance_vs_sunlight"]) < -0.45, "long-run shade specialization persists")
	_check(float(long_run["wet_minus_dry_water_preference"]) > 0.15, "long-run water divergence persists")
	_check(float(long_run["dry_minus_wet_root_depth_m"]) > 0.35, "long-run root divergence persists")
	_check(float(long_run["shaded_minus_sunlit_shade_tolerance"]) > 0.045, "long-run shade divergence persists")

func _test_no_runaway_or_boundary_hugging() -> void:
	for run in Array(result["runs"]) + [result["long_run"]]:
		var traits: Dictionary = run["final_trait_means"]
		_check(float(traits["water_preference"]) > 0.20 and float(traits["water_preference"]) < 0.80, "water preference mean remains interior")
		_check(float(traits["root_depth_m"]) > 0.20 and float(traits["root_depth_m"]) < 2.0, "root depth mean remains interior")
		_check(float(traits["growth_rate"]) > 0.20 and float(traits["growth_rate"]) < 0.90, "growth rate mean remains interior")
		_check(float(traits["shade_tolerance"]) > 0.20 and float(traits["shade_tolerance"]) < 0.80, "shade tolerance mean remains interior")
		_check(absf(float(traits["seed_dispersal_distance_m"]) - 15.0) < 0.000000001, "dispersal remains frozen until migration benefit exists")

func _test_source_boundaries() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_local_adaptation_robustness_gate_v1.gd").to_lower()
	_check(not source.contains("biome"), "robustness gate has no biome rules")
	_check(not source.contains("species"), "robustness gate has no species classes")
	_check(not source.contains("camera"), "robustness gate has no presentation input")
	_check(not source.contains("authority"), "robustness gate has no authority dependency")
	_check(not source.contains("network"), "robustness gate has no network dependency")
	_check(source.contains("field.run"), "robustness gate reuses accepted S3 field model")

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	print("ECO.P1B-S4 aggregate_hash=%s" % String(result.get("aggregate_hash", "")))
	print("ECO.P1B-S4 aggregate=%s" % str(result.get("aggregate", {})))
	print("ECO.P1B-S4 neutral=%s" % str(result.get("neutral", {})))
	print("ECO.P1B-S4 long_run=%s" % str(result.get("long_run", {})))
	if failures.is_empty():
		print("ECO.P1B-S4 Local Adaptation Robustness: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.P1B-S4 FAIL: %s" % failure)
	print("ECO.P1B-S4 Local Adaptation Robustness: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)

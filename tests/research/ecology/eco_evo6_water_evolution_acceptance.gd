extends SceneTree

const Bridge = preload("res://scripts/research/ecology/evo6_water_evolution_bridge_v1.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var first := Bridge.run_all()
	var replay := Bridge.run_all()
	_check(not first.is_empty(), "water evolution bridge builds")
	_check(String(first.get("result_hash", "")) == String(replay.get("result_hash", "")), "same seed is deterministic")
	if first.is_empty():
		_finish(first)
		return
	var metrics: Dictionary = first["metrics"]
	_check(bool(metrics["common_first_candidate_pool"]), "all water regimes start from identical generation-one candidates")
	_check(int(metrics["distinct_final_populations"]) >= 3, "water regimes produce at least three distinct evolved populations")
	_check(bool(metrics["water_causes_evolutionary_divergence"]), "water conditions causally change selected descendants")

	var scenarios: Dictionary = first["scenarios"]
	var flooded: Dictionary = scenarios["flooded"]
	var riparian: Dictionary = scenarios["riparian"]
	var mesic: Dictionary = scenarios["mesic"]
	var dry: Dictionary = scenarios["dry"]
	var flooded_final: Dictionary = flooded["final"]
	var riparian_final: Dictionary = riparian["final"]
	var mesic_final: Dictionary = mesic["final"]
	var dry_final: Dictionary = dry["final"]

	_check(float(flooded_final["mean_water_preference"]) > float(dry_final["mean_water_preference"]) + 0.20, "flood selects much higher water preference than drought")
	_check(float(riparian_final["mean_water_preference"]) > float(dry_final["mean_water_preference"]) + 0.12, "riparian water selects higher water preference than drought")
	_check(float(dry_final["mean_root_depth_m"]) > float(flooded_final["mean_root_depth_m"]) + 0.35, "drought selects substantially deeper roots than flood")
	_check(float(dry_final["mean_root_depth_m"]) > float(mesic_final["mean_root_depth_m"]), "drought selects deeper roots than mesic conditions")

	_check(float(flooded_final["mean_water_preference"]) >= 0.90, "flood drives water preference toward the wet extreme")
	_check(float(dry_final["mean_water_preference"]) <= 0.45, "drought drives water preference toward the dry extreme")
	_check(float(dry_final["mean_root_depth_m"]) >= 1.50, "drought produces deep-rooted descendants")

	var all_final_genomes_materialized := true
	var all_final_genomes_match_population := true
	for scenario_id in ["flooded", "riparian", "mesic", "dry"]:
		var scenario: Dictionary = scenarios[scenario_id]
		_check(float(scenario["final"]["mean_fitness"]) >= float(scenario["initial"]["mean_fitness"]), "%s population does not lose fitness" % scenario_id)
		_check(int(scenario["mutation_events"]) > 0, "%s observes mutations from existing P1B kernel" % scenario_id)
		var final_genomes: Array = scenario.get("final_genomes", [])
		all_final_genomes_materialized = all_final_genomes_materialized and not final_genomes.is_empty()
		all_final_genomes_match_population = all_final_genomes_match_population and final_genomes.size() == int(first["population_size"])
	_check(all_final_genomes_materialized, "selected final genomes are materialized for visual/read-only adapters")
	_check(all_final_genomes_match_population, "materialized final genome count matches selected population size")

	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/evo6_water_evolution_bridge_v1.gd")
	_check(source.find("MutationKernel.reproduce") >= 0, "water evolution delegates mutation to existing P1B kernel")
	_check(source.find("PlantGenome.create(") < 0, "water evolution does not implement a second genome mutation path")
	_finish(first)

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish(result: Dictionary) -> void:
	if not result.is_empty():
		print("ECO.EVO6-WATER result_hash=%s" % String(result.get("result_hash", "")))
		for scenario_id in ["flooded", "riparian", "mesic", "dry"]:
			var scenario: Dictionary = result["scenarios"][scenario_id]
			print("  %s initial=%s final=%s" % [scenario_id, str(scenario["initial"]), str(scenario["final"])])
	if failures.is_empty():
		print("ECO.EVO6-WATER evolution: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO6-WATER FAIL: %s" % failure)
	print("ECO.EVO6-WATER evolution: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)

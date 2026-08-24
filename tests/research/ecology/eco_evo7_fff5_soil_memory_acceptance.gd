extends SceneTree

const EffectV3 = preload("res://scripts/research/ecology/plant_environment_effect_v3.gd")
const Legacy = preload("res://scripts/research/ecology/soil_legacy_field_v1.gd")
const Bridge = preload("res://scripts/research/ecology/evo7_soil_memory_bridge_v1.gd")
const SEED := 20260823
var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_contract_and_memory_field()
	_causality_identity_fence()
	_experiment_d()
	_multiseed()
	_source_boundaries()
	_finish()

func _contract_and_memory_field() -> void:
	var pristine := Legacy.create_pristine()
	_check(Legacy.validate(pristine), "pristine soil state validates")
	var a := EffectV3.create("a", "cell", 1, 0, 0, 0, 50000, 10000, "a".repeat(64))
	var b := EffectV3.create("b", "cell", 1, 0, 0, 0, 30000, 5000, "b".repeat(64))
	_check(bool(EffectV3.validate(a).get("success", false)) and bool(EffectV3.validate(b).get("success", false)), "FFF5 effect v3 activates litter/binding")
	var s1 := Legacy.apply_cycle(pristine, [a, b])
	var s1_reordered := Legacy.apply_cycle(pristine, [b, a])
	_check(not s1.is_empty(), "legacy cycle computes")
	_check(String(s1["state_hash"]) == String(s1_reordered["state_hash"]), "legacy aggregation order invariant")
	_check(int(s1["organic_matter_ppm"]) > 0, "litter creates organic matter proxy")
	_check(int(s1["retention_bonus_ppm"]) > 0 and int(s1["nutrient_bonus_ppm"]) > 0 and int(s1["establishment_bonus_ppm"]) > 0, "organic matter creates slow retention/nutrient/establishment channels")
	var s2 := Legacy.apply_cycle(s1, [a, b])
	_check(int(s2["organic_matter_ppm"]) > int(s1["organic_matter_ppm"]), "repeated vegetation builds soil memory despite decay")

func _causality_identity_fence() -> void:
	var tag := Bridge.evaluation_seed_tag(4, 2, 1)
	_check(tag == "fff5-eval|4|2|1", "counterfactual realization identity is keyed only by generation/parent/offspring")
	_check(not tag.contains("modified") and not tag.contains("pristine"), "modified/pristine mode cannot perturb realization seed")
	_check(Bridge.evaluation_seed_tag(-1, 0, 0).is_empty(), "invalid realization identity fails closed")

func _experiment_d() -> void:
	var result := Bridge.run_all(SEED)
	_check(not result.is_empty(), "FFF5 Experiment D bridge runs")
	if result.is_empty(): return
	_check(String(result.get("evaluation_identity_rule", "")) == Bridge.EVALUATION_IDENTITY_RULE, "Experiment D publishes mode-independent evaluation identity rule")
	_check(bool(result["source_removed"]), "Experiment D removes source vegetation before challenge")
	_check(int(result["modified_soil"]["organic_matter_ppm"]) > 0, "modified soil retains vegetation legacy")
	_check(int(result["pristine_soil"]["organic_matter_ppm"]) == 0, "pristine control remains zero legacy")
	_check(String(result["common_first_candidate_pool_hash"]).length() == 64, "modified/pristine challenge uses identical generation-one mutation pool")
	_check(String(result["modified"]["final_population_hash"]) != String(result["pristine"]["final_population_hash"]), "Experiment D: soil history changes selected descendants")
	_check(float(result["modified"]["mean_fitness"]) > float(result["pristine"]["mean_fitness"]), "legacy improves establishment/resource opportunity in modified soil")
	var replay := Bridge.run_all(SEED)
	_check(String(replay["result_hash"]) == String(result["result_hash"]), "FFF5 deterministic replay")

func _multiseed() -> void:
	var passes := 0
	for seed in [SEED, SEED + 1, SEED + 2]:
		var result := Bridge.run_all(seed, 6, 14, 14, 3)
		if result.is_empty(): continue
		if String(result["modified"]["final_population_hash"]) != String(result["pristine"]["final_population_hash"]) and float(result["modified"]["mean_fitness"]) > float(result["pristine"]["mean_fitness"]):
			passes += 1
	_check(passes >= 2, "FFF5 multiseed ecological-memory direction holds in >=2/3 seeds")

func _source_boundaries() -> void:
	var legacy_source := FileAccess.get_file_as_string("res://scripts/research/ecology/soil_legacy_field_v1.gd").to_lower()
	for forbidden in ["randf", "randi(", "randomize", "node3d", "get_tree"]:
		_check(not legacy_source.contains(forbidden), "soil legacy excludes %s" % forbidden)
	var bridge_source := FileAccess.get_file_as_string("res://scripts/research/ecology/evo7_soil_memory_bridge_v1.gd")
	_check(bridge_source.contains("LineageExtension.reproduce_bundle"), "FFF5 reuses single lineage authority")
	_check(bridge_source.contains("source_removed\": true"), "FFF5 result makes source-removal boundary explicit")
	_check(bridge_source.contains("evaluation_seed_tag(generation, parent_index, offspring_index)"), "FFF5 evaluation consumes mode-independent realization identity")
	_check(not bridge_source.contains("fff5-eval|%s"), "FFF5 mode string is absent from realization seed formula")
	_check(not bridge_source.contains("species_class"), "FFF5 has no hardcoded species archetype switch")

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition: failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO7 FFF5 Litter / Soil Memory: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures: push_error("ECO.EVO7 FFF5 FAIL: %s" % failure)
	print("ECO.EVO7 FFF5 Litter / Soil Memory: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)

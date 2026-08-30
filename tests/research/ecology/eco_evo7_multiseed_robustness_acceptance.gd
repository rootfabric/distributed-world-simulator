extends SceneTree

## ECO.EVO7 multiseed robustness acceptance (independent research probe, R1 line).
##
## Runs BOTH deterministic evolution bridges across 5 lineage seeds
## [20260823, 11, 22, 33, 44] and asserts DIRECTIONAL STABILITY, not exact hashes:
##   FFF2 morphology bridge (generations=24, population=18, offspring=4):
##     - dry_ridge mean realized_root_depth_m > wet_lowland (>= 4/5 seeds);
##     - sunny_slope mean realized_crown_density > shaded_slope (>= 4/5 seeds);
##     - anti-runaway (hard gate, 5/5 seeds): mean ext foliage_density within
##       [0.07..0.98] and mean ext root_shoot_ratio within [0.17..0.83] in every
##       scenario - a pinned trait mean means evolution ran to the bound rail;
##     - determinism: instrumented replay reproduces every final population
##       (final_population_hash equality, 5/5 seeds) plus a strict double run of
##       seed 20260823 with identical result_hash.
##   FFF3 light feedback bridge (generations=16):
##     - feedback_on final_population_hash != feedback_off (5/5 seeds);
##     - deep_shade_mean_lai < open_light_mean_lai (>= 4/5 seeds);
##     - mean_understory_light < base_sunlight - 0.03 (>= 4/5 seeds);
##     - determinism: double run per seed -> identical result_hash (5/5 seeds).
##
## The FFF2 ext-trait means (foliage_density, root_shoot_ratio) are not exposed
## by run_all, so this acceptance re-derives each final selected population with
## the bridge's OWN building blocks (same ancestor template, same mutation
## stream formula, same evaluation and ranking helpers) and proves faithfulness
## through per-scenario final_population_hash equality before reading the trait
## means. No bridge code is modified or weakened by this probe.
##
## Research-only probe: creates no fixtures, writes no files, no platform RNG.

const Bridge = preload("res://scripts/research/ecology/evo7_morphology_evolution_bridge_v1.gd")
const LightBridge = preload("res://scripts/research/ecology/evo7_light_feedback_bridge_v1.gd")
const LineageExtension = preload("res://scripts/research/ecology/plant_mutation_lineage_extension_evo7_v1.gd")
const Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const Fixture = preload("res://scripts/research/ecology/synthetic_environment_fixture_v1.gd")

const SEEDS := [20260823, 11, 22, 33, 44]
const REFERENCE_SEED := 20260823
const DIRECTION_MIN_SEEDS := 4
const UNANIMOUS_SEEDS := 5

const FFF2_GENERATIONS := 24
const FFF2_POPULATION := 18
const FFF2_OFFSPRING := 4
const FFF2_FOLIAGE_WINDOW := [0.07, 0.98]
const FFF2_ROOT_SHOOT_WINDOW := [0.17, 0.83]

const FFF3_UNDERSTORY_MARGIN := 0.03

var assertions := 0
var failures: Array[String] = []
var matrix: Array[Dictionary] = []

func _init() -> void:
	var started := Time.get_ticks_msec()
	_fff2_multiseed()
	_fff3_multiseed()
	_stability_rates()
	_print_matrix()
	_finish(started)

func _fff2_multiseed() -> void:
	var started := Time.get_ticks_msec()
	var results := {}
	for seed in SEEDS:
		var run_started := Time.get_ticks_msec()
		var result: Dictionary = Bridge.run_all(int(seed), FFF2_GENERATIONS, FFF2_POPULATION, FFF2_OFFSPRING)
		results[int(seed)] = result
		if result.is_empty():
			push_error("FFF2 run_all returned an empty result for seed %d" % int(seed))
			print("FFF2 seed=%d BRIDGE FAILED (empty result)" % int(seed))
		else:
			print("FFF2 run seed=%d runtime_ms=%d result_hash=%s" % [
				int(seed), Time.get_ticks_msec() - run_started,
				String(result["result_hash"]).substr(0, 16)])

	var root_values: Array[bool] = []
	var crown_values: Array[bool] = []
	var foliage_values: Array[bool] = []
	var root_shoot_values: Array[bool] = []
	var replay_values: Array[bool] = []
	for seed in SEEDS:
		var s := int(seed)
		var result: Dictionary = results.get(s, {})
		var dry := _scenario_features(result, "dry_ridge")
		var wet := _scenario_features(result, "wet_lowland")
		var sunny := _scenario_features(result, "sunny_slope")
		var shaded := _scenario_features(result, "shaded_slope")
		var directions_ok := not (dry.is_empty() or wet.is_empty() or sunny.is_empty() or shaded.is_empty())
		root_values.append(directions_ok and float(dry["realized_root_depth_m"]) > float(wet["realized_root_depth_m"]))
		crown_values.append(directions_ok and float(sunny["realized_crown_density"]) > float(shaded["realized_crown_density"]))

		var replay_ok := not result.is_empty()
		var foliage_ok := false
		var root_shoot_ok := false
		var means := {}
		if replay_ok:
			var ancestor: Dictionary = Bridge.default_ancestor_bundle(s)
			if ancestor.is_empty():
				replay_ok = false
			else:
				var policy := LineageExtension.default_policy()
				var all_match := true
				for scenario_name in Bridge.SCENARIO_NAMES:
					var scenario: Dictionary = result["scenarios"][String(scenario_name)]
					var replay: Dictionary = _replay_final_population(ancestor, String(scenario_name), s, policy)
					if replay.is_empty() or String(replay["final_population_hash"]) != String(scenario["final_population_hash"]):
						all_match = false
						break
					means[String(scenario_name)] = replay
				replay_ok = all_match
				if all_match:
					var foliage_in_window := true
					var root_shoot_in_window := true
					var foliage_low := INF
					var foliage_high := -INF
					var rs_low := INF
					var rs_high := -INF
					for scenario_name in Bridge.SCENARIO_NAMES:
						var entry: Dictionary = means[String(scenario_name)]
						var foliage := float(entry["mean_foliage_density"])
						var rs_ratio := float(entry["mean_root_shoot_ratio"])
						foliage_low = minf(foliage_low, foliage)
						foliage_high = maxf(foliage_high, foliage)
						rs_low = minf(rs_low, rs_ratio)
						rs_high = maxf(rs_high, rs_ratio)
					foliage_in_window = foliage_low >= float(FFF2_FOLIAGE_WINDOW[0]) and foliage_high <= float(FFF2_FOLIAGE_WINDOW[1])
					root_shoot_in_window = rs_low >= float(FFF2_ROOT_SHOOT_WINDOW[0]) and rs_high <= float(FFF2_ROOT_SHOOT_WINDOW[1])
					foliage_ok = foliage_in_window
					root_shoot_ok = root_shoot_in_window
					print("FFF2 seed=%d dry_root=%.3f wet_root=%.3f sunny_crown=%.3f shaded_crown=%.3f foliage=[%.3f..%.3f] root_shoot=[%.3f..%.3f] replay=faithful" % [
						s, float(dry["realized_root_depth_m"]), float(wet["realized_root_depth_m"]),
						float(sunny["realized_crown_density"]), float(shaded["realized_crown_density"]),
						foliage_low, foliage_high, rs_low, rs_high])
		if not replay_ok:
			foliage_ok = false
			root_shoot_ok = false
			print("FFF2 seed=%d replay=FAILED (trait means unavailable)" % s)
		replay_values.append(replay_ok)
		foliage_values.append(foliage_ok)
		root_shoot_values.append(root_shoot_ok)

	_row("FFF2", "FFF2 root_depth: dry_ridge > wet_lowland", DIRECTION_MIN_SEEDS, root_values)
	_row("FFF2", "FFF2 crown_density: sunny_slope > shaded_slope", DIRECTION_MIN_SEEDS, crown_values)
	_row("FFF2", "FFF2 anti-runaway: foliage_density in [0.07..0.98]", UNANIMOUS_SEEDS, foliage_values)
	_row("FFF2", "FFF2 anti-runaway: root_shoot_ratio in [0.17..0.83]", UNANIMOUS_SEEDS, root_shoot_values)
	_row("FFF2", "FFF2 determinism: replay = bridge final populations", UNANIMOUS_SEEDS, replay_values)

	# Strict end-to-end determinism on the reference seed: bridge vs bridge.
	var repeat: Dictionary = Bridge.run_all(REFERENCE_SEED, FFF2_GENERATIONS, FFF2_POPULATION, FFF2_OFFSPRING)
	var base: Dictionary = results.get(REFERENCE_SEED, {})
	_check(not base.is_empty() and not repeat.is_empty() and String(base["result_hash"]) == String(repeat["result_hash"]),
		"FFF2 determinism: seed %d double run -> identical result_hash" % REFERENCE_SEED)
	if not base.is_empty() and not repeat.is_empty():
		print("FFF2 strict double run seed=%d result_hash=%s (twice identical: %s)" % [
			REFERENCE_SEED, String(base["result_hash"]).substr(0, 16),
			str(String(base["result_hash"]) == String(repeat["result_hash"]))])
	print("FFF2 phase runtime_ms=%d" % (Time.get_ticks_msec() - started))

## Re-derives the final selected population of one FFF2 scenario with the
## bridge's own building blocks (identical ancestor template, mutation stream
## formula, evaluation and ranking) and extracts the ext-trait means that
## run_all does not expose. The caller proves faithfulness through
## final_population_hash equality with the bridge result.
func _replay_final_population(
	ancestor_template: Dictionary,
	scenario_name: String,
	lineage_seed: int,
	policy: Dictionary
) -> Dictionary:
	var env := Fixture.control_point(scenario_name, lineage_seed)
	if env.is_empty():
		return {}
	var population: Array[Dictionary] = []
	for index in FFF2_POPULATION:
		var individual_seed := Contract.derive_individual_seed(
			String(ancestor_template["lineage"]["lineage_id"]), "evo7-gen0|%d" % index, index,
			String(ancestor_template["genome"]["version"]))
		var bundle: Dictionary = ancestor_template.duplicate(true)
		bundle["individual_seed"] = individual_seed
		bundle["bundle_checksum"] = LineageExtension.bundle_checksum(
			bundle["genome"], bundle["dev_traits"], bundle["ext_traits"], bundle["lineage"], individual_seed)
		population.append(Bridge._evaluate(bundle, env))
	for generation in range(1, FFF2_GENERATIONS + 1):
		var candidates: Array[Dictionary] = []
		for parent_index in population.size():
			var parent: Dictionary = population[parent_index]
			for offspring_index in FFF2_OFFSPRING:
				var mutation_seed := ("EVO7-MORPHO|%d|%d|%d|%d" % [lineage_seed, generation, parent_index, offspring_index]).hash()
				var child_result := LineageExtension.reproduce_bundle(parent["bundle"], mutation_seed, offspring_index, policy)
				if child_result.is_empty():
					return {}
				candidates.append(Bridge._evaluate(child_result["bundle"], env))
		candidates.sort_custom(Callable(Bridge, "_rank_order"))
		population = candidates.slice(0, FFF2_POPULATION)
	var foliage_sum := 0.0
	var root_shoot_sum := 0.0
	var checksums := PackedStringArray()
	for individual in population:
		foliage_sum += float(individual["bundle"]["ext_traits"]["foliage_density"])
		root_shoot_sum += float(individual["bundle"]["ext_traits"]["root_shoot_ratio"])
		checksums.append(String(individual["bundle"]["bundle_checksum"]))
	checksums.sort()
	return {
		"final_population_hash": "|".join(checksums).sha256_text(),
		"mean_foliage_density": snappedf(foliage_sum / float(population.size()), 1e-9),
		"mean_root_shoot_ratio": snappedf(root_shoot_sum / float(population.size()), 1e-9),
	}

func _fff3_multiseed() -> void:
	var started := Time.get_ticks_msec()
	var on_off_values: Array[bool] = []
	var lai_values: Array[bool] = []
	var understory_values: Array[bool] = []
	var determinism_values: Array[bool] = []
	for seed in SEEDS:
		var s := int(seed)
		var run_started := Time.get_ticks_msec()
		var result: Dictionary = LightBridge.run_all(s)
		var repeat: Dictionary = LightBridge.run_all(s)
		var ok := not result.is_empty() and not repeat.is_empty()
		var on_off := false
		var lai := false
		var understory := false
		var determinism := false
		if ok:
			var on: Dictionary = result["feedback_on"]
			var off: Dictionary = result["feedback_off"]
			on_off = String(on["final_population_hash"]) != String(off["final_population_hash"])
			lai = float(on["deep_shade_mean_lai"]) < float(on["open_light_mean_lai"])
			understory = float(on["mean_understory_light"]) < float(result["base_sunlight"]) - FFF3_UNDERSTORY_MARGIN
			determinism = String(result["result_hash"]) == String(repeat["result_hash"])
			print("FFF3 seed=%d deep_shade_lai=%.3f open_light_lai=%.3f understory=%.3f base_sunlight=%.3f on!=off=%s runtime_ms=%d result_hash=%s" % [
				s, float(on["deep_shade_mean_lai"]), float(on["open_light_mean_lai"]),
				float(on["mean_understory_light"]), float(result["base_sunlight"]),
				str(on_off), Time.get_ticks_msec() - run_started,
				String(result["result_hash"]).substr(0, 16)])
		else:
			push_error("FFF3 run_all returned an empty result for seed %d" % s)
			print("FFF3 seed=%d BRIDGE FAILED (empty result)" % s)
		on_off_values.append(on_off)
		lai_values.append(lai)
		understory_values.append(understory)
		determinism_values.append(determinism)
	_row("FFF3", "FFF3 causality: feedback_on != feedback_off", UNANIMOUS_SEEDS, on_off_values)
	_row("FFF3", "FFF3 form: deep_shade_lai < open_light_lai", DIRECTION_MIN_SEEDS, lai_values)
	_row("FFF3", "FFF3 darkening: understory < base_sunlight - 0.03", DIRECTION_MIN_SEEDS, understory_values)
	_row("FFF3", "FFF3 determinism: double-run identical result_hash", UNANIMOUS_SEEDS, determinism_values)
	print("FFF3 phase runtime_ms=%d" % (Time.get_ticks_msec() - started))

func _scenario_features(result: Dictionary, scenario_name: String) -> Dictionary:
	if result.is_empty() or not (result.get("scenarios", {}) as Dictionary).has(scenario_name):
		return {}
	var scenario: Dictionary = (result["scenarios"] as Dictionary)[scenario_name]
	if not scenario.has("mean_features"):
		return {}
	return scenario["mean_features"]

func _row(bridge: String, label: String, required_seeds: int, values: Array[bool]) -> void:
	matrix.append({
		"bridge": bridge,
		"label": label,
		"required": required_seeds,
		"values": values,
	})

func _stability_rates() -> void:
	for row in matrix:
		var passes := 0
		for value in row["values"]:
			if bool(value):
				passes += 1
		_check(passes >= int(row["required"]), "stability rate [%s] %s: %d/%d seeds (required >= %d)" % [
			String(row["bridge"]), String(row["label"]), passes, SEEDS.size(), int(row["required"])])

func _print_matrix() -> void:
	print("")
	print("=== ECO.EVO7 multiseed robustness: check x seed (directional >= %d/%d; unanimous == %d/%d) ===" % [
		DIRECTION_MIN_SEEDS, SEEDS.size(), UNANIMOUS_SEEDS, SEEDS.size()])
	var header := "%-52s" % "check"
	for seed in SEEDS:
		header += "%10d" % int(seed)
	header += "%8s" % "rate"
	print(header)
	for row in matrix:
		var line := "%-52s" % String(row["label"])
		var passes := 0
		for value in row["values"]:
			if bool(value):
				passes += 1
			line += "%10s" % ("pass" if bool(value) else "FAIL")
		line += "%7s" % ("%d/%d" % [passes, int(row["required"])])
		print(line)
	print("")

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish(started: int) -> void:
	print("total runtime_ms=%d" % (Time.get_ticks_msec() - started))
	if failures.is_empty():
		print("ECO.EVO7 multiseed robustness: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 multiseed robustness FAIL: %s" % failure)
	print("ECO.EVO7 multiseed robustness: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)

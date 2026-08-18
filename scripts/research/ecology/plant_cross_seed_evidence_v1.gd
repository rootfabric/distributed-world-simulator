extends RefCounted

const Protocol = preload("res://scripts/research/ecology/plant_cross_seed_protocol_v1.gd")

const TARGET_CELLS: Array[String] = ["DRY", "WET"]
const SEED_IDS: Array[String] = ["S01", "S02", "S03", "S04", "S05", "S06", "S07", "S08", "S09", "S10"]
const REQUIRED_POSITIVE_SEEDS := 8
const REQUIRED_HOME_ADVANTAGE_SEEDS := 8
const GENERATIONS := 10
const POPULATION_SIZE := 8
const EPSILON := 0.000000001
const E2_5_CONTROL_POLICY_HASH := "0e6481175af3658b2673a612717dd850b917ec5156260b37bd9ee29a9789dc4e"
const E2_5_TREATMENT_POLICY_HASH := "e2927ce7a8f6b3ab5f3d4942a2cc70ca3794e0d67c3e770e0301748967c14416"
const CELL_FIELDS: Array[String] = ["cell_id", "environment_checksum", "initial_population_hash", "control", "treatment", "sorting_detected", "sorting_gain", "adaptation_gain", "classification", "positive_adaptation_effect", "home_value", "away_value", "home_advantage", "paired_hash"]
const ARM_FIELDS: Array[String] = ["arm", "adaptation_enabled", "policy_hash", "initial", "final", "final_population", "arm_hash"]
const SUMMARY_FIELDS: Array[String] = ["generation", "average_net_resource_balance", "best_net_resource_balance", "lineage_counts", "trait_means", "unique_genome_count", "novel_genome_count", "population_hash"]
const SEED_RESULT_FIELDS: Array[String] = ["seed_id", "cells", "cross_environment", "full_seed_pass", "seed_hash"]
const AGGREGATE_FIELDS: Array[String] = ["cell_id", "seed_count", "adaptation_gains", "mean_adaptation_gain", "median_adaptation_gain", "q25_adaptation_gain", "q75_adaptation_gain", "minimum_adaptation_gain", "maximum_adaptation_gain", "positive_count", "null_count", "reversal_count", "home_advantage_count", "home_advantage_fail_count", "classification_counts", "leave_one_out_mean_values", "leave_one_out_min_mean", "max_leave_one_out_mean_shift", "robustness_pass", "cell_aggregate_hash"]

static func validate_seed_semantics(seed_result: Dictionary, strategies: Array, environments: Dictionary) -> bool:
	var frozen_checksums := Protocol.frozen_checksums(strategies)
	var treatment_populations := {}
	for index in range(TARGET_CELLS.size()):
		var cell_id := TARGET_CELLS[index]
		var cell: Dictionary = Dictionary(Array(seed_result.get("cells", []))[index])
		var environment: Dictionary = Dictionary(environments.get(cell_id, {}))
		if environment.is_empty() or String(cell.get("environment_checksum", "")) != String(environment.get("checksum", "")):
			return false
		var founders := Protocol.founders(strategies, cell_id)
		if founders.size() != POPULATION_SIZE:
			return false
		var expected_initial := Protocol.summary(founders, environment, 0, frozen_checksums)
		if expected_initial.is_empty():
			return false
		var control: Dictionary = cell.get("control", {})
		var treatment: Dictionary = cell.get("treatment", {})
		if String(control.get("arm", "")) != "CONTROL" or bool(control.get("adaptation_enabled", true)) or String(control.get("policy_hash", "")) != E2_5_CONTROL_POLICY_HASH:
			return false
		if String(treatment.get("arm", "")) != "TREATMENT" or not bool(treatment.get("adaptation_enabled", false)) or String(treatment.get("policy_hash", "")) != E2_5_TREATMENT_POLICY_HASH:
			return false
		if Dictionary(control.get("initial", {})) != expected_initial or Dictionary(treatment.get("initial", {})) != expected_initial:
			return false
		if String(cell.get("initial_population_hash", "")) != String(expected_initial.get("population_hash", "")):
			return false
		if not _population_identity_valid(Array(control.get("final_population", [])), strategies) or not _population_identity_valid(Array(treatment.get("final_population", [])), strategies):
			return false
		var expected_control_final := Protocol.summary(Array(control.get("final_population", [])), environment, GENERATIONS, frozen_checksums)
		var expected_treatment_final := Protocol.summary(Array(treatment.get("final_population", [])), environment, GENERATIONS, frozen_checksums)
		if expected_control_final.is_empty() or expected_treatment_final.is_empty():
			return false
		if Dictionary(control.get("final", {})) != expected_control_final or Dictionary(treatment.get("final", {})) != expected_treatment_final:
			return false
		if int(expected_control_final.get("novel_genome_count", -1)) != 0:
			return false
		var sorting_detected := Dictionary(expected_control_final.get("lineage_counts", {})) != Dictionary(expected_initial.get("lineage_counts", {}))
		var sorting_gain := float(expected_control_final.get("average_net_resource_balance", 0.0)) - float(expected_initial.get("average_net_resource_balance", 0.0))
		var adaptation_gain := float(expected_treatment_final.get("average_net_resource_balance", 0.0)) - float(expected_control_final.get("average_net_resource_balance", 0.0))
		var novel := int(expected_treatment_final.get("novel_genome_count", 0)) > 0
		if bool(cell.get("sorting_detected", false)) != sorting_detected or absf(float(cell.get("sorting_gain", 0.0)) - sorting_gain) > EPSILON or absf(float(cell.get("adaptation_gain", 0.0)) - adaptation_gain) > EPSILON:
			return false
		if String(cell.get("classification", "")) != Protocol.classification(sorting_detected, novel, adaptation_gain):
			return false
		if bool(cell.get("positive_adaptation_effect", false)) != (novel and adaptation_gain > EPSILON):
			return false
		treatment_populations[cell_id] = Array(treatment.get("final_population", [])).duplicate(true)
	var expected_cross := Protocol.cross_environment(treatment_populations, environments)
	if expected_cross.is_empty() or Dictionary(seed_result.get("cross_environment", {})) != expected_cross:
		return false
	var expected_full := true
	for cell_value in Array(seed_result.get("cells", [])):
		var cell: Dictionary = cell_value
		var cell_id := String(cell.get("cell_id", ""))
		var away_id := "WET" if cell_id == "DRY" else "DRY"
		var expected_home := float(Dictionary(expected_cross[cell_id])[cell_id])
		var expected_away := float(Dictionary(expected_cross[away_id])[cell_id])
		var expected_advantage := expected_home > expected_away + EPSILON
		if absf(float(cell.get("home_value", 0.0)) - expected_home) > EPSILON or absf(float(cell.get("away_value", 0.0)) - expected_away) > EPSILON or bool(cell.get("home_advantage", false)) != expected_advantage:
			return false
		if String(cell.get("paired_hash", "")) != Protocol.paired_hash(cell):
			return false
		if not bool(cell.get("positive_adaptation_effect", false)) or not expected_advantage:
			expected_full = false
	if bool(seed_result.get("full_seed_pass", false)) != expected_full:
		return false
	return String(seed_result.get("seed_hash", "")) == Protocol.seed_hash(seed_result)


static func _population_identity_valid(population: Array, strategies: Array) -> bool:
	if population.size() != POPULATION_SIZE:
		return false
	var expected := {}
	for strategy_value in strategies:
		var strategy: Dictionary = strategy_value
		expected[String(strategy.get("research_species_id", ""))] = strategy
	for value in population:
		if typeof(value) != TYPE_DICTIONARY:
			return false
		var member: Dictionary = value
		var species_id := String(member.get("research_species_id", ""))
		if not expected.has(species_id):
			return false
		var strategy: Dictionary = expected[species_id]
		if String(member.get("source_lineage_id", "")) != String(strategy.get("source_lineage_id", "")) or String(member.get("frozen_genome_checksum", "")) != String(strategy.get("genome_checksum", "")):
			return false
	return true


static func aggregate_cell(seed_results: Array, cell_id: String) -> Dictionary:
	var gains: Array[float] = []
	var positive := 0
	var null_count := 0
	var reversal := 0
	var home := 0
	var classifications := {}
	for seed_value in seed_results:
		var cell := Protocol.cell(Dictionary(seed_value), cell_id)
		if cell.is_empty():
			return {}
		var gain := float(cell["adaptation_gain"])
		gains.append(gain)
		if bool(cell["positive_adaptation_effect"]):
			positive += 1
		elif gain < -EPSILON:
			reversal += 1
		else:
			null_count += 1
		if bool(cell["home_advantage"]):
			home += 1
		var classification := String(cell["classification"])
		classifications[classification] = int(classifications.get(classification, 0)) + 1
	var sorted_gains := gains.duplicate()
	sorted_gains.sort()
	var total := 0.0
	for value in gains:
		total += value
	var mean := total / float(gains.size())
	var median: float = _median(sorted_gains)
	var q25: float = _nearest_quantile(sorted_gains, 0.25)
	var q75: float = _nearest_quantile(sorted_gains, 0.75)
	var loo_values: Array[float] = []
	var loo_min := INF
	var max_shift := 0.0
	for index in range(gains.size()):
		var loo_mean := (total - gains[index]) / float(gains.size() - 1)
		loo_values.append(loo_mean)
		loo_min = minf(loo_min, loo_mean)
		max_shift = maxf(max_shift, absf(loo_mean - mean))
	var robust: bool = positive >= REQUIRED_POSITIVE_SEEDS and home >= REQUIRED_HOME_ADVANTAGE_SEEDS and q25 > EPSILON and median > EPSILON and loo_min > EPSILON
	var aggregate := {
		"cell_id": cell_id,
		"seed_count": gains.size(),
		"adaptation_gains": gains,
		"mean_adaptation_gain": mean,
		"median_adaptation_gain": median,
		"q25_adaptation_gain": q25,
		"q75_adaptation_gain": q75,
		"minimum_adaptation_gain": sorted_gains[0],
		"maximum_adaptation_gain": sorted_gains[sorted_gains.size() - 1],
		"positive_count": positive,
		"null_count": null_count,
		"reversal_count": reversal,
		"home_advantage_count": home,
		"home_advantage_fail_count": gains.size() - home,
		"classification_counts": Protocol.sorted_counts(classifications),
		"leave_one_out_mean_values": loo_values,
		"leave_one_out_min_mean": loo_min,
		"max_leave_one_out_mean_shift": max_shift,
		"robustness_pass": robust,
	}
	aggregate["cell_aggregate_hash"] = cell_aggregate_hash(aggregate)
	return aggregate


static func _median(sorted_values: Array[float]) -> float:
	if sorted_values.is_empty():
		return NAN
	var n := sorted_values.size()
	if n % 2 == 1:
		return float(sorted_values[n / 2])
	return (float(sorted_values[n / 2 - 1]) + float(sorted_values[n / 2])) * 0.5


static func _nearest_quantile(sorted_values: Array[float], q: float) -> float:
	if sorted_values.is_empty() or q < 0.0 or q > 1.0:
		return NAN
	var index := int(floor(q * float(sorted_values.size() - 1)))
	return float(sorted_values[index])


static func seed_shape_valid(seed_result: Dictionary) -> bool:
	if not exact_fields(seed_result, SEED_RESULT_FIELDS) or not String(seed_result.get("seed_id", "")) in SEED_IDS:
		return false
	if typeof(seed_result.get("cells")) != TYPE_ARRAY or Array(seed_result["cells"]).size() != TARGET_CELLS.size() or typeof(seed_result.get("cross_environment")) != TYPE_DICTIONARY:
		return false
	for index in range(TARGET_CELLS.size()):
		var value = Array(seed_result["cells"])[index]
		if typeof(value) != TYPE_DICTIONARY:
			return false
		var cell: Dictionary = value
		if not _cell_shape_valid(cell) or String(cell["cell_id"]) != TARGET_CELLS[index]:
			return false
	var computed_full := true
	for value in Array(seed_result["cells"]):
		var cell: Dictionary = value
		if not bool(cell["positive_adaptation_effect"]) or not bool(cell["home_advantage"]):
			computed_full = false
	if computed_full != bool(seed_result.get("full_seed_pass", false)):
		return false
	return String(seed_result.get("seed_hash", "")) == Protocol.seed_hash(seed_result)


static func _cell_shape_valid(cell: Dictionary) -> bool:
	if not exact_fields(cell, CELL_FIELDS) or not String(cell.get("cell_id", "")) in TARGET_CELLS:
		return false
	if typeof(cell.get("control")) != TYPE_DICTIONARY or typeof(cell.get("treatment")) != TYPE_DICTIONARY:
		return false
	if not _arm_shape_valid(Dictionary(cell["control"])) or not _arm_shape_valid(Dictionary(cell["treatment"])):
		return false
	return String(cell.get("paired_hash", "")) == Protocol.paired_hash(cell)


static func _arm_shape_valid(arm: Dictionary) -> bool:
	if not exact_fields(arm, ARM_FIELDS) or typeof(arm.get("initial")) != TYPE_DICTIONARY or typeof(arm.get("final")) != TYPE_DICTIONARY or typeof(arm.get("final_population")) != TYPE_ARRAY:
		return false
	if not exact_fields(Dictionary(arm["initial"]), SUMMARY_FIELDS) or not exact_fields(Dictionary(arm["final"]), SUMMARY_FIELDS):
		return false
	if int(Dictionary(arm["initial"]).get("generation", -1)) != 0 or int(Dictionary(arm["final"]).get("generation", -1)) != GENERATIONS:
		return false
	return String(arm.get("arm_hash", "")) == Protocol.arm_hash(arm)

static func aggregate_shape_valid(aggregate: Dictionary) -> bool:
	if not exact_fields(aggregate, AGGREGATE_FIELDS) or not String(aggregate.get("cell_id", "")) in TARGET_CELLS:
		return false
	if int(aggregate.get("seed_count", -1)) != SEED_IDS.size() or typeof(aggregate.get("adaptation_gains")) != TYPE_ARRAY or Array(aggregate["adaptation_gains"]).size() != SEED_IDS.size():
		return false
	if typeof(aggregate.get("leave_one_out_mean_values")) != TYPE_ARRAY or Array(aggregate["leave_one_out_mean_values"]).size() != SEED_IDS.size() or typeof(aggregate.get("classification_counts")) != TYPE_DICTIONARY:
		return false
	if not bool(aggregate.get("robustness_pass", false)):
		return false
	return String(aggregate.get("cell_aggregate_hash", "")) == cell_aggregate_hash(aggregate)


static func cell_aggregate_hash(aggregate: Dictionary) -> String:
	var tokens := PackedStringArray([String(aggregate.get("cell_id", "")), str(int(aggregate.get("seed_count", 0)))])
	for value in Array(aggregate.get("adaptation_gains", [])):
		tokens.append("gain=%.12f" % float(value))
	for name in ["mean_adaptation_gain", "median_adaptation_gain", "q25_adaptation_gain", "q75_adaptation_gain", "minimum_adaptation_gain", "maximum_adaptation_gain", "leave_one_out_min_mean", "max_leave_one_out_mean_shift"]:
		tokens.append("%s=%.12f" % [name, float(aggregate.get(name, 0.0))])
	for name in ["positive_count", "null_count", "reversal_count", "home_advantage_count", "home_advantage_fail_count"]:
		tokens.append("%s=%d" % [name, int(aggregate.get(name, 0))])
	var classifications: Dictionary = aggregate.get("classification_counts", {})
	var keys: Array[String] = []
	for key in classifications.keys(): keys.append(String(key))
	keys.sort()
	for key in keys: tokens.append("class=%s|%d" % [key, int(classifications[key])])
	for value in Array(aggregate.get("leave_one_out_mean_values", [])):
		tokens.append("loo=%.12f" % float(value))
	tokens.append("pass=" + ("1" if bool(aggregate.get("robustness_pass", false)) else "0"))
	return "\n".join(tokens).sha256_text()


static func exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.keys().size() != fields.size():
		return false
	for field_name in fields:
		if not value.has(field_name):
			return false
	for key in value.keys():
		if not String(key) in fields:
			return false
	return true

extends SceneTree

const Baseline = preload("res://scripts/research/ecology/plant_morphology_economics_baseline_v1.gd")
const Competition = preload("res://scripts/research/ecology/plant_morphology_aware_selection_competition_v1.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var first: Dictionary = Baseline.run()
	var second: Dictionary = Baseline.run()
	_check(not first.is_empty(), "CAL1-A first baseline exists")
	_check(not second.is_empty(), "CAL1-A replay baseline exists")
	if first.is_empty() or second.is_empty():
		_finish(first)
		return

	_check(String(first.get("schema", "")) == Baseline.SCHEMA, "CAL1-A schema")
	_check(String(first.get("version", "")) == Baseline.VERSION, "CAL1-A version")
	_check(int(first.get("row_count", 0)) == Baseline.ENVIRONMENT_ORDER.size() * Baseline.STRATEGY_ORDER.size(), "CAL1-A has exact 4x8 matrix")
	_check(String(first.get("baseline_hash", "")).length() == 64, "CAL1-A baseline hash exists")
	_check(String(first["baseline_hash"]) == String(second["baseline_hash"]), "CAL1-A same-process replay hash exact")
	_check(String(first["legacy_ph3c_pairwise_hash"]) == String(second["legacy_ph3c_pairwise_hash"]), "CAL1-A PH3C pairwise replay exact")

	var direct_pairwise: Dictionary = Competition.run_matrix()
	_check(not direct_pairwise.is_empty(), "accepted PH3C matrix still runs")
	if not direct_pairwise.is_empty():
		_check(String(first["legacy_ph3c_pairwise_hash"]) == String(direct_pairwise["aggregate_hash"]), "CAL1-A records current accepted PH3C aggregate unchanged")
		var direct_results: Dictionary = direct_pairwise["results"]
		_check(String(direct_results["SUN_CROWN/AWARE"]["winner"]) == "CROWN_WIDE", "legacy SUN crown winner preserved")
		_check(String(direct_results["DRY_CROWN/AWARE"]["winner"]) == "CROWN_NARROW", "legacy DRY crown reversal preserved")
		_check(String(direct_results["REFERENCE_HEIGHT/AWARE"]["winner"]) == "HEIGHT_LOW", "legacy low-height pair winner preserved")
		_check(String(direct_results["REFERENCE_GIANT/AWARE"]["winner"]) == "BASE", "legacy giant penalty preserved")

	var environment_results: Dictionary = first["environment_results"]
	_check(environment_results.size() == Baseline.ENVIRONMENT_ORDER.size(), "four environment results")
	for environment_name in Baseline.ENVIRONMENT_ORDER:
		_check(environment_results.has(environment_name), "%s result exists" % environment_name)
		if not environment_results.has(environment_name):
			continue
		var environment_result: Dictionary = environment_results[environment_name]
		var rows: Array = environment_result.get("rows", [])
		var summary: Dictionary = environment_result.get("summary", {})
		_check(rows.size() == Baseline.STRATEGY_ORDER.size(), "%s has eight strategies" % environment_name)
		_check(not summary.is_empty(), "%s summary exists" % environment_name)
		if rows.size() != Baseline.STRATEGY_ORDER.size() or summary.is_empty():
			continue

		var share_sum := 0.0
		var common_seed := int(Dictionary(rows[0])["individual_seed"])
		var seen_ranks: Dictionary = {}
		for index in range(rows.size()):
			var row: Dictionary = rows[index]
			var strategy_name := String(row["strategy"])
			_check(int(row["rank"]) == index + 1, "%s/%s rank matches score order" % [environment_name, strategy_name])
			_check(not seen_ranks.has(int(row["rank"])), "%s/%s rank unique" % [environment_name, strategy_name])
			seen_ranks[int(row["rank"])] = true
			_check(int(row["individual_seed"]) == common_seed, "%s/%s common IndividualSeed isolates morphology" % [environment_name, strategy_name])
			_check(String(row["phenotype_hash"]).length() == 64, "%s/%s phenotype hash" % [environment_name, strategy_name])
			_check(String(row["growth_graph_hash"]).length() == 64, "%s/%s graph hash" % [environment_name, strategy_name])
			_check(String(row["coupling_hash"]).length() == 64, "%s/%s coupling hash" % [environment_name, strategy_name])
			_check(is_finite(float(row["realized_graph_height_m"])) and float(row["realized_graph_height_m"]) > 0.0, "%s/%s realized graph height finite positive" % [environment_name, strategy_name])
			_check(is_finite(float(row["realized_total_length_m"])) and float(row["realized_total_length_m"]) > 0.0, "%s/%s realized total length finite positive" % [environment_name, strategy_name])
			_check(is_finite(float(row["selection_score"])), "%s/%s selection score finite" % [environment_name, strategy_name])
			var raw: Dictionary = row["raw_components"]
			var signed: Dictionary = row["signed_components"]
			_check(raw.size() == Baseline.MORPH_COMPONENT_ORDER.size(), "%s/%s raw component count" % [environment_name, strategy_name])
			_check(signed.size() == Baseline.MORPH_COMPONENT_ORDER.size(), "%s/%s signed component count" % [environment_name, strategy_name])
			var reconstructed_delta := 0.0
			for component_name in Baseline.MORPH_COMPONENT_ORDER:
				_check(raw.has(component_name) and signed.has(component_name), "%s/%s component %s exists" % [environment_name, strategy_name, component_name])
				if not raw.has(component_name) or not signed.has(component_name):
					continue
				_check(is_finite(float(raw[component_name])) and float(raw[component_name]) >= 0.0, "%s/%s raw %s non-negative finite" % [environment_name, strategy_name, component_name])
				reconstructed_delta += float(signed[component_name])
			_check(absf(reconstructed_delta - float(row["morphology_delta"])) < 0.000000001, "%s/%s component sum reconstructs morphology delta" % [environment_name, strategy_name])
			_check(absf(float(row["base_net_resource_balance"]) + reconstructed_delta - float(row["selection_score"])) < 0.000000001, "%s/%s component sum reconstructs selection score" % [environment_name, strategy_name])
			_check(String(row["sensitivity_component"]) in Baseline.MORPH_COMPONENT_ORDER, "%s/%s sensitivity component known" % [environment_name, strategy_name])
			_check(int(row["sensitivity_rank_shift"]) >= 0, "%s/%s sensitivity rank shift non-negative" % [environment_name, strategy_name])
			_check(int(row["sensitivity_ablated_rank"]) >= 1 and int(row["sensitivity_ablated_rank"]) <= Baseline.STRATEGY_ORDER.size(), "%s/%s sensitivity ablated rank bounded" % [environment_name, strategy_name])
			_check(float(row["margin_to_winner"]) >= -0.000000001, "%s/%s winner margin non-negative" % [environment_name, strategy_name])
			_check(float(row["full_pool_share"]) > 0.0 and float(row["full_pool_share"]) < 1.0, "%s/%s full-pool share bounded" % [environment_name, strategy_name])
			share_sum += float(row["full_pool_share"])
		_check(absf(share_sum - 1.0) < 0.000000001, "%s full-pool shares conserve one" % environment_name)
		_check(String(summary["winner"]) == String(Dictionary(rows[0])["strategy"]), "%s summary winner matches rank one" % environment_name)
		_check(String(summary["runner_up"]) == String(Dictionary(rows[1])["strategy"]), "%s summary runner matches rank two" % environment_name)
		_check(float(summary["winner_margin"]) >= -0.000000001, "%s winner margin non-negative" % environment_name)
		_check(String(summary["winner_top_driver"]) != "", "%s winner driver identified" % environment_name)
		_check(String(summary["height_low_vs_high_top_driver"]) != "", "%s HEIGHT_LOW vs HIGH driver identified" % environment_name)
		_check(float(summary["height_low_minus_height_high"]) > 0.0, "%s HEIGHT_LOW still beats HEIGHT_HIGH before new mechanisms" % environment_name)
		print("ECO.CAL1-A %s winner=%s runner=%s margin=%.9f driver=%s driver_delta=%.9f height_low_rank=%d height_high_rank=%d height_delta=%.9f height_driver=%s" % [
			environment_name,
			String(summary["winner"]),
			String(summary["runner_up"]),
			float(summary["winner_margin"]),
			String(summary["winner_top_driver"]),
			float(summary["winner_top_driver_delta"]),
			int(summary["height_low_rank"]),
			int(summary["height_high_rank"]),
			float(summary["height_low_minus_height_high"]),
			String(summary["height_low_vs_high_top_driver"]),
		])

	_check(int(first["height_low_beats_height_high_count"]) == Baseline.ENVIRONMENT_ORDER.size(), "HEIGHT_LOW beats HEIGHT_HIGH across all four controlled environments")
	_check(int(first["height_low_top2_count"]) >= 3, "known HEIGHT_LOW broad full-pool advantage reproduced")
	_check(String(first["dominance_classification"]) in ["HEIGHT_LOW_BROAD_FULL_POOL_WINNER", "HEIGHT_LOW_BROAD_FULL_POOL_ADVANTAGE"], "known compact dominance classified as broad")
	_test_source_boundaries()
	_finish(first)

func _test_source_boundaries() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_morphology_economics_baseline_v1.gd").to_lower()
	_check(source.contains("plant_morphology_resource_coupling_v1.gd"), "CAL1-A consumes accepted PH3 coupling")
	_check(source.contains("plant_morphology_aware_selection_competition_v1.gd"), "CAL1-A consumes accepted PH3C strategy pool/isolation")
	_check(not source.contains("plant_morphology_resource_profile_v1.gd"), "CAL1-A does not import coefficient profile")
	_check(not source.contains("profile.create"), "CAL1-A does not construct tuned coefficient profile")
	for forbidden in ["meshinstance", "multimesh", "camera3d", "authority", "network", "persistence", "worldquery", "scheduler"]:
		_check(not source.contains(forbidden), "CAL1-A source excludes %s" % forbidden)

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish(result: Dictionary) -> void:
	if failures.is_empty():
		print("ECO.CAL1-A Baseline Decomposition / Mechanism Audit: PASS (%d assertions) baseline_hash=%s legacy_ph3c_pairwise_hash=%s classification=%s height_low_wins=%d height_low_top2=%d" % [
			assertions,
			String(result.get("baseline_hash", "")),
			String(result.get("legacy_ph3c_pairwise_hash", "")),
			String(result.get("dominance_classification", "")),
			int(result.get("height_low_win_count", 0)),
			int(result.get("height_low_top2_count", 0)),
		])
		quit(0)
		return
	for failure in failures:
		push_error("ECO.CAL1-A FAIL: %s" % failure)
	print("ECO.CAL1-A Baseline Decomposition / Mechanism Audit: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)

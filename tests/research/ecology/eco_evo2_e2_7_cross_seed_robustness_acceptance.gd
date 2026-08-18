extends SceneTree

const E27 = preload("res://scripts/research/ecology/plant_cross_seed_robustness_v1.gd")

var assertions := 0
var failed := false


func _init() -> void:
	_check(E27.PARENT_E2_6_ACCEPTED_AGGREGATE == "1a4bcf1cffe65450a27037e9307bb5c7ac3cb8a98899918207107e367d9d5fbd", "exact accepted E2.6 aggregate pinned")
	_check(E27.PARENT_E2_6_CODE_UNDER_TEST == "8ac37bfea0f36731407e1252db1a7c2a2305420e", "exact accepted E2.6 code-under-test pinned")
	_check(E27.PARENT_E2_6_REPLICATE_SET_HASH == "5e02d04d3d94f95f6e8e76f6387ee07c723d2e596046f6a65d65cd815abbc637", "exact accepted E2.6 replicate-set hash pinned")
	_check(E27.E2_2_BAKE_HASH == "45496eb67aac5cc0a65babfeb0c49fa99616df17c2f7e8b9e8b95d04cb2b4e5b", "exact E2.2 bake pinned")
	_check(E27.E2_2_CATALOG_HASH == "5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219", "exact E2.2 catalog pinned")
	_check(E27.SEED_IDS == ["S01", "S02", "S03", "S04", "S05", "S06", "S07", "S08", "S09", "S10"], "cross-seed ensemble is predeclared and ordered")
	_check(E27.SEED_IDS.size() == 10, "E2.7 doubles E2.6 five-stream breadth")
	_check(E27.REQUIRED_POSITIVE_SEEDS == 8 and E27.REQUIRED_HOME_ADVANTAGE_SEEDS == 8 and E27.REQUIRED_FULL_SEED_PASS == 7, "robustness thresholds frozen before evidence")
	_check(E27.GENERATIONS == 10 and E27.POPULATION_SIZE == 8 and E27.OFFSPRING_PER_PARENT == 4, "E2.5/E2.6 causal horizon and population protocol preserved")

	var control_policy := E27.control_policy()
	var treatment_policy := E27.treatment_policy()
	_check(float(control_policy["mutation_probability"]) == 0.0, "Control hard-disables mutation")
	_check(float(treatment_policy["mutation_probability"]) == 0.30, "Treatment reuses exact E2.5 mutation probability")
	_check(_policies_differ_only_in_mutation_permission(control_policy, treatment_policy), "Control/Treatment differ only by mutation permission")
	_check(E27.MutationKernel.policy_hash(control_policy) == E27.E2_5_CONTROL_POLICY_HASH, "Control policy exact E2.5 hash")
	_check(E27.MutationKernel.policy_hash(treatment_policy) == E27.E2_5_TREATMENT_POLICY_HASH, "Treatment policy exact E2.5 hash")

	var result := E27.run()
	_check(not result.is_empty(), "E2.7 cross-seed experiment executes")
	_check(E27.validate_result(result), "E2.7 result deterministic replay validates")
	_check(String(result["parent_e2_6_accepted_aggregate"]) == E27.PARENT_E2_6_ACCEPTED_AGGREGATE, "result carries exact E2.6 aggregate")
	_check(String(result["parent_e2_6_code_under_test"]) == E27.PARENT_E2_6_CODE_UNDER_TEST, "result carries exact E2.6 code-under-test")
	_check(String(result["parent_e2_6_replicate_set_hash"]) == E27.PARENT_E2_6_REPLICATE_SET_HASH, "result carries exact E2.6 replicate-set identity")
	_check(Array(result["target_cells"]) == ["DRY", "WET"], "challenge cells remain DRY/WET")
	_check(Array(result["seed_ids"]) == E27.SEED_IDS, "result preserves full predeclared seed ensemble")
	_check(String(result["seed_ensemble_hash"]) == E27.compute_seed_ensemble_hash(E27.SEED_IDS), "seed ensemble hashes canonically")
	_check(not bool(result["censoring_allowed"]), "post-hoc seed censoring forbidden")
	_check(bool(result["all_seeds_retained"]), "all predeclared seeds retained")
	_check(not bool(result["formal_significance_claimed"]), "bounded robustness does not claim formal significance")
	_check(not bool(result["cross_catalog_robustness_claimed"]), "E2.7 does not claim cross-catalog robustness")
	_check(not bool(result["canonical_species_declared"]), "E2.7 does not promote canonical species taxonomy")
	_check(not bool(result["production_authority_claimed"]), "E2.7 remains research-only")
	_check(bool(result["bounded_cross_seed_robustness_pass"]), "predeclared bounded cross-seed robustness gate passes")
	_check(int(result["full_seed_pass_count"]) >= E27.REQUIRED_FULL_SEED_PASS, "enough complete seeds pass both cells and reciprocal contrast")
	_check(int(result["full_seed_pass_count"]) + int(result["full_seed_fail_count"]) == E27.SEED_IDS.size(), "full seed accounting has no censoring")

	var strategies: Array = result["frozen_strategies"]
	_check(strategies.size() == 2, "same two frozen E2.2 strategies used")
	_check(_strategy_checksum(strategies, "eco-lineage/e22-alpha") == "ebed17aadaf721218d91af4c07bc1242700151fdad8d3f614b43e751de607383", "alpha frozen genome exact")
	_check(_strategy_checksum(strategies, "eco-lineage/e22-beta") == "a4c391bd696aea19075f7b7ff42122401db65644b038d7983d89f18102e9eff6", "beta frozen genome exact")
	var environments: Dictionary = result["environments"]
	_check(String(Dictionary(environments["DRY"])["checksum"]) == "45e23226bf205381aa1d1e85d987f0815714fcea674e4856d534f55f38e5588b", "exact accepted DRY environment reused")
	_check(String(Dictionary(environments["WET"])["checksum"]) == "b9c6a58274ff30329a8cad3b02360a5c61036da19a4d8a0d422786bb469b7ec5", "exact accepted WET environment reused")

	var seen_hashes := {}
	for index in range(E27.SEED_IDS.size()):
		var seed_result: Dictionary = Array(result["seed_results"])[index]
		var seed_id := E27.SEED_IDS[index]
		_check(String(seed_result["seed_id"]) == seed_id, seed_id + " retained in predeclared order")
		_check(String(seed_result["seed_hash"]).length() == 64, seed_id + " seed result hashes canonically")
		_check(not seen_hashes.has(String(seed_result["seed_hash"])), seed_id + " seed result is distinct")
		seen_hashes[String(seed_result["seed_hash"])] = true
		var dry := E27._cell(seed_result, "DRY")
		var wet := E27._cell(seed_result, "WET")
		_check(not dry.is_empty() and not wet.is_empty(), seed_id + " contains both challenge cells")
		for cell in [dry, wet]:
			var cell_id := String(cell["cell_id"])
			var control: Dictionary = cell["control"]
			var treatment: Dictionary = cell["treatment"]
			_check(String(control["initial"]["population_hash"]) == String(treatment["initial"]["population_hash"]), seed_id + " " + cell_id + " paired arms start identically")
			_check(not bool(control["adaptation_enabled"]) and bool(treatment["adaptation_enabled"]), seed_id + " " + cell_id + " only Treatment enables adaptation")
			_check(int(control["final"]["novel_genome_count"]) == 0, seed_id + " " + cell_id + " Control remains genetically frozen")
			_check(bool(cell["sorting_detected"]) and float(cell["sorting_gain"]) > 0.0, seed_id + " " + cell_id + " Control exhibits beneficial ecological sorting")
			_check(int(treatment["final"]["novel_genome_count"]) > 0, seed_id + " " + cell_id + " Treatment produces inherited novel genomes")
			_check(String(cell["classification"]) in ["ADAPTATION_DETECTED", "ADAPTATION_NO_MEASURABLE_ADVANTAGE", "SORTING_ONLY_RESPONSE", "NO_RESPONSE"], seed_id + " " + cell_id + " classification is explicit")
			_check(String(cell["paired_hash"]).length() == 64, seed_id + " " + cell_id + " paired evidence hashes")
			if bool(cell["positive_adaptation_effect"]):
				_check(String(cell["classification"]) == "ADAPTATION_DETECTED" and float(cell["adaptation_gain"]) > E27.EPSILON, seed_id + " " + cell_id + " positive effect has causal adaptation classification")
			else:
				_check(float(cell["adaptation_gain"]) <= E27.EPSILON, seed_id + " " + cell_id + " null/reversal effect is retained rather than promoted")
		var expected_full := bool(dry["positive_adaptation_effect"]) and bool(dry["home_advantage"]) and bool(wet["positive_adaptation_effect"]) and bool(wet["home_advantage"])
		_check(bool(seed_result["full_seed_pass"]) == expected_full, seed_id + " full-seed pass derives from both paired effects and reciprocal home advantage")

	for cell_id in E27.TARGET_CELLS:
		var aggregate := _aggregate(result, cell_id)
		_check(not aggregate.is_empty(), cell_id + " robustness aggregate present")
		_check(int(aggregate["seed_count"]) == E27.SEED_IDS.size(), cell_id + " aggregate retains every seed")
		_check(Array(aggregate["adaptation_gains"]).size() == E27.SEED_IDS.size(), cell_id + " aggregate exposes all effect sizes")
		_check(int(aggregate["positive_count"]) >= E27.REQUIRED_POSITIVE_SEEDS, cell_id + " positive-effect rate clears predeclared threshold")
		_check(int(aggregate["home_advantage_count"]) >= E27.REQUIRED_HOME_ADVANTAGE_SEEDS, cell_id + " reciprocal-home rate clears predeclared threshold")
		_check(int(aggregate["positive_count"]) + int(aggregate["null_count"]) + int(aggregate["reversal_count"]) == E27.SEED_IDS.size(), cell_id + " positive/null/reversal accounting complete")
		_check(float(aggregate["q25_adaptation_gain"]) > 0.0, cell_id + " lower quartile adaptation gain remains positive")
		_check(float(aggregate["median_adaptation_gain"]) > 0.0, cell_id + " median adaptation gain remains positive")
		_check(float(aggregate["leave_one_out_min_mean"]) > 0.0, cell_id + " mean stays positive after removing any single seed")
		_check(float(aggregate["minimum_adaptation_gain"]) <= float(aggregate["q25_adaptation_gain"]), cell_id + " min <= q25")
		_check(float(aggregate["q25_adaptation_gain"]) <= float(aggregate["median_adaptation_gain"]), cell_id + " q25 <= median")
		_check(float(aggregate["median_adaptation_gain"]) <= float(aggregate["q75_adaptation_gain"]), cell_id + " median <= q75")
		_check(float(aggregate["q75_adaptation_gain"]) <= float(aggregate["maximum_adaptation_gain"]), cell_id + " q75 <= max")
		_check(Array(aggregate["leave_one_out_mean_values"]).size() == E27.SEED_IDS.size(), cell_id + " leave-one-out influence audit covers every seed")
		_check(bool(aggregate["robustness_pass"]), cell_id + " bounded robustness aggregate passes")
		_check(String(aggregate["cell_aggregate_hash"]).length() == 64, cell_id + " aggregate hashes canonically")

	var drop_seed := result.duplicate(true)
	var dropped: Array = Array(drop_seed["seed_results"]).duplicate(true)
	dropped.remove_at(dropped.size() - 1)
	drop_seed["seed_results"] = dropped
	drop_seed["aggregate_hash"] = E27.compute_aggregate_hash(drop_seed)
	_check(not E27.validate_result(drop_seed), "dropping a seed fails closed even after aggregate rehash")

	var reordered := result.duplicate(true)
	var reordered_values: Array = Array(reordered["seed_results"]).duplicate(true)
	var tmp = reordered_values[0]
	reordered_values[0] = reordered_values[1]
	reordered_values[1] = tmp
	reordered["seed_results"] = reordered_values
	reordered["aggregate_hash"] = E27.compute_aggregate_hash(reordered)
	_check(not E27.validate_result(reordered), "reordering predeclared seeds fails closed even after rehash")

	var semantic := result.duplicate(true)
	var seed_values: Array = Array(semantic["seed_results"]).duplicate(true)
	var first_seed: Dictionary = Dictionary(seed_values[0]).duplicate(true)
	var cells: Array = Array(first_seed["cells"]).duplicate(true)
	var dry_cell: Dictionary = Dictionary(cells[0]).duplicate(true)
	dry_cell["adaptation_gain"] = float(dry_cell["adaptation_gain"]) + 0.125
	dry_cell["paired_hash"] = E27._paired_hash(dry_cell)
	cells[0] = dry_cell
	first_seed["cells"] = cells
	first_seed["seed_hash"] = E27._seed_hash(first_seed)
	seed_values[0] = first_seed
	semantic["seed_results"] = seed_values
	semantic["cell_aggregates"] = [E27._aggregate_cell(seed_values, "DRY"), E27._aggregate_cell(seed_values, "WET")]
	semantic["aggregate_hash"] = E27.compute_aggregate_hash(semantic)
	_check(not E27.validate_result(semantic), "fully rehashed semantic effect tamper rejected by deterministic replay")

	var significance := result.duplicate(true)
	significance["formal_significance_claimed"] = true
	significance["aggregate_hash"] = E27.compute_aggregate_hash(significance)
	_check(not E27.validate_result(significance), "formal significance promotion fails closed")
	var cross_catalog := result.duplicate(true)
	cross_catalog["cross_catalog_robustness_claimed"] = true
	cross_catalog["aggregate_hash"] = E27.compute_aggregate_hash(cross_catalog)
	_check(not E27.validate_result(cross_catalog), "cross-catalog robustness promotion fails closed")
	var authority := result.duplicate(true)
	authority["production_authority_claimed"] = true
	authority["aggregate_hash"] = E27.compute_aggregate_hash(authority)
	_check(not E27.validate_result(authority), "production authority promotion fails closed")

	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_cross_seed_robustness_v1.gd") + "\n" + FileAccess.get_file_as_string("res://scripts/research/ecology/plant_cross_seed_protocol_v1.gd") + "\n" + FileAccess.get_file_as_string("res://scripts/research/ecology/plant_cross_seed_evidence_v1.gd")
	_check(source.find("MutationKernel.reproduce") >= 0, "E2.7 reuses exact deterministic mutation kernel")
	_check(source.find("ResourceModel.evaluate") >= 0, "E2.7 selection consequence reuses exact causal ResourceModel")
	_check(source.find("biome") == -1 and source.find("species_table") == -1, "E2.7 has no biome-to-species shortcut")
	_check(source.find("fitness_bonus") == -1 and source.find("target_bonus") == -1, "E2.7 has no hidden seed/environment fitness bonus")
	_check(source.find("randf(") == -1 and source.find("randi(") == -1 and source.find("randomize(") == -1, "E2.7 consumes no global RNG API")
	_check(source.find("plant_replicated_causal_experiments_v1.gd") == -1, "accepted E2.6 runtime is pinned as parent rather than silently reexecuted")

	if failed:
		quit(1)
		return
	print("ECO.EVO2 E2.7 Cross-Seed Robustness: PASS (%d assertions)" % assertions)
	print("aggregate_hash=" + String(result["aggregate_hash"]))
	print("parent_e2_6=" + E27.PARENT_E2_6_ACCEPTED_AGGREGATE)
	print("parent_e2_6_head=" + E27.PARENT_E2_6_CODE_UNDER_TEST)
	print("parent_e2_6_replicate_set=" + E27.PARENT_E2_6_REPLICATE_SET_HASH)
	print("seed_ensemble_hash=" + String(result["seed_ensemble_hash"]))
	print("full_seed_pass_count=%d" % int(result["full_seed_pass_count"]))
	print("full_seed_fail_count=%d" % int(result["full_seed_fail_count"]))
	for cell_id in E27.TARGET_CELLS:
		var aggregate := _aggregate(result, cell_id)
		print("%s_mean=%.12f" % [cell_id.to_lower(), float(aggregate["mean_adaptation_gain"])])
		print("%s_median=%.12f" % [cell_id.to_lower(), float(aggregate["median_adaptation_gain"])])
		print("%s_q25=%.12f" % [cell_id.to_lower(), float(aggregate["q25_adaptation_gain"])])
		print("%s_q75=%.12f" % [cell_id.to_lower(), float(aggregate["q75_adaptation_gain"])])
		print("%s_min=%.12f" % [cell_id.to_lower(), float(aggregate["minimum_adaptation_gain"])])
		print("%s_max=%.12f" % [cell_id.to_lower(), float(aggregate["maximum_adaptation_gain"])])
		print("%s_positive_count=%d" % [cell_id.to_lower(), int(aggregate["positive_count"])])
		print("%s_null_count=%d" % [cell_id.to_lower(), int(aggregate["null_count"])])
		print("%s_reversal_count=%d" % [cell_id.to_lower(), int(aggregate["reversal_count"])])
		print("%s_home_count=%d" % [cell_id.to_lower(), int(aggregate["home_advantage_count"])])
		print("%s_loo_min_mean=%.12f" % [cell_id.to_lower(), float(aggregate["leave_one_out_min_mean"])])
		print("%s_aggregate_hash=%s" % [cell_id.to_lower(), String(aggregate["cell_aggregate_hash"])])
	for seed_value in Array(result["seed_results"]):
		var seed_result: Dictionary = seed_value
		print("seed_%s_hash=%s" % [String(seed_result["seed_id"]).to_lower(), String(seed_result["seed_hash"])])
	quit(0)


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if condition:
		return
	failed = true
	push_error("E2.7 assertion failed: " + label)


func _aggregate(result: Dictionary, cell_id: String) -> Dictionary:
	for value in Array(result.get("cell_aggregates", [])):
		if typeof(value) == TYPE_DICTIONARY and String(Dictionary(value).get("cell_id", "")) == cell_id:
			return Dictionary(value)
	return {}


func _strategy_checksum(strategies: Array, lineage_id: String) -> String:
	for value in strategies:
		var strategy: Dictionary = value
		if String(strategy.get("source_lineage_id", "")) == lineage_id:
			return String(strategy.get("genome_checksum", ""))
	return ""


func _policies_differ_only_in_mutation_permission(control: Dictionary, treatment: Dictionary) -> bool:
	if control.keys().size() != treatment.keys().size():
		return false
	for key in treatment.keys():
		if String(key) == "mutation_probability":
			continue
		if control[key] != treatment[key]:
			return false
	return true

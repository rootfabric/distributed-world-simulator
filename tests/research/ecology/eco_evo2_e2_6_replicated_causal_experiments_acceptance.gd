extends SceneTree

const E26 = preload("res://scripts/research/ecology/plant_replicated_causal_experiments_v1.gd")

var assertions := 0
var failed := false


func _init() -> void:
	_check(E26.PARENT_E2_5_ACCEPTED_AGGREGATE == "942ad54e7672c4f57874e1802b320c1b2a4aa74e43b05f7e285793ea4ec8b2a6", "exact accepted E2.5 aggregate pinned")
	_check(E26.PARENT_E2_5_CODE_UNDER_TEST == "4c17a91957e392eabc04e136f9590773dbe54dd1", "exact accepted E2.5 code-under-test pinned")
	_check(E26.PARENT_E2_4_ACCEPTED_AGGREGATE == "ae2952de10ac721c8052694963b690d9f72af05d9c92e2fa4cd70e00f72fb2b5", "exact accepted E2.4 aggregate provenance pinned")
	_check(E26.PARENT_E2_4_PLAN_HASH == "f688eb014245d63483562376c3f5db8c08a85bdc35feb52428f5ff17753f82e0", "exact accepted E2.4 plan provenance pinned")
	_check(E26.E2_2_BAKE_HASH == "45496eb67aac5cc0a65babfeb0c49fa99616df17c2f7e8b9e8b95d04cb2b4e5b", "exact E2.2 bake provenance pinned")
	_check(E26.E2_2_CATALOG_HASH == "5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219", "exact E2.2 catalog provenance pinned")
	_check(E26.REPLICATE_IDS == ["R01", "R02", "R03", "R04", "R05"], "replicate set predeclared as R01..R05")
	_check(E26.REQUIRED_POSITIVE_REPLICATES == 4 and E26.REQUIRED_HOME_ADVANTAGE_REPLICATES == 4, "replicated signal thresholds predeclared at 4/5")
	_check(E26.GENERATIONS == 10 and E26.POPULATION_SIZE == 8 and E26.OFFSPRING_PER_PARENT == 4, "E2.5 bounded assay shape preserved")

	var control_policy := E26.control_policy()
	var treatment_policy := E26.treatment_policy()
	_check(float(control_policy["mutation_probability"]) == 0.0, "Control disables inherited variation")
	_check(float(treatment_policy["mutation_probability"]) == 0.30, "Treatment preserves E2.5 mutation permission")
	_check(_policies_differ_only_in_mutation_permission(control_policy, treatment_policy), "Control/Treatment differ only by mutation permission")
	_check(E26.MutationKernel.policy_hash(control_policy) == E26.E2_5_CONTROL_POLICY_HASH, "Control policy hash exactly equals accepted E2.5")
	_check(E26.MutationKernel.policy_hash(treatment_policy) == E26.E2_5_TREATMENT_POLICY_HASH, "Treatment policy hash exactly equals accepted E2.5")

	var strategies := E26._frozen_strategies()
	_check(strategies.size() == 2, "exact frozen strategy pair reconstructs")
	_check(String(Dictionary(strategies[0])["research_species_id"]) == "eco-research-species/247a0b301db2781bfc317a13", "canonical ordering pins beta research identity")
	_check(String(Dictionary(strategies[1])["research_species_id"]) == "eco-research-species/34b4de11b3cbb2eae9f73176", "canonical ordering pins alpha research identity")
	_check(_strategy_checksum(strategies, "eco-lineage/e22-alpha") == "ebed17aadaf721218d91af4c07bc1242700151fdad8d3f614b43e751de607383", "frozen alpha genome checksum pinned")
	_check(_strategy_checksum(strategies, "eco-lineage/e22-beta") == "a4c391bd696aea19075f7b7ff42122401db65644b038d7983d89f18102e9eff6", "frozen beta genome checksum pinned")

	var environments := E26._environments()
	_check(environments.keys().size() == 2, "exact DRY/WET environment pair reconstructs")
	_check(String(Dictionary(environments["DRY"])["checksum"]) == "45e23226bf205381aa1d1e85d987f0815714fcea674e4856d534f55f38e5588b", "exact accepted E2.4 DRY environment pinned")
	_check(String(Dictionary(environments["WET"])["checksum"]) == "b9c6a58274ff30329a8cad3b02360a5c61036da19a4d8a0d422786bb469b7ec5", "exact accepted E2.4 WET environment pinned")

	seed(26062606)
	var expected_rng := [randi(), randi(), randi(), randi()]
	seed(26062606)
	var result := E26.run()
	var actual_rng := [randi(), randi(), randi(), randi()]
	_check(actual_rng == expected_rng, "E2.6 consumes no global RNG")
	_check(not result.is_empty(), "E2.6 replicated causal experiment executes")
	_check(E26.validate_result(result), "E2.6 result independently reconstructs and validates")
	_check(Array(result["replicate_ids"]) == E26.REPLICATE_IDS, "artifact retains exact predeclared replicate IDs and order")
	_check(Array(result["replicates"]).size() == 5, "artifact retains all five replicate records")
	_check(bool(result["all_replicates_retained"]), "artifact explicitly declares all replicates retained")
	_check(not bool(result["censoring_allowed"]), "post-hoc replicate censoring is forbidden")
	_check(not bool(result["significance_claimed"]), "n=5 replication does not claim statistical significance")
	_check(not bool(result["cross_seed_robustness_claimed"]), "E2.6 does not impersonate E2.7 cross-seed robustness")
	_check(not bool(result["canonical_species_declared"]), "replication does not promote canonical biological species")
	_check(not bool(result["production_authority_claimed"]), "replication remains research-only")
	_check(String(result["replicate_set_hash"]) == E26.compute_replicate_set_hash(E26.REPLICATE_IDS), "replicate-set identity hashes canonically")

	var common_initial := {"DRY": "", "WET": ""}
	var seen_replicates := {}
	var raw_gains := {"DRY": [], "WET": []}
	var positive_counts := {"DRY": 0, "WET": 0}
	var home_counts := {"DRY": 0, "WET": 0}
	var classification_counts := {"DRY": {}, "WET": {}}
	for replicate_value in Array(result["replicates"]):
		var replicate: Dictionary = replicate_value
		var replicate_id := String(replicate["replicate_id"])
		_check(not seen_replicates.has(replicate_id), replicate_id + " appears exactly once")
		seen_replicates[replicate_id] = true
		_check(String(replicate["replicate_hash"]).length() == 64, replicate_id + " has canonical replicate hash")
		_check(Dictionary(replicate["cross_environment"]).keys().size() == 2, replicate_id + " carries full reciprocal cross-environment matrix")
		for cell_id in E26.TARGET_CELLS:
			var cell := E26._cell(replicate, cell_id)
			_check(not cell.is_empty(), replicate_id + " retains " + cell_id + " paired record")
			var control: Dictionary = cell["control"]
			var treatment: Dictionary = cell["treatment"]
			_check(String(control["initial"]["population_hash"]) == String(treatment["initial"]["population_hash"]), replicate_id + " " + cell_id + " arms have exact same founders")
			if String(common_initial[cell_id]).is_empty():
				common_initial[cell_id] = String(control["initial"]["population_hash"])
			_check(String(control["initial"]["population_hash"]) == String(common_initial[cell_id]), replicate_id + " " + cell_id + " reuses replicate-independent founder set")
			_check(not bool(control["adaptation_enabled"]) and bool(treatment["adaptation_enabled"]), replicate_id + " " + cell_id + " changes only adaptation permission")
			_check(Array(control["selected_mutation_events"]).is_empty(), replicate_id + " " + cell_id + " Control selects no mutations")
			_check(int(control["final"]["novel_genome_count"]) == 0, replicate_id + " " + cell_id + " Control remains genetically frozen")
			_check(bool(cell["sorting_detected"]), replicate_id + " " + cell_id + " frozen Control exhibits ecological sorting")
			_check(float(cell["sorting_gain"]) > 0.0, replicate_id + " " + cell_id + " sorting has positive resource response")
			_check(String(cell["classification"]) in ["ADAPTATION_DETECTED", "ADAPTATION_NO_MEASURABLE_ADVANTAGE", "SORTING_ONLY_RESPONSE", "NO_RESPONSE"], replicate_id + " " + cell_id + " retains explicit causal classification")
			_check(String(cell["paired_hash"]).length() == 64, replicate_id + " " + cell_id + " paired evidence hashes canonically")
			_check(_population_preserves_research_identity(Array(treatment["final_population"]), strategies), replicate_id + " " + cell_id + " adapted descendants preserve frozen research identities")
			var gain := float(cell["adaptation_gain"])
			raw_gains[cell_id].append(gain)
			if bool(cell["positive_adaptation_effect"]):
				positive_counts[cell_id] = int(positive_counts[cell_id]) + 1
				_check(int(treatment["final"]["novel_genome_count"]) > 0 and gain > E26.EPSILON, replicate_id + " " + cell_id + " positive effect requires novel genome plus positive gain")
			if bool(cell["home_advantage"]):
				home_counts[cell_id] = int(home_counts[cell_id]) + 1
				_check(float(cell["home_value"]) > float(cell["away_value"]), replicate_id + " " + cell_id + " home advantage uses direct reciprocal evaluation")
			var class_counts: Dictionary = classification_counts[cell_id]
			var classification := String(cell["classification"])
			class_counts[classification] = int(class_counts.get(classification, 0)) + 1
			classification_counts[cell_id] = class_counts

	_check(seen_replicates.keys().size() == E26.REPLICATE_IDS.size(), "no replicate silently disappears")
	for cell_id in E26.TARGET_CELLS:
		var aggregate := _aggregate(result, cell_id)
		_check(not aggregate.is_empty(), cell_id + " aggregate present")
		_check(int(aggregate["replicate_count"]) == 5, cell_id + " aggregate counts all five replicates")
		_check(Array(aggregate["adaptation_gains"]) == Array(raw_gains[cell_id]), cell_id + " raw gains retained without filtering")
		_check(int(aggregate["positive_adaptation_count"]) == int(positive_counts[cell_id]), cell_id + " positive count derives from retained records")
		_check(int(aggregate["nonpositive_adaptation_count"]) == 5 - int(positive_counts[cell_id]), cell_id + " null/reversal count remains explicit")
		_check(int(aggregate["home_advantage_count"]) == int(home_counts[cell_id]), cell_id + " home-advantage count derives from retained records")
		_check(int(aggregate["home_advantage_fail_count"]) == 5 - int(home_counts[cell_id]), cell_id + " reciprocal failures remain explicit")
		_check(Dictionary(aggregate["classification_counts"]) == _sorted_counts(Dictionary(classification_counts[cell_id])), cell_id + " classification histogram retains every outcome")
		_check(_aggregate_numbers_match(Array(raw_gains[cell_id]), aggregate), cell_id + " mean/median/min/max recompute from raw retained gains")
		_check(int(aggregate["positive_adaptation_count"]) >= E26.REQUIRED_POSITIVE_REPLICATES, cell_id + " reaches predeclared >=4/5 positive adaptation threshold")
		_check(int(aggregate["home_advantage_count"]) >= E26.REQUIRED_HOME_ADVANTAGE_REPLICATES, cell_id + " reaches predeclared >=4/5 reciprocal home-advantage threshold")
		_check(bool(aggregate["replicated_signal_pass"]), cell_id + " replicated causal signal passes frozen threshold")
		_check(String(aggregate["cell_aggregate_hash"]).length() == 64, cell_id + " aggregate hashes canonically")

	var dropped := result.duplicate(true)
	var dropped_replicates: Array = Array(dropped["replicates"]).duplicate(true)
	dropped_replicates.remove_at(2)
	dropped["replicates"] = dropped_replicates
	dropped["cell_aggregates"] = [E26._aggregate_cell(dropped_replicates, "DRY"), E26._aggregate_cell(dropped_replicates, "WET")]
	dropped["aggregate_hash"] = E26.compute_aggregate_hash(dropped)
	_check(not E26.validate_result(dropped), "dropping a null/reversal-capable replicate fails closed even after full rehash")

	var reordered := result.duplicate(true)
	var reordered_replicates: Array = Array(reordered["replicates"]).duplicate(true)
	var first = reordered_replicates[0]
	reordered_replicates[0] = reordered_replicates[1]
	reordered_replicates[1] = first
	reordered["replicates"] = reordered_replicates
	reordered["aggregate_hash"] = E26.compute_aggregate_hash(reordered)
	_check(not E26.validate_result(reordered), "post-hoc replicate reordering fails closed after rehash")

	var semantic := result.duplicate(true)
	var semantic_replicates: Array = Array(semantic["replicates"]).duplicate(true)
	var semantic_rep: Dictionary = Dictionary(semantic_replicates[0]).duplicate(true)
	var semantic_cells: Array = Array(semantic_rep["cells"]).duplicate(true)
	var semantic_cell: Dictionary = Dictionary(semantic_cells[0]).duplicate(true)
	semantic_cell["adaptation_gain"] = float(semantic_cell["adaptation_gain"]) + 0.5
	semantic_cell["positive_adaptation_effect"] = true
	semantic_cell["paired_hash"] = E26._paired_hash(semantic_cell)
	semantic_cells[0] = semantic_cell
	semantic_rep["cells"] = semantic_cells
	semantic_rep["replicate_hash"] = E26._replicate_hash(semantic_rep)
	semantic_replicates[0] = semantic_rep
	semantic["replicates"] = semantic_replicates
	semantic["cell_aggregates"] = [E26._aggregate_cell(semantic_replicates, "DRY"), E26._aggregate_cell(semantic_replicates, "WET")]
	semantic["aggregate_hash"] = E26.compute_aggregate_hash(semantic)
	_check(not E26.validate_result(semantic), "fully rehashed effect-size tamper rejected by deterministic replay")

	var significance := result.duplicate(true)
	significance["significance_claimed"] = true
	significance["aggregate_hash"] = E26.compute_aggregate_hash(significance)
	_check(not E26.validate_result(significance), "n=5 significance promotion fails closed after rehash")
	var robustness := result.duplicate(true)
	robustness["cross_seed_robustness_claimed"] = true
	robustness["aggregate_hash"] = E26.compute_aggregate_hash(robustness)
	_check(not E26.validate_result(robustness), "E2.7 robustness promotion fails closed after rehash")
	var extra := result.duplicate(true)
	extra["unexpected"] = true
	_check(not E26.validate_result(extra), "unexpected result field fails closed")

	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_replicated_causal_experiments_v1.gd")
	_check(source.find("MutationKernel.reproduce") >= 0, "replicates reuse accepted deterministic mutation kernel")
	_check(source.find("ResourceModel.evaluate") >= 0, "replicate selection uses accepted causal ResourceModel")
	_check(source.find("R01") >= 0 and source.find("R05") >= 0, "replicate set is literal protocol data, not post-hoc discovery")
	_check(source.find("biome") == -1 and source.find("species_table") == -1, "replication contains no biome-to-species shortcut")
	_check(source.find("fitness_bonus") == -1 and source.find("target_bonus") == -1, "replication contains no hidden target fitness bonus")
	_check(source.find("randi(") == -1 and source.find("randomize(") == -1, "replication does not call global RNG")

	if failed:
		quit(1)
		return
	print("ECO.EVO2 E2.6 Replicated Causal Experiments: PASS (%d assertions)" % assertions)
	print("aggregate_hash=" + String(result["aggregate_hash"]))
	print("replicate_set_hash=" + String(result["replicate_set_hash"]))
	print("parent_e2_5=" + E26.PARENT_E2_5_ACCEPTED_AGGREGATE)
	print("parent_e2_5_head=" + E26.PARENT_E2_5_CODE_UNDER_TEST)
	for cell_id in E26.TARGET_CELLS:
		var aggregate := _aggregate(result, cell_id)
		print("%s_mean_adaptation_gain=%.12f" % [cell_id.to_lower(), float(aggregate["mean_adaptation_gain"])])
		print("%s_positive_count=%d" % [cell_id.to_lower(), int(aggregate["positive_adaptation_count"])])
		print("%s_home_advantage_count=%d" % [cell_id.to_lower(), int(aggregate["home_advantage_count"])])
		print("%s_aggregate_hash=%s" % [cell_id.to_lower(), String(aggregate["cell_aggregate_hash"])])
	for replicate in Array(result["replicates"]):
		print("replicate_%s_hash=%s" % [String(replicate["replicate_id"]).to_lower(), String(replicate["replicate_hash"])])
	quit(0)


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if condition:
		return
	failed = true
	push_error("E2.6 assertion failed: " + label)


func _strategy_checksum(strategies: Array, lineage_id: String) -> String:
	for value in strategies:
		if String(Dictionary(value).get("source_lineage_id", "")) == lineage_id:
			return String(Dictionary(value).get("genome_checksum", ""))
	return ""


func _population_preserves_research_identity(population: Array, strategies: Array) -> bool:
	var allowed_species := {}
	var allowed_lineages := {}
	for value in strategies:
		allowed_species[String(Dictionary(value)["research_species_id"])] = true
		allowed_lineages[String(Dictionary(value)["source_lineage_id"])] = true
	for value in population:
		var entry: Dictionary = value
		if not allowed_species.has(String(entry.get("research_species_id", ""))) or not allowed_lineages.has(String(entry.get("source_lineage_id", ""))):
			return false
		if String(Dictionary(entry["lineage"]).get("lineage_id", "")) != String(entry.get("source_lineage_id", "")):
			return false
	return true


func _aggregate(result: Dictionary, cell_id: String) -> Dictionary:
	for value in Array(result.get("cell_aggregates", [])):
		if String(Dictionary(value).get("cell_id", "")) == cell_id:
			return Dictionary(value)
	return {}


func _aggregate_numbers_match(gains_value: Array, aggregate: Dictionary) -> bool:
	if gains_value.size() != 5:
		return false
	var gains: Array[float] = []
	var total := 0.0
	for value in gains_value:
		gains.append(float(value))
		total += float(value)
	var sorted := gains.duplicate()
	sorted.sort()
	return absf(float(aggregate["mean_adaptation_gain"]) - total / 5.0) <= 0.000000000001 \
		and absf(float(aggregate["median_adaptation_gain"]) - sorted[2]) <= 0.000000000001 \
		and absf(float(aggregate["minimum_adaptation_gain"]) - sorted[0]) <= 0.000000000001 \
		and absf(float(aggregate["maximum_adaptation_gain"]) - sorted[4]) <= 0.000000000001


func _sorted_counts(counts: Dictionary) -> Dictionary:
	var keys: Array[String] = []
	for key in counts.keys(): keys.append(String(key))
	keys.sort()
	var result := {}
	for key in keys: result[key] = int(counts[key])
	return result


func _policies_differ_only_in_mutation_permission(control: Dictionary, treatment: Dictionary) -> bool:
	if control.keys().size() != treatment.keys().size():
		return false
	for key in treatment.keys():
		if String(key) == "mutation_probability":
			continue
		if control[key] != treatment[key]:
			return false
	return true

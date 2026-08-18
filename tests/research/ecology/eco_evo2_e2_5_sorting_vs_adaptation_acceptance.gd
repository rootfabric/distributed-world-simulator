extends SceneTree

const Env = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const Traits = preload("res://scripts/research/ecology/plant_recruitment_traits_v1.gd")
const Divergence = preload("res://scripts/research/ecology/plant_lineage_divergence_diagnostics_v1.gd")
const Bake = preload("res://scripts/research/ecology/plant_evolution_bake_export_v1.gd")
const Matrix = preload("res://scripts/research/ecology/plant_environment_generalization_matrix_v1.gd")
const E25 = preload("res://scripts/research/ecology/plant_sorting_vs_adaptation_v1.gd")

const FINAL_YEAR := 12
const SOURCE_RUN_HASH := "d44a160531d7f49cd0d0018a1fa8cb55d6be8ebf8157e5cb555232b8dd0fb337"

var assertions := 0
var failed := false


func _init() -> void:
	var bake := _accepted_e2_2_bake()
	_check(not bake.is_empty(), "accepted E2.2 bake fixture builds")
	_check(String(bake.get("bake_hash", "")) == "45496eb67aac5cc0a65babfeb0c49fa99616df17c2f7e8b9e8b95d04cb2b4e5b", "exact E2.2 bake pinned")
	_check(String(bake.get("catalog_hash", "")) == "5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219", "exact E2.2 catalog pinned")

	var plan := Matrix.default_plan()
	_check(not plan.is_empty() and Matrix.validate_plan(plan), "accepted E2.4 matrix plan reconstructs")
	_check(String(plan.get("plan_hash", "")) == E25.PARENT_E2_4_PLAN_HASH, "exact accepted E2.4 plan hash pinned")
	var matrix := Matrix.run(bake, plan)
	_check(not matrix.is_empty(), "accepted E2.4 matrix replays")
	_check(Matrix.validate_result(bake, matrix), "accepted E2.4 matrix validates")
	_check(String(matrix.get("matrix_hash", "")) == E25.PARENT_E2_4_ACCEPTED_AGGREGATE, "exact accepted E2.4 aggregate pinned")
	_check(E25.PARENT_E2_4_CODE_UNDER_TEST == "0135aee461a107375cdb3e52e07e8c799145998b", "exact accepted E2.4 code-under-test pinned")

	var bake_before := bake.duplicate(true)
	var matrix_before := matrix.duplicate(true)
	var result := E25.run(bake, matrix)
	_check(not result.is_empty(), "E2.5 paired causal assay executes")
	_check(E25.validate_result(bake, matrix, result), "E2.5 result independently reconstructs and validates")
	_check(bake == bake_before, "E2.5 does not mutate frozen bake/catalog")
	_check(matrix == matrix_before, "E2.5 does not mutate accepted E2.4 evidence")
	_check(String(result["parent_e2_4_accepted_aggregate"]) == E25.PARENT_E2_4_ACCEPTED_AGGREGATE, "E2.5 result carries exact E2.4 aggregate")
	_check(String(result["parent_e2_4_code_under_test"]) == E25.PARENT_E2_4_CODE_UNDER_TEST, "E2.5 result carries exact E2.4 code-under-test")
	_check(String(result["parent_e2_4_plan_hash"]) == E25.PARENT_E2_4_PLAN_HASH, "E2.5 result carries exact E2.4 plan")
	_check(String(result["e2_2_bake_hash"]) == String(bake["bake_hash"]), "E2.5 result preserves exact frozen bake")
	_check(String(result["catalog_hash"]) == String(bake["catalog_hash"]), "E2.5 result preserves exact frozen catalog")
	_check(Array(result["target_cells"]) == ["DRY", "WET"], "E2.5 bounded challenge is DRY/WET only")
	_check(int(result["generations"]) == 10 and int(result["population_size"]) == 8 and int(result["offspring_per_parent"]) == 4, "E2.5 bounded experiment shape pinned")
	_check(not bool(result["full_transfer_continuation_claimed"]), "E2.5 does not claim full transfer continuation")
	_check(not bool(result["canonical_species_declared"]), "E2.5 does not promote canonical species taxonomy")
	_check(not bool(result["production_authority_claimed"]), "E2.5 remains research-only")
	_check(not bool(result["adaptation_creates_canonical_species"]), "adapted descendants remain within research lineage hypotheses")

	var catalog: Dictionary = bake["species_catalog"]
	var frozen_species := _catalog_species_ids(catalog)
	var frozen_genomes := _catalog_genome_checksums(catalog)
	_check(Array(result["frozen_species_ids"]) == frozen_species, "starting research species identities exactly equal frozen catalog")
	_check(Array(result["frozen_genome_checksums"]) == frozen_genomes, "starting genome identities exactly equal frozen catalog")
	_check(frozen_species.size() == 2 and frozen_genomes.size() == 2, "accepted E2.2 fixture exposes exactly two retained strategies")

	var control_policy := E25.control_policy()
	var treatment_policy := E25.treatment_policy()
	_check(float(control_policy["mutation_probability"]) == 0.0, "Control hard-disables mutation")
	_check(float(treatment_policy["mutation_probability"]) > 0.0, "Treatment enables bounded mutation")
	_check(_policies_differ_only_in_mutation_permission(control_policy, treatment_policy), "Control/Treatment policy differs only by mutation permission")
	_check(String(result["control_policy_hash"]) != String(result["treatment_policy_hash"]), "causal treatment policy identity differs explicitly")

	var dry := _cell(result, "DRY")
	var wet := _cell(result, "WET")
	_check(not dry.is_empty() and not wet.is_empty(), "DRY and WET paired cells present")
	var dry_control: Dictionary = dry["control"]
	var dry_treatment: Dictionary = dry["treatment"]
	var wet_control: Dictionary = wet["control"]
	var wet_treatment: Dictionary = wet["treatment"]

	for pair in [[dry, dry_control, dry_treatment, "DRY"], [wet, wet_control, wet_treatment, "WET"]]:
		var cell: Dictionary = pair[0]
		var control: Dictionary = pair[1]
		var treatment: Dictionary = pair[2]
		var label := String(pair[3])
		_check(String(control["initial"]["population_hash"]) == String(treatment["initial"]["population_hash"]), label + " arms start from exact same population")
		_check(Dictionary(control["initial"]["lineage_counts"]) == Dictionary(treatment["initial"]["lineage_counts"]), label + " arms start from exact same lineage abundances")
		_check(String(cell["initial_population_hash"]) == String(control["initial"]["population_hash"]), label + " paired record binds common initial state")
		_check(not bool(control["adaptation_enabled"]) and bool(treatment["adaptation_enabled"]), label + " only Treatment enables adaptation")
		_check(Array(control["selected_mutation_events"]).is_empty(), label + " Control has no selected mutation events")
		_check(int(control["final"]["novel_genome_count"]) == 0, label + " Control remains genetically frozen")
		_check(_population_genomes_are_frozen(Array(control["final_population"]), frozen_genomes), label + " Control final genomes remain frozen catalog genomes")
		_check(bool(cell["sorting_detected"]), label + " Control exhibits ecological sorting")
		_check(Dictionary(control["final"]["lineage_counts"]) != Dictionary(control["initial"]["lineage_counts"]), label + " sorting changes frozen lineage abundance")
		_check(float(cell["sorting_gain"]) > 0.0, label + " sorting improves resource balance without genetic change")
		_check(not Array(treatment["selected_mutation_events"]).is_empty(), label + " Treatment selects inherited mutation events")
		_check(int(treatment["final"]["novel_genome_count"]) > 0, label + " Treatment contains novel descendant genomes")
		_check(_adapted_population_preserves_research_identity(Array(treatment["final_population"]), frozen_species), label + " adapted descendants preserve frozen research species/lineage identity")
		_check(_events_preserve_research_identity(Array(treatment["selected_mutation_events"]), frozen_species), label + " mutation evidence stays bound to frozen research identities")
		_check(bool(cell["adaptation_detected"]), label + " adaptation requires novel genomes plus measurable advantage")
		_check(float(cell["adaptation_gain"]) > 0.0, label + " Treatment has measurable advantage beyond sorting Control")
		_check(String(cell["classification"]) == "ADAPTATION_DETECTED", label + " causal classification is ADAPTATION_DETECTED")
		_check(String(cell["paired_hash"]).length() == 64, label + " paired causal evidence hashes canonically")

	var dry_winner := _single_winner_species(dry_control)
	var wet_winner := _single_winner_species(wet_control)
	_check(not dry_winner.is_empty() and not wet_winner.is_empty(), "Control sorting converges to a single frozen strategy in both challenges")
	_check(dry_winner != wet_winner, "DRY and WET sorting select different pre-existing frozen strategies")
	_check(dry_winner == _species_for_lineage(catalog, "eco-lineage/e22-alpha"), "DRY sorting selects frozen alpha strategy")
	_check(wet_winner == _species_for_lineage(catalog, "eco-lineage/e22-beta"), "WET sorting selects frozen beta strategy")

	_check(float(dry_treatment["final"]["trait_means"]["water_preference"]) < float(dry_control["final"]["trait_means"]["water_preference"]), "DRY adaptation shifts water preference downward from sorted frozen state")
	_check(float(wet_treatment["final"]["trait_means"]["water_preference"]) > float(wet_control["final"]["trait_means"]["water_preference"]), "WET adaptation shifts water preference upward from sorted frozen state")

	var cross: Dictionary = result["cross_environment"]
	_check(float(cross["DRY"]["DRY"]) > float(cross["WET"]["DRY"]), "dry-adapted population outperforms wet-adapted population in DRY environment")
	_check(float(cross["WET"]["WET"]) > float(cross["DRY"]["WET"]), "wet-adapted population outperforms dry-adapted population in WET environment")
	_check(float(cross["DRY"]["DRY"]) > float(dry_control["final"]["average_net_resource_balance"]), "DRY home-adapted population exceeds frozen sorting Control")
	_check(float(cross["WET"]["WET"]) > float(wet_control["final"]["average_net_resource_balance"]), "WET home-adapted population exceeds frozen sorting Control")

	var repeat := E25.run(bake, matrix)
	_check(repeat == result, "same-process E2.5 assay is exactly deterministic")
	_check(String(repeat["aggregate_hash"]) == String(result["aggregate_hash"]), "same-process E2.5 aggregate stable")

	seed(25052505)
	var expected_rng := [randi(), randi(), randi(), randi()]
	seed(25052505)
	E25.run(bake, matrix)
	var actual_rng := [randi(), randi(), randi(), randi()]
	_check(actual_rng == expected_rng, "E2.5 consumes no global RNG")

	var tampered_matrix := matrix.duplicate(true)
	tampered_matrix["matrix_hash"] = "0".repeat(64)
	_check(E25.run(bake, tampered_matrix).is_empty(), "tampered E2.4 parent matrix fails closed")
	var tampered_bake := bake.duplicate(true)
	tampered_bake["bake_hash"] = "0".repeat(64)
	_check(E25.run(tampered_bake, matrix).is_empty(), "tampered frozen bake fails closed")
	var tampered_catalog_bake := bake.duplicate(true)
	var tampered_catalog: Dictionary = Dictionary(tampered_catalog_bake["species_catalog"]).duplicate(true)
	tampered_catalog["catalog_hash"] = "0".repeat(64)
	tampered_catalog_bake["species_catalog"] = tampered_catalog
	_check(E25.run(tampered_catalog_bake, matrix).is_empty(), "tampered frozen catalog fails closed")

	var semantic_tamper := result.duplicate(true)
	var semantic_cross: Dictionary = Dictionary(semantic_tamper["cross_environment"]).duplicate(true)
	var semantic_row: Dictionary = Dictionary(semantic_cross["DRY"]).duplicate(true)
	semantic_row["DRY"] = float(semantic_row["DRY"]) + 0.25
	semantic_cross["DRY"] = semantic_row
	semantic_tamper["cross_environment"] = semantic_cross
	semantic_tamper["aggregate_hash"] = E25.compute_aggregate_hash(semantic_tamper)
	_check(not E25.validate_result(bake, matrix, semantic_tamper), "fully rehashed cross-environment semantic tamper rejected by deterministic replay")

	var event_tamper := result.duplicate(true)
	var tamper_cells: Array = Array(event_tamper["cells"]).duplicate(true)
	var tamper_cell: Dictionary = Dictionary(tamper_cells[0]).duplicate(true)
	var tamper_treatment: Dictionary = Dictionary(tamper_cell["treatment"]).duplicate(true)
	var tamper_events: Array = Array(tamper_treatment["selected_mutation_events"]).duplicate(true)
	var tamper_event: Dictionary = Dictionary(tamper_events[0]).duplicate(true)
	tamper_event["mutation_count"] = int(tamper_event["mutation_count"]) + 1
	tamper_events[0] = tamper_event
	tamper_treatment["selected_mutation_events"] = tamper_events
	tamper_treatment["arm_hash"] = E25._arm_hash(tamper_treatment)
	tamper_cell["treatment"] = tamper_treatment
	tamper_cell["paired_hash"] = E25._paired_hash(tamper_cell)
	tamper_cells[0] = tamper_cell
	event_tamper["cells"] = tamper_cells
	event_tamper["aggregate_hash"] = E25.compute_aggregate_hash(event_tamper)
	_check(not E25.validate_result(bake, matrix, event_tamper), "fully rehashed selected-mutation semantic tamper rejected by deterministic replay")

	var extra_field := result.duplicate(true)
	extra_field["unexpected"] = true
	_check(not E25.validate_result(bake, matrix, extra_field), "unexpected result field fails closed")
	var identity_tamper := result.duplicate(true)
	identity_tamper["canonical_species_declared"] = true
	identity_tamper["aggregate_hash"] = E25.compute_aggregate_hash(identity_tamper)
	_check(not E25.validate_result(bake, matrix, identity_tamper), "canonical taxonomy promotion fails closed even after rehash")

	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_sorting_vs_adaptation_v1.gd")
	_check(source.find("MutationKernel.reproduce") >= 0, "Treatment reuses accepted deterministic mutation/lineage kernel")
	_check(source.find("ResourceModel.evaluate") >= 0, "selection consequence comes from accepted causal ResourceModel")
	_check(source.find("biome") == -1 and source.find("species_table") == -1, "E2.5 has no biome-to-species shortcut")
	_check(source.find("target_bonus") == -1 and source.find("fitness_bonus") == -1, "E2.5 has no hand-written target fitness bonus")
	_check(source.find("static func treatment_policy()") >= 0 and source.find("environment: Dictionary") > source.find("static func treatment_policy()"), "treatment policy is fixed before environment-specific evaluation")

	if failed:
		quit(1)
		return
	print("ECO.EVO2 E2.5 Ecological Sorting vs Continued Adaptation: PASS (%d assertions)" % assertions)
	print("aggregate_hash=" + String(result["aggregate_hash"]))
	print("parent_e2_4=" + E25.PARENT_E2_4_ACCEPTED_AGGREGATE)
	print("parent_e2_4_head=" + E25.PARENT_E2_4_CODE_UNDER_TEST)
	print("parent_e2_4_plan=" + E25.PARENT_E2_4_PLAN_HASH)
	print("bake_hash=" + String(result["e2_2_bake_hash"]))
	print("catalog_hash=" + String(result["catalog_hash"]))
	print("control_policy_hash=" + String(result["control_policy_hash"]))
	print("treatment_policy_hash=" + String(result["treatment_policy_hash"]))
	for cell_id in ["DRY", "WET"]:
		var cell := _cell(result, cell_id)
		print("cell_%s_hash=%s" % [cell_id.to_lower(), String(cell["paired_hash"])])
		print("%s_classification=%s" % [cell_id.to_lower(), String(cell["classification"])])
		print("%s_sorting_gain=%.12f" % [cell_id.to_lower(), float(cell["sorting_gain"])])
		print("%s_adaptation_gain=%.12f" % [cell_id.to_lower(), float(cell["adaptation_gain"])])
	print("cross_dry_home=%.12f" % float(cross["DRY"]["DRY"]))
	print("cross_dry_away=%.12f" % float(cross["WET"]["DRY"]))
	print("cross_wet_home=%.12f" % float(cross["WET"]["WET"]))
	print("cross_wet_away=%.12f" % float(cross["DRY"]["WET"]))
	quit(0)


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if condition:
		return
	failed = true
	push_error("E2.5 assertion failed: " + label)


func _cell(result: Dictionary, cell_id: String) -> Dictionary:
	for value in Array(result.get("cells", [])):
		if typeof(value) == TYPE_DICTIONARY and String(Dictionary(value).get("cell_id", "")) == cell_id:
			return Dictionary(value)
	return {}


func _catalog_species_ids(catalog: Dictionary) -> Array[String]:
	var values: Array[String] = []
	for entry in Array(catalog.get("entries", [])):
		values.append(String(Dictionary(entry).get("research_species_id", "")))
	values.sort()
	return values


func _catalog_genome_checksums(catalog: Dictionary) -> Array[String]:
	var values: Array[String] = []
	for entry in Array(catalog.get("entries", [])):
		values.append(String(Dictionary(entry).get("genome_checksum", "")))
	values.sort()
	return values


func _species_for_lineage(catalog: Dictionary, lineage_id: String) -> String:
	for entry in Array(catalog.get("entries", [])):
		if String(Dictionary(entry).get("lineage_id", "")) == lineage_id:
			return String(Dictionary(entry).get("research_species_id", ""))
	return ""


func _single_winner_species(arm: Dictionary) -> String:
	var counts: Dictionary = Dictionary(arm["final"]["lineage_counts"])
	if counts.size() != 1:
		return ""
	return String(counts.keys()[0])


func _population_genomes_are_frozen(population: Array, frozen_genomes: Array[String]) -> bool:
	for value in population:
		if not String(Dictionary(Dictionary(value)["genome"])["checksum"]) in frozen_genomes:
			return false
	return true


func _adapted_population_preserves_research_identity(population: Array, frozen_species: Array[String]) -> bool:
	for value in population:
		var entry: Dictionary = value
		if not String(entry.get("research_species_id", "")) in frozen_species:
			return false
		if String(Dictionary(entry["lineage"]).get("lineage_id", "")) != String(entry.get("source_lineage_id", "")):
			return false
	return true


func _events_preserve_research_identity(events: Array, frozen_species: Array[String]) -> bool:
	for value in events:
		var event: Dictionary = value
		if not String(event.get("research_species_id", "")) in frozen_species:
			return false
		if not String(event.get("source_lineage_id", "")).begins_with("eco-lineage/"):
			return false
	return true


func _policies_differ_only_in_mutation_permission(control: Dictionary, treatment: Dictionary) -> bool:
	if control.keys().size() != treatment.keys().size():
		return false
	for key in treatment.keys():
		if String(key) == "mutation_probability":
			continue
		if control[key] != treatment[key]:
			return false
	return true


func _accepted_e2_2_bake() -> Dictionary:
	var ga0 := Genome.create("genome/e22-alpha-early", 1.2, 0.48, 1.4, 0.38, 0.22, 0.62, 140, 14.0, 8.0)
	var ga1 := Genome.create("genome/e22-alpha-late", 1.5, 0.54, 1.7, 0.34, 0.25, 0.65, 130, 16.0, 8.5)
	var gb := Genome.create("genome/e22-beta", 0.8, 0.72, 0.6, 0.70, 0.28, 0.28, 360, 28.0, 3.0)
	var go := Genome.create("genome/e22-other", 2.3, 0.60, 2.2, 0.50, 0.32, 0.48, 180, 20.0, 10.0)
	var ta := Traits.create("recruit/e22-alpha", 0.38, 4.5)
	var tb := Traits.create("recruit/e22-beta", 0.18, 1.8)
	var to := Traits.create("recruit/e22-other", 0.30, 3.0)
	var rows := [
		_lineage("eco-lineage/e22-alpha", [_obs("eco-lineage/e22-alpha", ["eco-lineage/e22-root", "eco-lineage/e22-alpha"], 2, 12, ga1, ta, "patch/alpha"), _obs("eco-lineage/e22-alpha", ["eco-lineage/e22-root", "eco-lineage/e22-alpha"], 2, 8, ga0, ta, "patch/alpha")], [1, 2, 2, 2, 3, 3, 3, 4]),
		_lineage("eco-lineage/e22-beta", [_obs("eco-lineage/e22-beta", ["eco-lineage/e22-root", "eco-lineage/e22-beta"], 1, 12, gb, tb, "patch/beta")], [0, 1, 1, 1, 1, 2, 2, 2]),
		_lineage("eco-lineage/e22-extinct", [_obs("eco-lineage/e22-extinct", ["eco-lineage/e22-root", "eco-lineage/e22-extinct"], 1, 12, go, to, "patch/extinct")], [1, 1, 1, 1, 1, 1, 1, 0]),
		_lineage("eco-lineage/e22-transient", [_obs("eco-lineage/e22-transient", ["eco-lineage/e22-root", "eco-lineage/e22-transient"], 1, 12, go, to, "patch/transient")], [0, 0, 0, 1, 0, 1, 1, 1]),
		_lineage("eco-lineage/e22-recent", [_obs("eco-lineage/e22-recent", ["eco-lineage/e22-root", "eco-lineage/e22-recent"], 8, 12, go, to, "patch/recent")], [0, 0, 0, 0, 1, 1, 1, 1]),
		_lineage("eco-lineage/e22-stale", [_obs("eco-lineage/e22-stale", ["eco-lineage/e22-root", "eco-lineage/e22-stale"], 1, 9, go, to, "patch/stale")], [1, 1, 1, 1, 1, 1, 1, 1]),
	]
	var source := Bake.create_source(rows, FINAL_YEAR, SOURCE_RUN_HASH)
	return Bake.export_catalog(source) if not source.is_empty() else {}


func _lineage(id: String, observations: Array, counts: Array) -> Dictionary:
	var history: Array = []
	var start := FINAL_YEAR - Bake.WINDOW_YEARS + 1
	for index in range(counts.size()):
		history.append({"year": start + index, "occupied_patch_count": int(counts[index])})
	return {"lineage_id": id, "observations": observations.duplicate(true), "occupancy_history": history}


func _obs(id: String, ancestry: Array, split: int, end: int, genome: Dictionary, traits: Dictionary, patch: String) -> Dictionary:
	var geography: Array = []
	var ecology: Array = []
	for year in range(split + 1, end + 1):
		geography.append({"year": year, "patch_ids": [patch]})
		ecology.append({"year": year, "environment": Env.create(float(year), float(-year), 10.0 + float(year) * 0.2, 0.45, 0.75, 0.62, 0.02, 22000 + year, "e22-fixture")})
	return Divergence.create_observation(id, ancestry, split, genome, traits, geography, ecology)

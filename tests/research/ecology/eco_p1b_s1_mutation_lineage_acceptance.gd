extends SceneTree

const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const LineageRecord = preload("res://scripts/research/ecology/plant_lineage_record_v1.gd")
const Kernel = preload("res://scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd")

const ANCESTOR_LINEAGE_SEED := 4701001
const MUTATION_SEED := 4702001
const POPULATION_SIZE := 256
const CHAIN_GENERATIONS := 160
const EXPECTED_ANCESTOR_LINEAGE_HASH := "73621a2c49d6496bb89faef63a8350f2a76b553fd718fa88d1bc6b21b83a230f"
const EXPECTED_POPULATION_HASH := "83a114cd712aacac42e0a1b4d74c0876a441fadb019f6640bfd44c921778ce84"
const EXPECTED_CHAIN_HASH := "3792cf995265b622ab8817a973f0bd38aedab8ca34721ca9468178e6e1a35874"

var assertions := 0
var failures: Array[String] = []
var ancestor_genome: Dictionary = {}
var ancestor_lineage: Dictionary = {}
var population_hash := ""
var chain_hash := ""


func _init() -> void:
	_test_policy_and_contract_boundaries()
	_test_ancestor_identity()
	_test_reproduction_replay()
	_test_zero_and_full_mutation_policies()
	_test_population_mutation_distribution()
	_test_multigeneration_lineage_chain()
	_finish()


func _test_policy_and_contract_boundaries() -> void:
	var policy := Kernel.default_policy()
	_check(bool(Kernel.validate_policy(policy).get("success", false)), "default mutation policy validates")
	_check(policy.keys().size() == Kernel.POLICY_KEYS.size(), "mutation policy exact field count")
	_check(Kernel.MUTABLE_TRAITS == ["water_preference", "root_depth_m", "growth_rate", "shade_tolerance", "seed_dispersal_distance_m"], "P1B-S1 mutable trait set matches EXP-V2")
	_check(String(Kernel.EXPERIMENT_REVISION) == "ECO.P1B-S1.1", "P1B-S1 experiment revision fixed")
	_check(Kernel.policy_hash(policy).length() == 64, "policy hash shape")
	for key in Kernel.POLICY_KEYS:
		_check(policy.has(key), "policy contains %s" % key)
	var invalid_probability := policy.duplicate(true)
	invalid_probability["mutation_probability"] = 1.01
	_check(not bool(Kernel.validate_policy(invalid_probability).get("success", false)), "mutation probability above one rejected")
	var invalid_step := policy.duplicate(true)
	invalid_step["root_depth_m_step"] = -0.1
	_check(not bool(Kernel.validate_policy(invalid_step).get("success", false)), "negative mutation step rejected")

	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_lineage_record_v1.gd")
	source += FileAccess.get_file_as_string("res://scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd")
	for forbidden in ["biome_id", "biome ==", "DESERT_PLANT", "RIVER_PLANT", "FOREST_TREE", "species_id", "species_class"]:
		_check(source.find(forbidden) < 0, "mutation/lineage kernel excludes predefined species/biome rule: %s" % forbidden)
	for forbidden in ["Camera3D", "CanvasLayer", "presentation_lod", "surface_cell_key", "AuthorityRegion", "ENetMultiplayerPeer"]:
		_check(source.find(forbidden) < 0, "mutation/lineage kernel excludes presentation/authority input: %s" % forbidden)


func _test_ancestor_identity() -> void:
	ancestor_genome = PlantGenome.create_default()
	_check(bool(PlantGenome.validate(ancestor_genome).get("success", false)), "accepted P1A ancestor genome validates")
	ancestor_lineage = Kernel.create_ancestor(ancestor_genome, ANCESTOR_LINEAGE_SEED)
	var replay := Kernel.create_ancestor(ancestor_genome, ANCESTOR_LINEAGE_SEED)
	_check(not ancestor_lineage.is_empty(), "ancestor lineage builds")
	_check(bool(LineageRecord.validate(ancestor_lineage).get("success", false)), "ancestor lineage validates")
	_check(String(ancestor_lineage["checksum"]) == String(replay["checksum"]), "ancestor lineage deterministic")
	_check(String(ancestor_lineage["lineage_id"]) == String(replay["lineage_id"]), "ancestor lineage id deterministic")
	_check(String(ancestor_lineage["individual_id"]) == String(replay["individual_id"]), "ancestor individual id deterministic")
	_check(int(ancestor_lineage["generation"]) == 0, "ancestor generation zero")
	_check(String(ancestor_lineage["parent_individual_id"]).is_empty(), "ancestor has no parent individual")
	_check(String(ancestor_lineage["parent_genome_checksum"]).is_empty(), "ancestor has no parent genome")
	_check(String(ancestor_lineage["genome_checksum"]) == String(ancestor_genome["checksum"]), "ancestor record binds accepted genome")
	if EXPECTED_ANCESTOR_LINEAGE_HASH != "PENDING":
		_check(String(ancestor_lineage["checksum"]) == EXPECTED_ANCESTOR_LINEAGE_HASH, "ancestor lineage fixed hash")


func _test_reproduction_replay() -> void:
	var child_a := Kernel.reproduce(ancestor_genome, ancestor_lineage, MUTATION_SEED, 7)
	var child_b := Kernel.reproduce(ancestor_genome, ancestor_lineage, MUTATION_SEED, 7)
	_check(not child_a.is_empty(), "deterministic child builds")
	_check(bool(Kernel.validate_result(child_a).get("success", false)), "deterministic child result validates")
	_check(String(child_a["result_hash"]) == String(child_b["result_hash"]), "same inputs reproduce exact child result hash")
	_check(String(child_a["child_genome_checksum"]) == String(child_b["child_genome_checksum"]), "same inputs reproduce exact genotype")
	_check(String(child_a["child_lineage_checksum"]) == String(child_b["child_lineage_checksum"]), "same inputs reproduce exact lineage record")
	_check(String(child_a["mutation_event_hash"]) == String(child_b["mutation_event_hash"]), "same inputs reproduce exact mutation event hash")
	_check(int(child_a["lineage"]["generation"]) == 1, "child generation increments")
	_check(String(child_a["lineage"]["parent_individual_id"]) == String(ancestor_lineage["individual_id"]), "child provenance points to exact parent")
	_check(String(child_a["lineage"]["lineage_id"]) == String(ancestor_lineage["lineage_id"]), "child remains in ancestor lineage")
	_check(String(child_a["parent_genome_checksum"]) == String(ancestor_genome["checksum"]), "child result records parent genotype")

	var sibling := Kernel.reproduce(ancestor_genome, ancestor_lineage, MUTATION_SEED, 8)
	var alternate_seed := Kernel.reproduce(ancestor_genome, ancestor_lineage, MUTATION_SEED + 1, 7)
	_check(String(child_a["result_hash"]) != String(sibling["result_hash"]), "offspring index changes deterministic event stream")
	_check(String(child_a["child_lineage_checksum"]) != String(sibling["child_lineage_checksum"]), "siblings have distinct individual provenance")
	_check(String(child_a["result_hash"]) != String(alternate_seed["result_hash"]), "mutation seed changes deterministic event stream")


func _test_zero_and_full_mutation_policies() -> void:
	var zero_policy := Kernel.default_policy()
	zero_policy["mutation_probability"] = 0.0
	var unchanged := Kernel.reproduce(ancestor_genome, ancestor_lineage, 1001, 0, zero_policy)
	_check(bool(Kernel.validate_result(unchanged).get("success", false)), "zero-mutation child validates")
	_check(int(unchanged["mutation_count"]) == 0, "zero probability produces no trait mutation")
	_check(String(unchanged["child_genome_checksum"]) == String(ancestor_genome["checksum"]), "no mutation preserves genotype checksum")
	_check(String(unchanged["genome"]["genome_id"]) == String(ancestor_genome["genome_id"]), "no mutation preserves genotype id")
	_check(String(unchanged["lineage"]["individual_id"]) != String(ancestor_lineage["individual_id"]), "new individual identity exists without new genotype")
	_check(String(unchanged["lineage"]["genome_checksum"]) == String(ancestor_genome["checksum"]), "lineage record can point to inherited unchanged genotype")
	for raw_event in Array(unchanged["events"]):
		var event: Dictionary = raw_event
		_check(not bool(event["mutated"]), "zero probability event not mutated: %s" % String(event["trait"]))
		_check(_approx(float(event["delta"]), 0.0), "zero probability delta zero: %s" % String(event["trait"]))

	var full_policy := Kernel.default_policy()
	full_policy["mutation_probability"] = 1.0
	var fully_mutated := Kernel.reproduce(ancestor_genome, ancestor_lineage, 2002, 0, full_policy)
	_check(bool(Kernel.validate_result(fully_mutated).get("success", false)), "full-mutation child validates")
	_check(int(fully_mutated["mutation_count"]) == Kernel.MUTABLE_TRAITS.size(), "probability one mutates all configured traits")
	_check(String(fully_mutated["child_genome_checksum"]) != String(ancestor_genome["checksum"]), "mutated genotype checksum differs")
	for raw_event in Array(fully_mutated["events"]):
		var event: Dictionary = raw_event
		_check(bool(event["mutated"]), "full probability event mutated: %s" % String(event["trait"]))
	_assert_nonmutable_traits_equal(ancestor_genome, fully_mutated["genome"], "full mutation")


func _test_population_mutation_distribution() -> void:
	var policy := Kernel.default_policy()
	var results: Array = []
	var replay_results: Array = []
	var mutation_counts := {}
	var positive_counts := {}
	var negative_counts := {}
	for trait_name in Kernel.MUTABLE_TRAITS:
		mutation_counts[trait_name] = 0
		positive_counts[trait_name] = 0
		negative_counts[trait_name] = 0
	var individual_ids := {}
	var unchanged_genotype_count := 0
	var mutated_genotype_count := 0
	for offspring_index in range(POPULATION_SIZE):
		var result := Kernel.reproduce(ancestor_genome, ancestor_lineage, MUTATION_SEED, offspring_index, policy)
		var replay := Kernel.reproduce(ancestor_genome, ancestor_lineage, MUTATION_SEED, offspring_index, policy)
		results.append(result)
		replay_results.append(replay)
		_check(bool(Kernel.validate_result(result).get("success", false)), "population child validates %d" % offspring_index)
		_check(String(result["result_hash"]) == String(replay["result_hash"]), "population child replay exact %d" % offspring_index)
		var individual_id := String(result["lineage"]["individual_id"])
		_check(not individual_ids.has(individual_id), "population individual id unique %d" % offspring_index)
		individual_ids[individual_id] = true
		_check(String(result["lineage"]["lineage_id"]) == String(ancestor_lineage["lineage_id"]), "population retains one ancestral lineage %d" % offspring_index)
		_assert_nonmutable_traits_equal(ancestor_genome, result["genome"], "population child %d" % offspring_index)
		if String(result["child_genome_checksum"]) == String(ancestor_genome["checksum"]):
			unchanged_genotype_count += 1
		else:
			mutated_genotype_count += 1
		for raw_event in Array(result["events"]):
			var event: Dictionary = raw_event
			var event_trait := String(event["trait"])
			var step := float(policy[Kernel.TRAIT_STEP_KEY[event_trait]])
			var delta := float(event["delta"])
			var after := float(event["after"])
			_check(absf(delta) <= step + 0.000000001, "mutation delta bounded %s child %d" % [event_trait, offspring_index])
			_check(after >= float(Kernel.TRAIT_MIN[event_trait]) - 0.000000001 and after <= float(Kernel.TRAIT_MAX[event_trait]) + 0.000000001, "mutated trait remains biological range %s child %d" % [event_trait, offspring_index])
			if bool(event["mutated"]):
				mutation_counts[event_trait] = int(mutation_counts[event_trait]) + 1
				if delta > 0.0:
					positive_counts[event_trait] = int(positive_counts[event_trait]) + 1
				elif delta < 0.0:
					negative_counts[event_trait] = int(negative_counts[event_trait]) + 1

	population_hash = Kernel.population_hash(results)
	var replay_hash := Kernel.population_hash(replay_results)
	_check(population_hash.length() == 64, "population hash shape")
	_check(population_hash == replay_hash, "whole sibling population replay exact")
	if EXPECTED_POPULATION_HASH != "PENDING":
		_check(population_hash == EXPECTED_POPULATION_HASH, "population fixed hash")
	_check(unchanged_genotype_count > 0, "default mutation probability leaves some inherited genotypes unchanged")
	_check(mutated_genotype_count > POPULATION_SIZE / 2, "default policy produces substantial mutated offspring")
	_check(individual_ids.size() == POPULATION_SIZE, "all sibling individuals unique")
	for trait_name in Kernel.MUTABLE_TRAITS:
		_check(int(mutation_counts[trait_name]) > 70, "trait mutates often enough for selection experiment: %s" % trait_name)
		_check(int(positive_counts[trait_name]) > 20, "trait explores positive direction: %s" % trait_name)
		_check(int(negative_counts[trait_name]) > 20, "trait explores negative direction: %s" % trait_name)
	print("ECO.P1B-S1 mutation_counts=%s positive=%s negative=%s unchanged_genotypes=%d mutated_genotypes=%d" % [str(mutation_counts), str(positive_counts), str(negative_counts), unchanged_genotype_count, mutated_genotype_count])


func _test_multigeneration_lineage_chain() -> void:
	var current_genome := ancestor_genome
	var current_lineage := ancestor_lineage
	var chain_results: Array = []
	var seen_individuals := {String(ancestor_lineage["individual_id"]): true}
	for generation_index in range(CHAIN_GENERATIONS):
		var parent_id := String(current_lineage["individual_id"])
		var result := Kernel.reproduce(current_genome, current_lineage, MUTATION_SEED + generation_index * 17, generation_index % 11)
		_check(bool(Kernel.validate_result(result).get("success", false)), "chain result validates generation %d" % (generation_index + 1))
		_check(bool(PlantGenome.validate(result["genome"]).get("success", false)), "chain genome validates generation %d" % (generation_index + 1))
		_check(bool(LineageRecord.validate(result["lineage"]).get("success", false)), "chain lineage validates generation %d" % (generation_index + 1))
		_check(int(result["lineage"]["generation"]) == generation_index + 1, "chain generation monotonic %d" % (generation_index + 1))
		_check(String(result["lineage"]["parent_individual_id"]) == parent_id, "chain parent pointer exact generation %d" % (generation_index + 1))
		_check(String(result["lineage"]["lineage_id"]) == String(ancestor_lineage["lineage_id"]), "chain retains ancestor lineage generation %d" % (generation_index + 1))
		var individual_id := String(result["lineage"]["individual_id"])
		_check(not seen_individuals.has(individual_id), "chain individual id never repeats generation %d" % (generation_index + 1))
		seen_individuals[individual_id] = true
		chain_results.append(result)
		current_genome = result["genome"]
		current_lineage = result["lineage"]

	chain_hash = Kernel.population_hash(chain_results)
	_check(chain_hash.length() == 64, "multigeneration chain hash shape")
	if EXPECTED_CHAIN_HASH != "PENDING":
		_check(chain_hash == EXPECTED_CHAIN_HASH, "multigeneration fixed chain hash")
	var changed_traits := 0
	for trait_name in Kernel.MUTABLE_TRAITS:
		if not _approx(float(current_genome[trait_name]), float(ancestor_genome[trait_name])):
			changed_traits += 1
	_check(changed_traits >= 3, "long lineage explores multiple ecological traits")
	_check(seen_individuals.size() == CHAIN_GENERATIONS + 1, "chain provenance unique for all generations")

	var replay_genome := ancestor_genome
	var replay_lineage := ancestor_lineage
	var replay_results: Array = []
	for generation_index in range(CHAIN_GENERATIONS):
		var replay := Kernel.reproduce(replay_genome, replay_lineage, MUTATION_SEED + generation_index * 17, generation_index % 11)
		replay_results.append(replay)
		replay_genome = replay["genome"]
		replay_lineage = replay["lineage"]
	_check(Kernel.population_hash(replay_results) == chain_hash, "full multigeneration lineage replay exact")
	_check(String(replay_lineage["checksum"]) == String(current_lineage["checksum"]), "final lineage record replay exact")
	_check(String(replay_genome["checksum"]) == String(current_genome["checksum"]), "final genotype replay exact")


func _assert_nonmutable_traits_equal(parent: Dictionary, child: Dictionary, label: String) -> void:
	for trait_name in ["height_m", "water_tolerance_width", "seed_count", "lifespan_years"]:
		if trait_name == "seed_count":
			_check(int(parent[trait_name]) == int(child[trait_name]), "%s keeps nonmutable %s" % [label, trait_name])
		else:
			_check(_approx(float(parent[trait_name]), float(child[trait_name])), "%s keeps nonmutable %s" % [label, trait_name])


func _approx(a: float, b: float, tolerance: float = 0.000000001) -> bool:
	return absf(a - b) <= tolerance


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)


func _finish() -> void:
	print("ECO.P1B-S1 ancestor_lineage_hash=%s" % String(ancestor_lineage.get("checksum", "")))
	print("ECO.P1B-S1 population_hash=%s" % population_hash)
	print("ECO.P1B-S1 chain_hash=%s" % chain_hash)
	if failures.is_empty():
		print("ECO.P1B-S1 Mutation/Inheritance/Lineage: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.P1B-S1 FAIL: %s" % failure)
	print("ECO.P1B-S1 Mutation/Inheritance/Lineage: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)

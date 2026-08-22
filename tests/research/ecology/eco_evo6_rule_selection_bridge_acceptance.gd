extends SceneTree

const Bridge = preload("res://scripts/research/ecology/evo6_rule_selection_bridge_v1.gd")
const MutationKernel = preload("res://scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var artifact := Bridge.load_artifact()
	_check(not artifact.is_empty(), "generated outcome artifact loads")
	_check(Bridge.validate_artifact(artifact), "generated outcome artifact validates")
	_check(
		bool(MutationKernel.validate_policy(Bridge.default_mutation_policy()).get("success", false)),
		"bridge mutation policy is accepted by P1B kernel"
	)
	var first := Bridge.run(artifact)
	var replay := Bridge.run(artifact)
	var alt_seed := Bridge.run(artifact, Bridge.DEFAULT_LINEAGE_SEED + 1)
	_check(not first.is_empty(), "rule selection bridge builds")
	_check(
		String(first.get("result_hash", "")) == String(replay.get("result_hash", "")),
		"same seed replay is deterministic"
	)
	_check(
		String(first.get("result_hash", "")) != String(alt_seed.get("result_hash", "")),
		"different lineage seed changes evolved result"
	)
	var metrics: Dictionary = first["metrics"]
	_check(bool(metrics["population_conserved"]), "population size conserved")
	_check(bool(metrics["common_first_candidate_pool"]), "all sites receive the same generation-one mutation pool")
	_check(int(metrics["mutation_events_observed"]) > 0, "existing P1B mutation kernel produced mutations")
	_check(bool(metrics["diversity_preserved"]), "anti-collapse diversity gate passes")
	_check(int(metrics["unique_genomes"]) > 1, "more than one final genome remains")
	_check(float(metrics["largest_genome_share"]) < 1.0, "no single genome owns all final populations")
	_check(float(metrics["max_trait_variance"]) > 0.0, "mutable trait variance survives selection")

	# Counterfactual causality gate: keep lineage seed and generation-one mutation
	# candidates identical, alter only EVO6 fitness surfaces, and require at least
	# one actually selected final population to change. Comparing result_hash alone
	# would be insufficient because it also includes selection_surface_digest.
	var biased := artifact.duplicate(true)
	for raw_site in biased["selection_sites"] as Array:
		var site: Dictionary = raw_site
		var surface: Dictionary = site["class_fitness"]
		var weakest := Bridge.CLASS_KEYS[0]
		for class_key in Bridge.CLASS_KEYS:
			if float(surface[class_key]) < float(surface[weakest]):
				weakest = class_key
		for class_key in Bridge.CLASS_KEYS:
			surface[class_key] = 0.05
		surface[weakest] = 4.0
	biased["selection_surface_digest"] = Bridge.selection_surface_digest(biased["selection_sites"] as Array)
	var counterfactual := Bridge.run(biased)
	_check(not counterfactual.is_empty(), "counterfactual rule-selection bridge builds")

	var same_first_candidate_pools := true
	var changed_final_population := false
	if not counterfactual.is_empty():
		var original_sites: Dictionary = first["sites"]
		var counterfactual_sites: Dictionary = counterfactual["sites"]
		for site_id in original_sites.keys():
			if not counterfactual_sites.has(site_id):
				same_first_candidate_pools = false
				continue
			var original_site: Dictionary = original_sites[site_id]
			var counterfactual_site: Dictionary = counterfactual_sites[site_id]
			var original_history: Array = original_site["history"]
			var counterfactual_history: Array = counterfactual_site["history"]
			if original_history.size() < 2 or counterfactual_history.size() < 2:
				same_first_candidate_pools = false
			else:
				same_first_candidate_pools = same_first_candidate_pools and (
					String(original_history[1].get("candidate_pool_hash", ""))
					== String(counterfactual_history[1].get("candidate_pool_hash", ""))
				)
			if String(original_site.get("final_population_hash", "")) != String(counterfactual_site.get("final_population_hash", "")):
				changed_final_population = true
	_check(same_first_candidate_pools, "counterfactual keeps generation-one mutation candidate pools identical")
	_check(changed_final_population, "changing only EVO6 fitness changes at least one selected final population")

	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/evo6_rule_selection_bridge_v1.gd")
	_check(source.find("MutationKernel.reproduce") >= 0, "bridge delegates reproduction to existing P1B kernel")
	_check(source.find("PlantGenome.create(") < 0, "bridge does not implement a second genome mutation path")
	_finish(first)

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish(result: Dictionary) -> void:
	print("ECO.EVO6-H1H3 result_hash=%s" % String(result.get("result_hash", "")))
	print("ECO.EVO6-H1H3 metrics=%s" % str(result.get("metrics", {})))
	if failures.is_empty():
		print("ECO.EVO6 generated-rule selection bridge: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO6-H1H3 FAIL: %s" % failure)
	print(
		"ECO.EVO6 generated-rule selection bridge: FAIL (%d assertions, %d failures)"
		% [assertions, failures.size()]
	)
	quit(1)

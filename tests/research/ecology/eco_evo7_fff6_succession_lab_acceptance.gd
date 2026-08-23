extends SceneTree

## ECO.EVO7 FFF6 - closed community evolution / succession lab acceptance
## (spec sections 15, 17 Experiment A, 19 FFF6; design doc open questions).
##
## Covered:
##   - six zones initialized deterministically (frozen parameters, distinct base
##     environment checksums, shared ancestor pool, common generation-one
##     candidate pool across zones AND feedback modes - G4);
##   - G5 geometry divergence: >= 3 pairwise zone-mean distinctions under the
##     FFF2 GEOMETRY_THRESHOLDS (the numeric core of the C-mode visual proof);
##   - G6/G7 + Experiment A: canopy ring darkens UNDER_CANOPY; deterministic
##     mid-run removal restores CANOPY_GAP light and fitness;
##   - ON/OFF counterfactual divergence in every zone under one mutation stream;
##   - >= 100 generation-equivalent stability runs without NaN, out-of-bounds
##     means or full axis bound-pinning (G11 preview);
##   - deterministic replay (run_all twice, incremental context path equivalence,
##     lineage-seed sensitivity);
##   - fail-closed matrix + source boundaries (single lineage authority, no RNG,
##     no archetypes, no ecology math inside the lab node).

const Simulation = preload("res://scripts/research/ecology/evo7_succession_simulation_v1.gd")
const LightField = preload("res://scripts/research/ecology/understory_light_field_v1.gd")
const EnvSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")

const SEED := 20260823

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_zone_contract()
	var result := Simulation.run_all(SEED)
	_main_run(result)
	_determinism_and_seeds(result)
	_fail_closed_matrix()
	_source_boundaries()
	_finish()

## ------------------------------------------------------------ zone contract --

func _zone_contract() -> void:
	for zone_name in Simulation.ZONE_ORDER:
		var parameters := Simulation.zone_parameters(zone_name)
		_check(not parameters.is_empty(), "zone parameters frozen for %s" % zone_name)
		if parameters.is_empty():
			continue
		for ratio_field in ["soil_moisture", "sunlight", "nutrients", "flood_frequency"]:
			var value := float(parameters[ratio_field])
			_check(is_finite(value) and value >= 0.0 and value <= 1.0,
				"%s %s within [0,1]" % [zone_name, ratio_field])
		_check(String(parameters["texture"]) in ["sand", "loam", "clay"],
			"%s texture is a versioned fixture channel" % zone_name)
		var base_env := Simulation.base_environment(zone_name)
		_check(not base_env.is_empty() and bool(EnvSample.validate(base_env).get("success", false)),
			"%s base environment sample validates" % zone_name)
	_check(Simulation.zone_parameters("BOGUS_ZONE").is_empty(), "unknown zone fails closed")
	_check(Simulation.base_environment("BOGUS_ZONE").is_empty(), "unknown zone env fails closed")
	_check(Simulation.ZONE_ORDER.size() == 6, "exactly six controlled zones")

	# Distinct zone identities: revision carries the zone, so checksums differ.
	var checksums := PackedStringArray()
	for zone_name in Simulation.ZONE_ORDER:
		checksums.append(String(Simulation.base_environment(zone_name)["checksum"]))
	var unique := {}
	for checksum in checksums:
		unique[checksum] = true
	_check(unique.size() == Simulation.ZONE_ORDER.size(), "zone base environments have distinct checksums")

	# Canopy ring: fixed tall/dense scenery, valid light records, deterministic.
	var canopy_a := Simulation.canopy_records()
	var canopy_b := Simulation.canopy_records()
	_check(canopy_a.size() == Simulation.CANOPY_PLANT_COUNT, "canopy ring has its declared plant count")
	var canopy_valid := true
	for record in canopy_a:
		if not bool(LightField.validate_record(record).get("success", false)):
			canopy_valid = false
	_check(canopy_valid, "canopy ring records validate against the light field contract")
	var canopy_tokens_a := _records_token(canopy_a)
	_check(canopy_tokens_a == _records_token(canopy_b), "canopy ring construction is deterministic")

## ----------------------------------------------------------------- main run --

func _main_run(result: Dictionary) -> void:
	_check(not result.is_empty(), "succession simulation runs")
	if result.is_empty():
		return
	print("ECO.EVO7 FFF6 result_hash=%s" % String(result["result_hash"]).substr(0, 16))

	_check(int(result["population_size"]) == 25, "5x5 community microcosm per zone")
	_check(String(result["mutation_stream_formula"]) == "EVO7-FFF6|seed|gen|parent|off",
		"shared mutation stream formula across every zone and mode")
	_check(not String(result["evo7_policy_hash"]).is_empty(), "single lineage policy hash present")
	_check(not String(result["ancestor_bundle_checksum"]).is_empty(), "ancestor bundle checksum present")

	# Deterministic initialization of all six zones.
	var initial_pop_hashes := PackedStringArray()
	var pool_hashes := PackedStringArray()
	for zone_name in Simulation.ZONE_ORDER:
		var zone: Dictionary = result["zones"].get(zone_name, {})
		_check(not zone.is_empty(), "zone %s completed both feedback runs" % zone_name)
		if zone.is_empty():
			continue
		_check(not String(zone["initial_field_hash"]).is_empty(), "%s initial light field hashed" % zone_name)
		_check(not String(zone["initial_plant_light_hash"]).is_empty(), "%s initial plant-light hashed" % zone_name)
		_check(not String(zone["initial_water_field_hash"]).is_empty(), "%s initial water field hashed" % zone_name)
		initial_pop_hashes.append(String(zone["initial_population_hash"]))
		pool_hashes.append(String(zone["common_first_generation_pool_hash"]))

		# G6 add-direction: the canopy ring darkens its zone before any evolution.
		if bool(zone["parameters"]["canopy"]):
			var open_reference := float(result["zones"]["MESIC_LOAM"]["initial_mean_understory_light"])
			_check(float(zone["initial_mean_understory_light"]) < open_reference - 0.30,
				"G6: canopy ring darkens %s understory at generation 1" % zone_name)

	var unique_initial := {}
	for token in initial_pop_hashes:
		unique_initial[token] = true
	_check(unique_initial.size() == 1, "one shared ancestor population across all zones")

	var unique_pool := {}
	for token in pool_hashes:
		unique_pool[token] = true
	_check(unique_pool.size() == 1, "G4: one generation-one candidate pool across all zones")
	for zone_name in Simulation.ZONE_ORDER:
		var zone: Dictionary = result["zones"][zone_name]
		_check(String(zone["feedback_on"]["common_first_generation_pool_hash"]) == String(zone["feedback_off"]["common_first_generation_pool_hash"]),
			"G4: %s pool hash identical across feedback modes" % zone_name)

	# G5: pairwise geometry-distinct zone means under GEOMETRY_THRESHOLDS.
	var comparison: Dictionary = result["comparison"]
	_check(int(comparison["geometry_distinct_pairs"]) >= 3,
		"G5: >= 3 zone pairs geometry-distinct (%d)" % int(comparison["geometry_distinct_pairs"]))
	_check(int(comparison["zones_distinct_from_moderate_baseline"]) >= 1,
		"G5: moderate baseline separated from contrasting zones")

	# ON/OFF counterfactual divergence everywhere.
	_check(int(comparison["on_off_divergent_zones"]) == Simulation.ZONE_ORDER.size(),
		"G7: feedback ON/OFF selects different descendants in all six zones")
	for zone_name in Simulation.ZONE_ORDER:
		var zone: Dictionary = result["zones"][zone_name]
		_check(String(zone["feedback_on"]["final_population_hash"]) != String(zone["feedback_off"]["final_population_hash"]),
			"G7: %s ON/OFF population hashes differ" % zone_name)
		_check(String(zone["feedback_on"]["first_generation_score_hash"]) != ""
			and String(zone["feedback_off"]["first_generation_score_hash"]) != "",
			"%s generation-one scores recorded for both modes" % zone_name)

	_experiment_a(result)

## ------------------------------------------------------------- Experiment A --

func _experiment_a(result: Dictionary) -> void:
	var under: Dictionary = result["zones"]["UNDER_CANOPY"]
	var gap: Dictionary = result["zones"]["CANOPY_GAP"]
	var under_on: Dictionary = under["feedback_on"]
	var gap_on: Dictionary = gap["feedback_on"]

	_check(bool(under["parameters"]["canopy"]) and bool(gap["parameters"]["canopy"]),
		"Experiment A precondition: both canopy zones start with the static ring")
	_check(String(under["parameters"]["texture"]) == String(gap["parameters"]["texture"])
		and int(under["parameters"]["nutrients"] * 1000) == int(gap["parameters"]["nutrients"] * 1000),
		"Experiment A: canopy zones share the frozen loam/mesic fixture channel")
	_check(float(under["parameters"]["soil_moisture"]) == float(gap["parameters"]["soil_moisture"])
		and float(under["parameters"]["sunlight"]) == float(gap["parameters"]["sunlight"]),
		"Experiment A: UNDER_CANOPY and CANOPY_GAP differ ONLY by the scheduled removal")

	# Removal restores the light field (G6 remove-direction).
	var pre_light := float(gap_on["pre_removal_mean_understory_light"])
	var post_light := float(gap_on["post_removal_mean_understory_light"])
	var under_light := float(under_on["mean_understory_light"])
	_check(pre_light > 0.0 and pre_light < 0.15,
		"Experiment A: deep shade before removal (mean %.4f)" % pre_light)
	_check(post_light > under_light + 0.30,
		"Experiment A/G6: removing the canopy restores GAP light over UNDER_CANOPY (+%.4f)" % float(result["comparison"]["gap_light_restoration_delta"]))
	_check(post_light > pre_light * 3.0, "Experiment A: light restoration is large, not marginal")

	# Trajectory bookkeeping is consistent with the removal boundary.
	var trajectory: Array = gap_on["mean_understory_light_trajectory"]
	_check(trajectory.size() == int(result["generations"]), "light trajectory covers every cycle")
	var removal := int(gap["parameters"]["canopy_removed_at_generation"])
	_check(absf(float(trajectory[removal - 1]) - pre_light) < 1e-9, "trajectory matches pre-removal generation")
	_check(absf(float(trajectory[removal]) - post_light) < 1e-9, "trajectory matches first post-removal generation")

	# Fitness recovers when the niche opens (net balance under OWN cell light).
	var net_recovery := float(gap_on["mean_net_balance"]) - float(under_on["mean_net_balance"])
	_check(net_recovery > 0.02, "Experiment A/G7: net balance recovers after gap creation (+%.5f)" % net_recovery)

	# The two communities evolve into DIFFERENT populations.
	_check(String(gap_on["final_population_hash"]) != String(under_on["final_population_hash"]),
		"Experiment A: GAP and UNDER_CANOPY descendants differ")

	# Field-level removal effect also visible WITHOUT feedback assignment.
	var gap_off: Dictionary = gap["feedback_off"]
	var off_pre := float(gap_off["pre_removal_mean_understory_light"])
	var off_post := float(gap_off["post_removal_mean_understory_light"])
	_check(off_post > off_pre * 3.0, "G6: removal restores the light field even in the OFF counterfactual")

	# Anti-runaway preview: no axis pinned in either canopy community.
	_check(float(under_on["max_bound_pinning_fraction"]) < 1.0 and float(gap_on["max_bound_pinning_fraction"]) < 1.0,
		"G11 preview: canopy communities do not end axis-pinned")

## ------------------------------------------------------ determinism/seeds --

func _determinism_and_seeds(result: Dictionary) -> void:
	if result.is_empty():
		return
	var replay := Simulation.run_all(SEED)
	_check(String(replay["result_hash"]) == String(result["result_hash"]),
		"deterministic replay: identical result hash on a full second run")

	# The lab consumes the INCREMENTAL context path; it must be byte-identical.
	var context := Simulation.create_context(SEED)
	var stepped := false
	while not Simulation.context_step(context):
		stepped = true
	var context_result := Simulation.context_finish(context)
	_check(stepped, "context path actually stepped zone-by-zone")
	_check(not context_result.is_empty() and String(context_result["result_hash"]) == String(result["result_hash"]),
		"incremental context aggregation is byte-identical to run_all")

	var other_seed := Simulation.run_all(SEED + 1)
	_check(not other_seed.is_empty() and String(other_seed["result_hash"]) != String(result["result_hash"]),
		"different lineage seed changes the landscape outcome")

	_stability_evidence()

func _stability_evidence() -> void:
	for stability_zone in ["MESIC_LOAM", "DRY_SAND"]:
		var stability := Simulation.run_zone_stability(stability_zone, SEED, Simulation.STABILITY_GENERATIONS)
		_check(not stability.is_empty(), "stability run completes for %s" % stability_zone)
		if stability.is_empty():
			continue
		_check(int(stability["completed_cycles"]) == Simulation.STABILITY_GENERATIONS
			and Simulation.STABILITY_GENERATIONS >= 100,
			"spec 19: %s ran %d generation-equivalents (>= 100)" % [stability_zone, int(stability["completed_cycles"])])
		_check(bool(stability["finite_means"]), "stability %s: no NaN in aggregate means" % stability_zone)
		_check(bool(stability["means_within_bounds"]), "stability %s: light/moisture/organic means stay in [0,1]" % stability_zone)
		_check(bool(stability["trajectory_finite"]), "stability %s: light trajectory finite" % stability_zone)
		_check(bool(stability["no_axis_fully_pinned"]),
			"G11: no evolvable axis fully bound-pinned in %s (max %.3f)" % [
				stability_zone, float(stability["max_bound_pinning_fraction"])])
		var pinning: Dictionary = stability["bound_pinning_fractions"]
		_check(pinning.size() == 8, "bound-pinning reported for all 8 lineage axes (%s)" % stability_zone)
		var pinning_sane := true
		for axis_name in pinning.keys():
			var fraction := float(pinning[axis_name])
			if fraction < 0.0 or fraction > 1.0:
				pinning_sane = false
		_check(pinning_sane, "pinning fractions are sane ratios (%s)" % stability_zone)

## ---------------------------------------------------------- fail-closed matrix --

func _fail_closed_matrix() -> void:
	_check(Simulation.run_all(SEED, 1).is_empty(), "fail-closed: run_all below minimum generations")
	_check(Simulation.run_all(SEED, 0).is_empty(), "fail-closed: run_all zero generations")
	_check(Simulation.create_context(SEED, 0).is_empty(), "fail-closed: context below minimum generations")
	_check(Simulation.context_step({}), "fail-closed: stepping an empty context finishes safely")
	_check(Simulation.context_finish({}).is_empty(), "fail-closed: finishing an empty context fails closed")
	var partial := Simulation.create_context(SEED, 4)
	Simulation.context_step(partial)
	partial["pending"] = []
	_check(Simulation.context_finish(partial).is_empty(), "fail-closed: unfinished zone set fails closed")
	_check(Simulation.run_zone_stability("BOGUS").is_empty(), "fail-closed: stability run rejects unknown zone")
	_check(Simulation.run_zone_stability("MESIC_LOAM", SEED, 1).is_empty(), "fail-closed: stability run below minimum generations")
	var orphan_bundle := Simulation.default_ancestor_bundle(SEED)
	_check(Simulation.realize_entry(orphan_bundle, "p00", {}).is_empty(),
		"fail-closed: realization rejects an invalid environment")
	_check(Simulation.morphology_cluster_count([]) == 0, "fail-closed: clustering empty set is zero clusters")
	_check(Simulation.bound_pinning_fractions([]).is_empty(), "fail-closed: pinning of empty population is empty map")
	var identical := {"realized_height_m": 1.0, "realized_crown_radius_m": 0.5, "realized_crown_density": 0.4,
		"leaf_area_index_proxy": 0.3, "realized_root_depth_m": 0.8, "realized_root_spread_m": 1.2,
		"structural_investment": 0.4}
	var shifted := identical.duplicate()
	shifted["realized_height_m"] = 1.0 + float(Simulation.GEOMETRY_THRESHOLDS["realized_height_m"])
	_check(not Simulation.geometry_distinct(identical, identical.duplicate()), "geometry comparator: identical vectors are not distinct")
	_check(Simulation.geometry_distinct(identical, shifted), "geometry comparator: threshold-exceeding vector is distinct")
	_check(int(Simulation.morphology_cluster_count([{"identity": "a", "features": identical}, {"identity": "b", "features": identical.duplicate()}])) == 1,
		"clustering merges vectors inside the thresholds into one cluster")

## --------------------------------------------------------- source boundaries --

func _source_boundaries() -> void:
	var simulation_source := FileAccess.get_file_as_string("res://scripts/research/ecology/evo7_succession_simulation_v1.gd").to_lower()
	for forbidden in ["randf", "randi(", "randomize", "randomnumbergenerator", "get_tree", "camera"]:
		_check(not simulation_source.contains(forbidden), "simulation source excludes %s" % forbidden)
	_check(not simulation_source.contains("archetype"), "simulation source contains no archetype vocabulary")
	_check(simulation_source.contains("plant_mutation_lineage_extension_evo7_v1.gd"),
		"simulation reproduces only through the single lineage authority")
	_check(simulation_source.contains("sort_custom"), "simulation aggregates in canonical order")

	var lab_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_form_function_feedback_lab.gd").to_lower()
	for forbidden in ["randf", "randi(", "randomize", "lineageextension", "plant_mutation_lineage_kernel", "envsample"]:
		_check(not lab_source.contains(forbidden),
			"lab node holds no evolution/environment authority (%s absent)" % forbidden)
	_check(lab_source.contains("multiscalematerializer.build"), "lab materializes through the real PH5 pipeline")
	_check(lab_source.contains("simulation.realize_entry"), "lab visuals come from the shared realization helper")
	_check(lab_source.contains("evo7_fff6_lab_autocap"), "lab exposes the headless autocap switch")
	_check(lab_source.contains("_unhandled_input"), "lab wires interactive controls")

	var scene_text := FileAccess.get_file_as_string("res://scenes/labs/ecology/eco_evo7_form_function_feedback_lab.tscn")
	_check(scene_text.contains("eco_evo7_form_function_feedback_lab.gd"), "scene references its 1:1 basename script")
	_check(scene_text.length() < 400, "scene stays minimal (EVO6 house pattern)")

## ------------------------------------------------------------------ output --

static func _records_token(records: Array) -> String:
	var tokens := PackedStringArray()
	for record in records:
		tokens.append("%s|%.6f|%.6f" % [String(record["identity"]), float(record["world_x_m"]), float(record["world_z_m"])])
	return "|".join(tokens).sha256_text()

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO7 FFF6 Succession Lab: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 FFF6 FAIL: %s" % failure)
	print("ECO.EVO7 FFF6 Succession Lab: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)

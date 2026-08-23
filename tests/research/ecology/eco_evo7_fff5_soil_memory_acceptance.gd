extends SceneTree

## ECO.EVO7 FFF5 - soil / litter memory acceptance (spec sections 10, 17
## Experiment D, 19 FFF5; gates G10/G12 supporting).
##
## Covered:
##   - effect contract: litter_input_ppm activated (FFF5), soil_binding still
##     zero-enforced ("no creation from nothing");
##   - soil organic field: deterministic accumulation, order invariance (G12),
##     bounds [0,1], texture decay direction (clay retains more than sand),
##     retention multiplier math, fail-closed matrix;
##   - water field retention coupling: with an organic map the SAME plants lose
##     less water to evaporation and keep more moisture; pristine behavior
##     (absent map) unchanged; fail-closed on bad maps;
##   - EXPERIMENT D causality: identical fresh seed pools diverge on modified vs
##     pristine plots (population hashes) with an establishment-component delta
##     in the direction "modified soil helps the next generation";
##   - determinism replay + lineage-seed sensitivity; source boundaries.

const WaterField = preload("res://scripts/research/ecology/soil_water_field_v1.gd")
const OrganicField = preload("res://scripts/research/ecology/soil_organic_field_v1.gd")
const Effect = preload("res://scripts/research/ecology/plant_environment_effect_v1.gd")
const Bridge = preload("res://scripts/research/ecology/evo7_litter_feedback_bridge_v1.gd")

const SEED := 20260823

## Thresholds carry >= 2x margin against the observed cross-seed values
## (20260823/24/25): legacy mean organic 0.161..0.174, modified-pristine mean
## organic delta 0.0825..0.0835, establishment component delta 0.00219..0.00246,
## modified-pool final mean organic 0.219..0.231 (see FFF5 checkpoint).
const LEGACY_MEAN_ORGANIC_THRESHOLD := 0.08
const ORGANIC_DELTA_THRESHOLD := 0.04
const ESTABLISHMENT_DELTA_THRESHOLD := 0.001
const POOL_MODIFIED_MEAN_ORGANIC_THRESHOLD := 0.11

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_effect_contract_litter()
	_organic_field_basics()
	_organic_effects_publication()
	_water_retention_coupling()
	var result := Bridge.run_all(SEED)
	_experiment_d(result)
	_determinism_and_seeds(result)
	_source_boundaries()
	_finish()

## ---------------------------------------------------------------- helpers --

static func _lrecord(identity: String, x: float, z: float, litter_ppm: int) -> Dictionary:
	return {
		"identity": identity,
		"world_x_m": x,
		"world_z_m": z,
		"litter_flux_ppm": litter_ppm,
		"source_phenotype_hash": "d".repeat(64),
	}

static func _grid_litter_records(litter_ppm: int) -> Array:
	var records: Array = []
	var index := 0
	for iz in 5:
		for ix in 5:
			records.append(_lrecord(
				"p%02d" % index, snappedf(float(ix) * 0.35 - 0.7, 1e-9), snappedf(float(iz) * 0.35 - 0.7, 1e-9),
				litter_ppm))
			index += 1
	return records

static func _wrecord(identity: String, x: float, z: float, demand_ppm: int) -> Dictionary:
	return {
		"identity": identity,
		"world_x_m": x,
		"world_z_m": z,
		"transpiration_demand_ppm": demand_ppm,
		"realized_crown_radius_m": 0.6,
		"realized_crown_density": 0.5,
		"realized_root_depth_m": 1.2,
		"realized_root_spread_m": 1.0,
		"root_shoot_ratio": 0.5,
		"shade_output_ppm": 0,
		"source_phenotype_hash": "c".repeat(64),
	}

static func _water_inputs(textures: Dictionary, moisture: Dictionary, organic_map: Dictionary) -> Dictionary:
	var inputs := {
		"fixture_id": "eco-soil-texture/fff5-acceptance",
		"fixture_version": "1.0.0",
		"textures": textures,
		"base_moisture": moisture,
		"base_evaporation_rate": 20000.0,
	}
	if not organic_map.is_empty():
		inputs["organic_map"] = organic_map.duplicate(true)
	return inputs

## --------------------------------------------------- effect contract (FFF5) --

func _effect_contract_litter() -> void:
	_check(Effect.ACTIVE_CHANNELS.has("litter_input_ppm"), "FFF5: litter_input_ppm channel is active")
	_check(Effect.INACTIVE_CHANNELS.has("soil_binding_ppm") and Effect.INACTIVE_CHANNELS.size() == 1, "FFF5: soil_binding_ppm stays reserved-zero")
	var effect := Effect.create("p00", "0|0", 6, 0, "b".repeat(64), 0, 0, 20000)
	_check(not effect.is_empty(), "FFF5: litter effect record created")
	_check(int(effect["litter_input_ppm"]) == 20000 and bool(Effect.validate(effect).get("success", false)), "FFF5: effect record carries nonzero litter_input_ppm and validates")
	var negative: Dictionary = effect.duplicate(true)
	negative["litter_input_ppm"] = -4
	_check(not bool(Effect.validate(negative).get("success", false)), "FFF5: negative litter channel rejected")
	var tampered: Dictionary = effect.duplicate(true)
	tampered["soil_binding_ppm"] = 9
	_check(not bool(Effect.validate(tampered).get("success", false)), "FFF5: nonzero soil_binding still rejected (no creation from nothing)")
	var legacy_shape := Effect.create("p01", "0|0", 6, 12000, "b".repeat(64), 25000, 30000)
	_check(int(legacy_shape["litter_input_ppm"]) == 0, "FFF5: defaulted litter argument keeps pre-FFF5 call sites at zero")
	var effect_b := Effect.create("pB", "0|0", 1, 0, "b".repeat(64), 0, 0, 500)
	var effect_a := Effect.create("pA", "1|1", 1, 0, "a".repeat(64), 0, 0, 700)
	var combined := String(Effect.combined_hash([effect_b, effect_a]))
	_check(String(Effect.combined_hash([effect_a, effect_b])) == combined, "FFF5: combined hash of litter-carrying records is order-invariant")

## ------------------------------------------------------- organic field ------

func _organic_field_basics() -> void:
	var records := _grid_litter_records(24000)
	var textures := {"-1|-1": "loam", "0|-1": "loam", "-1|0": "loam", "0|0": "loam"}
	var inputs := OrganicField.field_inputs_for("fff5-basics", textures)
	var field := OrganicField.compute(records, inputs)
	_check(not field.is_empty(), "G8-style: organic field computes for the reference community")
	if field.is_empty():
		_finish()
		return
	var cells: Dictionary = field["cells"]
	_check(cells.size() == 4, "organic field buckets plants into the expected 4 cells")
	var bounds_ok := true
	var deposited_total := 0
	for cell_id in cells.keys():
		var cell: Dictionary = cells[cell_id]
		var organic_after := float(cell["organic_after"])
		if organic_after < 0.0 or organic_after > OrganicField.ORGANIC_CAPACITY:
			bounds_ok = false
		deposited_total += int(cell["deposited_litter_ppm"])
	_check(bounds_ok, "organic proxy stays within [0, ORGANIC_CAPACITY]")
	var expected_total := 25 * 24000
	_check(deposited_total == expected_total, "deposited litter is conserved into per-cell totals")

	var replay := OrganicField.compute(records, inputs)
	_check(String(replay["organic_field_hash"]) == String(field["organic_field_hash"]) and String(replay["plant_litter_hash"]) == String(field["plant_litter_hash"]), "deterministic accumulation reproduces both hashes exactly")

	# G12 order invariance.
	var permuted := [
		records[17], records[3], records[24], records[9], records[11],
		records[0], records[20], records[6], records[13],
	]
	var grid_textures := {"-1|-1": "loam", "0|-1": "loam", "-1|0": "loam", "0|0": "loam"}
	var permuted_inputs := OrganicField.field_inputs_for("fff5-basics", grid_textures)
	var permuted_field := OrganicField.compute(permuted, permuted_inputs)
	var canonical_field := OrganicField.compute(_sorted_by_identity(permuted), permuted_inputs)
	var reversed_field := OrganicField.compute(_reversed_copy(permuted), permuted_inputs)
	_check(not permuted_field.is_empty() and String(permuted_field["organic_field_hash"]) == String(canonical_field["organic_field_hash"]), "G12: organic field hash invariant under permutation")
	_check(String(permuted_field["plant_litter_hash"]) == String(canonical_field["plant_litter_hash"]), "G12: plant litter hash invariant under permutation")
	_check(String(reversed_field["organic_field_hash"]) == String(canonical_field["organic_field_hash"]) and String(reversed_field["plant_litter_hash"]) == String(canonical_field["plant_litter_hash"]), "G12: reversed input order gives identical organic field")
	var per_plant_equal := true
	for record: Dictionary in permuted:
		var identity := String(record["identity"])
		if int(permuted_field["plant_litter"][identity]["litter_flux_ppm"]) != int(canonical_field["plant_litter"][identity]["litter_flux_ppm"]):
			per_plant_equal = false
	_check(per_plant_equal, "G12: per-plant deposited litter identical under permutation")

	# Accumulation across updates via the carryover map.
	var first_map: Dictionary = field["organic_map"]
	var second_inputs := OrganicField.field_inputs_for("fff5-basics", textures, first_map)
	var second_field := OrganicField.compute(records, second_inputs)
	var second_cells: Dictionary = second_field["cells"]
	var accumulation_ok := true
	for cell_id in second_cells.keys():
		if float(second_cells[cell_id]["organic_after"]) <= float(first_map[String(cell_id)]):
			accumulation_ok = false
	_check(accumulation_ok, "carryover map accumulates: every cell gains organic after a further equal deposit")

	# Texture decay direction: equal litter + equal decay rate, clay keeps more
	# than sand (multipliers 0.75 vs 1.3).
	var texture_records := [
		_lrecord("sandy", -5.5, -5.5, 100000),
		_lrecord("clayey", 5.5, 5.5, 100000),
	]
	var texture_inputs := OrganicField.field_inputs_for("fff5-textures", {"-6|-6": "sand", "5|5": "clay"})
	var texture_field := OrganicField.compute(texture_records, texture_inputs)
	_check(not texture_field.is_empty(), "texture decay contrast computes")
	var sand_cell: Dictionary = texture_field["cells"]["-6|-6"]
	var clay_cell: Dictionary = texture_field["cells"]["5|5"]
	_check(float(clay_cell["organic_after"]) > float(sand_cell["organic_after"]), "decay direction: clay retains more organic than sand after equal litter+decay")
	_check(absf(float(clay_cell["decay_factor"]) - 0.94) < 1e-6 and absf(float(sand_cell["decay_factor"]) - 0.896) < 1e-6, "decay factors exact: clay (1-0.08*0.75)=0.94, sand (1-0.08*1.3)=0.896")
	_check(float(OrganicField.retention_multiplier(float(clay_cell["organic_after"]))) > float(OrganicField.retention_multiplier(float(sand_cell["organic_after"]))), "clay's extra organic yields a higher retention multiplier")

	# No creation from nothing + capacity clamp + multiplier math.
	var single_cell_inputs := OrganicField.field_inputs_for("fff5-single", {"0|0": "loam"})
	var zero_field := OrganicField.compute([_lrecord("quiet", 0.5, 0.5, 0)], single_cell_inputs)
	_check(not zero_field.is_empty() and float(zero_field["cells"]["0|0"]["organic_after"]) == 0.0, "zero litter over zero legacy leaves the cell pristine (no organic from nothing)")
	var huge := OrganicField.compute([_lrecord("huge", 0.5, 0.5, 999999999)], single_cell_inputs)
	_check(float(huge["cells"]["0|0"]["organic_after"]) == OrganicField.ORGANIC_CAPACITY, "organic clamps at ORGANIC_CAPACITY under extreme litter")
	_check(absf(OrganicField.retention_multiplier(0.0) - 1.0) < 1e-12 and absf(OrganicField.retention_multiplier(0.4) - 1.14) < 1e-9 and absf(OrganicField.retention_multiplier(1.0) - 1.35) < 1e-9, "retention multiplier exact: 1 + 0.35 * clamp01(organic)")

	# Fail-closed matrix.
	_check(OrganicField.compute([], single_cell_inputs).is_empty(), "fail-closed: empty record set")
	var dup := [_lrecord("dup", 0.5, 0.5, 100), _lrecord("dup", 1.5, 1.5, 100)]
	_check(OrganicField.compute(dup, single_cell_inputs).is_empty(), "fail-closed: duplicate identity")
	_check(OrganicField.compute([_lrecord("neg", 0.5, 0.5, -1)], single_cell_inputs).is_empty(), "fail-closed: negative litter flux")
	_check(OrganicField.compute([_lrecord("x", 50.5, 50.5, 100)], single_cell_inputs).is_empty(), "fail-closed: occupied cell without texture")
	var bad_texture_inputs := OrganicField.field_inputs_for("fff5-bad-texture", {"50|50": "gravel"})
	_check(OrganicField.compute([_lrecord("x", 50.5, 50.5, 100)], bad_texture_inputs).is_empty(), "fail-closed: unknown texture value")
	_check(not bool(OrganicField.validate_field_inputs({"fixture_id": "", "fixture_version": "1.0.0", "textures": {}}).get("success", false)), "fail-closed: empty fixture identity")
	_check(not bool(OrganicField.validate_field_inputs({"fixture_id": "t", "fixture_version": "1.0.0", "textures": {}, "decay_rate": 1.5}).get("success", false)), "fail-closed: decay_rate outside [0,1]")
	_check(OrganicField.compute([_lrecord("x", 0.5, 0.5, 100)], OrganicField.field_inputs_for("fff5-gap", {"0|0": "loam"}, {"9|9": 0.5})).is_empty(), "fail-closed: carryover map missing an occupied cell")
	_check(not bool(OrganicField.validate_field_inputs({"fixture_id": "t", "fixture_version": "1.0.0", "textures": {}, "initial_organic": {"0|0": 1.5}}).get("success", false)), "fail-closed: carryover value above capacity")

func _organic_effects_publication() -> void:
	var records := _grid_litter_records(18000)
	var inputs := OrganicField.field_inputs_for("fff5-effects", {"-1|-1": "loam", "0|-1": "loam", "-1|0": "loam", "0|0": "loam"})
	var effects := OrganicField.effect_records(records, inputs, 5)
	_check(effects.size() == records.size(), "one litter effect record per plant")
	var all_valid := true
	var any_litter := true
	var single_channel := true
	for effect: Dictionary in effects:
		if not bool(Effect.validate(effect).get("success", false)):
			all_valid = false
		if int(effect["litter_input_ppm"]) <= 0:
			any_litter = false
		if int(effect["shade_ppm"]) != 0 or int(effect["water_uptake_ppm"]) != 0 or int(effect["evaporation_suppression_ppm"]) != 0:
			single_channel = false
	_check(all_valid, "every litter effect record validates")
	_check(any_litter, "effect records carry nonzero litter_input_ppm")
	_check(single_channel, "organic field publishes only its own channel (single-channel discipline)")
	var ordered: Array = Effect.canonical_sort(effects)
	_check(String(ordered[0]["plant_identity"]) == "p00" and int(ordered[0]["generation"]) == 5, "canonical publication order and generation stamp")

## ------------------------------------------------ water retention coupling --

func _water_retention_coupling() -> void:
	var records := [_wrecord("mulched", 0.5, 0.5, 8000), _wrecord("bare", 5.5, 5.5, 8000)]
	var textures := {"0|0": "loam", "5|5": "loam"}
	var moisture := {"0|0": 0.5, "5|5": 0.5}
	var pristine := WaterField.compute(records, _water_inputs(textures, moisture, {}))
	_check(not pristine.is_empty(), "pristine water field computes (no organic map)")
	var explicit_zero := WaterField.compute(records, _water_inputs(textures, moisture, {"0|0": 0.0, "5|5": 0.0}))
	_check(not explicit_zero.is_empty() and float(explicit_zero["cells"]["0|0"]["evaporation_ppm"]) == float(pristine["cells"]["0|0"]["evaporation_ppm"]), "explicit zero-organic map scales evaporation by exactly 1/1.0 (= no change)")
	_check(bool(pristine["organic_coupling"]) == false and not pristine["cells"]["0|0"].has("organic_input"), "absent map marks organic_coupling=false and adds no per-cell coupling state")

	var organic_map := {"0|0": 0.4, "5|5": 0.1}
	var mulched := WaterField.compute(records, _water_inputs(textures, moisture, organic_map))
	_check(not mulched.is_empty(), "coupled water field computes")
	var mulched_cell: Dictionary = mulched["cells"]["0|0"]
	var bare_cell: Dictionary = mulched["cells"]["5|5"]
	var pristine_cell: Dictionary = pristine["cells"]["0|0"]
	var unscaled := snappedf(20000.0 * 1.0 * (1.0 - float(pristine_cell["shade_suppression"])), 1e-9)
	var expected_evap := snappedf(clampf(unscaled / OrganicField.retention_multiplier(0.4), 0.0, unscaled), 1e-9)
	_check(absf(float(mulched_cell["evaporation_ppm"]) - expected_evap) < 1e-6, "coupled evaporation = shade-reduced base / (1 + 0.35*organic) exactly")
	_check(float(mulched_cell["evaporation_ppm"]) < float(pristine_cell["evaporation_ppm"]), "RETENTION COUPLING: same plant loses less water to evaporation on the organic-mulched cell")
	var pristine_bare_cell: Dictionary = pristine["cells"]["5|5"]
	_check(float(bare_cell["evaporation_ppm"]) < float(pristine_bare_cell["evaporation_ppm"]) and float(bare_cell["evaporation_ppm"]) > float(mulched_cell["evaporation_ppm"]), "weak organic gives partial retention (monotone in organic)")
	_check(float(mulched_cell["moisture_after"]) > float(pristine_cell["moisture_after"]), "mulched cell keeps more moisture over the same update")
	_check(int(mulched_cell["total_uptake_ppm"]) == int(pristine_cell["total_uptake_ppm"]), "uptake is untouched by the organic coupling (same demands)")
	_check(bool(mulched["field_hash"] != pristine["field_hash"]), "coupling changes the field hash (initial != modified evidence)")

	# Fail-closed on bad organic maps.
	_check(WaterField.compute(records, _water_inputs(textures, moisture, {"9|9": 0.5})).is_empty(), "fail-closed: organic map missing an occupied cell")
	var out_of_range := _water_inputs(textures, moisture, {"0|0": 1.5, "5|5": 0.1})
	_check(not bool(WaterField.validate_field_inputs(out_of_range).get("success", false)), "fail-closed: organic value above capacity")
	var wrong_type := _water_inputs(textures, moisture, {})
	wrong_type["organic_map"] = "not-a-map"
	_check(not bool(WaterField.validate_field_inputs(wrong_type).get("success", false)), "fail-closed: non-dictionary organic map")

## ------------------------------------------------------------ Experiment D --

func _experiment_d(result: Dictionary) -> void:
	_check(not result.is_empty(), "litter feedback bridge runs")
	if result.is_empty():
		_finish()
		return
	print("ECO.EVO7 FFF5 bridge result_hash=%s" % String(result["result_hash"]).substr(0, 16))
	var fixture: Dictionary = result["scenario"]
	_check(String(fixture["texture"]) == "loam" and String(fixture["control_point"]) == "wet_lowland", "loam_legacy scenario: loam over the wet_lowland control point")
	_check(String(result["mutation_stream_formula"]) == "EVO7-LITTER|seed|gen|parent|off", "shared mutation stream formula across all runs")
	_check(int(result["legacy_generations"]) == 10 and int(result["experiment_d"]["generations"]) == 8, "Experiment D phasing: 10 legacy cycles then 8 pool cycles")

	var legacy: Dictionary = result["legacy_phase"]
	var trajectory: Array = legacy["mean_organic_trajectory"]
	_check(String(legacy["final_organic_map_hash"]) != String(legacy["initial_organic_map_hash"]), "G10: community built an organic legacy (initial map hash != final)")
	_check(trajectory.size() == 10 and float(trajectory[trajectory.size() - 1]) > float(trajectory[0]), "organic legacy rises monotonically enough to observe (first cycle below last)")
	_check(float(legacy["mean_cell_organic"]) > LEGACY_MEAN_ORGANIC_THRESHOLD, "legacy mean organic clears the calibrated threshold (observed ~%.3f)" % float(legacy["mean_cell_organic"]))

	var experiment: Dictionary = result["experiment_d"]
	var modified: Dictionary = experiment["pool_modified"]
	var pristine_pool: Dictionary = experiment["pool_pristine"]
	var feedback_off: Dictionary = experiment["feedback_off_on_modified"]
	var divergence: Dictionary = experiment["divergence"]
	var cross: Dictionary = experiment["cross_evaluation"]

	_check(bool(experiment["seed_pools_identical"]), "EXPERIMENT D precondition: the two fresh seed pools are identical")
	_check(int(cross["genome_count"]) == 50, "cross-evaluation scores the pooled genomes of both pools")

	# The stage gate itself: same seeds, different soil, different descendants.
	_check(bool(divergence["populations_differ_modified_vs_pristine"]), "EXPERIMENT D: modified-vs-pristine pools evolve DIFFERENT populations")
	_check(bool(divergence["population_differs_feedback_on_vs_off"]), "ON/OFF counterfactual: feedback assignment changes the selected descendants")
	_check(float(divergence["organic_modified_minus_pristine"]) > ORGANIC_DELTA_THRESHOLD, "EXPERIMENT D: modified plot keeps more organic than pristine (delta %.4f)" % float(divergence["organic_modified_minus_pristine"]))
	_check(float(modified["mean_cell_organic"]) > POOL_MODIFIED_MEAN_ORGANIC_THRESHOLD, "EXPERIMENT D: modified pool inherits a rich organic state")
	_check(float(divergence["establishment_component_modified_minus_pristine"]) > ESTABLISHMENT_DELTA_THRESHOLD, "EXPERIMENT D: establishment success is HIGHER on the modified soil (delta %.5f)" % float(divergence["establishment_component_modified_minus_pristine"]))
	_check(float(modified["mean_establishment_component"]) > float(pristine_pool["mean_establishment_component"]), "EXPERIMENT D: direction 'modified soil helps the next generation' (establishment-weighted success)")
	_check(float(feedback_off["mean_establishment_component"]) == 0.0, "feedback OFF carries no organic establishment bonus by construction")
	_check(float(modified["mean_net_balance"]) > -1.0 and float(pristine_pool["mean_net_balance"]) > -1.0, "both pools stay viable (finite net balances)")
	_check(float(modified["mean_features"]["establishment_capacity"]) > 0.0 and float(pristine_pool["mean_features"]["establishment_capacity"]) > 0.0, "establishment capacities observable in both pools")

## ------------------------------------------------------ determinism/seeds --

func _determinism_and_seeds(result: Dictionary) -> void:
	if result.is_empty():
		return
	var replay := Bridge.run_all(SEED)
	_check(String(replay["result_hash"]) == String(result["result_hash"]), "deterministic replay: identical result hash")
	var other_seed := Bridge.run_all(SEED + 1)
	_check(not other_seed.is_empty() and String(other_seed["result_hash"]) != String(result["result_hash"]), "different lineage seed changes the litter-feedback outcome")

## ------------------------------------------------------- source boundaries --

func _source_boundaries() -> void:
	var organic_source := FileAccess.get_file_as_string("res://scripts/research/ecology/soil_organic_field_v1.gd").to_lower()
	for forbidden in ["randf", "randi(", "randomize", "get_tree", "node", "camera"]:
		_check(not organic_source.contains(forbidden), "organic field source excludes %s" % forbidden)
	_check(organic_source.contains("sort_custom"), "organic field sorts records into canonical order")
	_check(organic_source.contains("texture_decay_multiplier"), "texture enters the organic field as versioned parameters")
	_check(organic_source.contains("retention_multiplier"), "organic field exposes the retention coupling accessor")

	var bridge_source := FileAccess.get_file_as_string("res://scripts/research/ecology/evo7_litter_feedback_bridge_v1.gd").to_lower()
	for forbidden in ["randf", "randi(", "randomize", "randomnumbergenerator", "archetype"]:
		_check(not bridge_source.contains(forbidden), "litter bridge source excludes %s" % forbidden)
	_check(bridge_source.contains("evo7-litter|"), "litter bridge uses the shared mutation stream formula")
	_check(bridge_source.contains("plant_mutation_lineage_extension_evo7_v1.gd"), "litter bridge reproduces only through the single lineage authority")
	var texture_lines_outside_fixture := 0
	for line in bridge_source.split("\n"):
		if (line.contains("sand") or line.contains("loam") or line.contains("clay")) \
				and not (line.contains("loam_legacy") or line.contains("texture")):
			texture_lines_outside_fixture += 1
	_check(texture_lines_outside_fixture == 0, "texture tokens appear only in fixture construction (no morphology rules)")

	var water_source := FileAccess.get_file_as_string("res://scripts/research/ecology/soil_water_field_v1.gd").to_lower()
	_check(water_source.contains("retention_multiplier"), "water field consumes the organic retention coupling as an optional input")
	var effect_source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_environment_effect_v1.gd")
	_check(effect_source.contains("INACTIVE_CHANNEL_NONZERO"), "effect contract still guards the reserved channel")

## ------------------------------------------------------------------ output --

static func _reversed_copy(records: Array) -> Array:
	var copy := records.duplicate()
	copy.reverse()
	return copy

static func _sorted_by_identity(records: Array) -> Array:
	var copy := records.duplicate()
	copy.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["identity"]) < String(b["identity"]))
	return copy

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO7 FFF5 Soil Memory: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 FFF5 FAIL: %s" % failure)
	print("ECO.EVO7 FFF5 Soil Memory: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)

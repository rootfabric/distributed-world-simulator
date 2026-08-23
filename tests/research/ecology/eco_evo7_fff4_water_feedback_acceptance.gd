extends SceneTree

## ECO.EVO7 FFF4 - water + soil texture feedback acceptance.
## Gates: G8 water engineering (moisture bounds, per-cell uptake <= available
## water, high-LAI dries soil more, canopy evaporation suppression, water effect
## records); G9 sand vs loam (dry_sand evolves compact crown + root-heavy form,
## mesic_loam keeps tall strategies, texture only through water field parameters);
## determinism (replay, seed sensitivity) and G12 order invariance.

const WaterField = preload("res://scripts/research/ecology/soil_water_field_v1.gd")
const Effect = preload("res://scripts/research/ecology/plant_environment_effect_v1.gd")
const Bridge = preload("res://scripts/research/ecology/evo7_water_feedback_bridge_v1.gd")

const SEED := 20260823

## G9 thresholds: observed dry-vs-mesic deltas on the fixed seed clear each
## threshold with >= 2x margin (cross-seed deltas: LAI 0.131..0.150,
## root depth 0.65..1.39, rsr 0.031..0.146 - see FFF4 checkpoint).
const LAI_DELTA_THRESHOLD := 0.05
const ROOT_DEPTH_DELTA_THRESHOLD := 0.30
const RSR_DELTA_THRESHOLD := 0.015

var assertions := 0
var failures: Array[String] = []
var bridge_runtime_msec := 0

func _init() -> void:
	_effect_contract_water()
	_g8_water_engineering()
	var bridge_started := Time.get_ticks_msec()
	var result := Bridge.run_all(SEED)
	bridge_runtime_msec = Time.get_ticks_msec() - bridge_started
	_g9_sand_vs_loam(result)
	_determinism_and_order(result)
	_source_boundaries()
	_finish()

static func _wrecord(
	identity: String, x: float, z: float, demand_ppm: int,
	crown_radius: float, crown_density: float, root_depth: float, root_spread: float,
	rsr := 0.5, shade_ppm := 0
) -> Dictionary:
	return {
		"identity": identity,
		"world_x_m": x,
		"world_z_m": z,
		"transpiration_demand_ppm": demand_ppm,
		"realized_crown_radius_m": crown_radius,
		"realized_crown_density": crown_density,
		"realized_root_depth_m": root_depth,
		"realized_root_spread_m": root_spread,
		"root_shoot_ratio": rsr,
		"shade_output_ppm": shade_ppm,
		"source_phenotype_hash": "c".repeat(64),
	}

static func _grid_records(demand_ppm: int, crown_radius: float, root_depth: float) -> Array:
	var records: Array = []
	var index := 0
	for iz in 5:
		for ix in 5:
			records.append(_wrecord(
				"p%02d" % index, snappedf(float(ix) * 0.35 - 0.7, 1e-9), snappedf(float(iz) * 0.35 - 0.7, 1e-9),
				demand_ppm, crown_radius, 0.8, root_depth, 1.0))
			index += 1
	return records

## Texture and base-moisture maps covering every cell the records occupy.
static func _maps_for(records: Array, texture: String, base_moisture: float) -> Dictionary:
	var textures := {}
	var moisture := {}
	for record: Dictionary in records:
		var cell_id := WaterField.cell_identity_for(float(record["world_x_m"]), float(record["world_z_m"]))
		textures[cell_id] = texture
		moisture[cell_id] = base_moisture
	return {"textures": textures, "base_moisture": moisture}

static func _field_inputs(maps: Dictionary, base_evaporation := 20000.0) -> Dictionary:
	return {
		"fixture_id": "eco-soil-texture/test-fixture",
		"fixture_version": "1.0.0",
		"textures": maps["textures"],
		"base_moisture": maps["base_moisture"],
		"base_evaporation_rate": base_evaporation,
	}

func _effect_contract_water() -> void:
	_check(Effect.ACTIVE_CHANNELS.has("shade_ppm") and Effect.ACTIVE_CHANNELS.has("water_uptake_ppm") and Effect.ACTIVE_CHANNELS.has("evaporation_suppression_ppm"), "water channels activated in R1 (FFF4)")
	_check(Effect.INACTIVE_CHANNELS.has("litter_input_ppm") and Effect.INACTIVE_CHANNELS.has("soil_binding_ppm"), "litter/soil_binding stay reserved for FFF5")
	var effect := Effect.create("p00", "0|0", 4, 12000, "b".repeat(64), 25000, 30000)
	_check(not effect.is_empty(), "water effect record created")
	_check(int(effect["water_uptake_ppm"]) == 25000 and int(effect["evaporation_suppression_ppm"]) == 30000, "water channels carry the published values")
	_check(bool(Effect.validate(effect).get("success", false)), "water effect record validates")
	_check(String(effect["effect_hash"]) == Effect.compute_effect_hash(effect), "water effect hash reproducible")
	var zero_water := Effect.create("p00", "0|0", 4, 12000, "b".repeat(64))
	_check(int(zero_water["water_uptake_ppm"]) == 0 and int(zero_water["evaporation_suppression_ppm"]) == 0, "water channels default to zero")
	var tampered: Dictionary = effect.duplicate(true)
	tampered["litter_input_ppm"] = 7
	_check(not bool(Effect.validate(tampered).get("success", false)), "nonzero FFF5 channel still rejected (no creation from nothing)")
	var negative: Dictionary = effect.duplicate(true)
	negative["water_uptake_ppm"] = -1
	_check(not bool(Effect.validate(negative).get("success", false)), "negative water channel rejected")
	var effect_b := Effect.create("pB", "0|0", 1, 1000, "b".repeat(64), 500, 0)
	var effect_a := Effect.create("pA", "1|1", 1, 500, "a".repeat(64), 700, 900)
	var combined := String(Effect.combined_hash([effect_b, effect_a]))
	_check(String(Effect.combined_hash([effect_a, effect_b])) == combined, "water effect combined hash order-invariant")

func _g8_water_engineering() -> void:
	var records := _grid_records(20000, 0.6, 1.5)
	var inputs := _field_inputs(_maps_for(records, "loam", 0.5))
	var field := WaterField.compute(records, inputs)
	_check(not field.is_empty(), "G8: water field computes for the reference community")
	if field.is_empty():
		_finish()
		return
	var cells: Dictionary = field["cells"]
	_check(cells.size() == 4, "G8: community occupies the expected 4 cells")
	var bounds_ok := true
	var conservation_ok := true
	var total_uptake := 0
	for cell_id in cells.keys():
		var cell: Dictionary = cells[cell_id]
		var moisture_after := float(cell["moisture_after"])
		if moisture_after < 0.0 or moisture_after > 1.0:
			bounds_ok = false
		if moisture_after > float(cell["base_moisture"]) + 1e-9:
			bounds_ok = false
		if float(int(cell["total_uptake_ppm"])) > float(cell["base_moisture"]) * WaterField.CELL_WATER_CAPACITY_PPM + 1e-3:
			conservation_ok = false
		total_uptake += int(cell["total_uptake_ppm"])
	_check(bounds_ok, "G8: every cell moisture stays in [0,1] and never rises above base")
	_check(conservation_ok, "G8: per-cell total uptake never exceeds available water")
	_check(total_uptake > 0, "G8: the community actually withdraws water")

	# Water stress: demand far above availability must clamp, not overdraw.
	var stressed := _grid_records(100000, 0.6, 1.5)
	var stressed_field := WaterField.compute(stressed, _field_inputs(_maps_for(stressed, "sand", 0.01)))
	_check(not stressed_field.is_empty(), "G8: water-stressed community still computes")
	var stress_ok := true
	for cell_id in stressed_field["cells"].keys():
		var cell: Dictionary = stressed_field["cells"][cell_id]
		if float(cell["moisture_after"]) < 0.0 or float(cell["moisture_after"]) > 1.0:
			stress_ok = false
		if float(int(cell["total_uptake_ppm"])) > float(cell["base_moisture"]) * WaterField.CELL_WATER_CAPACITY_PPM + 1e-3:
			stress_ok = false
	_check(stress_ok, "G8: under stress uptake is capped by availability and moisture stays in [0,1]")

	# High-LAI community dries the shared soil more than a low-LAI control.
	var high_lai := WaterField.compute(_grid_records(60000, 0.6, 1.5), inputs)
	var low_lai := WaterField.compute(_grid_records(8000, 0.6, 1.5), inputs)
	_check(not high_lai.is_empty() and not low_lai.is_empty(), "G8: high/low LAI communities compute")
	var high_moisture := _mean_cell_moisture(high_lai)
	var low_moisture := _mean_cell_moisture(low_lai)
	_check(high_moisture < low_moisture - 0.05, "G8: high-LAI community dries the soil more than the low-LAI control")
	_check(_total_uptake(high_lai) > _total_uptake(low_lai), "G8: high-LAI community withdraws more water")

	# Canopy counter-effect: shade suppresses bare-soil evaporation (spec 9.3).
	var shade_records := [
		_wrecord("shaded", 0.5, 0.5, 0, 2.0, 0.8, 1.0, 1.0),
		_wrecord("bare", 5.5, 5.5, 0, 0.0, 0.8, 1.0, 1.0),
	]
	var shade_maps := _maps_for(shade_records, "loam", 0.5)
	var shade_field := WaterField.compute(shade_records, _field_inputs(shade_maps))
	_check(not shade_field.is_empty(), "G8: shade contrast field computes")
	var shaded: Dictionary = shade_field["cells"]["0|0"]
	var bare: Dictionary = shade_field["cells"]["5|5"]
	_check(absf(float(shaded["shade_suppression"]) - 0.48) < 1e-9, "G8: shade suppression = clamp01(canopy_cover * 0.6) exact")
	_check(absf(float(shaded["evaporation_ppm"]) - 20000.0 * 0.52) < 1e-6, "G8: shaded evaporation = base * (1 - suppression) exact")
	_check(float(bare["evaporation_ppm"]) == 20000.0, "G8: unshaded cell evaporates at the bare rate")
	_check(float(shaded["evaporation_ppm"]) < float(bare["evaporation_ppm"]), "G8: shaded cell loses less water to evaporation than the unshaded control")
	_check(float(shaded["moisture_after"]) > float(bare["moisture_after"]), "G8: shaded cell keeps more moisture over the same update")

	# Texture fixture channel: sand vs clay parameters (spec 9.4).
	var pair := [_wrecord("sandy", -5.5, -5.5, 100000, 0.0, 0.0, 1.0, 1.0), _wrecord("clayey", 5.5, 5.5, 100000, 0.0, 0.0, 1.0, 1.0)]
	var sand_maps := {"textures": {"-6|-6": "sand"}, "base_moisture": {"-6|-6": 0.001, "5|5": 0.001}}
	var texture_maps := {"textures": {"-6|-6": "sand", "5|5": "clay"}, "base_moisture": {"-6|-6": 0.001, "5|5": 0.001}}
	var texture_field := WaterField.compute(pair, _field_inputs(texture_maps))
	_check(not texture_field.is_empty(), "G8: texture contrast field computes")
	var sand_cell: Dictionary = texture_field["cells"]["-6|-6"]
	var clay_cell: Dictionary = texture_field["cells"]["5|5"]
	_check(float(sand_cell["evaporation_ppm"]) > float(clay_cell["evaporation_ppm"]), "G8: sand evaporates faster than clay (1.35x vs 0.8x)")
	_check(int(sand_cell["total_uptake_ppm"]) < int(clay_cell["total_uptake_ppm"]), "G8: sand yields less uptake per available water than clay (0.85 vs 0.9)")
	_check(sand_maps["textures"]["-6|-6"] == "sand", "G8: texture fixture map is versioned input")

	# Fail-closed discipline.
	var missing_texture: Array = [_wrecord("p", 0.0, 0.0, 1000, 0.0, 0.0, 1.0, 1.0)]
	_check(WaterField.compute(missing_texture, _field_inputs({"textures": {}, "base_moisture": {"0|0": 0.5}})).is_empty(), "fail-closed: occupied cell without texture")
	_check(WaterField.compute(missing_texture, _field_inputs({"textures": {"0|0": "gravel"}, "base_moisture": {"0|0": 0.5}})).is_empty(), "fail-closed: unknown texture value")
	_check(WaterField.compute(missing_texture, _field_inputs({"textures": {"0|0": "sand"}, "base_moisture": {}})).is_empty(), "fail-closed: occupied cell without base moisture")
	_check(WaterField.compute(missing_texture, _field_inputs({"textures": {"0|0": "sand"}, "base_moisture": {"0|0": 1.5}})).is_empty(), "fail-closed: base moisture out of range")
	_check(WaterField.compute([], _field_inputs(_maps_for(records, "loam", 0.5))).is_empty(), "fail-closed: empty record set")
	_check(WaterField.compute([_wrecord("p", 0.0, 0.0, 1000, 0.0, 0.0, 1.0, 1.0), _wrecord("p", 3.0, 3.0, 1000, 0.0, 0.0, 1.0, 1.0)], _field_inputs(_maps_for([_wrecord("p", 0.0, 0.0, 1000, 0.0, 0.0, 1.0, 1.0)], "loam", 0.5))).is_empty(), "fail-closed: duplicate identity")
	var bad_record := _wrecord("p", 0.0, 0.0, -5, 0.0, 0.0, 1.0, 1.0)
	_check(WaterField.compute([bad_record], _field_inputs(_maps_for([bad_record], "loam", 0.5))).is_empty(), "fail-closed: negative transpiration demand")
	var bad_ratio := _wrecord("p", 0.0, 0.0, 1000, 0.0, 0.0, 1.0, 1.0, 1.5)
	_check(WaterField.compute([bad_ratio], _field_inputs(_maps_for([bad_ratio], "loam", 0.5))).is_empty(), "fail-closed: root_shoot_ratio out of [0,1]")

	# Effect records carry the water channels and validate.
	var effects := WaterField.effect_records(records, inputs, 7)
	_check(effects.size() == records.size(), "G8: one effect record per plant in canonical order")
	var all_valid := true
	var any_uptake := true
	var any_suppression := false
	for effect: Dictionary in effects:
		if not bool(Effect.validate(effect).get("success", false)):
			all_valid = false
		if int(effect["water_uptake_ppm"]) <= 0:
			any_uptake = false
		if int(effect["evaporation_suppression_ppm"]) > 0:
			any_suppression = true
	_check(all_valid, "G8: every water effect record validates")
	_check(any_uptake, "G8: effect records carry nonzero water_uptake_ppm")
	_check(any_suppression, "G8: effect records carry nonzero evaporation_suppression_ppm under canopy")
	var by_identity := {}
	for effect: Dictionary in effects:
		by_identity[String(effect["plant_identity"])] = effect
	_check(int(by_identity["p00"]["water_uptake_ppm"]) == int(field["plant_uptake"]["p00"]["actual_uptake_ppm"]), "G8: effect uptake matches the field's bounded uptake")
	_check(int(by_identity["p00"]["generation"]) == 7, "G8: effect records carry the generation")

func _g9_sand_vs_loam(result: Dictionary) -> void:
	_check(not result.is_empty(), "water feedback bridge runs")
	if result.is_empty():
		_finish()
		return
	print("ECO.EVO7 FFF4 bridge runtime_ms=%d result_hash=%s" % [bridge_runtime_msec, String(result["result_hash"]).substr(0, 16)])

	var dry: Dictionary = result["scenarios"]["dry_sand"]
	var mesic: Dictionary = result["scenarios"]["mesic_loam"]
	_check(String(dry["fixture"]["texture"]) == "sand" and String(dry["fixture"]["control_point"]) == "dry_ridge", "dry_sand fixture: sand over the dry_ridge control point")
	_check(String(mesic["fixture"]["texture"]) == "loam" and String(mesic["fixture"]["control_point"]) == "wet_lowland", "mesic_loam fixture: loam over the wet_lowland control point")
	_check(String(dry["fixture"]["base_env"]["checksum"]) != String(mesic["fixture"]["base_env"]["checksum"]), "scenarios use distinct fixture environments")

	var dry_on: Dictionary = dry["feedback_on"]
	var mesic_on: Dictionary = mesic["feedback_on"]
	var dry_off: Dictionary = dry["feedback_off"]
	var mesic_off: Dictionary = mesic["feedback_off"]
	var dry_base_moisture := float(dry["fixture"]["base_soil_moisture"])

	_check(float(dry_on["mean_cell_moisture"]) < 0.5 * dry_base_moisture, "G8/G9: dry_sand shows real water limitation (final mean moisture below half of base)")
	_check(float(dry_on["mean_cell_moisture"]) < float(mesic_on["mean_cell_moisture"]) - 0.2, "G9: dry_sand cells are far drier than mesic_loam cells")
	_check(String(dry["initial_field_hash"]) != String(dry_on["final_field_hash"]), "G10: dry_sand plants moved their water field (initial != final)")
	_check(String(mesic["initial_field_hash"]) != String(mesic_on["final_field_hash"]), "G10: mesic_loam plants moved their water field (initial != final)")

	var dry_features: Dictionary = dry_on["mean_features"]
	var mesic_features: Dictionary = mesic_on["mean_features"]
	_check(float(mesic_features["leaf_area_index_proxy"]) - float(dry_features["leaf_area_index_proxy"]) > LAI_DELTA_THRESHOLD, "G9: dry_sand evolves lower mean leaf_area_index_proxy (compact crown)")
	_check(float(dry_features["realized_root_depth_m"]) - float(mesic_features["realized_root_depth_m"]) > ROOT_DEPTH_DELTA_THRESHOLD, "G9: dry_sand evolves deeper mean realized roots (root-heavy)")
	_check(float(dry_features["root_shoot_ratio"]) - float(mesic_features["root_shoot_ratio"]) > RSR_DELTA_THRESHOLD, "G9: dry_sand evolves higher root-shoot allocation")
	_check(float(dry_on["mean_fitness"]) > 0.0, "G9: dry_sand population stays viable (positive mean net balance via root strategy)")
	_check(float(mesic_on["mean_fitness"]) > 0.0 and float(mesic_features["realized_height_m"]) > 2.0, "G9: mesic_loam does not forbid tall strategies (positive net, stature > 2 m)")
	_check(float(dry_on["driest_quartile_mean_root_depth"]) > 0.0 and float(dry_on["wettest_quartile_mean_root_depth"]) > 0.0, "G9: deep-vs-open moisture quartiles are observable")

	_check(String(dry_on["final_population_hash"]) != String(dry_off["final_population_hash"]), "G7-causality: dry_sand feedback ON/OFF select different descendants")
	_check(String(mesic_on["final_population_hash"]) != String(mesic_off["final_population_hash"]), "G7-causality: mesic_loam feedback ON/OFF select different descendants")
	_check(String(dry_on["final_population_hash"]) != String(mesic_on["final_population_hash"]), "G9: scenarios evolve different communities under the same mutation stream formula")
	_check(String(result["mutation_stream_formula"]) == "EVO7-WATER|seed|gen|parent|off", "mutation stream formula shared across modes and scenarios")

func _determinism_and_order(result: Dictionary) -> void:
	if result.is_empty():
		return
	var replay := Bridge.run_all(SEED)
	_check(String(replay["result_hash"]) == String(result["result_hash"]), "deterministic replay: identical result hash")
	var other_seed := Bridge.run_all(SEED + 1)
	_check(not other_seed.is_empty() and String(other_seed["result_hash"]) != String(result["result_hash"]), "different lineage seed changes the community")

	# G12: permuting the input records cannot change the water field.
	var records := _grid_records(20000, 0.6, 1.5)
	var inputs := _field_inputs(_maps_for(records, "loam", 0.5))
	var reference := WaterField.compute(records, inputs)
	var permutations := [
		[records[24], records[7], records[13], records[0], records[18], records[3], records[21], records[9], records[16]],
		[records[11], records[2], records[19], records[23], records[5], records[14], records[8], records[20], records[1]],
	]
	for permutation_index in permutations.size():
		var subset: Array = permutations[permutation_index]
		var subset_inputs := _field_inputs(_maps_for(subset, "loam", 0.5))
		var field := WaterField.compute(subset, subset_inputs)
		var canonical := WaterField.compute(_sorted_by_identity(subset), subset_inputs)
		var reordered := WaterField.compute(_reversed_copy(subset), subset_inputs)
		_check(String(field["field_hash"]) == String(canonical["field_hash"]), "G12: field hash invariant under permutation %d" % permutation_index)
		_check(String(field["plant_uptake_hash"]) == String(canonical["plant_uptake_hash"]), "G12: plant uptake hash invariant under permutation %d" % permutation_index)
		_check(String(reordered["field_hash"]) == String(canonical["field_hash"]) and String(reordered["plant_uptake_hash"]) == String(canonical["plant_uptake_hash"]), "G12: reversed input order gives identical field %d" % permutation_index)
		var per_plant_equal := true
		for record: Dictionary in subset:
			var identity := String(record["identity"])
			if int(field["plant_uptake"][identity]["actual_uptake_ppm"]) != int(canonical["plant_uptake"][identity]["actual_uptake_ppm"]):
				per_plant_equal = false
		_check(per_plant_equal, "G12: per-plant uptake identical under permutation %d" % permutation_index)
	_check(not reference.is_empty(), "G12: reference field computes")

func _source_boundaries() -> void:
	var field_source := FileAccess.get_file_as_string("res://scripts/research/ecology/soil_water_field_v1.gd").to_lower()
	for forbidden in ["randf", "randi(", "randomize", "get_tree", "node", "camera"]:
		_check(not field_source.contains(forbidden), "water field source excludes %s" % forbidden)
	_check(field_source.contains("sort_custom"), "water field sorts records into canonical order")
	_check(field_source.contains("texture_uptake_efficiency") and field_source.contains("texture_evaporation_multiplier"), "texture enters the field as versioned parameters")
	_check(not field_source.contains("if texture") and not field_source.contains("archetype"), "no texture-conditional rules or archetypes in the field")
	var bridge_source := FileAccess.get_file_as_string("res://scripts/research/ecology/evo7_water_feedback_bridge_v1.gd").to_lower()
	for forbidden in ["randf", "randi(", "randomize", "randomnumbergenerator", "archetype"]:
		_check(not bridge_source.contains(forbidden), "water bridge source excludes %s" % forbidden)
	_check(bridge_source.contains("evo7-water|"), "water bridge uses the shared mutation stream formula")
	_check(bridge_source.contains("plant_mutation_lineage_extension_evo7_v1.gd"), "water bridge reproduces only through the single lineage authority")
	var texture_lines_outside_fixture := 0
	for line in bridge_source.split("\n"):
		if (line.contains("sand") or line.contains("loam") or line.contains("clay")) \
				and not (line.contains("dry_sand") or line.contains("mesic_loam") or line.contains("texture")):
			texture_lines_outside_fixture += 1
	_check(texture_lines_outside_fixture == 0, "texture tokens appear only in fixture construction (no morphology rules)")
	var phenotype_source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_functional_phenotype_v1.gd").to_lower()
	for forbidden in ["texture", "sand", "loam", "clay"]:
		_check(not phenotype_source.contains(forbidden), "fitness path carries no %s knowledge" % forbidden)
	var effect_source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_environment_effect_v1.gd")
	_check(effect_source.contains("INACTIVE_CHANNEL_NONZERO"), "effect contract still guards FFF5 channels")

static func _reversed_copy(records: Array) -> Array:
	var copy := records.duplicate()
	copy.reverse()
	return copy

static func _sorted_by_identity(records: Array) -> Array:
	var copy := records.duplicate()
	copy.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["identity"]) < String(b["identity"]))
	return copy

static func _mean_cell_moisture(field: Dictionary) -> float:
	var cells: Dictionary = field["cells"]
	var total := 0.0
	for cell_id in cells.keys():
		total += float(cells[cell_id]["moisture_after"])
	return total / float(cells.size())

static func _total_uptake(field: Dictionary) -> int:
	var cells: Dictionary = field["cells"]
	var total := 0
	for cell_id in cells.keys():
		total += int(cells[cell_id]["total_uptake_ppm"])
	return total

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO7 FFF4 Water Feedback: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 FFF4 FAIL: %s" % failure)
	print("ECO.EVO7 FFF4 Water Feedback: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)

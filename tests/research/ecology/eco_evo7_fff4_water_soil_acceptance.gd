extends SceneTree

const WaterField = preload("res://scripts/research/ecology/soil_water_field_v1.gd")
const EffectV2 = preload("res://scripts/research/ecology/plant_environment_effect_v2.gd")
const Bridge = preload("res://scripts/research/ecology/evo7_water_soil_feedback_bridge_v1.gd")

const SEED := 20260823
var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_effect_v2_contract()
	_water_budget_and_texture()
	_order_invariance()
	_g8_g9_evolution()
	_multiseed_direction()
	_source_boundaries()
	_finish()

static func _record(identity: String, depth: float, spread: float, rsr: float, lai: float, demand: int, shade: int) -> Dictionary:
	return {
		"identity":identity, "cell_identity":"cell-0",
		"realized_root_depth_m":depth, "realized_root_spread_m":spread,
		"root_shoot_ratio":rsr, "leaf_area_index_proxy":lai,
		"transpiration_demand_ppm":demand, "shade_output_ppm":shade,
		"source_phenotype_hash":identity.sha256_text(),
	}

func _effect_v2_contract() -> void:
	var effect := EffectV2.create("p0", "cell-0", 2, 12000, 34000, 5000, "a".repeat(64))
	_check(not effect.is_empty(), "FFF4 effect v2 created")
	_check(bool(EffectV2.validate(effect).get("success", false)), "FFF4 effect v2 validates")
	_check(int(effect["water_uptake_ppm"]) == 34000, "water uptake channel active")
	_check(int(effect["evaporation_suppression_ppm"]) == 5000, "evaporation suppression channel active")
	_check(int(effect["litter_input_ppm"]) == 0 and int(effect["soil_binding_ppm"]) == 0, "FFF5 channels remain inactive")
	var illegal := effect.duplicate(true)
	illegal["litter_input_ppm"] = 1
	illegal["effect_hash"] = EffectV2.compute_effect_hash(illegal)
	_check(not bool(EffectV2.validate(illegal).get("success", false)), "FFF5 channel cannot activate early")

func _water_budget_and_texture() -> void:
	var shallow := _record("a", 0.5, 0.5, 0.35, 1.2, 120000, 20000)
	var deep := _record("b", 2.5, 2.0, 0.70, 0.6, 70000, 10000)
	var dry := WaterField.compute(180000, "sand", 0.95, [shallow, deep], 1)
	_check(not dry.is_empty(), "G8 water field computes")
	var available_for_plants := int(dry["available_before_ppm"]) - int(dry["evaporation_loss_ppm"])
	_check(int(dry["total_uptake_ppm"]) <= available_for_plants, "G8: sum uptake <= available after evaporation")
	_check(int(dry["water_after_ppm"]) >= 0, "G8: water never negative")
	_check(float(dry["plant_water"]["b"]["water_satisfaction"]) > float(dry["plant_water"]["a"]["water_satisfaction"]), "G8: deeper/root-heavy strategy has stronger dry access")

	var sand := WaterField.compute(400000, "sand", 0.8, [shallow, deep], 1)
	var loam := WaterField.compute(400000, "loam", 0.8, [shallow, deep], 1)
	var clay := WaterField.compute(400000, "clay", 0.8, [shallow, deep], 1)
	_check(int(sand["available_before_ppm"]) < int(loam["available_before_ppm"]), "texture: sand retains less than loam")
	_check(int(loam["available_before_ppm"]) < int(clay["available_before_ppm"]), "texture: clay retains more than loam")

	var no_shade := _record("n", 1.0, 1.0, 0.5, 0.2, 80000, 0)
	var canopy := _record("c", 1.0, 1.0, 0.5, 2.5, 80000, 180000)
	var open_field := WaterField.compute(500000, "loam", 0.9, [no_shade], 1)
	var canopy_field := WaterField.compute(500000, "loam", 0.9, [canopy], 1)
	_check(int(canopy_field["evaporation_loss_ppm"]) < int(open_field["evaporation_loss_ppm"]), "G8: canopy suppresses bare-soil evaporation")

func _order_invariance() -> void:
	var records := [
		_record("c", 1.0, 0.7, 0.45, 1.0, 90000, 30000),
		_record("a", 2.0, 1.6, 0.65, 0.6, 75000, 14000),
		_record("b", 0.7, 0.9, 0.40, 1.5, 125000, 45000),
	]
	var a := WaterField.compute(310000, "sand", 0.92, records, 4)
	var b := WaterField.compute(310000, "sand", 0.92, [records[2], records[0], records[1]], 4)
	_check(String(a["field_hash"]) == String(b["field_hash"]), "G12: soil-water field hash order invariant")
	_check(String(a["effects_hash"]) == String(b["effects_hash"]), "G12: water effects hash order invariant")

func _g8_g9_evolution() -> void:
	var result := Bridge.run_all(SEED)
	_check(not result.is_empty(), "FFF4 bridge runs")
	if result.is_empty():
		return
	var dry: Dictionary = result["scenarios"]["dry_sand"]
	var mesic: Dictionary = result["scenarios"]["mesic_loam"]
	_check(String(result["common_first_candidate_pool_hash"]).length() == 64, "G4: common generation-one mutation pool")
	_check(String(dry["final_population_hash"]) != String(mesic["final_population_hash"]), "G9: dry-sand and mesic-loam select different descendants")
	_check(float(dry["mean_water_satisfaction"]) < float(mesic["mean_water_satisfaction"]), "G8: dry sand imposes stronger water limitation")
	_check(float(dry["mean_features"]["leaf_area_index_proxy"]) < float(mesic["mean_features"]["leaf_area_index_proxy"]), "G9: dry sand selects lower leaf area")
	var root_heavier := float(dry["mean_features"]["realized_root_depth_m"]) > float(mesic["mean_features"]["realized_root_depth_m"]) or float(dry["mean_features"]["root_shoot_ratio"]) > float(mesic["mean_features"]["root_shoot_ratio"])
	_check(root_heavier, "G9: dry sand selects a root-heavier strategy")
	_check(float(mesic["mean_features"]["realized_height_m"]) > 0.5, "G9: mesic loam does not hard-forbid tall growth")
	var replay := Bridge.run_all(SEED)
	_check(String(replay["result_hash"]) == String(result["result_hash"]), "FFF4 deterministic replay")

func _multiseed_direction() -> void:
	var directional_passes := 0
	for seed in [SEED, SEED + 1, SEED + 2]:
		var result := Bridge.run_all(seed, 20, 14, 3)
		if result.is_empty():
			continue
		var dry: Dictionary = result["scenarios"]["dry_sand"]
		var mesic: Dictionary = result["scenarios"]["mesic_loam"]
		var lower_lai := float(dry["mean_features"]["leaf_area_index_proxy"]) < float(mesic["mean_features"]["leaf_area_index_proxy"])
		var root_heavier := float(dry["mean_features"]["realized_root_depth_m"]) > float(mesic["mean_features"]["realized_root_depth_m"]) or float(dry["mean_features"]["root_shoot_ratio"]) > float(mesic["mean_features"]["root_shoot_ratio"])
		if lower_lai and root_heavier:
			directional_passes += 1
	_check(directional_passes >= 2, "FFF4 multiseed: dry compact/root-heavy direction holds in >=2/3 seeds")

func _source_boundaries() -> void:
	var water_source := FileAccess.get_file_as_string("res://scripts/research/ecology/soil_water_field_v1.gd").to_lower()
	for forbidden in ["randf", "randi(", "randomize", "get_tree", "node3d"]:
		_check(not water_source.contains(forbidden), "water field excludes %s" % forbidden)
	_check(water_source.contains("total_uptake > water_for_plants"), "water field contains structural conservation fence")
	var bridge_source := FileAccess.get_file_as_string("res://scripts/research/ecology/evo7_water_soil_feedback_bridge_v1.gd")
	_check(bridge_source.contains("LineageExtension.reproduce_bundle"), "FFF4 uses the single EVO7 lineage extension")
	_check(not bridge_source.contains("Kernel.reproduce"), "FFF4 has no second direct mutation path")
	var old_effect_source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_environment_effect_v1.gd")
	_check(old_effect_source.contains("ACTIVE_CHANNELS: Array[String] = [\"shade_ppm\"]"), "FFF3 shade-only v1 remains unchanged")

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO7 FFF4 Water + Soil Texture Feedback: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 FFF4 FAIL: %s" % failure)
	print("ECO.EVO7 FFF4 Water + Soil Texture Feedback: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
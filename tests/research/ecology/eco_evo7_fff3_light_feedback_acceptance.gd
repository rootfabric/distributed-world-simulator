extends SceneTree

## ECO.EVO7 FFF3 - light feedback acceptance.
## Gates: G6 tall canopy changes light (add/remove/monotonicity/vertical rule);
## G7 feedback ON/OFF changes selected descendants with the same mutation stream;
## G10 closed-loop causality through the community; G12 aggregation order invariance.

const LightField = preload("res://scripts/research/ecology/understory_light_field_v1.gd")
const Effect = preload("res://scripts/research/ecology/plant_environment_effect_v1.gd")
const Bridge = preload("res://scripts/research/ecology/evo7_light_feedback_bridge_v1.gd")

const SEED := 20260823

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_effect_contract()
	_g6_canopy_changes_light()
	_g12_order_invariance()
	_g7_g10_light_feedback_loop()
	_source_boundaries()
	_finish()

static func _record(identity: String, x: float, z: float, height: float, radius: float, lai: float, base_sunlight := 0.8) -> Dictionary:
	return {
		"identity": identity,
		"world_x_m": x,
		"world_z_m": z,
		"realized_height_m": height,
		"realized_crown_radius_m": radius,
		"realized_crown_density": 0.5,
		"leaf_area_index_proxy": lai,
		"base_sunlight": base_sunlight,
		"shade_output_ppm": 1000,
		"source_phenotype_hash": "a".repeat(64),
	}

func _effect_contract() -> void:
	var effect := Effect.create("p00", "0|0", 3, 15000, "b".repeat(64))
	_check(not effect.is_empty(), "effect record created")
	_check(bool(Effect.validate(effect).get("success", false)), "effect record validates")
	_check(int(effect["water_uptake_ppm"]) == 0 and int(effect["litter_input_ppm"]) == 0, "inactive channels are zero in R1")
	_check(String(effect["effect_hash"]) == Effect.compute_effect_hash(effect), "effect hash reproducible")
	var tampered: Dictionary = effect.duplicate(true)
	tampered["litter_input_ppm"] = 5
	_check(not bool(Effect.validate(tampered).get("success", false)), "nonzero inactive channel rejected (no creation from nothing)")
	var negative: Dictionary = effect.duplicate(true)
	negative["shade_ppm"] = -1
	_check(not bool(Effect.validate(negative).get("success", false)), "negative channel rejected")
	var effect_b := Effect.create("pB", "0|0", 1, 1000, "b".repeat(64))
	var effect_a := Effect.create("pA", "1|1", 1, 500, "a".repeat(64))
	_check(not effect_b.is_empty() and not effect_a.is_empty(), "effect records for two plants created")
	var combined := String(Effect.combined_hash([effect_b, effect_a]))
	var shuffled := [effect_a, effect_b]
	_check(String(Effect.combined_hash(shuffled)) == combined, "effect combined hash order-invariant")
	var sorted_records: Array = Effect.canonical_sort([effect_b, effect_a])
	_check(String(sorted_records[0]["plant_identity"]) == "pA", "canonical order sorts by plant identity")

func _g6_canopy_changes_light() -> void:
	var small := _record("small", 0.5, 0.5, 0.5, 0.4, 0.2)
	var tall := _record("tall", 0.0, 0.0, 5.0, 1.2, 1.2)

	var with_canopy := LightField.compute([small.duplicate(true), tall.duplicate(true)])
	_check(not with_canopy.is_empty(), "field with canopy computes")
	var shaded_light := float(with_canopy["plant_light"]["small"]["understory_light"])
	_check(shaded_light < 0.8, "G6: tall canopy reduces understory light below base")

	var without_canopy := LightField.compute([small.duplicate(true)])
	var restored_light := float(without_canopy["plant_light"]["small"]["understory_light"])
	_check(absf(restored_light - 0.8) < 1e-9, "G6: canopy removal restores base light exactly")
	_check(String(with_canopy["field_hash"]) != String(without_canopy["field_hash"]), "G6: field hash tracks canopy presence")

	var tall2 := _record("tall2", 1.0, 0.0, 6.0, 1.2, 1.2)
	var double_canopy := LightField.compute([small.duplicate(true), tall.duplicate(true), tall2.duplicate(true)])
	var double_light := float(double_canopy["plant_light"]["small"]["understory_light"])
	_check(double_light < shaded_light, "G6: more canopy is monotonically darker (Beer-Lambert)")

	var expected := 0.8 * exp(-LightField.EXTINCTION_K * float(with_canopy["plant_light"]["small"]["overlap_lai"]))
	_check(absf(shaded_light - expected) < 1e-6, "G6: Beer-Lambert transmittance exact")

	var only_short := LightField.compute([_record("small_a", 0.0, 0.0, 0.4, 0.5, 0.3), _record("tall_target", 0.5, 0.5, 5.0, 0.5, 0.3)])
	_check(absf(float(only_short["plant_light"]["tall_target"]["understory_light"]) - 0.8) < 1e-9, "G6 vertical rule: short plants never shade a taller one")

	var equal_height := LightField.compute([_record("eq_a", 0.0, 0.0, 2.0, 1.0, 0.8), _record("eq_b", 0.3, 0.3, 2.0, 1.0, 0.8)])
	_check(absf(float(equal_height["plant_light"]["eq_a"]["understory_light"]) - 0.8) < 1e-9, "G6 vertical rule: equal-height plants do not shade each other (R1)")

	_check(LightField.compute([]).is_empty(), "empty record set fails closed")
	_check(LightField.compute([_record("p", 0.0, 0.0, 1.0, 1.0, 0.2), _record("p", 1.0, 1.0, 1.0, 1.0, 0.2)]).is_empty(), "duplicate identity fails closed")
	var bad_record := _record("p", 0.0, 0.0, 1.0, 1.0, 0.2)
	bad_record["realized_crown_density"] = 1.5
	_check(LightField.compute([bad_record]).is_empty(), "out-of-range record fails closed")

func _g12_order_invariance() -> void:
	var records := [
		_record("pC", 0.0, 0.0, 3.0, 1.0, 0.9),
		_record("pA", 0.5, 0.2, 1.0, 0.8, 0.4),
		_record("pB", -0.4, 0.6, 2.0, 0.9, 0.6),
		_record("pD", 0.9, -0.7, 4.0, 1.1, 0.7),
		_record("pE", 0.2, -0.2, 0.8, 0.5, 0.3),
	]
	var reference := LightField.compute(records)
	_check(not reference.is_empty(), "reference field computes")
	var permutations := [
		[records[4], records[2], records[0], records[3], records[1]],
		[records[3], records[1], records[4], records[0], records[2]],
		[records[2], records[4], records[1], records[3], records[0]],
	]
	for permutation_index in permutations.size():
		var shuffled: Array = permutations[permutation_index]
		var field := LightField.compute(shuffled)
		_check(String(field["field_hash"]) == String(reference["field_hash"]),
			"G12: field hash invariant under permutation %d" % permutation_index)
		_check(String(field["plant_light_hash"]) == String(reference["plant_light_hash"]),
			"G12: plant light hash invariant under permutation %d" % permutation_index)
		var all_lights_equal := true
		for identity in ["pA", "pB", "pC", "pD", "pE"]:
			if absf(float(field["plant_light"][identity]["understory_light"]) - float(reference["plant_light"][identity]["understory_light"])) > 0.0:
				all_lights_equal = false
		_check(all_lights_equal, "G12: per-plant light identical under permutation %d" % permutation_index)

func _g7_g10_light_feedback_loop() -> void:
	var started := Time.get_ticks_msec()
	var result := Bridge.run_all(SEED)
	_check(not result.is_empty(), "light feedback bridge runs")
	if result.is_empty():
		_finish()
		return
	var elapsed := Time.get_ticks_msec() - started
	print("ECO.EVO7 FFF3 bridge runtime_ms=%d result_hash=%s" % [elapsed, String(result["result_hash"]).substr(0, 16)])

	var on: Dictionary = result["feedback_on"]
	var off: Dictionary = result["feedback_off"]
	_check(String(on["final_population_hash"]) != String(off["final_population_hash"]), "G7: feedback ON/OFF select different descendants")
	_check(String(result["initial_field_hash"]) != String(on["final_field_hash"]), "G10: closed loop moves the light field (initial != final)")
	_check(float(on["mean_understory_light"]) < float(result["base_sunlight"]) - 0.05, "G10: canopy darkens the ground layer (mean understory < base - 0.05)")
	_check(float(on["deep_shade_mean_lai"]) < float(on["open_light_mean_lai"]) - 0.03, "G7: understory form emerges - deep-shade plants carry less leaf area than open-light plants")
	_check(float(on["mean_understory_light"]) != float(off["mean_understory_light"]) or String(on["final_field_hash"]) != String(off["final_field_hash"]), "G7: ON and OFF environments diverge")

	var replay := Bridge.run_all(SEED)
	_check(String(replay["result_hash"]) == String(result["result_hash"]), "deterministic replay: identical result hash")
	var other_seed := Bridge.run_all(SEED + 1)
	_check(not other_seed.is_empty() and String(other_seed["result_hash"]) != String(result["result_hash"]), "different lineage seed changes the community")

func _source_boundaries() -> void:
	var field_source := FileAccess.get_file_as_string("res://scripts/research/ecology/understory_light_field_v1.gd").to_lower()
	for forbidden in ["randf", "randi(", "randomize", "get_tree", "node", "camera"]:
		_check(not field_source.contains(forbidden), "light field source excludes %s" % forbidden)
	_check(field_source.contains("sort_custom"), "light field sorts records into canonical order")
	var bridge_source := FileAccess.get_file_as_string("res://scripts/research/ecology/evo7_light_feedback_bridge_v1.gd").to_lower()
	for forbidden in ["randf", "randi(", "randomize", "randomnumbergenerator"]:
		_check(not bridge_source.contains(forbidden), "light bridge source excludes %s" % forbidden)
	_check(bridge_source.contains("evo7-light|"), "mutation stream formula shared across feedback modes")
	var effect_source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_environment_effect_v1.gd")
	_check(effect_source.contains("INACTIVE_CHANNEL_NONZERO"), "effect contract guards inactive channels")

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO7 FFF3 Light Feedback: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 FFF3 FAIL: %s" % failure)
	print("ECO.EVO7 FFF3 Light Feedback: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)

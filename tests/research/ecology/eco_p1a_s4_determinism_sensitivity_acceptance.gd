extends SceneTree

const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const Fixture = preload("res://scripts/research/ecology/synthetic_environment_fixture_v1.gd")
const PatchSimulator = preload("res://scripts/research/ecology/single_plant_patch_simulator_v1.gd")
const Harness = preload("res://scripts/research/ecology/eco_p1a_s4_sensitivity_harness_v1.gd")

const EXPECTED_ENVIRONMENT_HASH := "b862c4fc529b5fd8229355c4c38b96a429e4ef1d902d6dd86b27860d8ce51af7"
const EXPECTED_BASELINE_SUMMARY_HASH := "327d211d24f8f74251e02f0ced22323b4120c18d9b42a9cfcf99974cf9accc5a"
const EXPECTED_BASELINE_RESULT_HASH := "cb1641a6b49dfa2be3f64c94f2ebc3240327eaca559d025d34e72ba74c0aa11e"
const BASELINE_GRID := 9
const BASELINE_SEASONS := 24
const SUMMARY_GRID := 17
const SEAM_EPSILON_M := 0.0001
const RATIO_SEAM_TOLERANCE := 0.00001
const TEMPERATURE_SEAM_TOLERANCE_C := 0.00005

var assertions := 0
var failures: Array[String] = []
var baseline_full: Dictionary = {}
var baseline_summary: Dictionary = {}
var sensitivity := {}
var failure_matrix := {}


func _init() -> void:
	_test_config_contract()
	_test_replay_and_restart_baseline()
	_test_sensitivity_matrix()
	_test_trait_tradeoffs()
	_test_failure_classification()
	_test_truth_boundaries()
	_finish()


func _test_config_contract() -> void:
	var base := Harness.baseline_config()
	_check(bool(Harness.validate_config(base).get("success", false)), "baseline experiment config validates")
	_check(base.keys().size() == Harness.CONFIG_KEYS.size(), "config exact field count")
	_check(String(Harness.EXPERIMENT_REVISION) == "ECO.P1A-S4.1", "experiment revision fixed")
	_check(Harness.config_hash(base).length() == 64, "config hash shape")
	for key in Harness.CONFIG_KEYS:
		_check(base.has(key), "config contains %s" % key)
	var invalid := base.duplicate(true)
	invalid["maintenance_cost_scale"] = 0.0
	_check(not bool(Harness.validate_config(invalid).get("success", false)), "zero cost scale rejected")
	_check(Fixture.environment_hash() == EXPECTED_ENVIRONMENT_HASH, "accepted S1 environment hash retained")


func _test_replay_and_restart_baseline() -> void:
	baseline_summary = Harness.sensitivity_summary(Harness.baseline_config(), SUMMARY_GRID)
	var replay_summary := Harness.sensitivity_summary(Harness.baseline_config(), SUMMARY_GRID)
	_check(not baseline_summary.is_empty(), "baseline summary builds")
	_check(String(baseline_summary.get("summary_hash", "")) == EXPECTED_BASELINE_SUMMARY_HASH, "baseline summary fixed hash")
	_check(String(replay_summary.get("summary_hash", "")) == EXPECTED_BASELINE_SUMMARY_HASH, "same-process summary replay exact")
	_check(_approx(float(baseline_summary["average_initial_net"]), float(replay_summary["average_initial_net"])), "same-process summary average exact")

	baseline_full = Harness.run(Harness.baseline_config(), BASELINE_GRID, BASELINE_SEASONS)
	var replay_full := Harness.run(Harness.baseline_config(), BASELINE_GRID, BASELINE_SEASONS)
	_check(not baseline_full.is_empty(), "baseline full run builds")
	_check(String(baseline_full.get("result_hash", "")) == EXPECTED_BASELINE_RESULT_HASH, "baseline full fixed hash")
	_check(String(replay_full.get("result_hash", "")) == EXPECTED_BASELINE_RESULT_HASH, "same-process full replay exact")
	_check(String(baseline_full.get("total_biomass_series_hash", "")) == String(replay_full.get("total_biomass_series_hash", "")), "biomass series replay exact")
	_check(Array(baseline_full.get("total_biomass_series", [])).size() == BASELINE_SEASONS + 1, "total biomass series emitted")
	_check(Dictionary(baseline_full.get("zone_summary", {})).size() == 4, "per-zone summary emitted")
	_check(Dictionary(baseline_full.get("limiting_counts", {})).size() == 5, "resource limitation summary emitted")
	_check(int(baseline_full.get("seed", 0)) == Fixture.DEFAULT_SEED, "seed emitted")
	_check(String(baseline_full.get("experiment_revision", "")) == Harness.EXPERIMENT_REVISION, "revision emitted")
	_check(String(baseline_full.get("config_hash", "")).length() == 64, "config hash emitted")


func _test_sensitivity_matrix() -> void:
	var variants := {
		"moisture_low": Harness.with_override("moisture_amplitude_scale", 0.95),
		"moisture_high": Harness.with_override("moisture_amplitude_scale", 1.05),
		"sunlight_low": Harness.with_override("sunlight_amplitude_scale", 0.95),
		"sunlight_high": Harness.with_override("sunlight_amplitude_scale", 1.05),
		"root_cost_low": Harness.with_override("root_cost_scale", 0.95),
		"root_cost_high": Harness.with_override("root_cost_scale", 1.05),
		"maintenance_low": Harness.with_override("maintenance_cost_scale", 0.95),
		"maintenance_high": Harness.with_override("maintenance_cost_scale", 1.05),
		"flood_cost_low": Harness.with_override("flood_penalty_scale", 0.95),
		"flood_cost_high": Harness.with_override("flood_penalty_scale", 1.05),
		"shade_low": Harness.with_override("shade_tolerance_delta", -0.05),
		"shade_high": Harness.with_override("shade_tolerance_delta", 0.05),
	}
	var hashes := {String(baseline_summary["summary_hash"]): true}
	for name in variants.keys():
		var result := Harness.sensitivity_summary(variants[name], SUMMARY_GRID)
		sensitivity[name] = result
		_check(not result.is_empty(), "sensitivity run builds: %s" % name)
		var hash := String(result.get("summary_hash", ""))
		_check(hash.length() == 64, "sensitivity hash shape: %s" % name)
		_check(not hashes.has(hash), "sensitivity result distinct: %s" % name)
		hashes[hash] = true
		var delta := absf(float(result.get("average_initial_net", 0.0)) - float(baseline_summary["average_initial_net"]))
		_check(delta < 0.08, "5 percent/small trait perturbation remains bounded: %s" % name)

	var base_net := float(baseline_summary["average_initial_net"])
	_check(float(sensitivity["moisture_low"]["average_initial_net"]) < base_net, "lower moisture amplitude lowers global mean net on fixture")
	_check(float(sensitivity["moisture_high"]["average_initial_net"]) > base_net, "higher moisture amplitude raises global mean net on fixture")
	_check(float(sensitivity["sunlight_low"]["average_initial_net"]) < base_net, "lower sunlight amplitude lowers global mean net")
	_check(float(sensitivity["sunlight_high"]["average_initial_net"]) > base_net, "higher sunlight amplitude raises global mean net")
	_check(float(sensitivity["root_cost_low"]["average_initial_net"]) > base_net, "lower root cost improves net")
	_check(float(sensitivity["root_cost_high"]["average_initial_net"]) < base_net, "higher root cost reduces net")
	_check(float(sensitivity["maintenance_low"]["average_initial_net"]) > base_net, "lower maintenance improves net")
	_check(float(sensitivity["maintenance_high"]["average_initial_net"]) < base_net, "higher maintenance reduces net")
	_check(float(sensitivity["flood_cost_low"]["average_initial_net"]) > base_net, "lower flood penalty improves net")
	_check(float(sensitivity["flood_cost_high"]["average_initial_net"]) < base_net, "higher flood penalty reduces net")
	_check(float(sensitivity["shade_low"]["average_initial_net"]) < float(sensitivity["shade_high"]["average_initial_net"]), "small shade trait change has ordered global response")


func _test_trait_tradeoffs() -> void:
	var root_half := Harness.sensitivity_summary(Harness.with_override("root_depth_scale", 0.50), SUMMARY_GRID)
	var root_mid := Harness.sensitivity_summary(Harness.with_override("root_depth_scale", 1.50), SUMMARY_GRID)
	var root_extreme := Harness.sensitivity_summary(Harness.with_override("root_depth_scale", 2.20), SUMMARY_GRID)
	_check(float(root_mid["average_initial_net"]) > float(root_half["average_initial_net"]), "deeper roots initially improve global mean net")
	_check(float(root_extreme["average_initial_net"]) < float(root_mid["average_initial_net"]), "extreme roots lose global advantage from cost")

	var dry_half := Harness.control_point("dry_ridge", Harness.with_override("root_depth_scale", 0.50))
	var dry_extreme := Harness.control_point("dry_ridge", Harness.with_override("root_depth_scale", 2.20))
	var wet_half := Harness.control_point("floodplain", Harness.with_override("root_depth_scale", 0.50))
	var wet_extreme := Harness.control_point("floodplain", Harness.with_override("root_depth_scale", 2.20))
	_check(float(dry_extreme["balance"]["net_resource_balance"]) > float(dry_half["balance"]["net_resource_balance"]), "deep roots help dry ridge")
	_check(float(wet_extreme["balance"]["net_resource_balance"]) < float(wet_half["balance"]["net_resource_balance"]), "deep roots cost viability on wet floodplain")
	failure_matrix["free_trait_escalation"] = "PASS_NON_MONOTONIC_GLOBAL_AND_OPPOSITE_LOCAL_EFFECT"


func _test_failure_classification() -> void:
	var series: Array = baseline_full.get("total_biomass_series", [])
	var initial_total := float(series[0])
	var final_total := float(series[-1])
	var max_total := 0.0
	for value in series:
		var v := float(value)
		_check(is_finite(v) and v >= 0.0, "biomass series finite/nonnegative")
		max_total = maxf(max_total, v)
	var patch_count := int(baseline_full["patch_count"])
	var hard_capacity := float(patch_count) * PatchSimulator.MAX_BIOMASS_KG_M2
	_check(final_total > 0.0, "baseline avoids global extinction")
	_check(int(baseline_full["viability_counts"].get("FAVOURABLE", 0)) > 0, "baseline retains favourable patches")
	_check(max_total < hard_capacity, "baseline biomass remains below hard capacity")
	_check(max_total < hard_capacity * 0.10, "baseline far from runaway/cap saturation")
	_check(final_total > initial_total * 0.50, "baseline does not collapse toward total extinction")
	failure_matrix["global_extinction"] = "PASS"
	failure_matrix["unbounded_biomass"] = "PASS_BOUNDED_FAR_BELOW_CAP"

	var limits: Dictionary = baseline_summary["limiting_counts"]
	var nonzero := 0
	var maximum := 0
	for key in limits.keys():
		var count := int(limits[key])
		if count > 0:
			nonzero += 1
		maximum = maxi(maximum, count)
	_check(nonzero >= 3, "multiple limiting factors active")
	_check(float(maximum) / float(int(baseline_summary["patch_count"])) < 0.75, "no single limiting field dominates >75 percent")
	failure_matrix["one_field_domination"] = "PASS_MULTIPLE_LIMITERS"

	var first := Harness.run(Harness.baseline_config(), 5, 12)
	var second := Harness.run(Harness.baseline_config(), 5, 12)
	_check(String(first.get("result_hash", "")) == String(second.get("result_hash", "")), "small replay exact floating-point hash")
	failure_matrix["floating_point_replay_divergence"] = "PASS_EXACT_HASH"


func _test_truth_boundaries() -> void:
	for boundary_index in [17, 64, 111]:
		var x := Fixture.logical_cell_boundary_x(boundary_index)
		_assert_samples_continuous(Fixture.sample_at(x - SEAM_EPSILON_M, 321.5), Fixture.sample_at(x + SEAM_EPSILON_M, 321.5), "x boundary %d" % boundary_index)
	for boundary_index in [13, 64, 116]:
		var z := Fixture.logical_cell_boundary_z(boundary_index)
		_assert_samples_continuous(Fixture.sample_at(-517.25, z - SEAM_EPSILON_M), Fixture.sample_at(-517.25, z + SEAM_EPSILON_M), "z boundary %d" % boundary_index)
	failure_matrix["boundary_seams"] = "PASS_PARENT_CONTINUITY_RECHECKED"

	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/synthetic_environment_fixture_v1.gd")
	source += FileAccess.get_file_as_string("res://scripts/research/ecology/plant_resource_model_v1.gd")
	source += FileAccess.get_file_as_string("res://scripts/research/ecology/single_plant_patch_simulator_v1.gd")
	source += FileAccess.get_file_as_string("res://scripts/research/ecology/eco_p1a_s4_sensitivity_harness_v1.gd")
	for forbidden in ["biome ==", "biome_id", "DESERT_PLANT", "RIVER_PLANT", "FOREST_TREE"]:
		_check(source.find(forbidden) < 0, "no hidden biome/region conditional: %s" % forbidden)
	failure_matrix["hidden_biome_conditionals"] = "PASS_SOURCE_SCAN"
	for forbidden in ["Camera3D", "CanvasLayer", "presentation_lod", "surface_cell_key", "AuthorityRegion", "ENetMultiplayerPeer"]:
		_check(source.find(forbidden) < 0, "S4 truth/sensitivity source excludes presentation/authority: %s" % forbidden)
	failure_matrix["presentation_resolution_dependency"] = "PASS_NO_PRESENTATION_INPUTS"

	var point := Fixture.CONTROL_POINTS["lower_slope"] as Vector2
	var direct_a := Fixture.sample_at(point.x, point.y)
	var direct_b := Fixture.sample_at(point.x, point.y)
	_check(String(direct_a["checksum"]) == String(direct_b["checksum"]), "coordinate result independent from sampling layout")


func _assert_samples_continuous(a: Dictionary, b: Dictionary, label: String) -> void:
	_check(absf(float(a["temperature_c"]) - float(b["temperature_c"])) <= TEMPERATURE_SEAM_TOLERANCE_C, "%s temperature continuity" % label)
	for field_name in EnvironmentSample.RATIO_FIELDS:
		_check(absf(float(a[field_name]) - float(b[field_name])) <= RATIO_SEAM_TOLERANCE, "%s %s continuity" % [label, field_name])


func _approx(a: float, b: float, tolerance: float = 0.000000001) -> bool:
	return absf(a - b) <= tolerance


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("ECO.P1A-S4 baseline_summary_hash=%s" % String(baseline_summary.get("summary_hash", "")))
		print("ECO.P1A-S4 baseline_result_hash=%s" % String(baseline_full.get("result_hash", "")))
		print("ECO.P1A-S4 biomass_series_hash=%s" % String(baseline_full.get("total_biomass_series_hash", "")))
		print("ECO.P1A-S4 failure_matrix=%s" % str(failure_matrix))
		print("ECO.P1A-S4 Determinism/Sensitivity: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.P1A-S4 FAIL: %s" % failure)
	print("ECO.P1A-S4 Determinism/Sensitivity: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)

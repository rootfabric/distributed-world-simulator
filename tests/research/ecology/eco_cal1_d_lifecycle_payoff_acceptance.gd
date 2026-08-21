extends SceneTree

const Experiment = preload("res://scripts/research/ecology/plant_lifecycle_payoff_experiment_v1.gd")

const ACCEPTED_CAL1_C_HASH := "d48919f42e2da92d32b3cbb8b344cb4ba0a2357411707781725a6873f40c3f1a"
const EPSILON := 0.000000001

func _init() -> void:
	var first := Experiment.run()
	var second := Experiment.run()
	var checks := 0
	assert(not first.is_empty() and not second.is_empty()); checks += 1
	assert(String(first["aggregate_hash"]).length() == 64); checks += 1
	assert(String(first["aggregate_hash"]) == String(second["aggregate_hash"])); checks += 1
	assert(String(first["cal1_c_parent_hash"]) == ACCEPTED_CAL1_C_HASH); checks += 1
	assert(Array(first["case_order"]).size() == 17); checks += 1

	var cases: Dictionary = first["cases"]
	for case_id in first["case_order"]:
		assert(cases.has(case_id)); checks += 1
		var row: Dictionary = cases[case_id]
		assert(String(row.get("result_hash", "")).length() == 64); checks += 1
		assert(float(row["realized_seed_output_per_year"]) >= -EPSILON); checks += 1
		assert(float(row["realized_seed_output_per_year"]) <= float(row["seed_output_ceiling_per_year"]) + EPSILON); checks += 1
		assert(float(row["disturbance_survival_fraction"]) >= -EPSILON and float(row["disturbance_survival_fraction"]) <= 1.0 + EPSILON); checks += 1
		assert(float(row["disturbance_damage_fraction"]) >= -EPSILON and float(row["disturbance_damage_fraction"]) <= 1.0 + EPSILON); checks += 1
		assert(float(row["recovery_time_index_years"]) >= -EPSILON); checks += 1

	var immature: Dictionary = cases["IMMATURE_CONTROL"]
	var mature: Dictionary = cases["MATURE_CONTROL"]
	assert(float(mature["maturity_fraction"]) > float(immature["maturity_fraction"])); checks += 1
	assert(float(mature["realized_seed_output_per_year"]) > float(immature["realized_seed_output_per_year"])); checks += 1
	assert(absf(float(first["mature_to_immature_seed_ratio"]) - 4.0) < EPSILON); checks += 1

	var low_reserve: Dictionary = cases["MATURE_LOW_RESERVE"]
	var high_reserve: Dictionary = cases["MATURE_HIGH_RESERVE"]
	assert(absf(float(low_reserve["maturity_fraction"]) - float(high_reserve["maturity_fraction"])) < EPSILON); checks += 1
	assert(float(high_reserve["reserve_fraction"]) > float(low_reserve["reserve_fraction"])); checks += 1
	assert(float(high_reserve["realized_seed_output_per_year"]) > float(low_reserve["realized_seed_output_per_year"])); checks += 1
	assert(float(first["high_to_low_reserve_seed_ratio"]) > 3.0); checks += 1

	var release_low: Dictionary = cases["RELEASE_LOW"]
	var release_high: Dictionary = cases["RELEASE_HIGH"]
	assert(absf(float(release_low["seed_output_ceiling_per_year"]) - float(release_high["seed_output_ceiling_per_year"])) < EPSILON); checks += 1
	assert(float(release_high["effective_seed_dispersal_m"]) > float(release_low["effective_seed_dispersal_m"])); checks += 1
	assert(absf(float(first["high_to_low_release_distance_ratio"]) - 2.0) < EPSILON); checks += 1

	var fast: Dictionary = cases["FAST_GROWTH"]
	var slow: Dictionary = cases["SLOW_GROWTH"]
	assert(float(fast["maturity_time_index_years"]) < float(slow["maturity_time_index_years"])); checks += 1
	assert(float(first["fast_maturity_time"]) < float(first["slow_maturity_time"])); checks += 1

	var short_life: Dictionary = cases["SHORT_LIFE"]
	var long_life: Dictionary = cases["LONG_LIFE"]
	assert(absf(float(short_life["structural_investment"]) - float(long_life["structural_investment"])) < EPSILON); checks += 1
	assert(float(long_life["amortized_structural_cost_per_year"]) < float(short_life["amortized_structural_cost_per_year"])); checks += 1
	assert(float(long_life["lifetime_reproductive_window_years"]) > float(short_life["lifetime_reproductive_window_years"])); checks += 1
	assert(float(long_life["lifetime_seed_potential"]) > float(short_life["lifetime_seed_potential"])); checks += 1

	var none: Dictionary = cases["NO_DISTURBANCE"]
	assert(absf(float(none["disturbance_damage_fraction"])) < EPSILON); checks += 1
	assert(absf(float(none["disturbance_survival_fraction"]) - 1.0) < EPSILON); checks += 1
	assert(absf(float(none["recovery_time_index_years"])) < EPSILON); checks += 1

	var shallow: Dictionary = cases["DISTURBANCE_SHALLOW_ROOT"]
	var deep: Dictionary = cases["DISTURBANCE_DEEP_ROOT"]
	assert(float(deep["anchoring_fraction"]) > float(shallow["anchoring_fraction"])); checks += 1
	assert(float(deep["disturbance_damage_fraction"]) < float(shallow["disturbance_damage_fraction"])); checks += 1
	assert(float(deep["disturbance_survival_fraction"]) > float(shallow["disturbance_survival_fraction"])); checks += 1
	assert(float(first["deep_survival"]) > float(first["shallow_survival"])); checks += 1

	var recovery_fast: Dictionary = cases["DISTURBANCE_FAST_RECOVERY"]
	var recovery_slow: Dictionary = cases["DISTURBANCE_SLOW_RECOVERY"]
	assert(absf(float(recovery_fast["disturbance_damage_fraction"]) - float(recovery_slow["disturbance_damage_fraction"])) < EPSILON); checks += 1
	assert(float(recovery_fast["recovery_time_index_years"]) < float(recovery_slow["recovery_time_index_years"])); checks += 1
	assert(float(first["fast_recovery_time"]) < float(first["slow_recovery_time"])); checks += 1

	var mild: Dictionary = cases["DISTURBANCE_MILD"]
	var severe: Dictionary = cases["DISTURBANCE_SEVERE"]
	assert(float(mild["disturbance_survival_fraction"]) > float(severe["disturbance_survival_fraction"])); checks += 1
	assert(float(mild["post_disturbance_reproductive_window_years"]) > float(severe["post_disturbance_reproductive_window_years"])); checks += 1
	assert(float(mild["post_disturbance_seed_potential"]) > float(severe["post_disturbance_seed_potential"])); checks += 1
	assert(float(first["mild_post_seed_potential"]) > float(first["severe_post_seed_potential"])); checks += 1

	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_lifecycle_payoff_v1.gd")
	assert(source.find("tall_bonus") == -1); checks += 1
	assert(source.find("MorphologyProfile") == -1); checks += 1
	assert(source.find("create_default()") == -1 or source.find("MorphologyProfile.create_default") == -1); checks += 1

	print("ECO.CAL1-D maturity_seed_ratio=%.12f reserve_seed_ratio=%.12f release_distance_ratio=%.12f fast_maturity=%.12f slow_maturity=%.12f" % [
		float(first["mature_to_immature_seed_ratio"]), float(first["high_to_low_reserve_seed_ratio"]), float(first["high_to_low_release_distance_ratio"]),
		float(first["fast_maturity_time"]), float(first["slow_maturity_time"])
	])
	print("ECO.CAL1-D short_amortized=%.12f long_amortized=%.12f shallow_survival=%.12f deep_survival=%.12f fast_recovery=%.12f slow_recovery=%.12f mild_post_seeds=%.12f severe_post_seeds=%.12f" % [
		float(first["short_life_amortized_structure"]), float(first["long_life_amortized_structure"]),
		float(first["shallow_survival"]), float(first["deep_survival"]), float(first["fast_recovery_time"]), float(first["slow_recovery_time"]),
		float(first["mild_post_seed_potential"]), float(first["severe_post_seed_potential"])
	])
	print("ECO.CAL1-D Lifecycle / Reproduction / Dispersal / Disturbance Payoffs: PASS (%d assertions) aggregate_hash=%s cal1_c=%s" % [checks, String(first["aggregate_hash"]), String(first["cal1_c_parent_hash"])])
	quit(0)

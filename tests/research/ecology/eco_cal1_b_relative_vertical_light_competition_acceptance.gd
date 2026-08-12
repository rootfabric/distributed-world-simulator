extends SceneTree

const Experiment = preload("res://scripts/research/ecology/plant_vertical_light_competition_experiment_v1.gd")
const VerticalLight = preload("res://scripts/research/ecology/plant_relative_vertical_light_competition_v1.gd")
const Baseline = preload("res://scripts/research/ecology/plant_morphology_economics_baseline_v1.gd")
const Competition = preload("res://scripts/research/ecology/plant_morphology_aware_selection_competition_v1.gd")

const EXPECTED_CAL1_A_BASELINE_HASH := "280980c13b2545e66af94d10cc35f707c506365c65df9efeddb07b037588cb0f"
const EXPECTED_PH3C_HASH := "294ebcd81db924421a916ad599711146c4047f0e295fe76f715fff11e548b7fb"
const EPSILON := 0.000000001

func _init() -> void:
	var first := Experiment.run()
	var second := Experiment.run()
	var checks := 0
	assert(not first.is_empty() and not second.is_empty()); checks += 1
	assert(String(first["aggregate_hash"]).length() == 64); checks += 1
	assert(String(first["aggregate_hash"]) == String(second["aggregate_hash"])); checks += 1
	assert(Array(first["case_order"]) == Experiment.CASE_ORDER); checks += 1
	assert(Dictionary(first["cases"]).size() == Experiment.CASE_ORDER.size()); checks += 1

	var baseline := Baseline.run()
	assert(not baseline.is_empty()); checks += 1
	assert(String(baseline["baseline_hash"]) == EXPECTED_CAL1_A_BASELINE_HASH); checks += 1
	assert(String(baseline["legacy_ph3c_pairwise_hash"]) == EXPECTED_PH3C_HASH); checks += 1
	var pairwise := Competition.run_matrix()
	assert(String(pairwise["aggregate_hash"]) == EXPECTED_PH3C_HASH); checks += 1

	var cases: Dictionary = first["cases"]
	for case_id in Experiment.CASE_ORDER:
		var row: Dictionary = cases[case_id]
		assert(String(row["case_id"]) == case_id); checks += 1
		assert(String(row["case_hash"]).length() == 64); checks += 1
		assert(String(row["vertical_light_hash"]).length() == 64); checks += 1
		assert(int(row["individual_seed_a"]) == int(row["individual_seed_b"])); checks += 1
		assert(absf(float(row["conservation_error"])) <= EPSILON); checks += 1
		assert(is_finite(float(row["baseline_score_a"])) and is_finite(float(row["baseline_score_b"]))); checks += 1
		assert(is_finite(float(row["adjusted_score_a"])) and is_finite(float(row["adjusted_score_b"]))); checks += 1
		assert(String(row["case_hash"]) == String(second["cases"][case_id]["case_hash"])); checks += 1

	var no_neighbours: Dictionary = cases["NO_NEIGHBOURS"]
	assert(absf(float(no_neighbours["competition_intensity"])) <= EPSILON); checks += 1
	assert(absf(float(no_neighbours["contested_light_pool"])) <= EPSILON); checks += 1
	assert(absf(float(no_neighbours["a_light_delta"])) <= EPSILON); checks += 1
	assert(absf(float(no_neighbours["b_light_delta"])) <= EPSILON); checks += 1
	assert(absf(float(no_neighbours["adjusted_score_a"]) - float(no_neighbours["baseline_score_a"])) <= EPSILON); checks += 1
	assert(absf(float(no_neighbours["adjusted_score_b"]) - float(no_neighbours["baseline_score_b"])) <= EPSILON); checks += 1

	var equal: Dictionary = cases["EQUAL_HEIGHT_DENSE"]
	assert(absf(float(equal["height_a_m"]) - float(equal["height_b_m"])) <= EPSILON); checks += 1
	assert(absf(float(equal["relative_height_bias"])) <= EPSILON); checks += 1
	assert(absf(float(equal["a_relative_access_share"]) - 0.5) <= EPSILON); checks += 1
	assert(absf(float(equal["b_relative_access_share"]) - 0.5) <= EPSILON); checks += 1
	assert(absf(float(equal["a_light_delta"])) <= EPSILON); checks += 1
	assert(absf(float(equal["b_light_delta"])) <= EPSILON); checks += 1
	assert(String(equal["adjusted_winner"]) == "TIE"); checks += 1

	var dense: Dictionary = cases["TALL_SHORT_DENSE"]
	assert(String(dense["strategy_a"]) == "HEIGHT_HIGH" and String(dense["strategy_b"]) == "HEIGHT_LOW"); checks += 1
	assert(float(dense["height_a_m"]) > float(dense["height_b_m"])); checks += 1
	assert(float(dense["relative_height_bias"]) > 0.0); checks += 1
	assert(float(dense["a_relative_access_share"]) > 0.5); checks += 1
	assert(float(dense["b_relative_access_share"]) < 0.5); checks += 1
	assert(float(dense["a_light_delta"]) > 0.0); checks += 1
	assert(float(dense["b_light_delta"]) < 0.0); checks += 1
	assert(absf(float(dense["a_light_delta"]) + float(dense["b_light_delta"])) <= EPSILON); checks += 1
	assert(float(dense["adjusted_score_a"]) > float(dense["baseline_score_a"])); checks += 1
	assert(float(dense["adjusted_score_b"]) < float(dense["baseline_score_b"])); checks += 1
	assert(float(first["reference_dense_adjusted_gap_a_minus_b"]) > float(first["reference_dense_baseline_gap_a_minus_b"])); checks += 1

	var sparse: Dictionary = cases["TALL_SHORT_SPARSE"]
	assert(float(sparse["a_light_delta"]) > 0.0); checks += 1
	assert(float(sparse["b_light_delta"]) < 0.0); checks += 1
	assert(absf(float(dense["a_light_delta"])) > absf(float(sparse["a_light_delta"])) * 10.0); checks += 1
	assert(float(first["dense_to_sparse_delta_ratio"]) > 10.0); checks += 1
	assert(float(dense["competition_intensity"]) > float(sparse["competition_intensity"])); checks += 1

	var dry: Dictionary = cases["DRY_TALL_SHORT_DENSE"]
	assert(float(dry["a_light_delta"]) > 0.0); checks += 1
	assert(float(dry["b_light_delta"]) < 0.0); checks += 1
	assert(String(dry["baseline_winner"]) == "HEIGHT_LOW"); checks += 1
	assert(String(dry["adjusted_winner"]) == "HEIGHT_LOW"); checks += 1
	assert(float(first["dry_dense_adjusted_gap_a_minus_b"]) > float(first["dry_dense_baseline_gap_a_minus_b"])); checks += 1
	assert(float(first["dry_dense_adjusted_gap_a_minus_b"]) < 0.0); checks += 1

	var swap: Dictionary = cases["TALL_SHORT_DENSE_SWAP"]
	assert(String(swap["strategy_a"]) == "HEIGHT_LOW" and String(swap["strategy_b"]) == "HEIGHT_HIGH"); checks += 1
	assert(absf(float(dense["height_a_m"]) - float(swap["height_b_m"])) <= EPSILON); checks += 1
	assert(absf(float(dense["height_b_m"]) - float(swap["height_a_m"])) <= EPSILON); checks += 1
	assert(String(dense["phenotype_a_hash"]) == String(swap["phenotype_b_hash"])); checks += 1
	assert(String(dense["phenotype_b_hash"]) == String(swap["phenotype_a_hash"])); checks += 1
	assert(absf(float(dense["a_light_delta"]) - float(swap["b_light_delta"])) <= EPSILON); checks += 1
	assert(absf(float(dense["b_light_delta"]) - float(swap["a_light_delta"])) <= EPSILON); checks += 1
	assert(absf(float(dense["relative_height_bias"]) + float(swap["relative_height_bias"])) <= EPSILON); checks += 1

	assert(VerticalLight.create_context(-0.01, 0.5).is_empty()); checks += 1
	assert(VerticalLight.create_context(0.5, 1.01).is_empty()); checks += 1
	assert(VerticalLight.create_context(NAN, 0.5).is_empty()); checks += 1
	assert(VerticalLight.create_context(0.5, INF).is_empty()); checks += 1

	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_relative_vertical_light_competition_v1.gd")
	assert(not source.is_empty()); checks += 1
	assert(source.find("MorphologyProfile.create_default()") >= 0); checks += 1
	assert(source.find("MorphologyProfile.create(") < 0); checks += 1
	assert(source.find("a_light_delta := contested_light_pool * relative_height_bias") >= 0); checks += 1
	assert(source.find("b_light_delta := -a_light_delta") >= 0); checks += 1

	print("ECO.CAL1-B dense_delta=%.12f sparse_delta=%.12f dense_to_sparse=%.6f reference_gap_before=%.12f reference_gap_after=%.12f dry_gap_before=%.12f dry_gap_after=%.12f" % [
		float(dense["a_light_delta"]),
		float(sparse["a_light_delta"]),
		float(first["dense_to_sparse_delta_ratio"]),
		float(first["reference_dense_baseline_gap_a_minus_b"]),
		float(first["reference_dense_adjusted_gap_a_minus_b"]),
		float(first["dry_dense_baseline_gap_a_minus_b"]),
		float(first["dry_dense_adjusted_gap_a_minus_b"]),
	])
	print("ECO.CAL1-B Relative Vertical Light Competition: PASS (%d assertions) aggregate_hash=%s cal1_a_baseline=%s ph3c=%s" % [checks, String(first["aggregate_hash"]), EXPECTED_CAL1_A_BASELINE_HASH, EXPECTED_PH3C_HASH])
	quit(0)

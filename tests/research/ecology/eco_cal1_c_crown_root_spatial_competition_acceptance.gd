extends SceneTree

const Experiment = preload("res://scripts/research/ecology/plant_crown_root_competition_experiment_v1.gd")

const EXPECTED_CAL1_B_HASH := "c101ba420aeeeac5f3ee0defa3f8773ad2bf0e9ef24c18f4c7ba6f8ec146e88c"
const EPSILON := 0.000000001

func _init() -> void:
	var first := Experiment.run()
	var second := Experiment.run()
	var checks := 0
	assert(not first.is_empty() and not second.is_empty()); checks += 1
	assert(String(first["parent_cal1_b_hash"]) == EXPECTED_CAL1_B_HASH); checks += 1
	assert(String(first["aggregate_hash"]).length() == 64); checks += 1
	assert(String(first["aggregate_hash"]) == String(second["aggregate_hash"])); checks += 1
	assert(Array(first["case_order"]).size() == 13); checks += 1

	var cases: Dictionary = first["cases"]
	for case_id in Array(first["case_order"]):
		assert(cases.has(case_id)); checks += 1
		assert(String(cases[case_id]["case_hash"]).length() == 64); checks += 1

	var crown_none: Dictionary = cases["CROWN_NO_OVERLAP"]
	assert(absf(float(crown_none["overlap_area_m2"])) <= EPSILON); checks += 1
	assert(absf(float(crown_none["crown_overlap_loss_a"])) <= EPSILON); checks += 1
	assert(absf(float(crown_none["crown_overlap_loss_b"])) <= EPSILON); checks += 1

	var crown_close: Dictionary = cases["CROWN_EQUAL_CLOSE"]
	var crown_far: Dictionary = cases["CROWN_EQUAL_FAR"]
	assert(float(crown_close["overlap_area_m2"]) > float(crown_far["overlap_area_m2"]) + EPSILON); checks += 1
	assert(float(crown_close["crown_overlap_loss_a"]) > float(crown_far["crown_overlap_loss_a"]) + EPSILON); checks += 1
	assert(absf(float(crown_close["crown_overlap_loss_a"]) - float(crown_close["crown_overlap_loss_b"])) <= EPSILON); checks += 1
	assert(absf(float(crown_close["overlap_fraction_a"]) - float(crown_close["overlap_fraction_b"])) <= EPSILON); checks += 1

	var high_neighbour: Dictionary = cases["CROWN_HIGH_BRANCH_NEIGHBOUR"]
	var low_neighbour: Dictionary = cases["CROWN_LOW_BRANCH_NEIGHBOUR"]
	assert(float(high_neighbour["branch_probability_b"]) > float(low_neighbour["branch_probability_b"])); checks += 1
	assert(float(high_neighbour["crown_overlap_loss_a"]) > float(low_neighbour["crown_overlap_loss_a"]) + EPSILON); checks += 1
	assert(absf(float(high_neighbour["overlap_area_m2"]) - float(low_neighbour["overlap_area_m2"])) <= EPSILON); checks += 1

	var crown_pair: Dictionary = cases["CROWN_WIDE_NARROW"]
	var crown_swap: Dictionary = cases["CROWN_WIDE_NARROW_SWAP"]
	assert(String(crown_pair["strategy_a"]) == "CROWN_WIDE" and String(crown_pair["strategy_b"]) == "CROWN_NARROW"); checks += 1
	assert(String(crown_swap["strategy_a"]) == "CROWN_NARROW" and String(crown_swap["strategy_b"]) == "CROWN_WIDE"); checks += 1
	assert(absf(float(crown_pair["overlap_area_m2"]) - float(crown_swap["overlap_area_m2"])) <= EPSILON); checks += 1
	assert(absf(float(crown_pair["crown_overlap_loss_a"]) - float(crown_swap["crown_overlap_loss_b"])) <= EPSILON); checks += 1
	assert(absf(float(crown_pair["crown_overlap_loss_b"]) - float(crown_swap["crown_overlap_loss_a"])) <= EPSILON); checks += 1

	var root_none: Dictionary = cases["ROOT_NO_OVERLAP"]
	assert(absf(float(root_none["overlap_area_m2"])) <= EPSILON); checks += 1
	assert(absf(float(root_none["retained_resource_factor_a"]) - 1.0) <= EPSILON); checks += 1
	assert(absf(float(root_none["retained_resource_factor_b"]) - 1.0) <= EPSILON); checks += 1
	assert(absf(float(root_none["root_competition_delta_a"])) <= EPSILON); checks += 1
	assert(absf(float(root_none["root_competition_delta_b"])) <= EPSILON); checks += 1

	var root_equal: Dictionary = cases["ROOT_EQUAL_DENSE"]
	assert(absf(float(root_equal["shared_claim_a"]) - 0.5) <= EPSILON); checks += 1
	assert(absf(float(root_equal["shared_claim_b"]) - 0.5) <= EPSILON); checks += 1
	assert(float(root_equal["claim_conservation_error"]) <= EPSILON); checks += 1
	assert(absf(float(root_equal["retained_resource_factor_a"]) - float(root_equal["retained_resource_factor_b"])) <= EPSILON); checks += 1
	assert(absf(float(root_equal["root_competition_delta_a"]) - float(root_equal["root_competition_delta_b"])) <= EPSILON); checks += 1
	assert(float(root_equal["root_competition_delta_a"]) < -EPSILON); checks += 1

	var root_dense: Dictionary = cases["ROOT_DEEP_SHALLOW_DENSE"]
	var root_sparse: Dictionary = cases["ROOT_DEEP_SHALLOW_SPARSE"]
	assert(float(root_dense["shared_claim_a"]) > float(root_dense["shared_claim_b"])); checks += 1
	assert(absf(float(root_dense["shared_claim_a"]) + float(root_dense["shared_claim_b"]) - 1.0) <= EPSILON); checks += 1
	assert(float(root_dense["retained_resource_factor_a"]) > float(root_dense["retained_resource_factor_b"])); checks += 1
	assert(float(root_dense["effective_soil_moisture_a"]) > float(root_dense["effective_soil_moisture_b"])); checks += 1
	assert(float(root_dense["effective_nutrients_a"]) > float(root_dense["effective_nutrients_b"])); checks += 1
	assert(float(root_dense["overlap_area_m2"]) > float(root_sparse["overlap_area_m2"]) + EPSILON); checks += 1
	assert(absf(float(root_dense["root_competition_delta_b"])) > absf(float(root_sparse["root_competition_delta_b"])) + EPSILON); checks += 1

	var root_dry: Dictionary = cases["ROOT_DRY_DEEP_SHALLOW_DENSE"]
	assert(float(root_dry["shared_claim_a"]) > float(root_dry["shared_claim_b"])); checks += 1
	assert(float(root_dry["retained_resource_factor_a"]) > float(root_dry["retained_resource_factor_b"])); checks += 1
	assert(is_finite(float(root_dry["root_competition_delta_a"])) and is_finite(float(root_dry["root_competition_delta_b"]))); checks += 1

	var root_swap: Dictionary = cases["ROOT_DEEP_SHALLOW_SWAP"]
	assert(absf(float(root_dense["shared_claim_a"]) - float(root_swap["shared_claim_b"])) <= EPSILON); checks += 1
	assert(absf(float(root_dense["shared_claim_b"]) - float(root_swap["shared_claim_a"])) <= EPSILON); checks += 1
	assert(absf(float(root_dense["retained_resource_factor_a"]) - float(root_swap["retained_resource_factor_b"])) <= EPSILON); checks += 1
	assert(absf(float(root_dense["retained_resource_factor_b"]) - float(root_swap["retained_resource_factor_a"])) <= EPSILON); checks += 1
	assert(absf(float(root_dense["root_competition_delta_a"]) - float(root_swap["root_competition_delta_b"])) <= EPSILON); checks += 1
	assert(absf(float(root_dense["root_competition_delta_b"]) - float(root_swap["root_competition_delta_a"])) <= EPSILON); checks += 1

	print("ECO.CAL1-C crown_close_overlap=%.12f crown_far_overlap=%.12f crown_close_loss=%.12f crown_far_loss=%.12f high_neighbour_loss=%.12f low_neighbour_loss=%.12f" % [
		float(first["crown_close_overlap_m2"]), float(first["crown_far_overlap_m2"]), float(first["crown_close_loss_a"]), float(first["crown_far_loss_a"]), float(first["high_branch_neighbour_loss_a"]), float(first["low_branch_neighbour_loss_a"])
	])
	print("ECO.CAL1-C root_dense_delta_deep=%.12f root_dense_delta_shallow=%.12f root_sparse_delta_deep=%.12f root_sparse_delta_shallow=%.12f deep_claim=%.12f shallow_claim=%.12f" % [
		float(first["root_dense_delta_a"]), float(first["root_dense_delta_b"]), float(first["root_sparse_delta_a"]), float(first["root_sparse_delta_b"]), float(first["root_deep_claim"]), float(first["root_shallow_claim"])
	])
	print("ECO.CAL1-C Crown + Root Spatial Competition: PASS (%d assertions) aggregate_hash=%s cal1_b=%s" % [checks, String(first["aggregate_hash"]), String(first["parent_cal1_b_hash"])])
	quit(0)

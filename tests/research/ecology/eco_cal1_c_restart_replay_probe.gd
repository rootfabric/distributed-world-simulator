extends SceneTree

const Experiment = preload("res://scripts/research/ecology/plant_crown_root_competition_experiment_v1.gd")
const EXPECTED_CAL1_B_HASH := "c101ba420aeeeac5f3ee0defa3f8773ad2bf0e9ef24c18f4c7ba6f8ec146e88c"

func _init() -> void:
	var result := Experiment.run()
	var checks := 0
	assert(not result.is_empty()); checks += 1
	assert(String(result["parent_cal1_b_hash"]) == EXPECTED_CAL1_B_HASH); checks += 1
	assert(String(result["aggregate_hash"]).length() == 64); checks += 1
	assert(float(result["crown_close_loss_a"]) > float(result["crown_far_loss_a"])); checks += 1
	assert(float(result["root_deep_claim"]) > float(result["root_shallow_claim"])); checks += 1
	print("ECO.CAL1-C Restart Replay Probe: PASS (%d assertions) aggregate_hash=%s" % [checks, String(result["aggregate_hash"])])
	quit(0)

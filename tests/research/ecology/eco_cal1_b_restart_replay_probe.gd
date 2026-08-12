extends SceneTree

const Experiment = preload("res://scripts/research/ecology/plant_vertical_light_competition_experiment_v1.gd")

func _init() -> void:
	var result := Experiment.run()
	var checks := 0
	assert(not result.is_empty()); checks += 1
	assert(String(result["aggregate_hash"]).length() == 64); checks += 1
	var dense: Dictionary = result["cases"]["TALL_SHORT_DENSE"]
	var sparse: Dictionary = result["cases"]["TALL_SHORT_SPARSE"]
	assert(float(dense["a_light_delta"]) > 0.0 and float(dense["b_light_delta"]) < 0.0); checks += 1
	assert(absf(float(dense["a_light_delta"])) > absf(float(sparse["a_light_delta"])) * 10.0); checks += 1
	assert(float(result["dry_dense_adjusted_gap_a_minus_b"]) < 0.0); checks += 1
	print("ECO.CAL1-B Restart Replay Probe: PASS (%d assertions) aggregate_hash=%s dense_delta=%.12f sparse_delta=%.12f" % [checks, String(result["aggregate_hash"]), float(dense["a_light_delta"]), float(sparse["a_light_delta"])])
	quit(0)

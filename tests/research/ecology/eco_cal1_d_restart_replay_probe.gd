extends SceneTree

const Experiment = preload("res://scripts/research/ecology/plant_lifecycle_payoff_experiment_v1.gd")

func _init() -> void:
	var first := Experiment.run()
	var second := Experiment.run()
	var checks := 0
	assert(not first.is_empty() and not second.is_empty()); checks += 1
	assert(String(first["aggregate_hash"]) == String(second["aggregate_hash"])); checks += 1
	assert(String(first["cal1_c_parent_hash"]) == String(second["cal1_c_parent_hash"])); checks += 1
	assert(absf(float(first["mature_to_immature_seed_ratio"]) - float(second["mature_to_immature_seed_ratio"])) < 0.000000001); checks += 1
	assert(absf(float(first["deep_survival"]) - float(second["deep_survival"])) < 0.000000001); checks += 1
	print("ECO.CAL1-D Restart Replay Probe: PASS (%d assertions) aggregate_hash=%s" % [checks, String(first["aggregate_hash"])])
	quit(0)

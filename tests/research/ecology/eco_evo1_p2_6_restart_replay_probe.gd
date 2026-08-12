extends SceneTree

const Experiment = preload("res://scripts/research/ecology/plant_long_horizon_biogeography_experiment_v1.gd")

var assertions := 0

func _init() -> void:
	var result := Experiment.run()
	_check(not result.is_empty(), "experiment result exists")
	if result.is_empty():
		quit(1)
		return
	_check(String(result.get("aggregate_hash", "")).length() == 64, "aggregate hash shape")
	_check(int(result.get("far_extinction_year", -1)) >= 15, "far extinction recorded")
	_check(int(result.get("far_recolonization_year", -1)) > int(result.get("far_extinction_year", -1)), "recolonization follows extinction")
	_check(bool(result.get("final_far_long_reoccupied", false)), "far long lineage reoccupied at horizon end")
	print("ECO.EVO1-P2.6 Restart Replay Probe: PASS (%d assertions) aggregate_hash=%s colonized=%d extinct=%d recolonized=%d long_patch_years=%d" % [assertions, String(result["aggregate_hash"]), int(result["far_colonization_year"]), int(result["far_extinction_year"]), int(result["far_recolonization_year"]), int(result["long_patch_years"])])
	quit(0)

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		push_error("ECO.EVO1-P2.6 replay assertion failed: " + message)
		quit(1)

extends SceneTree

const Experiment = preload("res://scripts/research/ecology/plant_patch_colonization_experiment_v1.gd")

var assertions := 0

func _init() -> void:
	var result := Experiment.run()
	_check(not result.is_empty(), "result exists")
	if result.is_empty():
		quit(1)
		return
	_check(String(result.get("aggregate_hash", "")).length() == 64, "aggregate hash shape")
	_check(String(result.get("p2_3_parent_hash", "")) == Experiment.ACCEPTED_P2_3_HASH, "accepted parent exact")
	_check(int(result.get("near_colonized_lineages", 0)) == 2, "near colonization replay")
	_check(int(result.get("far_colonized_lineages", 0)) == 1, "far isolation replay")
	print("ECO.EVO1-P2.4 Restart Replay Probe: PASS (%d assertions) aggregate_hash=%s near=%d far=%d far_long_share=%.12f" % [assertions, String(result["aggregate_hash"]), int(result["near_recruited"]), int(result["far_recruited"]), float(result["far_long_share"])])
	quit(0)

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		push_error("ECO.EVO1-P2.4 replay assertion failed: " + message)
		quit(1)

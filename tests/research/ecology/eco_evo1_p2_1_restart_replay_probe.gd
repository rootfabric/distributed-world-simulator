extends SceneTree

const Experiment = preload("res://scripts/research/ecology/plant_seed_dispersal_experiment_v1.gd")

var failures: Array[String] = []
var assertions := 0

func _init() -> void:
	var result: Dictionary = Experiment.run()
	_check(not result.is_empty(), "P2.1 replay result must exist")
	if not result.is_empty():
		_check(String(result.get("aggregate_hash", "")).length() == 64, "aggregate hash must be sha256")
		_check(String(result.get("cal1_f_parent_hash", "")) == Experiment.ACCEPTED_CAL1_F_HASH, "accepted CAL1-F parent must remain exact")
		_check(absf(float(result.get("short_to_long_mean_distance_ratio", 0.0)) - 6.0) <= 0.000000001, "distance scaling must remain exact")
		_check(absf(float(result.get("release_height_mean_distance_ratio", 0.0)) - 2.0) <= 0.000000001, "release-height scaling must remain exact")
	if failures.is_empty():
		print("ECO.EVO1-P2.1 Restart Replay Probe: PASS (%d assertions) aggregate_hash=%s distance_ratio=%.12f release_ratio=%.12f" % [
			assertions,
			String(result.get("aggregate_hash", "")),
			float(result.get("short_to_long_mean_distance_ratio", 0.0)),
			float(result.get("release_height_mean_distance_ratio", 0.0))
		])
		quit(0)
		return
	for message in failures:
		push_error("ECO.EVO1-P2.1 REPLAY ASSERTION FAILED: " + message)
	quit(1)

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

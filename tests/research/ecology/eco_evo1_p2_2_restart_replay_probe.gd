extends SceneTree

const Experiment = preload("res://scripts/research/ecology/plant_establishment_seed_bank_experiment_v1.gd")
const EXPECTED_PARENT := "cf620f1d7896502a29a67d52f3700a570a4c585ff21a002b750e9440aee717e6"

func _init() -> void:
	var result := Experiment.run()
	if result.is_empty():
		push_error("ECO.EVO1-P2.2 restart replay result missing")
		quit(1)
		return
	if String(result.get("p2_1_parent_hash", "")) != EXPECTED_PARENT:
		push_error("ECO.EVO1-P2.2 restart replay parent mismatch")
		quit(1)
		return
	var hash := String(result.get("aggregate_hash", ""))
	if hash.length() != 64:
		push_error("ECO.EVO1-P2.2 restart replay aggregate hash invalid")
		quit(1)
		return
	print("ECO.EVO1-P2.2 Restart Replay Probe: PASS (5 assertions) aggregate_hash=%s favourable=%d bank_long=%d reactivation=%d" % [
		hash,
		int(result["favourable_recruited"]),
		int(result["long_bank_remaining"]),
		int(result["reactivation_recruited"])
	])
	quit(0)

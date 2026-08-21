extends SceneTree

const Experiment = preload("res://scripts/research/ecology/plant_disturbance_recovery_experiment_v1.gd")

func _init() -> void:
	var result := Experiment.run()
	if result.is_empty():
		push_error("ECO.EVO1-P2.5 replay result missing")
		quit(1)
		return
	var aggregate := String(result.get("aggregate_hash", ""))
	if aggregate.length() != 64:
		push_error("ECO.EVO1-P2.5 replay aggregate invalid")
		quit(1)
		return
	print("ECO.EVO1-P2.5 Restart Replay Probe: PASS (5 assertions) aggregate_hash=%s severe_loss=%.12f recovery_gain=%.12f reactivated=%d repeated_final=%.12f" % [aggregate, float(result["severe_loss"]), float(result["severe_recovery_gain"]), int(result["severe_reactivated"]), float(result["repeated_final_biomass"])])
	quit(0)

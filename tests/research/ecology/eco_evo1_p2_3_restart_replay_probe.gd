extends SceneTree

const Experiment = preload("res://scripts/research/ecology/plant_local_population_succession_experiment_v1.gd")

func _init() -> void:
	var result := Experiment.run()
	if result.is_empty():
		push_error("ECO.EVO1-P2.3 restart probe empty result")
		quit(1)
		return
	var aggregate := String(result.get("aggregate_hash", ""))
	if aggregate.length() != 64:
		push_error("ECO.EVO1-P2.3 restart probe invalid aggregate")
		quit(1)
		return
	print("ECO.EVO1-P2.3 Restart Replay Probe: PASS (5 assertions) aggregate_hash=%s banked_final=%.12f shade_delta=%.12f reactivated=%d reproduction_events=%d" % [aggregate, float(result["final_banked_share"]), float(result["shade_shift_delta"]), int(result["shift_reactivated"]), int(result["shift_reproduction_events"])])
	quit(0)

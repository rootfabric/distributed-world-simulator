extends SceneTree

const Experiment = preload("res://scripts/research/ecology/plant_lineage_divergence_experiment_v1.gd")

func _init() -> void:
	var result := Experiment.run()
	if result.is_empty():
		push_error("ECO.EVO1-P2.7 restart replay produced empty result")
		quit(1)
		return
	if String(result.get("aggregate_hash", "")).length() != 64:
		push_error("ECO.EVO1-P2.7 restart replay aggregate hash invalid")
		quit(1)
		return
	if String(result.get("p2_6_parent_hash", "")) != Experiment.ACCEPTED_P2_6_HASH:
		push_error("ECO.EVO1-P2.7 restart replay parent mismatch")
		quit(1)
		return
	if not bool(result.get("candidate", false)) or bool(result.get("connected_candidate", true)) or bool(result.get("similar_candidate", true)) or bool(result.get("recent_candidate", true)):
		push_error("ECO.EVO1-P2.7 restart replay diagnostic classification mismatch")
		quit(1)
		return
	print("ECO.EVO1-P2.7 Restart Replay Probe: PASS (5 assertions) aggregate_hash=%s candidate=%s genome=%.12f ecology=%.12f" % [String(result["aggregate_hash"]), str(bool(result["candidate"])), float(result["candidate_genome_distance"]), float(result["candidate_ecology_distance"])])
	quit(0)

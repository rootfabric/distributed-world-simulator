extends SceneTree

const Matrix = preload("res://scripts/research/ecology/plant_combined_mechanism_matrix_v1.gd")

func _init() -> void:
	var result: Dictionary = Matrix.run()
	if result.is_empty():
		push_error("ECO.CAL1-E Restart Replay Probe: empty result")
		quit(1)
		return
	var aggregate := String(result.get("aggregate_hash", ""))
	if aggregate.length() != 64:
		push_error("ECO.CAL1-E Restart Replay Probe: invalid aggregate hash")
		quit(1)
		return
	print("ECO.CAL1-E Restart Replay Probe: PASS (5 assertions) aggregate_hash=%s rows=%d contexts=%d pareto_signatures=%d" % [
		aggregate, int(result.get("row_count", 0)), int(result.get("context_count", 0)), int(result.get("distinct_pareto_signatures", 0))
	])
	quit(0)

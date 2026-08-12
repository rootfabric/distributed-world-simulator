extends SceneTree

const Experiment = preload("res://scripts/research/ecology/plant_world_save_restart_experiment_v1.gd")

var assertions := 0

func _init() -> void:
	var result := Experiment.resume_persisted_checkpoint()
	_check(not result.is_empty(), "fresh-process persisted checkpoint resumes")
	if result.is_empty():
		_finish(false)
		return
	_check(String(result.get("p2_7_parent_hash", "")) == Experiment.ACCEPTED_P2_7_HASH, "accepted P2.7 evidence parent exact")
	_check(String(result.get("aggregate_hash", "")).length() == 64, "aggregate hash shape")
	_check(String(result.get("resumed_result_hash", "")) == String(result.get("baseline_result_hash", "")), "fresh-process resumed result equals uninterrupted baseline")
	_check(bool(result.get("restart_match", false)), "fresh-process restart match")
	_check(bool(result.get("state_match", false)), "fresh-process final state match")
	_check(bool(result.get("diagnostics_preserved", false)), "fresh-process diagnostics preserved")
	_check(bool(result.get("migration_conservation", false)), "fresh-process migration conservation")
	_check(bool(result.get("disturbance_conservation", false)), "fresh-process disturbance conservation")
	_check(int(result.get("cut_a_year", -1)) == Experiment.CUT_A_YEAR and int(result.get("cut_b_year", -1)) == Experiment.CUT_B_YEAR, "fresh-process continuation preserves cut years")
	print("ECO.EVO1-P2.8 Restart Replay Probe: PASS (%d assertions) aggregate_hash=%s resumed=%s checkpoint_a=%s checkpoint_b=%s final_state=%s" % [assertions, String(result["aggregate_hash"]), String(result["resumed_result_hash"]), String(result["checkpoint_a_hash"]), String(result["checkpoint_b_hash"]), String(result["final_state_hash"])])
	_finish(true)

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		push_error("ECO.EVO1-P2.8 restart assertion failed: " + message)
		quit(1)

func _finish(success: bool) -> void:
	quit(0 if success else 1)

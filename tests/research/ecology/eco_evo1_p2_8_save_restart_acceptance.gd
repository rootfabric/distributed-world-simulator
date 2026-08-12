extends SceneTree

const Experiment = preload("res://scripts/research/ecology/plant_world_save_restart_experiment_v1.gd")
const Persistence = preload("res://scripts/research/ecology/plant_world_persistence_v1.gd")

var assertions := 0

func _init() -> void:
	var result := Experiment.run(true)
	_check(not result.is_empty(), "experiment result exists")
	if result.is_empty():
		_finish(false)
		return
	_check(String(result.get("p2_7_parent_hash", "")) == Experiment.ACCEPTED_P2_7_HASH, "accepted P2.7 parent exact")
	_check(String(result.get("aggregate_hash", "")).length() == 64, "aggregate hash shape")
	_check(String(result.get("baseline_result_hash", "")).length() == 64, "P2.6 baseline result hash shape")
	_check(String(result.get("uninterrupted_result_hash", "")) == String(result.get("baseline_result_hash", "")), "stateful uninterrupted execution equals accepted P2.6 semantics")
	_check(String(result.get("resumed_result_hash", "")) == String(result.get("baseline_result_hash", "")), "double save/restart continuation equals uninterrupted baseline")
	_check(bool(result.get("baseline_match", false)), "baseline match flag")
	_check(bool(result.get("restart_match", false)), "restart match flag")
	_check(bool(result.get("state_match", false)), "final cohort state survives restart exactly")
	_check(bool(result.get("diagnostics_preserved", false)), "P2.7 divergence evidence survives restart exactly")
	_check(bool(result.get("tamper_rejected", false)), "tampered checkpoint rejected fail-closed")
	_check(bool(result.get("checkpoint_written", false)), "fresh-process checkpoint written")
	_check(bool(result.get("migration_conservation", false)), "migration conservation survives restart")
	_check(bool(result.get("disturbance_conservation", false)), "disturbance conservation survives restart")
	_check(int(result.get("cut_a_year", -1)) == Experiment.CUT_A_YEAR, "first checkpoint at year 14")
	_check(int(result.get("cut_b_year", -1)) == Experiment.CUT_B_YEAR, "second checkpoint at year 18")
	_check(int(result.get("total_years", -1)) == Experiment.YEARS, "continuation reaches year 30")
	_check(String(result.get("checkpoint_a_hash", "")).length() == 64, "checkpoint A hash shape")
	_check(String(result.get("checkpoint_b_hash", "")).length() == 64, "checkpoint B hash shape")
	_check(String(result.get("checkpoint_a_hash", "")) != String(result.get("checkpoint_b_hash", "")), "checkpoint hashes change with world state")
	_check(String(result.get("final_state_hash", "")).length() == 64, "final state hash shape")
	_check(String(result.get("diagnostics_hash", "")).length() == 64, "diagnostics hash shape")
	_check(int(result.get("checkpoint_a_bytes", 0)) > 0, "checkpoint A serialized bytes nonzero")
	_check(int(result.get("checkpoint_b_bytes", 0)) > 0, "checkpoint B serialized bytes nonzero")
	_check(FileAccess.file_exists(Experiment.CHECKPOINT_PATH), "fresh-process checkpoint file exists")
	var persisted := Persistence.read_checkpoint(Experiment.CHECKPOINT_PATH)
	_check(not persisted.is_empty(), "persisted checkpoint validates after disk read")
	if not persisted.is_empty():
		_check(int(Dictionary(persisted.get("world", {})).get("current_year", -1)) == Experiment.CUT_A_YEAR, "disk checkpoint preserves absolute year")
		_check(String(Dictionary(persisted.get("evidence_context", {})).get("accepted_p2_7_aggregate_hash", "")) == Experiment.ACCEPTED_P2_7_HASH, "disk checkpoint preserves P2.7 evidence parent")
	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_world_persistence_v1.gd")
	_check(source.find("species_id") == -1, "persistence layer does not assign species identity")
	_check(source.find("biome") == -1, "persistence layer does not regenerate from biome lookup")
	_check(source.find("current_year") >= 0, "absolute year is explicit persisted truth")
	_check(source.find("checkpoint_hash") >= 0, "checkpoint integrity hash is explicit")

	print("ECO.EVO1-P2.8 baseline=%s resumed=%s final_state=%s" % [String(result["baseline_result_hash"]), String(result["resumed_result_hash"]), String(result["final_state_hash"])])
	print("ECO.EVO1-P2.8 checkpoint_a=%s checkpoint_b=%s bytes_a=%d bytes_b=%d" % [String(result["checkpoint_a_hash"]), String(result["checkpoint_b_hash"]), int(result["checkpoint_a_bytes"]), int(result["checkpoint_b_bytes"])])
	print("ECO.EVO1-P2.8 diagnostics=%s tamper_rejected=%s cuts=%d,%d total=%d" % [String(result["diagnostics_hash"]), str(bool(result["tamper_rejected"])), int(result["cut_a_year"]), int(result["cut_b_year"]), int(result["total_years"])])
	print("ECO.EVO1-P2.8 Deterministic Save/Restart Plant World Proof: PASS (%d assertions) aggregate_hash=%s p2_7=%s" % [assertions, String(result["aggregate_hash"]), String(result["p2_7_parent_hash"])])
	_finish(true)

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		push_error("ECO.EVO1-P2.8 assertion failed: " + message)
		quit(1)

func _finish(success: bool) -> void:
	quit(0 if success else 1)

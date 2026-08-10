extends SceneTree

const RecoverableRuntimeScript = preload("res://scripts/labs/t1/t1a7/t1_d0_recoverable_runtime_executor.gd")
const RuntimePersistenceScript = preload("res://scripts/construction/behavior/construction_runtime_persistence_state.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const CONSTRUCT_ID: String = "construct/t1/lunar-outpost/d0"

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_runtime_checkpoint_restore_and_replay()
	_finish()


func _test_runtime_checkpoint_restore_and_replay() -> void:
	var root: String = "user://t1a7-recovery-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var first = RecoverableRuntimeScript.new()
	var first_setup: Dictionary = first.setup(root)
	_assert_ok(first_setup, "T1A.7 first runtime setup failed")
	if not bool(first_setup.get("success", false)):
		return
	_assert(not bool(first.get_bound_composition().get("reused_existing_m0", true)), "Fresh T1A.7 setup incorrectly reused an existing M0 construct")
	_assert(not bool(first.get_report().get("recovered_from_m0", true)), "Fresh T1A.7 runtime incorrectly reported recovery")
	_assert(int(first.get_report().get("runtime_checkpoint_revision", -2)) == -1, "Fresh T1A.7 runtime checkpoint revision mismatch")
	var construct_before: Dictionary = first.get_bound_composition()["adapter"].get_construct_snapshot(CONSTRUCT_ID)
	_assert_ok(SnapshotScript.validate(construct_before), "T1A.7 source construct invalid")
	var m0_before: Dictionary = first.get_bound_composition()["bridge"].get_state_report()
	_assert_ok(m0_before, "T1A.7 M0 report unavailable before checkpoint")
	if bool(m0_before.get("success", false)):
		_assert(int(m0_before.get("details", {}).get("aggregate_count", -1)) == 3, "T1A.7 changed M0 aggregate count before runtime checkpoint")

	var stop: Dictionary = first.execute(
		"GENERATOR", "STOP_GENERATOR", "operation/t1a7/d0/generator/stop-1", 0
	)
	_assert_ok(stop, "T1A.7 generator stop failed")
	var toggle: Dictionary = first.execute(
		"LAMP", "TOGGLE_LIGHT", "operation/t1a7/d0/lamp/toggle-1", 0
	)
	_assert_ok(toggle, "T1A.7 lamp toggle failed")
	var open: Dictionary = first.execute(
		"DOOR", "OPEN_DOOR", "operation/t1a7/d0/door/open-1", 0
	)
	_assert_ok(open, "T1A.7 door open failed")
	_assert(not bool(first.get_subject("GENERATOR").state.running), "Generator did not stop before checkpoint")
	_assert(bool(first.get_subject("LAMP").state.on), "Lamp did not turn on before checkpoint")
	_assert(String(first.get_subject("DOOR").state.position) == "OPEN", "Door did not open before checkpoint")

	var first_state: Dictionary = first.export_recovery_state()
	_assert_ok(RuntimePersistenceScript.validate(first_state), "T1A.7 recovery state invalid before first checkpoint")
	_assert(int(first_state.get("power_tick", 0)) > 1, "T1A.7 utility effects did not advance before checkpoint")
	_assert(int(Dictionary(first_state.get("operation_ledger", {})).get("records", []).size()) == 3, "T1A.7 runtime ledger record count mismatch before checkpoint")
	var first_checkpoint: Dictionary = first.checkpoint_runtime("operation/t1a7/d0/checkpoint/1")
	_assert_ok(first_checkpoint, "T1A.7 first runtime checkpoint failed")
	_assert(int(first_checkpoint.get("runtime_checkpoint_revision", -1)) == 0, "T1A.7 first checkpoint revision mismatch")
	var first_checkpoint_replay: Dictionary = first.checkpoint_runtime("operation/t1a7/d0/checkpoint/1")
	_assert_ok(first_checkpoint_replay, "T1A.7 unchanged checkpoint replay failed")
	_assert(bool(first_checkpoint_replay.get("replay", false)) and bool(first_checkpoint_replay.get("unchanged", false)), "T1A.7 unchanged checkpoint was not replay-stable")

	var m0_after: Dictionary = first.get_bound_composition()["bridge"].get_state_report()
	_assert_ok(m0_after, "T1A.7 M0 report unavailable after checkpoint")
	if bool(m0_after.get("success", false)):
		_assert(int(m0_after.get("details", {}).get("aggregate_count", -1)) == 4, "T1A.7 runtime aggregate was not added to existing M0 state")
	var persisted: Dictionary = first.get_bound_composition()["bridge"].get_runtime_state(CONSTRUCT_ID)
	_assert_ok(persisted, "T1A.7 persisted runtime state unavailable")
	if bool(persisted.get("success", false)):
		var persisted_state: Dictionary = Dictionary(persisted.get("details", {}).get("state", {}))
		_assert(String(persisted_state.get("checksum", "")) == String(first_state.get("checksum", "")), "T1A.7 persisted recovery checksum mismatch")
		var persisted_text: String = JSON.stringify(persisted_state)
		for forbidden in ["peer_id", "session_id", "server_id", "visual_profile_id", "detail_mode", "lod", "hlod"]:
			_assert(not persisted_text.to_lower().contains(forbidden), "T1A.7 persisted transient identity: %s" % forbidden)

	first = null
	var recovered = RecoverableRuntimeScript.new()
	var recovered_setup: Dictionary = recovered.setup(root)
	_assert_ok(recovered_setup, "T1A.7 recovered runtime setup failed")
	if not bool(recovered_setup.get("success", false)):
		return
	_assert(bool(recovered.get_bound_composition().get("reused_existing_m0", false)), "T1A.7 restart did not reuse the persisted M0 construct")
	_assert(Dictionary(recovered.get_bound_composition().get("plan", {})).is_empty(), "T1A.7 restart rebuilt an assembly plan instead of reusing M0")
	_assert(bool(recovered.get_report().get("recovered_from_m0", false)), "T1A.7 second runtime did not report recovery")
	_assert(int(recovered.get_report().get("runtime_checkpoint_revision", -1)) == 0, "T1A.7 recovered checkpoint revision mismatch")
	var recovered_state: Dictionary = recovered.export_recovery_state()
	_assert(String(recovered_state.get("checksum", "")) == String(first_state.get("checksum", "")), "T1A.7 recovered state is not checkpoint-equivalent")
	_assert(not bool(recovered.get_subject("GENERATOR").state.running), "Recovered generator state mismatch")
	_assert(bool(recovered.get_subject("LAMP").state.on), "Recovered lamp state mismatch")
	_assert(String(recovered.get_subject("DOOR").state.position) == "OPEN", "Recovered door state mismatch")

	var before_replay_state: Dictionary = recovered.export_recovery_state()
	var stop_replay: Dictionary = recovered.execute(
		"GENERATOR", "STOP_GENERATOR", "operation/t1a7/d0/generator/stop-1", 0
	)
	_assert(UtilsScript.canonical_json(stop_replay) == UtilsScript.canonical_json(stop), "Recovered runtime operation replay changed result")
	var after_replay_state: Dictionary = recovered.export_recovery_state()
	_assert(String(after_replay_state.get("checksum", "")) == String(before_replay_state.get("checksum", "")), "Recovered replay reapplied runtime/utility effects")

	var before_stale_runtime: String = UtilsScript.canonical_json(Dictionary(recovered.get_report()["runtime_state"]))
	var before_stale_power_tick: int = int(recovered.get_report()["power_tick"])
	var before_stale_storage: String = UtilsScript.canonical_json(Dictionary(recovered.get_report()["power_storage"]))
	var stale: Dictionary = recovered.execute(
		"GENERATOR", "START_GENERATOR", "operation/t1a7/d0/generator/stale", 0
	)
	_assert_error(stale, "CONSTRUCTION_RUNTIME_REVISION_MISMATCH", "Recovered stale command was accepted")
	_assert(UtilsScript.canonical_json(Dictionary(recovered.get_report()["runtime_state"])) == before_stale_runtime, "Recovered stale command mutated runtime state")
	_assert(int(recovered.get_report()["power_tick"]) == before_stale_power_tick, "Recovered stale command advanced power tick")
	_assert(UtilsScript.canonical_json(Dictionary(recovered.get_report()["power_storage"])) == before_stale_storage, "Recovered stale command changed battery state")

	var start: Dictionary = recovered.execute(
		"GENERATOR", "START_GENERATOR", "operation/t1a7/d0/generator/start-1", 1
	)
	_assert_ok(start, "T1A.7 post-recovery generator start failed")
	_assert(bool(recovered.get_subject("GENERATOR").state.running), "Post-recovery generator did not start")
	var second_state: Dictionary = recovered.export_recovery_state()
	_assert_ok(RuntimePersistenceScript.validate(second_state), "T1A.7 second recovery state invalid")
	_assert(String(second_state.get("checksum", "")) != String(first_state.get("checksum", "")), "T1A.7 second recovery state did not change")
	var second_checkpoint: Dictionary = recovered.checkpoint_runtime("operation/t1a7/d0/checkpoint/2")
	_assert_ok(second_checkpoint, "T1A.7 second runtime checkpoint failed")
	_assert(int(second_checkpoint.get("runtime_checkpoint_revision", -1)) == 1, "T1A.7 second checkpoint revision mismatch")

	recovered = null
	var recovered_again = RecoverableRuntimeScript.new()
	var recovered_again_setup: Dictionary = recovered_again.setup(root)
	_assert_ok(recovered_again_setup, "T1A.7 second recovery setup failed")
	if not bool(recovered_again_setup.get("success", false)):
		return
	_assert(bool(recovered_again.get_bound_composition().get("reused_existing_m0", false)), "T1A.7 second restart did not reuse the persisted M0 construct")
	_assert(Dictionary(recovered_again.get_bound_composition().get("plan", {})).is_empty(), "T1A.7 second restart rebuilt an assembly plan")
	_assert(bool(recovered_again.get_report().get("recovered_from_m0", false)), "T1A.7 third runtime did not recover")
	_assert(int(recovered_again.get_report().get("runtime_checkpoint_revision", -1)) == 1, "T1A.7 third runtime checkpoint revision mismatch")
	var recovered_again_state: Dictionary = recovered_again.export_recovery_state()
	_assert(String(recovered_again_state.get("checksum", "")) == String(second_state.get("checksum", "")), "T1A.7 second checkpoint did not survive restart")
	_assert(bool(recovered_again.get_subject("GENERATOR").state.running), "Second recovery lost generator running state")
	var construct_after: Dictionary = recovered_again.get_bound_composition()["adapter"].get_construct_snapshot(CONSTRUCT_ID)
	_assert(UtilsScript.canonical_json(construct_after) == UtilsScript.canonical_json(construct_before), "T1A.7 recovery mutated canonical ConstructSnapshot")


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert_error(result: Dictionary, code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == code, "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("T1A.7 runtime recovery: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("T1A.7 runtime recovery: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)

extends SceneTree

const RuntimeExecutorScript = preload("res://scripts/construction/behavior/construction_affordance_runtime_executor.gd")
const RuntimeStoreScript = preload("res://scripts/construction/behavior/construction_runtime_state_store.gd")
const RuntimeSubjectScript = preload("res://scripts/construction/behavior/construction_runtime_subject_state.gd")
const OperationLedgerScript = preload("res://scripts/items/services/item_operation_ledger.gd")
const RuntimeLabScript = preload("res://scripts/labs/t1/t1_d0_interactive_runtime_executor.gd")
const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

var assertions: int = 0
var failures: Array[String] = []
var _effect_mode: String = "SUCCESS"
var _effect_calls: int = 0


func _init() -> void:
	_test_generic_transactional_effect_boundary()
	_test_d0_utility_effect_exactly_once()
	_finish()


func _test_generic_transactional_effect_boundary() -> void:
	var success_store = _make_store()
	var success_ledger = OperationLedgerScript.new()
	var success_executor = RuntimeExecutorScript.new()
	_effect_mode = "SUCCESS"
	_effect_calls = 0
	_assert_ok(success_executor.setup(
		success_store,
		success_ledger,
		Callable(self, "_generic_handler"),
		Callable(self, "_generic_effect_committer")
	), "Transactional executor setup failed")
	var success_command := RuntimeExecutorScript.create_command(
		"operation/t1a5/transaction/success",
		"SET_VALUE",
		"runtime/test/transaction",
		0,
		{"value": 1}
	)
	var success: Dictionary = success_executor.execute(success_command)
	_assert_ok(success, "Transactional success command failed")
	_assert(_effect_calls == 1, "Successful transactional effect was not committed exactly once")
	_assert(int(success_store.get_subject("runtime/test/transaction").revision) == 1, "Successful transaction revision mismatch")
	_assert(int(success_store.get_subject("runtime/test/transaction").state.value) == 1, "Successful transaction state mismatch")
	_assert(bool(Dictionary(success.get("details", {})).get("transactional_effect_committed", false)), "Successful transaction did not report committed effect")
	var success_generation := success_store.get_generation()
	var success_replay: Dictionary = success_executor.execute(success_command)
	_assert(UtilsScript.canonical_json(success_replay) == UtilsScript.canonical_json(success), "Successful transaction replay changed result")
	_assert(_effect_calls == 1, "Successful transaction replay committed effect twice")
	_assert(success_store.get_generation() == success_generation, "Successful transaction replay changed runtime generation")

	var fail_store = _make_store()
	var fail_ledger = OperationLedgerScript.new()
	var fail_executor = RuntimeExecutorScript.new()
	_effect_mode = "FAIL"
	_effect_calls = 0
	_assert_ok(fail_executor.setup(
		fail_store,
		fail_ledger,
		Callable(self, "_generic_handler"),
		Callable(self, "_generic_effect_committer")
	), "Rollback executor setup failed")
	var before_store := UtilsScript.canonical_json(fail_store.to_dict())
	var fail_command := RuntimeExecutorScript.create_command(
		"operation/t1a5/transaction/fail",
		"SET_VALUE",
		"runtime/test/transaction",
		0,
		{"value": 2}
	)
	var failed: Dictionary = fail_executor.execute(fail_command)
	_assert_error(failed, "TEST_EFFECT_COMMIT_FAILED", "Failed effect commit was not rejected")
	_assert(_effect_calls == 1, "Failed effect committer call count mismatch")
	_assert(UtilsScript.canonical_json(fail_store.to_dict()) == before_store, "Failed effect commit left partial runtime state")
	_assert(int(fail_store.get_subject("runtime/test/transaction").revision) == 0, "Failed effect commit left advanced subject revision")
	_assert(fail_ledger.size() == 1, "Failed transaction was not terminally recorded")
	_assert(String(fail_ledger.get_record("operation/t1a5/transaction/fail").status) == OperationLedgerScript.STATUS_REJECTED, "Failed transaction ledger status mismatch")
	var fail_replay: Dictionary = fail_executor.execute(fail_command)
	_assert(UtilsScript.canonical_json(fail_replay) == UtilsScript.canonical_json(failed), "Failed transaction replay changed result")
	_assert(_effect_calls == 1, "Failed transaction replay called effect committer twice")
	_assert(UtilsScript.canonical_json(fail_store.to_dict()) == before_store, "Failed transaction replay changed runtime state")


func _test_d0_utility_effect_exactly_once() -> void:
	var root := "user://t1a5-transactional-effects-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var runtime = RuntimeLabScript.new()
	_assert_ok(runtime.setup(root), "D0 transactional runtime setup failed")
	var before: Dictionary = runtime.get_report()
	var before_tick := int(before.power_tick)
	var stop: Dictionary = runtime.execute(
		"GENERATOR",
		"STOP_GENERATOR",
		"operation/t1a5/transaction/generator-stop",
		0
	)
	_assert_ok(stop, "D0 generator stop transaction failed")
	_assert(bool(Dictionary(stop.get("details", {})).get("transactional_effect_committed", false)), "D0 generator stop did not use transactional effect boundary")
	var after_stop: Dictionary = runtime.get_report()
	_assert(int(after_stop.power_tick) == before_tick + 1, "D0 committed utility effect did not advance exactly one tick")
	_assert(not bool(runtime.get_subject("GENERATOR").state.running), "D0 generator state did not commit")
	var after_stop_storage := UtilsScript.canonical_json(Dictionary(after_stop.power_storage))
	var stop_replay: Dictionary = runtime.execute(
		"GENERATOR",
		"STOP_GENERATOR",
		"operation/t1a5/transaction/generator-stop",
		0
	)
	_assert(UtilsScript.canonical_json(stop_replay) == UtilsScript.canonical_json(stop), "D0 transactional replay changed result")
	var after_replay: Dictionary = runtime.get_report()
	_assert(int(after_replay.power_tick) == int(after_stop.power_tick), "D0 transactional replay advanced utility tick twice")
	_assert(UtilsScript.canonical_json(Dictionary(after_replay.power_storage)) == after_stop_storage, "D0 transactional replay changed battery state")
	_assert(int(runtime.get_subject("GENERATOR").revision) == 1, "D0 transactional replay advanced generator revision")

	var before_stale: Dictionary = runtime.get_report()
	var generator_before_stale := UtilsScript.canonical_json(runtime.get_subject("GENERATOR"))
	var stale: Dictionary = runtime.execute(
		"GENERATOR",
		"START_GENERATOR",
		"operation/t1a5/transaction/generator-stale",
		0
	)
	_assert_error(stale, "CONSTRUCTION_RUNTIME_REVISION_MISMATCH", "D0 stale transactional command was accepted")
	var after_stale: Dictionary = runtime.get_report()
	_assert(int(after_stale.power_tick) == int(before_stale.power_tick), "Rejected D0 transaction advanced utility tick")
	_assert(UtilsScript.canonical_json(Dictionary(after_stale.power_storage)) == UtilsScript.canonical_json(Dictionary(before_stale.power_storage)), "Rejected D0 transaction changed battery state")
	_assert(UtilsScript.canonical_json(runtime.get_subject("GENERATOR")) == generator_before_stale, "Rejected D0 transaction changed generator state")


func _make_store():
	var store = RuntimeStoreScript.new()
	_assert_ok(store.setup(), "Runtime store setup failed")
	var subject := RuntimeSubjectScript.create(
		"runtime/test/transaction",
		"construct/test/transaction",
		"item/test/transaction",
		"capability/test/transaction",
		0,
		{"kind": "TEST", "value": 0}
	)
	_assert_ok(store.register_subject(subject), "Runtime transaction subject registration failed")
	return store


func _generic_handler(command: Dictionary, subject: Dictionary) -> Dictionary:
	var next_state: Dictionary = Dictionary(subject.state).duplicate(true)
	next_state["value"] = int(Dictionary(command.payload).get("value", 0))
	return {
		"success": true,
		"mutates": true,
		"next_state": next_state,
		"effect": {"kind": "TEST_EFFECT", "value": int(next_state.value)},
		"details": {"kind": "TEST"},
	}


func _generic_effect_committer(_command: Dictionary, _before: Dictionary, _after: Dictionary, _effect: Dictionary) -> Dictionary:
	_effect_calls += 1
	if _effect_mode == "FAIL":
		return {"success": false, "error_code": "TEST_EFFECT_COMMIT_FAILED", "details": {}}
	return {"success": true, "error_code": ""}


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
		print("T1A.5 transactional runtime effects: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("T1A.5 transactional runtime effects: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)

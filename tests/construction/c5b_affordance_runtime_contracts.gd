extends SceneTree

const SubjectScript = preload("res://scripts/construction/behavior/construction_runtime_subject_state.gd")
const StoreScript = preload("res://scripts/construction/behavior/construction_runtime_state_store.gd")
const ExecutorScript = preload("res://scripts/construction/behavior/construction_affordance_runtime_executor.gd")
const LedgerScript = preload("res://scripts/items/services/item_operation_ledger.gd")
const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_subject_and_store()
	_test_executor_replay_and_conflict()
	_finish()


func _subject() -> Dictionary:
	return SubjectScript.create(
		"runtime/contracts/door",
		"construct/contracts/runtime",
		"item/11111111-1111-4111-8111-111111111111",
		"capability/contracts/door",
		0,
		{"kind": "TEST", "enabled": false}
	)


func _test_subject_and_store() -> void:
	var subject: Dictionary = _subject()
	_assert_ok(SubjectScript.validate(subject), "Runtime subject rejected")
	_assert(String(subject.checksum).length() == 64, "Runtime subject checksum missing")
	var tampered: Dictionary = subject.duplicate(true)
	tampered.state.enabled = true
	_assert_error(SubjectScript.validate(tampered), "CONSTRUCTION_RUNTIME_SUBJECT_CHECKSUM_MISMATCH", "Tampered runtime subject accepted")

	var store = StoreScript.new()
	_assert_ok(store.setup(), "Runtime store setup failed")
	var registered: Dictionary = store.register_subject(subject)
	_assert_ok(registered, "Runtime subject registration failed")
	_assert(not bool(registered.get("replay", true)), "First runtime subject registration marked replay")
	var replay: Dictionary = store.register_subject(subject)
	_assert_ok(replay, "Runtime subject replay failed")
	_assert(bool(replay.get("replay", false)), "Runtime subject replay not detected")
	var updated: Dictionary = store.update_subject("runtime/contracts/door", 0, {"kind": "TEST", "enabled": true})
	_assert_ok(updated, "Runtime subject update failed")
	_assert(int(updated.after.revision) == 1, "Runtime subject revision did not advance")
	_assert(bool(updated.after.state.enabled), "Runtime subject next state missing")
	_assert_error(store.update_subject("runtime/contracts/door", 0, {"kind": "TEST", "enabled": false}), "CONSTRUCTION_RUNTIME_REVISION_MISMATCH", "Stale runtime update accepted")
	var state: Dictionary = store.to_dict()
	_assert_ok(StoreScript.validate_state(state), "Runtime store state invalid")
	var clone = StoreScript.new()
	_assert_ok(clone.setup(), "Runtime clone setup failed")
	_assert_ok(clone.load_dict(state), "Runtime store roundtrip failed")
	_assert(UtilsScript.canonical_json(clone.to_dict()) == UtilsScript.canonical_json(state), "Runtime store JSON roundtrip changed semantics")


func _test_executor_replay_and_conflict() -> void:
	var store = StoreScript.new()
	store.setup()
	store.register_subject(_subject())
	var ledger = LedgerScript.new()
	var executor = ExecutorScript.new()
	_assert_ok(executor.setup(store, ledger, Callable(self, "_handler")), "Runtime executor setup failed")

	var command: Dictionary = ExecutorScript.create_command(
		"operation/contracts/runtime/toggle-1",
		"TOGGLE_TEST",
		"runtime/contracts/door",
		0,
		{}
	)
	_assert_ok(ExecutorScript.validate_command(command), "Runtime command invalid")
	var first: Dictionary = executor.execute(command)
	_assert_ok(first, "Runtime command failed")
	_assert(String(first.status) == LedgerScript.STATUS_SUCCEEDED, "Runtime command status mismatch")
	_assert(int(first.result_revision) == 1, "Runtime command result revision mismatch")
	_assert(bool(store.get_subject("runtime/contracts/door").state.enabled), "Runtime command did not mutate subject")
	var generation_after_first := store.get_generation()
	var replay: Dictionary = executor.execute(command)
	_assert(UtilsScript.canonical_json(replay) == UtilsScript.canonical_json(first), "Runtime exact replay changed result")
	_assert(store.get_generation() == generation_after_first, "Runtime replay mutated state")
	_assert(ledger.size() == 1, "Runtime replay added ledger record")

	var conflict: Dictionary = command.duplicate(true)
	conflict.payload = {"different": true}
	var conflict_result: Dictionary = executor.execute(conflict)
	_assert_error(conflict_result, "OPERATION_ID_CONFLICT", "Runtime operation conflict not detected")
	_assert(store.get_generation() == generation_after_first, "Runtime conflict mutated state")

	var stale: Dictionary = ExecutorScript.create_command(
		"operation/contracts/runtime/stale",
		"TOGGLE_TEST",
		"runtime/contracts/door",
		0,
		{}
	)
	var stale_result: Dictionary = executor.execute(stale)
	_assert_error(stale_result, "CONSTRUCTION_RUNTIME_REVISION_MISMATCH", "Stale runtime command accepted")
	_assert(String(stale_result.status) == LedgerScript.STATUS_REJECTED, "Stale runtime command not terminally rejected")

	var read: Dictionary = ExecutorScript.create_command(
		"operation/contracts/runtime/read",
		"READ_TEST",
		"runtime/contracts/door",
		1,
		{}
	)
	var read_result: Dictionary = executor.execute(read)
	_assert_ok(read_result, "Runtime read command failed")
	_assert(int(read_result.result_revision) == 1, "Runtime read changed revision")
	_assert(store.get_generation() == generation_after_first, "Runtime read mutated state")


func _handler(command: Dictionary, subject: Dictionary) -> Dictionary:
	match String(command.action_kind):
		"TOGGLE_TEST":
			var next_state: Dictionary = Dictionary(subject.state).duplicate(true)
			next_state.enabled = not bool(next_state.get("enabled", false))
			return {"success": true, "mutates": true, "next_state": next_state, "details": {"handled": true}}
		"READ_TEST":
			return {"success": true, "mutates": false, "next_state": Dictionary(subject.state).duplicate(true), "details": {"enabled": bool(subject.state.enabled)}}
	return {"success": false, "error_code": "TEST_ACTION_REJECTED", "mutates": false, "details": {}}


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
		print("C5B affordance runtime contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("C5B affordance runtime contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)

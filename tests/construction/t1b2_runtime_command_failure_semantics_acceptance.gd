extends SceneTree

const RuntimeExecutorScript = preload("res://scripts/construction/behavior/construction_affordance_runtime_executor.gd")
const RuntimeStoreScript = preload("res://scripts/construction/behavior/construction_runtime_state_store.gd")
const RuntimeSubjectScript = preload("res://scripts/construction/behavior/construction_runtime_subject_state.gd")
const CommandFailureHandlerScript = preload("res://scripts/construction/behavior/construction_runtime_command_failure_handler.gd")
const OperationLedgerScript = preload("res://scripts/items/services/item_operation_ledger.gd")
const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const RUNTIME_ID: String = "runtime/t1b2/command/device"
const CONSTRUCT_ID: String = "construct/t1b2/command/device"

var assertions: int = 0
var failures: Array[String] = []
var _handler_calls: int = 0
var _effect_calls: int = 0
var _effect_mode: String = "SUCCESS"


func _init() -> void:
	_test_failure_aware_command_boundary()
	_test_invalid_policy_configuration()
	_finish()


func _test_failure_aware_command_boundary() -> void:
	var store = RuntimeStoreScript.new()
	_assert_ok(store.setup(), "store setup")
	_assert_ok(store.register_subject(RuntimeSubjectScript.create(
		RUNTIME_ID,
		CONSTRUCT_ID,
		"item/t1b2/command/device",
		"capability/t1b2/command/device",
		0,
		{
			"kind": "TEST_DEVICE",
			"value": 0,
			"operability": "OFFLINE",
			"failure_codes": ["POWER_UNAVAILABLE"],
		}
	)), "subject registration")

	var failure_handler = CommandFailureHandlerScript.new()
	_assert_ok(failure_handler.setup(
		Callable(self, "_base_handler"),
		{
			"SET_VALUE": CommandFailureHandlerScript.POLICY_REQUIRE_ONLINE,
			"DEGRADED_SET": CommandFailureHandlerScript.POLICY_ALLOW_DEGRADED,
			"DIAGNOSTIC": CommandFailureHandlerScript.POLICY_ALLOW_OFFLINE,
		}
	), "failure handler setup")
	var report: Dictionary = failure_handler.report()
	_assert(int(report.get("policy_count", -1)) == 3, "failure handler policy count mismatch")
	_assert(not bool(report.get("mutates_canonical_state", true)), "failure handler claims canonical mutation")
	_assert(not bool(report.get("owns_operation_ledger", true)), "failure handler claims operation ledger ownership")
	_assert(not bool(report.get("owns_transaction_commit", true)), "failure handler claims transaction ownership")

	var ledger = OperationLedgerScript.new()
	var executor = RuntimeExecutorScript.new()
	_assert_ok(executor.setup(
		store,
		ledger,
		Callable(failure_handler, "handle"),
		Callable(self, "_effect_committer")
	), "executor setup")

	var offline_before: String = UtilsScript.canonical_json(store.to_dict())
	var offline_command: Dictionary = RuntimeExecutorScript.create_command(
		"operation/t1b2/offline/reject",
		"SET_VALUE",
		RUNTIME_ID,
		0,
		{"value": 1}
	)
	var offline_rejected: Dictionary = executor.execute(offline_command)
	_assert_error(offline_rejected, "CONSTRUCTION_RUNTIME_SUBJECT_OFFLINE", "offline mutating command not rejected")
	_assert(_handler_calls == 0, "offline rejection reached base handler")
	_assert(_effect_calls == 0, "offline rejection reached effect committer")
	_assert(UtilsScript.canonical_json(store.to_dict()) == offline_before, "offline rejection mutated runtime store")
	_assert(String(ledger.get_record("operation/t1b2/offline/reject").status) == OperationLedgerScript.STATUS_REJECTED, "offline rejection not terminally recorded")
	var offline_replay: Dictionary = executor.execute(offline_command)
	_assert(UtilsScript.canonical_json(offline_replay) == UtilsScript.canonical_json(offline_rejected), "offline rejection replay changed result")
	_assert(_handler_calls == 0 and _effect_calls == 0, "offline rejection replay caused side effects")

	var diagnostic: Dictionary = executor.execute(RuntimeExecutorScript.create_command(
		"operation/t1b2/offline/diagnostic",
		"DIAGNOSTIC",
		RUNTIME_ID,
		0,
		{}
	))
	_assert_ok(diagnostic, "offline diagnostic command")
	_assert(_handler_calls == 1, "offline diagnostic did not reach base handler")
	_assert(_effect_calls == 0, "offline diagnostic unexpectedly committed effect")
	_assert(int(store.get_subject(RUNTIME_ID).revision) == 0, "offline diagnostic mutated subject")
	var diagnostic_details: Dictionary = Dictionary(diagnostic.get("details", {}))
	_assert(String(diagnostic_details.get("runtime_operability", "")) == "OFFLINE", "offline diagnostic operability detail mismatch")
	_assert(String(diagnostic_details.get("command_failure_policy", "")) == "ALLOW_OFFLINE", "offline diagnostic policy detail mismatch")
	_assert(not bool(diagnostic_details.get("degraded_execution", true)), "offline diagnostic marked degraded")

	var degraded_state: Dictionary = Dictionary(store.get_subject(RUNTIME_ID).state).duplicate(true)
	degraded_state["operability"] = "DEGRADED"
	degraded_state["failure_codes"] = ["DATA_UNAVAILABLE"]
	_assert_ok(store.update_subject(RUNTIME_ID, 0, degraded_state), "transition to degraded")
	_assert(int(store.get_subject(RUNTIME_ID).revision) == 1, "degraded transition revision mismatch")

	var degraded_rejected: Dictionary = executor.execute(RuntimeExecutorScript.create_command(
		"operation/t1b2/degraded/reject",
		"SET_VALUE",
		RUNTIME_ID,
		1,
		{"value": 2}
	))
	_assert_error(degraded_rejected, "CONSTRUCTION_RUNTIME_SUBJECT_DEGRADED", "online-only command accepted while degraded")
	_assert(_handler_calls == 1, "degraded rejection reached base handler")
	_assert(_effect_calls == 0, "degraded rejection reached effect committer")
	_assert(int(store.get_subject(RUNTIME_ID).revision) == 1, "degraded rejection advanced revision")

	var degraded_allowed_command: Dictionary = RuntimeExecutorScript.create_command(
		"operation/t1b2/degraded/allowed",
		"DEGRADED_SET",
		RUNTIME_ID,
		1,
		{"value": 5}
	)
	var degraded_allowed: Dictionary = executor.execute(degraded_allowed_command)
	_assert_ok(degraded_allowed, "degraded-capable command")
	_assert(_handler_calls == 2, "degraded-capable command handler count mismatch")
	_assert(_effect_calls == 1, "degraded-capable command effect count mismatch")
	_assert(int(store.get_subject(RUNTIME_ID).revision) == 2, "degraded-capable command revision mismatch")
	_assert(int(Dictionary(store.get_subject(RUNTIME_ID).state).get("value", -1)) == 5, "degraded-capable command value mismatch")
	var degraded_details: Dictionary = Dictionary(degraded_allowed.get("details", {}))
	_assert(bool(degraded_details.get("degraded_execution", false)), "degraded-capable command did not report degraded execution")
	_assert(String(degraded_details.get("command_failure_policy", "")) == "ALLOW_DEGRADED", "degraded-capable command policy detail mismatch")
	var degraded_generation: int = store.get_generation()
	var degraded_replay: Dictionary = executor.execute(degraded_allowed_command)
	_assert(UtilsScript.canonical_json(degraded_replay) == UtilsScript.canonical_json(degraded_allowed), "degraded command replay changed result")
	_assert(_handler_calls == 2 and _effect_calls == 1, "degraded command replay duplicated handler/effect")
	_assert(store.get_generation() == degraded_generation, "degraded command replay changed generation")

	var online_state: Dictionary = Dictionary(store.get_subject(RUNTIME_ID).state).duplicate(true)
	online_state["operability"] = "ONLINE"
	online_state["failure_codes"] = []
	_assert_ok(store.update_subject(RUNTIME_ID, 2, online_state), "transition to online")
	_assert(int(store.get_subject(RUNTIME_ID).revision) == 3, "online transition revision mismatch")

	var online: Dictionary = executor.execute(RuntimeExecutorScript.create_command(
		"operation/t1b2/online/success",
		"SET_VALUE",
		RUNTIME_ID,
		3,
		{"value": 7}
	))
	_assert_ok(online, "online command")
	_assert(_handler_calls == 3 and _effect_calls == 2, "online command handler/effect count mismatch")
	_assert(int(store.get_subject(RUNTIME_ID).revision) == 4, "online command revision mismatch")
	_assert(int(Dictionary(store.get_subject(RUNTIME_ID).state).get("value", -1)) == 7, "online command value mismatch")
	var online_details: Dictionary = Dictionary(online.get("details", {}))
	_assert(String(online_details.get("runtime_operability", "")) == "ONLINE", "online command operability detail mismatch")
	_assert(not bool(online_details.get("degraded_execution", true)), "online command marked degraded")

	_effect_mode = "FAIL"
	var before_failed_effect: String = UtilsScript.canonical_json(store.to_dict())
	var failed_effect_command: Dictionary = RuntimeExecutorScript.create_command(
		"operation/t1b2/online/effect-fail",
		"SET_VALUE",
		RUNTIME_ID,
		4,
		{"value": 9}
	)
	var failed_effect: Dictionary = executor.execute(failed_effect_command)
	_assert_error(failed_effect, "TEST_EFFECT_COMMIT_FAILED", "failed effect was not rejected")
	_assert(_handler_calls == 4 and _effect_calls == 3, "failed effect call counts mismatch")
	_assert(UtilsScript.canonical_json(store.to_dict()) == before_failed_effect, "failed effect left partial runtime state")
	_assert(int(store.get_subject(RUNTIME_ID).revision) == 4, "failed effect left advanced revision")
	var failed_effect_replay: Dictionary = executor.execute(failed_effect_command)
	_assert(UtilsScript.canonical_json(failed_effect_replay) == UtilsScript.canonical_json(failed_effect), "failed effect replay changed result")
	_assert(_handler_calls == 4 and _effect_calls == 3, "failed effect replay duplicated work")
	_assert(UtilsScript.canonical_json(store.to_dict()) == before_failed_effect, "failed effect replay changed state")
	_effect_mode = "SUCCESS"

	var missing_policy: Dictionary = executor.execute(RuntimeExecutorScript.create_command(
		"operation/t1b2/policy/missing",
		"UNDECLARED_ACTION",
		RUNTIME_ID,
		4,
		{}
	))
	_assert_error(missing_policy, "CONSTRUCTION_RUNTIME_COMMAND_FAILURE_POLICY_MISSING", "undeclared action did not fail closed")
	_assert(_handler_calls == 4 and _effect_calls == 3, "missing policy reached base handler/effect")
	_assert(int(store.get_subject(RUNTIME_ID).revision) == 4, "missing policy changed subject revision")


func _test_invalid_policy_configuration() -> void:
	var invalid = CommandFailureHandlerScript.new()
	_assert_error(invalid.setup(Callable(self, "_base_handler"), {}), "CONSTRUCTION_RUNTIME_COMMAND_FAILURE_POLICY_REQUIRED", "empty policy accepted")
	_assert_error(invalid.setup(Callable(self, "_base_handler"), {"set_value": "REQUIRE_ONLINE"}), "INVALID_CONSTRUCTION_RUNTIME_ACTION_KIND", "lowercase action policy accepted")
	_assert_error(invalid.setup(Callable(self, "_base_handler"), {"SET_VALUE": "UNKNOWN"}), "INVALID_CONSTRUCTION_RUNTIME_COMMAND_FAILURE_POLICY", "unknown command policy accepted")
	var unconfigured = CommandFailureHandlerScript.new()
	_assert_error(unconfigured.handle({}, {}), "CONSTRUCTION_RUNTIME_COMMAND_FAILURE_HANDLER_NOT_CONFIGURED", "unconfigured handler accepted command")


func _base_handler(command: Dictionary, subject: Dictionary) -> Dictionary:
	_handler_calls += 1
	if String(command.get("action_kind", "")) == "DIAGNOSTIC":
		return {
			"success": true,
			"mutates": false,
			"details": {"diagnostic": true},
		}
	var next_state: Dictionary = Dictionary(subject.get("state", {})).duplicate(true)
	next_state["value"] = int(Dictionary(command.get("payload", {})).get("value", 0))
	return {
		"success": true,
		"mutates": true,
		"next_state": next_state,
		"effect": {"kind": "TEST_EFFECT", "value": int(next_state.get("value", 0))},
		"details": {"kind": "TEST_COMMAND"},
	}


func _effect_committer(_command: Dictionary, _before: Dictionary, _after: Dictionary, _effect: Dictionary) -> Dictionary:
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
		print("T1B.2 runtime command failure semantics: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("T1B.2 runtime command failure semantics: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)

extends SceneTree

const RuntimeLabScript = preload("res://scripts/labs/t1/t1_d0_interactive_runtime_executor.gd")
const RuntimeStoreScript = preload("res://scripts/construction/behavior/construction_runtime_state_store.gd")
const ExecutionProfileScript = preload("res://scripts/construction/utilities/construction_utility_execution_profile.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const CONSTRUCT_ID := "construct/t1/lunar-outpost/d0"

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_runtime_bootstrap_and_actions()
	_finish()


func _test_runtime_bootstrap_and_actions() -> void:
	var root := "user://t1a5-acceptance-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var runtime = RuntimeLabScript.new()
	var setup: Dictionary = runtime.setup(root)
	_assert_ok(setup, "T1A.5 runtime setup failed")
	if not bool(setup.get("success", false)):
		return

	var report: Dictionary = runtime.get_report()
	_assert(String(report.get("schema", "")) == RuntimeLabScript.SCHEMA, "Runtime report schema mismatch")
	_assert(String(report.get("construct_id", "")) == CONSTRUCT_ID, "Runtime report construct mismatch")
	_assert_ok(RuntimeStoreScript.validate_state(Dictionary(report["runtime_state"])), "Runtime state store invalid")
	_assert(Array(Dictionary(report["runtime_state"])["subjects"]).size() == 4, "Expected four executable runtime subjects")
	_assert(int(Dictionary(report["runtime_state"])["generation"]) == 4, "Runtime bootstrap generation mismatch")
	_assert_ok(ExecutionProfileScript.validate(Dictionary(report["power_execution_profile"])), "Runtime power profile invalid")
	_assert_ok(ExecutionProfileScript.validate(Dictionary(report["data_execution_profile"])), "Runtime data profile invalid")
	_assert(String(report["power_execution_profile"].status) == "BALANCED", "Runtime power bootstrap is not balanced")
	_assert(String(report["data_execution_profile"].status) == "BALANCED", "Runtime data bootstrap is not balanced")

	_assert(String(runtime.get_subject("DOOR").state.position) == "CLOSED", "Door initial state mismatch")
	_assert(bool(runtime.get_subject("GENERATOR").state.running), "Generator should start running")
	_assert(not bool(runtime.get_subject("LAMP").state.on), "Lamp should start off")
	_assert(not bool(runtime.get_subject("CONSOLE").state.active), "Console should start inactive")

	var bound: Dictionary = runtime.get_bound_composition()
	var adapter = bound["adapter"]
	var construct_before: Dictionary = adapter.get_construct_snapshot(CONSTRUCT_ID)
	_assert_ok(SnapshotScript.validate(construct_before), "Bound construct invalid before runtime actions")
	var adapter_before := UtilsScript.canonical_json(adapter.export_state())
	var item_graph_before := UtilsScript.canonical_json(Dictionary(adapter.export_state().get("item_registry", {})))

	var open: Dictionary = runtime.execute("DOOR", "OPEN_DOOR", "operation/t1a5/d0/door/open-1", 0)
	_assert_ok(open, "Door OPEN failed")
	_assert(int(open.result_revision) == 1, "Door OPEN revision mismatch")
	_assert(String(runtime.get_subject("DOOR").state.position) == "OPEN", "Door did not open")
	var replay: Dictionary = runtime.execute("DOOR", "OPEN_DOOR", "operation/t1a5/d0/door/open-1", 0)
	_assert(UtilsScript.canonical_json(replay) == UtilsScript.canonical_json(open), "Door exact replay changed result")
	_assert(int(runtime.get_subject("DOOR").revision) == 1, "Door replay changed revision")
	_assert(int(runtime.get_report().operation_count) == 1, "Door replay added runtime operation")

	var conflict: Dictionary = runtime.execute("DOOR", "CLOSE_DOOR", "operation/t1a5/d0/door/open-1", 1)
	_assert_error(conflict, "OPERATION_ID_CONFLICT", "Runtime operation-id conflict not detected")
	_assert(String(runtime.get_subject("DOOR").state.position) == "OPEN", "Runtime conflict mutated door")

	var close: Dictionary = runtime.execute("DOOR", "CLOSE_DOOR", "operation/t1a5/d0/door/close-1", 1)
	_assert_ok(close, "Door CLOSE failed")
	_assert(int(close.result_revision) == 2, "Door CLOSE revision mismatch")
	_assert(String(runtime.get_subject("DOOR").state.position) == "CLOSED", "Door did not close")

	var storage_before_stop := float(runtime.get_report().power_storage.stored_amount)
	var power_tick_before_stop := int(runtime.get_report().power_tick)
	var stop: Dictionary = runtime.execute("GENERATOR", "STOP_GENERATOR", "operation/t1a5/d0/generator/stop-1", 0)
	_assert_ok(stop, "Generator STOP failed")
	_assert(not bool(runtime.get_subject("GENERATOR").state.running), "Generator did not stop")
	_assert(int(runtime.get_subject("GENERATOR").revision) == 1, "Generator STOP revision mismatch")
	_assert(int(runtime.get_report().power_tick) == power_tick_before_stop + 1, "Generator STOP did not advance utility tick")
	_assert(float(runtime.get_report().power_storage.stored_amount) < storage_before_stop, "Battery did not discharge after generator stop")
	_assert(String(runtime.get_report().power_execution_profile.status) == "BALANCED", "Door standby should remain powered from battery")

	var toggle: Dictionary = runtime.execute("LAMP", "TOGGLE_LIGHT", "operation/t1a5/d0/lamp/toggle-1", 0)
	_assert_ok(toggle, "Lamp toggle failed")
	_assert(bool(runtime.get_subject("LAMP").state.on), "Lamp did not turn on")
	_assert(int(runtime.get_subject("LAMP").revision) == 1, "Lamp revision mismatch")
	_assert_ok(ExecutionProfileScript.validate(Dictionary(runtime.get_report().power_execution_profile)), "Power profile invalid after lamp toggle")

	var storage_before_start := float(runtime.get_report().power_storage.stored_amount)
	var start: Dictionary = runtime.execute("GENERATOR", "START_GENERATOR", "operation/t1a5/d0/generator/start-1", 1)
	_assert_ok(start, "Generator START failed")
	_assert(bool(runtime.get_subject("GENERATOR").state.running), "Generator did not start")
	_assert(int(runtime.get_subject("GENERATOR").revision) == 2, "Generator START revision mismatch")
	_assert(float(runtime.get_report().power_storage.stored_amount) > storage_before_start, "Generator restart did not recharge battery")
	_assert(String(runtime.get_report().power_execution_profile.status) == "BALANCED", "Power network not balanced after generator restart")

	var use_console: Dictionary = runtime.execute("CONSOLE", "USE_WORKSTATION", "operation/t1a5/d0/console/use-1", 0)
	_assert_ok(use_console, "Console use failed")
	_assert(bool(runtime.get_subject("CONSOLE").state.active), "Console did not become active")
	_assert(int(runtime.get_subject("CONSOLE").state.use_count) == 1, "Console use count mismatch")
	_assert(int(runtime.get_subject("CONSOLE").revision) == 1, "Console revision mismatch")
	_assert(String(runtime.get_report().power_execution_profile.status) == "BALANCED", "Console activation destabilized powered D0")

	var lamp_before_stale := UtilsScript.canonical_json(runtime.get_subject("LAMP"))
	var stale: Dictionary = runtime.execute("LAMP", "TOGGLE_LIGHT", "operation/t1a5/d0/lamp/stale", 0)
	_assert_error(stale, "CONSTRUCTION_RUNTIME_REVISION_MISMATCH", "Stale lamp action accepted")
	_assert(UtilsScript.canonical_json(runtime.get_subject("LAMP")) == lamp_before_stale, "Stale lamp action mutated runtime state")
	var stale_replay: Dictionary = runtime.execute("LAMP", "TOGGLE_LIGHT", "operation/t1a5/d0/lamp/stale", 0)
	_assert(UtilsScript.canonical_json(stale_replay) == UtilsScript.canonical_json(stale), "Rejected runtime command replay changed result")

	var wrong_action: Dictionary = runtime.execute("LAMP", "OPEN_DOOR", "operation/t1a5/d0/lamp/wrong-action", 1)
	_assert_error(wrong_action, "T1A5_ACTION_NOT_SUPPORTED_BY_RUNTIME", "Runtime accepted affordance on wrong capability")
	_assert(bool(runtime.get_subject("LAMP").state.on), "Rejected wrong action mutated lamp")

	var final_report: Dictionary = runtime.get_report()
	_assert_ok(RuntimeStoreScript.validate_state(Dictionary(final_report["runtime_state"])), "Final runtime state invalid")
	_assert_ok(ExecutionProfileScript.validate(Dictionary(final_report["power_execution_profile"])), "Final power execution profile invalid")
	_assert_ok(ExecutionProfileScript.validate(Dictionary(final_report["data_execution_profile"])), "Final data execution profile invalid")
	_assert(int(final_report.operation_count) >= 7, "Runtime operation ledger did not record terminal operations")

	var construct_after: Dictionary = adapter.get_construct_snapshot(CONSTRUCT_ID)
	_assert(UtilsScript.canonical_json(construct_after) == UtilsScript.canonical_json(construct_before), "Runtime execution mutated canonical ConstructSnapshot")
	_assert(UtilsScript.canonical_json(adapter.export_state()) == adapter_before, "Runtime execution mutated C2B/M0 authoritative composition")
	_assert(UtilsScript.canonical_json(Dictionary(adapter.export_state().get("item_registry", {}))) == item_graph_before, "Runtime execution mutated Item Graph state")
	var snapshot_text := JSON.stringify(construct_after)
	for forbidden in ["runtime/t1a5", "construction_runtime", "power_tick", "use_count", "OPEN_DOOR", "TOGGLE_LIGHT"]:
		_assert(not snapshot_text.contains(forbidden), "Runtime execution leaked into canonical ConstructSnapshot: %s" % forbidden)
	var report_text := JSON.stringify(final_report)
	_assert(not report_text.contains("server_id"), "Runtime report encoded server routing identity")
	_assert(not report_text.contains("visual_profile_id"), "Runtime report encoded presentation identity")
	_assert(not report_text.contains("material_definition_id"), "Runtime report invented material ontology")


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
		print("T1A.5 interactive runtime execution: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("T1A.5 interactive runtime execution: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)

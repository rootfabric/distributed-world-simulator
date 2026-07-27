extends SceneTree

const LifecycleCoordinatorScript = preload(
	"res://scripts/runtime/lifecycle_coordinator.gd"
)

class FakeRuntime:
	extends Node
	var request_count: int = 0
	var drain_count: int = 0
	var requested_reason: String = ""
	var timeout_ms: int = -1

	func request_runtime_stop(reason: String) -> Dictionary:
		request_count += 1
		requested_reason = reason
		return {"success": true, "drained": false}

	func drain_runtime_stop(timeout_value: int) -> Dictionary:
		drain_count += 1
		timeout_ms = timeout_value
		return {"success": true, "drained": true, "elapsed_ms": 4}


var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	var coordinator = LifecycleCoordinatorScript.new()
	coordinator.setup({"node_id": "sim-test-01"})
	_assert(coordinator.state == LifecycleCoordinatorScript.STARTING, "setup must enter STARTING")
	_assert(not coordinator.accepts_commands(), "STARTING must not accept commands")
	_assert(bool(coordinator.mark_running().get("success", false)), "STARTING -> RUNNING failed")
	_assert(coordinator.state == LifecycleCoordinatorScript.RUNNING, "state is not RUNNING")
	_assert(coordinator.accepts_commands(), "RUNNING must accept commands")
	_assert(
		not bool(coordinator.mark_stopped().get("success", true)),
		"RUNNING -> STOPPED must be rejected"
	)

	var runtime := FakeRuntime.new()
	var drain_result: Dictionary = coordinator.drain_runtime(runtime, "world_switch", 1234)
	_assert(bool(drain_result.get("success", false)), "runtime drain failed")
	_assert(bool(drain_result.get("drained", false)), "runtime was not drained")
	_assert(runtime.request_count == 1, "request_runtime_stop was not called once")
	_assert(runtime.drain_count == 1, "drain_runtime_stop was not called once")
	_assert(runtime.requested_reason == "world_switch", "drain reason was lost")
	_assert(runtime.timeout_ms == 1234, "drain timeout was lost")
	runtime.free()

	var begin_result: Dictionary = coordinator.begin_shutdown("test_shutdown", 7)
	_assert(bool(begin_result.get("success", false)), "RUNNING -> DRAINING failed")
	_assert(coordinator.state == LifecycleCoordinatorScript.DRAINING, "state is not DRAINING")
	_assert(not coordinator.accepts_commands(), "DRAINING must reject commands")
	_assert(coordinator.is_stopping(), "DRAINING must report stopping")
	_assert(bool(coordinator.mark_stopping().get("success", false)), "DRAINING -> STOPPING failed")
	_assert(bool(coordinator.mark_stopped().get("success", false)), "STOPPING -> STOPPED failed")
	_assert(coordinator.state == LifecycleCoordinatorScript.STOPPED, "state is not STOPPED")
	_assert(bool(coordinator.begin_shutdown("duplicate", 0).get("success", false)), "STOPPED shutdown must be idempotent")

	var snapshot: Dictionary = coordinator.create_snapshot()
	_assert(String(snapshot.get("schema", "")) == LifecycleCoordinatorScript.SCHEMA, "snapshot schema mismatch")
	_assert(String(snapshot.get("node_id", "")) == "sim-test-01", "snapshot node id mismatch")
	_assert(String(snapshot.get("shutdown_reason", "")) == "test_shutdown", "shutdown reason mismatch")
	_assert(int(snapshot.get("requested_exit_code", -1)) == 7, "exit code mismatch")
	_assert(snapshot.get("transitions", []).size() == 5, "unexpected transition count")
	_assert(not bool(snapshot.get("accepts_commands", true)), "STOPPED snapshot accepts commands")

	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("Runtime lifecycle coordinator: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Runtime lifecycle coordinator: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)

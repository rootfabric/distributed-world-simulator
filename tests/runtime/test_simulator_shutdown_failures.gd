extends SceneTree

const SimulatorAppScript = preload("res://scripts/app/simulator_app.gd")
const LifecycleCoordinatorScript = preload(
	"res://scripts/runtime/lifecycle_coordinator.gd"
)
const CommandRegistryScript = preload("res://scripts/core/command_registry.gd")
const RuntimeTestRegistryScript = preload("res://scripts/core/runtime_test_registry.gd")
const WorldCatalogScript = preload("res://scripts/core/world_catalog.gd")
const SystemMenuScript = preload("res://scripts/ui/system_menu.gd")

const WORLD_CATALOG_PATH := "res://config/worlds/catalog.json"

class FailingRuntime:
	extends Node

	var failure_mode: String = "undrained"
	var request_count: int = 0
	var drain_count: int = 0

	func request_runtime_stop(_reason: String) -> Dictionary:
		request_count += 1
		if failure_mode == "request_failed":
			return {
				"success": false,
				"drained": false,
				"error_code": "REQUEST_STOP_FAILED",
			}
		return {"success": true, "drained": false}

	func drain_runtime_stop(_timeout_ms: int) -> Dictionary:
		drain_count += 1
		if failure_mode == "drained":
			return {
				"success": true,
				"drained": true,
				"within_timeout": true,
				"state": "STOPPED",
			}
		return {
			"success": true,
			"drained": false,
			"within_timeout": false,
			"state": "GENERATING",
		}

	func prepare_for_unload() -> void:
		pass


var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	_test_dispose_rejects_request_failure()
	_test_world_switch_is_blocked_by_undrained_runtime()
	_test_shutdown_does_not_publish_stopped_after_drain_failure()
	_test_failed_begin_shutdown_uses_emergency_exit()
	_finish()


func _test_dispose_rejects_request_failure() -> void:
	var fixture: Dictionary = _create_fixture("request_failed")
	var app = fixture["app"]
	var runtime = fixture["runtime"]
	var host = fixture["host"]

	var result: Dictionary = app._dispose_current_runtime("request_failure_test")
	_assert(not bool(result.get("success", true)), "request failure must reject disposal")
	_assert(String(result.get("error_code", "")) == "RUNTIME_DRAIN_FAILED", "request failure code was lost")
	_assert(bool(result.get("runtime_retained", false)), "failed drain must retain runtime")
	_assert(app.current_runtime == runtime, "failed request cleared current_runtime")
	_assert(is_instance_valid(runtime), "failed request freed runtime")
	_assert(runtime.get_parent() == host, "failed request detached runtime")
	_assert(app.current_world_id == "earth_moon", "failed request cleared world identity")
	_assert(app._runtime_release_blocked, "failed request did not fence runtime release")
	_assert(runtime.request_count == 1, "request_runtime_stop call count mismatch")
	_assert(runtime.drain_count == 0, "drain must not run after request failure")

	_destroy_fixture(fixture)


func _test_world_switch_is_blocked_by_undrained_runtime() -> void:
	var fixture: Dictionary = _create_fixture("undrained")
	var app = fixture["app"]
	var runtime = fixture["runtime"]
	var host = fixture["host"]
	app.world_catalog = WorldCatalogScript.new()
	_assert(app.world_catalog.load_catalog(WORLD_CATALOG_PATH), "world catalog failed to load")

	var result: Dictionary = app.load_world("playground", false)
	_assert(not bool(result.get("success", true)), "world switch must fail without drain barrier")
	_assert(String(result.get("error_code", "")) == "RUNTIME_DRAIN_FAILED", "world switch failure code mismatch")
	_assert(String(result.get("target_world_id", "")) == "playground", "target world was not reported")
	_assert(app.current_runtime == runtime, "blocked world switch replaced current runtime")
	_assert(app.current_world_id == "earth_moon", "blocked world switch changed world id")
	_assert(is_instance_valid(runtime), "blocked world switch freed old runtime")
	_assert(runtime.get_parent() == host, "blocked world switch detached old runtime")
	_assert(host.get_child_count() == 1, "blocked world switch left a second runtime")
	_assert(not app._loading_world, "blocked world switch left loading flag set")
	_assert(runtime.request_count == 1, "world switch stop request count mismatch")
	_assert(runtime.drain_count == 1, "world switch drain count mismatch")

	_destroy_fixture(fixture)


func _test_shutdown_does_not_publish_stopped_after_drain_failure() -> void:
	var fixture: Dictionary = _create_fixture("undrained")
	var app = fixture["app"]
	var runtime = fixture["runtime"]
	var quit_capture := {"called": false, "exit_code": -1}
	app.set_process_quit_handler_for_tests(func(exit_code: int) -> void:
		quit_capture["called"] = true
		quit_capture["exit_code"] = exit_code
	)

	var begin_result: Dictionary = app.request_graceful_shutdown("drain_failure", 0)
	_assert(bool(begin_result.get("success", false)), "shutdown begin unexpectedly failed")
	_assert(app._shutdown_in_progress, "successful shutdown begin did not set flag")
	app._complete_graceful_shutdown()

	_assert(app.lifecycle_coordinator.state == LifecycleCoordinatorScript.FAILED, "drain failure must mark lifecycle FAILED")
	_assert(not bool(quit_capture["called"]), "unsafe drain failure attempted process quit")
	_assert(not app._shutdown_in_progress, "failed drain left shutdown flag permanently stuck")
	_assert(app.current_runtime == runtime, "shutdown drain failure cleared runtime")
	_assert(is_instance_valid(runtime), "shutdown drain failure freed runtime")
	_assert(app._runtime_release_blocked, "shutdown drain failure did not fence release")
	_assert(
		not _has_transition_to(app.lifecycle_coordinator.transitions, LifecycleCoordinatorScript.STOPPED),
		"shutdown drain failure published STOPPED"
	)
	_assert(
		String(app._last_runtime_drain.get("details", {}).get("state", "")) == "GENERATING",
		"failed drain diagnostics were not retained"
	)

	runtime.failure_mode = "drained"
	var requests_before_late_load: int = runtime.request_count
	var drains_before_late_load: int = runtime.drain_count
	var host: Node = runtime.get_parent()
	var late_load_result: Dictionary = app.load_world("playground", false)
	_assert(
		not bool(late_load_result.get("success", true)),
		"FAILED lifecycle accepted world load after worker became drainable"
	)
	_assert(
		String(late_load_result.get("error_code", "")) == "RUNTIME_RELEASE_BLOCKED",
		"late world load did not preserve runtime release fence"
	)
	_assert(app.lifecycle_coordinator.state == LifecycleCoordinatorScript.FAILED, "late world load changed FAILED lifecycle")
	_assert(app.current_runtime == runtime, "late world load replaced retained runtime")
	_assert(app.current_world_id == "earth_moon", "late world load changed retained world id")
	_assert(is_instance_valid(runtime), "late world load freed retained runtime")
	_assert(runtime.get_parent() == host, "late world load detached retained runtime")
	_assert(host.get_child_count() == 1, "late world load created a second runtime")
	_assert(runtime.request_count == requests_before_late_load, "late world load retried stop request")
	_assert(runtime.drain_count == drains_before_late_load, "late world load retried drain outside emergency shutdown")
	_assert(app._runtime_release_blocked, "late world load cleared runtime release fence")

	var menu = SystemMenuScript.new()
	menu.simulator = app
	menu.status_label = Label.new()
	menu._on_world_pressed("playground")
	_assert(
		menu.status_label.text.contains("drain barrier"),
		"SystemMenu did not surface the central release-fence rejection"
	)
	_assert(app.current_runtime == runtime, "SystemMenu bypassed retained runtime fence")
	_assert(host.get_child_count() == 1, "SystemMenu created a second runtime after FAILED")
	_assert(runtime.drain_count == drains_before_late_load, "SystemMenu retried drain after FAILED")
	menu.status_label.free()
	menu.free()

	var retry_begin: Dictionary = app.request_graceful_shutdown("retry_after_drain", 0)
	_assert(not bool(retry_begin.get("success", true)), "FAILED lifecycle unexpectedly accepted retry begin")
	_assert(bool(retry_begin.get("emergency_shutdown_scheduled", false)), "retry did not schedule emergency drain")
	var retry_result: Dictionary = app._complete_emergency_shutdown(
		"begin_shutdown_failed",
		"retry_after_drain",
		0,
		retry_begin
	)
	_assert(bool(retry_result.get("success", false)), "recovered drain did not complete emergency shutdown")
	_assert(bool(quit_capture["called"]), "recovered drain did not request process quit")
	_assert(int(quit_capture["exit_code"]) == 1, "recovered failed lifecycle must exit non-zero")
	_assert(app.current_runtime == null, "recovered drain retained current runtime")
	_assert(not app._runtime_release_blocked, "recovered drain left release fence set")

	_destroy_fixture(fixture)


func _test_failed_begin_shutdown_uses_emergency_exit() -> void:
	var app = SimulatorAppScript.new()
	app.command_registry = CommandRegistryScript.new()
	app.test_registry = RuntimeTestRegistryScript.new()
	app.lifecycle_coordinator = LifecycleCoordinatorScript.new()
	app.lifecycle_coordinator.setup({"node_id": "failed-begin-test"})
	app.lifecycle_coordinator.mark_failed("startup failed")
	var quit_capture := {"called": false, "exit_code": -1}
	app.set_process_quit_handler_for_tests(func(exit_code: int) -> void:
		quit_capture["called"] = true
		quit_capture["exit_code"] = exit_code
	)

	var begin_result: Dictionary = app.request_graceful_shutdown("window_close", 0)
	_assert(not bool(begin_result.get("success", true)), "FAILED lifecycle accepted graceful shutdown")
	_assert(String(begin_result.get("error_code", "")) == "LIFECYCLE_FAILED", "begin failure code mismatch")
	_assert(bool(begin_result.get("emergency_shutdown_scheduled", false)), "emergency cleanup was not scheduled")
	_assert(not app._shutdown_in_progress, "failed begin left graceful shutdown flag stuck")

	var emergency_result: Dictionary = app._complete_emergency_shutdown(
		"begin_shutdown_failed",
		"window_close",
		0,
		begin_result
	)
	_assert(bool(emergency_result.get("success", false)), "safe emergency shutdown failed")
	_assert(bool(quit_capture["called"]), "safe emergency shutdown did not request quit")
	_assert(int(quit_capture["exit_code"]) == 1, "failed lifecycle must exit non-zero")
	_assert(not app._runtime_release_blocked, "empty emergency cleanup incorrectly blocked release")

	app.free()


func _create_fixture(failure_mode: String) -> Dictionary:
	var app = SimulatorAppScript.new()
	app.command_registry = CommandRegistryScript.new()
	app.test_registry = RuntimeTestRegistryScript.new()
	app.lifecycle_coordinator = LifecycleCoordinatorScript.new()
	app.lifecycle_coordinator.setup({"node_id": "failure-fixture"})
	app.lifecycle_coordinator.mark_running()
	app.launch_options = {"shutdown_timeout_ms": 10}
	var host := Node3D.new()
	var runtime := FailingRuntime.new()
	runtime.failure_mode = failure_mode
	host.add_child(runtime)
	app.world_host = host
	app.current_runtime = runtime
	app.current_world_id = "earth_moon"
	app.current_world_definition = {"id": "earth_moon"}
	return {"app": app, "host": host, "runtime": runtime}


func _destroy_fixture(fixture: Dictionary) -> void:
	var app = fixture.get("app")
	var host = fixture.get("host")
	if app != null:
		app.current_runtime = null
		app._runtime_release_blocked = false
	if host != null and is_instance_valid(host):
		host.free()
	if app != null and is_instance_valid(app):
		app.free()


func _has_transition_to(transitions: Array, target_state: String) -> bool:
	for transition in transitions:
		if String(transition.get("to", "")) == target_state:
			return true
	return false


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("Simulator shutdown failure paths: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Simulator shutdown failure paths: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)

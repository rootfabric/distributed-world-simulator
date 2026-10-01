extends SceneTree

const StallWatchdog = preload(
	"res://scripts/runtime/networked_gameplay/m3/live2_server_stall_watchdog.gd"
)
const LiveEarth = preload(
	"res://scripts/app/earth_p3_resource_mining_app.gd"
)


class FakeRuntime:
	extends RefCounted
	signal command_result_received(result: Dictionary)

	var async_calls: Array[Dictionary] = []
	var blocking_calls := 0

	func get_local_player_id() -> String:
		return "a"

	func execute_item_command_async(
		command_type: String,
		payload: Dictionary,
		operation_id: String = ""
	) -> Dictionary:
		var op := operation_id if not operation_id.is_empty() else "operation/r3-2/fake/%d" % (async_calls.size() + 1)
		async_calls.append({
			"command_type": command_type,
			"payload": payload.duplicate(true),
			"operation_id": op,
		})
		return {
			"success": true,
			"error_code": "",
			"details": {
				"operation_id": op,
				"pending": true,
			},
		}

	func execute_item_command_blocking(
		_command_type: String,
		_payload: Dictionary,
		_operation_id: String = ""
	) -> Dictionary:
		blocking_calls += 1
		return {
			"success": false,
			"error_code": "BLOCKING_PATH_FORBIDDEN",
			"details": {},
		}


class FakeConstructionShell:
	extends RefCounted

	var calls := 0

	func build_next_stage_async() -> Dictionary:
		calls += 1
		return {
			"success": true,
			"error_code": "",
			"details": {
				"operation_id": "operation/r3-2/construction/1",
				"pending": true,
			},
		}


var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_independent_watchdog()
	_test_i2s_async_submitter()
	_test_construction_rejection_feedback()
	_finish()


func _test_independent_watchdog() -> void:
	var watchdog = StallWatchdog.new()
	var started: Dictionary = watchdog.start(OS.get_process_id())
	_assert(bool(started.get("success", false)), "stall watchdog starts")
	var token := watchdog.enter("TEST:MAIN_THREAD_BLOCK", {
		"operation_id": "operation/r3-2/watchdog-test",
		"server_tick": 42,
	})
	_assert(token > 0, "stall watchdog returns phase token")

	# This blocks the main test thread on purpose. The watchdog runs in a
	# dedicated Thread and must still observe the soft 2s threshold.
	OS.delay_msec(2400)

	var report: Dictionary = watchdog.get_report()
	_assert(int(report.get("soft_reports", 0)) >= 1, "watchdog reports a soft stall while main thread is blocked")
	_assert(String(report.get("current", {}).get("stage", "")) == "TEST:MAIN_THREAD_BLOCK", "watchdog preserves current blocking phase")
	_assert(int(report.get("max_elapsed_ms", 0)) >= 2000, "watchdog records multi-second elapsed time")
	watchdog.exit(token)
	watchdog.stop()


func _test_i2s_async_submitter() -> void:
	var earth = LiveEarth.new()
	var runtime = FakeRuntime.new()
	earth.m3_multiplayer_client_runtime = runtime
	earth._m3_attached = true

	var pickup: Dictionary = earth._submit_i2s_command_async(
		"item.pickup",
		{"item_id": "item/shared/beacon/1"}
	)
	_assert(bool(pickup.get("success", false)), "I2S pickup send succeeds")
	_assert(bool(pickup.get("pending", false)), "I2S pickup returns immediately pending")
	_assert(runtime.async_calls.size() == 1, "I2S pickup uses exactly one async item command")
	_assert(runtime.blocking_calls == 0, "I2S pickup never enters blocking item API")
	_assert(String(runtime.async_calls[0].get("command_type", "")) == "item.pickup", "I2S pickup preserves canonical command type")

	var operation_id := String(runtime.async_calls[0].get("operation_id", ""))
	_assert(earth._live2_pending_actions.has(operation_id), "I2S pickup is tracked until ACK")
	earth._on_live2_async_command_result({
		"type": "COMMAND_RESULT",
		"operation_id": operation_id,
		"command_type": "item.pickup",
		"status": "SUCCEEDED",
		"error_code": "",
		"details": {},
		"async": true,
	})
	_assert(not earth._live2_pending_actions.has(operation_id), "I2S pickup pending clears on ACK")
	_assert(earth._live2_last_action_text == "Предмет подобран", "I2S pickup final feedback is server-result driven")
	earth.free()


func _test_construction_rejection_feedback() -> void:
	var earth = LiveEarth.new()
	var shell = FakeConstructionShell.new()
	earth._mvp_inventory_shell = shell

	var sent: Dictionary = earth._command_live2_build_next_stage([])
	_assert(bool(sent.get("success", false)), "Construction async command sends")
	_assert(bool(sent.get("pending", false)), "Construction command returns pending")
	_assert(shell.calls == 1, "Construction shell called once")

	var operation_id := String(sent.get("operation_id", ""))
	_assert(operation_id == "operation/r3-2/construction/1", "Construction operation id is exposed")
	_assert(earth._live2_pending_actions.has(operation_id), "Construction operation is tracked for HUD result")

	earth._on_live2_async_command_result({
		"type": "COMMAND_RESULT",
		"operation_id": operation_id,
		"command_type": "CONSTRUCTION_COMMAND",
		"status": "REJECTED",
		"error_code": "MATERIAL_INSUFFICIENT",
		"details": {},
		"async": true,
	})
	_assert(not earth._live2_pending_actions.has(operation_id), "Construction pending HUD state clears on rejection")
	_assert(
		earth._live2_last_action_text.contains("MATERIAL_INSUFFICIENT"),
		"Construction rejection reason is visible to the player"
	)
	earth.free()


func _assert(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("V0-LIVE.2 R3.2 stall/async UX: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("V0-LIVE.2 R3.2 stall/async UX: FAIL (%d failures, %d assertions)" % [
		failures.size(), assertions
	])
	quit(1)

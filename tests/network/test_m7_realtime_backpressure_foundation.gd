extends SceneTree

const InputBuffer = preload("res://scripts/network/simulation/fixed_tick_input_buffer.gd")
const ServerRuntime = preload("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd")

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_continuous_refreshes_are_coalesced()
	_test_state_transitions_and_jump_edges_are_preserved()
	_test_full_queue_can_absorb_equivalent_refresh()
	_test_runtime_wiring_is_realtime_safe()
	_finish()


func _test_continuous_refreshes_are_coalesced() -> void:
	var buffer = InputBuffer.new()
	_assert(_ok(buffer.configure()), "continuous buffer setup failed")
	for sequence in range(1, 501):
		var intent := _intent(0.0, 1.0, false, false)
		intent["look_yaw"] = float(sequence) * 0.01
		var result: Dictionary = buffer.enqueue(_entry(sequence, intent), 1)
		_assert(_ok(result), "continuous refresh rejected at sequence %d: %s" % [sequence, result])
	var report: Dictionary = buffer.get_report(1)
	_assert(int(report.get("pending", -1)) == 1, "continuous refreshes accumulated instead of coalescing: %s" % report)
	_assert(int(report.get("coalesced_refreshes", 0)) == 499, "continuous coalescing counter mismatch: %s" % report)
	_assert(int(report.get("queue_full_rejected", -1)) == 0, "continuous refresh stream hit INPUT_QUEUE_FULL")
	var consumed: Dictionary = buffer.consume_for_tick(2)
	_assert(int(consumed.get("details", {}).get("input_sequence", 0)) == 500, "latest continuous refresh sequence was not retained")
	_assert(is_equal_approx(float(consumed.get("details", {}).get("intent", {}).get("look_yaw", 0.0)), 5.0), "latest look state was not retained")


func _test_state_transitions_and_jump_edges_are_preserved() -> void:
	var buffer = InputBuffer.new()
	_assert(_ok(buffer.configure()), "transition buffer setup failed")
	_assert(_ok(buffer.enqueue(_entry(1, _intent(0.0, 0.0, false, false)), 1)), "idle transition rejected")
	for sequence in range(2, 101):
		_assert(_ok(buffer.enqueue(_entry(sequence, _intent(0.0, 1.0, false, false)), 1)), "movement refresh rejected")
	_assert(_ok(buffer.enqueue(_entry(101, _intent(0.0, 1.0, true, false)), 1)), "sprint transition rejected")
	_assert(_ok(buffer.enqueue(_entry(102, _intent(0.0, 1.0, true, true)), 1)), "jump edge rejected")
	_assert(_ok(buffer.enqueue(_entry(103, _intent(0.0, 0.0, false, false)), 1)), "final idle transition rejected")
	var expected_sequences: Array[int] = [1, 100, 101, 102, 103]
	var observed_sequences: Array[int] = []
	var jump_edges: int = 0
	for tick in range(1, expected_sequences.size() + 1):
		var consumed: Dictionary = buffer.consume_for_tick(tick)
		observed_sequences.append(int(consumed.get("details", {}).get("input_sequence", 0)))
		if bool(consumed.get("details", {}).get("jump_edge", false)):
			jump_edges += 1
	_assert(observed_sequences == expected_sequences, "coalescing erased state transitions: %s" % [observed_sequences])
	_assert(jump_edges == 1, "jump edge was lost or repeated during coalescing")


func _test_full_queue_can_absorb_equivalent_refresh() -> void:
	var buffer = InputBuffer.new()
	_assert(_ok(buffer.configure()), "pressure buffer setup failed")
	for sequence in range(1, InputBuffer.MAX_PENDING_INPUTS + 1):
		var moving: bool = sequence % 2 == 0
		var result: Dictionary = buffer.enqueue(
			_entry(sequence, _intent(0.0, 1.0 if moving else 0.0, false, false)), 1
		)
		_assert(_ok(result), "pressure fill rejected before capacity at %d" % sequence)
	_assert(buffer.get_pending_count() == InputBuffer.MAX_PENDING_INPUTS, "pressure queue did not reach configured bound")
	var refresh_sequence: int = InputBuffer.MAX_PENDING_INPUTS + 1
	var refresh: Dictionary = buffer.enqueue(
		_entry(refresh_sequence, _intent(0.0, 1.0, false, false)), 1
	)
	_assert(_ok(refresh), "equivalent refresh was rejected at full queue: %s" % refresh)
	_assert(bool(refresh.get("details", {}).get("coalesced", false)), "full-queue equivalent refresh did not use coalescing")
	var report: Dictionary = buffer.get_report(1)
	_assert(int(report.get("pending", -1)) == InputBuffer.MAX_PENDING_INPUTS, "full-queue coalescing changed bounded capacity")
	_assert(int(report.get("queue_pressure_recoveries", 0)) == 1, "queue-pressure recovery was not observable")
	_assert(int(report.get("queue_full_rejected", -1)) == 0, "equivalent full-queue refresh incremented queue-full rejection")
	var incompatible: Dictionary = buffer.enqueue(
		_entry(refresh_sequence + 1, _intent(1.0, 0.0, false, false)), 1
	)
	_assert(String(incompatible.get("error_code", "")) == "INPUT_QUEUE_FULL", "true transition overflow must remain bounded")


func _test_runtime_wiring_is_realtime_safe() -> void:
	_assert(ServerRuntime.can_instantiate(), "M7 dedicated server runtime no longer instantiates")
	var runtime = ServerRuntime.new()
	var report: Dictionary = runtime.get_report()
	var foundation: Dictionary = Dictionary(report.get("realtime_foundation", {}))
	_assert(String(foundation.get("report_policy", "")) == "ASYNC_COALESCED_READY_SYNC_TERMINAL_V1", "async report policy missing")
	_assert(String(foundation.get("event_loop_policy", "")) == "FIXED_TICK_BEFORE_NETWORK_DRAIN_V1", "fixed-tick priority policy missing")
	_assert(String(foundation.get("item_replication_policy", "")) == "ITEM_GRAPH_DELTA_NO_REDUNDANT_GAMEPLAY_SNAPSHOT_V1", "item replication policy missing")
	_assert(int(foundation.get("network_event_budget_per_frame", 0)) <= 64, "network event drain is not bounded")

	var result_dir: String = ProjectSettings.globalize_path("res://artifacts/test-results")
	DirAccess.make_dir_recursive_absolute(result_dir)
	var result_path: String = result_dir.path_join(
		"m7-realtime-backpressure-%d.json" % OS.get_process_id()
	)
	if FileAccess.file_exists(result_path):
		DirAccess.remove_absolute(result_path)
	runtime.set("_result_file", result_path)
	runtime.call("_write_report", "READY", false)
	_assert(FileAccess.file_exists(result_path), "initial synchronous readiness report was not written")
	for _index in range(8):
		runtime.call("_write_report", "READY", false)
	runtime.set("_last_report_dispatch_ms", Time.get_ticks_msec() - 1000)
	runtime.call("_dispatch_deferred_report")
	_assert(runtime.get("_report_thread") != null, "deferred READY report did not start a writer thread")
	runtime.call("_write_report", "READY", false)
	runtime.call("_drain_report_thread")
	var after_write: Dictionary = runtime.get_report()
	var after_foundation: Dictionary = Dictionary(after_write.get("realtime_foundation", {}))
	_assert(int(after_foundation.get("report_writes_completed", 0)) >= 2, "async report worker did not complete")
	_assert(int(after_foundation.get("report_requests_coalesced", 0)) >= 1, "READY report requests were not coalesced")
	_assert(int(after_foundation.get("report_write_failures", -1)) == 0, "diagnostic report worker failed")
	_assert(float(after_foundation.get("report_last_write_duration_ms", -1.0)) >= 0.0, "report write latency is not observable")
	runtime.free()
	if FileAccess.file_exists(result_path):
		DirAccess.remove_absolute(result_path)

	var source: String = FileAccess.get_file_as_string("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd")
	var fixed_tick_pos: int = source.find("_advance_fixed_simulation(delta)")
	var poll_pos: int = source.find("_boundary.poll_events(M7_NETWORK_EVENT_BUDGET_PER_FRAME)")
	_assert(fixed_tick_pos >= 0 and poll_pos > fixed_tick_pos, "network drain still runs before fixed simulation")
	_assert(source.contains("Thread.new()"), "READY diagnostic writes are not moved off the authority thread")
	_assert(source.contains("_report_requests_coalesced"), "report coalescing is not observable")
	_assert(not source.contains("_broadcast_snapshot(\"ITEM_GRAPH_UPDATED\""), "canonical item command still emits redundant gameplay snapshot")
	_assert(InputBuffer.SCHEMA == "planet_simulator.fixed_tick_input_buffer.v1", "internal hardening changed NX3 wire identity")
	_assert(InputBuffer.INPUT_SELECTION_POLICY == "FIFO_STATE_TRANSITIONS_ONE_PER_FIXED_TICK_V1", "internal hardening changed accepted NX3 selection contract")


func _entry(sequence: int, intent: Dictionary) -> Dictionary:
	return {
		"input_sequence": sequence,
		"operation_id": "operation/m7/backpressure/%d" % sequence,
		"client_tick": sequence,
		"client_sent_at_ms": sequence,
		"intent": intent.duplicate(true),
	}


func _intent(move_x: float, move_z: float, sprint: bool, jump_pressed: bool) -> Dictionary:
	return {
		"move_x": move_x,
		"move_z": move_z,
		"look_yaw": 0.0,
		"look_pitch": 0.0,
		"jump_pressed": jump_pressed,
		"sprint": sprint,
		"delta_seconds": 1.0 / 60.0,
	}


func _ok(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	for failure in failures:
		push_error(failure)
	print("M7 realtime backpressure foundation: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

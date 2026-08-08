extends SceneTree

const InputBuffer = preload("res://scripts/network/simulation/fixed_tick_input_buffer.gd")
const Scheduler = preload("res://scripts/network/simulation/fixed_tick_scheduler.gd")
const ServerRuntime = preload("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd")

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_shallow_refreshes_preserve_fifo_and_look()
	_test_state_transitions_and_jump_edges_are_preserved()
	_test_pressure_compaction_keeps_latest_state_and_jump_edges()
	_test_lossless_scheduler_retains_transient_stall_time()
	_test_runtime_wiring_is_realtime_safe()
	_finish()


func _test_shallow_refreshes_preserve_fifo_and_look() -> void:
	var buffer = InputBuffer.new()
	_assert(_ok(buffer.configure()), "normal FIFO buffer setup failed")
	for sequence in range(1, InputBuffer.PRESSURE_COMPACTION_THRESHOLD + 1):
		var intent := _intent(0.0, 1.0, false, false)
		intent["look_yaw"] = float(sequence) * 0.01
		var result: Dictionary = buffer.enqueue(_entry(sequence, intent), 1)
		_assert(_ok(result), "normal refresh rejected at sequence %d: %s" % [sequence, result])
		_assert(not bool(result.get("details", {}).get("pressure_compacted", false)), "shallow refresh entered pressure recovery at sequence %d" % sequence)
	var report: Dictionary = buffer.get_report(1)
	_assert(int(report.get("pending", -1)) == InputBuffer.PRESSURE_COMPACTION_THRESHOLD, "shallow continuous input no longer preserves NX3 FIFO depth: %s" % report)
	_assert(int(report.get("pressure_compactions", -1)) == 0, "shallow input unexpectedly entered pressure recovery: %s" % report)
	_assert(String(report.get("coalescing_policy", "")) == "PRESSURE_LATEST_STATE_WITH_JUMP_EDGE_PRESERVATION_V4", "pressure compaction policy missing")
	for sequence in range(1, InputBuffer.PRESSURE_COMPACTION_THRESHOLD + 1):
		var consumed: Dictionary = buffer.consume_for_tick(sequence)
		_assert(int(consumed.get("details", {}).get("input_sequence", 0)) == sequence, "shallow FIFO sequence changed at tick %d: %s" % [sequence, consumed])
		_assert(is_equal_approx(float(consumed.get("details", {}).get("intent", {}).get("look_yaw", 0.0)), float(sequence) * 0.01), "shallow FIFO look state changed at tick %d" % sequence)


func _test_state_transitions_and_jump_edges_are_preserved() -> void:
	var buffer = InputBuffer.new()
	_assert(_ok(buffer.configure()), "transition buffer setup failed")
	_assert(_ok(buffer.enqueue(_entry(1, _intent(0.0, 0.0, false, false)), 1)), "idle transition rejected")
	_assert(_ok(buffer.enqueue(_entry(2, _intent(0.0, 1.0, false, false)), 1)), "movement transition rejected")
	_assert(_ok(buffer.enqueue(_entry(3, _intent(0.0, 1.0, true, false)), 1)), "sprint transition rejected")
	_assert(_ok(buffer.enqueue(_entry(4, _intent(0.0, 1.0, true, true)), 1)), "jump edge rejected")
	_assert(_ok(buffer.enqueue(_entry(5, _intent(0.0, 0.0, false, false)), 1)), "final idle transition rejected")
	var expected_sequences: Array[int] = [1, 2, 3, 4, 5]
	var observed_sequences: Array[int] = []
	var jump_edges: int = 0
	for tick in range(1, expected_sequences.size() + 1):
		var consumed: Dictionary = buffer.consume_for_tick(tick)
		observed_sequences.append(int(consumed.get("details", {}).get("input_sequence", 0)))
		if bool(consumed.get("details", {}).get("jump_edge", false)):
			jump_edges += 1
	_assert(observed_sequences == expected_sequences, "shallow FIFO/state transition ordering changed: %s" % [observed_sequences])
	_assert(jump_edges == 1, "jump edge was lost or repeated")


func _test_pressure_compaction_keeps_latest_state_and_jump_edges() -> void:
	var buffer = InputBuffer.new()
	_assert(_ok(buffer.configure()), "pressure buffer setup failed")
	for sequence in range(1, 41):
		var jump_pressed: bool = sequence in [5, 17]
		var intent := _intent(
			1.0 if sequence % 3 == 0 else 0.0,
			-1.0 if sequence % 2 == 0 else 1.0,
			sequence % 4 == 0,
			jump_pressed
		)
		intent["look_yaw"] = float(sequence) * 0.02
		var result: Dictionary = buffer.enqueue(_entry(sequence, intent), 10)
		_assert(_ok(result), "pressure enqueue rejected at sequence %d: %s" % [sequence, result])
	var report: Dictionary = buffer.get_report(10)
	_assert(int(report.get("pending", 99)) <= InputBuffer.PRESSURE_COMPACTION_THRESHOLD, "pressure queue remained latency-sized: %s" % report)
	_assert(int(report.get("pressure_compactions", 0)) >= 1, "pressure backlog was never compacted: %s" % report)
	_assert(int(report.get("pressure_dropped_inputs", 0)) > 0, "pressure compaction did not discard superseded continuous samples")
	_assert(int(report.get("queue_full_rejected", -1)) == 0, "continuous pressure still reached hard INPUT_QUEUE_FULL")
	_assert(int(report.get("peak_pending", 0)) <= InputBuffer.PRESSURE_COMPACTION_THRESHOLD + 1, "pressure recovery allowed a large pending spike: %s" % report)

	# NX2 batches retransmit recent input history. Sequence 34 is deliberately
	# compacted when sequence 35 pushes the pressure backlog above the threshold.
	# It must not be resurrected when resent.
	var pending_before_retransmit: int = buffer.get_pending_count()
	var retransmit_intent := _intent(0.0, -1.0, false, false)
	retransmit_intent["look_yaw"] = 34.0 * 0.02
	var retransmit: Dictionary = buffer.enqueue(_entry(34, retransmit_intent), 11)
	_assert(_ok(retransmit), "compacted input retransmit returned transport failure")
	_assert(not bool(retransmit.get("details", {}).get("accepted", true)), "compacted sequence 34 was resurrected")
	_assert(bool(retransmit.get("details", {}).get("pressure_discarded", false)), "compacted retransmit was not identified")
	_assert(buffer.get_pending_count() == pending_before_retransmit, "compacted retransmit changed pending depth")
	report = buffer.get_report(11)
	_assert(int(report.get("pressure_retransmits_suppressed", 0)) == 1, "compacted retransmit suppression is not observable")

	var observed_jump_edges: int = 0
	var last_sequence: int = 0
	var tick: int = 11
	while buffer.get_pending_count() > 0 and tick < 100:
		var consumed: Dictionary = buffer.consume_for_tick(tick)
		last_sequence = int(consumed.get("details", {}).get("input_sequence", last_sequence))
		if bool(consumed.get("details", {}).get("jump_edge", false)):
			observed_jump_edges += 1
		tick += 1
	_assert(observed_jump_edges == 2, "pressure compaction lost a jump edge: %d" % observed_jump_edges)
	_assert(last_sequence == 40, "pressure compaction did not converge to newest input state: %d" % last_sequence)
	_assert(int(buffer.get_report(tick).get("pressure_discarded_sequence_count", -1)) == 0, "pressure retransmit tombstones were not pruned after authority advanced")


func _test_lossless_scheduler_retains_transient_stall_time() -> void:
	var scheduler = Scheduler.new()
	_assert(_ok(scheduler.configure(60, 4, 0, 1.0, true)), "lossless scheduler setup failed")
	var first: Dictionary = scheduler.advance(0.25)
	_assert(_ok(first), "lossless scheduler stall advance failed")
	_assert(int(first.get("details", {}).get("tick_count", 0)) == 4, "lossless scheduler ignored per-frame catch-up bound")
	_assert(int(first.get("details", {}).get("pending_catch_up_ticks", 0)) == 11, "lossless scheduler did not retain remaining 250 ms debt: %s" % first)
	_assert(is_zero_approx(float(scheduler.get_report().get("dropped_time_seconds", -1.0))), "lossless scheduler dropped transient authority time")
	var drain_guard: int = 0
	while scheduler.get_pending_catch_up_ticks() > 0 and drain_guard < 10:
		_assert(_ok(scheduler.advance(0.0)), "lossless scheduler backlog drain failed")
		drain_guard += 1
	var report: Dictionary = scheduler.get_report()
	_assert(int(report.get("server_tick", 0)) == 15, "lossless scheduler did not recover all 250 ms fixed ticks: %s" % report)
	_assert(int(report.get("pending_catch_up_ticks", -1)) == 0, "lossless scheduler left retained backlog after drain")
	_assert(String(report.get("backlog_policy", "")) == Scheduler.BACKLOG_POLICY_RETAIN_EXCESS, "lossless scheduler policy is not observable")
	_assert(int(report.get("retained_backlog_peak_ticks", 0)) >= 11, "lossless scheduler backlog peak is not observable")


func _test_runtime_wiring_is_realtime_safe() -> void:
	var runtime_script: Script = ServerRuntime
	_assert(runtime_script.can_instantiate(), "M7 dedicated server runtime no longer instantiates")
	var runtime = runtime_script.new()
	var report: Dictionary = runtime.get_report()
	var foundation: Dictionary = Dictionary(report.get("realtime_foundation", {}))
	_assert(String(foundation.get("report_policy", "")) == "ASYNC_COALESCED_READY_SYNC_TERMINAL_V1", "async report policy missing")
	_assert(String(foundation.get("event_loop_policy", "")) == "FIXED_TICK_BEFORE_NETWORK_DRAIN_V1", "fixed-tick priority policy missing")
	_assert(String(foundation.get("item_replication_policy", "")) == "ITEM_GRAPH_DELTA_WITH_GAMEPLAY_REVISION_SYNC_V2", "item/gameplay revision sync policy missing")
	_assert(String(foundation.get("fixed_tick_backlog_policy", "")) == "RETAIN_TRANSIENT_STALL_TIME_V1", "M7 transient-stall scheduler policy missing")
	_assert(String(foundation.get("movement_snapshot_recovery_policy", "")) == "SUPPRESS_WHILE_STALL_OR_AUTHORITY_BACKLOG_V1", "stale movement snapshot guard missing")
	_assert(int(foundation.get("network_event_budget_per_frame", 0)) <= 32, "network event drain is not tightly bounded")
	_assert(int(foundation.get("fixed_tick_max_catch_up_ticks", 0)) == 16, "M7 catch-up batch size drifted")
	_assert(is_equal_approx(float(foundation.get("fixed_tick_max_frame_delta_seconds", 0.0)), 1.0), "M7 transient stall retention window drifted")
	_assert(int(foundation.get("item_gameplay_revision_snapshots_published", -1)) == 0, "fresh runtime has invalid item gameplay sync counter")

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
	_assert(source.contains("M7_FIXED_TICK_MAX_CATCH_UP_TICKS"), "M7 runtime does not tune transient catch-up")
	_assert(source.contains("M7_STALL_SNAPSHOT_GUARD_SECONDS"), "M7 runtime does not guard post-stall snapshots")
	_assert(source.contains("_movement_snapshot_recovery_suppressions"), "movement recovery suppression is not observable")
	_assert(source.contains("Thread.new()"), "READY diagnostic writes are not moved off the authority thread")
	_assert(source.contains("_report_requests_coalesced"), "report coalescing is not observable")
	_assert(source.contains("_broadcast_snapshot(\"ITEM_GRAPH_UPDATED\", RealtimeChannelPolicy.RESYNC, \"RELIABLE_ORDERED\")"), "canonical item mutation does not publish its gameplay revision")
	_assert(source.contains("_broadcast_item_delta(item_delta, peer_id, command_type)"), "canonical item payload no longer uses ITEM delta stream")
	_assert(InputBuffer.SCHEMA == "planet_simulator.fixed_tick_input_buffer.v1", "internal hardening changed NX3 wire identity")
	_assert(InputBuffer.INPUT_SELECTION_POLICY == "FIFO_STATE_TRANSITIONS_ONE_PER_FIXED_TICK_V1", "internal hardening changed accepted NX3 shallow-queue selection contract")
	_assert(InputBuffer.PRESSURE_COMPACTION_THRESHOLD <= 8, "input pressure recovery starts too late for smooth local prediction")


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

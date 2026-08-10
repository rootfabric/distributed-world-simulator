extends SceneTree

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	var source: String = FileAccess.get_file_as_string(
		"res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd"
	)
	_assert(
		source.contains("STALL_OR_FIXED_TICK_BACKLOG_ONLY_PENDING_FUTURE_INPUTS_ALLOWED_V1"),
		"FIX10 fix6 remote snapshot guard policy missing"
	)
	var process_start: int = source.find("func _process(delta: float) -> void:")
	var fixed_tick_start: int = source.find("func _run_fixed_tick(server_tick: int) -> void:")
	_assert(process_start >= 0 and fixed_tick_start > process_start, "FIX10 fix6 canonical server owns process guard")
	if process_start >= 0 and fixed_tick_start > process_start:
		var process_source: String = source.substr(process_start, fixed_tick_start - process_start)
		_assert(
			process_source.contains("if transient_stall or scheduler_backlog_ticks > 0:"),
			"FIX10 fix6 snapshots still guard real authority catch-up"
		)
		_assert(
			not process_source.contains("or input_backlog_before_drain > M7_INPUT_SNAPSHOT_BACKLOG_GUARD"),
			"FIX10 fix6 raw pending future input still suppresses realtime snapshots"
		)
		var bypass_pos: int = process_source.find(
			"input_backlog_before_drain > M7_INPUT_SNAPSHOT_BACKLOG_GUARD"
		)
		var publish_pos: int = process_source.find("_maybe_publish_movement_snapshot()")
		_assert(
			bypass_pos >= 0 and publish_pos > bypass_pos,
			"FIX10 fix6 observes high pending depth but still publishes authoritative snapshot"
		)
	_assert(
		source.contains("fix10_fix6_pending_input_snapshot_guard_bypasses"),
		"FIX10 fix6 pending-guard bypass metric missing"
	)
	_assert(
		source.contains("fix10_fix6_max_pending_inputs_while_snapshot_allowed"),
		"FIX10 fix6 max allowed pending metric missing"
	)
	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)
	else:
		print("PASS: %s" % message)


func _finish() -> void:
	print("M7 FIX10 fix6 remote snapshot guard: PASS (%d assertions)" % assertions if failures.is_empty() else "M7 FIX10 fix6 remote snapshot guard: FAIL (%d/%d)" % [failures.size(), assertions])
	quit(0 if failures.is_empty() else 1)

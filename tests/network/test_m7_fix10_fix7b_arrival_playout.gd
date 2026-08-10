extends SceneTree

const InputBuffer = preload("res://scripts/network/simulation/fixed_tick_input_buffer_fix10.gd")

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_client_tick_gap_never_delays_available_input()
	_test_pressure_recovery_does_not_turn_tick_gap_into_playout_wait()
	_finish()


func _test_client_tick_gap_never_delays_available_input() -> void:
	var buffer = InputBuffer.new()
	_assert(bool(buffer.configure().get("success", false)), "FIX10 fix7b buffer configures")
	_assert(bool(buffer.enqueue(_input(1, 100), 110).get("success", false)), "first input enqueues")
	var first: Dictionary = buffer.consume_for_tick(111)
	_assert(bool(first.get("success", false)), "first consume succeeds")
	_assert(bool(first.get("details", {}).get("consumed_new_input", false)), "first input applies immediately")
	_assert(int(first.get("details", {}).get("input_sequence", 0)) == 1, "first sequence applied")
	_assert(int(first.get("details", {}).get("fix10_client_tick", 0)) == 100, "client tick retained as metadata")

	_assert(bool(buffer.enqueue(_input(2, 102), 111).get("success", false)), "normal spaced input enqueues")
	var second: Dictionary = buffer.consume_for_tick(112)
	_assert(bool(second.get("details", {}).get("consumed_new_input", false)), "normal spaced input consumes on nearest server tick")
	_assert(int(second.get("details", {}).get("input_sequence", 0)) == 2, "second sequence applied without semantic wait")
	_assert(not bool(second.get("details", {}).get("fix10_fix6_semantic_wait", false)), "no client-tick semantic wait is generated")

	# Prediction clocks may jump forward during reconciliation. A large metadata
	# gap must not become authority playout latency.
	_assert(bool(buffer.enqueue(_input(3, 120), 112).get("success", false)), "clock-jump input enqueues")
	var jumped: Dictionary = buffer.consume_for_tick(113)
	_assert(bool(jumped.get("details", {}).get("consumed_new_input", false)), "clock-jump input still applies immediately")
	_assert(int(jumped.get("details", {}).get("input_sequence", 0)) == 3, "clock-jump sequence applied")
	_assert(int(jumped.get("details", {}).get("fix10_client_tick", 0)) == 120, "clock-jump metadata preserved")

	var report: Dictionary = buffer.get_report(113)
	_assert(String(report.get("fix10_fix7b_input_playout_policy", "")) == "ARRIVAL_PACED_NEAREST_FIXED_TICK_CLIENT_TICK_METADATA_ONLY_V1", "arrival-paced playout policy reported")
	_assert(int(report.get("fix10_fix6_semantic_wait_ticks", -1)) == 0, "semantic wait counter remains zero")
	_assert(int(report.get("fix10_fix7_relative_targets", -1)) == 0, "relative target scheduler is inactive")
	_assert(int(report.get("fix10_fix7b_arrival_paced_consumes", 0)) == 3, "arrival-paced consumes counted")


func _test_pressure_recovery_does_not_turn_tick_gap_into_playout_wait() -> void:
	var buffer = InputBuffer.new()
	_assert(bool(buffer.configure().get("success", false)), "pressure fixture configures")
	# Feed a burst that exceeds the parent's pressure threshold. The parent may
	# compact superseded continuous states, but the retained newest states must be
	# consumed immediately rather than waiting for their large client_tick gap.
	for sequence in range(1, 11):
		_assert(
			bool(buffer.enqueue(_input(sequence, 200 + sequence * 2), 300).get("success", false)),
			"pressure input %d enqueues" % sequence
		)
	var before: Dictionary = buffer.get_report(300)
	_assert(int(before.get("pressure_compactions", 0)) >= 1, "parent pressure compaction actually exercised")
	_assert(int(before.get("pressure_dropped_inputs", 0)) >= 1, "pressure fixture dropped superseded continuous samples")

	var consume301: Dictionary = buffer.consume_for_tick(301)
	_assert(bool(consume301.get("details", {}).get("consumed_new_input", false)), "retained pressure state consumes immediately")
	_assert(int(consume301.get("details", {}).get("input_sequence", 0)) >= 9, "pressure recovery consumes a newest retained state")
	_assert(not bool(consume301.get("details", {}).get("fix10_fix6_semantic_wait", false)), "pressure recovery never creates semantic wait")
	var after: Dictionary = buffer.get_report(301)
	_assert(int(after.get("fix10_fix6_semantic_wait_ticks", -1)) == 0, "pressure recovery leaves semantic waits at zero")
	_assert(int(after.get("fix10_fix7b_max_queue_age_before_consume", 99)) <= 1, "fresh LOCAL-style burst is not deliberately aged")


func _input(sequence: int, client_tick: int) -> Dictionary:
	return {
		"input_sequence": sequence,
		"operation_id": "operation/fix10-fix7b/%d" % sequence,
		"client_tick": client_tick,
		"client_sent_at_ms": 1,
		"intent": {
			"move_x": 0.0,
			"move_z": 1.0,
			"look_yaw": 0.0,
			"look_pitch": 0.0,
			"jump_pressed": false,
			"sprint": false,
			"delta_seconds": 1.0 / 60.0,
		},
	}


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _finish() -> void:
	print("M7 FIX10 fix7b arrival playout: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

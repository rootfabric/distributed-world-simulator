extends SceneTree

const InputBuffer = preload("res://scripts/network/simulation/fixed_tick_input_buffer_fix10.gd")

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_relative_scheduler_rebases_after_late_packet()
	_test_render_rate_presentation_composition()
	_finish()


func _test_relative_scheduler_rebases_after_late_packet() -> void:
	var buffer = InputBuffer.new()
	_assert(bool(buffer.configure().get("success", false)), "FIX10 fix7 relative buffer configures")
	_assert(bool(buffer.enqueue(_input(1, 100), 110).get("success", false)), "FIX10 fix7 first input queues")
	var first: Dictionary = buffer.consume_for_tick(111)
	_assert(bool(first.get("details", {}).get("consumed_new_input", false)), "FIX10 fix7 first input applies immediately")

	_assert(bool(buffer.enqueue(_input(2, 102), 111).get("success", false)), "FIX10 fix7 spaced input queues")
	var wait112: Dictionary = buffer.consume_for_tick(112)
	_assert(not bool(wait112.get("details", {}).get("consumed_new_input", true)), "FIX10 fix7 preserves two-tick client spacing")
	var second: Dictionary = buffer.consume_for_tick(113)
	_assert(bool(second.get("details", {}).get("consumed_new_input", false)), "FIX10 fix7 spaced input applies at relative target")

	# Simulate transport/authority delay. The old absolute-offset scheduler would
	# keep using client_tick+11 forever. V2 applies this late transition now and
	# bases the following spacing on the actual server application tick.
	_assert(bool(buffer.enqueue(_input(3, 104), 120).get("success", false)), "FIX10 fix7 late input queues")
	var late: Dictionary = buffer.consume_for_tick(120)
	_assert(bool(late.get("details", {}).get("consumed_new_input", false)), "FIX10 fix7 late input applies immediately")
	_assert(int(late.get("details", {}).get("fix10_input_applied_server_tick", 0)) == 120, "FIX10 fix7 late input rebases on actual server tick")

	_assert(bool(buffer.enqueue(_input(4, 106), 120).get("success", false)), "FIX10 fix7 post-rebase input queues")
	var wait121: Dictionary = buffer.consume_for_tick(121)
	_assert(not bool(wait121.get("details", {}).get("consumed_new_input", true)), "FIX10 fix7 post-rebase spacing waits one tick")
	var fourth: Dictionary = buffer.consume_for_tick(122)
	_assert(bool(fourth.get("details", {}).get("consumed_new_input", false)), "FIX10 fix7 post-rebase input applies at 122")
	var report: Dictionary = buffer.get_report(122)
	_assert(String(report.get("fix10_fix7_effective_semantic_schedule_policy", "")) == "RELATIVE_APPLIED_TICK_PRESERVES_CLIENT_SPACING_V2", "FIX10 fix7 effective schedule policy reported")
	_assert(int(report.get("fix10_fix6_late_apply_events", 0)) >= 1, "FIX10 fix7 late apply remains observable")
	_assert(int(report.get("fix10_fix7_first_inputs_applied_immediately", 0)) == 1, "FIX10 fix7 first immediate application counted")
	_assert(int(report.get("fix10_fix7_relative_targets", 0)) >= 3, "FIX10 fix7 relative targets counted")


func _test_render_rate_presentation_composition() -> void:
	var scene_source := FileAccess.get_file_as_string("res://scenes/testing/playground.tscn")
	var fix8_source := FileAccess.get_file_as_string(
		"res://scripts/world/testing/playground_view_relative_runtime_fix8.gd"
	)
	var source := FileAccess.get_file_as_string(
		"res://scripts/world/testing/playground_view_relative_runtime_fix7.gd"
	)
	_assert(scene_source.contains("playground_view_relative_runtime_fix8.gd"), "FIX10 fix7 preserves accepted FIX8 playground scene identity")
	_assert(fix8_source.contains("playground_view_relative_runtime_fix7.gd"), "FIX10 fix7 render repair remains in active FIX8 inheritance chain")
	_assert(source.contains("PHYSICS_SIMULATION_RENDER_RATE_BOUNDED_EXTRAPOLATION_V1"), "FIX10 fix7 render presentation policy present")
	_assert(source.contains("super._process(delta)"), "FIX10 fix7 preserves parent render processing")
	_assert(source.contains("_fix10_fix7_apply_render_presentation()"), "FIX10 fix7 applies local presentation from render process")
	_assert(source.contains("velocity_vector * _fix10_fix7_render_elapsed_seconds"), "FIX10 fix7 bounded sub-tick extrapolation present")
	_assert(source.contains("FIX10_FIX7_FIXED_DELTA_SECONDS"), "FIX10 fix7 render extrapolation bounded to fixed tick")
	_assert(not source.contains("_sync_m7_predicted_player_state(delta)"), "FIX10 fix7 layer does not advance simulation from render")


func _input(sequence: int, client_tick: int) -> Dictionary:
	return {
		"input_sequence": sequence,
		"operation_id": "operation/fix10-fix7/%d" % sequence,
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
	print("M7 FIX10 fix7 relative scheduler/render: %d assertions, %d failures" % [
		assertions, failures.size()
	])
	quit(0 if failures.is_empty() else 1)

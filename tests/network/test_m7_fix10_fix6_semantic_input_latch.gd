extends SceneTree

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_semantic_input_latch_source_contract()
	_finish()


func _test_semantic_input_latch_source_contract() -> void:
	var source: String = FileAccess.get_file_as_string(
		"res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_fix10_fix6_core.gd"
	)
	_assert(
		source.contains("ONE_SEQUENCE_PER_CLIENT_FIXED_TICK_V1"),
		"FIX10 fix6 semantic input latch policy missing"
	)
	_assert(
		source.contains("target_client_tick == _fix10_fix6_last_latched_client_tick"),
		"FIX10 fix6 same-client-tick submission guard missing"
	)
	_assert(
		source.contains("_fix10_fix6_same_tick_input_update_suppressions += 1"),
		"FIX10 fix6 same-client-tick suppression is not observable"
	)
	var guard_pos: int = source.find(
		"target_client_tick == _fix10_fix6_last_latched_client_tick"
	)
	var submit_pos: int = source.find(
		"submit_movement_intent_nonblocking(canonical, target_client_tick)",
		guard_pos
	)
	_assert(
		guard_pos >= 0 and submit_pos > guard_pos,
		"FIX10 fix6 guards duplicate semantic tick before creating input sequence"
	)
	_assert(
		source.contains("_fix10_fix6_last_latched_client_tick = target_client_tick"),
		"FIX10 fix6 successful semantic submission does not latch client tick"
	)
	_assert(
		source.contains("submission_error == \"M7_PLAYER_INPUT_SEND_FAILED\""),
		"FIX10 fix6 transport retry path can recreate same-tick semantic sequence"
	)
	_assert(
		source.contains("fix6_semantic_input_latch_policy"),
		"FIX10 fix6 input latch policy missing from runtime report"
	)
	_assert(
		source.contains("fix6_same_tick_input_update_suppressions"),
		"FIX10 fix6 input latch suppression count missing from runtime report"
	)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _finish() -> void:
	print("M7 FIX10 fix6 semantic input latch: %d assertions, %d failures" % [
		assertions,
		failures.size(),
	])
	quit(0 if failures.is_empty() else 1)

extends SceneTree

const InputSequence = preload("res://scripts/network/simulation/input_sequence.gd")

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_sequence_duplicate_backward_and_wrap()
	_test_half_range_future_fence()
	_test_owner_state_does_not_trust_client_tick()
	_finish()


func _test_sequence_duplicate_backward_and_wrap() -> void:
	for reference in [1, 2, 17, InputSequence.MAX_SEQUENCE - 1, InputSequence.MAX_SEQUENCE]:
		_assert(not InputSequence.is_newer(reference, reference), "duplicate sequence rejected at %d" % reference)
		var candidate := InputSequence.next(reference)
		_assert(InputSequence.is_newer(candidate, reference), "next sequence accepted at %d" % reference)
	_assert(InputSequence.next(InputSequence.MAX_SEQUENCE) == 1, "sequence wraps deterministically")
	_assert(InputSequence.is_newer(1, InputSequence.MAX_SEQUENCE), "wrapped sequence is newer")
	_assert(not InputSequence.is_newer(1, 2), "ordinary backward sequence rejected")
	_assert(not InputSequence.is_newer(0, 1), "zero sequence rejected")


func _test_half_range_future_fence() -> void:
	var reference := 1
	var edge := reference + InputSequence.HALF_RANGE
	var too_far := edge + 1
	_assert(InputSequence.is_newer(edge, reference), "half-range edge accepted")
	_assert(not InputSequence.is_newer(too_far, reference), "huge future jump beyond half-range rejected")
	for offset in [1, 2, 31, 1024, 65535]:
		var candidate := reference + offset
		_assert(InputSequence.forward_distance(reference, candidate) == offset, "forward distance deterministic for offset %d" % offset)


func _test_owner_state_does_not_trust_client_tick() -> void:
	var source := FileAccess.get_file_as_string(
		"res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_owner_movement.gd"
	)
	_assert(source.count("_client_tick") == 1, "client tick exists only as ignored compatibility parameter")
	_assert(source.count("\"client_tick\"") == 0, "owner state payload never sends client tick as authority")
	_assert(source.contains("InputSequence.next(_input_sequence)"), "owner state identity uses bounded wrap-safe sequence")
	_assert(source.contains("predicted_sequence != _owner_pending_state_sequence"), "state send waits for matching locally simulated sequence")


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error("NX.C1 client tick robustness: %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("NX.C1 client tick/sequence robustness: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("NX.C1 client tick/sequence robustness: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)

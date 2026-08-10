extends SceneTree

const ClientRuntime = preload(
	"res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd"
)

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_continuous_look_is_rate_shaped()
	_test_responsiveness_edges_remain_immediate()
	_test_local_presentation_has_single_render_writer()
	_finish()


func _test_continuous_look_is_rate_shaped() -> void:
	var runtime = ClientRuntime.new()
	_assert(runtime != null, "FIX10 fix6 cadence runtime instantiates")
	if runtime == null:
		return
	var previous := _intent(0.0, 1.0, 0.25, false, false)
	var current := _intent(0.0, 1.0, 0.27, false, false)
	var urgent: bool = bool(runtime.call(
		"_fix10_fix6_is_urgent_semantic_transition",
		previous,
		current
	))
	_assert(not urgent, "FIX10 fix6 continuous look change is cadence-shaped")
	runtime.free()


func _test_responsiveness_edges_remain_immediate() -> void:
	var runtime = ClientRuntime.new()
	if runtime == null:
		return
	var idle := _intent(0.0, 0.0, 0.0, false, false)
	var moving := _intent(0.0, 1.0, 0.0, false, false)
	var sprinting := _intent(0.0, 1.0, 0.0, false, true)
	var jumping := _intent(0.0, 1.0, 0.0, true, false)
	_assert(bool(runtime.call("_fix10_fix6_is_urgent_semantic_transition", idle, moving)), "FIX10 fix6 movement start is immediate")
	_assert(bool(runtime.call("_fix10_fix6_is_urgent_semantic_transition", moving, idle)), "FIX10 fix6 movement stop is immediate")
	_assert(bool(runtime.call("_fix10_fix6_is_urgent_semantic_transition", moving, sprinting)), "FIX10 fix6 sprint edge is immediate")
	_assert(bool(runtime.call("_fix10_fix6_is_urgent_semantic_transition", moving, jumping)), "FIX10 fix6 jump edge is immediate")
	runtime.free()


func _test_local_presentation_has_single_render_writer() -> void:
	var canonical_source: String = FileAccess.get_file_as_string(
		"res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd"
	)
	_assert(
		canonical_source.contains("m3_graphical_client_runtime_fix10_fix6_local_presentation.gd"),
		"FIX10 fix6 canonical client composes single-writer local presentation"
	)

	var presentation_source: String = FileAccess.get_file_as_string(
		"res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_fix10_fix6_local_presentation.gd"
	)
	var reconcile_start: int = presentation_source.find(
		"func _reconcile_prediction_from_snapshot(snapshot: Dictionary)"
	)
	var advance_start: int = presentation_source.find(
		"func advance_local_prediction(intent: Dictionary, frame_delta_seconds: float)",
		reconcile_start
	)
	_assert(
		reconcile_start >= 0 and advance_start > reconcile_start,
		"FIX10 fix6 local presentation reconcile override present"
	)
	if reconcile_start >= 0 and advance_start > reconcile_start:
		var reconcile_source: String = presentation_source.substr(
			reconcile_start,
			advance_start - reconcile_start
		)
		_assert(
			not reconcile_source.contains("prediction_updated.emit("),
			"FIX10 fix6 authority reconcile does not emit render pose"
		)
		_assert(
			not reconcile_source.contains("sample_presentation("),
			"FIX10 fix6 authority reconcile does not consume presentation sampler"
		)

	var cadence_source: String = FileAccess.get_file_as_string(
		"res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_fix10_fix6_semantic_cadence.gd"
	)
	_assert(
		cadence_source.contains("URGENT_EDGES_IMMEDIATE_CONTINUOUS_30HZ_V1"),
		"FIX10 fix6 continuous semantic cadence policy source present"
	)
	_assert(
		cadence_source.contains("target_client_tick <= _fix10_fix6_last_latched_client_tick"),
		"FIX10 fix6 semantic client tick latch is monotonic"
	)


func _intent(
	move_x: float,
	move_z: float,
	look_yaw: float,
	jump_pressed: bool,
	sprint: bool
) -> Dictionary:
	return {
		"move_x": move_x,
		"move_z": move_z,
		"look_yaw": look_yaw,
		"look_pitch": 0.0,
		"jump_pressed": jump_pressed,
		"sprint": sprint,
		"delta_seconds": 1.0 / 60.0,
	}


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("M7 FIX10 fix6 cadence/presentation: PASS (%d assertions)" % assertions)
		quit(0)
		return
	push_error(
		"M7 FIX10 fix6 cadence/presentation: FAIL (%d/%d): %s" % [
			failures.size(), assertions, "; ".join(failures)
		]
	)
	quit(1)

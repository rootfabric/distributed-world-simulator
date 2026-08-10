extends SceneTree

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	var scene_source := FileAccess.get_file_as_string("res://scenes/testing/playground.tscn")
	var fix7_source := FileAccess.get_file_as_string(
		"res://scripts/world/testing/playground_view_relative_runtime_fix7.gd"
	)
	var base_source := FileAccess.get_file_as_string(
		"res://scripts/world/testing/playground_view_relative_runtime.gd"
	)
	_assert(scene_source.contains("playground_view_relative_runtime_fix8.gd"), "accepted FIX8 scene identity preserved")
	_assert(fix7_source.contains("PHYSICS_SIMULATION_RENDER_RATE_BOUNDED_EXTRAPOLATION_V1"), "render-rate presentation policy present")
	_assert(fix7_source.contains("velocity_vector * _fix10_fix7_render_elapsed_seconds"), "render extrapolation uses predicted velocity")
	_assert(fix7_source.contains("FIX10_FIX7_FIXED_DELTA_SECONDS"), "render extrapolation is bounded to one fixed tick")
	_assert(fix7_source.contains("_fix10_fix7_apply_render_presentation"), "render writer is present")
	_assert(not fix7_source.contains("_sync_m7_predicted_player_state(delta)"), "render layer never advances deterministic simulation")
	_assert(base_source.contains("_render_prediction_steps_suppressed += 1"), "physics-only simulation contract remains intact")
	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _finish() -> void:
	print("M7 FIX10 fix7 render presentation: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

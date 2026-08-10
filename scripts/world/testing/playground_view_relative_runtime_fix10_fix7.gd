extends "res://scripts/world/testing/playground_view_relative_runtime_fix8.gd"

# The view-relative runtime intentionally advances deterministic prediction only
# from the 60 Hz physics loop. Older composition expected either Godot physics
# interpolation or a render-rate prediction presentation layer to smooth those
# fixed states. FIX7 disabled engine interpolation for the player/camera hierarchy,
# while view_relative_runtime continued suppressing render prediction. The result
# was a fixed 60 Hz transform presented on 120-165+ Hz render frames.
#
# Keep simulation physics-only, but restore a presentation-only render writer.
# The newest fixed prediction pose is extrapolated by elapsed render time (bounded
# to one fixed tick) using its already-deterministic velocity. No input sequence,
# prediction tick or authority state is advanced from _process().

const FIX10_FIX7_RENDER_PRESENTATION_POLICY: String = \
	"PHYSICS_SIMULATION_RENDER_RATE_BOUNDED_EXTRAPOLATION_V1"
const FIX10_FIX7_FIXED_DELTA_SECONDS: float = 1.0 / 60.0

var _fix10_fix7_latest_prediction_presentation: Dictionary = {}
var _fix10_fix7_render_elapsed_seconds: float = 0.0
var _fix10_fix7_render_presentation_applies: int = 0
var _fix10_fix7_fixed_presentations_consumed: int = 0
var _fix10_fix7_max_render_elapsed_seconds: float = 0.0
var _fix10_fix7_max_render_extrapolation_m: float = 0.0


func _process(delta: float) -> void:
	# Preserve FIX9 accounting, FIX10 remote presentation and the parent's explicit
	# render-side simulation suppression. This call does NOT advance prediction for
	# a network playground client.
	super._process(delta)
	if (
		runtime_role != "game-client"
		or not _m3_attached
		or not _network_playground_enabled
		or player == null
	):
		return

	# Physics has already consumed a newly emitted presentation through the virtual
	# _flush_pending_prediction_presentation() override below. Between fixed ticks,
	# advance only the visual pose.
	_fix10_fix7_render_elapsed_seconds = minf(
		_fix10_fix7_render_elapsed_seconds + maxf(delta, 0.0),
		FIX10_FIX7_FIXED_DELTA_SECONDS
	)
	_fix10_fix7_max_render_elapsed_seconds = maxf(
		_fix10_fix7_max_render_elapsed_seconds,
		_fix10_fix7_render_elapsed_seconds
	)
	_fix10_fix7_apply_render_presentation()


func _flush_pending_prediction_presentation() -> void:
	# This method is invoked by the inherited physics process after fixed prediction.
	# Consume the newest presentation state but deliberately do not mutate the
	# CharacterBody transform here. Render owns the visible transform exactly once.
	if not _pending_prediction_presentation_dirty:
		return
	_fix10_fix7_latest_prediction_presentation = \
		_pending_prediction_presentation.duplicate(true)
	_pending_prediction_presentation = {}
	_pending_prediction_presentation_dirty = false
	_fix10_fix7_render_elapsed_seconds = 0.0
	_fix10_fix7_fixed_presentations_consumed += 1


func _fix10_fix7_apply_render_presentation() -> void:
	if _fix10_fix7_latest_prediction_presentation.is_empty() or player == null:
		return
	var state: Dictionary = _fix10_fix7_latest_prediction_presentation
	var position_value = state.get("position", {})
	var velocity_value = state.get("velocity", {})
	if not position_value is Dictionary or not velocity_value is Dictionary:
		return
	var position: Dictionary = position_value
	var velocity: Dictionary = velocity_value
	var base_position := Vector3(
		float(position.get("x", 0.0)),
		float(position.get("y", 0.0)),
		float(position.get("z", 0.0))
	)
	var velocity_vector := Vector3(
		float(velocity.get("x", 0.0)),
		float(velocity.get("y", 0.0)),
		float(velocity.get("z", 0.0))
	)
	var extrapolation := velocity_vector * _fix10_fix7_render_elapsed_seconds
	_fix10_fix7_max_render_extrapolation_m = maxf(
		_fix10_fix7_max_render_extrapolation_m,
		extrapolation.length()
	)
	player.set_world_position(base_position + extrapolation)
	player.velocity = velocity_vector
	var yaw: float = float(state.get("orientation_yaw", 0.0))
	if player.visual_root != null:
		player.visual_root.rotation.y = yaw
	_fix10_fix7_render_presentation_applies += 1


func create_m3_graphical_client_report() -> Dictionary:
	var report: Dictionary = super.create_m3_graphical_client_report()
	var view_report: Dictionary = Dictionary(
		report.get("view_relative_prediction", {})
	).duplicate(true)
	view_report["presentation_policy"] = FIX10_FIX7_RENDER_PRESENTATION_POLICY
	view_report["render_presentation_applies"] = _fix10_fix7_render_presentation_applies
	view_report["fixed_presentations_consumed"] = _fix10_fix7_fixed_presentations_consumed
	view_report["max_render_elapsed_seconds"] = _fix10_fix7_max_render_elapsed_seconds
	view_report["max_render_extrapolation_m"] = _fix10_fix7_max_render_extrapolation_m
	report["view_relative_prediction"] = view_report
	return report

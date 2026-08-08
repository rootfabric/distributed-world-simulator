extends "res://scripts/network/prediction/client_prediction_reconciler_nx4.gd"

# FIX7 separates deterministic 60 Hz prediction from render-rate presentation.
# The authoritative/predicted state remains fixed-tick and unchanged. Only the
# returned presentation pose is advanced through the scheduler's residual
# sub-tick time using the already-predicted velocity. At the next fixed tick the
# simulated position advances by the same v*dt, so the render pose remains
# continuous instead of holding a 10/20 cm step for several 120/144/165 Hz frames.

const FIX7_PRESENTATION_POLICY: String = "SUBTICK_VELOCITY_EXTRAPOLATION_V1"
const FIX7_MAX_SUBTICK_EXTRAPOLATION_M: float = 0.35

var _fix7_render_samples: int = 0
var _fix7_nonzero_subtick_samples: int = 0
var _fix7_max_subtick_alpha: float = 0.0
var _fix7_max_extrapolation_m: float = 0.0


func sample_presentation(frame_delta_seconds: float) -> Dictionary:
	var state: Dictionary = super.sample_presentation(frame_delta_seconds)
	if state.is_empty() or not _configured:
		return state

	_fix7_render_samples += 1
	var residual_seconds: float = 0.0
	var alpha: float = 0.0
	if _scheduler != null:
		if _scheduler.has_method("get_accumulator_seconds"):
			residual_seconds = maxf(float(_scheduler.call("get_accumulator_seconds")), 0.0)
		if _scheduler.has_method("get_subtick_alpha"):
			alpha = clampf(float(_scheduler.call("get_subtick_alpha")), 0.0, 1.0)
		elif FIXED_DELTA_SECONDS > 0.0:
			alpha = clampf(residual_seconds / FIXED_DELTA_SECONDS, 0.0, 1.0)
	_fix7_max_subtick_alpha = maxf(_fix7_max_subtick_alpha, alpha)
	if residual_seconds <= 0.0000001:
		return state

	var velocity_value = state.get("velocity", {})
	if not velocity_value is Dictionary:
		return state
	var velocity: Dictionary = velocity_value
	var velocity_vector := Vector3(
		float(velocity.get("x", 0.0)),
		float(velocity.get("y", 0.0)),
		float(velocity.get("z", 0.0))
	)
	var extrapolation: Vector3 = velocity_vector * residual_seconds
	var extrapolation_m: float = extrapolation.length()
	if extrapolation_m > FIX7_MAX_SUBTICK_EXTRAPOLATION_M and extrapolation_m > 0.0:
		extrapolation *= FIX7_MAX_SUBTICK_EXTRAPOLATION_M / extrapolation_m
		extrapolation_m = FIX7_MAX_SUBTICK_EXTRAPOLATION_M
	if extrapolation_m <= 0.0000001:
		return state

	var position_value = state.get("position", {})
	if not position_value is Dictionary:
		return state
	var position: Dictionary = position_value
	var rendered_position := Vector3(
		float(position.get("x", 0.0)),
		float(position.get("y", 0.0)),
		float(position.get("z", 0.0))
	) + extrapolation
	state["position"] = {
		"x": rendered_position.x,
		"y": rendered_position.y,
		"z": rendered_position.z,
	}
	_fix7_nonzero_subtick_samples += 1
	_fix7_max_extrapolation_m = maxf(_fix7_max_extrapolation_m, extrapolation_m)
	return state


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	report["render_presentation_policy"] = FIX7_PRESENTATION_POLICY
	report["render_samples"] = _fix7_render_samples
	report["nonzero_subtick_samples"] = _fix7_nonzero_subtick_samples
	report["max_subtick_alpha"] = _fix7_max_subtick_alpha
	report["max_subtick_extrapolation_m"] = _fix7_max_extrapolation_m
	report["max_subtick_extrapolation_limit_m"] = FIX7_MAX_SUBTICK_EXTRAPOLATION_M
	return report

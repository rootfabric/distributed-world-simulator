extends "res://scripts/network/prediction/client_prediction_reconciler_nx4.gd"

# FIX7 separates deterministic 60 Hz prediction from render-rate presentation.
# The authoritative/predicted state remains fixed-tick and unchanged. Only the
# returned presentation pose is advanced through the scheduler's residual
# sub-tick time using the already-predicted velocity. At the next fixed tick the
# simulated position advances by the same v*dt, so the render pose remains
# continuous instead of holding a 10/20 cm step for several 120/144/165 Hz frames.
#
# FIX8 addresses the remaining LOCAL micro-correction signature: movement
# snapshots are normally published every three authority ticks, and a client can
# receive T+3 while its prediction scheduler is still at T even though both sides
# already agree on the active input sequence. Comparing T against T+3 creates an
# artificial 0.3 m error at 6 m/s. FIX8 pre-simulates only this sequence-matched
# bounded future gap. A true clock-only snapshot whose kinematic state is already
# identical advances only the clock. Both paths preserve the scheduler's sub-tick
# phase instead of reconfiguring it. Real input-latency disagreement (different
# input sequence) remains on the existing authoritative reconciliation path.
#
# FIX8 also makes visual correction continuity bounded and rate-limited. The old
# compositor could preserve presentation continuity by accumulating repeated
# offsets, then decay a metre-scale offset using the short duration selected from
# one 0.3 m correction. The new policy caps that continuity debt and chooses a
# decay duration from the actual visual offset as well as the prediction error.

const FIX7_PRESENTATION_POLICY: String = "SUBTICK_VELOCITY_EXTRAPOLATION_V1"
const FIX7_MAX_SUBTICK_EXTRAPOLATION_M: float = 0.35

const FIX8_CLOCK_ALIGNMENT_POLICY: String = "SEQUENCE_MATCHED_FUTURE_TICK_PREALIGN_V1"
const FIX8_CORRECTION_POLICY: String = "BOUNDED_CONTINUITY_OFFSET_RATE_LIMITED_DECAY_V1"
const FIX8_MAX_FUTURE_ALIGNMENT_TICKS: int = 8
const FIX8_MAX_VISUAL_OFFSET_M: float = 0.50
const FIX8_MAX_VISUAL_CORRECTION_SPEED_MPS: float = 2.50
const FIX8_KINEMATIC_EPSILON_M: float = 0.000001

var _fix7_render_samples: int = 0
var _fix7_nonzero_subtick_samples: int = 0
var _fix7_max_subtick_alpha: float = 0.0
var _fix7_max_extrapolation_m: float = 0.0

var _fix8_clock_alignment_events: int = 0
var _fix8_clock_alignment_ticks: int = 0
var _fix8_clock_only_alignment_events: int = 0
var _fix8_clock_only_alignment_ticks: int = 0
var _fix8_max_future_gap_ticks: int = 0
var _fix8_large_gap_alignment_skips: int = 0
var _fix8_sequence_mismatch_alignment_skips: int = 0
var _fix8_visual_offset_clamps: int = 0
var _fix8_rate_limited_corrections: int = 0
var _fix8_max_raw_visual_offset_m: float = 0.0
var _fix8_max_bounded_visual_offset_m: float = 0.0
var _fix8_max_decay_seconds: float = 0.0


func reconcile(authoritative_player: Dictionary, server_tick: int) -> Dictionary:
	var aligned_ticks: int = 0
	var alignment_mode := "NONE"
	if (
		_configured
		and server_tick >= _last_authoritative_tick
		and server_tick > _prediction_tick
		and _valid_player_state(authoritative_player)
	):
		var gap_ticks: int = server_tick - _prediction_tick
		_fix8_max_future_gap_ticks = maxi(_fix8_max_future_gap_ticks, gap_ticks)
		var authoritative_sequence: int = int(
			authoritative_player.get("last_input_sequence", 0)
		)
		var sequence_matches: bool = authoritative_sequence == _current_sequence
		if not sequence_matches:
			_fix8_sequence_mismatch_alignment_skips += 1
		elif gap_ticks > FIX8_MAX_FUTURE_ALIGNMENT_TICKS:
			_fix8_large_gap_alignment_skips += 1
		elif _fix8_same_kinematic_state(authoritative_player, _predicted_state):
			var clock_only_alignment: Dictionary = _fix8_align_clock_only_forward(
				server_tick
			)
			if not bool(clock_only_alignment.get("success", false)):
				return clock_only_alignment
			aligned_ticks = int(
				clock_only_alignment.get("details", {}).get("aligned_ticks", 0)
			)
			alignment_mode = "CLOCK_ONLY"
		else:
			var alignment: Dictionary = _fix8_align_prediction_forward(server_tick)
			if not bool(alignment.get("success", false)):
				return alignment
			aligned_ticks = int(alignment.get("details", {}).get("aligned_ticks", 0))
			alignment_mode = "SIMULATED"

	var result: Dictionary = super.reconcile(authoritative_player, server_tick)
	if bool(result.get("success", false)):
		var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
		details["fix8_clock_aligned_ticks"] = aligned_ticks
		details["fix8_clock_alignment_mode"] = alignment_mode
		details["fix8_clock_alignment_policy"] = FIX8_CLOCK_ALIGNMENT_POLICY
		result["details"] = details
	return result


func _fix8_align_clock_only_forward(target_tick: int) -> Dictionary:
	if target_tick <= _prediction_tick:
		return _success({"aligned_ticks": 0})
	var start_tick := _prediction_tick
	var scheduler_alignment: Dictionary = _scheduler.align_forward_to_tick(target_tick)
	if not bool(scheduler_alignment.get("success", false)):
		return _failure(
			String(scheduler_alignment.get(
				"error_code", "FIX8_PREDICTION_CLOCK_ALIGNMENT_FAILED"
			)),
			Dictionary(scheduler_alignment.get("details", {}))
		)
	_prediction_tick = target_tick
	var aligned_ticks := target_tick - start_tick
	_fix8_clock_alignment_events += 1
	_fix8_clock_alignment_ticks += aligned_ticks
	_fix8_clock_only_alignment_events += 1
	_fix8_clock_only_alignment_ticks += aligned_ticks
	return _success({
		"aligned_ticks": aligned_ticks,
		"prediction_tick": _prediction_tick,
		"preserved_subtick_seconds": float(
			scheduler_alignment.get("details", {}).get(
				"preserved_accumulator_seconds", 0.0
			)
		),
	})


func _fix8_align_prediction_forward(target_tick: int) -> Dictionary:
	if target_tick <= _prediction_tick:
		return _success({"aligned_ticks": 0})
	var start_tick: int = _prediction_tick
	var alignment_intent: Dictionary = _current_intent.duplicate(true)
	for tick in range(start_tick + 1, target_tick + 1):
		var tick_result: Dictionary = _simulate_tick(
			tick,
			_current_sequence,
			alignment_intent,
			true
		)
		if not bool(tick_result.get("success", false)):
			return tick_result
		alignment_intent["jump_pressed"] = false
	if target_tick > start_tick:
		_current_intent["jump_pressed"] = false
	var scheduler_alignment: Dictionary = _scheduler.align_forward_to_tick(target_tick)
	if not bool(scheduler_alignment.get("success", false)):
		return _failure(
			String(scheduler_alignment.get(
				"error_code", "FIX8_PREDICTION_CLOCK_ALIGNMENT_FAILED"
			)),
			Dictionary(scheduler_alignment.get("details", {}))
		)
	_prediction_tick = target_tick
	var aligned_ticks: int = target_tick - start_tick
	_fix8_clock_alignment_events += 1
	_fix8_clock_alignment_ticks += aligned_ticks
	return _success({
		"aligned_ticks": aligned_ticks,
		"prediction_tick": _prediction_tick,
		"preserved_subtick_seconds": float(
			scheduler_alignment.get("details", {}).get(
				"preserved_accumulator_seconds", 0.0
			)
		),
	})


func _fix8_same_kinematic_state(left: Dictionary, right: Dictionary) -> bool:
	if left.is_empty() or right.is_empty():
		return false
	if int(left.get("last_input_sequence", 0)) != int(right.get("last_input_sequence", 0)):
		return false
	if _position(left).distance_to(_position(right)) > FIX8_KINEMATIC_EPSILON_M:
		return false
	if _fix8_velocity(left).distance_to(_fix8_velocity(right)) > FIX8_KINEMATIC_EPSILON_M:
		return false
	return is_equal_approx(
		float(left.get("orientation_yaw", 0.0)),
		float(right.get("orientation_yaw", 0.0))
	)


func _fix8_velocity(state: Dictionary) -> Vector3:
	var value: Dictionary = Dictionary(state.get("velocity", {}))
	return Vector3(
		float(value.get("x", 0.0)),
		float(value.get("y", 0.0)),
		float(value.get("z", 0.0))
	)


func _apply_correction(presentation_offset: Vector3, error_m: float) -> void:
	_last_correction_mode = "NONE"
	if error_m < IGNORE_THRESHOLD_M:
		# Matching clock-only and duplicate snapshots must not cancel a visual
		# correction that is still decaying from an earlier authoritative update.
		return
	_visual_offset = Vector3.ZERO
	_visual_decay_seconds = 0.0
	_corrections += 1
	if error_m > HARD_CORRECTION_THRESHOLD_M:
		_hard_corrections += 1
		_last_correction_mode = "HARD"
		return

	var raw_offset_m: float = presentation_offset.length()
	_fix8_max_raw_visual_offset_m = maxf(
		_fix8_max_raw_visual_offset_m, raw_offset_m
	)
	_visual_offset = presentation_offset
	if raw_offset_m > FIX8_MAX_VISUAL_OFFSET_M and raw_offset_m > 0.0:
		_visual_offset *= FIX8_MAX_VISUAL_OFFSET_M / raw_offset_m
		_fix8_visual_offset_clamps += 1
	var bounded_offset_m: float = _visual_offset.length()
	_fix8_max_bounded_visual_offset_m = maxf(
		_fix8_max_bounded_visual_offset_m, bounded_offset_m
	)

	var threshold_duration: float = VERY_FAST_DURATION_SECONDS
	if error_m <= SMOOTH_THRESHOLD_M:
		_last_correction_mode = "SMOOTH"
		threshold_duration = SMOOTH_DURATION_SECONDS
	elif error_m <= FAST_THRESHOLD_M:
		_last_correction_mode = "FAST"
		threshold_duration = FAST_DURATION_SECONDS
	else:
		_last_correction_mode = "VERY_FAST"
		threshold_duration = VERY_FAST_DURATION_SECONDS

	var rate_limited_duration: float = (
		bounded_offset_m / FIX8_MAX_VISUAL_CORRECTION_SPEED_MPS
		if FIX8_MAX_VISUAL_CORRECTION_SPEED_MPS > 0.0
		else threshold_duration
	)
	_visual_decay_seconds = maxf(threshold_duration, rate_limited_duration)
	if rate_limited_duration > threshold_duration + 0.000001:
		_fix8_rate_limited_corrections += 1
	_fix8_max_decay_seconds = maxf(
		_fix8_max_decay_seconds, _visual_decay_seconds
	)


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
	report["clock_alignment_policy"] = FIX8_CLOCK_ALIGNMENT_POLICY
	report["correction_policy"] = FIX8_CORRECTION_POLICY
	report["max_future_alignment_ticks"] = FIX8_MAX_FUTURE_ALIGNMENT_TICKS
	report["clock_alignment_events"] = _fix8_clock_alignment_events
	report["clock_alignment_ticks"] = _fix8_clock_alignment_ticks
	report["clock_only_alignment_events"] = _fix8_clock_only_alignment_events
	report["clock_only_alignment_ticks"] = _fix8_clock_only_alignment_ticks
	report["max_future_gap_ticks"] = _fix8_max_future_gap_ticks
	report["large_gap_alignment_skips"] = _fix8_large_gap_alignment_skips
	report["sequence_mismatch_alignment_skips"] = _fix8_sequence_mismatch_alignment_skips
	report["max_visual_offset_limit_m"] = FIX8_MAX_VISUAL_OFFSET_M
	report["max_visual_correction_speed_mps"] = FIX8_MAX_VISUAL_CORRECTION_SPEED_MPS
	report["visual_offset_clamps"] = _fix8_visual_offset_clamps
	report["rate_limited_corrections"] = _fix8_rate_limited_corrections
	report["max_raw_visual_offset_m"] = _fix8_max_raw_visual_offset_m
	report["max_bounded_visual_offset_m"] = _fix8_max_bounded_visual_offset_m
	report["max_visual_decay_seconds"] = _fix8_max_decay_seconds
	return report

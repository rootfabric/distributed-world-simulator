extends "res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_fix10_fix6_core.gd"

# FIX10 fix6 semantic cadence layer.
#
# Prediction/rendering remains 60 Hz. Only creation of new authoritative input
# sequences is rate-shaped: continuous movement/look state is sampled at the
# existing 30 Hz realtime input cadence, while discrete responsiveness edges are
# submitted immediately. This keeps the server input queue shallow enough that
# its accepted pressure compaction policy does not discard ordinary semantic
# transitions and invalidate PRE/POST transition comparison.

const FIX10_FIX6_CONTINUOUS_INPUT_POLICY: String = \
	"URGENT_EDGES_IMMEDIATE_CONTINUOUS_30HZ_V1"
const FIX10_FIX6_URGENT_MOVE_DELTA_THRESHOLD: float = 0.35

var _fix10_fix6_continuous_changes_rate_limited: int = 0
var _fix10_fix6_urgent_semantic_submissions: int = 0
var _fix10_fix6_cadence_semantic_submissions: int = 0
var _fix10_fix6_nonmonotonic_tick_suppressions: int = 0


func setup(config: Dictionary) -> Dictionary:
	_fix10_fix6_continuous_changes_rate_limited = 0
	_fix10_fix6_urgent_semantic_submissions = 0
	_fix10_fix6_cadence_semantic_submissions = 0
	_fix10_fix6_nonmonotonic_tick_suppressions = 0
	return super.setup(config)


func advance_local_prediction(intent: Dictionary, frame_delta_seconds: float) -> Dictionary:
	if not is_ready():
		return _failure("M7_CLIENT_NOT_READY")
	if _prediction_reconciler == null or not _prediction_reconciler.is_configured():
		_initialize_prediction_from_snapshot(get_snapshot())
	if _prediction_reconciler == null or not _prediction_reconciler.is_configured():
		return _failure("NX4_PREDICTION_NOT_READY")

	var canonical: Dictionary = _canonical_prediction_intent(intent)
	_prediction_input_accumulator += maxf(frame_delta_seconds, 0.0)
	var first_submission: bool = _prediction_last_network_intent.is_empty()
	var changed: bool = not _same_prediction_intent(
		_prediction_last_network_intent,
		canonical
	)
	var urgent: bool = (
		first_submission
		or _fix10_fix6_is_urgent_semantic_transition(
			_prediction_last_network_intent,
			canonical
		)
	)
	var cadence_due: bool = (
		_prediction_input_accumulator >= NX4_INPUT_SEND_INTERVAL_SECONDS
	)
	var should_submit: bool = urgent or cadence_due
	if changed and not urgent and not cadence_due:
		_fix10_fix6_continuous_changes_rate_limited += 1

	var target_client_tick: int = _prediction_reconciler.get_prediction_tick() + 1
	var submission: Dictionary = _success()
	var submission_attempted: bool = false
	if should_submit:
		# Reconciliation can temporarily move the local prediction clock backward.
		# Never create another semantic sequence for a tick that was already latched.
		if target_client_tick <= _fix10_fix6_last_latched_client_tick:
			_fix10_fix6_same_tick_input_update_suppressions += 1
			if target_client_tick < _fix10_fix6_last_latched_client_tick:
				_fix10_fix6_nonmonotonic_tick_suppressions += 1
		else:
			submission_attempted = true
			submission = submit_movement_intent_nonblocking(
				canonical,
				target_client_tick
			)
			var submission_error: String = String(submission.get("error_code", ""))
			var semantic_latched: bool = (
				bool(submission.get("success", false))
				or submission_error == "M7_PLAYER_INPUT_SEND_FAILED"
			)
			if semantic_latched:
				_fix10_fix6_last_latched_client_tick = target_client_tick
				_fix10_fix6_semantic_input_submissions += 1
				if urgent:
					_fix10_fix6_urgent_semantic_submissions += 1
				else:
					_fix10_fix6_cadence_semantic_submissions += 1
				_prediction_input_accumulator = 0.0
				_prediction_last_network_intent = canonical.duplicate(true)
			elif not submission_error.is_empty():
				return submission

	var advanced: Dictionary = _prediction_reconciler.advance_frame(frame_delta_seconds)
	if not bool(advanced.get("success", false)):
		_prediction_advance_failures += 1
		return advanced
	_prediction_frames += 1
	var predicted_state: Dictionary = _prediction_reconciler.get_predicted_state()
	var presentation_state: Dictionary = _prediction_reconciler.sample_presentation(
		frame_delta_seconds
	)
	_prediction_updates_emitted += 1
	prediction_updated.emit(
		predicted_state.duplicate(true),
		presentation_state.duplicate(true),
		_prediction_reconciler.get_report()
	)
	return _success({
		"submission_attempted": submission_attempted,
		"submission": submission,
		"predicted_state": predicted_state,
		"presentation_state": presentation_state,
		"prediction": _prediction_reconciler.get_report(),
		"fix10_fix6_target_client_tick": target_client_tick,
		"fix10_fix6_semantic_input_latch_policy": FIX10_FIX6_SEMANTIC_INPUT_LATCH_POLICY,
		"fix10_fix6_continuous_input_policy": FIX10_FIX6_CONTINUOUS_INPUT_POLICY,
		"fix10_fix6_urgent_transition": urgent,
		"fix10_fix6_cadence_due": cadence_due,
	})


func _fix10_fix6_is_urgent_semantic_transition(
	previous: Dictionary,
	current: Dictionary
) -> bool:
	if previous.is_empty():
		return true
	if bool(current.get("jump_pressed", false)):
		return true
	if bool(previous.get("sprint", false)) != bool(current.get("sprint", false)):
		return true

	var previous_move := Vector2(
		float(previous.get("move_x", 0.0)),
		float(previous.get("move_z", 0.0))
	)
	var current_move := Vector2(
		float(current.get("move_x", 0.0)),
		float(current.get("move_z", 0.0))
	)
	var previous_active: bool = previous_move.length_squared() > 0.000001
	var current_active: bool = current_move.length_squared() > 0.000001
	if previous_active != current_active:
		return true
	if (
		previous_active
		and previous_move.distance_to(current_move)
			>= FIX10_FIX6_URGENT_MOVE_DELTA_THRESHOLD
	):
		return true
	return false


func _emit_prediction_health_if_due() -> void:
	var previous_health_ms: int = _last_prediction_health_ms
	super._emit_prediction_health_if_due()
	if _last_prediction_health_ms == previous_health_ms:
		return
	_debug_event("FIX10_FIX6_SEMANTIC_CADENCE_HEALTH", {
		"policy": FIX10_FIX6_CONTINUOUS_INPUT_POLICY,
		"continuous_changes_rate_limited": _fix10_fix6_continuous_changes_rate_limited,
		"urgent_semantic_submissions": _fix10_fix6_urgent_semantic_submissions,
		"cadence_semantic_submissions": _fix10_fix6_cadence_semantic_submissions,
		"nonmonotonic_tick_suppressions": _fix10_fix6_nonmonotonic_tick_suppressions,
	})


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	var transport: Dictionary = Dictionary(
		report.get("fix10_prediction_ack_transport", {})
	).duplicate(true)
	transport["fix6_continuous_input_policy"] = FIX10_FIX6_CONTINUOUS_INPUT_POLICY
	transport["fix6_continuous_changes_rate_limited"] = \
		_fix10_fix6_continuous_changes_rate_limited
	transport["fix6_urgent_semantic_submissions"] = _fix10_fix6_urgent_semantic_submissions
	transport["fix6_cadence_semantic_submissions"] = _fix10_fix6_cadence_semantic_submissions
	transport["fix6_nonmonotonic_tick_suppressions"] = _fix10_fix6_nonmonotonic_tick_suppressions
	report["fix10_prediction_ack_transport"] = transport
	return report

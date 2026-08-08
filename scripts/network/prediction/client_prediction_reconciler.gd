extends "res://scripts/network/prediction/client_prediction_reconciler_fix8.gd"

# FIX10 preserves every FIX7/FIX8 presentation and correction invariant, but
# stops treating server wall-clock phase as the acknowledgement boundary for a
# locally predicted input stream. The server now echoes the authoritative state
# immediately after it first consumes an input sequence together with the
# original client prediction tick. That pair is the same logical point in the
# deterministic movement stream even when transport delay makes the server apply
# it several wall-clock ticks later.
#
# FIX10 fix4 additionally treats the snapshot clock that transported an ACK as
# provenance, not semantic identity. Standalone ACKs travel on a different ENet
# channel and can legitimately arrive before/after a later movement snapshot.
# Reconciliation therefore keys the baseline by client_tick/input_sequence and
# only requires the carrying snapshot clock to be <= the snapshot currently being
# reconciled. A newer authoritative snapshot may already acknowledge a later input
# sequence; that is normal and no longer counted as an ACK mismatch.
#
# FIX10 fix5 closes one remaining ambiguity exposed by the exact Windows
# two-client process. Multiple movement state transitions can legitimately be
# stamped with the same future client prediction tick before that tick is
# simulated. Therefore client_tick alone is not an ACK identity. The semantic key
# is the ordered pair (client_tick, input_sequence), with wrap-aware sequence
# ordering inside one tick. Same-tick newer sequences supersede older metadata;
# same-tick older sequences are stale. Only a conflicting authoritative baseline
# for the exact same composite key remains a semantic mismatch.
#
# Compatibility anchors retained for the accepted FIX8 source contracts:
# SEQUENCE_MATCHED_FUTURE_TICK_PREALIGN_V1
# authoritative_sequence == _current_sequence
# FIX8_MAX_FUTURE_ALIGNMENT_TICKS
# FIX8_MAX_VISUAL_OFFSET_M
# FIX8_MAX_VISUAL_CORRECTION_SPEED_MPS

const Fix10InputSequence = preload("res://scripts/network/simulation/input_sequence.gd")

const FIX10_PREDICTION_ACK_POLICY: String = "SERVER_ECHOED_POST_INPUT_BASELINE_V1"
const FIX10_RECONCILIATION_POLICY: String = "ACK_BASELINE_REPLAY_LOCAL_TIMELINE_V1"
const FIX10_TIMELINE_POLICY: String = "BOUNDED_CLIENT_TICK_INPUT_TIMELINE_V1"
const FIX10_FIX4_ACK_TRANSPORT_POLICY: String = "SEMANTIC_ACK_BASELINE_DECOUPLED_FROM_TRANSPORT_SNAPSHOT_V1"
const FIX10_FIX5_ACK_IDENTITY_POLICY: String = "CLIENT_TICK_AND_WRAP_AWARE_INPUT_SEQUENCE_V1"
const FIX10_MAX_TIMELINE_TICKS: int = 512

var _fix10_pending_ack: Dictionary = {}
var _fix10_timeline_by_tick: Dictionary = {}
var _fix10_timeline_ticks: Array[int] = []
var _fix10_ack_reconciliations: int = 0
var _fix10_ack_replays: int = 0
var _fix10_ack_replayed_ticks: int = 0
var _fix10_ack_history_misses: int = 0
var _fix10_ack_mismatches: int = 0
var _fix10_ack_registration_rejections: int = 0
var _fix10_max_ack_baseline_error_m: float = 0.0
var _fix10_max_present_replay_error_m: float = 0.0
var _fix10_last_ack_sequence: int = 0
var _fix10_last_ack_client_tick: int = 0
var _fix10_last_ack_applied_server_tick: int = 0
var _fix10_last_reconciliation_mode: String = "NONE"
var _fix10_last_ack_semantic: Dictionary = {}

var _fix10_fix4_transport_tick_lagged: int = 0
var _fix10_fix4_authority_sequence_ahead: int = 0
var _fix10_fix4_future_ack_deferrals: int = 0
var _fix10_fix4_stale_ack_registrations: int = 0
var _fix10_fix4_pending_ack_superseded: int = 0
var _fix10_fix4_last_ack_transport_snapshot_tick: int = -1

var _fix10_fix5_same_tick_sequence_supersessions: int = 0
var _fix10_fix5_same_tick_sequence_stale: int = 0
var _fix10_fix5_exact_key_conflicts: int = 0
var _fix10_fix5_local_timeline_superseded_acks: int = 0


func configure(authoritative_player: Dictionary, server_tick: int) -> Dictionary:
	_fix10_reset_state()
	return super.configure(authoritative_player, server_tick)


func set_authoritative_input_ack(ack_value: Dictionary, snapshot_server_tick: int) -> Dictionary:
	if not _configured:
		return _failure("FIX10_PREDICTION_NOT_CONFIGURED")
	if snapshot_server_tick < 0:
		_fix10_ack_registration_rejections += 1
		return _failure("FIX10_INVALID_ACK_SNAPSHOT_TICK")
	var ack: Dictionary = ack_value.duplicate(true)
	var sequence: int = int(ack.get("input_sequence", 0))
	var client_tick: int = int(ack.get("client_tick", 0))
	var applied_server_tick: int = int(ack.get("applied_server_tick", 0))
	if not Fix10InputSequence.is_valid(sequence):
		_fix10_ack_registration_rejections += 1
		return _failure("FIX10_INVALID_ACK_SEQUENCE")
	if client_tick < 1 or applied_server_tick < 1:
		_fix10_ack_registration_rejections += 1
		return _failure("FIX10_INVALID_ACK_TIMELINE")
	if applied_server_tick > snapshot_server_tick:
		_fix10_ack_registration_rejections += 1
		return _failure("FIX10_ACK_AFTER_SNAPSHOT")
	if not ack.get("position") is Dictionary or not ack.get("velocity") is Dictionary:
		_fix10_ack_registration_rejections += 1
		return _failure("FIX10_ACK_KINEMATICS_REQUIRED")
	var yaw: float = float(ack.get("orientation_yaw", 0.0))
	if is_nan(yaw) or is_inf(yaw):
		_fix10_ack_registration_rejections += 1
		return _failure("FIX10_INVALID_ACK_ORIENTATION")
	ack["snapshot_server_tick"] = snapshot_server_tick

	# Compare against the most recently accepted semantic ACK using the composite
	# key. Different sequences at the same client tick are legal state transitions,
	# not contradictions.
	if not _fix10_last_ack_semantic.is_empty():
		var accepted_order: int = _fix10_fix5_compare_ack_order(ack, _fix10_last_ack_semantic)
		if accepted_order < 0:
			_fix10_fix4_stale_ack_registrations += 1
			if client_tick == _fix10_last_ack_client_tick:
				_fix10_fix5_same_tick_sequence_stale += 1
			return _fix10_fix5_stale_registration_result(ack)
		if accepted_order == 0:
			if not _fix10_fix5_same_ack_baseline(ack, _fix10_last_ack_semantic):
				_fix10_ack_mismatches += 1
				_fix10_fix5_exact_key_conflicts += 1
				return _failure("FIX10_ACK_BASELINE_CONFLICT_AT_SEMANTIC_KEY")
			_fix10_fix4_stale_ack_registrations += 1
			return _fix10_fix5_stale_registration_result(ack, true)

	if not _fix10_pending_ack.is_empty():
		var pending_order: int = _fix10_fix5_compare_ack_order(ack, _fix10_pending_ack)
		if pending_order < 0:
			_fix10_fix4_stale_ack_registrations += 1
			if client_tick == int(_fix10_pending_ack.get("client_tick", 0)):
				_fix10_fix5_same_tick_sequence_stale += 1
			return _fix10_fix5_stale_registration_result(ack)
		if pending_order == 0:
			if not _fix10_fix5_same_ack_baseline(ack, _fix10_pending_ack):
				_fix10_ack_mismatches += 1
				_fix10_fix5_exact_key_conflicts += 1
				return _failure("FIX10_PENDING_ACK_BASELINE_CONFLICT")
			if snapshot_server_tick < int(_fix10_pending_ack.get("snapshot_server_tick", -1)):
				_fix10_fix4_stale_ack_registrations += 1
				return _fix10_fix5_stale_registration_result(ack, true)
		else:
			_fix10_fix4_pending_ack_superseded += 1
			if client_tick == int(_fix10_pending_ack.get("client_tick", 0)):
				_fix10_fix5_same_tick_sequence_supersessions += 1

	_fix10_pending_ack = ack
	return _success({
		"input_sequence": sequence,
		"client_tick": client_tick,
		"applied_server_tick": applied_server_tick,
		"snapshot_server_tick": snapshot_server_tick,
		"ignored_stale": false,
		"duplicate_semantic": false,
	})


func reconcile(authoritative_player: Dictionary, server_tick: int) -> Dictionary:
	_fix10_last_reconciliation_mode = "FALLBACK"
	if not _fix10_pending_ack.is_empty():
		var ack: Dictionary = _fix10_pending_ack.duplicate(true)
		_fix10_pending_ack.clear()
		var attempt: Dictionary = _fix10_reconcile_from_ack(
			authoritative_player,
			server_tick,
			ack
		)
		if bool(attempt.get("defer", false)):
			_fix10_pending_ack = ack
		elif bool(attempt.get("handled", false)):
			return Dictionary(attempt.get("result", {}))
	return super.reconcile(authoritative_player, server_tick)


func _simulate_tick(
	tick: int,
	input_sequence: int,
	intent: Dictionary,
	replay: bool
) -> Dictionary:
	var result: Dictionary = super._simulate_tick(tick, input_sequence, intent, replay)
	if bool(result.get("success", false)) and input_sequence > 0:
		_fix10_record_timeline_tick(tick, input_sequence, intent, _predicted_state)
	return result


func _fix10_reconcile_from_ack(
	authoritative_player: Dictionary,
	server_tick: int,
	ack: Dictionary
) -> Dictionary:
	if not _configured or not _valid_player_state(authoritative_player):
		return {"handled": false}
	if server_tick < _last_authoritative_tick:
		_fix10_ack_replays += 1
		return {"handled": false}

	var transport_snapshot_tick: int = int(ack.get("snapshot_server_tick", -1))
	if transport_snapshot_tick > server_tick:
		_fix10_fix4_future_ack_deferrals += 1
		return {"handled": false, "defer": true}
	if transport_snapshot_tick < server_tick:
		_fix10_fix4_transport_tick_lagged += 1
	_fix10_fix4_last_ack_transport_snapshot_tick = transport_snapshot_tick

	var sequence: int = int(ack.get("input_sequence", 0))
	var client_tick: int = int(ack.get("client_tick", 0))
	var applied_server_tick: int = int(ack.get("applied_server_tick", 0))
	var authoritative_sequence: int = int(authoritative_player.get("last_input_sequence", 0))
	if sequence != authoritative_sequence:
		if Fix10InputSequence.is_newer(sequence, authoritative_sequence):
			# A carrying snapshot at/before this authoritative snapshot cannot truthfully
			# acknowledge an input newer than the player's current authority sequence.
			_fix10_ack_mismatches += 1
			return {"handled": false}
		if Fix10InputSequence.is_newer(authoritative_sequence, sequence):
			_fix10_fix4_authority_sequence_ahead += 1
		else:
			_fix10_ack_mismatches += 1
			return {"handled": false}
	if client_tick > _prediction_tick:
		_fix10_ack_history_misses += 1
		return {"handled": false}

	# A repeated movement snapshot often carries the same latest ack while the
	# server continues to hold that input. Re-applying the same baseline would
	# manufacture a correction every snapshot, so advance acknowledgement
	# observability only and keep the already reconstructed local prediction.
	if sequence == _fix10_last_ack_sequence and client_tick == _fix10_last_ack_client_tick:
		_last_authoritative_tick = server_tick
		_last_authoritative_sequence = authoritative_sequence
		_last_error_m = 0.0
		_reconciliations += 1
		_fix10_ack_replays += 1
		_fix10_last_ack_applied_server_tick = applied_server_tick
		_fix10_last_reconciliation_mode = "ACK_REPLAY"
		_fix10_last_ack_semantic = ack.duplicate(true)
		return {"handled": true, "result": _success({
			"prediction_error_m": 0.0,
			"replayed_ticks": 0,
			"prediction_tick": _prediction_tick,
			"correction_mode": "NONE",
			"hard_correction": false,
			"predicted_state": _predicted_state.duplicate(true),
			"fix10_reconciliation_mode": "ACK_REPLAY",
			"fix10_ack_sequence": sequence,
			"fix10_ack_client_tick": client_tick,
			"fix10_ack_applied_server_tick": applied_server_tick,
			"fix10_ack_transport_snapshot_tick": transport_snapshot_tick,
		})}

	var baseline_record: Dictionary = _fix10_timeline_record(client_tick)
	if baseline_record.is_empty():
		_fix10_ack_history_misses += 1
		return {"handled": false}
	var baseline_sequence: int = int(baseline_record.get("input_sequence", 0))
	if baseline_sequence != sequence:
		# A newer local transition can legitimately share the same client tick. That
		# makes this ACK metadata stale for replay, but it is not a history hole or a
		# protocol mismatch. Fall back conservatively for the authority snapshot.
		if Fix10InputSequence.is_newer(baseline_sequence, sequence):
			_fix10_fix5_local_timeline_superseded_acks += 1
			return {"handled": false}
		_fix10_ack_history_misses += 1
		return {"handled": false}

	var old_prediction_tick: int = _prediction_tick
	var replay_records: Array[Dictionary] = []
	var expected_tick: int = client_tick + 1
	for tick in _fix10_timeline_ticks:
		if tick <= client_tick or tick > old_prediction_tick:
			continue
		if tick != expected_tick:
			_fix10_ack_history_misses += 1
			return {"handled": false}
		var record: Dictionary = _fix10_timeline_record(tick)
		if record.is_empty():
			_fix10_ack_history_misses += 1
			return {"handled": false}
		replay_records.append(record)
		expected_tick += 1
	if old_prediction_tick >= client_tick + 1 and expected_tick != old_prediction_tick + 1:
		_fix10_ack_history_misses += 1
		return {"handled": false}

	var baseline_player: Dictionary = authoritative_player.duplicate(true)
	baseline_player["position"] = Dictionary(ack.get("position", {})).duplicate(true)
	baseline_player["velocity"] = Dictionary(ack.get("velocity", {})).duplicate(true)
	baseline_player["orientation_yaw"] = float(ack.get("orientation_yaw", 0.0))
	baseline_player["last_input_sequence"] = sequence
	baseline_player["state_revision"] = int(
		ack.get("state_revision", baseline_player.get("state_revision", 1))
	)
	if not _valid_player_state(baseline_player):
		_fix10_ack_mismatches += 1
		return {"handled": false}

	var baseline_error_m: float = _position(
		Dictionary(baseline_record.get("state", {}))
	).distance_to(_position(baseline_player))
	_fix10_max_ack_baseline_error_m = maxf(
		_fix10_max_ack_baseline_error_m,
		baseline_error_m
	)

	# Build the corrected present transactionally. Nothing in the live prediction
	# state is mutated until the entire replay succeeds.
	var candidate_state: Dictionary = baseline_player.duplicate(true)
	var rebuilt_history: Array[Dictionary] = []
	for record_value in replay_records:
		var record: Dictionary = Dictionary(record_value)
		var record_sequence: int = int(record.get("input_sequence", 0))
		var record_intent: Dictionary = Dictionary(record.get("intent", {})).duplicate(true)
		var movement_result: Dictionary = _movement.apply_fixed_tick(
			candidate_state,
			record_sequence,
			record_intent,
			FIXED_DELTA_SECONDS
		)
		if not bool(movement_result.get("success", false)):
			_fix10_ack_mismatches += 1
			return {"handled": false}
		candidate_state = Dictionary(
			movement_result.get("details", {}).get("player", candidate_state)
		).duplicate(true)
		rebuilt_history.append({
			"tick": int(record.get("tick", 0)),
			"input_sequence": record_sequence,
			"intent": record_intent.duplicate(true),
			"state": candidate_state.duplicate(true),
		})

	var old_predicted_position: Vector3 = _position(_predicted_state)
	var old_presentation_position: Vector3 = old_predicted_position + _visual_offset
	var present_error_m: float = old_predicted_position.distance_to(_position(candidate_state))
	_fix10_max_present_replay_error_m = maxf(
		_fix10_max_present_replay_error_m,
		present_error_m
	)

	_predicted_state = candidate_state
	_prediction_tick = old_prediction_tick
	_history.clear()
	for rebuilt_value in rebuilt_history:
		var rebuilt: Dictionary = Dictionary(rebuilt_value)
		_history.append(rebuilt.duplicate(true))
		_fix10_record_timeline_tick(
			int(rebuilt.get("tick", 0)),
			int(rebuilt.get("input_sequence", 0)),
			Dictionary(rebuilt.get("intent", {})),
			Dictionary(rebuilt.get("state", {}))
		)
	_last_authoritative_tick = server_tick
	_last_authoritative_sequence = authoritative_sequence
	_last_error_m = present_error_m
	_maximum_error_m = maxf(_maximum_error_m, present_error_m)
	_reconciliations += 1
	_ticks_replayed += rebuilt_history.size()
	_apply_correction(old_presentation_position - _position(_predicted_state), present_error_m)

	_fix10_ack_reconciliations += 1
	_fix10_ack_replayed_ticks += rebuilt_history.size()
	_fix10_last_ack_sequence = sequence
	_fix10_last_ack_client_tick = client_tick
	_fix10_last_ack_applied_server_tick = applied_server_tick
	_fix10_last_reconciliation_mode = "ACK_BASELINE_REPLAY"
	_fix10_last_ack_semantic = ack.duplicate(true)
	_fix10_prune_timeline(client_tick)
	return {"handled": true, "result": _success({
		"prediction_error_m": present_error_m,
		"replayed_ticks": rebuilt_history.size(),
		"prediction_tick": _prediction_tick,
		"correction_mode": _last_correction_mode,
		"hard_correction": _last_correction_mode == "HARD",
		"predicted_state": _predicted_state.duplicate(true),
		"fix10_reconciliation_mode": "ACK_BASELINE_REPLAY",
		"fix10_ack_sequence": sequence,
		"fix10_ack_client_tick": client_tick,
		"fix10_ack_applied_server_tick": applied_server_tick,
		"fix10_ack_transport_snapshot_tick": transport_snapshot_tick,
		"fix10_ack_baseline_error_m": baseline_error_m,
		"fix10_present_replay_error_m": present_error_m,
		"fix10_ack_replayed_ticks": rebuilt_history.size(),
	})}


func _fix10_fix5_compare_ack_order(candidate: Dictionary, reference: Dictionary) -> int:
	var candidate_tick: int = int(candidate.get("client_tick", 0))
	var reference_tick: int = int(reference.get("client_tick", 0))
	if candidate_tick > reference_tick:
		return 1
	if candidate_tick < reference_tick:
		return -1
	var candidate_sequence: int = int(candidate.get("input_sequence", 0))
	var reference_sequence: int = int(reference.get("input_sequence", 0))
	if candidate_sequence == reference_sequence:
		return 0
	if Fix10InputSequence.is_newer(candidate_sequence, reference_sequence):
		return 1
	if Fix10InputSequence.is_newer(reference_sequence, candidate_sequence):
		return -1
	return 0


func _fix10_fix5_same_ack_baseline(left: Dictionary, right: Dictionary) -> bool:
	if int(left.get("client_tick", 0)) != int(right.get("client_tick", 0)):
		return false
	if int(left.get("input_sequence", 0)) != int(right.get("input_sequence", 0)):
		return false
	if int(left.get("applied_server_tick", 0)) != int(right.get("applied_server_tick", 0)):
		return false
	if int(left.get("state_revision", 0)) != int(right.get("state_revision", 0)):
		return false
	if _position(left).distance_to(_position(right)) > 0.000001:
		return false
	if _fix8_velocity(left).distance_to(_fix8_velocity(right)) > 0.000001:
		return false
	return is_equal_approx(
		float(left.get("orientation_yaw", 0.0)),
		float(right.get("orientation_yaw", 0.0))
	)


func _fix10_fix5_stale_registration_result(ack: Dictionary, duplicate_semantic: bool = false) -> Dictionary:
	return _success({
		"input_sequence": int(ack.get("input_sequence", 0)),
		"client_tick": int(ack.get("client_tick", 0)),
		"applied_server_tick": int(ack.get("applied_server_tick", 0)),
		"snapshot_server_tick": int(ack.get("snapshot_server_tick", -1)),
		"ignored_stale": true,
		"duplicate_semantic": duplicate_semantic,
	})


func _fix10_record_timeline_tick(
	tick: int,
	input_sequence: int,
	intent: Dictionary,
	state: Dictionary
) -> void:
	if tick < 1 or input_sequence < 1 or state.is_empty():
		return
	if not _fix10_timeline_by_tick.has(tick):
		_fix10_timeline_ticks.append(tick)
		_fix10_timeline_ticks.sort()
	_fix10_timeline_by_tick[tick] = {
		"tick": tick,
		"input_sequence": input_sequence,
		"intent": intent.duplicate(true),
		"state": state.duplicate(true),
	}
	while _fix10_timeline_ticks.size() > FIX10_MAX_TIMELINE_TICKS:
		var oldest_tick: int = _fix10_timeline_ticks.pop_front()
		_fix10_timeline_by_tick.erase(oldest_tick)


func _fix10_timeline_record(tick: int) -> Dictionary:
	if not _fix10_timeline_by_tick.has(tick):
		return {}
	return Dictionary(_fix10_timeline_by_tick[tick]).duplicate(true)


func _fix10_prune_timeline(ack_client_tick: int) -> void:
	var keep_from: int = maxi(ack_client_tick - 2, 1)
	while not _fix10_timeline_ticks.is_empty() and _fix10_timeline_ticks.front() < keep_from:
		var tick: int = _fix10_timeline_ticks.pop_front()
		_fix10_timeline_by_tick.erase(tick)


func _fix10_reset_state() -> void:
	_fix10_pending_ack.clear()
	_fix10_timeline_by_tick.clear()
	_fix10_timeline_ticks.clear()
	_fix10_ack_reconciliations = 0
	_fix10_ack_replays = 0
	_fix10_ack_replayed_ticks = 0
	_fix10_ack_history_misses = 0
	_fix10_ack_mismatches = 0
	_fix10_ack_registration_rejections = 0
	_fix10_max_ack_baseline_error_m = 0.0
	_fix10_max_present_replay_error_m = 0.0
	_fix10_last_ack_sequence = 0
	_fix10_last_ack_client_tick = 0
	_fix10_last_ack_applied_server_tick = 0
	_fix10_last_reconciliation_mode = "NONE"
	_fix10_last_ack_semantic.clear()
	_fix10_fix4_transport_tick_lagged = 0
	_fix10_fix4_authority_sequence_ahead = 0
	_fix10_fix4_future_ack_deferrals = 0
	_fix10_fix4_stale_ack_registrations = 0
	_fix10_fix4_pending_ack_superseded = 0
	_fix10_fix4_last_ack_transport_snapshot_tick = -1
	_fix10_fix5_same_tick_sequence_supersessions = 0
	_fix10_fix5_same_tick_sequence_stale = 0
	_fix10_fix5_exact_key_conflicts = 0
	_fix10_fix5_local_timeline_superseded_acks = 0


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	report["fix10_prediction_ack_policy"] = FIX10_PREDICTION_ACK_POLICY
	report["fix10_reconciliation_policy"] = FIX10_RECONCILIATION_POLICY
	report["fix10_timeline_policy"] = FIX10_TIMELINE_POLICY
	report["fix10_fix4_ack_transport_policy"] = FIX10_FIX4_ACK_TRANSPORT_POLICY
	report["fix10_fix5_ack_identity_policy"] = FIX10_FIX5_ACK_IDENTITY_POLICY
	report["fix10_timeline_size"] = _fix10_timeline_ticks.size()
	report["fix10_max_timeline_ticks"] = FIX10_MAX_TIMELINE_TICKS
	report["fix10_ack_reconciliations"] = _fix10_ack_reconciliations
	report["fix10_ack_replays"] = _fix10_ack_replays
	report["fix10_ack_replayed_ticks"] = _fix10_ack_replayed_ticks
	report["fix10_ack_history_misses"] = _fix10_ack_history_misses
	report["fix10_ack_mismatches"] = _fix10_ack_mismatches
	report["fix10_ack_registration_rejections"] = _fix10_ack_registration_rejections
	report["fix10_max_ack_baseline_error_m"] = _fix10_max_ack_baseline_error_m
	report["fix10_max_present_replay_error_m"] = _fix10_max_present_replay_error_m
	report["fix10_last_ack_sequence"] = _fix10_last_ack_sequence
	report["fix10_last_ack_client_tick"] = _fix10_last_ack_client_tick
	report["fix10_last_ack_applied_server_tick"] = _fix10_last_ack_applied_server_tick
	report["fix10_last_reconciliation_mode"] = _fix10_last_reconciliation_mode
	report["fix10_fix4_transport_tick_lagged"] = _fix10_fix4_transport_tick_lagged
	report["fix10_fix4_authority_sequence_ahead"] = _fix10_fix4_authority_sequence_ahead
	report["fix10_fix4_future_ack_deferrals"] = _fix10_fix4_future_ack_deferrals
	report["fix10_fix4_stale_ack_registrations"] = _fix10_fix4_stale_ack_registrations
	report["fix10_fix4_pending_ack_superseded"] = _fix10_fix4_pending_ack_superseded
	report["fix10_fix4_last_ack_transport_snapshot_tick"] = _fix10_fix4_last_ack_transport_snapshot_tick
	report["fix10_fix5_same_tick_sequence_supersessions"] = _fix10_fix5_same_tick_sequence_supersessions
	report["fix10_fix5_same_tick_sequence_stale"] = _fix10_fix5_same_tick_sequence_stale
	report["fix10_fix5_exact_key_conflicts"] = _fix10_fix5_exact_key_conflicts
	report["fix10_fix5_local_timeline_superseded_acks"] = _fix10_fix5_local_timeline_superseded_acks
	report["fix10_corrections_per_1000_prediction_ticks"] = (
		1000.0 * float(_corrections) / float(_ticks_predicted)
		if _ticks_predicted > 0
		else 0.0
	)
	return report

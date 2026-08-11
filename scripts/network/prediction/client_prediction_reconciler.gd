extends "res://scripts/network/prediction/client_prediction_reconciler_fix10_fix6_core.gd"

# FIX10 fix8 owner-presentation reconciliation guard.
#
# FIX7b restored arrival-paced authority input. Client and server fixed clocks are
# therefore intentionally not a playout-locked phase pair: the same deterministic
# input transition can be applied a few ticks apart while still being semantically
# identical. Rewinding/replaying the already-correct local prediction for every
# 20 Hz ACK wastes several milliseconds on the render thread and small phase-only
# offsets become visible first-person correction springs.
#
# This leaf keeps FIX6 transition diagnostics and every FIX5 stale/future/authority
# preflight, but adds two conservative confirmation paths before rewind/replay:
# 1) exact authoritative post-input baseline == local transition baseline;
# 2) grounded constant-velocity phase translation exactly explains the position
#    offset while transition/velocity/orientation deltas remain identical.
# Anything else keeps the existing authoritative fallback/replay unchanged.
#
# Accepted source-contract anchors retained on the canonical path:
# res://scripts/network/prediction/client_prediction_reconciler_fix8.gd
# ACK_BASELINE_REPLAY_LOCAL_TIMELINE_V1
# BOUNDED_CLIENT_TICK_INPUT_TIMELINE_V1
# SEMANTIC_ACK_BASELINE_DECOUPLED_FROM_TRANSPORT_SNAPSHOT_V1
# CLIENT_TICK_AND_WRAP_AWARE_INPUT_SEQUENCE_V1
# SEQUENCE_MATCHED_FUTURE_TICK_PREALIGN_V1
# authoritative_sequence == _current_sequence
# FIX8_MAX_FUTURE_ALIGNMENT_TICKS
# FIX8_MAX_VISUAL_OFFSET_M
# FIX8_MAX_VISUAL_CORRECTION_SPEED_MPS

const FIX10_FIX8_OWNER_CONFIRM_POLICY: String = \
	"EXACT_OR_EXPLAINED_PHASE_ACK_CONFIRM_WITHOUT_PRESENT_REPLAY_V1"
const FIX10_FIX8_KINEMATIC_EPSILON: float = 0.00001
const FIX10_FIX8_PHASE_TRANSLATION_EPSILON_M: float = 0.002
const FIX10_FIX8_MAX_PHASE_EQUIVALENT_HOLD_DELTA_TICKS: int = 4

var _fix10_fix8_exact_ack_confirmations: int = 0
var _fix10_fix8_phase_equivalent_ack_confirmations: int = 0
var _fix10_fix8_fast_confirm_rejections: int = 0
var _fix10_fix8_replay_ticks_avoided: int = 0


func configure(authoritative_player: Dictionary, server_tick: int) -> Dictionary:
	_fix10_fix8_exact_ack_confirmations = 0
	_fix10_fix8_phase_equivalent_ack_confirmations = 0
	_fix10_fix8_fast_confirm_rejections = 0
	_fix10_fix8_replay_ticks_avoided = 0
	return super.configure(authoritative_player, server_tick)


func _fix10_reconcile_from_ack(
	authoritative_player: Dictionary,
	server_tick: int,
	ack: Dictionary
) -> Dictionary:
	if String(ack.get("semantic_transition_policy", "")) != FIX10_FIX6_TRANSITION_POLICY:
		return super._fix10_reconcile_from_ack(authoritative_player, server_tick, ack)

	var diagnostics: Dictionary = _fix10_fix6_transition_diagnostics(ack)
	_fix10_fix6_last_transition_diagnostics = diagnostics.duplicate(true)
	var fast_confirm: Dictionary = _fix10_fix8_try_confirm_without_replay(
		authoritative_player,
		server_tick,
		ack,
		diagnostics
	)
	if bool(fast_confirm.get("handled", false)):
		return fast_confirm

	var needs_authority_fallback: bool = (
		not bool(diagnostics.get("local_transition_available", false))
		or bool(diagnostics.get("phase_mismatch", false))
	)
	if needs_authority_fallback:
		var preflight: Dictionary = _fix10_fix6_authority_fallback_preflight(
			authoritative_player,
			server_tick,
			ack
		)
		if bool(preflight.get("stop", false)):
			return Dictionary(preflight.get("attempt", {"handled": false}))
	return super._fix10_reconcile_from_ack(authoritative_player, server_tick, ack)


func _fix10_fix8_try_confirm_without_replay(
	authoritative_player: Dictionary,
	server_tick: int,
	ack: Dictionary,
	diagnostics: Dictionary
) -> Dictionary:
	if not _fix10_fix8_fast_confirm_preflight(authoritative_player, server_tick, ack):
		_fix10_fix8_fast_confirm_rejections += 1
		return {"handled": false}
	if not bool(diagnostics.get("local_transition_available", false)):
		_fix10_fix8_fast_confirm_rejections += 1
		return {"handled": false}

	var sequence: int = int(ack.get("input_sequence", 0))
	var client_tick: int = int(ack.get("client_tick", 0))
	var transition: Dictionary = _fix10_fix6_find_transition_record(sequence)
	if transition.is_empty() or int(transition.get("tick", 0)) != client_tick:
		_fix10_fix8_fast_confirm_rejections += 1
		return {"handled": false}
	var local_pre: Dictionary = Dictionary(transition.get("pre_state", {}))
	var local_post: Dictionary = Dictionary(transition.get("state", {}))
	if local_pre.is_empty() or local_post.is_empty():
		_fix10_fix8_fast_confirm_rejections += 1
		return {"handled": false}

	var server_pre: Dictionary = {
		"position": Dictionary(ack.get("pre_position", {})).duplicate(true),
		"velocity": Dictionary(ack.get("pre_velocity", {})).duplicate(true),
		"orientation_yaw": float(ack.get("pre_orientation_yaw", 0.0)),
	}
	var server_post: Dictionary = {
		"position": Dictionary(ack.get("position", {})).duplicate(true),
		"velocity": Dictionary(ack.get("velocity", {})).duplicate(true),
		"orientation_yaw": float(ack.get("orientation_yaw", 0.0)),
	}

	if _fix10_fix8_states_match(local_post, server_post):
		_fix10_fix8_exact_ack_confirmations += 1
		return _fix10_fix8_confirm_ack(
			authoritative_player,
			server_tick,
			ack,
			diagnostics,
			"ACK_EXACT_BASELINE_CONFIRM_NO_REPLAY"
		)

	if _fix10_fix8_phase_translation_matches(local_pre, local_post, server_pre, server_post, diagnostics):
		_fix10_fix8_phase_equivalent_ack_confirmations += 1
		return _fix10_fix8_confirm_ack(
			authoritative_player,
			server_tick,
			ack,
			diagnostics,
			"ACK_PHASE_EQUIVALENT_CONFIRM_NO_REPLAY"
		)

	_fix10_fix8_fast_confirm_rejections += 1
	return {"handled": false}


func _fix10_fix8_fast_confirm_preflight(
	authoritative_player: Dictionary,
	server_tick: int,
	ack: Dictionary
) -> bool:
	if not _configured or not _valid_player_state(authoritative_player):
		return false
	if server_tick < _last_authoritative_tick:
		return false
	var transport_snapshot_tick: int = int(ack.get("snapshot_server_tick", -1))
	if transport_snapshot_tick > server_tick:
		return false
	var sequence: int = int(ack.get("input_sequence", 0))
	var authoritative_sequence: int = int(authoritative_player.get("last_input_sequence", 0))
	if not Fix10InputSequence.is_valid(sequence):
		return false
	if sequence != authoritative_sequence:
		if Fix10InputSequence.is_newer(sequence, authoritative_sequence):
			return false
		if not Fix10InputSequence.is_newer(authoritative_sequence, sequence):
			return false
	if int(ack.get("client_tick", 0)) > _prediction_tick:
		return false
	return true


func _fix10_fix8_states_match(local_state: Dictionary, server_state: Dictionary) -> bool:
	return (
		_position(local_state).distance_to(_position(server_state)) <= FIX10_FIX8_KINEMATIC_EPSILON
		and _fix8_velocity(local_state).distance_to(_fix8_velocity(server_state)) <= FIX10_FIX8_KINEMATIC_EPSILON
		and _fix10_fix8_angle_distance(
			float(local_state.get("orientation_yaw", 0.0)),
			float(server_state.get("orientation_yaw", 0.0))
		) <= FIX10_FIX8_KINEMATIC_EPSILON
	)


func _fix10_fix8_phase_translation_matches(
	local_pre: Dictionary,
	local_post: Dictionary,
	server_pre: Dictionary,
	server_post: Dictionary,
	diagnostics: Dictionary
) -> bool:
	if not bool(diagnostics.get("phase_mismatch", false)):
		return false
	if bool(diagnostics.get("previous_sequence_mismatch", false)):
		return false
	if bool(diagnostics.get("declared_tick_mismatch", false)):
		return false
	var hold_delta_ticks: int = int(diagnostics.get("hold_delta_ticks", 0))
	if hold_delta_ticks == 0 or absi(hold_delta_ticks) > FIX10_FIX8_MAX_PHASE_EQUIVALENT_HOLD_DELTA_TICKS:
		return false
	if float(diagnostics.get("transition_delta_error_m", INF)) > FIX10_FIX8_KINEMATIC_EPSILON:
		return false
	if float(diagnostics.get("velocity_delta_error_m", INF)) > FIX10_FIX8_KINEMATIC_EPSILON:
		return false
	var local_pre_velocity: Vector3 = _fix8_velocity(local_pre)
	var server_pre_velocity: Vector3 = _fix8_velocity(server_pre)
	# Do not normalize airborne/jump phase by a constant-velocity shortcut. Gravity
	# makes those trajectories non-linear; they keep the full authority path.
	if absf(local_pre_velocity.y) > FIX10_FIX8_KINEMATIC_EPSILON or absf(server_pre_velocity.y) > FIX10_FIX8_KINEMATIC_EPSILON:
		return false
	if local_pre_velocity.distance_to(server_pre_velocity) > FIX10_FIX8_KINEMATIC_EPSILON:
		return false
	if _fix10_fix8_angle_distance(
		float(local_pre.get("orientation_yaw", 0.0)),
		float(server_pre.get("orientation_yaw", 0.0))
	) > FIX10_FIX8_KINEMATIC_EPSILON:
		return false
	if _fix10_fix8_angle_distance(
		float(local_post.get("orientation_yaw", 0.0)),
		float(server_post.get("orientation_yaw", 0.0))
	) > FIX10_FIX8_KINEMATIC_EPSILON:
		return false

	var pre_offset: Vector3 = _position(server_pre) - _position(local_pre)
	var post_offset: Vector3 = _position(server_post) - _position(local_post)
	if pre_offset.distance_to(post_offset) > FIX10_FIX8_PHASE_TRANSLATION_EPSILON_M:
		return false
	var expected_offset: Vector3 = (
		local_pre_velocity
		* float(hold_delta_ticks)
		* FIXED_DELTA_SECONDS
	)
	return pre_offset.distance_to(expected_offset) <= FIX10_FIX8_PHASE_TRANSLATION_EPSILON_M


func _fix10_fix8_confirm_ack(
	authoritative_player: Dictionary,
	server_tick: int,
	ack: Dictionary,
	diagnostics: Dictionary,
	mode: String
) -> Dictionary:
	var sequence: int = int(ack.get("input_sequence", 0))
	var client_tick: int = int(ack.get("client_tick", 0))
	var authoritative_sequence: int = int(authoritative_player.get("last_input_sequence", 0))
	var avoided_ticks: int = maxi(_prediction_tick - client_tick, 0)
	_fix10_fix8_replay_ticks_avoided += avoided_ticks
	_last_authoritative_tick = server_tick
	_last_authoritative_sequence = authoritative_sequence
	_last_error_m = 0.0
	_last_correction_mode = "NONE"
	_reconciliations += 1
	_fix10_ack_reconciliations += 1
	_fix10_last_ack_sequence = sequence
	_fix10_last_ack_client_tick = client_tick
	_fix10_last_ack_applied_server_tick = int(ack.get("applied_server_tick", 0))
	_fix10_last_reconciliation_mode = mode
	_fix10_last_ack_semantic = ack.duplicate(true)
	_fix10_fix6_last_ack_phase_mismatch = false
	if mode == "ACK_EXACT_BASELINE_CONFIRM_NO_REPLAY" and not bool(diagnostics.get("phase_mismatch", false)):
		_fix10_fix6_phase_matched_ack_reconciliations += 1
	_fix10_prune_timeline(client_tick)

	var details: Dictionary = {
		"prediction_error_m": 0.0,
		"replayed_ticks": 0,
		"prediction_tick": _prediction_tick,
		"correction_mode": "NONE",
		"hard_correction": false,
		"predicted_state": _predicted_state.duplicate(true),
		"fix10_reconciliation_mode": mode,
		"fix10_ack_sequence": sequence,
		"fix10_ack_client_tick": client_tick,
		"fix10_ack_applied_server_tick": _fix10_last_ack_applied_server_tick,
		"fix10_ack_transport_snapshot_tick": int(ack.get("snapshot_server_tick", -1)),
		"fix10_fix8_replay_ticks_avoided": avoided_ticks,
	}
	_fix10_fix6_merge_diagnostics(details, diagnostics)
	return {"handled": true, "result": _success(details)}


func _fix10_fix8_angle_distance(left: float, right: float) -> float:
	return absf(wrapf(left - right, -PI, PI))


func _fix10_fix6_authority_fallback_preflight(
	authoritative_player: Dictionary,
	server_tick: int,
	ack: Dictionary
) -> Dictionary:
	if not _configured or not _valid_player_state(authoritative_player):
		return {"stop": true, "attempt": {"handled": false}}
	if server_tick < _last_authoritative_tick:
		_fix10_ack_replays += 1
		return {"stop": true, "attempt": {"handled": false}}

	var transport_snapshot_tick: int = int(ack.get("snapshot_server_tick", -1))
	if transport_snapshot_tick > server_tick:
		_fix10_fix4_future_ack_deferrals += 1
		return {"stop": true, "attempt": {"handled": false, "defer": true}}
	if transport_snapshot_tick < server_tick:
		_fix10_fix4_transport_tick_lagged += 1
	_fix10_fix4_last_ack_transport_snapshot_tick = transport_snapshot_tick

	var sequence: int = int(ack.get("input_sequence", 0))
	var authoritative_sequence: int = int(authoritative_player.get("last_input_sequence", 0))
	if sequence != authoritative_sequence:
		if Fix10InputSequence.is_newer(sequence, authoritative_sequence):
			_fix10_ack_mismatches += 1
			return {"stop": true, "attempt": {"handled": false}}
		if Fix10InputSequence.is_newer(authoritative_sequence, sequence):
			_fix10_fix4_authority_sequence_ahead += 1
		else:
			_fix10_ack_mismatches += 1
			return {"stop": true, "attempt": {"handled": false}}
	if int(ack.get("client_tick", 0)) > _prediction_tick:
		_fix10_ack_history_misses += 1
		return {"stop": true, "attempt": {"handled": false}}
	return {"stop": false}


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	report["fix10_fix8_owner_confirm_policy"] = FIX10_FIX8_OWNER_CONFIRM_POLICY
	report["fix10_fix8_exact_ack_confirmations"] = _fix10_fix8_exact_ack_confirmations
	report["fix10_fix8_phase_equivalent_ack_confirmations"] = \
		_fix10_fix8_phase_equivalent_ack_confirmations
	report["fix10_fix8_fast_confirm_rejections"] = _fix10_fix8_fast_confirm_rejections
	report["fix10_fix8_replay_ticks_avoided"] = _fix10_fix8_replay_ticks_avoided
	return report

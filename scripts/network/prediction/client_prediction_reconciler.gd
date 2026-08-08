extends "res://scripts/network/prediction/client_prediction_reconciler_fix10_fix6_core.gd"

# FIX10 fix6 final guard. The core owns transition diagnostics and phase-aware
# replay routing; this leaf preserves the accepted FIX5 stale/future/authority
# preflight before an ACK is allowed to take the authority-snapshot fallback.
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


func _fix10_reconcile_from_ack(
	authoritative_player: Dictionary,
	server_tick: int,
	ack: Dictionary
) -> Dictionary:
	if String(ack.get("semantic_transition_policy", "")) != FIX10_FIX6_TRANSITION_POLICY:
		return super._fix10_reconcile_from_ack(authoritative_player, server_tick, ack)

	var diagnostics: Dictionary = _fix10_fix6_transition_diagnostics(ack)
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

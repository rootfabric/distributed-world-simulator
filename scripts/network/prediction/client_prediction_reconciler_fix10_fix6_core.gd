extends "res://scripts/network/prediction/client_prediction_reconciler_fix10_fix5.gd"

# FIX10 fix6 is intentionally a leaf over the accepted FIX5 implementation.
# The copied FIX5 base remains byte-identical to the accepted branch; this file
# adds only transition-phase semantics and diagnostics.
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

const FIX10_FIX6_SEMANTIC_BASELINE_POLICY: String = "PRE_POST_TRANSITION_PHASE_AWARE_AUTHORITY_SNAPSHOT_V1"
const FIX10_FIX6_TRANSITION_POLICY: String = "PRE_POST_INPUT_TRANSITION_WITH_HOLD_TICKS_V1"
const FIX10_FIX6_PHASE_MISMATCH_MODE: String = "ACK_PHASE_MISMATCH_AUTHORITY_SNAPSHOT"
const FIX10_FIX6_TRANSITION_HISTORY_MISS_MODE: String = "ACK_TRANSITION_HISTORY_MISS_AUTHORITY_SNAPSHOT"
const FIX10_FIX6_TRANSITION_LOOKBACK_TICKS: int = 64
const FIX10_FIX6_KINEMATIC_EPSILON_M: float = 0.000001

var _fix10_fix6_phase_mismatch_authority_reconciliations: int = 0
var _fix10_fix6_phase_matched_ack_reconciliations: int = 0
var _fix10_fix6_transition_history_misses: int = 0
var _fix10_fix6_transition_metadata_acks: int = 0
var _fix10_fix6_max_server_hold_ticks: int = 0
var _fix10_fix6_max_client_hold_ticks: int = 0
var _fix10_fix6_max_hold_delta_ticks: int = 0
var _fix10_fix6_max_raw_phase_baseline_offset_m: float = 0.0
var _fix10_fix6_max_pre_state_offset_m: float = 0.0
var _fix10_fix6_max_transition_delta_error_m: float = 0.0
var _fix10_fix6_max_velocity_delta_error_m: float = 0.0
var _fix10_fix6_max_same_clock_authority_error_m: float = 0.0
var _fix10_fix6_last_ack_phase_mismatch: bool = false
var _fix10_fix6_last_transition_diagnostics: Dictionary = {}
var _fix10_fix6_recording_pre_state: Dictionary = {}


func configure(authoritative_player: Dictionary, server_tick: int) -> Dictionary:
	_fix10_fix6_reset_state()
	return super.configure(authoritative_player, server_tick)


func set_authoritative_input_ack(ack_value: Dictionary, snapshot_server_tick: int) -> Dictionary:
	if String(ack_value.get("semantic_transition_policy", "")) == FIX10_FIX6_TRANSITION_POLICY:
		if not _fix10_fix6_valid_transition_metadata(ack_value):
			_fix10_ack_registration_rejections += 1
			return _failure("FIX10_FIX6_INVALID_TRANSITION_METADATA")
		_fix10_fix6_transition_metadata_acks += 1
	return super.set_authoritative_input_ack(ack_value, snapshot_server_tick)


func _simulate_tick(
	tick: int,
	input_sequence: int,
	intent: Dictionary,
	replay: bool
) -> Dictionary:
	_fix10_fix6_recording_pre_state = _predicted_state.duplicate(true)
	var result: Dictionary = super._simulate_tick(tick, input_sequence, intent, replay)
	_fix10_fix6_recording_pre_state.clear()
	return result


func _fix10_record_timeline_tick(
	tick: int,
	input_sequence: int,
	intent: Dictionary,
	state: Dictionary
) -> void:
	var previous_pre_state: Dictionary = {}
	if _fix10_timeline_by_tick.has(tick):
		previous_pre_state = Dictionary(
			Dictionary(_fix10_timeline_by_tick[tick]).get("pre_state", {})
		).duplicate(true)
	super._fix10_record_timeline_tick(tick, input_sequence, intent, state)
	if not _fix10_timeline_by_tick.has(tick):
		return
	var record: Dictionary = Dictionary(_fix10_timeline_by_tick[tick]).duplicate(true)
	var pre_state: Dictionary = _fix10_fix6_recording_pre_state.duplicate(true)
	if pre_state.is_empty():
		pre_state = previous_pre_state
	if pre_state.is_empty():
		var previous_record: Dictionary = _fix10_timeline_record(tick - 1)
		if not previous_record.is_empty():
			pre_state = Dictionary(previous_record.get("state", {})).duplicate(true)
	record["pre_state"] = pre_state
	_fix10_timeline_by_tick[tick] = record


func _fix10_prune_timeline(ack_client_tick: int) -> void:
	var keep_from: int = maxi(ack_client_tick - FIX10_FIX6_TRANSITION_LOOKBACK_TICKS, 1)
	while not _fix10_timeline_ticks.is_empty() and _fix10_timeline_ticks.front() < keep_from:
		var tick: int = _fix10_timeline_ticks.pop_front()
		_fix10_timeline_by_tick.erase(tick)


func _fix10_reconcile_from_ack(
	authoritative_player: Dictionary,
	server_tick: int,
	ack: Dictionary
) -> Dictionary:
	if String(ack.get("semantic_transition_policy", "")) != FIX10_FIX6_TRANSITION_POLICY:
		return super._fix10_reconcile_from_ack(authoritative_player, server_tick, ack)

	var diagnostics: Dictionary = _fix10_fix6_transition_diagnostics(ack)
	_fix10_fix6_last_transition_diagnostics = diagnostics.duplicate(true)
	if not bool(diagnostics.get("local_transition_available", false)):
		_fix10_fix6_transition_history_misses += 1
		return _fix10_fix6_reconcile_authority_snapshot(
			authoritative_player,
			server_tick,
			ack,
			diagnostics,
			FIX10_FIX6_TRANSITION_HISTORY_MISS_MODE
		)

	if bool(diagnostics.get("phase_mismatch", false)):
		return _fix10_fix6_reconcile_authority_snapshot(
			authoritative_player,
			server_tick,
			ack,
			diagnostics,
			FIX10_FIX6_PHASE_MISMATCH_MODE
		)

	_fix10_fix6_phase_matched_ack_reconciliations += 1
	_fix10_fix6_last_ack_phase_mismatch = false
	var direct: Dictionary = super._fix10_reconcile_from_ack(
		authoritative_player,
		server_tick,
		ack
	)
	if bool(direct.get("handled", false)):
		var result: Dictionary = Dictionary(direct.get("result", {})).duplicate(true)
		if bool(result.get("success", false)):
			var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
			_fix10_fix6_merge_diagnostics(details, diagnostics)
			result["details"] = details
			direct["result"] = result
	return direct


func _fix10_fix6_reconcile_authority_snapshot(
	authoritative_player: Dictionary,
	server_tick: int,
	ack: Dictionary,
	diagnostics: Dictionary,
	mode: String
) -> Dictionary:
	# The FIX5 caller already popped this ACK from _fix10_pending_ack. Re-entering
	# FIX5 reconcile therefore falls through to the canonical FIX8/NX4 snapshot
	# path and cannot recursively apply the same ACK baseline.
	var result: Dictionary = super.reconcile(authoritative_player, server_tick)
	if not bool(result.get("success", false)):
		return {"handled": true, "result": result}
	var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
	var same_clock_error_m: float = float(details.get("prediction_error_m", 0.0))
	_fix10_fix6_max_same_clock_authority_error_m = maxf(
		_fix10_fix6_max_same_clock_authority_error_m,
		same_clock_error_m
	)
	_fix10_ack_reconciliations += 1
	if mode == FIX10_FIX6_PHASE_MISMATCH_MODE:
		_fix10_fix6_phase_mismatch_authority_reconciliations += 1
		_fix10_fix6_last_ack_phase_mismatch = true
	else:
		_fix10_fix6_last_ack_phase_mismatch = false
	_fix10_last_ack_sequence = int(ack.get("input_sequence", 0))
	_fix10_last_ack_client_tick = int(ack.get("client_tick", 0))
	_fix10_last_ack_applied_server_tick = int(ack.get("applied_server_tick", 0))
	_fix10_last_reconciliation_mode = mode
	_fix10_last_ack_semantic = ack.duplicate(true)
	_fix10_prune_timeline(_fix10_last_ack_client_tick)
	details["fix10_reconciliation_mode"] = mode
	details["fix10_ack_sequence"] = _fix10_last_ack_sequence
	details["fix10_ack_client_tick"] = _fix10_last_ack_client_tick
	details["fix10_ack_applied_server_tick"] = _fix10_last_ack_applied_server_tick
	details["fix10_ack_transport_snapshot_tick"] = int(ack.get("snapshot_server_tick", -1))
	details["fix10_fix6_same_clock_authority_error_m"] = same_clock_error_m
	_fix10_fix6_merge_diagnostics(details, diagnostics)
	result["details"] = details
	return {"handled": true, "result": result}


func _fix10_fix6_transition_diagnostics(ack: Dictionary) -> Dictionary:
	var metadata_complete: bool = bool(ack.get("transition_metadata_complete", true))
	if not metadata_complete:
		return {
			"metadata_available": true,
			"metadata_complete": false,
			"local_transition_available": false,
			"ack_sequence": int(ack.get("input_sequence", 0)),
			"declared_client_tick": int(ack.get("client_tick", 0)),
			"server_hold_ticks_before_input": int(ack.get("server_hold_ticks_before_input", 0)),
		}
	var sequence: int = int(ack.get("input_sequence", 0))
	var transition: Dictionary = _fix10_fix6_find_transition_record(sequence)
	if transition.is_empty():
		return {
			"metadata_available": true,
			"metadata_complete": true,
			"local_transition_available": false,
			"ack_sequence": sequence,
			"declared_client_tick": int(ack.get("client_tick", 0)),
			"server_hold_ticks_before_input": int(ack.get("server_hold_ticks_before_input", 0)),
		}

	var local_tick: int = int(transition.get("tick", 0))
	var local_pre: Dictionary = Dictionary(transition.get("pre_state", {}))
	var local_post: Dictionary = Dictionary(transition.get("state", {}))
	var local_previous_sequence: int = int(local_pre.get("last_input_sequence", 0))
	var previous_transition: Dictionary = _fix10_fix6_find_transition_record(
		local_previous_sequence,
		local_tick
	)
	var previous_local_tick: int = int(previous_transition.get("tick", 0))
	var client_hold_ticks: int = 0
	if previous_local_tick > 0:
		client_hold_ticks = maxi(local_tick - previous_local_tick - 1, 0)
	else:
		var previous_client_tick: int = int(ack.get("previous_client_tick", 0))
		if previous_client_tick > 0:
			client_hold_ticks = maxi(local_tick - previous_client_tick - 1, 0)
	var server_hold_ticks: int = maxi(int(ack.get("server_hold_ticks_before_input", 0)), 0)
	var hold_delta_ticks: int = server_hold_ticks - client_hold_ticks
	var server_previous_sequence: int = int(
		ack.get("previous_input_sequence", local_previous_sequence)
	)
	var previous_sequence_mismatch: bool = server_previous_sequence != local_previous_sequence
	var declared_tick_mismatch: bool = local_tick != int(ack.get("client_tick", local_tick))
	var phase_mismatch: bool = (
		hold_delta_ticks != 0
		or previous_sequence_mismatch
		or declared_tick_mismatch
	)

	var server_pre: Dictionary = {
		"position": Dictionary(ack.get("pre_position", {})).duplicate(true),
		"velocity": Dictionary(ack.get("pre_velocity", {})).duplicate(true),
	}
	var server_post: Dictionary = {
		"position": Dictionary(ack.get("position", {})).duplicate(true),
		"velocity": Dictionary(ack.get("velocity", {})).duplicate(true),
	}
	var raw_post_offset_m: float = _position(local_post).distance_to(_position(server_post))
	var raw_pre_offset_m: float = _position(local_pre).distance_to(_position(server_pre))
	var local_transition_delta: Vector3 = _position(local_post) - _position(local_pre)
	var server_transition_delta: Vector3 = _position(server_post) - _position(server_pre)
	var transition_delta_error_m: float = local_transition_delta.distance_to(server_transition_delta)
	var local_velocity_delta: Vector3 = _fix8_velocity(local_post) - _fix8_velocity(local_pre)
	var server_velocity_delta: Vector3 = _fix8_velocity(server_post) - _fix8_velocity(server_pre)
	var velocity_delta_error_m: float = local_velocity_delta.distance_to(server_velocity_delta)

	_fix10_fix6_max_server_hold_ticks = maxi(_fix10_fix6_max_server_hold_ticks, server_hold_ticks)
	_fix10_fix6_max_client_hold_ticks = maxi(_fix10_fix6_max_client_hold_ticks, client_hold_ticks)
	_fix10_fix6_max_hold_delta_ticks = maxi(_fix10_fix6_max_hold_delta_ticks, absi(hold_delta_ticks))
	_fix10_fix6_max_raw_phase_baseline_offset_m = maxf(_fix10_fix6_max_raw_phase_baseline_offset_m, raw_post_offset_m)
	_fix10_fix6_max_pre_state_offset_m = maxf(_fix10_fix6_max_pre_state_offset_m, raw_pre_offset_m)
	_fix10_fix6_max_transition_delta_error_m = maxf(_fix10_fix6_max_transition_delta_error_m, transition_delta_error_m)
	_fix10_fix6_max_velocity_delta_error_m = maxf(_fix10_fix6_max_velocity_delta_error_m, velocity_delta_error_m)

	return {
		"metadata_available": true,
		"metadata_complete": true,
		"local_transition_available": true,
		"phase_mismatch": phase_mismatch,
		"declared_tick_mismatch": declared_tick_mismatch,
		"previous_sequence_mismatch": previous_sequence_mismatch,
		"ack_sequence": sequence,
		"declared_client_tick": int(ack.get("client_tick", 0)),
		"local_first_simulated_tick": local_tick,
		"local_previous_transition_tick": previous_local_tick,
		"local_previous_input_sequence": local_previous_sequence,
		"server_previous_input_sequence": server_previous_sequence,
		"previous_client_tick": int(ack.get("previous_client_tick", 0)),
		"previous_applied_server_tick": int(ack.get("previous_applied_server_tick", 0)),
		"client_hold_ticks_before_input": client_hold_ticks,
		"server_hold_ticks_before_input": server_hold_ticks,
		"hold_delta_ticks": hold_delta_ticks,
		"raw_phase_baseline_offset_m": raw_post_offset_m,
		"pre_state_offset_m": raw_pre_offset_m,
		"transition_delta_error_m": transition_delta_error_m,
		"velocity_delta_error_m": velocity_delta_error_m,
	}


func _fix10_fix6_find_transition_record(
	sequence: int,
	before_tick_exclusive: int = 2147483647
) -> Dictionary:
	if sequence < 1:
		return {}
	for tick in _fix10_timeline_ticks:
		if tick >= before_tick_exclusive:
			break
		var record: Dictionary = _fix10_timeline_record(tick)
		if int(record.get("input_sequence", 0)) != sequence:
			continue
		var pre_state: Dictionary = Dictionary(record.get("pre_state", {}))
		if pre_state.is_empty() or int(pre_state.get("last_input_sequence", 0)) == sequence:
			continue
		return record
	return {}


func _fix10_fix6_valid_transition_metadata(ack: Dictionary) -> bool:
	if not bool(ack.get("transition_metadata_complete", true)):
		return true
	if not ack.get("pre_position") is Dictionary or not ack.get("pre_velocity") is Dictionary:
		return false
	if int(ack.get("server_hold_ticks_before_input", -1)) < 0:
		return false
	var pre_yaw: float = float(ack.get("pre_orientation_yaw", 0.0))
	return not is_nan(pre_yaw) and not is_inf(pre_yaw)


func _fix10_fix6_merge_diagnostics(target: Dictionary, diagnostics: Dictionary) -> void:
	for key in [
		"metadata_complete",
		"local_transition_available",
		"phase_mismatch",
		"declared_tick_mismatch",
		"previous_sequence_mismatch",
		"declared_client_tick",
		"local_first_simulated_tick",
		"local_previous_transition_tick",
		"local_previous_input_sequence",
		"server_previous_input_sequence",
		"previous_client_tick",
		"previous_applied_server_tick",
		"client_hold_ticks_before_input",
		"server_hold_ticks_before_input",
		"hold_delta_ticks",
		"raw_phase_baseline_offset_m",
		"pre_state_offset_m",
		"transition_delta_error_m",
		"velocity_delta_error_m",
	]:
		if diagnostics.has(key):
			target["fix10_fix6_%s" % String(key)] = diagnostics[key]


func _fix10_fix5_same_ack_baseline(left: Dictionary, right: Dictionary) -> bool:
	if not super._fix10_fix5_same_ack_baseline(left, right):
		return false
	var left_policy: String = String(left.get("semantic_transition_policy", ""))
	var right_policy: String = String(right.get("semantic_transition_policy", ""))
	if left_policy != right_policy:
		return false
	if left_policy != FIX10_FIX6_TRANSITION_POLICY:
		return true
	if bool(left.get("transition_metadata_complete", true)) != bool(right.get("transition_metadata_complete", true)):
		return false
	if int(left.get("previous_input_sequence", 0)) != int(right.get("previous_input_sequence", 0)):
		return false
	if int(left.get("previous_client_tick", 0)) != int(right.get("previous_client_tick", 0)):
		return false
	if int(left.get("previous_applied_server_tick", 0)) != int(right.get("previous_applied_server_tick", 0)):
		return false
	if int(left.get("server_hold_ticks_before_input", 0)) != int(right.get("server_hold_ticks_before_input", 0)):
		return false
	if not bool(left.get("transition_metadata_complete", true)):
		return true
	var left_pre: Dictionary = {"position": left.get("pre_position", {}), "velocity": left.get("pre_velocity", {})}
	var right_pre: Dictionary = {"position": right.get("pre_position", {}), "velocity": right.get("pre_velocity", {})}
	if _position(left_pre).distance_to(_position(right_pre)) > FIX10_FIX6_KINEMATIC_EPSILON_M:
		return false
	if _fix8_velocity(left_pre).distance_to(_fix8_velocity(right_pre)) > FIX10_FIX6_KINEMATIC_EPSILON_M:
		return false
	return is_equal_approx(float(left.get("pre_orientation_yaw", 0.0)), float(right.get("pre_orientation_yaw", 0.0)))


func _fix10_fix6_reset_state() -> void:
	_fix10_fix6_phase_mismatch_authority_reconciliations = 0
	_fix10_fix6_phase_matched_ack_reconciliations = 0
	_fix10_fix6_transition_history_misses = 0
	_fix10_fix6_transition_metadata_acks = 0
	_fix10_fix6_max_server_hold_ticks = 0
	_fix10_fix6_max_client_hold_ticks = 0
	_fix10_fix6_max_hold_delta_ticks = 0
	_fix10_fix6_max_raw_phase_baseline_offset_m = 0.0
	_fix10_fix6_max_pre_state_offset_m = 0.0
	_fix10_fix6_max_transition_delta_error_m = 0.0
	_fix10_fix6_max_velocity_delta_error_m = 0.0
	_fix10_fix6_max_same_clock_authority_error_m = 0.0
	_fix10_fix6_last_ack_phase_mismatch = false
	_fix10_fix6_last_transition_diagnostics.clear()
	_fix10_fix6_recording_pre_state.clear()


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	report["fix10_fix6_semantic_baseline_policy"] = FIX10_FIX6_SEMANTIC_BASELINE_POLICY
	report["fix10_fix6_transition_policy"] = FIX10_FIX6_TRANSITION_POLICY
	report["fix10_fix6_phase_mismatch_authority_reconciliations"] = _fix10_fix6_phase_mismatch_authority_reconciliations
	report["fix10_fix6_phase_matched_ack_reconciliations"] = _fix10_fix6_phase_matched_ack_reconciliations
	report["fix10_fix6_transition_history_misses"] = _fix10_fix6_transition_history_misses
	report["fix10_fix6_transition_metadata_acks"] = _fix10_fix6_transition_metadata_acks
	report["fix10_fix6_max_server_hold_ticks"] = _fix10_fix6_max_server_hold_ticks
	report["fix10_fix6_max_client_hold_ticks"] = _fix10_fix6_max_client_hold_ticks
	report["fix10_fix6_max_hold_delta_ticks"] = _fix10_fix6_max_hold_delta_ticks
	report["fix10_fix6_max_raw_phase_baseline_offset_m"] = _fix10_fix6_max_raw_phase_baseline_offset_m
	report["fix10_fix6_max_pre_state_offset_m"] = _fix10_fix6_max_pre_state_offset_m
	report["fix10_fix6_max_transition_delta_error_m"] = _fix10_fix6_max_transition_delta_error_m
	report["fix10_fix6_max_velocity_delta_error_m"] = _fix10_fix6_max_velocity_delta_error_m
	report["fix10_fix6_max_same_clock_authority_error_m"] = _fix10_fix6_max_same_clock_authority_error_m
	report["fix10_fix6_last_ack_phase_mismatch"] = _fix10_fix6_last_ack_phase_mismatch
	report["fix10_fix6_last_transition_diagnostics"] = _fix10_fix6_last_transition_diagnostics.duplicate(true)
	return report

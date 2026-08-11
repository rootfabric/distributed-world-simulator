extends SceneTree

const Reconciler = preload("res://scripts/network/prediction/client_prediction_reconciler.gd")

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_exact_ack_confirms_without_replay()
	_test_grounded_phase_translation_confirms_without_spring()
	_test_real_divergence_still_rewinds_and_corrects()
	_test_source_contract()
	_finish()


func _test_exact_ack_confirms_without_replay() -> void:
	var fixture: Dictionary = _fixture()
	var reconciler = fixture["reconciler"]
	var pre: Dictionary = Dictionary(fixture["seq2_pre"]).duplicate(true)
	var post: Dictionary = Dictionary(fixture["seq2_post"]).duplicate(true)
	var authority_current: Dictionary = Dictionary(fixture["current"]).duplicate(true)
	var before: Dictionary = reconciler.get_predicted_state()
	var ticks_replayed_before: int = int(reconciler.get_report().get("ticks_replayed", 0))
	var ack: Dictionary = _ack(pre, post, 2, 103, 103, 1, 101, 101, 1)
	_assert(bool(reconciler.set_authoritative_input_ack(ack, 105).get("success", false)), "FIX10 fix8 exact ACK registers")
	var reconciled: Dictionary = reconciler.reconcile(authority_current, 105)
	_assert(bool(reconciled.get("success", false)), "FIX10 fix8 exact ACK reconciliation succeeds")
	var details: Dictionary = Dictionary(reconciled.get("details", {}))
	_assert(String(details.get("fix10_reconciliation_mode", "")) == "ACK_EXACT_BASELINE_CONFIRM_NO_REPLAY", "FIX10 fix8 exact baseline uses no-replay confirm")
	_assert(int(details.get("replayed_ticks", -1)) == 0, "FIX10 fix8 exact confirm replays zero ticks")
	_assert(String(details.get("correction_mode", "")) == "NONE", "FIX10 fix8 exact confirm creates no visual correction")
	_assert(_position(reconciler.get_predicted_state()).distance_to(_position(before)) < 0.000001, "FIX10 fix8 exact confirm preserves present prediction")
	var report: Dictionary = reconciler.get_report()
	_assert(int(report.get("ticks_replayed", 0)) == ticks_replayed_before, "FIX10 fix8 exact confirm does not mutate replay count")
	_assert(int(report.get("fix10_fix8_exact_ack_confirmations", 0)) == 1, "FIX10 fix8 exact confirmation counted")
	_assert(int(report.get("fix10_fix8_replay_ticks_avoided", 0)) >= 2, "FIX10 fix8 exact confirmation reports avoided replay")


func _test_grounded_phase_translation_confirms_without_spring() -> void:
	var fixture: Dictionary = _fixture()
	var reconciler = fixture["reconciler"]
	var local_pre: Dictionary = Dictionary(fixture["seq2_pre"]).duplicate(true)
	var local_post: Dictionary = Dictionary(fixture["seq2_post"]).duplicate(true)
	var current: Dictionary = Dictionary(fixture["current"]).duplicate(true)
	var previous_velocity: Vector3 = _velocity(local_pre)
	var phase_offset: Vector3 = previous_velocity * (1.0 / 60.0)
	var server_pre: Dictionary = _shift(local_pre, phase_offset)
	var server_post: Dictionary = _shift(local_post, phase_offset)
	var authority_current: Dictionary = _shift(current, phase_offset)
	var before: Dictionary = reconciler.get_predicted_state()
	var corrections_before: int = int(reconciler.get_report().get("corrections", 0))
	var ack: Dictionary = _ack(server_pre, server_post, 2, 103, 104, 1, 101, 101, 2)
	_assert(bool(reconciler.set_authoritative_input_ack(ack, 105).get("success", false)), "FIX10 fix8 phase-equivalent ACK registers")
	var reconciled: Dictionary = reconciler.reconcile(authority_current, 105)
	_assert(bool(reconciled.get("success", false)), "FIX10 fix8 phase-equivalent reconciliation succeeds")
	var details: Dictionary = Dictionary(reconciled.get("details", {}))
	_assert(bool(details.get("fix10_fix6_phase_mismatch", false)), "FIX10 fix8 fixture really contains phase mismatch")
	_assert(int(details.get("fix10_fix6_hold_delta_ticks", 0)) == 1, "FIX10 fix8 fixture carries one-tick phase delta")
	_assert(String(details.get("fix10_reconciliation_mode", "")) == "ACK_PHASE_EQUIVALENT_CONFIRM_NO_REPLAY", "FIX10 fix8 explained phase uses no-replay confirm")
	_assert(int(details.get("replayed_ticks", -1)) == 0, "FIX10 fix8 phase-equivalent confirm replays zero ticks")
	_assert(String(details.get("correction_mode", "")) == "NONE", "FIX10 fix8 phase-equivalent confirm creates no spring correction")
	_assert(_position(reconciler.get_predicted_state()).distance_to(_position(before)) < 0.000001, "FIX10 fix8 phase-equivalent confirm preserves local present")
	var report: Dictionary = reconciler.get_report()
	_assert(int(report.get("corrections", 0)) == corrections_before, "FIX10 fix8 phase-equivalent confirm does not increment corrections")
	_assert(int(report.get("fix10_fix8_phase_equivalent_ack_confirmations", 0)) == 1, "FIX10 fix8 phase-equivalent confirmation counted")


func _test_real_divergence_still_rewinds_and_corrects() -> void:
	var fixture: Dictionary = _fixture()
	var reconciler = fixture["reconciler"]
	var local_pre: Dictionary = Dictionary(fixture["seq2_pre"]).duplicate(true)
	var local_post: Dictionary = Dictionary(fixture["seq2_post"]).duplicate(true)
	var current: Dictionary = Dictionary(fixture["current"]).duplicate(true)
	var real_offset := Vector3(0.20, 0.0, 0.0)
	var server_pre: Dictionary = _shift(local_pre, real_offset)
	var server_post: Dictionary = _shift(local_post, real_offset)
	var authority_current: Dictionary = _shift(current, real_offset)
	var ack: Dictionary = _ack(server_pre, server_post, 2, 103, 103, 1, 101, 101, 1)
	_assert(bool(reconciler.set_authoritative_input_ack(ack, 105).get("success", false)), "FIX10 fix8 divergent ACK registers")
	var reconciled: Dictionary = reconciler.reconcile(authority_current, 105)
	_assert(bool(reconciled.get("success", false)), "FIX10 fix8 divergent ACK reconciliation succeeds")
	var details: Dictionary = Dictionary(reconciled.get("details", {}))
	_assert(String(details.get("fix10_reconciliation_mode", "")) != "ACK_EXACT_BASELINE_CONFIRM_NO_REPLAY", "FIX10 fix8 real divergence bypasses exact fast confirm")
	_assert(String(details.get("fix10_reconciliation_mode", "")) != "ACK_PHASE_EQUIVALENT_CONFIRM_NO_REPLAY", "FIX10 fix8 real divergence bypasses phase fast confirm")
	_assert(float(details.get("prediction_error_m", 0.0)) > 0.19, "FIX10 fix8 real divergence remains visible")
	_assert(String(details.get("correction_mode", "NONE")) != "NONE", "FIX10 fix8 real divergence still creates correction")
	_assert(int(reconciler.get_report().get("corrections", 0)) >= 1, "FIX10 fix8 real divergence correction counted")


func _test_source_contract() -> void:
	var source: String = FileAccess.get_file_as_string("res://scripts/network/prediction/client_prediction_reconciler.gd")
	_assert(source.contains("EXACT_OR_EXPLAINED_PHASE_ACK_CONFIRM_WITHOUT_PRESENT_REPLAY_V1"), "FIX10 fix8 fast-confirm policy present")
	_assert(source.contains("ACK_EXACT_BASELINE_CONFIRM_NO_REPLAY"), "FIX10 fix8 exact mode present")
	_assert(source.contains("ACK_PHASE_EQUIVALENT_CONFIRM_NO_REPLAY"), "FIX10 fix8 phase-equivalent mode present")
	_assert(source.contains("FIX10_FIX8_MAX_PHASE_EQUIVALENT_HOLD_DELTA_TICKS"), "FIX10 fix8 phase-equivalent bound present")
	_assert(source.contains("return super._fix10_reconcile_from_ack"), "FIX10 fix8 preserves authoritative fallback")


func _fixture() -> Dictionary:
	var reconciler = Reconciler.new()
	_assert(bool(reconciler.configure(_player(), 100).get("success", false)), "FIX10 fix8 fixture configures")
	_assert(bool(reconciler.set_input(1, _intent(0.0, 1.0)).get("success", false)), "FIX10 fix8 seq1 accepted")
	_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "FIX10 fix8 tick101 predicted")
	_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "FIX10 fix8 tick102 predicted")
	var seq2_pre: Dictionary = reconciler.get_predicted_state()
	_assert(bool(reconciler.set_input(2, _intent(1.0, 0.0)).get("success", false)), "FIX10 fix8 seq2 accepted")
	_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "FIX10 fix8 tick103 predicted")
	var seq2_post: Dictionary = reconciler.get_predicted_state()
	_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "FIX10 fix8 tick104 predicted")
	_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "FIX10 fix8 tick105 predicted")
	return {
		"reconciler": reconciler,
		"seq2_pre": seq2_pre,
		"seq2_post": seq2_post,
		"current": reconciler.get_predicted_state(),
	}


func _ack(
	pre_state: Dictionary,
	post_state: Dictionary,
	sequence: int,
	client_tick: int,
	applied_server_tick: int,
	previous_sequence: int,
	previous_client_tick: int,
	previous_applied_server_tick: int,
	server_hold_ticks: int
) -> Dictionary:
	return {
		"input_sequence": sequence,
		"client_tick": client_tick,
		"applied_server_tick": applied_server_tick,
		"position": Dictionary(post_state.get("position", {})).duplicate(true),
		"velocity": Dictionary(post_state.get("velocity", {})).duplicate(true),
		"orientation_yaw": float(post_state.get("orientation_yaw", 0.0)),
		"state_revision": int(post_state.get("state_revision", 1)),
		"semantic_transition_policy": "PRE_POST_INPUT_TRANSITION_WITH_HOLD_TICKS_V1",
		"previous_input_sequence": previous_sequence,
		"previous_client_tick": previous_client_tick,
		"previous_applied_server_tick": previous_applied_server_tick,
		"server_hold_ticks_before_input": server_hold_ticks,
		"pre_position": Dictionary(pre_state.get("position", {})).duplicate(true),
		"pre_velocity": Dictionary(pre_state.get("velocity", {})).duplicate(true),
		"pre_orientation_yaw": float(pre_state.get("orientation_yaw", 0.0)),
		"transition_metadata_complete": true,
	}


func _player() -> Dictionary:
	return {
		"logical_player_id": "a",
		"player_entity_id": "player/a",
		"transport_session_id": "transport-session/fix10-fix8",
		"ownership_epoch": 1,
		"connected": true,
		"position": {"x": 0.0, "y": 0.0, "z": 0.0},
		"velocity": {"x": 0.0, "y": 0.0, "z": 0.0},
		"inventory": [],
		"last_input_sequence": 0,
		"state_revision": 1,
		"orientation_yaw": 0.0,
		"flashlight_enabled": false,
	}


func _intent(move_x: float, move_z: float) -> Dictionary:
	return {
		"move_x": move_x,
		"move_z": move_z,
		"look_yaw": 0.0,
		"look_pitch": 0.0,
		"jump_pressed": false,
		"sprint": false,
		"delta_seconds": 1.0 / 60.0,
	}


func _shift(state: Dictionary, offset: Vector3) -> Dictionary:
	var shifted: Dictionary = state.duplicate(true)
	var position: Vector3 = _position(shifted) + offset
	shifted["position"] = {"x": position.x, "y": position.y, "z": position.z}
	return shifted


func _position(state: Dictionary) -> Vector3:
	var value: Dictionary = Dictionary(state.get("position", {}))
	return Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0)))


func _velocity(state: Dictionary) -> Vector3:
	var value: Dictionary = Dictionary(state.get("velocity", {}))
	return Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0)))


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _finish() -> void:
	print("M7 FIX10 fix8 owner ACK fast-confirm: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

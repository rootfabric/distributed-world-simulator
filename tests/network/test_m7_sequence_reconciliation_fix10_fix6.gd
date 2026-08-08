extends SceneTree

const Reconciler = preload("res://scripts/network/prediction/client_prediction_reconciler.gd")
const InputBufferFix10 = preload("res://scripts/network/simulation/fixed_tick_input_buffer_fix10.gd")
const ClientRuntime = preload("res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd")

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_server_semantic_schedule_preserves_client_tick_spacing()
	_test_same_client_tick_queue_keeps_only_simulated_sequence()
	_test_phase_mismatch_does_not_use_absolute_ack_as_semantic_baseline()
	_test_phase_matched_transition_keeps_direct_ack_replay()
	_test_fix6_transition_wire_decoding()
	_test_ack_dispatch_is_independent_from_canonical_snapshot_acceptance()
	_finish()


func _test_server_semantic_schedule_preserves_client_tick_spacing() -> void:
	var buffer = InputBufferFix10.new()
	_assert(bool(buffer.configure().get("success", false)), "FIX10 fix6 input buffer configures")
	_assert(bool(buffer.enqueue(_input(1, 100, _intent(0.0, 1.0)), 110).get("success", false)), "FIX10 fix6 first input enqueues")
	var first: Dictionary = buffer.consume_for_tick(111)
	_assert(bool(first.get("success", false)), "FIX10 fix6 first input consumes")
	_assert(bool(first.get("details", {}).get("consumed_new_input", false)), "FIX10 fix6 first input establishes semantic clock offset")
	_assert(int(first.get("details", {}).get("input_sequence", 0)) == 1, "FIX10 fix6 first sequence applied")

	_assert(bool(buffer.enqueue(_input(2, 102, _intent(1.0, 0.0)), 111).get("success", false)), "FIX10 fix6 second input enqueues")
	var wait_tick: Dictionary = buffer.consume_for_tick(112)
	_assert(bool(wait_tick.get("success", false)), "FIX10 fix6 semantic wait tick succeeds")
	_assert(not bool(wait_tick.get("details", {}).get("consumed_new_input", true)), "FIX10 fix6 does not consume transition before semantic target")
	_assert(bool(wait_tick.get("details", {}).get("fix10_fix6_semantic_wait", false)), "FIX10 fix6 semantic wait is observable")
	_assert(int(wait_tick.get("details", {}).get("input_sequence", 0)) == 1, "FIX10 fix6 previous input remains active during semantic wait")

	var second: Dictionary = buffer.consume_for_tick(113)
	_assert(bool(second.get("success", false)), "FIX10 fix6 second target tick succeeds")
	_assert(bool(second.get("details", {}).get("consumed_new_input", false)), "FIX10 fix6 consumes transition at semantic target")
	_assert(int(second.get("details", {}).get("input_sequence", 0)) == 2, "FIX10 fix6 second sequence applied at target")
	var report: Dictionary = buffer.get_report(113)
	_assert(String(report.get("fix10_fix6_semantic_schedule_policy", "")) == "FIRST_APPLY_OFFSET_PRESERVES_CLIENT_TICK_SPACING_V1", "FIX10 fix6 semantic schedule policy reported")
	_assert(int(report.get("fix10_fix6_client_to_server_tick_offset", 0)) == 11, "FIX10 fix6 stable client/server tick offset captured")
	_assert(int(report.get("fix10_fix6_semantic_wait_ticks", 0)) == 1, "FIX10 fix6 waited exactly one fixed tick")
	_assert(int(report.get("fix10_fix6_late_apply_events", 0)) == 0, "FIX10 fix6 on-time semantic schedule has no late applies")


func _test_same_client_tick_queue_keeps_only_simulated_sequence() -> void:
	var buffer = InputBufferFix10.new()
	_assert(bool(buffer.configure().get("success", false)), "FIX10 fix6 same-tick buffer configures")
	_assert(bool(buffer.enqueue(_input(1, 200, _intent(0.0, 1.0)), 210).get("success", false)), "FIX10 fix6 same-tick seq1 enqueues")
	_assert(bool(buffer.enqueue(_input(2, 200, _intent(1.0, 0.0)), 210).get("success", false)), "FIX10 fix6 same-tick seq2 enqueues")
	var consumed: Dictionary = buffer.consume_for_tick(211)
	_assert(bool(consumed.get("success", false)), "FIX10 fix6 same-tick consume succeeds")
	_assert(int(consumed.get("details", {}).get("input_sequence", 0)) == 2, "FIX10 fix6 server consumes newest same-client-tick sequence")
	var report: Dictionary = buffer.get_report(211)
	_assert(int(report.get("fix10_fix6_same_client_tick_compactions", 0)) == 1, "FIX10 fix6 same-client-tick compaction counted")
	_assert(int(report.get("fix10_fix6_same_client_tick_inputs_dropped", 0)) == 1, "FIX10 fix6 superseded same-tick input counted")


func _test_phase_mismatch_does_not_use_absolute_ack_as_semantic_baseline() -> void:
	var fixture: Dictionary = _build_transition_fixture()
	var reconciler = fixture["reconciler"]
	var local_pre: Dictionary = Dictionary(fixture["seq2_pre"]).duplicate(true)
	var local_post: Dictionary = Dictionary(fixture["seq2_post"]).duplicate(true)
	var shifted_pre: Dictionary = _shift_state(local_pre, Vector3(1.20, 0.0, 0.0))
	var shifted_post: Dictionary = _shift_state(local_post, Vector3(1.20, 0.0, 0.0))
	var ack: Dictionary = _transition_ack(
		shifted_pre,
		shifted_post,
		2,
		103,
		103,
		1,
		101,
		100,
		2
	)
	_assert(bool(reconciler.set_authoritative_input_ack(ack, 103).get("success", false)), "FIX10 fix6 phase-mismatch ACK registers")
	var reconciled: Dictionary = reconciler.reconcile(local_post, 103)
	_assert(bool(reconciled.get("success", false)), "FIX10 fix6 phase-mismatch reconciliation succeeds")
	var details: Dictionary = Dictionary(reconciled.get("details", {}))
	_assert(String(details.get("fix10_reconciliation_mode", "")) == "ACK_PHASE_MISMATCH_AUTHORITY_SNAPSHOT", "FIX10 fix6 routes phase mismatch away from direct ACK baseline")
	_assert(int(details.get("fix10_fix6_client_hold_ticks_before_input", -1)) == 1, "FIX10 fix6 measures local previous-input hold ticks")
	_assert(int(details.get("fix10_fix6_server_hold_ticks_before_input", -1)) == 2, "FIX10 fix6 measures server previous-input hold ticks")
	_assert(int(details.get("fix10_fix6_hold_delta_ticks", 0)) == 1, "FIX10 fix6 reports hold phase delta")
	_assert(float(details.get("fix10_fix6_raw_phase_baseline_offset_m", 0.0)) > 1.19, "FIX10 fix6 observes raw non-comparable ACK phase offset")
	_assert(float(reconciler.get_report().get("fix10_max_ack_baseline_error_m", 0.0)) < 0.000001, "FIX10 fix6 does not count phase offset as direct ACK baseline error")
	_assert(int(reconciler.get_report().get("fix10_fix6_phase_mismatch_authority_reconciliations", 0)) == 1, "FIX10 fix6 phase-mismatch authority path counted")


func _test_phase_matched_transition_keeps_direct_ack_replay() -> void:
	var fixture: Dictionary = _build_transition_fixture()
	var reconciler = fixture["reconciler"]
	var local_pre: Dictionary = Dictionary(fixture["seq2_pre"]).duplicate(true)
	var local_post: Dictionary = Dictionary(fixture["seq2_post"]).duplicate(true)
	var shifted_pre: Dictionary = _shift_state(local_pre, Vector3(0.20, 0.0, 0.0))
	var shifted_post: Dictionary = _shift_state(local_post, Vector3(0.20, 0.0, 0.0))
	var ack: Dictionary = _transition_ack(
		shifted_pre,
		shifted_post,
		2,
		103,
		102,
		1,
		101,
		100,
		1
	)
	_assert(bool(reconciler.set_authoritative_input_ack(ack, 103).get("success", false)), "FIX10 fix6 phase-matched ACK registers")
	var reconciled: Dictionary = reconciler.reconcile(local_post, 103)
	_assert(bool(reconciled.get("success", false)), "FIX10 fix6 phase-matched reconciliation succeeds")
	var details: Dictionary = Dictionary(reconciled.get("details", {}))
	_assert(String(details.get("fix10_reconciliation_mode", "")) == "ACK_BASELINE_REPLAY", "FIX10 fix6 phase-matched transition retains direct ACK replay")
	_assert(not bool(details.get("fix10_fix6_phase_mismatch", true)), "FIX10 fix6 phase-matched transition classified correctly")
	_assert(float(details.get("fix10_ack_baseline_error_m", 0.0)) > 0.19, "FIX10 fix6 still observes real phase-matched deterministic divergence")
	_assert(int(reconciler.get_report().get("corrections", 0)) >= 1, "FIX10 fix6 still corrects real phase-matched divergence")
	_assert(int(reconciler.get_report().get("fix10_fix6_phase_matched_ack_reconciliations", 0)) == 1, "FIX10 fix6 phase-matched ACK path counted")


func _test_fix6_transition_wire_decoding() -> void:
	var runtime = ClientRuntime.new()
	_assert(runtime != null, "FIX10 fix6 client runtime instantiates")
	if runtime == null:
		return
	var wire: Array = [
		17, 142, 150,
		1.25, 2.5, -3.75,
		6.0, 0.0, -1.5,
		0.75, 24,
		16, 140, 148, 1,
		1.15, 2.5, -3.75,
		6.0, 0.0, -1.5,
		0.70, 1,
	]
	var ack: Dictionary = runtime.call(
		"_fix10_extract_prediction_ack",
		{
			"snapshot": {"t": 152},
			"prediction_ack": wire,
		},
		"COMPACT_GAMEPLAY_SNAPSHOT"
	)
	_assert(not ack.is_empty(), "FIX10 fix6 transition wire decodes")
	_assert(String(ack.get("semantic_transition_policy", "")) == "PRE_POST_INPUT_TRANSITION_WITH_HOLD_TICKS_V1", "FIX10 fix6 transition policy decoded")
	_assert(int(ack.get("previous_input_sequence", 0)) == 16, "FIX10 fix6 previous sequence decoded")
	_assert(int(ack.get("server_hold_ticks_before_input", -1)) == 1, "FIX10 fix6 server hold decoded")
	_assert(bool(ack.get("transition_metadata_complete", false)), "FIX10 fix6 transition completeness decoded")
	_assert(_position({"position": ack.get("pre_position", {})}).distance_to(Vector3(1.15, 2.5, -3.75)) < 0.000001, "FIX10 fix6 pre-position decoded")
	var transport_report: Dictionary = Dictionary(runtime.get_report().get("fix10_prediction_ack_transport", {}))
	_assert(String(transport_report.get("fix6_wire_policy", "")) == "COMPACT_TRANSITION_ARRAY_V2", "FIX10 fix6 transition wire policy reported")
	_assert(int(transport_report.get("fix6_transition_wire_received", 0)) == 1, "FIX10 fix6 transition wire decode counted")
	runtime.free()


func _test_ack_dispatch_is_independent_from_canonical_snapshot_acceptance() -> void:
	var source: String = FileAccess.get_file_as_string(
		"res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd"
	)
	var standalone_start: int = source.find("if message_type == \"PREDICTION_ACK\":")
	var snapshot_start: int = source.find("if message_type in [\"GAMEPLAY_SNAPSHOT\", \"COMPACT_GAMEPLAY_SNAPSHOT\"]:")
	_assert(standalone_start >= 0 and snapshot_start > standalone_start, "FIX10 fix6 standalone/snapshot dispatch branches present")
	if standalone_start >= 0 and snapshot_start > standalone_start:
		var standalone_branch: String = source.substr(
			standalone_start,
			snapshot_start - standalone_start
		)
		_assert(not standalone_branch.contains("super._handle_message(payload)"), "FIX10 fix6 standalone ACK never reaches UNKNOWN base handler")
		_assert(standalone_branch.contains("return"), "FIX10 fix6 standalone ACK branch terminates locally")
	var snapshot_register: int = source.find("_fix10_fix6_register_snapshot_ack(snapshot_ack)", snapshot_start)
	var canonical_dispatch: int = source.find("super._handle_message(payload)", snapshot_register)
	_assert(snapshot_register >= 0 and canonical_dispatch > snapshot_register, "FIX10 fix6 snapshot ACK registers before canonical parent dispatch")
	_assert(source.contains("REGISTER_BEFORE_CANONICAL_ACCEPT_AND_TERMINATE_STANDALONE_V1"), "FIX10 fix6 ACK dispatch policy source present")


func _build_transition_fixture() -> Dictionary:
	var reconciler = Reconciler.new()
	_assert(bool(reconciler.configure(_player(), 100).get("success", false)), "FIX10 fix6 prediction fixture configures")
	_assert(bool(reconciler.set_input(1, _intent(0.0, 1.0)).get("success", false)), "FIX10 fix6 seq1 accepted")
	_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "FIX10 fix6 tick101 predicted")
	_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "FIX10 fix6 tick102 predicted")
	var seq2_pre: Dictionary = reconciler.get_predicted_state()
	_assert(bool(reconciler.set_input(2, _intent(1.0, 0.0)).get("success", false)), "FIX10 fix6 seq2 accepted")
	_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "FIX10 fix6 tick103 predicted")
	var seq2_post: Dictionary = reconciler.get_predicted_state()
	return {
		"reconciler": reconciler,
		"seq2_pre": seq2_pre,
		"seq2_post": seq2_post,
	}


func _transition_ack(
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


func _input(sequence: int, client_tick: int, intent: Dictionary) -> Dictionary:
	return {
		"input_sequence": sequence,
		"operation_id": "operation/fix10-fix6/%d" % sequence,
		"client_tick": client_tick,
		"client_sent_at_ms": 1,
		"intent": intent.duplicate(true),
	}


func _shift_state(state: Dictionary, offset: Vector3) -> Dictionary:
	var shifted: Dictionary = state.duplicate(true)
	var position: Vector3 = _position(shifted) + offset
	shifted["position"] = {"x": position.x, "y": position.y, "z": position.z}
	return shifted


func _player() -> Dictionary:
	return {
		"logical_player_id": "player/fix10-fix6",
		"player_entity_id": "entity/player/fix10-fix6",
		"transport_session_id": "transport-session/fix10-fix6",
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


func _position(state: Dictionary) -> Vector3:
	var value: Dictionary = Dictionary(state.get("position", {}))
	return Vector3(
		float(value.get("x", 0.0)),
		float(value.get("y", 0.0)),
		float(value.get("z", 0.0))
	)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error("FIX10 fix6 assertion failed: %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("M7 sequence-aware reconciliation FIX10 fix6: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("M7 sequence-aware reconciliation FIX10 fix6: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)

extends SceneTree

const Reconciler = preload("res://scripts/network/prediction/client_prediction_reconciler.gd")
const ClientRuntime = preload("res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd")

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_phase_mismatch_does_not_use_absolute_ack_baseline()
	_test_phase_matched_transition_keeps_direct_ack_replay()
	_test_transition_wire_decoding()
	_test_ack_dispatch_is_independent_from_canonical_snapshot_acceptance()
	_finish()


func _test_phase_mismatch_does_not_use_absolute_ack_baseline() -> void:
	var fixture: Dictionary = _build_transition_fixture()
	var reconciler = fixture["reconciler"]
	var local_pre: Dictionary = Dictionary(fixture["seq2_pre"]).duplicate(true)
	var local_post: Dictionary = Dictionary(fixture["seq2_post"]).duplicate(true)
	var shifted_pre: Dictionary = _shift_state(local_pre, Vector3(1.20, 0.0, 0.0))
	var shifted_post: Dictionary = _shift_state(local_post, Vector3(1.20, 0.0, 0.0))
	var ack: Dictionary = _transition_ack(shifted_pre, shifted_post, 2, 103, 103, 1, 101, 100, 2)
	_assert(bool(reconciler.set_authoritative_input_ack(ack, 103).get("success", false)), "phase-mismatch ACK registers")
	var reconciled: Dictionary = reconciler.reconcile(local_post, 103)
	_assert(bool(reconciled.get("success", false)), "phase-mismatch reconciliation succeeds")
	var details: Dictionary = Dictionary(reconciled.get("details", {}))
	_assert(String(details.get("fix10_reconciliation_mode", "")) == "ACK_PHASE_MISMATCH_AUTHORITY_SNAPSHOT", "phase mismatch avoids direct absolute ACK baseline")
	_assert(int(details.get("fix10_fix6_client_hold_ticks_before_input", -1)) == 1, "client hold measured")
	_assert(int(details.get("fix10_fix6_server_hold_ticks_before_input", -1)) == 2, "server hold measured")
	_assert(int(details.get("fix10_fix6_hold_delta_ticks", 0)) == 1, "phase delta reported")
	_assert(float(reconciler.get_report().get("fix10_max_ack_baseline_error_m", 0.0)) < 0.000001, "phase offset excluded from direct ACK baseline metric")


func _test_phase_matched_transition_keeps_direct_ack_replay() -> void:
	var fixture: Dictionary = _build_transition_fixture()
	var reconciler = fixture["reconciler"]
	var local_pre: Dictionary = Dictionary(fixture["seq2_pre"]).duplicate(true)
	var local_post: Dictionary = Dictionary(fixture["seq2_post"]).duplicate(true)
	var shifted_pre: Dictionary = _shift_state(local_pre, Vector3(0.20, 0.0, 0.0))
	var shifted_post: Dictionary = _shift_state(local_post, Vector3(0.20, 0.0, 0.0))
	var ack: Dictionary = _transition_ack(shifted_pre, shifted_post, 2, 103, 102, 1, 101, 100, 1)
	_assert(bool(reconciler.set_authoritative_input_ack(ack, 103).get("success", false)), "phase-matched ACK registers")
	var reconciled: Dictionary = reconciler.reconcile(local_post, 103)
	_assert(bool(reconciled.get("success", false)), "phase-matched reconciliation succeeds")
	var details: Dictionary = Dictionary(reconciled.get("details", {}))
	_assert(String(details.get("fix10_reconciliation_mode", "")) == "ACK_BASELINE_REPLAY", "phase match retains direct ACK replay")
	_assert(not bool(details.get("fix10_fix6_phase_mismatch", true)), "phase match classified correctly")
	_assert(float(details.get("fix10_ack_baseline_error_m", 0.0)) > 0.19, "real deterministic baseline divergence remains observable")
	_assert(int(reconciler.get_report().get("corrections", 0)) >= 1, "real phase-matched divergence still corrects")


func _test_transition_wire_decoding() -> void:
	var runtime = ClientRuntime.new()
	_assert(runtime != null, "client runtime instantiates")
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
		{"snapshot": {"t": 152}, "prediction_ack": wire},
		"COMPACT_GAMEPLAY_SNAPSHOT"
	)
	_assert(not ack.is_empty(), "transition wire decodes")
	_assert(String(ack.get("semantic_transition_policy", "")) == "PRE_POST_INPUT_TRANSITION_WITH_HOLD_TICKS_V1", "transition policy decoded")
	_assert(int(ack.get("previous_input_sequence", 0)) == 16, "previous sequence decoded")
	_assert(int(ack.get("server_hold_ticks_before_input", -1)) == 1, "server hold decoded")
	_assert(bool(ack.get("transition_metadata_complete", false)), "transition metadata complete")
	runtime.free()


func _test_ack_dispatch_is_independent_from_canonical_snapshot_acceptance() -> void:
	var source: String = FileAccess.get_file_as_string(
		"res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd"
	)
	var standalone_start: int = source.find("if message_type == \"PREDICTION_ACK\":")
	var snapshot_start: int = source.find("if message_type in [\"GAMEPLAY_SNAPSHOT\", \"COMPACT_GAMEPLAY_SNAPSHOT\"]:")
	_assert(standalone_start >= 0 and snapshot_start > standalone_start, "standalone/snapshot dispatch branches present")
	if standalone_start >= 0 and snapshot_start > standalone_start:
		var standalone_branch: String = source.substr(standalone_start, snapshot_start - standalone_start)
		_assert(not standalone_branch.contains("super._handle_message(payload)"), "standalone ACK never reaches UNKNOWN base handler")
		_assert(standalone_branch.contains("return"), "standalone ACK branch terminates locally")
	var snapshot_register: int = source.find("_fix10_fix6_register_snapshot_ack(snapshot_ack)", snapshot_start)
	var canonical_dispatch: int = source.find("super._handle_message(payload)", snapshot_register)
	_assert(snapshot_register >= 0 and canonical_dispatch > snapshot_register, "snapshot ACK registers before canonical parent dispatch")
	_assert(source.contains("REGISTER_BEFORE_CANONICAL_ACCEPT_AND_TERMINATE_STANDALONE_V1"), "ACK dispatch policy source present")


func _build_transition_fixture() -> Dictionary:
	var reconciler = Reconciler.new()
	_assert(bool(reconciler.configure(_player(), 100).get("success", false)), "prediction fixture configures")
	_assert(bool(reconciler.set_input(1, _intent(0.0, 1.0)).get("success", false)), "seq1 accepted")
	_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "tick101 predicted")
	_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "tick102 predicted")
	var seq2_pre: Dictionary = reconciler.get_predicted_state()
	_assert(bool(reconciler.set_input(2, _intent(1.0, 0.0)).get("success", false)), "seq2 accepted")
	_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "tick103 predicted")
	return {"reconciler": reconciler, "seq2_pre": seq2_pre, "seq2_post": reconciler.get_predicted_state()}


func _transition_ack(pre_state: Dictionary, post_state: Dictionary, sequence: int, client_tick: int, applied_server_tick: int, previous_sequence: int, previous_client_tick: int, previous_applied_server_tick: int, server_hold_ticks: int) -> Dictionary:
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
	return Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0)))


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error("FIX10 fix6 ACK assertion failed: %s" % message)


func _finish() -> void:
	print("M7 FIX10 fix6 ACK/phase semantics: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

extends SceneTree

const Reconciler = preload("res://scripts/network/prediction/client_prediction_reconciler.gd")

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_same_client_tick_newer_sequence_supersedes()
	_test_same_client_tick_older_sequence_is_stale()
	_test_exact_composite_key_conflict_remains_strict()
	_test_same_tick_sequence_order_is_wrap_aware()
	_test_client_source_can_stamp_same_future_tick()
	_finish()


func _test_same_client_tick_newer_sequence_supersedes() -> void:
	var fixture: Dictionary = _build_same_tick_fixture()
	var reconciler = fixture["reconciler"]
	var baseline: Dictionary = Dictionary(fixture["baseline_seq3"]).duplicate(true)

	var older: Dictionary = reconciler.set_authoritative_input_ack(
		_ack_from_player(baseline, 2, 103, 107),
		109
	)
	_assert(bool(older.get("success", false)), "FIX10 fix5 older same-tick ACK registers")
	var newer: Dictionary = reconciler.set_authoritative_input_ack(
		_ack_from_player(baseline, 3, 103, 108),
		110
	)
	_assert(bool(newer.get("success", false)), "FIX10 fix5 newer same-tick sequence supersedes older ACK")
	_assert(not bool(newer.get("details", {}).get("ignored_stale", true)), "FIX10 fix5 newer same-tick sequence remains pending")

	var authority_current: Dictionary = reconciler.get_predicted_state()
	var reconciled: Dictionary = reconciler.reconcile(authority_current, 110)
	_assert(bool(reconciled.get("success", false)), "FIX10 fix5 newer same-tick ACK reconciles")
	var details: Dictionary = Dictionary(reconciled.get("details", {}))
	_assert(String(details.get("fix10_reconciliation_mode", "")) == "ACK_BASELINE_REPLAY", "FIX10 fix5 same-tick newest sequence uses ACK replay")
	_assert(int(details.get("fix10_ack_sequence", 0)) == 3, "FIX10 fix5 newer same-tick sequence wins")
	_assert(float(details.get("prediction_error_m", 1.0)) < 0.000001, "FIX10 fix5 same-tick supersession creates no phase correction")

	var report: Dictionary = reconciler.get_report()
	_assert(String(report.get("fix10_fix5_ack_identity_policy", "")) == "CLIENT_TICK_AND_WRAP_AWARE_INPUT_SEQUENCE_V1", "FIX10 fix5 composite ACK identity policy reported")
	_assert(int(report.get("fix10_fix5_same_tick_sequence_supersessions", 0)) == 1, "FIX10 fix5 same-tick supersession counted")
	_assert(int(report.get("fix10_ack_mismatches", 0)) == 0, "FIX10 fix5 legal same-tick sequence transition is not mismatch")


func _test_same_client_tick_older_sequence_is_stale() -> void:
	var fixture: Dictionary = _build_same_tick_fixture()
	var reconciler = fixture["reconciler"]
	var baseline: Dictionary = Dictionary(fixture["baseline_seq3"]).duplicate(true)

	var newer: Dictionary = reconciler.set_authoritative_input_ack(
		_ack_from_player(baseline, 3, 103, 108),
		110
	)
	_assert(bool(newer.get("success", false)), "FIX10 fix5 newer same-tick ACK registers first")
	var reordered_old: Dictionary = reconciler.set_authoritative_input_ack(
		_ack_from_player(baseline, 2, 103, 107),
		109
	)
	_assert(bool(reordered_old.get("success", false)), "FIX10 fix5 reordered older same-tick ACK is benign")
	_assert(bool(reordered_old.get("details", {}).get("ignored_stale", false)), "FIX10 fix5 reordered older same-tick ACK is explicitly stale")
	var report: Dictionary = reconciler.get_report()
	_assert(int(report.get("fix10_fix5_same_tick_sequence_stale", 0)) == 1, "FIX10 fix5 same-tick stale sequence counted")
	_assert(int(report.get("fix10_ack_mismatches", 0)) == 0, "FIX10 fix5 stale same-tick sequence does not increment mismatch")


func _test_exact_composite_key_conflict_remains_strict() -> void:
	var fixture: Dictionary = _build_same_tick_fixture()
	var reconciler = fixture["reconciler"]
	var baseline: Dictionary = Dictionary(fixture["baseline_seq3"]).duplicate(true)
	var first_ack: Dictionary = _ack_from_player(baseline, 3, 103, 108)
	_assert(bool(reconciler.set_authoritative_input_ack(first_ack, 110).get("success", false)), "FIX10 fix5 exact-key fixture registers")

	var conflicting_ack: Dictionary = first_ack.duplicate(true)
	var position: Dictionary = Dictionary(conflicting_ack.get("position", {})).duplicate(true)
	position["x"] = float(position.get("x", 0.0)) + 0.25
	conflicting_ack["position"] = position
	var conflict: Dictionary = reconciler.set_authoritative_input_ack(conflicting_ack, 111)
	_assert(not bool(conflict.get("success", false)), "FIX10 fix5 conflicting baseline for exact composite key is rejected")
	_assert(String(conflict.get("error_code", "")) == "FIX10_PENDING_ACK_BASELINE_CONFLICT", "FIX10 fix5 exact-key conflict has precise error")
	var report: Dictionary = reconciler.get_report()
	_assert(int(report.get("fix10_fix5_exact_key_conflicts", 0)) == 1, "FIX10 fix5 exact-key conflict counted")
	_assert(int(report.get("fix10_ack_mismatches", 0)) == 1, "FIX10 fix5 true exact-key contradiction remains mismatch")


func _test_same_tick_sequence_order_is_wrap_aware() -> void:
	var reconciler = Reconciler.new()
	var wrapped_new: Dictionary = {"client_tick": 200, "input_sequence": 1}
	var wrapped_old: Dictionary = {"client_tick": 200, "input_sequence": 2147483647}
	_assert(int(reconciler.call("_fix10_fix5_compare_ack_order", wrapped_new, wrapped_old)) == 1, "FIX10 fix5 sequence 1 is newer than MAX after wrap")
	_assert(int(reconciler.call("_fix10_fix5_compare_ack_order", wrapped_old, wrapped_new)) == -1, "FIX10 fix5 MAX is stale relative to wrapped sequence 1")
	# Reconciler inherits RefCounted; do not call free(). The local reference is
	# released automatically when this test scope ends.


func _test_client_source_can_stamp_same_future_tick() -> void:
	var source: String = FileAccess.get_file_as_string(
		"res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_nx6.gd"
	)
	_assert(source.contains("_prediction_reconciler.get_prediction_tick() + 1"), "FIX10 fix5 source proves movement transitions stamp the next future prediction tick")
	_assert(source.contains("_input_sequence = InputSequence.next(_input_sequence)"), "FIX10 fix5 source proves input sequence can advance independently of prediction tick")


func _build_same_tick_fixture() -> Dictionary:
	var reconciler = Reconciler.new()
	_assert(bool(reconciler.configure(_player(), 100).get("success", false)), "FIX10 fix5 prediction fixture configures")
	_assert(bool(reconciler.set_input(1, _intent(0.0, 1.0)).get("success", false)), "FIX10 fix5 seq1 accepted")
	_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "FIX10 fix5 tick101 predicted")
	_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "FIX10 fix5 tick102 predicted")

	# Two state transitions target the same next prediction tick before tick103 is
	# simulated. Only the newest sequence is the local timeline state for tick103,
	# while the server may still ACK both transitions on successive authority ticks.
	_assert(bool(reconciler.set_input(2, _intent(1.0, 0.0)).get("success", false)), "FIX10 fix5 seq2 accepted for future tick103")
	_assert(bool(reconciler.set_input(3, _intent(-1.0, 0.0)).get("success", false)), "FIX10 fix5 seq3 accepted for same future tick103")
	_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "FIX10 fix5 tick103 predicted with newest sequence")
	var baseline_seq3: Dictionary = reconciler.get_predicted_state()
	_assert(int(baseline_seq3.get("last_input_sequence", 0)) == 3, "FIX10 fix5 local timeline keeps newest same-tick sequence")
	return {
		"reconciler": reconciler,
		"baseline_seq3": baseline_seq3,
	}


func _ack_from_player(
	player: Dictionary,
	sequence: int,
	client_tick: int,
	applied_server_tick: int
) -> Dictionary:
	return {
		"input_sequence": sequence,
		"client_tick": client_tick,
		"applied_server_tick": applied_server_tick,
		"position": Dictionary(player.get("position", {})).duplicate(true),
		"velocity": Dictionary(player.get("velocity", {})).duplicate(true),
		"orientation_yaw": float(player.get("orientation_yaw", 0.0)),
		"state_revision": int(player.get("state_revision", 1)),
	}


func _player() -> Dictionary:
	return {
		"logical_player_id": "player/fix10-fix5",
		"player_entity_id": "entity/player/fix10-fix5",
		"transport_session_id": "transport-session/fix10-fix5",
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


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error("FIX10 fix5 assertion failed: %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("M7 sequence-aware reconciliation FIX10 fix5: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("M7 sequence-aware reconciliation FIX10 fix5: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)

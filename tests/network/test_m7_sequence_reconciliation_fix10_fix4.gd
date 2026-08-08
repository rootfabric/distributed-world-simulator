extends SceneTree

const Reconciler = preload("res://scripts/network/prediction/client_prediction_reconciler.gd")
const ServerRuntime = preload("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd")

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_ack_from_older_transport_snapshot_reconciles_against_newer_authority()
	_test_cross_channel_reordering_keeps_newest_semantic_ack()
	_test_realtime_movement_envelope_headroom_contract()
	_finish()


func _test_ack_from_older_transport_snapshot_reconciles_against_newer_authority() -> void:
	var fixture: Dictionary = _build_prediction_fixture()
	var reconciler = fixture["reconciler"]
	var baseline_seq2: Dictionary = Dictionary(fixture["baseline_seq2"]).duplicate(true)
	var old_prediction: Dictionary = reconciler.get_predicted_state()
	var authority_current: Dictionary = old_prediction.duplicate(true)

	# This reproduces the fix3 standalone-ACK topology: the ACK was emitted for
	# snapshot T110 on TELEMETRY, but reconciliation happens when a later movement
	# snapshot T116 is already authoritative and carries sequence 4.
	var registered: Dictionary = reconciler.set_authoritative_input_ack(
		_ack_from_player(baseline_seq2, 2, 103, 107),
		110
	)
	_assert(bool(registered.get("success", false)), "FIX10 fix4 lagged standalone ACK registers")
	var reconciled: Dictionary = reconciler.reconcile(authority_current, 116)
	_assert(bool(reconciled.get("success", false)), "FIX10 fix4 lagged standalone ACK reconciles")
	var details: Dictionary = Dictionary(reconciled.get("details", {}))
	_assert(
		String(details.get("fix10_reconciliation_mode", "")) == "ACK_BASELINE_REPLAY",
		"FIX10 fix4 uses semantic ACK baseline despite later carrying snapshot"
	)
	_assert(int(details.get("fix10_ack_sequence", 0)) == 2, "FIX10 fix4 preserves ACK sequence")
	_assert(int(details.get("fix10_ack_transport_snapshot_tick", -1)) == 110, "FIX10 fix4 keeps ACK transport clock as provenance")
	_assert(_position(reconciler.get_predicted_state()).distance_to(_position(old_prediction)) < 0.000001, "FIX10 fix4 reconstructs present from older ACK baseline")
	_assert(float(details.get("prediction_error_m", 1.0)) < 0.000001, "FIX10 fix4 transport lag creates no artificial correction")
	_assert(String(details.get("correction_mode", "")) == "NONE", "FIX10 fix4 transport lag creates no visual spring")
	var report: Dictionary = reconciler.get_report()
	_assert(String(report.get("fix10_fix4_ack_transport_policy", "")) == "SEMANTIC_ACK_BASELINE_DECOUPLED_FROM_TRANSPORT_SNAPSHOT_V1", "FIX10 fix4 ACK transport policy reported")
	_assert(int(report.get("fix10_fix4_transport_tick_lagged", 0)) == 1, "FIX10 fix4 lagged transport clock counted")
	_assert(int(report.get("fix10_fix4_authority_sequence_ahead", 0)) == 1, "FIX10 fix4 newer authority sequence is classified as normal")
	_assert(int(report.get("fix10_ack_mismatches", 0)) == 0, "FIX10 fix4 normal cross-channel lag is not an ACK mismatch")


func _test_cross_channel_reordering_keeps_newest_semantic_ack() -> void:
	var fixture: Dictionary = _build_prediction_fixture()
	var reconciler = fixture["reconciler"]
	var baseline_seq2: Dictionary = Dictionary(fixture["baseline_seq2"]).duplicate(true)
	var baseline_seq3: Dictionary = Dictionary(fixture["baseline_seq3"]).duplicate(true)
	var authority_current: Dictionary = reconciler.get_predicted_state()

	var older_first: Dictionary = reconciler.set_authoritative_input_ack(
		_ack_from_player(baseline_seq2, 2, 103, 107),
		110
	)
	_assert(bool(older_first.get("success", false)), "FIX10 fix4 older pending ACK registers first")
	var newer: Dictionary = reconciler.set_authoritative_input_ack(
		_ack_from_player(baseline_seq3, 3, 105, 111),
		113
	)
	_assert(bool(newer.get("success", false)), "FIX10 fix4 newer pending ACK supersedes older")
	var reordered_old: Dictionary = reconciler.set_authoritative_input_ack(
		_ack_from_player(baseline_seq2, 2, 103, 107),
		110
	)
	_assert(bool(reordered_old.get("success", false)), "FIX10 fix4 reordered older ACK is benign")
	_assert(bool(reordered_old.get("details", {}).get("ignored_stale", false)), "FIX10 fix4 reordered older ACK is explicitly ignored")

	var reconciled: Dictionary = reconciler.reconcile(authority_current, 116)
	_assert(bool(reconciled.get("success", false)), "FIX10 fix4 newest pending ACK reconciles")
	var details: Dictionary = Dictionary(reconciled.get("details", {}))
	_assert(int(details.get("fix10_ack_sequence", 0)) == 3, "FIX10 fix4 newest semantic ACK wins cross-channel race")
	_assert(float(details.get("prediction_error_m", 1.0)) < 0.000001, "FIX10 fix4 reordered ACKs do not manufacture correction")
	var report: Dictionary = reconciler.get_report()
	_assert(int(report.get("fix10_fix4_pending_ack_superseded", 0)) == 1, "FIX10 fix4 pending ACK supersession counted")
	_assert(int(report.get("fix10_fix4_stale_ack_registrations", 0)) == 1, "FIX10 fix4 stale ACK registration counted")
	_assert(int(report.get("fix10_ack_mismatches", 0)) == 0, "FIX10 fix4 channel reordering is not semantic mismatch")


func _test_realtime_movement_envelope_headroom_contract() -> void:
	var server = ServerRuntime.new()
	_assert(
		String(ServerRuntime.FIX10_FIX4_MOVEMENT_ENVELOPE_POLICY)
		== "OMIT_REDUNDANT_REASON_ON_REALTIME_SNAPSHOT_V1",
		"FIX10 fix4 server exposes reasonless realtime envelope policy"
	)
	_assert(ServerRuntime.FIX10_UNRELIABLE_SAFE_PACKET_BYTES == 1350, "FIX10 fix4 preserves conservative 1350-byte safe budget")
	_assert(
		server._fix10_unreliable_budget_decision(1351, false)
		== ServerRuntime.FIX10_UNRELIABLE_DECISION_DROP,
		"FIX10 fix4 does not weaken oversize drop guard"
	)
	server.free()

	var source: String = FileAccess.get_file_as_string(
		"res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd"
	)
	_assert(source.contains("OMIT_REDUNDANT_REASON_ON_REALTIME_SNAPSHOT_V1"), "FIX10 fix4 movement envelope policy source present")
	_assert(not source.contains("\"reason\": \"MOVEMENT_NETWORK_TICK\""), "FIX10 fix4 removes redundant movement reason from realtime wire")
	_assert(source.contains("\"reason\": reason"), "FIX10 fix4 keeps reason on reliable full/resync snapshots")

	var with_reason: int = JSON.stringify({
		"reason": "MOVEMENT_NETWORK_TICK",
		"snapshot": {"t": 100},
	}).to_utf8_buffer().size()
	var without_reason: int = JSON.stringify({
		"snapshot": {"t": 100},
	}).to_utf8_buffer().size()
	_assert(with_reason - without_reason >= 30, "FIX10 fix4 removes meaningful envelope bytes without changing snapshot body")


func _build_prediction_fixture() -> Dictionary:
	var reconciler = Reconciler.new()
	_assert(bool(reconciler.configure(_player(), 100).get("success", false)), "FIX10 fix4 prediction fixture configures")
	_assert(bool(reconciler.set_input(1, _intent(0.0, 1.0)).get("success", false)), "FIX10 fix4 seq1 accepted")
	_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "FIX10 fix4 tick101 predicted")
	_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "FIX10 fix4 tick102 predicted")
	_assert(bool(reconciler.set_input(2, _intent(1.0, 0.0)).get("success", false)), "FIX10 fix4 seq2 accepted")
	_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "FIX10 fix4 tick103 predicted")
	var baseline_seq2: Dictionary = reconciler.get_predicted_state()
	_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "FIX10 fix4 tick104 predicted")
	_assert(bool(reconciler.set_input(3, _intent(1.0, 0.0)).get("success", false)), "FIX10 fix4 seq3 accepted")
	_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "FIX10 fix4 tick105 predicted")
	var baseline_seq3: Dictionary = reconciler.get_predicted_state()
	_assert(bool(reconciler.set_input(4, _intent(0.0, 1.0)).get("success", false)), "FIX10 fix4 seq4 accepted")
	_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "FIX10 fix4 tick106 predicted")
	return {
		"reconciler": reconciler,
		"baseline_seq2": baseline_seq2,
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
		"logical_player_id": "player/fix10-fix4",
		"player_entity_id": "entity/player/fix10-fix4",
		"transport_session_id": "transport-session/fix10-fix4",
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
		push_error("FIX10 fix4 assertion failed: %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("M7 sequence-aware reconciliation FIX10 fix4: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("M7 sequence-aware reconciliation FIX10 fix4: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)
extends SceneTree

const Reconciler = preload("res://scripts/network/prediction/client_prediction_reconciler.gd")
const InputBufferFix10 = preload("res://scripts/network/simulation/fixed_tick_input_buffer_fix10.gd")
const MovementService = preload("res://scripts/runtime/networked_gameplay/services/player_movement_service.gd")
const ClientRuntime = preload("res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd")

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_consumed_input_preserves_client_tick()
	_test_ack_baseline_replays_local_timeline_without_phase_correction()
	_test_repeated_ack_does_not_reapply_baseline()
	_test_real_baseline_divergence_still_corrects()
	_test_compact_ack_wire_decoding()
	_test_fix10_source_composition()
	_finish()


func _test_consumed_input_preserves_client_tick() -> void:
	var buffer = InputBufferFix10.new()
	_assert(bool(buffer.configure().get("success", false)), "FIX10 input buffer configures")
	var enqueued: Dictionary = buffer.enqueue({
		"input_sequence": 1,
		"operation_id": "operation/fix10/input/1",
		"client_tick": 42,
		"client_sent_at_ms": 1,
		"intent": _intent(0.0, 1.0),
	}, 10)
	_assert(bool(enqueued.get("success", false)), "FIX10 input fixture enqueues")
	var consumed: Dictionary = buffer.consume_for_tick(11)
	_assert(bool(consumed.get("success", false)), "FIX10 input fixture consumes")
	var details: Dictionary = Dictionary(consumed.get("details", {}))
	_assert(bool(details.get("consumed_new_input", false)), "FIX10 marks newly consumed input")
	_assert(int(details.get("fix10_client_tick", 0)) == 42, "FIX10 preserves original client prediction tick")
	_assert(int(details.get("fix10_input_applied_server_tick", 0)) == 11, "FIX10 records authoritative application tick")
	var report: Dictionary = buffer.get_report(11)
	_assert(String(report.get("fix10_input_timeline_policy", "")) == "PRESERVE_CLIENT_TICK_ON_CONSUMED_INPUT_V1", "FIX10 input timeline policy reported")
	_assert(int(report.get("fix10_consumed_with_client_tick", 0)) == 1, "FIX10 client-tick consumption counted")


func _test_ack_baseline_replays_local_timeline_without_phase_correction() -> void:
	var fixture: Dictionary = _build_prediction_fixture()
	var reconciler = fixture["reconciler"]
	var old_state: Dictionary = reconciler.get_predicted_state()
	var baseline: Dictionary = Dictionary(fixture["baseline_seq2"]).duplicate(true)
	var authority_current: Dictionary = _advance_state(
		baseline,
		2,
		_intent(1.0, 0.0),
		3
	)
	var registered: Dictionary = reconciler.set_authoritative_input_ack(
		_ack_from_player(baseline, 2, 103, 107),
		110
	)
	_assert(bool(registered.get("success", false)), "FIX10 exact input ack registers")
	var reconciled: Dictionary = reconciler.reconcile(authority_current, 110)
	_assert(bool(reconciled.get("success", false)), "FIX10 ack reconciliation succeeds")
	var details: Dictionary = Dictionary(reconciled.get("details", {}))
	_assert(String(details.get("fix10_reconciliation_mode", "")) == "ACK_BASELINE_REPLAY", "FIX10 uses ack-baseline replay")
	_assert(int(details.get("fix10_ack_replayed_ticks", 0)) == 3, "FIX10 replays every local tick after acknowledged client tick")
	_assert(_position(reconciler.get_predicted_state()).distance_to(_position(old_state)) < 0.000001, "FIX10 reconstructs the same current prediction despite server wall-clock phase")
	_assert(float(details.get("prediction_error_m", 1.0)) < 0.000001, "FIX10 phase-only delay produces zero present-state error")
	_assert(String(details.get("correction_mode", "")) == "NONE", "FIX10 phase-only delay produces no visual spring correction")
	var report: Dictionary = reconciler.get_report()
	_assert(int(report.get("fix10_ack_reconciliations", 0)) == 1, "FIX10 ack reconciliation counted")
	_assert(int(report.get("fix10_ack_replayed_ticks", 0)) == 3, "FIX10 replayed-tick telemetry counted")
	_assert(int(report.get("current_input_sequence", 0)) == 4, "FIX10 preserves newer local input sequence")
	_assert(int(report.get("prediction_tick", 0)) == 106, "FIX10 keeps client prediction clock instead of snapping to server wall clock")


func _test_repeated_ack_does_not_reapply_baseline() -> void:
	var fixture: Dictionary = _build_prediction_fixture()
	var reconciler = fixture["reconciler"]
	var baseline: Dictionary = Dictionary(fixture["baseline_seq2"]).duplicate(true)
	var authority_current: Dictionary = _advance_state(baseline, 2, _intent(1.0, 0.0), 3)
	_assert(bool(reconciler.set_authoritative_input_ack(_ack_from_player(baseline, 2, 103, 107), 110).get("success", false)), "FIX10 first repeated-ack fixture registers")
	_assert(bool(reconciler.reconcile(authority_current, 110).get("success", false)), "FIX10 first repeated-ack fixture reconciles")
	var after_first: Dictionary = reconciler.get_predicted_state()
	_assert(bool(reconciler.set_authoritative_input_ack(_ack_from_player(baseline, 2, 103, 107), 113).get("success", false)), "FIX10 repeated ack registers")
	var repeated: Dictionary = reconciler.reconcile(authority_current, 113)
	_assert(bool(repeated.get("success", false)), "FIX10 repeated ack is accepted")
	_assert(String(repeated.get("details", {}).get("fix10_reconciliation_mode", "")) == "ACK_REPLAY", "FIX10 repeated ack is classified as replay")
	_assert(_position(reconciler.get_predicted_state()).distance_to(_position(after_first)) < 0.000001, "FIX10 repeated ack cannot move current prediction")
	_assert(int(reconciler.get_report().get("fix10_ack_replays", 0)) >= 1, "FIX10 repeated ack telemetry increments")


func _test_real_baseline_divergence_still_corrects() -> void:
	var fixture: Dictionary = _build_prediction_fixture()
	var reconciler = fixture["reconciler"]
	var baseline: Dictionary = Dictionary(fixture["baseline_seq2"]).duplicate(true)
	var shifted_position: Dictionary = Dictionary(baseline.get("position", {})).duplicate(true)
	shifted_position["x"] = float(shifted_position.get("x", 0.0)) + 0.20
	baseline["position"] = shifted_position
	var authority_current: Dictionary = _advance_state(baseline, 2, _intent(1.0, 0.0), 3)
	_assert(bool(reconciler.set_authoritative_input_ack(_ack_from_player(baseline, 2, 103, 107), 110).get("success", false)), "FIX10 divergent ack registers")
	var reconciled: Dictionary = reconciler.reconcile(authority_current, 110)
	_assert(bool(reconciled.get("success", false)), "FIX10 divergent ack reconciles")
	var details: Dictionary = Dictionary(reconciled.get("details", {}))
	_assert(float(details.get("fix10_ack_baseline_error_m", 0.0)) > 0.19, "FIX10 observes real baseline divergence")
	_assert(float(details.get("fix10_present_replay_error_m", 0.0)) > 0.19, "FIX10 carries real divergence to current prediction")
	_assert(String(details.get("correction_mode", "NONE")) != "NONE", "FIX10 still corrects real deterministic divergence")
	_assert(int(reconciler.get_report().get("corrections", 0)) >= 1, "FIX10 real divergence increments correction count")


func _test_compact_ack_wire_decoding() -> void:
	var runtime = ClientRuntime.new()
	_assert(runtime != null, "FIX10 client runtime instantiates for compact ACK probe")
	if runtime == null:
		return
	var wire: Array = [
		17, 142, 144,
		1.25, 2.5, -3.75,
		6.0, 0.0, -1.5,
		0.75, 24,
	]
	var verbose_ack: Dictionary = runtime.call(
		"_fix10_extract_prediction_ack",
		{
			"snapshot": {"t": 150},
			"prediction_ack": wire,
		},
		"COMPACT_GAMEPLAY_SNAPSHOT"
	)
	_assert(not verbose_ack.is_empty(), "FIX10 compact ACK wire decodes")
	_assert(int(verbose_ack.get("input_sequence", 0)) == 17, "FIX10 compact ACK preserves sequence")
	_assert(int(verbose_ack.get("client_tick", 0)) == 142, "FIX10 compact ACK preserves client tick")
	_assert(int(verbose_ack.get("applied_server_tick", 0)) == 144, "FIX10 compact ACK preserves apply tick")
	_assert(int(verbose_ack.get("transport_snapshot_server_tick", 0)) == 150, "FIX10 compact ACK binds transport snapshot tick")
	_assert(_position(verbose_ack).distance_to(Vector3(1.25, 2.5, -3.75)) < 0.000001, "FIX10 compact ACK preserves position")
	var velocity: Dictionary = Dictionary(verbose_ack.get("velocity", {}))
	_assert(Vector3(float(velocity.get("x", 0.0)), float(velocity.get("y", 0.0)), float(velocity.get("z", 0.0))).distance_to(Vector3(6.0, 0.0, -1.5)) < 0.000001, "FIX10 compact ACK preserves velocity")
	_assert(is_equal_approx(float(verbose_ack.get("orientation_yaw", 0.0)), 0.75), "FIX10 compact ACK preserves yaw")
	_assert(int(verbose_ack.get("state_revision", 0)) == 24, "FIX10 compact ACK preserves state revision")
	var transport_report: Dictionary = Dictionary(runtime.get_report().get("fix10_prediction_ack_transport", {}))
	_assert(String(transport_report.get("wire_policy", "")) == "COMPACT_ARRAY_V1", "FIX10 compact ACK wire policy reported")
	_assert(int(transport_report.get("compact_sidecars_received", 0)) == 1, "FIX10 compact ACK decode is observable")
	var verbose_wire_bytes: int = JSON.stringify({
		"input_sequence": 17,
		"client_tick": 142,
		"applied_server_tick": 144,
		"position": {"x": 1.25, "y": 2.5, "z": -3.75},
		"velocity": {"x": 6.0, "y": 0.0, "z": -1.5},
		"orientation_yaw": 0.75,
		"state_revision": 24,
	}).to_utf8_buffer().size()
	var compact_wire_bytes: int = JSON.stringify(wire).to_utf8_buffer().size()
	_assert(compact_wire_bytes + 80 < verbose_wire_bytes, "FIX10 compact ACK materially reduces unreliable packet budget")
	runtime.free()


func _test_fix10_source_composition() -> void:
	var server_source: String = FileAccess.get_file_as_string(
		"res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd"
	)
	_assert(server_source.contains("SERVER_ECHOED_POST_INPUT_BASELINE_V1"), "FIX10 server ack policy source missing")
	_assert(server_source.contains("prediction_ack"), "FIX10 server snapshot ack sidecar missing")
	_assert(server_source.contains("COMPACT_ARRAY_V1"), "FIX10 server compact ACK wire policy missing")
	_assert(server_source.contains("_fix10_ack_wire_for_peer"), "FIX10 server does not compact ACK sidecar")
	_assert(server_source.contains("fixed_tick_input_buffer_fix10.gd"), "FIX10 server does not activate client-tick input buffer")
	var client_source: String = FileAccess.get_file_as_string(
		"res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd"
	)
	_assert(client_source.contains("set_authoritative_input_ack"), "FIX10 client does not route ack sidecar to reconciler")
	_assert(client_source.contains("COMPACT_ARRAY_V1"), "FIX10 client compact ACK decoder missing")
	_assert(client_source.contains("m3_graphical_client_runtime_fix9.gd"), "FIX10 client must preserve FIX9 runtime underneath")
	var reconciler_source: String = FileAccess.get_file_as_string(
		"res://scripts/network/prediction/client_prediction_reconciler.gd"
	)
	_assert(reconciler_source.contains("ACK_BASELINE_REPLAY_LOCAL_TIMELINE_V1"), "FIX10 reconciliation policy source missing")
	_assert(reconciler_source.contains("client_prediction_reconciler_fix8.gd"), "FIX10 reconciler must preserve FIX8 underneath")


func _build_prediction_fixture() -> Dictionary:
	var reconciler = Reconciler.new()
	_assert(bool(reconciler.configure(_player(), 100).get("success", false)), "FIX10 prediction fixture configures")
	_assert(bool(reconciler.set_input(1, _intent(0.0, 1.0)).get("success", false)), "FIX10 seq1 accepted")
	_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "FIX10 tick101 predicted")
	_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "FIX10 tick102 predicted")
	_assert(bool(reconciler.set_input(2, _intent(1.0, 0.0)).get("success", false)), "FIX10 seq2 accepted")
	_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "FIX10 tick103 predicted")
	var baseline_seq2: Dictionary = reconciler.get_predicted_state()
	_assert(int(baseline_seq2.get("last_input_sequence", 0)) == 2, "FIX10 seq2 baseline captured at client tick103")
	_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "FIX10 tick104 predicted")
	_assert(bool(reconciler.set_input(3, _intent(1.0, 0.0)).get("success", false)), "FIX10 seq3 accepted")
	_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "FIX10 tick105 predicted")
	_assert(bool(reconciler.set_input(4, _intent(0.0, 1.0)).get("success", false)), "FIX10 seq4 accepted")
	_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "FIX10 tick106 predicted")
	return {"reconciler": reconciler, "baseline_seq2": baseline_seq2}


func _advance_state(
	state: Dictionary,
	sequence: int,
	intent: Dictionary,
	ticks: int
) -> Dictionary:
	var movement = MovementService.new()
	var current: Dictionary = state.duplicate(true)
	for _index in range(ticks):
		var result: Dictionary = movement.apply_fixed_tick(
			current,
			sequence,
			intent,
			1.0 / 60.0
		)
		_assert(bool(result.get("success", false)), "FIX10 authority fixture advances")
		if not bool(result.get("success", false)):
			return current
		current = Dictionary(result.get("details", {}).get("player", current)).duplicate(true)
	return current


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
		"logical_player_id": "a",
		"player_entity_id": "player/a",
		"transport_session_id": "transport-session/fix10/a",
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
		push_error("FIX10 assertion failed: %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("M7 sequence-aware reconciliation FIX10: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("M7 sequence-aware reconciliation FIX10: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)

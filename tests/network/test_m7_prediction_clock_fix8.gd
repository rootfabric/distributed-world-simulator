extends SceneTree

const Reconciler = preload("res://scripts/network/prediction/client_prediction_reconciler.gd")
const RemotePresenter = preload("res://scripts/runtime/networked_gameplay/m3/remote_player_presenter.gd")

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_sequence_matched_future_clock_alignment()
	_test_sequence_mismatch_keeps_authoritative_path()
	_test_visual_correction_is_bounded_and_rate_limited()
	_test_remote_snapshot_gap_telemetry()
	_test_fix8_source_contracts()
	_finish()


func _test_sequence_matched_future_clock_alignment() -> void:
	var reconciler = Reconciler.new()
	_assert(bool(reconciler.configure(_player(), 0).get("success", false)), "FIX8 reconciler configures")
	_assert(bool(reconciler.set_input(1, _intent(0.0, 1.0)).get("success", false)), "FIX8 movement input accepted")
	_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "FIX8 first fixed prediction tick advances")
	var before := _position(reconciler.get_predicted_state())
	_assert(before.z < -0.09 and before.z > -0.11, "FIX8 fixture starts at one 0.1 m walk tick")

	# Preserve a real render-rate residual before the authority clock moves ahead.
	_assert(bool(reconciler.advance_frame(1.0 / 144.0).get("success", false)), "FIX8 accumulates a sub-tick render phase")
	var authority := _player_at_z(-0.4, -6.0, 1)
	var reconciled: Dictionary = reconciler.reconcile(authority, 4)
	_assert(bool(reconciled.get("success", false)), "sequence-matched future authority reconciles")
	_assert(int(reconciled.get("details", {}).get("fix8_clock_aligned_ticks", 0)) == 3, "FIX8 pre-aligns the three-tick snapshot phase gap")
	_assert(float(reconciled.get("details", {}).get("prediction_error_m", 1.0)) < 0.000001, "clock phase no longer appears as a 0.3 m prediction error")
	_assert(String(reconciled.get("details", {}).get("correction_mode", "BAD")) == "NONE", "phase-only authority update creates no visual correction")
	_assert(_position(reconciler.get_predicted_state()).distance_to(Vector3(0.0, 0.0, -0.4)) < 0.000001, "canonical prediction converges at authority tick 4")

	var report: Dictionary = reconciler.get_report()
	_assert(String(report.get("clock_alignment_policy", "")) == "SEQUENCE_MATCHED_FUTURE_TICK_PREALIGN_V1", "FIX8 clock alignment policy is reported")
	_assert(int(report.get("clock_alignment_events", 0)) == 1, "FIX8 counts one clock alignment")
	_assert(int(report.get("clock_alignment_ticks", 0)) == 3, "FIX8 counts aligned ticks")
	_assert(int(report.get("corrections", -1)) == 0, "phase-only fixture has zero corrections")
	var scheduler: Dictionary = Dictionary(report.get("scheduler", {}))
	_assert(String(scheduler.get("clock_alignment_policy", "")) == "MONOTONIC_FORWARD_PRESERVE_SUBTICK_PHASE_V1", "scheduler exposes FIX8 monotonic alignment policy")
	_assert(float(scheduler.get("accumulator_seconds", 0.0)) > 0.006, "clock alignment preserves the pre-existing sub-tick accumulator")
	_assert(float(scheduler.get("accumulator_seconds", 1.0)) < 0.008, "preserved sub-tick accumulator remains the 144 Hz fragment")

	var rendered := _position(reconciler.sample_presentation(0.0))
	_assert(rendered.z < -0.43 and rendered.z > -0.46, "FIX7 sub-tick presentation still works after FIX8 clock alignment")


func _test_sequence_mismatch_keeps_authoritative_path() -> void:
	var reconciler = Reconciler.new()
	_assert(bool(reconciler.configure(_player(), 0).get("success", false)), "sequence-mismatch fixture configures")
	_assert(bool(reconciler.set_input(2, _intent(0.0, 1.0)).get("success", false)), "newer local input accepted")
	_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "sequence-mismatch fixture predicts one tick")
	var authority := _player_at_z(-0.1, -6.0, 1)
	var reconciled: Dictionary = reconciler.reconcile(authority, 4)
	_assert(bool(reconciled.get("success", false)), "sequence-mismatch authority remains valid")
	_assert(int(reconciled.get("details", {}).get("fix8_clock_aligned_ticks", -1)) == 0, "FIX8 never invents future ticks across an unacknowledged input sequence")
	var report: Dictionary = reconciler.get_report()
	_assert(int(report.get("sequence_mismatch_alignment_skips", 0)) == 1, "sequence-mismatch clock alignment is explicitly counted")
	_assert(int(report.get("clock_alignment_events", 0)) == 0, "sequence mismatch stays on the existing authoritative reconciliation path")


func _test_visual_correction_is_bounded_and_rate_limited() -> void:
	var reconciler = Reconciler.new()
	_assert(bool(reconciler.configure(_player(), 0).get("success", false)), "visual-bound fixture configures")
	var first := reconciler.reconcile(_player_at_z(0.4, 0.0, 0), 0)
	_assert(bool(first.get("success", false)), "first real correction accepted")
	var second := reconciler.reconcile(_player_at_z(0.8, 0.0, 0), 0)
	_assert(bool(second.get("success", false)), "second continuity correction accepted")
	var report: Dictionary = reconciler.get_report()
	_assert(String(report.get("correction_policy", "")) == "BOUNDED_CONTINUITY_OFFSET_RATE_LIMITED_DECAY_V1", "FIX8 correction policy is reported")
	_assert(float(report.get("max_raw_visual_offset_m", 0.0)) > 0.79, "fixture reproduces an accumulating raw continuity offset")
	_assert(float(report.get("max_bounded_visual_offset_m", 1.0)) <= 0.500001, "FIX8 bounds the applied visual continuity offset")
	_assert(float(report.get("visual_offset_m", 1.0)) <= 0.500001, "current visual correction debt remains bounded")
	_assert(int(report.get("visual_offset_clamps", 0)) >= 1, "FIX8 records the bound activation")
	_assert(int(report.get("rate_limited_corrections", 0)) >= 1, "FIX8 rate-limits decay using actual visual distance")
	_assert(float(report.get("max_visual_decay_seconds", 0.0)) >= 0.19, "half-metre correction cannot be forced through the old 80 ms fast window")
	_assert(int(report.get("hard_corrections", -1)) == 0, "bounded sub-metre corrections remain non-hard")


func _test_remote_snapshot_gap_telemetry() -> void:
	var presenter = RemotePresenter.new()
	var initial := _remote_player(0.0, -6.0, 1)
	var setup: Dictionary = presenter.setup(initial, {
		"server_tick": 100,
		"snapshot_revision": 1,
		"authority_epoch": 1,
	})
	_assert(bool(setup.get("success", false)), "FIX8 remote presenter configures with explicit snapshot context")
	var second := _remote_player(-0.3, -6.0, 2)
	_assert(bool(presenter.apply_replica(second, false, {
		"server_tick": 103,
		"snapshot_revision": 2,
		"authority_epoch": 1,
	}).get("success", false)), "remote snapshot +3 ticks accepted")
	var third := _remote_player(-0.9, -6.0, 3)
	_assert(bool(presenter.apply_replica(third, false, {
		"server_tick": 109,
		"snapshot_revision": 3,
		"authority_epoch": 1,
	}).get("success", false)), "remote snapshot +6 ticks accepted")
	var report: Dictionary = presenter.get_report()
	_assert(String(report.get("fix8_remote_buffer_policy", "")) == "MOVING_HOLD_AND_SNAPSHOT_GAP_DIAGNOSTICS_V1", "remote presenter exposes FIX8 buffer telemetry policy")
	_assert(int(report.get("fix8_snapshot_gap_samples", 0)) == 2, "remote presenter counts snapshot gaps")
	_assert(int(report.get("fix8_max_snapshot_gap_ticks", 0)) == 6, "remote presenter reports maximum snapshot gap")
	_assert(absf(float(report.get("fix8_mean_snapshot_gap_ticks", 0.0)) - 4.5) < 0.000001, "remote presenter reports mean snapshot gap")
	presenter.free()


func _test_fix8_source_contracts() -> void:
	var reconciler_source := FileAccess.get_file_as_string("res://scripts/network/prediction/client_prediction_reconciler.gd")
	_assert(reconciler_source.contains("SEQUENCE_MATCHED_FUTURE_TICK_PREALIGN_V1"), "FIX8 source owns explicit clock alignment policy")
	_assert(reconciler_source.contains("authoritative_sequence == _current_sequence"), "future pre-alignment is guarded by input-sequence agreement")
	_assert(reconciler_source.contains("FIX8_MAX_FUTURE_ALIGNMENT_TICKS"), "future clock alignment has a hard bounded horizon")
	_assert(reconciler_source.contains("FIX8_MAX_VISUAL_OFFSET_M"), "visual continuity debt is explicitly bounded")
	_assert(reconciler_source.contains("FIX8_MAX_VISUAL_CORRECTION_SPEED_MPS"), "visual correction decay is rate-limited")
	var presenter_source := FileAccess.get_file_as_string("res://scripts/runtime/networked_gameplay/m3/remote_player_presenter.gd")
	_assert(presenter_source.contains("fix8_moving_buffer_underruns"), "remote presenter reports moving buffer underruns")
	_assert(presenter_source.contains("HOLD_EXTRAPOLATION_LIMIT"), "remote moving-hold telemetry observes the real interpolation hold mode")


func _player() -> Dictionary:
	return _player_at_z(0.0, 0.0, 0)


func _player_at_z(z: float, velocity_z: float, input_sequence: int) -> Dictionary:
	return {
		"logical_player_id": "a",
		"player_entity_id": "player/a",
		"transport_session_id": "transport-session/fix8/a",
		"ownership_epoch": 1,
		"connected": true,
		"position": {"x": 0.0, "y": 0.0, "z": z},
		"velocity": {"x": 0.0, "y": 0.0, "z": velocity_z},
		"inventory": [],
		"last_input_sequence": input_sequence,
		"state_revision": maxi(1, input_sequence + 1),
		"orientation_yaw": 0.0,
		"flashlight_enabled": false,
	}


func _remote_player(z: float, velocity_z: float, state_revision: int) -> Dictionary:
	return {
		"logical_player_id": "remote",
		"player_entity_id": "player/remote",
		"transport_session_id": "transport-session/fix8/remote",
		"ownership_epoch": 1,
		"connected": true,
		"position": {"x": 0.0, "y": 0.0, "z": z},
		"velocity": {"x": 0.0, "y": 0.0, "z": velocity_z},
		"inventory": [],
		"last_input_sequence": state_revision,
		"state_revision": state_revision,
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
		push_error("FIX8 assertion failed: %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("M7 prediction clock FIX8: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("M7 prediction clock FIX8: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)

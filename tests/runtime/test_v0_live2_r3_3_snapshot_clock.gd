extends SceneTree

const EarthPresenter = preload("res://scripts/app/earth_m3_remote_spectator_presenter.gd")
const Snapshot = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--negative-presenter="):
			_test_legacy_negative(argument.trim_prefix("--negative-presenter="))
			_finish("NEGATIVE_CONTROL")
			return
	_test_wire_context_and_validation()
	_test_epoch_change()
	for fps in [60, 144, 240]:
		_test_twenty_hz_stream(fps)
	_finish("POSITIVE")


func _record(index: int = 0, epoch: int = 1) -> Dictionary:
	return {
		"logical_player_id": "b", "player_entity_id": "player/b",
		"transport_session_id": "transport-session/r3-3/b/%d" % epoch,
		"ownership_epoch": epoch, "connected": true,
		"position": {"x": float(index) * 0.15, "y": 0.0, "z": 0.0},
		"velocity": {"x": 3.0, "y": 0.0, "z": 0.0},
		"inventory": [], "last_input_sequence": index,
		"state_revision": index + 1, "orientation_yaw": 0.0,
		"flashlight_enabled": false,
	}


func _snapshot(record: Dictionary, tick: int, revision: int) -> Dictionary:
	return Snapshot.create(
		"simulation/earth", 1, revision, tick, "region/earth",
		[record], {"item_id": "item/shared/beacon/1", "available": true,
			"owner_player_entity_id": "", "revision": 0}
	)


func _map_position(x: float, z: float) -> Vector3:
	return Vector3(x, 1000.0, z)


func _test_wire_context_and_validation() -> void:
	var record := _record()
	var snapshot := _snapshot(record, 6000, 900)
	var untouched := snapshot.duplicate(true)
	_check(bool(Snapshot.validate(snapshot).get("success", false)), "fixture is a real canonical wire snapshot")
	var wrapper = EarthPresenter.new()
	var setup: Dictionary = wrapper.setup(record, snapshot, Callable(self, "_map_position"))
	_check(bool(setup.get("success", false)), "raw canonical envelope accepted by Earth wrapper")
	if not bool(setup.get("success", false)):
		wrapper.free()
		return
	var report: Dictionary = wrapper.get_report()
	_check(int(report.get("interpolation", {}).get("latest_server_tick", -1)) == 6000,
		"Earth must retain canonical server_tick, not state_revision or call count")
	_check(int(report.get("snapshot_clock_context", {}).get("snapshot_revision", -1)) == 900,
		"wire revision normalized to NX5 snapshot_revision")
	_check(snapshot == untouched, "context normalization does not mutate the canonical envelope")

	var next_record := _record(1)
	var normalized := {"server_tick": 6003, "snapshot_revision": 901, "authority_epoch": 1}
	var accepted: Dictionary = wrapper.apply_replica(next_record, normalized)
	_check(bool(accepted.get("success", false)), "existing explicit NX5 context remains supported")
	var duplicate: Dictionary = wrapper.apply_replica(next_record, normalized)
	_check(bool(duplicate.get("details", {}).get("duplicate", false)), "duplicate remains a duplicate")
	_check(int(wrapper.get_report().get("duplicate_presenter_samples", 0)) == 1,
		"duplicate arrivals are not confused with accepted samples")

	var bad_inputs: Array = [
		{}, {"server_tick": 6006, "authority_epoch": 1},
		{"server_tick": -1, "revision": 902, "authority_epoch": 1},
		{"server_tick": 6006, "revision": 902, "authority_epoch": 0},
		{"server_tick": 6006.5, "revision": 902, "authority_epoch": 1},
		{"server_tick": "6006", "revision": 902, "authority_epoch": 1},
		{"server_tick": 6006, "revision": 902, "snapshot_revision": 903, "authority_epoch": 1},
	]
	for bad in bad_inputs:
		var rejected: Dictionary = wrapper.apply_replica(next_record, bad)
		_check(not bool(rejected.get("success", true)), "invalid clock cannot fall back to synthetic time")
		_check(int(wrapper.get_report().get("interpolation", {}).get("latest_server_tick", -1)) == 6003,
			"rejected clock cannot advance or replace accepted timeline")
	wrapper.free()


func _test_epoch_change() -> void:
	var wrapper = EarthPresenter.new()
	var initial := _record()
	_check(bool(wrapper.setup(initial, _snapshot(initial, 6000, 900), Callable(self, "_map_position")).get("success", false)),
		"epoch baseline accepted")
	var next_record := _record(2, 2)
	var changed: Dictionary = wrapper.apply_replica(next_record, _snapshot(next_record, 6300, 950))
	_check(bool(changed.get("success", false)), "new remote transport epoch accepted")
	_check(String(changed.get("details", {}).get("reset_reason", "")) == "AUTHORITY_OR_SESSION_CHANGED",
		"new remote epoch reseeds existing interpolator")
	_check(int(wrapper.get_report().get("interpolation", {}).get("latest_server_tick", -1)) == 6300,
		"remote epoch reset preserves server clock rather than local revision")
	var stale: Dictionary = wrapper.apply_replica(initial, _snapshot(initial, 6303, 951))
	_check(not bool(stale.get("success", true)), "old remote epoch remains rejected")
	_check(int(wrapper.get_report().get("interpolation", {}).get("latest_server_tick", -1)) == 6300,
		"old epoch cannot overwrite new timeline")
	wrapper.free()


func _test_twenty_hz_stream(fps: int) -> void:
	var wrapper = EarthPresenter.new()
	var first := _record()
	var setup: Dictionary = wrapper.setup(first, _snapshot(first, 6000, 900), Callable(self, "_map_position"))
	_check(bool(setup.get("success", false)), "20Hz stream setup at %dfps" % fps)
	if not bool(setup.get("success", false)):
		wrapper.free()
		return
	var next_sample := 1
	var tested_frames := 0
	var interpolation_frames := 0
	var hold_frames := 0
	var delta := 1.0 / float(fps)
	for frame in range(fps * 8):
		var time_seconds := float(frame) / float(fps)
		while float(next_sample) / 20.0 <= time_seconds + 0.0000001:
			var record := _record(next_sample)
			# A 60Hz server emits at 20Hz. State revision is deliberately not
			# the server clock, reproducing the production envelope distinction.
			var accepted: Dictionary = wrapper.apply_replica(
				record, _snapshot(record, 6000 + next_sample * 3, 900 + next_sample)
			)
			_check(bool(accepted.get("success", false)), "valid wire sample accepted at %dfps" % fps)
			next_sample += 1
		wrapper._delegate._process(delta)
		wrapper._process(delta)
		if time_seconds >= 0.5:
			tested_frames += 1
			var mode := String(wrapper._delegate._last_mode)
			if mode == "INTERPOLATE":
				interpolation_frames += 1
			if mode.begins_with("HOLD"):
				hold_frames += 1
	var ratio := float(interpolation_frames) / float(maxi(tested_frames, 1))
	var report: Dictionary = wrapper.get_report()
	_check(ratio > 0.9, "healthy 20Hz wire stream interpolates after warmup at %dfps" % fps)
	_check(hold_frames == 0, "healthy 20Hz stream does not starve into HOLD at %dfps" % fps)
	_check(int(report.get("interpolation", {}).get("latest_server_tick", -1)) == 6000 + (next_sample - 1) * 3,
		"latest accepted tick matches wire clock at %dfps" % fps)
	var measured_ms := 0.0
	for value in report.get("sample_mode_time_ms", {}).values():
		measured_ms += float(value)
	_check(absf(measured_ms - 8000.0) < 0.01, "render-time occupancy sums to elapsed time, independent of FPS")
	print("R3_3_CLOCK_STREAM fps=%d interpolate_ratio=%.6f hold_frames=%d latest_tick=%d" % [
		fps, ratio, hold_frames, int(report.get("interpolation", {}).get("latest_server_tick", -1))])
	# A real delivery gap must still produce HOLD: the fix must not hide it.
	for _frame in range(fps):
		wrapper._delegate._process(delta)
		wrapper._process(delta)
	_check(String(wrapper._delegate._last_mode) == "HOLD_EXTRAPOLATION_LIMIT",
		"a genuine one-second sample gap is still observable at %dfps" % fps)
	wrapper.free()


func _test_legacy_negative(path: String) -> void:
	# The control workflow extracts the exact baseline wrapper via git show.
	# No product file is replaced, and this path is not used by normal tests.
	var script = load(path)
	_check(script != null, "negative control loads the exact old presenter source")
	if script == null:
		return
	var wrapper = script.new()
	var record := _record()
	var result: Dictionary = wrapper.setup(record, _snapshot(record, 6000, 900), Callable(self, "_map_position"))
	_check(bool(result.get("success", false)), "baseline negative fails semantically, not at import")
	if bool(result.get("success", false)):
		var actual := int(wrapper.get_report().get("interpolation", {}).get("latest_server_tick", -1))
		_check(actual == 1, "exact baseline substitutes state_revision=1 for server_tick=6000")
		if actual == 1:
			print("BASELINE_CLOCK_MISMATCH_CONFIRMED expected_server_tick=6000 actual_tick=1")
	wrapper.free()


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish(mode: String) -> void:
	for failure in failures:
		push_error(failure)
	print("V0-LIVE.2 R3.3 snapshot clock %s: %d assertions, %d failures" % [mode, assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

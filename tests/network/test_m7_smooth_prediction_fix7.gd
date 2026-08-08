extends SceneTree

const Reconciler = preload("res://scripts/network/prediction/client_prediction_reconciler.gd")
const ReplicaStore = preload("res://scripts/runtime/host_client/multiplayer_gameplay_replica_store.gd")
const Snapshot = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd")
const Delta = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_delta.gd")

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_subtick_render_presentation()
	_test_same_revision_stale_delta_is_superseded()
	_test_same_revision_equal_tick_mutation_still_rejected()
	_test_lightweight_ready_report_source_contract()
	_test_manual_prediction_interpolation_source_contract()
	_finish()


func _test_subtick_render_presentation() -> void:
	var reconciler = Reconciler.new()
	_assert(bool(reconciler.configure(_player(), 0).get("success", false)), "FIX7 reconciler configures")
	_assert(bool(reconciler.set_input(1, _intent(0.0, 1.0)).get("success", false)), "FIX7 movement input accepted")
	_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "FIX7 first prediction tick advances")
	var fixed_position := _position(reconciler.get_predicted_state())
	_assert(fixed_position.z < -0.09 and fixed_position.z > -0.11, "60 Hz simulation remains one canonical 0.1 m walk tick")

	# Accumulate a render frame smaller than one fixed tick. The deterministic
	# predicted state must stay unchanged while presentation advances smoothly.
	_assert(bool(reconciler.advance_frame(1.0 / 144.0).get("success", false)), "144 Hz render fragment advances scheduler")
	var still_fixed := _position(reconciler.get_predicted_state())
	_assert(still_fixed.distance_to(fixed_position) < 0.0000001, "sub-tick rendering never mutates deterministic prediction")
	var rendered := _position(reconciler.sample_presentation(0.0))
	_assert(rendered.z < fixed_position.z - 0.03, "sub-tick presentation moves between 60 Hz simulation ticks")
	_assert(rendered.z > fixed_position.z - 0.06, "sub-tick presentation stays bounded to the current tick phase")

	var report: Dictionary = reconciler.get_report()
	_assert(String(report.get("render_presentation_policy", "")) == "SUBTICK_VELOCITY_EXTRAPOLATION_V1", "FIX7 render policy is reported")
	_assert(int(report.get("nonzero_subtick_samples", 0)) >= 1, "FIX7 counts nonzero sub-tick samples")
	_assert(float(report.get("max_subtick_extrapolation_m", 0.0)) > 0.03, "FIX7 reports real sub-tick travel")
	_assert(float(report.get("max_subtick_extrapolation_m", 1.0)) <= 0.35 + 0.000001, "FIX7 visual extrapolation is bounded")


func _test_same_revision_stale_delta_is_superseded() -> void:
	var store = ReplicaStore.new()
	var current := Snapshot.create(
		"authority/test", 1, 5, 100, "region/test", [_player()], _shared_item()
	)
	_assert(bool(store.accept_snapshot(current).get("success", false)), "replica accepts current revision snapshot")
	var stale_player := _player()
	stale_player["position"] = {"x": 1.0, "y": 0.0, "z": 0.0}
	var stale_delta := Delta.create(
		"authority/test", 1, 4, 5, 90, "PLAYER_MOVED", stale_player, {},
		"superseded-target".sha256_text()
	)
	var accepted: Dictionary = store.accept_delta(stale_delta)
	_assert(bool(accepted.get("success", false)), "older-tick same-revision delta is accepted as transport history")
	_assert(bool(accepted.get("details", {}).get("replay", false)), "older-tick same-revision delta is replay/superseded")
	_assert(bool(accepted.get("details", {}).get("superseded", false)), "older-tick same-revision delta is explicitly superseded")
	_assert(bool(accepted.get("details", {}).get("same_revision", false)), "same-revision race is explicit")
	_assert(store.get_snapshot() == current, "superseded delta cannot mutate the newer snapshot")
	var report: Dictionary = store.get_report()
	_assert(int(report.get("same_revision_superseded_deltas", 0)) == 1, "same-revision race is counted")
	_assert(String(report.get("same_revision_delta_policy", "")) == "OLDER_TICK_DIFFERENT_CHECKSUM_IS_SUPERSEDED_V1", "same-revision policy is reported")


func _test_same_revision_equal_tick_mutation_still_rejected() -> void:
	var store = ReplicaStore.new()
	var current := Snapshot.create(
		"authority/test", 1, 5, 100, "region/test", [_player()], _shared_item()
	)
	_assert(bool(store.accept_snapshot(current).get("success", false)), "mutation fixture snapshot accepted")
	var changed_player := _player()
	changed_player["position"] = {"x": 2.0, "y": 0.0, "z": 0.0}
	var conflicting := Delta.create(
		"authority/test", 1, 4, 5, 100, "PLAYER_MOVED", changed_player, {},
		"conflicting-target".sha256_text()
	)
	var rejected: Dictionary = store.accept_delta(conflicting)
	_assert(not bool(rejected.get("success", true)), "equal-tick different-checksum same revision remains rejected")
	_assert(String(rejected.get("error_code", "")) == "MULTIPLAYER_SAME_REVISION_MUTATION", "real same-revision mutation invariant remains strict")


func _test_lightweight_ready_report_source_contract() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd")
	_assert(source.contains("LIGHTWEIGHT_READY_FULL_TERMINAL_V1"), "server exposes FIX7 lightweight READY policy")
	_assert(source.contains("_build_fix7_ready_report"), "server has dedicated lightweight READY builder")
	_assert(source.contains("m3_dedicated_server_runtime_fix6.gd"), "FIX7 server overlay preserves FIX6 behavior")
	var dispatch_start := source.find("func _dispatch_deferred_report")
	var builder_start := source.find("func _build_fix7_ready_report")
	_assert(dispatch_start >= 0 and builder_start > dispatch_start, "FIX7 READY dispatch source is discoverable")
	if dispatch_start >= 0 and builder_start > dispatch_start:
		var dispatch_source := source.substr(dispatch_start, builder_start - dispatch_start)
		_assert(not dispatch_source.contains("get_report()"), "steady READY dispatch never builds the full report on authority thread")
	var builder_end := source.find("func get_fix7_ready_report_policy")
	if builder_start >= 0 and builder_end > builder_start:
		var builder_source := source.substr(builder_start, builder_end - builder_start)
		_assert(not builder_source.contains("export_durable_state"), "light READY never exports durable state")
		_assert(not builder_source.contains("export_replay_state"), "light READY never exports replay state")


func _test_manual_prediction_interpolation_source_contract() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/world/testing/playground_runtime.gd")
	_assert(source.contains("MANUAL_PREDICTION_PRESENTATION_ENGINE_INTERPOLATION_OFF_V1"), "playground reports manual prediction presentation policy")
	_assert(source.contains("PHYSICS_INTERPOLATION_MODE_OFF"), "network player hierarchy disables engine physics interpolation")
	_assert(source.contains("reset_physics_interpolation"), "manual prediction presentation resets stale engine interpolation history")


func _player() -> Dictionary:
	return {
		"logical_player_id": "a",
		"player_entity_id": "player/a",
		"transport_session_id": "transport-session/fix7/a",
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


func _shared_item() -> Dictionary:
	return {
		"item_id": "item/shared/beacon/1",
		"available": true,
		"owner_player_entity_id": "",
		"revision": 0,
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
		push_error("FIX7 assertion failed: %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("M7 smooth prediction FIX7: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("M7 smooth prediction FIX7: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)

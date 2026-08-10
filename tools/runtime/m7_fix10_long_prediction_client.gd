extends "res://tools/runtime/m7_playable_network_client_camera_sync_fix.gd"

# FIX10 fix6 long acceptance client.
#
# Unlike the short M7 process regression, this worker never disables M7
# prediction sync and never uses submit_movement_intent_blocking(). Every movement
# transition is produced by the normal playground Input -> advance_local_prediction
# path, so client_tick/input_sequence transition diagnostics describe the same
# semantic stream on client and authority.

const FIX10_MIN_STRESS_DURATION_MS: int = 300000
const FIX10_MIN_DIAGNOSTIC_DURATION_MS: int = 20000
const FIX10_DEFAULT_STRESS_DURATION_MS: int = 330000
const FIX10_PROGRESS_WRITE_INTERVAL_MS: int = 2000
const FIX10_WAYPOINT_TOLERANCE_M: float = 0.65
const FIX10_ITEM_WAYPOINT_TOLERANCE_M: float = 1.75

var _fix10_stress_duration_ms: int = FIX10_DEFAULT_STRESS_DURATION_MS
var _fix10_stress_started_ms: int = 0
var _fix10_last_progress_write_ms: int = 0
var _fix10_waypoints_completed: int = 0
var _fix10_item_actions: int = 0
var _fix10_diagnostic_only: bool = false


func _run_phase() -> void:
	await process_frame
	await process_frame
	_fix10_diagnostic_only = _fix10_user_arg_int("diagnostic", 0) > 0
	var minimum_duration_ms: int = (
		FIX10_MIN_DIAGNOSTIC_DURATION_MS
		if _fix10_diagnostic_only
		else FIX10_MIN_STRESS_DURATION_MS
	)
	_fix10_stress_duration_ms = maxi(
		_fix10_user_arg_int("duration-ms", FIX10_DEFAULT_STRESS_DURATION_MS),
		minimum_duration_ms
	)
	playground.set_m7_state_sync_enabled(true)

	var initial_report: Dictionary = playground.create_m3_graphical_client_report()
	_assert(bool(initial_report.get("network_playground_enabled", false)), "FIX10 long stress network playground active")
	_assert(bool(initial_report.get("network_prediction_mode", false)), "FIX10 long stress prediction active")
	_assert(bool(initial_report.get("m7_state_sync_enabled", false)), "FIX10 long stress state sync remains enabled")
	_assert(
		String(initial_report.get("m7_interpolation_mode", "")) == "CLIENT_PREDICTION_RECONCILIATION",
		"FIX10 long stress uses prediction/reconciliation presentation"
	)
	if not failures.is_empty():
		_fail("FIX10_LONG_STRESS_INITIALIZATION_FAILED")
		return

	var remote_ready: bool = await _fix10_wait_for_remote_peer(30000)
	_assert(remote_ready, "FIX10 long stress sees the second client")
	if not remote_ready:
		_fail("FIX10_LONG_STRESS_REMOTE_PEER_TIMEOUT")
		return

	_fix10_stress_started_ms = Time.get_ticks_msec()
	_fix10_last_progress_write_ms = _fix10_stress_started_ms
	var item_ok: bool = (
		await _fix10_item_probe_a()
		if client_id == "a"
		else await _fix10_item_probe_b()
	)
	_assert(item_ok, "FIX10 long stress item probe completed")
	if not item_ok:
		_fail("FIX10_LONG_STRESS_ITEM_PROBE_FAILED")
		return

	var waypoints: Array[Vector3] = (
		[
			Vector3(4.0, 1.2, 2.0),
			Vector3(4.0, 1.2, -4.0),
			Vector3(-4.0, 1.2, -4.0),
			Vector3(-4.0, 1.2, 2.0),
		]
		if client_id == "a"
		else [
			Vector3(-3.0, 1.2, 3.0),
			Vector3(5.0, 1.2, 3.0),
			Vector3(5.0, 1.2, -3.0),
			Vector3(-3.0, 1.2, -3.0),
		]
	)
	var waypoint_index: int = 0
	while Time.get_ticks_msec() - _fix10_stress_started_ms < _fix10_stress_duration_ms:
		var remaining_ms: int = _fix10_stress_duration_ms - (
			Time.get_ticks_msec() - _fix10_stress_started_ms
		)
		if remaining_ms <= 0:
			break
		var reached: bool = await _fix10_move_prediction_toward(
			waypoints[waypoint_index % waypoints.size()],
			mini(remaining_ms, 15000),
			FIX10_WAYPOINT_TOLERANCE_M,
			waypoint_index % 3 == 1
		)
		if reached:
			_fix10_waypoints_completed += 1
		waypoint_index += 1
		_fix10_release_movement_actions()
		await _wait_frames(4)

	_fix10_release_movement_actions()
	await create_timer(1.0).timeout
	var final_world_report: Dictionary = playground.create_m3_graphical_client_report()
	var final_runtime_report: Dictionary = client.get_report()
	var prediction: Dictionary = Dictionary(
		final_runtime_report.get("client_prediction", {}).get("runtime", {})
	)
	_assert(bool(final_world_report.get("m7_state_sync_enabled", false)), "FIX10 long stress never disabled prediction sync")
	if _fix10_diagnostic_only:
		_assert(_fix10_waypoints_completed > 0, "FIX10 diagnostic completed movement waypoints")
		_assert(int(prediction.get("ticks_predicted", 0)) > 100, "FIX10 diagnostic accumulated prediction ticks")
	else:
		_assert(_fix10_waypoints_completed > 10, "FIX10 long stress completed repeated movement waypoints")
		_assert(int(prediction.get("ticks_predicted", 0)) > 1000, "FIX10 long stress accumulated prediction ticks")
	_assert(
		int(final_runtime_report.get("client_prediction", {}).get("reconcile_failures", -1)) == 0,
		"FIX10 long stress has no prediction reconcile failures"
	)
	_assert("b" in client.get_remote_player_ids() if client_id == "a" else "a" in client.get_remote_player_ids(), "FIX10 long stress remote peer remains visible")
	if not failures.is_empty():
		_fail("FIX10_LONG_STRESS_FINAL_ASSERTION_FAILED")
		return

	_complete(_fix10_progress_details())


func _fix10_item_probe_a() -> bool:
	if not await _fix10_move_prediction_toward(
		Vector3(1.2, 1.2, -3.4), 20000, FIX10_ITEM_WAYPOINT_TOLERANCE_M, false
	):
		return false
	var adapter = playground._m7_item_adapter
	var shared_beacon: String = adapter.to_replica_item_id("item/shared/beacon/1")
	var pickup_submission: Dictionary = playground.item_gameplay.pickup_world_item(shared_beacon)
	if not bool(pickup_submission.get("success", false)):
		return false
	var pickup: Dictionary = await _await_item_authority(pickup_submission)
	if not bool(pickup.get("success", false)):
		return false
	_fix10_item_actions += 1

	var select_base: Dictionary = playground.item_gameplay.select_hotbar(1)
	if not bool(select_base.get("success", false)):
		return false
	var place_submission: Dictionary = playground.item_gameplay.place_selected_item_at_transform(
		Transform3D(Basis.IDENTITY, Vector3(9000.0, 9000.0, 9000.0))
	)
	if not bool(place_submission.get("success", false)):
		return false
	var place: Dictionary = await _await_item_authority(place_submission)
	if not bool(place.get("success", false)):
		return false
	_fix10_item_actions += 1

	var mount_id: String = _latest_fixture_mount(client.get_item_graph_snapshot())
	if mount_id.is_empty():
		return false
	var select_beacon: Dictionary = playground.item_gameplay.select_hotbar(0)
	if not bool(select_beacon.get("success", false)):
		return false
	var mount_submission: Dictionary = playground.item_gameplay.mount_selected_item(
		mount_id, "beacon_socket"
	)
	if not bool(mount_submission.get("success", false)):
		return false
	var mount: Dictionary = await _await_item_authority(mount_submission)
	if not bool(mount.get("success", false)):
		return false
	_fix10_item_actions += 1

	var detach_submission: Dictionary = playground.item_gameplay.detach_socket_to_inventory(
		mount_id, "beacon_socket"
	)
	if not bool(detach_submission.get("success", false)):
		return false
	var detach: Dictionary = await _await_item_authority(detach_submission)
	if not bool(detach.get("success", false)):
		return false
	_fix10_item_actions += 1

	var drop_submission: Dictionary = playground.item_gameplay.drop_selected_item()
	if not bool(drop_submission.get("success", false)):
		return false
	var drop: Dictionary = await _await_item_authority(drop_submission)
	if not bool(drop.get("success", false)):
		return false
	_fix10_item_actions += 1
	return true


func _fix10_item_probe_b() -> bool:
	if not await _fix10_move_prediction_toward(
		Vector3(3.0, 1.2, -2.0), 20000, FIX10_ITEM_WAYPOINT_TOLERANCE_M, false
	):
		return false
	var adapter = playground._m7_item_adapter
	var crate_id: String = adapter.to_replica_item_id("item/shared/crate/1")
	var open_crate: Dictionary = playground.item_gameplay.interact_world_item(crate_id)
	if not bool(open_crate.get("success", false)):
		return false
	_fix10_item_actions += 1

	if not await _fix10_move_prediction_toward(
		Vector3(-1.5, 1.2, -2.8), 20000, FIX10_ITEM_WAYPOINT_TOLERANCE_M, false
	):
		return false
	var ore_id: String = adapter.to_replica_item_id("item/shared/ore/1")
	var pickup_submission: Dictionary = playground.item_gameplay.pickup_world_item(ore_id)
	if not bool(pickup_submission.get("success", false)):
		return false
	var pickup: Dictionary = await _await_item_authority(pickup_submission)
	if not bool(pickup.get("success", false)):
		return false
	_fix10_item_actions += 1
	return true


func _fix10_move_prediction_toward(
	target: Vector3,
	timeout_ms: int,
	tolerance_m: float,
	sprint: bool
) -> bool:
	var started_ms: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_ms < timeout_ms:
		_fix10_write_progress_if_due()
		var current: Vector3 = playground.player.get_world_position()
		var delta: Vector3 = (target - current).slide(Vector3.UP)
		if delta.length() <= tolerance_m:
			_fix10_release_movement_actions()
			return true
		if delta.length_squared() > 0.000001:
			delta = delta.normalized()
			_set_automated_camera_yaw(atan2(-delta.x, -delta.z))
		Input.action_press("move_forward")
		if sprint:
			Input.action_press("boost")
		else:
			Input.action_release("boost")
		await process_frame
	_fix10_release_movement_actions()
	return false


func _fix10_wait_for_remote_peer(timeout_ms: int) -> bool:
	var expected: String = "b" if client_id == "a" else "a"
	var started_ms: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_ms < timeout_ms:
		if expected in client.get_remote_player_ids():
			return true
		await create_timer(0.05).timeout
	return false


func _fix10_write_progress_if_due() -> void:
	if _fix10_stress_started_ms <= 0:
		return
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _fix10_last_progress_write_ms < FIX10_PROGRESS_WRITE_INTERVAL_MS:
		return
	_fix10_last_progress_write_ms = now_ms
	_write("STRESSING", false, _fix10_progress_details())


func _fix10_progress_details() -> Dictionary:
	return {
		"normal_prediction_only": true,
		"prediction_sync_enabled_for_entire_stress": true,
		"diagnostic_only": _fix10_diagnostic_only,
		"stress_duration_ms": maxi(Time.get_ticks_msec() - _fix10_stress_started_ms, 0),
		"requested_stress_duration_ms": _fix10_stress_duration_ms,
		"waypoints_completed": _fix10_waypoints_completed,
		"item_actions": _fix10_item_actions,
	}


func _fix10_release_movement_actions() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right", "boost", "jump"]:
		Input.action_release(action)


func _fix10_user_arg_int(key: String, fallback: int) -> int:
	var prefix: String = "--%s=" % key
	for value in OS.get_cmdline_user_args():
		var argument: String = String(value)
		if argument.begins_with(prefix):
			return int(argument.substr(prefix.length()))
	return fallback
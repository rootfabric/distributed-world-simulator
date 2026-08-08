extends "res://tools/runtime/m7_playable_network_client.gd"

# The production M7 movement intent derives authoritative yaw from the actual
# camera basis. The acceptance worker used to assign `player.camera_yaw`
# directly, which changes only the scalar field and does not rotate CameraYaw.
# As a result the worker kept sending yaw=0 while believing it was steering
# toward the beacon/crate. Use the player's public view API so the scalar and
# camera node stay synchronized before each authoritative movement intent.
#
# FIX6 throttles materialization of the server READY diagnostic file to 1 Hz.
# That file's embedded `snapshot` can therefore be older than the dedicated
# runtime's explicit `last_two_connected_checksum`, which is captured directly
# from authority whenever the two-player semantic state is synchronized. The
# graphical process acceptance must compare against that captured authority
# checksum first, while retaining the snapshot checksum as a compatibility
# fallback for older runtimes.

func _move_authority_toward(target: Vector3, steps: int) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": ""}
	for _index in range(steps):
		var local_record: Dictionary = client.get_local_player_record()
		var position_value: Dictionary = Dictionary(local_record.get("position", {}))
		var position := Vector3(
			float(position_value.get("x", 0.0)),
			float(position_value.get("y", 0.0)),
			float(position_value.get("z", 0.0))
		)
		var direction := (target - position).slide(Vector3.UP)
		if direction.length_squared() <= 0.000001:
			break
		direction = direction.normalized()
		_set_automated_camera_yaw(atan2(-direction.x, -direction.z))
		result = client.submit_movement_intent_blocking(
			playground._create_m7_movement_intent(0.25, Vector2(0.0, -1.0), 0, 0)
		)
		if not bool(result.get("success", false)):
			return result
		await _wait_frames(4)
	var final_record: Dictionary = client.get_local_player_record()
	var final_position_value: Dictionary = Dictionary(final_record.get("position", {}))
	var final_position := Vector3(
		float(final_position_value.get("x", 0.0)),
		float(final_position_value.get("y", 0.0)),
		float(final_position_value.get("z", 0.0))
	)
	var final_direction := (target - final_position).slide(Vector3.UP)
	if final_direction.length_squared() > 0.000001:
		final_direction = final_direction.normalized()
		_set_automated_camera_yaw(atan2(-final_direction.x, -final_direction.z))
		result = client.submit_movement_intent_blocking(
			playground._create_m7_movement_intent(0.05, Vector2.ZERO, 0, 0)
		)
		await _wait_frames(4)
	return result


func _set_automated_camera_yaw(desired_yaw: float) -> void:
	var current_yaw := float(playground.player.camera_yaw)
	var yaw_delta := wrapf(desired_yaw - current_yaw, -PI, PI)
	playground.player.adjust_view(yaw_delta, 0.0)


func _wait_server_player_checksum(timeout_ms: int) -> bool:
	if server_file.is_empty():
		return false
	var start := Time.get_ticks_msec()
	var stable_checksum := ""
	var stable_since := 0
	while Time.get_ticks_msec() - start < timeout_ms:
		var server_report := _read(server_file)
		var expected := _preferred_server_player_checksum(server_report)
		var local := String(client.get_snapshot().get("checksum", ""))
		if not expected.is_empty() and local == expected:
			if stable_checksum != expected:
				stable_checksum = expected
				stable_since = Time.get_ticks_msec()
			elif Time.get_ticks_msec() - stable_since >= 250:
				return true
		else:
			stable_checksum = ""
			stable_since = 0
		await create_timer(0.05).timeout
	return false


func _server_player_checksum() -> String:
	return _preferred_server_player_checksum(_read(server_file))


func _preferred_server_player_checksum(server_report: Dictionary) -> String:
	var captured := String(server_report.get("last_two_connected_checksum", "")).strip_edges()
	if not captured.is_empty():
		return captured
	return String(server_report.get("snapshot", {}).get("checksum", "")).strip_edges()

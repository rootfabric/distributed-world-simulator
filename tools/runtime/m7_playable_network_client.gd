extends SceneTree

const ClientRuntime = preload("res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd")
const PlaygroundScene = preload("res://scenes/testing/playground.tscn")
const Support = preload("res://scripts/runtime/networked_gameplay/m3/m3_process_support.gd")

const TIMEOUT_MS := 60000

var host := "127.0.0.1"
var port := 0
var client_id := "a"
var phase := 1
var result_file := ""
var peer_file := ""
var server_file := ""
var network_profile := "LOCAL"
var client
var playground
var started_ms := 0
var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	_parse_args()
	call_deferred("_start")


func _start() -> void:
	started_ms = Time.get_ticks_msec()
	if port < 1 or result_file.is_empty():
		_fail("INVALID_M7_WORKER_CONFIGURATION")
		return
	playground = PlaygroundScene.instantiate()
	playground.configure_runtime({
		"runtime_role": "game-client",
		"presentation_enabled": true,
		"local_input_enabled": true,
		"universe_id": "main",
		"instance_id": "m7-process-%s" % client_id,
		"launch_options": {"network_playground": true},
		"world_definition": {"id":"playground","options":{"spawn":[0.0,1.2,6.0]}},
	})
	root.add_child(playground)
	client = ClientRuntime.new()
	root.add_child(client)
	client.session_ready.connect(_on_ready)
	client.connection_failed.connect(_on_failed)
	var setup: Dictionary = client.setup({
		"host": host,
		"port": port,
		"logical_player_id": client_id,
		"connect_timeout_ms": 30000,
		"command_timeout_ms": 10000,
		"automated_acceptance": true,
		"playable_sandbox": true,
		"network_condition_profile": network_profile,
	})
	_assert(bool(setup.get("success", false)), "client runtime configured")
	if not bool(setup.get("success", false)):
		_fail(String(setup.get("error_code", "M7_CLIENT_SETUP_FAILED")))


func _on_ready(runtime) -> void:
	var attached: Dictionary = playground.attach_m3_multiplayer_client(runtime)
	_assert(bool(attached.get("success", false)), "playable network playground attached")
	if not bool(attached.get("success", false)):
		_fail(String(attached.get("error_code", "M7_PLAYGROUND_ATTACH_FAILED")))
		return
	call_deferred("_run_phase")


func _on_failed(error_code: String, details: Dictionary) -> void:
	_fail(error_code, details)


func _run_phase() -> void:
	await process_frame
	await process_frame
	var report: Dictionary = playground.create_m3_graphical_client_report()
	_assert(bool(report.get("network_playground_enabled", false)), "network playground mode active")
	_assert(bool(report.get("network_prediction_mode", false)), "client-side movement prediction active")
	_assert(String(report.get("m7_interpolation_mode", "")) == "CLIENT_PREDICTION_RECONCILIATION", "prediction/reconciliation presentation active")
	_assert(int(report.get("m7_prediction_report", {}).get("ticks_predicted", 0)) > 0, "local prediction advances fixed ticks")
	_assert(bool(report.get("seven_days_inventory_active", false)), "Seven Days inventory profile active")
	_assert(playground.item_gameplay != null, "real ItemGameplayController active")
	_assert(playground.m5_networked_inventory_shell == null, "M5 shell remains separate")
	if phase == 1:
		await _run_a()
	else:
		await _run_b()


func _run_a() -> void:
	var before: Vector3 = playground.player.get_world_position()
	Input.action_press("move_forward")
	await _wait_physics_frames(24)
	Input.action_release("move_forward")
	var moved: bool = await _wait_local_movement(before, 0.05, 3000)
	_assert(moved, "A moved through InputMap and server simulation")
	playground.set_m7_state_sync_enabled(false)
	var move_result: Dictionary = await _move_authority_toward(Vector3(1.2, 0.4, -3.4), 2)
	_assert(bool(move_result.get("success", false)), "A movement intent accepted by server simulation")
	await _wait_frames(8)
	var adapter = playground._m7_item_adapter
	var shared_beacon: String = adapter.to_replica_item_id("item/shared/beacon/1")
	var pickup_submission: Dictionary = playground.item_gameplay.pickup_world_item(shared_beacon)
	_assert(bool(pickup_submission.get("success", false)), "A picked up shared 3D beacon")
	var pickup: Dictionary = await _await_item_authority(pickup_submission)
	_assert(bool(pickup.get("success", false)), "A pickup confirmed by server")
	var select_base: Dictionary = playground.item_gameplay.select_hotbar(1)
	_assert(bool(select_base.get("success", false)), "A selected mount base")
	var place_submission: Dictionary = playground.item_gameplay.place_selected_item_at_transform(
		Transform3D(Basis.IDENTITY, Vector3(9000.0, 9000.0, 9000.0))
	)
	_assert(bool(place_submission.get("success", false)), "A placed mount base")
	var place: Dictionary = await _await_item_authority(place_submission)
	_assert(bool(place.get("success", false)), "A placement confirmed by server")
	var mount_id := _latest_fixture_mount(client.get_item_graph_snapshot())
	_assert(not mount_id.is_empty(), "A received placed mount fixture")
	var select_beacon: Dictionary = playground.item_gameplay.select_hotbar(0)
	_assert(bool(select_beacon.get("success", false)), "A selected beacon")
	var mount_submission: Dictionary = playground.item_gameplay.mount_selected_item(mount_id, "beacon_socket")
	_assert(bool(mount_submission.get("success", false)), "A mounted beacon")
	var mount: Dictionary = await _await_item_authority(mount_submission)
	_assert(bool(mount.get("success", false)), "A mount confirmed by server")
	var detach_submission: Dictionary = playground.item_gameplay.detach_socket_to_inventory(mount_id, "beacon_socket")
	_assert(bool(detach_submission.get("success", false)), "A detached beacon")
	var detach: Dictionary = await _await_item_authority(detach_submission)
	_assert(bool(detach.get("success", false)), "A detach confirmed by server")
	var drop_submission: Dictionary = playground.item_gameplay.drop_selected_item()
	_assert(bool(drop_submission.get("success", false)), "A dropped selected item")
	var drop: Dictionary = await _await_item_authority(drop_submission)
	_assert(bool(drop.get("success", false)), "A drop confirmed by server")
	_write("A_DONE", false, {"mount_id":mount_id})
	var peer: Dictionary = await _wait_peer(["B_DONE", "FAILED"], TIMEOUT_MS)
	_assert(String(peer.get("state", "")) == "B_DONE", "A observed B completion")
	if String(peer.get("state", "")) != "B_DONE":
		_fail("M7_B_DID_NOT_COMPLETE", peer)
		return
	playground.set_m7_state_sync_enabled(false)
	await _wait_frames(20)
	var expected_checksum := String(peer.get("item_graph_checksum", ""))
	var converged := await _wait_item_checksum(expected_checksum, 15000)
	_assert(converged, "A converged to B Item Graph checksum")
	_assert("b" in client.get_remote_player_ids(), "A sees remote player B")
	var player_converged := await _wait_server_player_checksum(15000)
	_assert(player_converged, "A converged to authoritative player checksum")
	var convergence_player_checksum := String(client.get_snapshot().get("checksum", ""))
	var convergence_server_checksum := _server_player_checksum()
	_write("A_CONVERGED", false, {
		"peer_checksum": expected_checksum,
		"mount_id": mount_id,
		"convergence_player_checksum": convergence_player_checksum,
		"convergence_server_player_checksum": convergence_server_checksum,
	})
	var b_converged: Dictionary = await _wait_peer(["B_CONVERGED", "FAILED"], TIMEOUT_MS)
	_assert(String(b_converged.get("state", "")) == "B_CONVERGED", "A observed B player convergence")
	if String(b_converged.get("state", "")) != "B_CONVERGED":
		_fail("M7_B_DID_NOT_CONVERGE", b_converged)
		return
	_complete({
		"peer_checksum": expected_checksum,
		"mount_id": mount_id,
		"convergence_player_checksum": convergence_player_checksum,
		"convergence_server_player_checksum": convergence_server_checksum,
	})


func _run_b() -> void:
	var peer: Dictionary = await _wait_peer(["A_DONE", "FAILED"], TIMEOUT_MS)
	_assert(String(peer.get("state", "")) == "A_DONE", "B observed A gameplay completion")
	if String(peer.get("state", "")) != "A_DONE":
		_fail("M7_A_DID_NOT_COMPLETE", peer)
		return
	var before: Vector3 = playground.player.get_world_position()
	Input.action_press("move_left")
	await _wait_physics_frames(24)
	Input.action_release("move_left")
	var moved: bool = await _wait_local_movement(before, 0.05, 3000)
	_assert(moved, "B moved through InputMap and server simulation")
	playground.set_m7_state_sync_enabled(false)
	var move_result: Dictionary = await _move_authority_toward(Vector3(3.0, 0.8, -2.0), 1)
	_assert(bool(move_result.get("success", false)), "B movement intent accepted by server simulation")
	await _wait_frames(10)
	var adapter = playground._m7_item_adapter
	var crate_id: String = adapter.to_replica_item_id("item/shared/crate/1")
	var open_crate: Dictionary = playground.item_gameplay.interact_world_item(crate_id)
	_assert(bool(open_crate.get("success", false)), "B opened shared 3D crate")
	_assert(String(playground.item_gameplay.inventory_ui.external_container_id) == "container/shared/crate/1", "B sees shared container slots")
	var ore_move: Dictionary = await _move_authority_toward(Vector3(-1.5, 0.35, -2.8), 3)
	_assert(bool(ore_move.get("success", false)), "B moved into ore interaction range")
	var ore_id: String = adapter.to_replica_item_id("item/shared/ore/1")
	var pickup_ore_submission: Dictionary = playground.item_gameplay.pickup_world_item(ore_id)
	_assert(bool(pickup_ore_submission.get("success", false)), "B picked up shared ore")
	var pickup_ore: Dictionary = await _await_item_authority(pickup_ore_submission)
	_assert(bool(pickup_ore.get("success", false)), "B ore pickup confirmed by server")
	playground.set_m7_state_sync_enabled(false)
	await _wait_frames(20)
	_assert("a" in client.get_remote_player_ids(), "B sees remote player A")
	_write("B_DONE", false, {})
	var a_converged: Dictionary = await _wait_peer(["A_CONVERGED", "FAILED"], TIMEOUT_MS)
	_assert(String(a_converged.get("state", "")) == "A_CONVERGED", "B observed A convergence")
	if String(a_converged.get("state", "")) != "A_CONVERGED":
		_fail("M7_A_DID_NOT_CONVERGE", a_converged)
		return
	var expected_player_checksum := String(
		a_converged.get("details", {}).get("convergence_player_checksum", "")
	)
	var player_converged := await _wait_player_checksum(expected_player_checksum, 15000)
	_assert(player_converged, "B converged to A player checksum")
	var server_converged := await _wait_server_player_checksum(15000)
	_assert(server_converged, "B converged to authoritative player checksum")
	var convergence_player_checksum := String(client.get_snapshot().get("checksum", ""))
	var convergence_server_checksum := _server_player_checksum()
	_write("B_CONVERGED", false, {
		"peer_checksum": String(a_converged.get("item_graph_checksum", "")),
		"convergence_player_checksum": convergence_player_checksum,
		"convergence_server_player_checksum": convergence_server_checksum,
	})
	var a_complete: Dictionary = await _wait_peer(["COMPLETE", "FAILED"], TIMEOUT_MS)
	_assert(String(a_complete.get("state", "")) == "COMPLETE", "B observed A clean completion")
	if String(a_complete.get("state", "")) != "COMPLETE":
		_fail("M7_A_DID_NOT_COMPLETE", a_complete)
		return
	_complete({
		"peer_checksum": String(a_converged.get("item_graph_checksum", "")),
		"convergence_player_checksum": convergence_player_checksum,
		"convergence_server_player_checksum": convergence_server_checksum,
	})


func _await_item_authority(submission: Dictionary) -> Dictionary:
	if not bool(submission.get("success", false)) or not bool(submission.get("pending", false)):
		return submission
	var operation_id := String(submission.get(
		"operation_id", submission.get("prediction_id", "")
	)).strip_edges()
	if operation_id.is_empty():
		return {"success": false, "error_code": "NX6_PENDING_OPERATION_ID_REQUIRED"}
	var bridge = playground._m7_item_bridge if playground != null else null
	if bridge == null or not bridge.has_method("wait_for_authoritative_completion"):
		return {"success": false, "error_code": "NX6_AUTHORITATIVE_COMPLETION_API_REQUIRED"}
	return await bridge.wait_for_authoritative_completion(operation_id, 15000)


func _stop_item_bridge() -> void:
	if playground == null:
		return
	var bridge = playground._m7_item_bridge
	if bridge != null and bridge.has_method("stop"):
		bridge.stop("NX6_M7_CLIENT_UNLOAD")


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
		playground.player.camera_yaw = atan2(-direction.x, -direction.z)
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
		playground.player.camera_yaw = atan2(-final_direction.x, -final_direction.z)
		result = client.submit_movement_intent_blocking(
			playground._create_m7_movement_intent(0.05, Vector2.ZERO, 0, 0)
		)
		await _wait_frames(4)
	return result


func _complete(details: Dictionary) -> void:
	_stop_item_bridge()
	_write("COMPLETE", failures.is_empty(), details)
	if client != null:
		client.stop()
	if playground != null:
		playground.prepare_for_unload()
	quit(0 if failures.is_empty() else 1)


func _fail(error_code: String, details: Dictionary = {}) -> void:
	failures.append(error_code)
	_stop_item_bridge()
	_write("FAILED", false, {"error_code":error_code,"cause":details})
	if client != null:
		client.stop()
	if playground != null:
		playground.prepare_for_unload()
	quit(1)


func _write(state: String, passed: bool, details: Dictionary) -> void:
	var report: Dictionary = playground.create_m3_graphical_client_report() if playground != null else {}
	Support.write(result_file, {
		"schema":"planet_simulator.m7_playable_network_client_report.v1",
		"state":state,
		"passed":passed,
		"client_id":client_id,
		"phase":phase,
		"assertions":assertions,
		"failures":failures.duplicate(),
		"details":details.duplicate(true),
		"display_server":DisplayServer.get_name(),
		"player_checksum":String(client.get_snapshot().get("checksum", "")) if client != null else "",
		"item_graph_checksum":String(client.get_item_graph_snapshot().get("checksum", "")) if client != null else "",
		"world_report":report,
		"runtime_report":client.get_report() if client != null else {},
		"process_id":OS.get_process_id(),
	})


func _wait_peer(states: Array[String], timeout_ms: int) -> Dictionary:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < timeout_ms:
		var value := _read(peer_file)
		if String(value.get("state", "")) in states:
			return value
		await create_timer(0.05).timeout
	return _read(peer_file)


func _wait_player_checksum(expected: String, timeout_ms: int) -> bool:
	if expected.is_empty():
		return false
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < timeout_ms:
		if String(client.get_snapshot().get("checksum", "")) == expected:
			return true
		await create_timer(0.05).timeout
	return false


func _wait_server_player_checksum(timeout_ms: int) -> bool:
	if server_file.is_empty():
		return false
	var start := Time.get_ticks_msec()
	var stable_checksum := ""
	var stable_since := 0
	while Time.get_ticks_msec() - start < timeout_ms:
		var server_report := _read(server_file)
		var expected := String(server_report.get("snapshot", {}).get("checksum", ""))
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
	return String(_read(server_file).get("snapshot", {}).get("checksum", ""))


func _wait_item_checksum(expected: String, timeout_ms: int) -> bool:
	if expected.is_empty():
		return false
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < timeout_ms:
		if String(client.get_item_graph_snapshot().get("checksum", "")) == expected:
			return true
		await create_timer(0.05).timeout
	return false


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _wait_local_movement(origin: Vector3, minimum_distance: float, timeout_ms: int) -> bool:
	var started_ms: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_ms <= timeout_ms:
		if playground.player.get_world_position().distance_to(origin) > minimum_distance:
			return true
		await process_frame
	return false


func _wait_physics_frames(count: int) -> void:
	for _index in range(count):
		await physics_frame


func _latest_fixture_mount(snapshot: Dictionary) -> String:
	var result := ""
	for mount_value in snapshot.get("mounts", []):
		if mount_value is Dictionary:
			var mount_id := String(mount_value.get("mount_id", ""))
			if mount_id.begins_with("fixture/item/player/"):
				result = mount_id
	return result


func _read(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return Dictionary(parsed) if parsed is Dictionary else {}


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)


func _parse_args() -> void:
	for value in OS.get_cmdline_user_args():
		var argument := String(value)
		if not argument.begins_with("--") or not argument.contains("="):
			continue
		var separator := argument.find("=")
		var key := argument.substr(2, separator - 2)
		var raw := argument.substr(separator + 1)
		match key:
			"host": host = raw
			"port": port = int(raw)
			"client-id": client_id = raw.to_lower()
			"phase": phase = int(raw)
			"result-file": result_file = raw
			"peer-file": peer_file = raw
			"server-file": server_file = raw
			"network-profile": network_profile = raw.strip_edges().to_upper()

extends SceneTree

const ClientRuntime = preload("res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd")

const BEACON_ID := "item/shared/beacon/1"
const CRATE_CONTAINER_ID := "container/shared/crate/1"
const TARGET_BEACON := Vector3(1.2, 0.4, -3.4)
const TARGET_CRATE := Vector3(3.0, 0.8, -2.0)
const COMMAND_TIMEOUT_MS := 30000
const CONTROL_TIMEOUT_MS := 60000

var host := "127.0.0.1"
var port := 0
var mode := "actor"
var result_file := ""
var control_file := ""
var expected_item_checksum := ""
var previous_session_id := ""
var previous_player_entity_id := ""
var previous_ownership_epoch := 0

var client
var assertions := 0
var failures: Array[String] = []
var _terminal := false


func _init() -> void:
	_parse_args()
	call_deferred("_start")


func _start() -> void:
	if (
		port < 1
		or result_file.is_empty()
		or mode not in ["actor", "before", "after"]
		or (mode in ["actor", "after"] and control_file.is_empty())
	):
		_fail("INVALID_V0_P1_RECONNECT_CLIENT_CONFIGURATION")
		return
	client = ClientRuntime.new()
	root.add_child(client)
	client.session_ready.connect(_on_ready)
	client.connection_failed.connect(_on_failed)
	client.server_disconnected.connect(_on_server_disconnected)
	var logical_player_id := "a" if mode == "actor" else "b"
	var configured: Dictionary = client.setup({
		"host": host,
		"port": port,
		"logical_player_id": logical_player_id,
		"connect_timeout_ms": COMMAND_TIMEOUT_MS,
		"command_timeout_ms": 10000,
		"automated_acceptance": false,
		"playable_sandbox": true,
		"world_id": "earth",
		"debug_logging": true,
	})
	_assert(bool(configured.get("success", false)), "V0-P1 reconnect client configured")
	if not bool(configured.get("success", false)):
		_fail(String(configured.get("error_code", "V0_P1_RECONNECT_CLIENT_SETUP_FAILED")))


func _on_ready(_runtime) -> void:
	call_deferred("_run")


func _on_failed(error_code: String, details: Dictionary) -> void:
	_fail(error_code, details)


func _on_server_disconnected(report: Dictionary) -> void:
	_fail("V0_P1_RECONNECT_SERVER_DISCONNECTED", {
		"runtime_report": report.duplicate(true),
	})


func _run() -> void:
	await _wait_frames(3)
	match mode:
		"actor":
			await _run_actor()
		"before":
			await _run_before()
		"after":
			await _run_after()


func _run_actor() -> void:
	var initial_snapshot: Dictionary = client.get_item_graph_snapshot()
	_assert_runtime_healthy(client.get_report(), "actor initial")
	_assert(not initial_snapshot.is_empty(), "actor receives canonical Item Graph")
	_assert(_item_location(initial_snapshot, BEACON_ID) == "WORLD", "shared beacon starts in WORLD")
	_write("ACTOR_READY", failures.is_empty(), {
		"item_graph_checksum": String(initial_snapshot.get("checksum", "")),
		"item_graph_revision": int(initial_snapshot.get("revision", -1)),
		"actor_player": client.get_local_player_record(),
		"runtime_report": client.get_report(),
	})
	if not failures.is_empty():
		_shutdown(1)
		return

	var mutate_requested := await _wait_control_phase("MUTATE", CONTROL_TIMEOUT_MS)
	_assert(mutate_requested, "actor receives MUTATE phase")
	if not mutate_requested:
		_fail("V0_P1_RECONNECT_MUTATE_PHASE_TIMEOUT")
		return

	var b_disconnected := await _wait_player_connected("b", false, 15000)
	_assert(b_disconnected, "actor replica observes B disconnected before mutation")
	if not b_disconnected:
		_fail("V0_P1_RECONNECT_B_DISCONNECT_NOT_OBSERVED")
		return

	var move_to_beacon: Dictionary = await _move_toward(TARGET_BEACON, 4)
	_assert(bool(move_to_beacon.get("success", false)), "actor moves to shared beacon while B absent")
	var pickup: Dictionary = client.execute_item_command_blocking("item.pickup", {"item_id": BEACON_ID})
	_assert(bool(pickup.get("success", false)), "actor picks up shared beacon while B absent")
	if not bool(pickup.get("success", false)):
		_fail(String(pickup.get("error_code", "V0_P1_RECONNECT_PICKUP_FAILED")), pickup)
		return

	var move_to_crate: Dictionary = await _move_toward(TARGET_CRATE, 4)
	_assert(bool(move_to_crate.get("success", false)), "actor moves to canonical crate while B absent")
	var opened: Dictionary = client.execute_item_command_blocking("container.open", {
		"container_id": CRATE_CONTAINER_ID,
	})
	_assert(bool(opened.get("success", false)), "actor opens canonical crate while B absent")
	if not bool(opened.get("success", false)):
		_fail(String(opened.get("error_code", "V0_P1_RECONNECT_CONTAINER_OPEN_FAILED")), opened)
		return

	var transferred: Dictionary = client.execute_item_command_blocking("item.transfer", {
		"item_id": BEACON_ID,
		"quantity": -1,
		"target_container_id": CRATE_CONTAINER_ID,
		"target_slot_index": 0,
		"target_item_id": "",
	})
	_assert(bool(transferred.get("success", false)), "actor transfers beacon into canonical crate while B absent")
	if not bool(transferred.get("success", false)):
		_fail(String(transferred.get("error_code", "V0_P1_RECONNECT_CONTAINER_TRANSFER_FAILED")), transferred)
		return

	var mutation_visible := await _wait_item_state(
		func(snapshot: Dictionary) -> bool:
			return (
				_item_location(snapshot, BEACON_ID) == "CONTAINER"
				and _item_container_id(snapshot, BEACON_ID) == CRATE_CONTAINER_ID
				and _item_slot_index(snapshot, BEACON_ID) == 0
				and _container_has_item(snapshot, CRATE_CONTAINER_ID, BEACON_ID)
			),
		10000
	)
	_assert(mutation_visible, "actor receives confirmed absent-peer Item Graph mutation")
	if not mutation_visible:
		_fail("V0_P1_RECONNECT_MUTATION_NOT_CONFIRMED")
		return

	var mutated_snapshot: Dictionary = client.get_item_graph_snapshot()
	_assert_runtime_healthy(client.get_report(), "actor post-mutation")
	var mutated_checksum := String(mutated_snapshot.get("checksum", ""))
	_assert(mutated_checksum.length() == 64, "actor captures canonical post-mutation checksum")
	_assert(mutated_checksum != String(initial_snapshot.get("checksum", "")), "absent-peer mutation changes Item Graph checksum")
	_write("ACTOR_MUTATED", failures.is_empty(), {
		"item_graph_checksum": mutated_checksum,
		"item_graph_revision": int(mutated_snapshot.get("revision", -1)),
		"beacon_location": _item_location(mutated_snapshot, BEACON_ID),
		"beacon_container_id": _item_container_id(mutated_snapshot, BEACON_ID),
		"beacon_slot_index": _item_slot_index(mutated_snapshot, BEACON_ID),
		"crate_contains_beacon": _container_has_item(mutated_snapshot, CRATE_CONTAINER_ID, BEACON_ID),
		"actor_player": client.get_local_player_record(),
		"b_player": client.get_player("b"),
		"runtime_report": client.get_report(),
	})
	if not failures.is_empty():
		_shutdown(1)
		return

	var b_reconnected := await _wait_player_connected("b", true, CONTROL_TIMEOUT_MS)
	_assert(b_reconnected, "actor remains live and observes B reconnect")
	if not b_reconnected:
		_fail("V0_P1_RECONNECT_B_RETURN_NOT_OBSERVED")
		return
	var reconnect_snapshot: Dictionary = client.get_item_graph_snapshot()
	_assert_runtime_healthy(client.get_report(), "actor reconnect-observed")
	_assert(String(reconnect_snapshot.get("checksum", "")) == mutated_checksum, "B reconnect does not mutate canonical Item Graph")
	_write("ACTOR_RECONNECT_SEEN", failures.is_empty(), {
		"item_graph_checksum": String(reconnect_snapshot.get("checksum", "")),
		"actor_player": client.get_local_player_record(),
		"b_player": client.get_player("b"),
		"runtime_report": client.get_report(),
	})

	var finish_requested := await _wait_control_phase("FINISH", CONTROL_TIMEOUT_MS)
	_assert(finish_requested, "actor receives FINISH phase")
	if not finish_requested:
		_fail("V0_P1_RECONNECT_FINISH_PHASE_TIMEOUT")
		return
	_complete("ACTOR_COMPLETE", {
		"item_graph_checksum": String(client.get_item_graph_snapshot().get("checksum", "")),
		"actor_player": client.get_local_player_record(),
		"runtime_report": client.get_report(),
	})


func _run_before() -> void:
	var snapshot: Dictionary = client.get_item_graph_snapshot()
	_assert(not snapshot.is_empty(), "B initial session receives canonical Item Graph")
	_assert(_item_location(snapshot, BEACON_ID) == "WORLD", "B initial session sees beacon in WORLD")
	_assert(bool(client.get_player("a").get("connected", false)), "B initial session observes A connected")
	var report: Dictionary = client.get_report()
	_assert_runtime_healthy(report, "B initial")
	var leave: Dictionary = client.request_graceful_leave(3000)
	_assert(bool(leave.get("success", false)), "B initial session leaves through canonical LEAVE")
	_write("BEFORE_COMPLETE", failures.is_empty(), {
		"item_graph_checksum": String(snapshot.get("checksum", "")),
		"item_graph_revision": int(snapshot.get("revision", -1)),
		"transport_session_id": String(report.get("transport_session_id", "")),
		"player_entity_id": String(report.get("player_entity_id", "")),
		"ownership_epoch": int(report.get("ownership_epoch", 0)),
		"actor_player": client.get_player("a"),
		"leave": leave,
		"runtime_report": report,
	})
	_shutdown(0 if failures.is_empty() else 1)


func _run_after() -> void:
	var converged := await _wait_item_state(
		func(snapshot: Dictionary) -> bool:
			return (
				not snapshot.is_empty()
				and (expected_item_checksum.is_empty() or String(snapshot.get("checksum", "")) == expected_item_checksum)
				and _item_location(snapshot, BEACON_ID) == "CONTAINER"
				and _item_container_id(snapshot, BEACON_ID) == CRATE_CONTAINER_ID
				and _item_slot_index(snapshot, BEACON_ID) == 0
				and _container_has_item(snapshot, CRATE_CONTAINER_ID, BEACON_ID)
			),
		15000
	)
	_assert(converged, "reconnected B converges to A absent-peer Item Graph mutation")
	var report: Dictionary = client.get_report()
	_assert_runtime_healthy(report, "B reconnected")
	_assert(String(report.get("transport_session_id", "")) != previous_session_id, "reconnected B receives a new transport session")
	_assert(String(report.get("player_entity_id", "")) == previous_player_entity_id, "reconnected B preserves canonical player entity identity")
	_assert(int(report.get("ownership_epoch", 0)) > previous_ownership_epoch, "reconnected B advances ownership epoch")
	_assert(bool(client.get_player("a").get("connected", false)), "reconnected B observes A still connected")
	var snapshot: Dictionary = client.get_item_graph_snapshot()
	_write("RECONNECT_READY", failures.is_empty(), {
		"item_graph_checksum": String(snapshot.get("checksum", "")),
		"item_graph_revision": int(snapshot.get("revision", -1)),
		"transport_session_id": String(report.get("transport_session_id", "")),
		"player_entity_id": String(report.get("player_entity_id", "")),
		"ownership_epoch": int(report.get("ownership_epoch", 0)),
		"beacon_location": _item_location(snapshot, BEACON_ID),
		"beacon_container_id": _item_container_id(snapshot, BEACON_ID),
		"beacon_slot_index": _item_slot_index(snapshot, BEACON_ID),
		"crate_contains_beacon": _container_has_item(snapshot, CRATE_CONTAINER_ID, BEACON_ID),
		"actor_player": client.get_player("a"),
		"runtime_report": report,
	})
	if not failures.is_empty():
		_shutdown(1)
		return

	var finish_requested := await _wait_control_phase("FINISH", CONTROL_TIMEOUT_MS)
	_assert(finish_requested, "reconnected B receives FINISH phase")
	if not finish_requested:
		_fail("V0_P1_RECONNECT_FINISH_PHASE_TIMEOUT")
		return
	var leave: Dictionary = client.request_graceful_leave(3000)
	_assert(bool(leave.get("success", false)), "reconnected B leaves cleanly")
	_complete("RECONNECT_COMPLETE", {
		"item_graph_checksum": String(client.get_item_graph_snapshot().get("checksum", "")),
		"actor_player": client.get_player("a"),
		"leave": leave,
		"runtime_report": client.get_report(),
	})


func _assert_runtime_healthy(report: Dictionary, label: String) -> void:
	_assert(String(report.get("last_error_code", "")).is_empty(), "%s runtime has no persistent error" % label)
	_assert(int(report.get("async_command_rejections", 0)) == 0, "%s runtime has zero async command rejections" % label)
	_assert(int(report.get("pending_blocking_command_count", 0)) == 0, "%s runtime has no pending blocking commands" % label)


func _move_toward(target: Vector3, steps: int) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": ""}
	for _index in range(steps):
		var position := _player_position(client.get_local_player_record())
		var direction := (target - position).slide(Vector3.UP)
		if direction.length_squared() <= 0.000001:
			break
		direction = direction.normalized()
		var yaw := atan2(-direction.x, -direction.z)
		result = client.submit_movement_intent_blocking({
			"move_x": 0.0,
			"move_z": 1.0,
			"look_yaw": yaw,
			"look_pitch": 0.0,
			"jump_pressed": false,
			"sprint": false,
			"delta_seconds": 0.25,
		})
		if not bool(result.get("success", false)):
			return result
		await _wait_frames(3)
	var position := _player_position(client.get_local_player_record())
	var direction := (target - position).slide(Vector3.UP)
	var yaw := atan2(-direction.x, -direction.z) if direction.length_squared() > 0.000001 else 0.0
	result = client.submit_movement_intent_blocking({
		"move_x": 0.0,
		"move_z": 0.0,
		"look_yaw": yaw,
		"look_pitch": 0.0,
		"jump_pressed": false,
		"sprint": false,
		"delta_seconds": 0.05,
	})
	await _wait_frames(3)
	return result


func _wait_item_state(predicate: Callable, timeout_ms: int) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < timeout_ms:
		if bool(predicate.call(client.get_item_graph_snapshot())):
			return true
		await create_timer(0.05).timeout
	return false


func _wait_player_connected(player_id: String, expected: bool, timeout_ms: int) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < timeout_ms:
		var record: Dictionary = client.get_player(player_id)
		if not record.is_empty() and bool(record.get("connected", false)) == expected:
			return true
		await create_timer(0.05).timeout
	return false


func _wait_control_phase(expected_phase: String, timeout_ms: int) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < timeout_ms:
		var control := _read_json(control_file)
		if String(control.get("phase", "")) == expected_phase:
			return true
		await create_timer(0.05).timeout
	return false


func _item_location(snapshot: Dictionary, item_id: String) -> String:
	return String(_item_record(snapshot, item_id).get("location", {}).get("kind", ""))


func _item_container_id(snapshot: Dictionary, item_id: String) -> String:
	return String(_item_record(snapshot, item_id).get("location", {}).get("container_id", ""))


func _item_slot_index(snapshot: Dictionary, item_id: String) -> int:
	return int(_item_record(snapshot, item_id).get("location", {}).get("slot_index", -1))


func _item_record(snapshot: Dictionary, item_id: String) -> Dictionary:
	for value in snapshot.get("items", []):
		if value is Dictionary and String(value.get("item_id", "")) == item_id:
			return Dictionary(value)
	return {}


func _container_has_item(snapshot: Dictionary, container_id: String, item_id: String) -> bool:
	for value in snapshot.get("containers", []):
		if value is Dictionary and String(value.get("container_id", "")) == container_id:
			return item_id in Array(value.get("slots", []))
	return false


func _player_position(record: Dictionary) -> Vector3:
	var position: Dictionary = Dictionary(record.get("position", {}))
	return Vector3(
		float(position.get("x", 0.0)),
		float(position.get("y", 0.0)),
		float(position.get("z", 0.0))
	)


func _complete(state: String, details: Dictionary) -> void:
	if _terminal:
		return
	_terminal = true
	_write(state, failures.is_empty(), details)
	_shutdown(0 if failures.is_empty() else 1)


func _fail(error_code: String, details: Dictionary = {}) -> void:
	if _terminal:
		return
	_terminal = true
	failures.append(error_code)
	_write("FAILED", false, {"error_code": error_code, "cause": details.duplicate(true)})
	_shutdown(1)


func _shutdown(exit_code: int) -> void:
	if client != null:
		client.stop()
	quit(exit_code)


func _write(state: String, passed: bool, details: Dictionary) -> void:
	_write_json(result_file, {
		"schema": "distributed_world_simulator.v0_p1_live_reconnect_client.v1",
		"state": state,
		"passed": passed,
		"mode": mode,
		"assertions": assertions,
		"failures": failures.duplicate(),
		"details": details.duplicate(true),
		"process_id": OS.get_process_id(),
	})


func _write_json(path: String, value: Dictionary) -> void:
	if path.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(value, "  "))
	file.close()


func _read_json(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return Dictionary(parsed) if parsed is Dictionary else {}


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


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
			"mode": mode = raw.to_lower()
			"result-file": result_file = raw
			"control-file": control_file = raw
			"expected-item-checksum": expected_item_checksum = raw
			"previous-session-id": previous_session_id = raw
			"previous-player-entity-id": previous_player_entity_id = raw
			"previous-ownership-epoch": previous_ownership_epoch = int(raw)

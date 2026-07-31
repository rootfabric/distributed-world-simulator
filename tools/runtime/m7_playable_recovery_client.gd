extends SceneTree

const ClientRuntime = preload("res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd")
const Support = preload("res://scripts/runtime/networked_gameplay/m3/m3_process_support.gd")
const StateCodec = preload("res://scripts/runtime/listen_host/playable_state_codec.gd")

const BEACON_ID := "item/shared/beacon/1"
const TARGET_BEACON := Vector3(1.2, 0.4, -3.4)
const COMMAND_TIMEOUT_MS := 30000

var host := "127.0.0.1"
var port := 0
var mode := "seed"
var result_file := ""
var expected_item_checksum := ""
var client
var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_parse_args()
	call_deferred("_start")


func _start() -> void:
	if port < 1 or result_file.is_empty() or mode not in ["seed", "recover"]:
		_fail("INVALID_M7_RECOVERY_CLIENT_CONFIGURATION")
		return
	client = ClientRuntime.new()
	root.add_child(client)
	client.session_ready.connect(_on_ready)
	client.connection_failed.connect(_on_failed)
	var configured: Dictionary = client.setup({
		"host": host,
		"port": port,
		"logical_player_id": "a",
		"connect_timeout_ms": COMMAND_TIMEOUT_MS,
		"command_timeout_ms": 10000,
		"automated_acceptance": true,
		"playable_sandbox": true,
	})
	_assert(bool(configured.get("success", false)), "M7 recovery client configured")
	if not bool(configured.get("success", false)):
		_fail(String(configured.get("error_code", "M7_RECOVERY_CLIENT_SETUP_FAILED")))


func _on_ready(_runtime) -> void:
	call_deferred("_run")


func _on_failed(error_code: String, details: Dictionary) -> void:
	_fail(error_code, details)


func _run() -> void:
	await process_frame
	await process_frame
	if mode == "seed":
		await _run_seed()
	else:
		await _run_recover()


func _run_seed() -> void:
	_assert(int(client.get_report().get("ownership_epoch", 0)) == 1, "initial M7 ownership epoch is one")
	var moved := await _move_toward(TARGET_BEACON, 3)
	_assert(bool(moved.get("success", false)), "server simulated movement before durable mutation")
	var pickup: Dictionary = client.execute_item_command_blocking("item.pickup", {"item_id": BEACON_ID})
	_assert(bool(pickup.get("success", false)), "M7 beacon pickup committed before restart")
	var assign: Dictionary = client.execute_item_command_blocking("inventory.assign_hotbar", {
		"item_id": BEACON_ID,
		"slot_index": 9,
	})
	_assert(bool(assign.get("success", false)), "M7 ten-slot hotbar assignment committed")
	var ready := await _wait_item_state(
		func(snapshot: Dictionary) -> bool:
			return _hotbar(snapshot, "a").size() == 10 and String(_hotbar(snapshot, "a")[9]) == BEACON_ID,
		10000
	)
	_assert(ready, "M7 ten-slot hotbar visible in authoritative replica")
	var snapshot: Dictionary = client.get_item_graph_snapshot()
	_complete("SEED_COMPLETE", {
		"ownership_epoch": int(client.get_report().get("ownership_epoch", 0)),
		"item_graph_checksum": String(snapshot.get("checksum", "")),
		"item_graph_revision": int(snapshot.get("revision", -1)),
		"hotbar_size": _hotbar(snapshot, "a").size(),
		"slot_9_item_id": String(_hotbar(snapshot, "a")[9]) if _hotbar(snapshot, "a").size() > 9 else "",
	})


func _run_recover() -> void:
	var initial_snapshot: Dictionary = client.get_item_graph_snapshot()
	_assert(int(client.get_report().get("ownership_epoch", 0)) == 2, "reconnected M7 ownership epoch advanced to two")
	_assert(bool(initial_snapshot.get("playable_sandbox", false)), "recovered Item Graph preserves playable sandbox")
	_assert(_hotbar(initial_snapshot, "a").size() == 10, "recovered M7 hotbar has ten slots")
	_assert(String(_hotbar(initial_snapshot, "a")[9]) == BEACON_ID, "recovered hotbar slot nine preserves beacon")
	_assert(expected_item_checksum.is_empty() or String(initial_snapshot.get("checksum", "")) == expected_item_checksum, "recovered Item Graph checksum matches pre-restart state")
	var before_position := _player_position(client.get_local_player_record())
	var movement: Dictionary = client.submit_movement_intent_blocking({
		"move_x": 0.0,
		"move_z": 1.0,
		"look_yaw": 0.0,
		"look_pitch": 0.0,
		"jump_pressed": false,
		"sprint": false,
		"delta_seconds": 0.1,
	})
	_assert(bool(movement.get("success", false)), "recovered server accepts new movement intent")
	await _wait_frames(4)
	var after_position := _player_position(client.get_local_player_record())
	_assert(after_position.distance_to(before_position) > 0.1, "recovered server continues authoritative movement simulation")
	var drop: Dictionary = client.execute_item_command_blocking("item.drop", {
		"item_id": BEACON_ID,
		"quantity": -1,
		"transform": _malicious_transform_dto(),
	})
	_assert(bool(drop.get("success", false)), "recovered server accepts continued item mutation")
	var dropped := await _wait_item_state(
		func(snapshot: Dictionary) -> bool:
			return _item_location(snapshot, BEACON_ID) == "WORLD",
		10000
	)
	_assert(dropped, "continued drop appears in recovered Item Graph")
	var final_snapshot: Dictionary = client.get_item_graph_snapshot()
	var drop_position := _item_position(final_snapshot, BEACON_ID)
	_assert(drop_position.distance_to(after_position) <= 3.0, "server constructs recovered drop transform near authoritative player")
	_assert(drop_position.length() < 100.0, "malicious recovered drop transform is ignored")
	_complete("RECOVER_COMPLETE", {
		"ownership_epoch": int(client.get_report().get("ownership_epoch", 0)),
		"initial_item_graph_checksum": String(initial_snapshot.get("checksum", "")),
		"final_item_graph_checksum": String(final_snapshot.get("checksum", "")),
		"hotbar_size": _hotbar(initial_snapshot, "a").size(),
		"slot_9_item_id": String(_hotbar(initial_snapshot, "a")[9]) if _hotbar(initial_snapshot, "a").size() > 9 else "",
		"drop_position": {"x": drop_position.x, "y": drop_position.y, "z": drop_position.z},
	})


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


func _hotbar(snapshot: Dictionary, player_id: String) -> Array:
	return Array(Dictionary(snapshot.get("inventories", {})).get(player_id, {}).get("hotbar", []))


func _item_location(snapshot: Dictionary, item_id: String) -> String:
	for value in snapshot.get("items", []):
		if value is Dictionary and String(value.get("item_id", "")) == item_id:
			return String(value.get("location", {}).get("kind", ""))
	return ""


func _item_position(snapshot: Dictionary, item_id: String) -> Vector3:
	for value in snapshot.get("items", []):
		if value is Dictionary and String(value.get("item_id", "")) == item_id:
			return StateCodec.transform_from_dto(Dictionary(value.get("transform", {}))).origin
	return Vector3.ZERO


func _player_position(record: Dictionary) -> Vector3:
	var position: Dictionary = Dictionary(record.get("position", {}))
	return Vector3(float(position.get("x", 0.0)), float(position.get("y", 0.0)), float(position.get("z", 0.0)))


func _malicious_transform_dto() -> Dictionary:
	return {
		"basis": {
			"x": {"x": 1.0, "y": 0.0, "z": 0.0},
			"y": {"x": 0.0, "y": 1.0, "z": 0.0},
			"z": {"x": 0.0, "y": 0.0, "z": 1.0},
		},
		"origin": {"x": 9000.0, "y": 9000.0, "z": 9000.0},
	}


func _complete(state: String, details: Dictionary) -> void:
	_write(state, failures.is_empty(), details)
	if client != null:
		client.stop()
	quit(0 if failures.is_empty() else 1)


func _fail(error_code: String, details: Dictionary = {}) -> void:
	failures.append(error_code)
	_write("FAILED", false, {"error_code": error_code, "cause": details.duplicate(true)})
	if client != null:
		client.stop()
	quit(1)


func _write(state: String, passed: bool, details: Dictionary) -> void:
	Support.write(result_file, {
		"schema": "planet_simulator.m7_playable_recovery_client_report.v1",
		"state": state,
		"passed": passed,
		"mode": mode,
		"assertions": assertions,
		"failures": failures.duplicate(),
		"details": details.duplicate(true),
		"runtime_report": client.get_report() if client != null else {},
		"item_graph_checksum": String(client.get_item_graph_snapshot().get("checksum", "")) if client != null else "",
		"process_id": OS.get_process_id(),
	})


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
			"expected-item-checksum": expected_item_checksum = raw

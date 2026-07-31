extends Node

const Support = preload("res://scripts/runtime/networked_gameplay/m5/m5_graphical_acceptance_support.gd")

const TIMEOUT_MS := 150000
const INPUT_HOLD_MS := 500
const POLL_DELAY_MS := 4

var _app
var _client
var _result_file := ""
var _peer_result_file := ""
var _control_file := ""
var _screenshot_dir := ""
var _client_id := ""
var _phase := 0
var _stage := "WAIT_READY"
var _started_ms := 0
var _stage_started_ms := 0
var _initial_input_sequence := 0
var _initial_ownership_epoch := 0
var _contention_result: Dictionary = {}
var _winner_workflow: Dictionary = {}
var _ore_pickup_result: Dictionary = {}
var _movement_result: Dictionary = {}
var _screenshot_result: Dictionary = {}
var _failures: Array[String] = []
var _finished := false
var _input_pressed := false
var _player_checksum := ""
var _item_checksum := ""
var _convergence_world: Dictionary = {}
var _convergence_locked := false


func setup(app_reference, client_runtime, config: Dictionary) -> Dictionary:
	if app_reference == null or client_runtime == null:
		return _failure("M5_ACCEPTANCE_RUNTIME_REQUIRED")
	_app = app_reference
	_client = client_runtime
	_result_file = String(config.get("result_file", "")).strip_edges()
	_peer_result_file = String(config.get("peer_result_file", "")).strip_edges()
	_control_file = String(config.get("control_file", "")).strip_edges()
	_screenshot_dir = String(config.get("screenshot_dir", "")).strip_edges()
	_client_id = String(config.get("client_id", "")).strip_edges().to_lower()
	_phase = int(config.get("phase", 0))
	if (
		_result_file.is_empty()
		or _control_file.is_empty()
		or _client_id not in ["a", "b"]
		or _phase not in [1, 2, 3]
	):
		return _failure("INVALID_M5_ACCEPTANCE_CONFIGURATION")
	_started_ms = Time.get_ticks_msec()
	_stage_started_ms = _started_ms
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_write_report("DRIVER_READY", false)
	print("M5_ACCEPTANCE_DRIVER_READY client=%s phase=%d" % [_client_id, _phase])
	return _success()


func _process(_delta: float) -> void:
	if _finished:
		return
	if Time.get_ticks_msec() - _started_ms > TIMEOUT_MS:
		_fail("M5_ACCEPTANCE_TIMEOUT", {"stage": _stage})
		return
	var runtime = _runtime()
	var shell = _shell(runtime)
	if runtime == null or shell == null or not _client.is_ready():
		return
	var local: Dictionary = _client.get_player(_client_id)
	var remote_id := "b" if _client_id == "a" else "a"
	var remote: Dictionary = _client.get_player(remote_id)
	var world: Dictionary = runtime.create_m3_graphical_client_report()
	match _stage:
		"WAIT_READY":
			if local.is_empty() or remote.is_empty() or not bool(remote.get("connected", false)):
				return
			if int(world.get("remote_presenter_count", 0)) != 1:
				return
			if int(shell.get_report().get("bridge", {}).get("projection", {}).get("revision", -1)) < 0:
				return
			_validate_graphical_world(world, shell)
			if not _failures.is_empty():
				_finish(false)
				return
			_initial_ownership_epoch = int(local.get("ownership_epoch", 0))
			if _phase == 3 and _initial_ownership_epoch < 2:
				return
			_open_inventory_through_input(shell)
			_set_stage("WAIT_UI_OPEN")
		"WAIT_UI_OPEN":
			if not shell.is_inventory_visible():
				return
			_screenshot_result = shell.acceptance_capture_viewport(
				_screenshot_dir.path_join("client-%s-phase-%d.png" % [_client_id, _phase])
			)
			if not bool(_screenshot_result.get("success", false)):
				_failures.append("Graphical screenshot failed: %s" % _screenshot_result)
				_finish(false)
				return
			_initial_input_sequence = int(_client.get_player(_client_id).get("last_input_sequence", 0))
			Input.action_press("move_forward")
			_input_pressed = true
			_set_stage("HOLD_REAL_INPUT")
		"HOLD_REAL_INPUT":
			if Time.get_ticks_msec() - _stage_started_ms < INPUT_HOLD_MS:
				return
			_release_input()
			_set_stage("WAIT_REAL_INPUT_ACK")
		"WAIT_REAL_INPUT_ACK":
			local = _client.get_player(_client_id)
			if int(local.get("last_input_sequence", 0)) <= _initial_input_sequence:
				return
			_movement_result = {
				"success": true,
				"initial_sequence": _initial_input_sequence,
				"final_sequence": int(local.get("last_input_sequence", 0)),
				"input_map_action": "move_forward",
			}
			if _phase == 3:
				_verify_reconnect_state(shell)
				if not _failures.is_empty():
					_finish(false)
					return
				_begin_convergence(world, shell)
			else:
				# Both graphical clients capture the same authoritative world cell
				# before the parent releases the contention barrier. The cursor is
				# transient UI state, so a winner snapshot cannot prevent the loser
				# from submitting its already prepared ITEM_COMMAND.
				var contention_cursor: Dictionary = shell.acceptance_click_item("item/shared/beacon/1")
				if not bool(contention_cursor.get("success", false)) or not bool(shell.get_report().get("cursor_active", false)):
					_failures.append("Contention cursor preparation failed: %s" % contention_cursor)
					_finish(false)
					return
				_write_report("READY_FOR_CONTENTION", false, world, shell)
				_set_stage("WAIT_CONTENTION_GO")
		"WAIT_CONTENTION_GO":
			if not bool(Support.read(_control_file).get("go_contention", false)):
				return
			_contention_result = _ui_place_cursor(shell, "inventory/%s" % _client_id, 0)
			_wait_replica_after_command(shell)
			_write_report("CONTENTION_DONE", false, runtime.create_m3_graphical_client_report(), shell)
			_set_stage("WAIT_PEER_CONTENTION")
		"WAIT_PEER_CONTENTION":
			var peer := Support.read(_peer_result_file)
			if String(peer.get("state", "")) not in ["CONTENTION_DONE", "POST_CONTENTION_READY", "A_CURSOR_PENDING", "WAITING_RECONNECT", "READY_TO_CONVERGE", "COMPLETE"]:
				return
			if bool(_contention_result.get("success", false)):
				_winner_workflow = _run_winner_ui_workflow(shell)
				if not bool(_winner_workflow.get("success", false)):
					_failures.append("Winner UI workflow failed: %s" % _winner_workflow)
					_finish(false)
					return
			else:
				if String(_contention_result.get("error_code", "")) != "ITEM_ALREADY_CLAIMED":
					_failures.append("Unexpected contention rejection: %s" % _contention_result)
					_finish(false)
					return
				if bool(shell.get_report().get("cursor_active", true)):
					failures_append("Rejected contention did not roll back cursor")
			_write_report("POST_CONTENTION_READY", false, runtime.create_m3_graphical_client_report(), shell)
			_set_stage("WAIT_WINNER_WORKFLOW")
		"WAIT_WINNER_WORKFLOW":
			var peer_post := Support.read(_peer_result_file)
			var peer_workflow: Dictionary = peer_post.get("winner_workflow", {})
			if not bool(_winner_workflow.get("success", false)) and not bool(peer_workflow.get("success", false)):
				return
			if _client_id == "a":
				_ore_pickup_result = _ui_transfer(shell, "item/shared/ore/1", "inventory/a", 1)
				_wait_replica_after_command(shell)
				if not bool(_ore_pickup_result.get("success", false)):
					_failures.append("A UI ore pickup failed: %s" % _ore_pickup_result)
					_finish(false)
					return
				var begin_cursor: Dictionary = shell.acceptance_click_item("item/shared/ore/1")
				if not bool(begin_cursor.get("success", false)) or not bool(shell.get_report().get("cursor_active", false)):
					_failures.append("A transient cursor was not created")
					_finish(false)
					return
				_write_report("A_CURSOR_PENDING", false, runtime.create_m3_graphical_client_report(), shell)
				_set_stage("WAIT_DISCONNECT_A")
			else:
				_set_stage("WAIT_A_CURSOR")
		"WAIT_DISCONNECT_A":
			if not bool(Support.read(_control_file).get("disconnect_a", false)):
				return
			_finish(true, "DISCONNECTED_WITH_TRANSIENT")
		"WAIT_A_CURSOR":
			var a_report := Support.read(_peer_result_file)
			if String(a_report.get("state", "")) not in ["A_CURSOR_PENDING", "DISCONNECTED_WITH_TRANSIENT"]:
				return
			_set_stage("WAIT_A_LEFT")
		"WAIT_A_LEFT":
			remote = _client.get_player("a")
			world = runtime.create_m3_graphical_client_report()
			if not remote.is_empty() and bool(remote.get("connected", true)):
				return
			if int(world.get("remote_presenter_count", -1)) != 0:
				return
			_initial_input_sequence = int(_client.get_player("b").get("last_input_sequence", 0))
			Input.action_press("move_right")
			_input_pressed = true
			_set_stage("HOLD_B_OFFLINE_INPUT")
		"HOLD_B_OFFLINE_INPUT":
			if Time.get_ticks_msec() - _stage_started_ms < INPUT_HOLD_MS:
				return
			_release_input()
			_set_stage("WAIT_B_OFFLINE_INPUT_ACK")
		"WAIT_B_OFFLINE_INPUT_ACK":
			local = _client.get_player("b")
			if int(local.get("last_input_sequence", 0)) <= _initial_input_sequence:
				return
			_write_report("WAITING_RECONNECT", false, runtime.create_m3_graphical_client_report(), shell)
			_set_stage("WAIT_A_REJOIN")
		"WAIT_A_REJOIN":
			remote = _client.get_player("a")
			world = runtime.create_m3_graphical_client_report()
			if remote.is_empty() or not bool(remote.get("connected", false)):
				return
			if int(remote.get("ownership_epoch", 0)) < 2:
				return
			if int(world.get("remote_presenter_count", 0)) != 1:
				return
			var reconnect_peer_path := String(Support.read(_control_file).get("reconnect_peer_result_file", "")).strip_edges()
			if not reconnect_peer_path.is_empty():
				_peer_result_file = reconnect_peer_path
			_begin_convergence(world, shell)
		"WAIT_CONVERGENCE_PEER":
			if not _convergence_locked:
				var latest_player_checksum := String(_client.get_snapshot().get("checksum", ""))
				var latest_item_checksum := String(_client.get_item_graph_snapshot().get("checksum", ""))
				if (
					not latest_player_checksum.is_empty()
					and not latest_item_checksum.is_empty()
					and (latest_player_checksum != _player_checksum or latest_item_checksum != _item_checksum)
				):
					_player_checksum = latest_player_checksum
					_item_checksum = latest_item_checksum
					_convergence_world = runtime.create_m3_graphical_client_report()
					_write_report("READY_TO_CONVERGE", false, _convergence_world, shell)
				var peer_ready := Support.read(_peer_result_file)
				if String(peer_ready.get("state", "")) not in ["READY_TO_CONVERGE", "CONVERGENCE_LOCKED"]:
					return
				if String(peer_ready.get("player_checksum", "")) != _player_checksum:
					return
				if String(peer_ready.get("item_checksum", "")) != _item_checksum:
					return
				_convergence_locked = true
				_write_report("CONVERGENCE_LOCKED", false, _convergence_world, shell)
			var peer_convergence := Support.read(_peer_result_file)
			if String(peer_convergence.get("state", "")) not in ["CONVERGENCE_LOCKED", "COMPLETE"]:
				return
			if String(peer_convergence.get("player_checksum", "")) != _player_checksum:
				return
			if String(peer_convergence.get("item_checksum", "")) != _item_checksum:
				return
			if not bool(Support.read(_control_file).get("finish", false)):
				return
			_finish(true)


func _run_winner_ui_workflow(shell) -> Dictionary:
	var steps: Dictionary = {}
	steps["assign_hotbar"] = _ui_transfer(shell, "item/shared/beacon/1", "hotbar/%s" % _client_id, 2)
	if not _accepted(steps["assign_hotbar"]):
		return _failure("M5_HOTBAR_ASSIGNMENT_FAILED", steps)
	_wait_replica_after_command(shell)
	var before_open := _revision(shell)
	var open_click: Dictionary = shell.acceptance_activate_item("item/shared/crate/1")
	if not bool(open_click.get("success", false)):
		return _failure("M5_CONTAINER_OPEN_UI_FAILED", steps)
	_wait_revision(shell, before_open + 1)
	steps["open_container"] = shell.get_report().get("last_command_result", {})
	if not _accepted(steps["open_container"]):
		return _failure("M5_CONTAINER_OPEN_FAILED", steps)
	steps["to_container"] = _ui_transfer(shell, "item/shared/beacon/1", "container/shared/crate/1", 0)
	if not _accepted(steps["to_container"]):
		return _failure("M5_CONTAINER_TRANSFER_FAILED", steps)
	_wait_replica_after_command(shell)
	steps["to_inventory"] = _ui_transfer(shell, "item/shared/beacon/1", "inventory/%s" % _client_id, 0)
	if not _accepted(steps["to_inventory"]):
		return _failure("M5_CONTAINER_REVERSE_FAILED", steps)
	_wait_replica_after_command(shell)
	steps["mount"] = _ui_transfer(shell, "item/shared/beacon/1", "mounts/shared", 0)
	if not _accepted(steps["mount"]):
		return _failure("M5_MOUNT_FAILED", steps)
	_wait_replica_after_command(shell)
	var before_detach := _revision(shell)
	var detach_click: Dictionary = shell.acceptance_activate_item("item/shared/beacon/1")
	if not bool(detach_click.get("success", false)):
		return _failure("M5_DETACH_UI_FAILED", steps)
	_wait_revision(shell, before_detach + 1)
	steps["detach"] = shell.get_report().get("last_command_result", {})
	if not _accepted(steps["detach"]):
		return _failure("M5_DETACH_FAILED", steps)
	var select_click: Dictionary = shell.acceptance_click_item("item/shared/beacon/1")
	if not bool(select_click.get("success", false)):
		return _failure("M5_DROP_SELECTION_FAILED", steps)
	shell.acceptance_cancel_cursor()
	var before_drop := _revision(shell)
	steps["drop"] = shell.acceptance_press_drop_selected()
	if not _accepted(steps["drop"]):
		return _failure("M5_DROP_FAILED", steps)
	_wait_revision(shell, before_drop + 1)
	steps["repick"] = _ui_transfer(shell, "item/shared/beacon/1", "inventory/%s" % _client_id, 0)
	if not _accepted(steps["repick"]):
		return _failure("M5_REPICK_FAILED", steps)
	_wait_replica_after_command(shell)
	steps["restore_hotbar"] = _ui_transfer(shell, "item/shared/beacon/1", "hotbar/%s" % _client_id, 2)
	if not _accepted(steps["restore_hotbar"]):
		return _failure("M5_HOTBAR_RESTORE_FAILED", steps)
	_wait_replica_after_command(shell)
	var before_close := _revision(shell)
	steps["close_container"] = shell.acceptance_press_close_container()
	if not _accepted(steps["close_container"]):
		return _failure("M5_CONTAINER_CLOSE_FAILED", steps)
	_wait_revision(shell, before_close + 1)
	return _success({"steps": steps, "winner": _client_id})


func _ui_place_cursor(shell, target_container_id: String, target_slot_index: int) -> Dictionary:
	var before_revision := _revision(shell)
	var target_click: Dictionary = shell.acceptance_click_slot(target_container_id, target_slot_index)
	if not bool(target_click.get("success", false)):
		return target_click
	var result := Dictionary(shell.get_report().get("last_command_result", {})).duplicate(true)
	# Both clients must observe the authority-selected revision. The losing
	# command is still submitted even when the winning snapshot arrives first.
	_wait_revision(shell, before_revision + 1, 12000)
	return result


func _ui_transfer(shell, item_id: String, target_container_id: String, target_slot_index: int) -> Dictionary:
	var before_revision := _revision(shell)
	var source_click: Dictionary = shell.acceptance_click_item(item_id)
	if not bool(source_click.get("success", false)):
		return source_click
	var target_click: Dictionary = shell.acceptance_click_slot(target_container_id, target_slot_index)
	if not bool(target_click.get("success", false)):
		return target_click
	var result := Dictionary(shell.get_report().get("last_command_result", {})).duplicate(true)
	# A rejected contention command still waits for the winner snapshot so the
	# loser UI can prove deterministic rollback against the canonical revision.
	_wait_revision(shell, before_revision + 1, 12000)
	return result


func _wait_replica_after_command(_shell) -> void:
	# UI helpers wait for the authoritative replica revision before returning.
	pass


func _wait_revision(shell, target_revision: int, timeout_ms: int = 10000) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= timeout_ms:
		_client._poll_blocking_once()
		if _revision(shell) >= target_revision:
			return true
		OS.delay_msec(POLL_DELAY_MS)
	return false


func _revision(shell) -> int:
	return int(shell.get_report().get("bridge", {}).get("projection", {}).get("revision", -1))


func _accepted(value) -> bool:
	return value is Dictionary and bool(Dictionary(value).get("success", false))


func _verify_reconnect_state(shell) -> void:
	var ore: Dictionary = shell.bridge.find_cell("item/shared/ore/1")
	if String(ore.get("source_container_id", "")) != "inventory/a":
		_failures.append("Reconnect did not restore A inventory ore")
	if bool(shell.get_report().get("cursor_active", true)):
		_failures.append("Transient cursor survived reconnect")
	if _initial_ownership_epoch < 2:
		_failures.append("Reconnect ownership epoch did not advance")


func _begin_convergence(world: Dictionary, shell) -> void:
	_player_checksum = String(_client.get_snapshot().get("checksum", ""))
	_item_checksum = String(_client.get_item_graph_snapshot().get("checksum", ""))
	_convergence_world = world.duplicate(true)
	if _player_checksum.is_empty() or _item_checksum.is_empty():
		_failures.append("Convergence checksum is empty")
		_finish(false)
		return
	_write_report("READY_TO_CONVERGE", false, world, shell)
	_set_stage("WAIT_CONVERGENCE_PEER")


func _open_inventory_through_input(shell) -> void:
	if shell.is_inventory_visible():
		return
	var press := InputEventKey.new()
	press.physical_keycode = KEY_TAB
	press.keycode = KEY_TAB
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventKey.new()
	release.physical_keycode = KEY_TAB
	release.keycode = KEY_TAB
	release.pressed = false
	Input.parse_input_event(release)


func _validate_graphical_world(world: Dictionary, shell) -> void:
	if DisplayServer.get_name().to_lower() in ["", "headless", "dummy"]:
		_failures.append("Client is not graphical")
	if not bool(world.get("presentation_enabled", false)) or not bool(world.get("local_input_enabled", false)):
		_failures.append("Graphical composition is disabled")
	if String(world.get("active_camera", "")).is_empty():
		_failures.append("LunarPlayer camera is not active")
	if not bool(world.get("network_replica_mode", false)):
		_failures.append("Local player is not replica-driven")
	if int(world.get("remote_presenter_count", 0)) != 1:
		_failures.append("Remote presenter is missing")
	if int(shell.get_report().get("authority_references", 1)) != 0:
		_failures.append("UI shell has authority reference")
	if int(shell.get_report().get("domain_references", 1)) != 0:
		_failures.append("UI shell has domain reference")


func _runtime():
	return _app.get_current_runtime() if _app != null else null


func _shell(runtime):
	if runtime == null or not runtime.has_method("get_m5_inventory_shell"):
		return null
	return runtime.get_m5_inventory_shell()


func _set_stage(value: String) -> void:
	_stage = value
	_stage_started_ms = Time.get_ticks_msec()


func _release_input() -> void:
	if not _input_pressed:
		return
	for action in ["move_forward", "move_back", "move_left", "move_right", "boost"]:
		Input.action_release(action)
	_input_pressed = false


func failures_append(message: String) -> void:
	_failures.append(message)


func _fail(error_code: String, details: Dictionary = {}) -> void:
	_failures.append("%s: %s" % [error_code, details])
	_finish(false)


func _finish(passed: bool, final_state: String = "COMPLETE") -> void:
	if _finished:
		return
	_release_input()
	var runtime = _runtime()
	var shell = _shell(runtime)
	var world: Dictionary = (
		runtime.create_m3_graphical_client_report()
		if runtime != null and runtime.has_method("create_m3_graphical_client_report")
		else {}
	)
	if passed and not _convergence_world.is_empty():
		world = _convergence_world.duplicate(true)
	passed = passed and _failures.is_empty()
	_write_report(final_state if passed else "FAILED", passed, world, shell)
	var leave_result: Dictionary = _client.request_graceful_leave(4000)
	if not bool(leave_result.get("success", false)):
		_failures.append("Graceful leave failed: %s" % leave_result)
		passed = false
		_write_report("FAILED", false, world, shell, leave_result)
	_finished = true
	set_process(false)
	print("M5_GRAPHICAL_CLIENT_RESULT %s" % JSON.stringify(Support.read(_result_file)))
	if _app != null and _app.has_method("request_graceful_shutdown"):
		_app.request_graceful_shutdown("m5_graphical_acceptance_complete", 0 if passed else 1)
	else:
		get_tree().quit(0 if passed else 1)


func _write_report(
	state: String,
	passed: bool,
	world: Dictionary = {},
	shell = null,
	leave_result: Dictionary = {}
) -> void:
	var report := {
		"schema": Support.REPORT_SCHEMA,
		"checkpoint": Support.CHECKPOINT,
		"build_id": Support.BUILD_ID,
		"state": state,
		"passed": passed,
		"client_id": _client_id,
		"phase": _phase,
		"process_id": OS.get_process_id(),
		"display_server": DisplayServer.get_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"resolved_user_data_dir": OS.get_user_data_dir(),
		"initial_ownership_epoch": _initial_ownership_epoch,
		"movement_result": _movement_result.duplicate(true),
		"contention_result": _contention_result.duplicate(true),
		"winner_workflow": _winner_workflow.duplicate(true),
		"ore_pickup_result": _ore_pickup_result.duplicate(true),
		"screenshot": _screenshot_result.duplicate(true),
		"player_checksum": _player_checksum,
		"item_checksum": _item_checksum,
		"client_runtime": _client.get_report() if _client != null else {},
		"item_graph": _client.get_item_graph_snapshot() if _client != null else {},
		"world": world.duplicate(true),
		"ui": shell.get_report() if shell != null else {},
		"failures": _failures.duplicate(),
		"leave_result": leave_result.duplicate(true),
	}
	Support.write(_result_file, report)


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}

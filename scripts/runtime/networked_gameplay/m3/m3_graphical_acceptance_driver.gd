extends Node

const Support = preload("res://scripts/runtime/networked_gameplay/m3/m3_process_support.gd")

const SCHEMA := "planet_simulator.m3_graphical_acceptance_report.v1"
const TIMEOUT_MS := 90000

var _app
var _client
var _result_file := ""
var _peer_result_file := ""
var _client_id := ""
var _phase := 0
var _started_ms := 0
var _stage := "WAIT_READY"
var _move_result: Dictionary = {}
var _second_move_result: Dictionary = {}
var _presentation_result: Dictionary = {}
var _playground_item_result: Dictionary = {}
var _playground_item_verified := false
var _earth_item_result: Dictionary = {}
var _earth_item_verified := false
var _initial_ownership_epoch := 0
var _failures: Array[String] = []
var _finished := false
var _waiting_report_written := false
var _convergence_checksum := ""
var _convergence_world: Dictionary = {}

func setup(app_reference, client_runtime, config: Dictionary) -> Dictionary:
	if app_reference == null or client_runtime == null:
		return _failure("M3_ACCEPTANCE_RUNTIME_REQUIRED")
	_app = app_reference
	_client = client_runtime
	_result_file = String(config.get("result_file", "")).strip_edges()
	_peer_result_file = String(config.get("peer_result_file", "")).strip_edges()
	_client_id = String(config.get("client_id", "")).strip_edges().to_lower()
	_phase = int(config.get("phase", 0))
	if _result_file.is_empty() or _client_id not in ["a", "b"] or _phase not in [1, 2, 3]:
		return _failure("INVALID_M3_ACCEPTANCE_CONFIGURATION")
	_started_ms = Time.get_ticks_msec()
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	Support.write(_result_file, {"schema": SCHEMA, "checkpoint": Support.CHECKPOINT, "build_id": Support.BUILD_ID, "state": "DRIVER_READY", "passed": false, "client_id": _client_id, "phase": _phase, "process_id": OS.get_process_id()})
	print("M3_ACCEPTANCE_DRIVER_READY client=%s phase=%d" % [_client_id, _phase])
	return _success()

func _process(_delta: float) -> void:
	if _finished: return
	if Time.get_ticks_msec() - _started_ms > TIMEOUT_MS:
		_fail("M3_ACCEPTANCE_TIMEOUT", {"stage": _stage, "client": _client.get_report()}); return
	var runtime = _app.get_current_runtime() if _app != null else null
	if runtime == null or not runtime.has_method("create_m3_graphical_client_report") or not _client.is_ready(): return
	var snapshot: Dictionary = _client.get_snapshot()
	var local: Dictionary = _client.get_player(_client_id)
	var remote_id := "b" if _client_id == "a" else "a"
	var remote: Dictionary = _client.get_player(remote_id)
	var world: Dictionary = runtime.create_m3_graphical_client_report()
	match _stage:
		"WAIT_READY":
			if local.is_empty() or remote.is_empty() or not bool(remote.get("connected", false)): return
			if int(world.get("remote_presenter_count", 0)) != 1: return
			_validate_graphical_world(world)
			if not _failures.is_empty(): _finish(false); return
			if (
				String(world.get("world_id", "")) == "playground"
				and not _playground_item_verified
			):
				if not runtime.has_method("m4_execute_item_command"):
					_failures.append("Playground M4 item command adapter is missing")
					_finish(false)
					return
				_playground_item_result = runtime.m4_execute_item_command(
					"inventory.select_hotbar",
					{"selected_hotbar_index": _phase % 8},
					"operation/m4/playground/acceptance/%s/%d/%d"
					% [_client_id, _phase, OS.get_process_id()]
				)
				if not bool(_playground_item_result.get("success", false)):
					_failures.append(
						"Playground M4 item command failed: %s"
						% _playground_item_result
					)
					_finish(false)
					return
				_playground_item_verified = true
			if (
				String(world.get("world_id", "")) == "earth"
				and _client_id == "a"
				and _phase == 1
				and not _earth_item_verified
			):
				if not runtime.has_method("m4_execute_item_command"):
					_failures.append("Earth M4 item command adapter is missing")
					_finish(false)
					return
				_earth_item_result = runtime.m4_execute_item_command(
					"item.pickup",
					{"item_id": "item/shared/beacon/1"},
					"operation/m4/earth/acceptance/%s/%d/%d"
					% [_client_id, _phase, OS.get_process_id()]
				)
				if not bool(_earth_item_result.get("success", false)):
					_failures.append("Earth M4 pickup failed: %s" % _earth_item_result)
					_finish(false)
					return
				_earth_item_verified = true
			_initial_ownership_epoch = int(local.get("ownership_epoch", 0))
			if String(world.get("world_id", "")) == "earth":
				_stage = "WAIT_EARTH_ITEM_REPLICATION"
				return
			if _phase == 3:
				if _initial_ownership_epoch < 2: return
				if int(remote.get("last_input_sequence", 0)) < 2: return
				_move_result = runtime.m3_apply_test_input_offset(Vector3(0.5, 0.0, 0.5))
				_stage = "WAIT_RECONNECT_MOVE"
				return
			var offset := Vector3(0.8, 0.0, 0.2) if _client_id == "a" else Vector3(-0.7, 0.0, -0.3)
			_move_result = runtime.m3_apply_test_input_offset(offset)
			if not bool(_move_result.get("success", false)): _failures.append("Initial authoritative move failed: %s" % _move_result); _finish(false); return
			_stage = "WAIT_MUTUAL_MOVEMENT"
		"WAIT_EARTH_ITEM_REPLICATION":
			if int(world.get("m4_item_graph_revision", -1)) < 1:
				return
			if _phase == 3:
				if _initial_ownership_epoch < 2:
					return
				if int(remote.get("last_input_sequence", 0)) < 2:
					return
				_move_result = runtime.m3_apply_test_input_offset(Vector3(0.5, 0.0, 0.5))
				_stage = "WAIT_RECONNECT_MOVE"
				return
			var earth_offset := Vector3(0.8, 0.0, 0.2) if _client_id == "a" else Vector3(-0.7, 0.0, -0.3)
			_move_result = runtime.m3_apply_test_input_offset(earth_offset)
			if not bool(_move_result.get("success", false)):
				_failures.append("Earth initial authoritative move failed: %s" % _move_result)
				_finish(false)
				return
			_stage = "WAIT_MUTUAL_MOVEMENT"
		"WAIT_MUTUAL_MOVEMENT":
			if int(local.get("last_input_sequence", 0)) < 1 or int(remote.get("last_input_sequence", 0)) < 1: return
			if int(world.get("remote_update_count", 0)) < 2: return
			if _client_id == "a":
				_presentation_result = _client.set_presentation_blocking(float(local.get("orientation_yaw", 0.0)), true)
				if not bool(_presentation_result.get("success", false)): _failures.append("A presentation update failed: %s" % _presentation_result); _finish(false); return
				_stage = "WAIT_LOCAL_PRESENTATION"
			else:
				_stage = "WAIT_REMOTE_PRESENTATION"
		"WAIT_LOCAL_PRESENTATION":
			local = _client.get_player(_client_id)
			if not bool(local.get("flashlight_enabled", false)): return
			_write_report("WAITING_PRESENTATION_PEER", false, world)
			_stage = "WAIT_REMOTE_PRESENTATION_ACK"
		"WAIT_REMOTE_PRESENTATION_ACK":
			var presentation_peer := _read_json(_peer_result_file)
			if String(presentation_peer.get("state", "")) != "PRESENTATION_OBSERVED": return
			_finish(true)
		"WAIT_REMOTE_PRESENTATION":
			remote = _client.get_player(remote_id)
			if not bool(remote.get("flashlight_enabled", false)): return
			world = runtime.create_m3_graphical_client_report()
			var presenters: Dictionary = world.get("remote_presenters", {})
			if not bool(Dictionary(presenters.get(remote_id, {})).get("flashlight_enabled", false)): return
			_write_report("PRESENTATION_OBSERVED", false, world)
			_stage = "WAIT_A_LEFT"
		"WAIT_A_LEFT":
			if remote.is_empty() or bool(remote.get("connected", true)): return
			if int(world.get("remote_presenter_count", -1)) != 0: return
			if int(world.get("remote_despawn_count", 0)) < 1: return
			_second_move_result = runtime.m3_apply_test_input_offset(Vector3(0.0, 0.0, 0.9))
			if not bool(_second_move_result.get("success", false)): _failures.append("B continuation move failed: %s" % _second_move_result); _finish(false); return
			_stage = "WAIT_B_CONTINUED"
		"WAIT_B_CONTINUED":
			if int(local.get("last_input_sequence", 0)) < 2: return
			if not _waiting_report_written:
				_write_report("WAITING_RECONNECT", false, world)
				_waiting_report_written = true
			_stage = "WAIT_A_REJOIN"
		"WAIT_A_REJOIN":
			if remote.is_empty() or not bool(remote.get("connected", false)): return
			if int(remote.get("ownership_epoch", 0)) < 2 or int(remote.get("last_input_sequence", 0)) < 2: return
			if int(world.get("remote_presenter_count", 0)) != 1 or int(world.get("remote_spawn_count", 0)) < 2: return
			_begin_convergence(world)
		"WAIT_RECONNECT_MOVE":
			if not bool(_move_result.get("success", false)): _failures.append("A reconnect move failed: %s" % _move_result); _finish(false); return
			local = _client.get_player(_client_id)
			if int(local.get("last_input_sequence", 0)) < 2: return
			if int(world.get("remote_presenter_count", 0)) != 1: return
			_begin_convergence(world)
		"WAIT_CONVERGENCE_PEER":
			var peer_report := _read_json(_peer_result_file)
			if String(peer_report.get("state", "")) not in ["READY_TO_CONVERGE", "COMPLETE"]: return
			var peer_checksum := String(peer_report.get("convergence_checksum", ""))
			if peer_checksum.is_empty() or peer_checksum != _convergence_checksum: return
			_finish(true)

func _begin_convergence(world: Dictionary) -> void:
	_convergence_checksum = String(_client.get_snapshot().get("checksum", ""))
	_convergence_world = world.duplicate(true)
	if _convergence_checksum.is_empty():
		_failures.append("Convergence checksum is empty")
		_finish(false)
		return
	_write_report("READY_TO_CONVERGE", false, world, _convergence_checksum)
	_stage = "WAIT_CONVERGENCE_PEER"

func _validate_graphical_world(world: Dictionary) -> void:
	if DisplayServer.get_name().to_lower() in ["headless", "dummy"]: _failures.append("Client is not graphical")
	if not bool(world.get("presentation_enabled", false)) or not bool(world.get("local_input_enabled", false)): _failures.append("Graphical composition disabled")
	if String(world.get("active_camera", "")).is_empty(): _failures.append("LunarPlayer camera is not active")
	if not bool(world.get("network_replica_mode", false)): _failures.append("Local player is not replica-driven")
	var presenters: Dictionary = world.get("remote_presenters", {})
	for presenter_value in presenters.values():
		if bool(Dictionary(presenter_value).get("input_authority", true)): _failures.append("Remote presentation has input authority")

func _finish(passed: bool) -> void:
	if _finished: return
	var runtime = _app.get_current_runtime() if _app != null else null
	var world: Dictionary = runtime.create_m3_graphical_client_report() if runtime != null and runtime.has_method("create_m3_graphical_client_report") else {}
	if passed and not _convergence_world.is_empty():
		world = _convergence_world.duplicate(true)
	passed = passed and _failures.is_empty()
	var convergence_checksum := _convergence_checksum if not _convergence_checksum.is_empty() else String(_client.get_snapshot().get("checksum", ""))
	_write_report("COMPLETE" if passed else "FAILED", passed, world, convergence_checksum)
	var leave_result: Dictionary = _client.request_graceful_leave(3000)
	if not bool(leave_result.get("success", false)):
		_failures.append("Graceful leave failed: %s" % leave_result)
		passed = false
		_write_report("FAILED", false, world, convergence_checksum, leave_result)
	_finished = true; set_process(false)
	print("M3_GRAPHICAL_CLIENT_RESULT %s" % JSON.stringify(_read_json(_result_file)))
	if _app != null and _app.has_method("request_graceful_shutdown"):
		_app.request_graceful_shutdown("m3_graphical_acceptance_complete", 0 if passed else 1)
	else: get_tree().quit(0 if passed else 1)

func _write_report(state: String, passed: bool, world: Dictionary, checksum: String = "", leave_result: Dictionary = {}) -> void:
	Support.write(_result_file, {
		"schema": SCHEMA, "checkpoint": Support.CHECKPOINT, "build_id": Support.BUILD_ID,
		"state": state, "passed": passed, "client_id": _client_id, "phase": _phase,
		"display_server": DisplayServer.get_name(),
		"rendering_method": String(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
		"client_runtime": _client.get_report(), "world": world.duplicate(true),
		"move_result": _move_result.duplicate(true), "second_move_result": _second_move_result.duplicate(true),
		"presentation_result": _presentation_result.duplicate(true),
		"playground_item_result": _playground_item_result.duplicate(true),
		"earth_item_result": _earth_item_result.duplicate(true),
		"initial_ownership_epoch": _initial_ownership_epoch,
		"convergence_checksum": checksum if not checksum.is_empty() else String(_client.get_snapshot().get("checksum", "")),
		"leave_result": leave_result.duplicate(true), "failures": _failures.duplicate(),
		"process_id": OS.get_process_id(), "resolved_user_data_dir": OS.get_user_data_dir(),
	})

func _fail(code: String, details: Dictionary = {}) -> void:
	_failures.append("%s: %s" % [code, details]); _finish(false)
func _read_json(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var parsed = JSON.parse_string(file.get_as_text()); file.close()
	return Dictionary(parsed) if parsed is Dictionary else {}
func _success(details: Dictionary = {}) -> Dictionary: return {"success": true, "error_code": "", "details": details.duplicate(true)}
func _failure(error_code: String) -> Dictionary: return {"success": false, "error_code": error_code, "details": {}}

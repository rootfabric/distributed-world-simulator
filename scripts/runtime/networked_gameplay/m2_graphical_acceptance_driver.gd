extends Node

const Support = preload("res://scripts/runtime/networked_gameplay/transports/m2_process_support.gd")
const StateCodec = preload("res://scripts/runtime/listen_host/playable_state_codec.gd")

const SCHEMA: String = "planet_simulator.m2_graphical_acceptance_report.v1"
const TIMEOUT_MS: int = 30000

var _app
var _client_runtime
var _result_file: String = ""
var _expected_state_file: String = ""
var _phase: int = 0
var _started_ms: int = 0
var _stage: String = "WAIT_READY"
var _sync_count_before: int = 0
var _initial_report: Dictionary = {}
var _movement_request: Dictionary = {}
var _inventory_result: Dictionary = {}
var _expected_report: Dictionary = {}
var _finished: bool = false
var _failures: Array[String] = []


func setup(app_reference, client_runtime_reference, config: Dictionary) -> Dictionary:
	if app_reference == null or client_runtime_reference == null:
		return _failure("M2_ACCEPTANCE_RUNTIME_REQUIRED")
	_result_file = String(config.get("result_file", "")).strip_edges()
	_expected_state_file = String(config.get("expected_state_file", "")).strip_edges()
	_phase = int(config.get("phase", 0))
	if _result_file.is_empty() or _phase not in [1, 2]:
		return _failure("INVALID_M2_ACCEPTANCE_CONFIGURATION")
	_app = app_reference
	_client_runtime = client_runtime_reference
	_started_ms = Time.get_ticks_msec()
	_expected_report = _read_json(_expected_state_file) if not _expected_state_file.is_empty() else {}
	set_process(true)
	return _success()


func _process(_delta: float) -> void:
	if _finished:
		return
	if Time.get_ticks_msec() - _started_ms > TIMEOUT_MS:
		_fail("M2_ACCEPTANCE_TIMEOUT", {"stage": _stage})
		return
	var runtime = _app.get_current_runtime() if _app != null else null
	if runtime == null or not runtime.has_method("create_m2_graphical_client_report"):
		return
	match _stage:
		"WAIT_READY":
			if not _client_runtime.is_ready():
				return
			var report: Dictionary = runtime.create_m2_graphical_client_report()
			if not bool(report.get("attached", false)):
				return
			_initial_report = report.duplicate(true)
			_validate_graphical_ready(report)
			if not _failures.is_empty():
				_finish(false)
				return
			if _phase == 2:
				_validate_reconnect_state(report)
				if not _failures.is_empty():
					_finish(false)
					return
			_sync_count_before = int(report.get("player_sync_count", 0))
			var offset := Vector3(0.05, 0.0, 0.0) if _phase == 1 else Vector3(0.0, 0.0, 0.04)
			_movement_request = runtime.m2_apply_test_input_offset(offset)
			if not bool(_movement_request.get("success", false)):
				_failures.append("M2 movement candidate was rejected")
				_finish(false)
				return
			_stage = "WAIT_MOVEMENT"
		"WAIT_MOVEMENT":
			var report: Dictionary = runtime.create_m2_graphical_client_report()
			if int(report.get("player_rejection_count", 0)) > 0:
				_failures.append("Authoritative movement produced a rejection")
				_finish(false)
				return
			if int(report.get("player_sync_count", 0)) <= _sync_count_before:
				return
			var hotbar_index: int = 1 if _phase == 1 else 2
			_inventory_result = runtime.m2_open_inventory_and_select_hotbar(hotbar_index)
			if not bool(_inventory_result.get("success", false)):
				_failures.append("Replica inventory/hotbar command failed: %s" % _inventory_result)
				_finish(false)
				return
			_stage = "FINALIZE"
		"FINALIZE":
			_finish(true)


func _validate_graphical_ready(report: Dictionary) -> void:
	var display_name: String = DisplayServer.get_name().to_lower()
	if display_name in ["headless", "dummy"]:
		_failures.append("Client did not run through a graphical display server: %s" % display_name)
	if not bool(report.get("presentation_enabled", false)):
		_failures.append("Graphical presentation is disabled")
	if not bool(report.get("local_input_enabled", false)):
		_failures.append("Graphical local input is disabled")
	if String(report.get("item_controller_mode", "")) != "replica":
		_failures.append("Inventory is not driven by replica state")
	if Dictionary(report.get("player_snapshot", {})).is_empty():
		_failures.append("Player replica snapshot is missing")
	if Dictionary(report.get("item_snapshot", {})).is_empty():
		_failures.append("Item Graph replica snapshot is missing")
	if String(report.get("active_camera", "")).is_empty():
		_failures.append("Real LunarPlayer camera is not active")
	var client_report: Dictionary = _client_runtime.get_report()
	if String(client_report.get("player_entity_id", "")) != "player/local-astronaut":
		_failures.append("Stable player entity identity was not assigned")
	if int(client_report.get("ownership_epoch", 0)) < 1:
		_failures.append("Ownership handshake did not complete")
	if int(client_report.get("direct_authority_references", 1)) != 0:
		_failures.append("Graphical client exposes an authority reference")


func _validate_reconnect_state(report: Dictionary) -> void:
	if _expected_report.is_empty():
		_failures.append("Reconnect phase has no previous client report")
		return
	var previous_client: Dictionary = Dictionary(_expected_report.get("client_runtime", {}))
	var current_client: Dictionary = _client_runtime.get_report()
	if String(previous_client.get("player_entity_id", "")) != String(current_client.get("player_entity_id", "")):
		_failures.append("Reconnect changed player entity identity")
	if int(current_client.get("ownership_epoch", 0)) <= int(previous_client.get("ownership_epoch", 0)):
		_failures.append("Reconnect did not advance ownership epoch")
	var previous_world: Dictionary = Dictionary(_expected_report.get("world", {}))
	var previous_snapshot: Dictionary = Dictionary(previous_world.get("player_snapshot", {}))
	var current_snapshot: Dictionary = Dictionary(report.get("player_snapshot", {}))
	var previous_state = previous_snapshot.get("domain_components", {}).get("player_state", {})
	var current_state = current_snapshot.get("domain_components", {}).get("player_state", {})
	if previous_state is Dictionary and current_state is Dictionary:
		var previous_position: Vector3 = StateCodec.player_position(Dictionary(previous_state))
		var current_position: Vector3 = StateCodec.player_position(Dictionary(current_state))
		if previous_position.distance_to(current_position) > 0.05:
			_failures.append("Reconnect did not restore authoritative player state")
	else:
		_failures.append("Reconnect player state snapshot is invalid")


func _finish(passed: bool) -> void:
	if _finished:
		return
	var runtime = _app.get_current_runtime() if _app != null else null
	var world_report: Dictionary = (
		runtime.create_m2_graphical_client_report()
		if runtime != null and runtime.has_method("create_m2_graphical_client_report")
		else {}
	)
	if passed:
		if not bool(_inventory_result.get("inventory_open", false)):
			_failures.append("Replicated inventory did not open")
		var expected_hotbar_index: int = 1 if _phase == 1 else 2
		if int(_inventory_result.get("selected_hotbar_index", -1)) != expected_hotbar_index:
			_failures.append("Replicated hotbar selection did not converge")
		if String(_inventory_result.get("runtime_mode", "")) != "replica":
			_failures.append("Hotbar command bypassed replica runtime")
	passed = passed and _failures.is_empty()
	var leave_result: Dictionary = _client_runtime.request_graceful_leave(2500)
	if not bool(leave_result.get("success", false)):
		_failures.append("Graceful client leave failed: %s" % leave_result)
		passed = false
	var report: Dictionary = {
		"schema": SCHEMA,
		"checkpoint": Support.CHECKPOINT,
		"build_id": Support.BUILD_ID,
		"state": "COMPLETE" if passed else "FAILED",
		"passed": passed,
		"phase": _phase,
		"display_server": DisplayServer.get_name(),
		"rendering_method": String(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
		"rendering_device_available": RenderingServer.get_rendering_device() != null,
		"initial_world": _initial_report.duplicate(true),
		"world": world_report.duplicate(true),
		"movement_request": _movement_request.duplicate(true),
		"inventory_result": _inventory_result.duplicate(true),
		"client_runtime": _client_runtime.get_report(),
		"leave_result": leave_result.duplicate(true),
		"failures": _failures.duplicate(),
		"process_id": OS.get_process_id(),
		"resolved_user_data_dir": OS.get_user_data_dir(),
	}
	Support.write(_result_file, report)
	_finished = true
	set_process(false)
	print("M2_GRAPHICAL_CLIENT_RESULT %s" % JSON.stringify(report))
	if _app != null and _app.has_method("request_graceful_shutdown"):
		_app.request_graceful_shutdown("m2_graphical_acceptance_complete", 0 if passed else 1)
	else:
		get_tree().quit(0 if passed else 1)


func _fail(error_code: String, details: Dictionary = {}) -> void:
	_failures.append("%s: %s" % [error_code, details])
	_finish(false)


func _read_json(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return Dictionary(parsed) if parsed is Dictionary else {}


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}

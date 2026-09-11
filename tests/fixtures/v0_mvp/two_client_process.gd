extends SceneTree

# Test-only orchestration. Control files carry input actions/barriers, NEVER peer state.
const Scene = preload("res://scenes/labs/mvp/v0_mvp_two_client_shared_world.tscn")
const ACTIONS: Array[String] = ["mvp2_left", "mvp2_right", "mvp2_forward", "mvp2_back", "mvp2_sprint", "mvp2_jump", "mvp2_flashlight"]
var _app = null
var _control := ""
var _output := ""
var _screenshot := ""
var _nonce := ""
var _sequence := 0
var _started := 0
var _last_report := 0
var _capture_pending := false
var _capture: Dictionary = {}
var _hidden: Array[Node3D] = []
var _finished := false


func _initialize() -> void:
	_control = OS.get_environment("DWS_MVP2_FIXTURE_CONTROL")
	_output = OS.get_environment("DWS_MVP2_FIXTURE_OUTPUT")
	_screenshot = OS.get_environment("DWS_MVP2_FIXTURE_SCREENSHOT")
	_nonce = OS.get_environment("DWS_MVP2_FIXTURE_NONCE")
	_started = Time.get_ticks_msec()
	call_deferred("_start")


func _start() -> void:
	if _control.is_empty() or _output.is_empty() or _nonce.is_empty():
		_fail("MVP2_FIXTURE_PATHS_AND_NONCE_REQUIRED")
		return
	_app = Scene.instantiate()
	root.add_child(_app)
	current_scene = _app
	_app.set_input_active(false)
	_write("RUNNING")


func _process(_delta: float) -> bool:
	if _finished or _app == null:
		return false
	if Time.get_ticks_msec() - _started > 120000:
		_fail("MVP2_FIXTURE_TIMEOUT")
		return false
	if FileAccess.file_exists(_control):
		var file := FileAccess.open(_control, FileAccess.READ)
		if file != null:
			var text := file.get_as_text()
			file.close()
			var value = JSON.parse_string(text)
			if value is Dictionary and int(value.get("sequence", 0)) > _sequence:
				if String(value.get("nonce", "")) != _nonce:
					_fail("MVP2_FIXTURE_FOREIGN_CONTROL")
					return false
				_sequence = int(value["sequence"])
				_apply_control(value)
	if not _finished and Time.get_ticks_msec() - _last_report >= 100:
		_write("RUNNING")
	return false


func _apply_control(control: Dictionary) -> void:
	var kind := String(control.get("kind", ""))
	match kind:
		"keys", "neutral":
			for action in ACTIONS:
				if InputMap.has_action(action):
					Input.action_release(action)
			var keys: Array = control.get("actions", []) if kind == "keys" else []
			for key_value in keys:
				var action := String(key_value)
				if action not in ACTIONS:
					_fail("MVP2_FIXTURE_UNKNOWN_ACTION")
					return
				Input.action_press(action)
			_app.set_input_active(kind == "keys")
		"hide_remote":
			_hidden.clear()
			for node in _app.get_children():
				if node is Node3D and String(node.name).begins_with("RemotePlayer_"):
					node.hide()
					_hidden.append(node)
		"restore_remote":
			for node in _hidden:
				if is_instance_valid(node):
					node.show()
			_hidden.clear()
		"capture":
			if not _capture_pending:
				_capture_frame()
		"stop":
			_finished = true
			var before: Dictionary = _app.observation()
			var stopped: Dictionary = _app.stop_session()
			_write("STOPPED", {"before_stop": before, "stop_result": stopped})
			print("MVP2_FIXTURE_STOPPED pid=%d success=%s" % [OS.get_process_id(), stopped.get("success", false)])
			quit(0 if bool(stopped.get("success", false)) else 6)
		_:
			_fail("MVP2_FIXTURE_UNKNOWN_CONTROL")


func _capture_frame() -> void:
	if DisplayServer.get_name().to_lower() in ["headless", "dummy"] or _screenshot.is_empty():
		_fail("MVP2_GRAPHICAL_CAPTURE_REQUIRED")
		return
	_capture_pending = true
	await RenderingServer.frame_post_draw
	if _finished:
		return
	var image: Image = root.get_texture().get_image()
	var error := image.save_png(_screenshot)
	if error != OK:
		_fail("MVP2_CAPTURE_WRITE_FAILED:%d" % error)
		return
	_capture = {
		"path": _screenshot, "sha256": FileAccess.get_sha256(_screenshot),
		"width": image.get_width(), "height": image.get_height(),
		"source": "IN_ENGINE_VIEWPORT_NOT_DESKTOP", "control_sequence": _sequence,
	}
	_capture_pending = false
	_write("RUNNING")


func _write(state: String, extra: Dictionary = {}) -> void:
	if _output.is_empty():
		return
	var record := {
		"schema": "distributed_world_simulator.mvp2_process_observation.v1",
		"nonce": _nonce, "state": state, "process_id": OS.get_process_id(),
		"control_sequence": _sequence, "capture": _capture.duplicate(true),
		"observation": _app.observation() if _app != null else {},
		"extra": extra,
	}
	var file := FileAccess.open(_output, FileAccess.WRITE)
	if file == null:
		push_error("MVP2_FIXTURE_REPORT_WRITE_FAILED")
		_finished = true
		quit(7)
		return
	file.store_string(JSON.stringify(record, "", true, true) + "\n")
	file.close()
	_last_report = Time.get_ticks_msec()


func _fail(code: String) -> void:
	_finished = true
	_write("FAILED", {"error": code})
	push_error(code)
	if _app != null:
		_app.stop_session()
	quit(8)

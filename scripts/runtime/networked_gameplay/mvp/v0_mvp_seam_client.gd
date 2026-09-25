extends Node3D

# Interactive bounded SM1 projection. The accepted remote workers remain owners.
# This operator/observer adapter is NOT the completed two-M3-player composition.
const Support = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")
const Continuity = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp_seam_continuity.gd")
const Surface = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp_bootstrap_surface.gd")
const PEER := "peer/enet/mvp3/gateway"
const SCENE_PATH := "res://scenes/labs/mvp/v0_mvp_seam_shared_scene.tscn"
const OPTIONS := {
	"host": {"kind": "string", "default": "127.0.0.1"},
	"port": {"kind": "int", "default": 0, "required": true},
	"client-id": {"kind": "string", "default": "", "required": true},
	"result-file": {"kind": "string", "default": "", "required": true},
	"subject-head": {"kind": "string", "default": "", "required": true},
	"run-id": {"kind": "string", "default": "", "required": true},
	"timeout-ms": {"kind": "int", "default": 180000},
}

var _options: Dictionary = {}
var _guard = Continuity.new()
var _boundary = null
var _body: MeshInstance3D
var _camera: Camera3D
var _surface: Node3D
var _hud: Label
var _body_id := 0
var _camera_id := 0
var _transport_session := ""
var _hello := false
var _started := false
var _finished := false
var _finishing_route := false
var _manual_input := true
var _request := ""
var _sequence := 0
var _command_results := 0
var _request_ms := 0
var _next_input_ms := 0
var _started_ms := 0
var _last_error := ""
var _command_receipts: Array[Dictionary] = []


func _ready() -> void:
	var parsed: Dictionary = Support.parse_options(OS.get_cmdline_user_args(), OPTIONS)
	_options = parsed.get("options", {})
	if not bool(parsed.get("success", false)):
		_finish(false, "INVALID_OPTIONS")
		return
	if _options["client-id"] not in ["a", "b"] or _options["host"] != "127.0.0.1" or int(_options["port"]) > 65535:
		_finish(false, "BOUNDED_LOOPBACK_ENDPOINT_REQUIRED")
		return
	var regex := RegEx.new()
	regex.compile("^[0-9a-f]{40}$")
	if regex.search(str(_options["subject-head"])) == null:
		_finish(false, "EXACT_HEAD_REQUIRED")
		return
	if DisplayServer.get_name().to_lower() in ["", "headless", "dummy"]:
		_finish(false, "GRAPHICAL_DISPLAY_REQUIRED")
		return
	var expected := Support.canonical_state()
	expected["gateway_endpoint_id"] = Support.GATEWAY_ENDPOINT_ID
	if not _guard.configure(expected).success:
		_finish(false, "IDENTITY_CONFIGURATION_FAILED")
		return
	_build_view()
	_surface = Surface.new()
	add_child(_surface)
	var surface_result: Dictionary = _surface.configure(true)
	if not bool(surface_result.get("success", false)):
		_finish(false, "BOOTSTRAP_SURFACE_FAILED")
		return
	_boundary = Support.make_boundary()
	if _boundary == null:
		_finish(false, "TRANSPORT_CONFIGURATION_FAILED")
		return
	_transport_session = "transport-session/mvp3/%s/%s" % [_options["run-id"], _options["client-id"]]
	var connected: Dictionary = _boundary.connect_client(Support.endpoint(_options["host"], _options["port"]), PEER, _transport_session, "route/mvp3/" + str(_options["client-id"]), 1)
	if not bool(connected.get("success", false)):
		_finish(false, "CONNECT_FAILED")
		return
	_started_ms = Time.get_ticks_msec()
	get_tree().auto_accept_quit = false
	get_window().title = "MVP3 seam — " + ("operator A" if _options["client-id"] == "a" else "observer B")
	Support.write_state(_options["result-file"], "CONNECTING", {"subject_head": _options["subject-head"], "run_id": _options["run-id"]})


func set_manual_input_enabled(enabled: bool) -> void:
	_manual_input = enabled


func submit_axis(axis: float) -> bool:
	# One in-flight input, 20 Hz ceiling, no accumulated input replay after handoff.
	if not is_finite(axis) or not _started or _finished or _finishing_route or _options.get("client-id") != "a" or not _request.is_empty() or Time.get_ticks_msec() < _next_input_ms:
		return false
	if absf(axis) < 0.5:
		return false
	if _sequence >= 240:
		_finish(false, "BOUNDED_INPUT_BUDGET_EXCEEDED")
		return false
	_next_input_ms = Time.get_ticks_msec() + 50
	return _send_command("MOVE", signf(axis) * Continuity.MAX_STEP_M, false)


func finish_route() -> bool:
	if _finished or _finishing_route or not _request.is_empty() or _options.get("client-id") != "a":
		return false
	if not bool(_guard.report().get("goal_reached", false)):
		return false
	_finishing_route = true
	return _send_command("ACTION", 0.0, true)


func observation() -> Dictionary:
	return {"started": _started, "finished": _finished, "client_id": _options.get("client-id", ""), "pending": not _request.is_empty(), "continuity": _guard.report()}


func _process(_delta: float) -> void:
	if _finished or _boundary == null:
		return
	var polled: Dictionary = _boundary.poll_events(128)
	if not bool(polled.get("success", false)):
		_finish(false, "TRANSPORT_POLL_FAILED")
		return
	for raw in polled.get("details", {}).get("events", []):
		if _finished:
			return
		var event: Dictionary = raw
		var event_type: String = str(event.get("event_type", ""))
		if event_type in ["PEER_CONNECTED", "PEER_DISCONNECTED"]:
			if not _guard.note_transport(event_type).success:
				_finish(false, "TRANSPORT_CONTINUITY_FAILED")
				return
			if not Support.mark_ready(_boundary, PEER):
				_finish(false, "TRANSPORT_NOT_READY")
				return
		elif event_type == "MESSAGE_RECEIVED":
			_handle(Support.payload_from_event(event))
	if _finished:
		return
	if not _hello and _boundary.get_peer_snapshot(PEER).get("state") == "READY":
		_hello = true
		var sent: Dictionary = Support.send(_boundary, PEER, {"type": "HELLO", "client_id": _options["client-id"]})
		if not bool(sent.get("success", false)):
			_finish(false, "HELLO_SEND_FAILED")
			return
	if _manual_input:
		var axis := 0.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			axis += 1.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			axis -= 1.0
		submit_axis(axis)
		if Input.is_key_pressed(KEY_ESCAPE):
			finish_route()
	_boundary.flush_outbound(128)
	if not _request.is_empty() and Time.get_ticks_msec() - _request_ms > 5000:
		_finish(false, "COMMAND_TIMEOUT_NO_RETRY")
	elif Time.get_ticks_msec() - _started_ms > int(_options["timeout-ms"]):
		_finish(false, "SCENE_TIMEOUT")
	_update_hud()


func _handle(payload: Dictionary) -> void:
	match str(payload.get("type", "")):
		"START":
			if _started or payload.get("gateway_endpoint_id") != Support.GATEWAY_ENDPOINT_ID or payload.get("product_session_id") != Support.PRODUCT_SESSION_ID or payload.get("active_authority_id") != Support.AUTHORITY_A or int(payload.get("authority_epoch", 0)) != 1:
				_finish(false, "INVALID_OR_DUPLICATE_START")
				return
			_started = true
			if _options["client-id"] == "a":
				_send_command("ACTION", 0.0, false)
		"STATE":
			if not _started or not _guard.accept_state(payload).success:
				_finish(false, "STATE_CONTINUITY_FAILED")
				return
			if _body.get_instance_id() != _body_id or _camera.get_instance_id() != _camera_id:
				_finish(false, "PRESENTATION_INSTANCE_CHANGED")
				return
			# Read only the receipt that passed validation, never the unvalidated payload.
			var last: Dictionary = _guard.report()["last_state"]
			_body.position = Vector3(float(last["position_x"]) - 5.0, 1.0, 0.0)
			_body.visible = true
		"COMMAND_RESULT":
			if _request.is_empty() or payload.get("request_id") != _request or not bool(payload.get("success", false)):
				_finish(false, "COMMAND_CORRELATION_OR_EXECUTION_FAILED")
				return
			var receipt: Dictionary = _guard.report()
			if int(payload.get("world_revision", -1)) != int(receipt["last_state"].get("world_revision", -2)) or int(payload.get("authority_epoch", -1)) != int(receipt["epochs"].back()) or payload.get("active_authority_id") != receipt["route_history"].back():
				_finish(false, "ACK_WITHOUT_MATCHING_OBSERVATION")
				return
			_command_receipts.append({"request_id": _request, "sequence": _sequence, "revision": payload["world_revision"], "authority_epoch": payload["authority_epoch"]})
			_command_results += 1
			_request = ""
		"COMPLETE":
			var receipt: Dictionary = _guard.report()
			var complete: bool = _started and _request.is_empty() and bool(receipt["goal_reached"]) and payload.get("gateway_endpoint_id") == Support.GATEWAY_ENDPOINT_ID and int(payload.get("authority_epoch", 0)) == 3 and payload.get("active_authority_id") == Support.AUTHORITY_A and int(payload.get("world_revision", -1)) == int(receipt["last_state"].get("world_revision", -2))
			_finish(complete, "" if complete else "PREMATURE_OR_MISMATCHED_COMPLETION")
		"ERROR":
			_finish(false, str(payload.get("error_code", "GATEWAY_ERROR")))
		_:
			_finish(false, "UNEXPECTED_MESSAGE")


func _send_command(kind: String, delta_x: float, final_command: bool) -> bool:
	_sequence += 1
	_request = "mvp3/%s/%d" % [_options["run-id"], _sequence]
	_request_ms = Time.get_ticks_msec()
	# This is the existing SM1 worker's explicit terminal test operation, not a route spoof.
	var operation: String = "operation/sm1/graphical/5" if final_command else "operation/" + _request
	var sent: Dictionary = Support.send(_boundary, PEER, {"type": "EXECUTE", "request_id": _request, "operation_id": operation, "input_sequence": _sequence, "command_kind": kind, "delta_x": delta_x})
	if not bool(sent.get("success", false)):
		_finish(false, "COMMAND_SEND_FAILED")
		return false
	return true


func _build_view() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.015, 0.02, 0.04)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.7, 0.72, 0.78)
	settings.ambient_light_energy = 0.8
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, -25.0, 0.0)
	add_child(sun)
	_body = MeshInstance3D.new()
	_body.name = "StableCanonicalPlayerProjection"
	var capsule := CapsuleMesh.new()
	capsule.height = 1.8
	capsule.radius = 0.4
	_body.mesh = capsule
	_body.visible = false
	add_child(_body)
	_body_id = _body.get_instance_id()
	_camera = Camera3D.new()
	_camera.name = "StableMVP3Camera"
	_camera.position = Vector3(0.0, 8.0, 14.0)
	add_child(_camera)
	_camera.look_at(Vector3.ZERO)
	_camera.make_current()
	_camera_id = _camera.get_instance_id()
	for entry in [[-5.0, "A return boundary: x = 0"], [5.0, "B entry boundary: x = 10"]]:
		var marker := Label3D.new()
		marker.text = str(entry[1])
		marker.position = Vector3(float(entry[0]), 2.8, 0.0)
		marker.font_size = 36
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(marker)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_hud = Label.new()
	_hud.position = Vector2(16, 16)
	_hud.add_theme_font_size_override("font_size", 18)
	canvas.add_child(_hud)


func _update_hud() -> void:
	if _hud == null:
		return
	var receipt: Dictionary = _guard.report()
	_hud.text = "MVP3 seam subgate | " + str(_options.get("client-id", "")) + "\nA/D or arrows: move | cross x=10, then return below x=0 | Esc: finish\n"
	_hud.text += "route: %s | epochs: %s\nconnections: %d | disconnects: %d | post-return movement: %d\n" % [str(receipt["route_history"]), str(receipt["epochs"]), receipt["connect_count"], receipt["disconnect_count"], int(receipt["movement_steps_by_epoch"].get("3", 0))]
	_hud.text += "Single canonical SM1 actor; B is observer. Two-M3-player integration is NOT accepted."


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not _finished:
		_finish(false, "USER_CANCELLED_NOT_ACCEPTED")


func _finish(passed: bool, error_code: String) -> void:
	if _finished:
		return
	_finished = true
	_last_error = error_code
	var report := {
		"schema": "distributed_world_simulator.mvp3_seam_client_subgate.v1",
		"state": "COMPLETE" if passed else "FAILED", "passed": passed, "error": error_code,
		"subject_head": _options.get("subject-head", ""), "run_id": _options.get("run-id", ""),
		"scene_path": SCENE_PATH, "client_id": _options.get("client-id", ""),
		"process_id": OS.get_process_id(), "user_data_dir": OS.get_user_data_dir(),
		"display_server": DisplayServer.get_name(), "transport_session_id": _transport_session,
		"connect_attempts": 1 if _boundary != null else 0,
		"body_instance_first": _body_id, "body_instance_last": _body.get_instance_id() if is_instance_valid(_body) else 0,
		"camera_instance_first": _camera_id, "camera_instance_last": _camera.get_instance_id() if is_instance_valid(_camera) else 0,
		"body_visible": is_instance_valid(_body) and _body.is_visible_in_tree(),
		"command_results": _command_results, "command_receipts": _command_receipts.duplicate(true),
		"continuity": _guard.report(), "surface": _surface.contract_report() if is_instance_valid(_surface) else {},
		"two_independent_players_integrated": false, "mvp3_predicate_verified": false,
		"canonical_state_owned": false,
	}
	if is_instance_valid(_camera) and DisplayServer.get_name().to_lower() not in ["headless", "dummy"]:
		await RenderingServer.frame_post_draw
		var capture_path: String = str(_options.get("result-file", "")) + ".png"
		var image := get_viewport().get_texture().get_image()
		var saved: int = image.save_png(capture_path)
		report["screenshot"] = capture_path
		report["screenshot_saved"] = saved == OK
		if saved != OK:
			report["passed"] = false
			report["state"] = "FAILED"
			report["error"] = "SCREENSHOT_SAVE_FAILED"
	if _boundary != null:
		_boundary.stop()
	var written: bool = Support.write_json(str(_options.get("result-file", "")), report)
	print("MVP3_SEAM_SUBGATE_CLIENT %s passed=%s error=%s" % [str(_options.get("client-id", "")), str(report["passed"]), str(report["error"])])
	get_tree().quit(0 if written and bool(report["passed"]) else 1)

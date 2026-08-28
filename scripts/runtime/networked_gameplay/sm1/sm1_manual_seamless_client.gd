extends SceneTree

const Support = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")

const OPTION_SPEC := {
	"host": {"kind": "string", "default": "127.0.0.1"},
	"port": {"kind": "int", "default": 0, "required": true},
	"result-file": {"kind": "string", "default": "", "required": true},
	"timeout-ms": {"kind": "int", "default": 86400000},
	"auto-demo": {"kind": "bool", "default": false},
}

const CLIENT_ID := "a"
const PEER_ID := "peer/enet/sm1/manual-gateway"
const MOVE_STEP := 0.75
const AUTO_MOVE_STEP := 1.0
const INPUT_INTERVAL_MS := 110
const CAMERA_HEIGHT := 7.0
const CAMERA_Z := 12.0
const AUTHORITY_A_TO_B_X := 10.0
const AUTHORITY_B_TO_A_X := 0.0

var _options: Dictionary = {}
var _boundary = null
var _started_ms := 0
var _hello_sent := false
var _start_received := false
var _finished := false
var _pending_command := false
var _stop_requested := false
var _next_input_ms := 0
var _input_sequence := 0
var _operation_serial := 0
var _connect_count := 0
var _reconnect_count := 0
var _respawn_count := 0
var _gateway_endpoint_id := ""
var _active_authority_id := ""
var _authority_epoch := 0
var _world_revision := 0
var _position_x := 0.0
var _last_error := ""
var _last_operation_id := ""
var _handoff_flash_until_ms := 0
var _route_history: Array[String] = []
var _epochs: Array[int] = []
var _last_state: Dictionary = {}
var _identity_failures: Array[String] = []
var _commands_sent := 0
var _command_results := 0
var _goal_achieved := false
var _goal_achieved_at_epoch := 0
var _goal_route_snapshot: Array[String] = []

var _world_root: Node3D
var _player_mesh: MeshInstance3D
var _camera: Camera3D
var _status_label: Label
var _controls_label: Label
var _banner_label: Label


func _initialize() -> void:
	var parsed: Dictionary = Support.parse_options(OS.get_cmdline_user_args(), OPTION_SPEC)
	if not bool(parsed.get("success", false)):
		_finish_failure("INVALID_OPTIONS", {"errors": parsed.get("errors", [])})
		return
	_options = parsed["options"]
	if DisplayServer.get_name().to_lower() in ["", "headless", "dummy"]:
		_finish_failure("GRAPHICAL_DISPLAY_REQUIRED", {"display_server": DisplayServer.get_name()})
		return
	_build_scene()
	_boundary = Support.make_boundary()
	if _boundary == null:
		_finish_failure("BOUNDARY_CONFIGURE_FAILED", {})
		return
	var connected: Dictionary = _boundary.connect_client(
		Support.endpoint(String(_options["host"]), int(_options["port"])),
		PEER_ID,
		"transport-session/sm1/manual-client-a",
		"route/sm1/manual-client-a",
		1
	)
	if not bool(connected.get("success", false)):
		_finish_failure(String(connected.get("error_code", "CONNECT_FAILED")), {})
		return
	_connect_count = 1
	_started_ms = Time.get_ticks_msec()
	Support.write_state(String(_options["result-file"]), "CONNECTING", {
		"client_id": CLIENT_ID,
		"display_server": DisplayServer.get_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"gateway_host": String(_options["host"]),
		"gateway_port": int(_options["port"]),
	})
	_update_hud()


func _process(_delta: float) -> bool:
	if _finished or _boundary == null:
		return false
	var polled: Dictionary = _boundary.poll_events(128)
	if not bool(polled.get("success", false)):
		_finish_failure(String(polled.get("error_code", "CLIENT_POLL_FAILED")), {})
		return false
	for raw in polled.get("details", {}).get("events", []):
		var event: Dictionary = Dictionary(raw)
		var event_type := String(event.get("event_type", ""))
		if event_type == "PEER_CONNECTED":
			if not Support.mark_ready(_boundary, PEER_ID):
				_finish_failure("GATEWAY_PEER_NOT_READY", {})
				return false
		elif event_type == "PEER_DISCONNECTED" and not _finished:
			_finish_failure("GATEWAY_DISCONNECTED", {})
			return false
		elif event_type == "MESSAGE_RECEIVED":
			var payload := Support.payload_from_event(event)
			if not payload.is_empty():
				_handle(payload)
	if not _hello_sent and String(_boundary.get_peer_snapshot(PEER_ID).get("state", "")) == "READY":
		_send_hello()
	if _start_received and not _stop_requested:
		if bool(_options.get("auto-demo", false)):
			_drive_auto_demo()
		else:
			_drive_manual_input()
	_boundary.flush_outbound(128)
	_update_scene()
	_update_hud()
	if Time.get_ticks_msec() - _started_ms > int(_options.get("timeout-ms", 86400000)):
		_finish_failure("CLIENT_TIMEOUT", {})
	return false


func _handle(payload: Dictionary) -> void:
	match String(payload.get("type", "")):
		"START":
			_handle_start(payload)
		"STATE":
			_handle_state(payload)
		"COMMAND_RESULT":
			_handle_command_result(payload)
		"COMPLETE":
			_finish_success(payload)
		"ERROR":
			var error_code := String(payload.get("error_code", "GATEWAY_ERROR"))
			_last_error = error_code
			if bool(_options.get("auto-demo", false)):
				_finish_failure(error_code, {"payload": payload})


func _handle_start(payload: Dictionary) -> void:
	if _start_received:
		_finish_failure("DUPLICATE_START", {})
		return
	_start_received = true
	_gateway_endpoint_id = String(payload.get("gateway_endpoint_id", ""))
	_active_authority_id = String(payload.get("active_authority_id", ""))
	_authority_epoch = int(payload.get("authority_epoch", 0))
	_record_route(_active_authority_id, _authority_epoch)
	_maybe_latch_demo_goal()
	if _gateway_endpoint_id != Support.GATEWAY_ENDPOINT_ID:
		_finish_failure("GATEWAY_ENDPOINT_CHANGED", {"gateway_endpoint_id": _gateway_endpoint_id})


func _handle_state(payload: Dictionary) -> void:
	if String(payload.get("gateway_endpoint_id", "")) != Support.GATEWAY_ENDPOINT_ID:
		_identity_failures.append("gateway_endpoint")
	var state_value = payload.get("shared_state", {})
	if not state_value is Dictionary:
		_identity_failures.append("shared_state")
		return
	var state: Dictionary = Dictionary(state_value).duplicate(true)
	_last_state = state
	_validate_identity(state)
	_position_x = float(state.get("position_x", _position_x))
	_world_revision = int(state.get("world_revision", _world_revision))
	_active_authority_id = String(payload.get("active_authority_id", _active_authority_id))
	_authority_epoch = int(payload.get("authority_epoch", _authority_epoch))
	_record_route(_active_authority_id, _authority_epoch)
	_maybe_latch_demo_goal()


func _handle_command_result(payload: Dictionary) -> void:
	_pending_command = false
	if not bool(payload.get("success", false)):
		_last_error = String(payload.get("error_code", "COMMAND_REJECTED"))
		if bool(_options.get("auto-demo", false)):
			_finish_failure(_last_error, {"payload": payload})
		return
	_command_results += 1
	_active_authority_id = String(payload.get("active_authority_id", _active_authority_id))
	_authority_epoch = int(payload.get("authority_epoch", _authority_epoch))
	_world_revision = int(payload.get("world_revision", _world_revision))
	_record_route(_active_authority_id, _authority_epoch)
	_maybe_latch_demo_goal()
	if bool(payload.get("handoff_complete", false)):
		_handoff_flash_until_ms = Time.get_ticks_msec() + 1300


func _drive_manual_input() -> void:
	if Input.is_key_pressed(KEY_ESCAPE):
		_request_stop()
		return
	if _pending_command or Time.get_ticks_msec() < _next_input_ms:
		return
	var direction := 0.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_UP):
		direction += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_DOWN):
		direction -= 1.0
	if absf(direction) > 0.01:
		_send_move(direction * MOVE_STEP)
		_next_input_ms = Time.get_ticks_msec() + INPUT_INTERVAL_MS


func _drive_auto_demo() -> void:
	if _pending_command:
		return
	if _demo_goal_reached():
		_request_stop()
		return
	if _active_authority_id == Support.AUTHORITY_A and _authority_epoch <= 1:
		_send_move(AUTO_MOVE_STEP)
	elif _active_authority_id == Support.AUTHORITY_B:
		_send_move(-AUTO_MOVE_STEP)
	elif _active_authority_id == Support.AUTHORITY_A and _authority_epoch >= 3:
		_request_stop()


func _send_hello() -> void:
	var sent := Support.send(_boundary, PEER_ID, {"type": "HELLO", "client_id": CLIENT_ID})
	if not bool(sent.get("success", false)):
		_finish_failure(String(sent.get("error_code", "HELLO_SEND_FAILED")), {})
		return
	_hello_sent = true


func _send_move(delta_x: float) -> void:
	if _pending_command or not _start_received or _stop_requested:
		return
	_input_sequence += 1
	_operation_serial += 1
	_last_operation_id = "operation/sm1/manual/%d" % _operation_serial
	var sent := Support.send(_boundary, PEER_ID, {
		"type": "EXECUTE",
		"request_id": "manual-client/request/%d" % _operation_serial,
		"operation_id": _last_operation_id,
		"input_sequence": _input_sequence,
		"command_kind": "MOVE",
		"delta_x": delta_x,
	})
	if not bool(sent.get("success", false)):
		_finish_failure(String(sent.get("error_code", "COMMAND_SEND_FAILED")), {})
		return
	_pending_command = true
	_commands_sent += 1


func _request_stop() -> void:
	if _stop_requested or _pending_command:
		return
	_stop_requested = true
	var sent := Support.send(_boundary, PEER_ID, {"type": "DEMO_STOP", "client_id": CLIENT_ID})
	if not bool(sent.get("success", false)):
		_finish_failure(String(sent.get("error_code", "DEMO_STOP_SEND_FAILED")), {})


func _record_route(authority_id: String, epoch: int) -> void:
	if not authority_id.is_empty() and (_route_history.is_empty() or _route_history[-1] != authority_id):
		_route_history.append(authority_id)
	if epoch > 0 and not _epochs.has(epoch):
		_epochs.append(epoch)


func _validate_identity(state: Dictionary) -> void:
	if String(state.get("product_session_id", "")) != Support.PRODUCT_SESSION_ID and not _identity_failures.has("product_session_id"):
		_identity_failures.append("product_session_id")
	if String(state.get("logical_player_id", "")) != Support.LOGICAL_PLAYER_ID and not _identity_failures.has("logical_player_id"):
		_identity_failures.append("logical_player_id")
	if String(state.get("player_entity_id", "")) != Support.PLAYER_ENTITY_ID and not _identity_failures.has("player_entity_id"):
		_identity_failures.append("player_entity_id")
	if int(state.get("spawn_generation", 0)) != 1 and not _identity_failures.has("spawn_generation"):
		_identity_failures.append("spawn_generation")


func _demo_goal_reached() -> bool:
	return _goal_achieved


func _maybe_latch_demo_goal() -> void:
	if _goal_achieved:
		return
	if not _contains_route_pattern([Support.AUTHORITY_A, Support.AUTHORITY_B, Support.AUTHORITY_A]):
		return
	if not (_epochs.has(1) and _epochs.has(2) and _epochs.has(3)):
		return
	if _active_authority_id != Support.AUTHORITY_A or _authority_epoch < 3:
		return
	if _connect_count != 1 or _reconnect_count != 0 or _respawn_count != 0:
		return
	if not _identity_failures.is_empty():
		return
	_goal_achieved = true
	_goal_achieved_at_epoch = _authority_epoch
	_goal_route_snapshot = _route_history.duplicate()


func _contains_route_pattern(pattern: Array[String]) -> bool:
	if pattern.is_empty() or _route_history.size() < pattern.size():
		return false
	for start in range(_route_history.size() - pattern.size() + 1):
		var matches := true
		for offset in range(pattern.size()):
			if _route_history[start + offset] != pattern[offset]:
				matches = false
				break
		if matches:
			return true
	return false


func _build_scene() -> void:
	root.title = "Distributed World Simulator — SM1 Manual Seamless Demo"
	root.size = Vector2i(1280, 720)
	_world_root = Node3D.new()
	root.add_child(_world_root)

	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(34.0, 8.0)
	ground.mesh = ground_mesh
	ground.material_override = _material(Color(0.10, 0.12, 0.15, 1.0))
	ground.position = Vector3(5.0, 0.0, 0.0)
	_world_root.add_child(ground)

	var band := MeshInstance3D.new()
	var band_mesh := BoxMesh.new()
	band_mesh.size = Vector3(10.0, 0.025, 7.6)
	band.mesh = band_mesh
	# Keep the authority transition band opaque. Alpha blending made the moving
	# presentation proxy look like it left a short ghost trail over the band.
	band.material_override = _material(Color(0.16, 0.20, 0.28, 1.0))
	band.position = Vector3(5.0, 0.02, 0.0)
	_world_root.add_child(band)

	_add_threshold_marker(AUTHORITY_B_TO_A_X, "B → A threshold  x=0")
	_add_threshold_marker(AUTHORITY_A_TO_B_X, "A → B threshold  x=10")

	_player_mesh = MeshInstance3D.new()
	# This proxy is driven directly from the latest canonical network state in
	# _process(), not from the physics tick. Disable automatic interpolation so
	# Godot does not blend an already-discrete presentation transform twice.
	_player_mesh.set_physics_interpolation_mode(Node.PHYSICS_INTERPOLATION_MODE_OFF)
	var player_box := BoxMesh.new()
	player_box.size = Vector3(0.8, 1.2, 0.8)
	_player_mesh.mesh = player_box
	_player_mesh.material_override = _material(Color(0.92, 0.92, 0.96, 1.0))
	_player_mesh.position = Vector3(0.0, 0.6, 0.0)
	_world_root.add_child(_player_mesh)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	light.light_energy = 1.4
	_world_root.add_child(light)

	_camera = Camera3D.new()
	# Camera motion is presentation-only and updated every render frame.
	# Disable automatic physics interpolation to avoid Camera3D warnings and
	# keep the manual demo camera responsive to the latest canonical position.
	_camera.set_physics_interpolation_mode(Node.PHYSICS_INTERPOLATION_MODE_OFF)
	_camera.current = true
	_world_root.add_child(_camera)

	var canvas := CanvasLayer.new()
	root.add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	panel.custom_minimum_size = Vector2(560, 0)
	canvas.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "SM1 MANUAL SEAMLESS — stable Gateway endpoint"
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 17)
	box.add_child(_status_label)
	_controls_label = Label.new()
	_controls_label.text = "Controls: W/D/→ = toward Authority B   S/A/← = toward Authority A   Esc = stop demo"
	_controls_label.add_theme_font_size_override("font_size", 15)
	box.add_child(_controls_label)
	_banner_label = Label.new()
	_banner_label.position = Vector2(18, 650)
	_banner_label.add_theme_font_size_override("font_size", 20)
	canvas.add_child(_banner_label)


func _add_threshold_marker(x: float, text: String) -> void:
	var marker := MeshInstance3D.new()
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(0.10, 0.08, 7.8)
	marker.mesh = marker_mesh
	marker.material_override = _material(Color(0.95, 0.72, 0.18, 1.0))
	marker.position = Vector3(x, 0.07, 0.0)
	_world_root.add_child(marker)
	var label := Label3D.new()
	label.text = text
	label.font_size = 40
	label.position = Vector3(x, 1.35, -2.6)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_world_root.add_child(label)


func _material(color: Color, transparent: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func _update_scene() -> void:
	if _player_mesh == null or _camera == null:
		return
	_player_mesh.position = Vector3(_position_x, 0.6, 0.0)
	var camera_x := clampf(_position_x, -2.0, 12.0)
	_camera.position = Vector3(camera_x, CAMERA_HEIGHT, CAMERA_Z)
	_camera.look_at(Vector3(camera_x, 0.4, 0.0), Vector3.UP)


func _update_hud() -> void:
	if _status_label == null or _banner_label == null:
		return
	var authority_short := "A" if _active_authority_id == Support.AUTHORITY_A else ("B" if _active_authority_id == Support.AUTHORITY_B else "?")
	var route_text := " → ".join(_route_history.map(func(value): return "A" if value == Support.AUTHORITY_A else "B"))
	_status_label.text = "\n".join([
		"Gateway: %s  %s:%d" % [_gateway_endpoint_id if not _gateway_endpoint_id.is_empty() else "connecting…", String(_options.get("host", "127.0.0.1")), int(_options.get("port", 0))],
		"Active authority: %s   epoch: %d   world revision: %d" % [authority_short, _authority_epoch, _world_revision],
		"Canonical X: %.2f   route: %s" % [_position_x, route_text if not route_text.is_empty() else "—"],
		"Connections: %d   reconnects: %d   respawns: %d" % [_connect_count, _reconnect_count, _respawn_count],
		"Commands: %d sent / %d confirmed   pending: %s" % [_commands_sent, _command_results, str(_pending_command)],
		"Last error: %s" % (_last_error if not _last_error.is_empty() else "none"),
	])
	if _demo_goal_reached():
		_banner_label.text = "✓ A → B → A proven. You may keep moving; Esc will preserve PASS."
	elif Time.get_ticks_msec() < _handoff_flash_until_ms:
		_banner_label.text = "HANDOFF COMPLETE → active %s / epoch %d" % [authority_short, _authority_epoch]
	elif not _start_received:
		_banner_label.text = "Connecting to Gateway…"
	else:
		_banner_label.text = "Move across the transition thresholds; the client endpoint must not change."


func _finish_success(payload: Dictionary) -> void:
	if _finished:
		return
	var passed := _demo_goal_reached() \
		and String(payload.get("gateway_endpoint_id", "")) == Support.GATEWAY_ENDPOINT_ID \
		and _identity_failures.is_empty()
	var report := {
		"schema": "planet_simulator.sm1_manual_seamless_client_report.v1",
		"state": "COMPLETE" if passed else "INCOMPLETE",
		"passed": passed,
		"process_id": OS.get_process_id(),
		"display_server": DisplayServer.get_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"gateway_endpoint_id": _gateway_endpoint_id,
		"gateway_host": String(_options.get("host", "")),
		"gateway_port": int(_options.get("port", 0)),
		"connect_count": _connect_count,
		"reconnect_count": _reconnect_count,
		"respawn_count": _respawn_count,
		"active_authority_id": _active_authority_id,
		"authority_epoch": _authority_epoch,
		"world_revision": _world_revision,
		"position_x": _position_x,
		"route_history": _route_history.duplicate(),
		"epochs": _epochs.duplicate(),
		"commands_sent": _commands_sent,
		"command_results": _command_results,
		"logical_player_id": String(_last_state.get("logical_player_id", "")),
		"player_entity_id": String(_last_state.get("player_entity_id", "")),
		"spawn_generation": int(_last_state.get("spawn_generation", 0)),
		"identity_failures": _identity_failures.duplicate(),
		"auto_demo": bool(_options.get("auto-demo", false)),
		"goal_achieved": _goal_achieved,
		"goal_achieved_at_epoch": _goal_achieved_at_epoch,
		"goal_route_snapshot": _goal_route_snapshot.duplicate(),
	}
	Support.write_json(String(_options["result-file"]), report)
	_finished = true
	_boundary.stop()
	print("SM1_MANUAL_SEAMLESS_CLIENT_COMPLETE passed=%s route=%s" % [str(passed), str(_route_history)])
	quit(0 if passed else 1)


func _finish_failure(error_code: String, details: Dictionary) -> void:
	if _finished:
		return
	_finished = true
	_last_error = error_code
	if _boundary != null:
		_boundary.stop()
	Support.write_json(String(_options.get("result-file", "")), {
		"schema": "planet_simulator.sm1_manual_seamless_client_report.v1",
		"state": "FAILED",
		"passed": false,
		"process_id": OS.get_process_id(),
		"failure_code": error_code,
		"details": details,
		"gateway_endpoint_id": _gateway_endpoint_id,
		"connect_count": _connect_count,
		"reconnect_count": _reconnect_count,
		"respawn_count": _respawn_count,
		"route_history": _route_history.duplicate(),
		"epochs": _epochs.duplicate(),
	})
	push_error("SM1 manual seamless client failed: %s" % error_code)
	quit(1)

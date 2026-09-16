extends Node3D

# One composition root, two roles. All gameplay writes stay in the accepted M3/NX stack.
const LaunchOptions = preload("res://scripts/runtime/launch_options.gd")
const ServerRuntime = preload("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd")
const ClientRuntime = preload("res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd")
const RemotePresenter = preload("res://scripts/runtime/networked_gameplay/m3/remote_player_presenter.gd")
const BootstrapSurface = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp_bootstrap_surface.gd")
const SCENE_PATH := "res://scenes/labs/mvp/v0_mvp_two_client_shared_world.tscn"
const BUILD_ID := "v0-mvp2-two-client-shared-world-r1"
const ACTION_KEYS := {
	"mvp2_left": KEY_A, "mvp2_right": KEY_D,
	"mvp2_forward": KEY_W, "mvp2_back": KEY_S,
	"mvp2_sprint": KEY_SHIFT, "mvp2_jump": KEY_SPACE,
	"mvp2_flashlight": KEY_F,
}

var _server = null
var _client = null
var _surface = null
var _remote: Dictionary = {}
var _item_snapshot: Dictionary = {}
var _options: Dictionary = {}
var _role := ""
var _player_id := ""
var _configured := false
var _stopped := false
var _input_active := true
var _last_error := ""
var _yaw := 0.0
var _camera: Camera3D
var _local_body: MeshInstance3D
var _local_light: SpotLight3D
var _status: Label


static func validate_options(options: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if String(options.get("role", "")) not in ["dedicated-server", "game-client"]:
		errors.append("MVP2_EXPLICIT_NETWORK_ROLE_REQUIRED")
	if String(options.get("world", "")) != "moon":
		errors.append("MVP2_MOON_WORLD_REQUIRED")
	if bool(options.get("network_mvp", false)) or bool(options.get("network_playground", false)):
		errors.append("MVP2_LEGACY_MODE_SELECTOR_FORBIDDEN")
	if String(options.get("network_build_id", "")) != BUILD_ID:
		errors.append("MVP2_BUILD_ID_MISMATCH")
	var commit := String(options.get("network_git_commit", ""))
	if commit.length() != 40 or not commit.is_valid_hex_number(false):
		errors.append("MVP2_EXACT_COMMIT_REQUIRED")
	if String(options.get("network_session_token", "")).strip_edges().is_empty():
		errors.append("MVP2_SESSION_REQUIRED")
	if int(options.get("server_port", 0)) < 1 or int(options.get("server_port", 0)) > 65535:
		errors.append("MVP2_PORT_INVALID")
	if String(options.get("server_address", "")).strip_edges().is_empty():
		errors.append("MVP2_ADDRESS_REQUIRED")
	if String(options.get("role", "")) == "game-client" and String(options.get("player_identity", "")).strip_edges().is_empty():
		errors.append("MVP2_PLAYER_ID_REQUIRED")
	return {"success": errors.is_empty(), "errors": errors}


func _ready() -> void:
	get_tree().auto_accept_quit = false
	var parsed: Dictionary = LaunchOptions.from_os()
	_options = Dictionary(parsed.get("options", {})).duplicate(true)
	var checked := validate_options(_options)
	if not bool(parsed.get("success", false)) or not bool(checked.get("success", false)):
		_last_error = "MVP2_INVALID_LAUNCH:%s:%s" % [parsed.get("errors", []), checked.get("errors", [])]
		push_error(_last_error)
		get_tree().quit(2)
		return
	_role = String(_options["role"])
	_player_id = String(_options["player_identity"])
	_surface = BootstrapSurface.new()
	_surface.name = "ImmutableP7BootstrapSurface"
	add_child(_surface)
	var surface_result: Dictionary = _surface.configure(_role == "game-client")
	if not bool(surface_result.get("success", false)):
		_last_error = String(surface_result.get("error_code", "MVP2_SURFACE_FAILED"))
		push_error(_last_error)
		get_tree().quit(3)
		return
	var config := {
		"host": String(_options["server_address"]),
		"port": int(_options["server_port"]),
		"logical_player_id": _player_id,
		"authority_owner_id": "authority/v0-mvp2/" + String(_options["network_session_token"]).sha256_text().left(16),
		"authority_epoch": 1,
		"world_id": "moon",
		# This selects the EXISTING fixed-tick movement kernel, not a new simulator.
		"playable_sandbox": true,
		"network_session_token": String(_options["network_session_token"]),
		"network_build_id": BUILD_ID,
		"network_git_commit": String(_options["network_git_commit"]),
		"network_protocol_hash": String(_options["network_protocol_hash"]),
		"network_condition_profile": String(_options["network_condition_profile"]),
		"connect_timeout_ms": int(_options["connect_timeout_ms"]),
		"command_timeout_ms": int(_options["command_timeout_ms"]),
	}
	var result: Dictionary
	if _role == "dedicated-server":
		_server = ServerRuntime.new()
		_server.name = "ExistingM3Authority"
		add_child(_server)
		result = _server.setup(config)
	else:
		_build_view()
		_ensure_actions()
		_client = ClientRuntime.new()
		_client.name = "ExistingM3Replica"
		add_child(_client)
		_client.replica_updated.connect(_on_snapshot)
		_client.item_graph_updated.connect(_on_item_snapshot)
		_client.connection_failed.connect(_on_connection_failed)
		_client.server_disconnected.connect(_on_server_disconnected)
		result = _client.setup(config)
	_configured = bool(result.get("success", false))
	if not _configured:
		_last_error = String(result.get("error_code", "MVP2_RUNTIME_SETUP_FAILED"))
		push_error(_last_error)
		get_tree().quit(4)
		return
	print("MVP2_COMPOSITION_READY role=%s player=%s pid=%d" % [_role, _player_id, OS.get_process_id()])


func _build_view() -> void:
	DisplayServer.window_set_title("DWS MVP2 — " + _player_id)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.025, 0.035, 0.06)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.7, 0.75, 0.85)
	settings.ambient_light_energy = 0.7
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	sun.light_energy = 1.6
	add_child(sun)
	_local_body = MeshInstance3D.new()
	_local_body.name = "LocalReplicaBody"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	_local_body.mesh = capsule
	_local_body.visible = false
	add_child(_local_body)
	_add_name(_local_body, _player_id + " (you)")
	_local_light = SpotLight3D.new()
	_local_light.name = "LocalReplicaFlashlight"
	_local_light.spot_range = 14.0
	_local_light.spot_angle = 32.0
	_local_light.light_energy = 2.0
	_local_light.visible = false
	_local_body.add_child(_local_light)
	_camera = Camera3D.new()
	_camera.name = "SharedWorldCamera"
	_camera.current = true
	_camera.fov = 65.0
	_camera.position = Vector3(0.0, 7.0, 10.0)
	add_child(_camera)
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	var canvas := CanvasLayer.new()
	canvas.name = "MVP2Status"
	add_child(canvas)
	_status = Label.new()
	_status.position = Vector2(18.0, 16.0)
	_status.add_theme_font_size_override("font_size", 18)
	canvas.add_child(_status)


func _add_name(parent: Node3D, text: String) -> void:
	var label := Label3D.new()
	label.name = "PlayerIdentityLabel"
	label.text = text
	label.position = Vector3(0.0, 1.4, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	parent.add_child(label)


func _ensure_actions() -> void:
	for action_value in ACTION_KEYS:
		var action := String(action_value)
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var key := InputEventKey.new()
		key.physical_keycode = int(ACTION_KEYS[action])
		InputMap.action_add_event(action, key)


func _intent(movement: Vector2) -> Dictionary:
	return {
		"move_x": movement.x, "move_z": movement.y,
		"look_yaw": _yaw, "look_pitch": 0.0,
		"jump_pressed": Input.is_action_just_pressed("mvp2_jump"),
		"sprint": Input.is_action_pressed("mvp2_sprint"),
		"delta_seconds": 1.0 / 60.0,
	}


func set_input_active(active: bool) -> void:
	if _input_active and not active and _client != null and _client.is_ready():
		var neutral := _intent(Vector2.ZERO)
		neutral["jump_pressed"] = false
		neutral["sprint"] = false
		var result: Dictionary = _client.submit_movement_intent_nonblocking(neutral)
		if not bool(result.get("success", false)):
			_last_error = String(result.get("error_code", "MVP2_NEUTRAL_INPUT_FAILED"))
	_input_active = active


func _process(delta: float) -> void:
	if _stopped or _role != "game-client" or _client == null:
		return
	var ready: bool = _client.is_ready()
	if _status != null:
		_status.text = "MVP2 | %s | %s | peers visible: %d\nWASD: move   Shift: sprint   Space: jump   F: flashlight\nClick: capture mouse   Esc: release/pause input\nImmutable P7 surface preview; network digging/seams are later leaves.\n%s" % [_player_id, "CONNECTED" if ready else "NOT CONNECTED", _remote.size(), _last_error]
	if not ready:
		_local_body.visible = false
		return
	if _input_active:
		var movement := Input.get_vector("mvp2_left", "mvp2_right", "mvp2_forward", "mvp2_back")
		var advanced: Dictionary = _client.advance_local_prediction(_intent(movement), delta)
		if not bool(advanced.get("success", false)):
			_last_error = String(advanced.get("error_code", "MVP2_PREDICTION_FAILED"))
		if Input.is_action_just_pressed("mvp2_flashlight"):
			var current: Dictionary = _client.get_player(_player_id)
			var toggled: Dictionary = _client.set_presentation_blocking(_yaw, not bool(current.get("flashlight_enabled", false)))
			if not bool(toggled.get("success", false)):
				_last_error = String(toggled.get("error_code", "MVP2_PRESENTATION_FAILED"))
	var local: Dictionary = _client.get_prediction_presentation_player() if _input_active else _client.get_player(_player_id)
	if local.is_empty():
		return
	_local_body.visible = true
	_local_body.position = _position(local)
	_local_body.rotation.y = float(local.get("orientation_yaw", 0.0))
	var canonical: Dictionary = _client.get_player(_player_id)
	_local_light.visible = bool(canonical.get("flashlight_enabled", false))
	_camera.position = _local_body.position + Vector3(0.0, 7.0, 10.0).rotated(Vector3.UP, _yaw)
	_camera.look_at(_local_body.position + Vector3(0.0, 0.4, 0.0), Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if _role != "game-client":
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		set_input_active(true)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * 0.003
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		set_input_active(false)


func _on_snapshot(snapshot: Dictionary) -> void:
	if _client == null or not _client.is_ready():
		return
	var seen: Dictionary = {}
	var context := {
		"server_tick": int(snapshot.get("server_tick", -1)),
		"snapshot_revision": int(snapshot.get("revision", -1)),
		"authority_epoch": int(snapshot.get("authority_epoch", 0)),
	}
	for value in snapshot.get("players", []):
		var record: Dictionary = value
		var id := String(record.get("logical_player_id", ""))
		if id == _player_id or not bool(record.get("connected", false)):
			continue
		seen[id] = true
		var view = _remote.get(id)
		var result: Dictionary
		if view == null:
			view = RemotePresenter.new()
			add_child(view)
			result = view.setup(record, context)
			if not bool(result.get("success", false)):
				view.free()
				_last_error = String(result.get("error_code", "MVP2_REMOTE_SETUP_FAILED"))
				continue
			_remote[id] = view
			_add_name(view, id)
		else:
			result = view.apply_replica(record, false, context)
			if not bool(result.get("success", false)):
				_last_error = String(result.get("error_code", "MVP2_REMOTE_UPDATE_FAILED"))
	for id in _remote.keys():
		if not seen.has(id):
			_remote[id].queue_free()
			_remote.erase(id)


func _on_item_snapshot(snapshot: Dictionary) -> void:
	_item_snapshot = snapshot.duplicate(true)


func _on_connection_failed(error_code: String, _details: Dictionary) -> void:
	_last_error = error_code
	print("MVP2_CONNECTION_REJECTED " + error_code)
	_clear_remote()


func _on_server_disconnected(_report: Dictionary) -> void:
	_last_error = "MVP2_SERVER_DISCONNECTED"
	_clear_remote()


func _clear_remote() -> void:
	for view in _remote.values():
		view.queue_free()
	_remote.clear()
	if _local_body != null:
		_local_body.visible = false


static func _position(record: Dictionary) -> Vector3:
	var value: Dictionary = record.get("position", {})
	return Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0)))


func observation() -> Dictionary:
	var runtime: Dictionary = _server.get_report() if _server != null else _client.get_report() if _client != null else {}
	var snapshot: Dictionary = runtime.get("snapshot", {}) if _server != null else _client.get_snapshot() if _client != null else {}
	var item_snapshot: Dictionary = runtime.get("item_graph_snapshot", {}) if _server != null else _item_snapshot
	var views: Dictionary = {}
	for id in _remote:
		var view = _remote[id]
		var report: Dictionary = view.get_report()
		var body := view.get_node_or_null("RemoteBody") as MeshInstance3D
		report["body_visible_in_tree"] = body != null and body.is_visible_in_tree() and body.mesh != null
		report["inside_camera_frustum"] = _camera != null and _camera.is_position_in_frustum(view.global_position)
		report["node_path"] = String(view.get_path())
		views[id] = report
	return {
		"schema": "distributed_world_simulator.mvp2_observation.v1",
		"scene_path": SCENE_PATH, "process_id": OS.get_process_id(),
		"role": _role, "player_id": _player_id, "world_id": "moon",
		"configured": _configured, "stopped": _stopped, "error": _last_error,
		"display_server": DisplayServer.get_name(), "user_data_dir": OS.get_user_data_dir(),
		"server_runtime_present": _server != null, "client_runtime_present": _client != null,
		"input_active": _input_active,
		"surface": _surface.contract_report() if _surface != null else {},
		"runtime": runtime, "snapshot": snapshot.duplicate(true),
		"item_graph_snapshot": item_snapshot.duplicate(true),
		"remote_presenters": views,
		"local_body_visible": _local_body != null and _local_body.is_visible_in_tree(),
		"local_body_position": [_local_body.position.x, _local_body.position.y, _local_body.position.z] if _local_body != null else [],
		"active_camera": String(_camera.get_path()) if _camera != null and _camera.current else "",
	}


func stop_session() -> Dictionary:
	if _stopped:
		return {"success": true, "already_stopped": true}
	_stopped = true
	_input_active = false
	var result: Dictionary = {"success": true}
	if _client != null:
		result = _client.stop()
	if _server != null:
		result = _server.stop()
	_configured = false
	return result


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		var result := stop_session()
		get_tree().quit(0 if bool(result.get("success", false)) else 5)


func _exit_tree() -> void:
	stop_session()

extends Node3D

const ManualClient = preload("res://scripts/runtime/seamless/sm0/sm0_manual_client_node.gd")
const NetworkManualClient = preload("res://scripts/runtime/seamless/sm0/sm0_manual_client_network_delay.gd")
const P3_1_NETWORK_PROFILE := "p31-controlled-latency-v1"

const ACTION_LEFT := "sm0_move_left"
const ACTION_RIGHT := "sm0_move_right"
const ACTION_FORWARD := "sm0_move_forward"
const ACTION_BACK := "sm0_move_back"
const VIEW_SCALE := 1.0

var _client
var _avatar: MeshInstance3D
var _camera: Camera3D
var _hud: Label
var _status: Label
var _target_position := Vector3(-1.0, 0.75, 0.0)
var _smoke_mode := false
var _smoke_frames := 0


func _ready() -> void:
	_smoke_mode = "--smoke" in OS.get_cmdline_user_args()
	_configure_input()
	_build_world()
	if _smoke_mode:
		_status.text = "SM0-P1 visual smoke"
		return
	var options := _parse_user_args()
	var network_profile := String(options.get("network-profile", "")).strip_edges().to_lower()
	_client = NetworkManualClient.new() if network_profile == P3_1_NETWORK_PROFILE else ManualClient.new()
	_client.name = "ManualClient"
	add_child(_client)
	_client.finished.connect(_on_client_finished)
	var setup_result: Dictionary = _client.setup({
		"server_host": String(options.get("server-host", "127.0.0.1")),
		"server_a_port": int(options.get("server-a-port", 24580)),
		"server_b_port": int(options.get("server-b-port", 24581)),
		"client_port": int(options.get("client-port", 24780)),
		"handoffs": 1000000,
		"timeout_ms": 86400000,
		"result_file": "",
		"network_profile": network_profile,
		"network_latency_ms": int(options.get("network-latency-ms", 0)),
		"network_jitter_ms": int(options.get("network-jitter-ms", 0)),
		"network_seed": int(options.get("network-seed", 431)),
	})
	if not bool(setup_result.get("success", false)):
		_status.text = "CLIENT SETUP FAILED: %s" % String(setup_result.get("error_code", "unknown"))
	elif network_profile == P3_1_NETWORK_PROFILE:
		_status.text = "P3.1 WAN SHAPER: %d ms one-way +/- %d ms · A/D cross · close window to measure" % [
			int(options.get("network-latency-ms", 0)),
			int(options.get("network-jitter-ms", 0)),
		]


func _process(delta: float) -> void:
	if _smoke_mode:
		_smoke_frames += 1
		if _smoke_frames >= 3:
			print("SM0-P1 graphical scene smoke PASS")
			get_tree().quit(0)
		return
	if _client == null:
		return
	var axis := Input.get_vector(ACTION_LEFT, ACTION_RIGHT, ACTION_FORWARD, ACTION_BACK)
	_client.set_manual_axis(Vector2(axis.x, axis.y))
	var view: Dictionary = _client.get_view_state()
	var player: Dictionary = Dictionary(view.get("player", {}))
	var position: Dictionary = Dictionary(player.get("position", {}))
	if not position.is_empty():
		_target_position = Vector3(
			float(position.get("x", 0.0)) * VIEW_SCALE,
			0.75,
			float(position.get("z", 0.0)) * VIEW_SCALE
		)
	_avatar.position = _avatar.position.lerp(_target_position, clampf(delta * 12.0, 0.0, 1.0))
	_update_hud(view)


func _configure_input() -> void:
	_ensure_key_action(ACTION_LEFT, KEY_A)
	_ensure_key_action(ACTION_RIGHT, KEY_D)
	_ensure_key_action(ACTION_FORWARD, KEY_W)
	_ensure_key_action(ACTION_BACK, KEY_S)


func _ensure_key_action(action: String, physical_keycode: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = physical_keycode
	for existing in InputMap.action_get_events(action):
		if existing is InputEventKey and existing.physical_keycode == physical_keycode:
			return
	InputMap.action_add_event(action, event)


func _build_world() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.035, 0.045, 0.065)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.7, 0.75, 0.85)
	environment.ambient_light_energy = 0.65
	environment_node.environment = environment
	add_child(environment_node)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.shadow_enabled = true
	sun.light_energy = 1.1
	add_child(sun)

	_add_floor_half("WestAuthorityA", Vector3(-6.0, -0.08, 0.0), Color(0.10, 0.30, 0.52))
	_add_floor_half("EastAuthorityB", Vector3(6.0, -0.08, 0.0), Color(0.56, 0.27, 0.08))
	_add_boundary()

	_avatar = MeshInstance3D.new()
	_avatar.name = "AuthoritativePlayerProjection"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.38
	capsule.height = 1.5
	_avatar.mesh = capsule
	var avatar_material := StandardMaterial3D.new()
	avatar_material.albedo_color = Color(0.92, 0.95, 1.0)
	avatar_material.metallic = 0.1
	avatar_material.roughness = 0.4
	_avatar.material_override = avatar_material
	_avatar.position = _target_position
	add_child(_avatar)

	_camera = Camera3D.new()
	_camera.name = "LabCamera"
	_camera.position = Vector3(0.0, 10.5, 12.5)
	_camera.fov = 55.0
	add_child(_camera)
	_camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)

	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(18.0, 18.0)
	panel.custom_minimum_size = Vector2(440.0, 190.0)
	canvas.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "SM0 — TWO AUTHORITY SEAMLESS HANDOFF LAB"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	_hud = Label.new()
	_hud.text = "Connecting..."
	_hud.add_theme_font_size_override("font_size", 16)
	box.add_child(_hud)
	_status = Label.new()
	_status.text = "A/D cross the authority boundary · W/S move along it · close window to stop lab"
	_status.add_theme_font_size_override("font_size", 14)
	box.add_child(_status)

	var legend := Label.new()
	legend.position = Vector2(18.0, 650.0)
	legend.text = "BLUE = authority A / WEST     | x=0 |     ORANGE = authority B / EAST"
	legend.add_theme_font_size_override("font_size", 15)
	canvas.add_child(legend)


func _add_floor_half(node_name: String, at: Vector3, color: Color) -> void:
	var floor := MeshInstance3D.new()
	floor.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = Vector3(12.0, 0.15, 12.0)
	floor.mesh = mesh
	floor.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	floor.material_override = material
	add_child(floor)


func _add_boundary() -> void:
	var boundary := MeshInstance3D.new()
	boundary.name = "AuthorityBoundaryX0"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.08, 0.04, 12.0)
	boundary.mesh = mesh
	boundary.position = Vector3(0.0, 0.02, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.92, 0.30)
	material.emission_enabled = true
	material.emission = Color(0.45, 0.40, 0.05)
	boundary.material_override = material
	add_child(boundary)


func _update_hud(view: Dictionary) -> void:
	var authority_id := String(view.get("authority_id", ""))
	var authority_short := "A" if authority_id.ends_with("/a") else ("B" if authority_id.ends_with("/b") else "?")
	var player: Dictionary = Dictionary(view.get("player", {}))
	var pos: Dictionary = Dictionary(player.get("position", {}))
	var pending: Dictionary = Dictionary(view.get("pending_transfer", {}))
	var pending_text := String(pending.get("transfer_id", ""))
	if pending_text.is_empty():
		pending_text = "none"
	_hud.text = "Authority: %s   Zone: %s\nState: %s   Authority epoch: %d   Ownership epoch: %d\nPlayer: %s\nPosition: x=%.2f  z=%.2f\nHandoffs: %d   Pending: %s" % [
		authority_short,
		String(view.get("zone_id", "")),
		String(view.get("client_state", "")),
		int(view.get("authority_epoch", 0)),
		int(view.get("ownership_epoch", 0)),
		String(view.get("player_entity_id", "")),
		float(pos.get("x", 0.0)),
		float(pos.get("z", 0.0)),
		int(view.get("handoffs_completed", 0)),
		pending_text,
	]
	var errors: Array = Array(view.get("errors", []))
	if not errors.is_empty():
		_status.text = "CLIENT ERROR: %s" % String(errors.back())


func _on_client_finished(exit_code: int) -> void:
	if exit_code != 0:
		_status.text = "CLIENT FINISHED WITH ERROR %d — close window and inspect graphical-client.log" % exit_code


func _parse_user_args() -> Dictionary:
	var result: Dictionary = {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--") or not arg.contains("="):
			continue
		var key := arg.trim_prefix("--").get_slice("=", 0)
		var value := arg.get_slice("=", 1)
		result[key] = value
	return result

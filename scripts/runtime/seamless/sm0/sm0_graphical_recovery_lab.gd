extends "res://scripts/runtime/seamless/sm0/sm0_graphical_handoff_lab.gd"

var _recovery_status_file := ""
var _recovery_poll_elapsed := 0.0
var _last_status_text := ""
var _recovery_hud: Label
var _outage_banner: Label
var _server_a_beacon: MeshInstance3D
var _server_b_beacon: MeshInstance3D
var _server_a_label: Label3D
var _server_b_label: Label3D


func _ready() -> void:
	super._ready()
	var options := _parse_user_args()
	_recovery_status_file = String(options.get("recovery-status-file", ""))
	_build_recovery_projection()
	if _smoke_mode:
		_recovery_hud.text = "SM0-P2 recovery projection smoke"
		return
	if _recovery_status_file.is_empty():
		_recovery_hud.text = "Recovery supervisor status: unavailable"
	else:
		_recovery_hud.text = "Recovery supervisor: waiting for status..."


func _process(delta: float) -> void:
	super._process(delta)
	if _smoke_mode:
		return
	_recovery_poll_elapsed += delta
	if _recovery_poll_elapsed < 0.08:
		return
	_recovery_poll_elapsed = 0.0
	_refresh_recovery_status()


func _build_recovery_projection() -> void:
	_server_a_beacon = _create_server_beacon("RecoveryServerA", Vector3(-4.5, 0.8, -4.4))
	_server_b_beacon = _create_server_beacon("RecoveryServerB", Vector3(4.5, 0.8, -4.4))
	_server_a_label = _create_server_label("A", Vector3(-4.5, 1.7, -4.4))
	_server_b_label = _create_server_label("B", Vector3(4.5, 1.7, -4.4))
	_set_beacon_state(_server_a_beacon, "UNKNOWN")
	_set_beacon_state(_server_b_beacon, "UNKNOWN")

	var canvas := CanvasLayer.new()
	canvas.name = "RecoveryHUD"
	add_child(canvas)

	var panel := PanelContainer.new()
	panel.position = Vector2(500.0, 18.0)
	panel.custom_minimum_size = Vector2(510.0, 230.0)
	canvas.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "P2 — RECOVERY SUPERVISOR"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	_recovery_hud = Label.new()
	_recovery_hud.text = "Starting..."
	_recovery_hud.add_theme_font_size_override("font_size", 15)
	box.add_child(_recovery_hud)

	_outage_banner = Label.new()
	_outage_banner.position = Vector2(235.0, 285.0)
	_outage_banner.custom_minimum_size = Vector2(560.0, 76.0)
	_outage_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outage_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_outage_banner.text = "TOTAL OUTAGE — BOTH AUTHORITIES DOWN"
	_outage_banner.add_theme_font_size_override("font_size", 28)
	_outage_banner.add_theme_color_override("font_color", Color(1.0, 0.24, 0.18))
	_outage_banner.visible = false
	canvas.add_child(_outage_banner)

	var help := Label.new()
	help.position = Vector2(18.0, 610.0)
	help.text = "P2: cross x=0 manually. Supervisor will crash/restart A+B at PREPARED, COMMITTED and ACTIVE for the SAME transfer."
	help.add_theme_font_size_override("font_size", 14)
	canvas.add_child(help)


func _create_server_beacon(node_name: String, at: Vector3) -> MeshInstance3D:
	var beacon := MeshInstance3D.new()
	beacon.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.38
	mesh.bottom_radius = 0.38
	mesh.height = 1.25
	beacon.mesh = mesh
	beacon.position = at
	add_child(beacon)
	return beacon


func _create_server_label(text_value: String, at: Vector3) -> Label3D:
	var label := Label3D.new()
	label.text = "SERVER %s" % text_value
	label.font_size = 42
	label.position = at
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	return label


func _refresh_recovery_status() -> void:
	if _recovery_status_file.is_empty() or not FileAccess.file_exists(_recovery_status_file):
		return
	var file := FileAccess.open(_recovery_status_file, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	if text == _last_status_text or text.is_empty():
		return
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return
	_last_status_text = text
	_apply_recovery_status(Dictionary(parsed))


func _apply_recovery_status(status: Dictionary) -> void:
	var server_a: Dictionary = Dictionary(status.get("server_a", {}))
	var server_b: Dictionary = Dictionary(status.get("server_b", {}))
	var state_a := String(server_a.get("state", "UNKNOWN"))
	var state_b := String(server_b.get("state", "UNKNOWN"))
	_set_beacon_state(_server_a_beacon, state_a)
	_set_beacon_state(_server_b_beacon, state_b)
	_server_a_label.text = "SERVER A\n%s" % state_a
	_server_b_label.text = "SERVER B\n%s" % state_b

	var transfer_id := String(status.get("transfer_id", ""))
	if transfer_id.is_empty():
		transfer_id = "none"
	var stage := String(status.get("stage", "READY"))
	var source := String(status.get("source", "-"))
	var target := String(status.get("target", "-"))
	var message := String(status.get("message", ""))
	_recovery_hud.text = "Stage: %s   Chain: %d   Outage: %d/3\nSource: %s   Target: %s\nTransfer: %s\nA: %s  pid=%d  phase=%s  gen=%d\nB: %s  pid=%d  phase=%s  gen=%d\n%s" % [
		stage,
		int(status.get("chain", 0)),
		int(status.get("outage", 0)),
		source,
		target,
		transfer_id,
		state_a,
		int(server_a.get("pid", 0)),
		String(server_a.get("phase", "-")),
		int(server_a.get("generation", 0)),
		state_b,
		int(server_b.get("pid", 0)),
		String(server_b.get("phase", "-")),
		int(server_b.get("generation", 0)),
		message,
	]
	_outage_banner.visible = stage == "OUTAGE" or (state_a == "DOWN" and state_b == "DOWN")


func _set_beacon_state(beacon: MeshInstance3D, state: String) -> void:
	if beacon == null:
		return
	var color := Color(0.55, 0.55, 0.58)
	match state:
		"ONLINE":
			color = Color(0.20, 0.88, 0.36)
		"RECOVERING":
			color = Color(1.0, 0.76, 0.18)
		"DOWN":
			color = Color(0.95, 0.12, 0.10)
		_:
			color = Color(0.55, 0.55, 0.58)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.55
	material.roughness = 0.35
	beacon.material_override = material

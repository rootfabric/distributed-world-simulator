extends Node3D

signal finished(exit_code: int)

const Contracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")
const ViewContract = preload("res://scripts/runtime/seamless/sm0/sm0_p6_pivot_view_contract.gd")

const VIEW_MESSAGE := "P6_PROJECTION_PIVOT_VIEW"
const STOP_POLL_INTERVAL_MS := 250

var _viewer_authority_id := ""
var _listen_host := "127.0.0.1"
var _listen_port := 0
var _stop_file := ""
var _socket: PacketPeerUDP
var _last_stop_poll_ms := 0
var _last_view_sequence := 0
var _last_view_checksum := ""
var _last_stable_role := ""
var _current_view: Dictionary = {}
var _avatar: MeshInstance3D
var _avatar_material: StandardMaterial3D
var _target_position := Vector3.ZERO
var _hud: Label
var _visible_logged := false
var _pivot_count := 0
var _visual_instance_id := 0


func setup(config: Dictionary) -> Dictionary:
	_viewer_authority_id = String(config.get("viewer_authority_id", "")).strip_edges()
	_listen_host = String(config.get("listen_host", "127.0.0.1")).strip_edges()
	_listen_port = int(config.get("listen_port", 0))
	_stop_file = String(config.get("stop_file", "")).strip_edges()
	if _viewer_authority_id not in [Contracts.AUTHORITY_A, Contracts.AUTHORITY_B] or _listen_port < 1:
		return _failure("SM0_P6_OBSERVER_INVALID_CONFIGURATION")
	_build_world()
	_socket = PacketPeerUDP.new()
	var bind_error := _socket.bind(_listen_port, _listen_host)
	if bind_error != OK:
		return _failure("SM0_P6_OBSERVER_BIND_FAILED", {"error": bind_error, "port": _listen_port})
	set_process(true)
	_event("SM0_P6_OBSERVER_READY", {
		"listen_port": _listen_port,
		"command_channel": false,
		"visual_instance_id": _visual_instance_id,
	})
	return _success()


func _process(delta: float) -> void:
	_poll_packets()
	if _avatar != null and _avatar.visible:
		_avatar.position = _avatar.position.lerp(_target_position, clampf(delta * 14.0, 0.0, 1.0))
	var now := Time.get_ticks_msec()
	if not _stop_file.is_empty() and now - _last_stop_poll_ms >= STOP_POLL_INTERVAL_MS:
		_last_stop_poll_ms = now
		if FileAccess.file_exists(_stop_file):
			shutdown(0, "stop-file")


func _poll_packets() -> void:
	if _socket == null:
		return
	while _socket.get_available_packet_count() > 0:
		var message := Contracts.decode_message(_socket.get_packet())
		var message_check := Contracts.validate_message(message)
		if not bool(message_check.get("success", false)):
			_event("SM0_P6_VIEW_REJECTED", {"error_code": String(message_check.get("error_code", "SM0_P6_MESSAGE_INVALID"))})
			continue
		if String(message.get("type", "")) != VIEW_MESSAGE:
			continue
		accept_view_for_tests(Dictionary(message.get("payload", {})))


func accept_view_for_tests(view: Dictionary) -> Dictionary:
	var validation := ViewContract.validate(view)
	if not bool(validation.get("success", false)):
		return _rejected(String(validation.get("error_code", "SM0_P6_VIEW_INVALID")))
	if String(view.get("viewer_authority_id", "")) != _viewer_authority_id:
		return _rejected("SM0_P6_VIEWER_AUTHORITY_MISMATCH")
	var sequence := int(view.get("view_sequence", 0))
	var checksum := String(view.get("checksum", ""))
	if sequence < _last_view_sequence:
		return _success({"stale": true})
	if sequence == _last_view_sequence and _last_view_sequence > 0:
		if checksum != _last_view_checksum:
			return _rejected("SM0_P6_SAME_SEQUENCE_MUTATION")
		return _success({"replay": true})

	var previous_view := _current_view.duplicate(true)
	_last_view_sequence = sequence
	_last_view_checksum = checksum
	_current_view = view.duplicate(true)
	_target_position = _to_world_position(Dictionary(view.get("position", {})))
	_avatar.visible = true
	_apply_role_material(String(view.get("presentation_role", "")))
	if not _visible_logged:
		_visible_logged = true
		_event("SM0_P6_PLAYER_VISIBLE", {
			"logical_player_id": String(view.get("logical_player_id", "")),
			"player_entity_id": String(view.get("player_entity_id", "")),
			"presentation_role": String(view.get("presentation_role", "")),
			"visual_instance_id": _visual_instance_id,
			"command_channel": false,
		})
	_track_pivot(previous_view, view)
	_update_hud()
	return _success({"view_sequence": sequence, "visual_instance_id": _visual_instance_id})


func _track_pivot(previous_view: Dictionary, view: Dictionary) -> void:
	var role := String(view.get("presentation_role", ""))
	if role == ViewContract.ROLE_HANDOFF_HOLD:
		_event("SM0_P6_HANDOFF_HOLD_VISIBLE", {
			"player_entity_id": String(view.get("player_entity_id", "")),
			"owner_authority_id": String(view.get("owner_authority_id", "")),
			"authority_epoch": int(view.get("authority_epoch", 0)),
			"visual_instance_id": _visual_instance_id,
		})
		return
	if role not in [ViewContract.ROLE_CANONICAL, ViewContract.ROLE_PROJECTION]:
		return
	if _last_stable_role.is_empty():
		_last_stable_role = role
		return
	if role == _last_stable_role:
		return
	var previous_entity := String(previous_view.get("player_entity_id", String(view.get("player_entity_id", ""))))
	if previous_entity != String(view.get("player_entity_id", "")):
		_event("SM0_P6_VISUAL_IDENTITY_VIOLATION", {
			"previous_player_entity_id": previous_entity,
			"player_entity_id": String(view.get("player_entity_id", "")),
			"visual_instance_id": _visual_instance_id,
		})
		return
	_pivot_count += 1
	var event_name := "SM0_P6_PROJECTION_TO_CANONICAL" if role == ViewContract.ROLE_CANONICAL else "SM0_P6_CANONICAL_TO_PROJECTION"
	_event(event_name, {
		"pivot_index": _pivot_count,
		"player_entity_id": String(view.get("player_entity_id", "")),
		"owner_authority_id": String(view.get("owner_authority_id", "")),
		"authority_epoch": int(view.get("authority_epoch", 0)),
		"state_revision": int(view.get("state_revision", 0)),
		"visual_instance_id": _visual_instance_id,
		"command_channel": false,
	})
	_last_stable_role = role


func status_for_tests() -> Dictionary:
	return {
		"viewer_authority_id": _viewer_authority_id,
		"view_sequence": _last_view_sequence,
		"presentation_role": String(_current_view.get("presentation_role", "")),
		"player_entity_id": String(_current_view.get("player_entity_id", "")),
		"owner_authority_id": String(_current_view.get("owner_authority_id", "")),
		"canonical_writer": bool(_current_view.get("canonical_writer", false)),
		"read_only": bool(_current_view.get("read_only", true)),
		"held": bool(_current_view.get("held", false)),
		"command_channel": false,
		"pivot_count": _pivot_count,
		"visual_instance_id": _visual_instance_id,
		"position": Dictionary(_current_view.get("position", {})).duplicate(true),
	}


func shutdown(exit_code: int = 0, reason: String = "test") -> void:
	if _socket != null:
		_socket.close()
	set_process(false)
	_event("SM0_P6_OBSERVER_EXIT", {"exit_code": exit_code, "reason": reason, "visual_instance_id": _visual_instance_id})
	finished.emit(exit_code)


func _build_world() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.03, 0.04, 0.06)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.76, 0.86)
	environment.ambient_light_energy = 0.7
	environment_node.environment = environment
	add_child(environment_node)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	sun.light_energy = 1.1
	add_child(sun)
	_add_floor("WestAuthorityA", Vector3(-6.0, -0.08, 0.0), Color(0.10, 0.30, 0.52))
	_add_floor("EastAuthorityB", Vector3(6.0, -0.08, 0.0), Color(0.56, 0.27, 0.08))
	_add_boundary()

	_avatar = MeshInstance3D.new()
	_avatar.name = "PersistentPlayerAVisual"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.42
	capsule.height = 1.65
	_avatar.mesh = capsule
	_avatar_material = StandardMaterial3D.new()
	_avatar_material.roughness = 0.4
	_avatar.material_override = _avatar_material
	_avatar.visible = false
	add_child(_avatar)
	_visual_instance_id = int(_avatar.get_instance_id())

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 10.5, 12.5)
	camera.fov = 55.0
	add_child(camera)
	camera.look_at_from_position(camera.position, Vector3.ZERO, Vector3.UP)

	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(18.0, 18.0)
	panel.custom_minimum_size = Vector2(560.0, 190.0)
	canvas.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "SM0-P6 — PROJECTION / CANONICAL PIVOT"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	_hud = Label.new()
	_hud.text = "Waiting for player/a..."
	_hud.add_theme_font_size_override("font_size", 16)
	box.add_child(_hud)
	var legend := Label.new()
	legend.text = "WHITE = canonical · GREEN = read-only projection · YELLOW = handoff hold · same MeshInstance3D across pivot"
	legend.add_theme_font_size_override("font_size", 14)
	box.add_child(legend)


func _apply_role_material(role: String) -> void:
	if _avatar_material == null:
		return
	match role:
		ViewContract.ROLE_CANONICAL:
			_avatar_material.albedo_color = Color(0.92, 0.95, 1.0)
		ViewContract.ROLE_PROJECTION:
			_avatar_material.albedo_color = Color(0.35, 0.95, 0.55)
		ViewContract.ROLE_HANDOFF_HOLD:
			_avatar_material.albedo_color = Color(0.98, 0.82, 0.25)


func _add_floor(node_name: String, at: Vector3, color: Color) -> void:
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


func _to_world_position(position: Dictionary) -> Vector3:
	return Vector3(float(position.get("x", 0.0)), 0.82, float(position.get("z", 0.0)))


func _update_hud() -> void:
	if _hud == null:
		return
	_hud.text = "Viewer: %s\nEntity: %s\nRole: %s · owner=%s · epoch=%d\nrev=%d · pivot_count=%d · visual_instance_id=%d\ncommand channel: NONE" % [
		_viewer_authority_id,
		String(_current_view.get("player_entity_id", "")),
		String(_current_view.get("presentation_role", "")),
		String(_current_view.get("owner_authority_id", "")),
		int(_current_view.get("authority_epoch", 0)),
		int(_current_view.get("state_revision", 0)),
		_pivot_count,
		_visual_instance_id,
	]


func _rejected(error_code: String) -> Dictionary:
	_event("SM0_P6_VIEW_REJECTED", {"error_code": error_code, "visual_instance_id": _visual_instance_id})
	return _failure(error_code)


func _event(event_name: String, details: Dictionary = {}) -> void:
	var event := {
		"schema": "distributed_world_simulator.sm0_event.v1",
		"event": event_name,
		"severity": "INFO",
		"process_role": "observer-a" if _viewer_authority_id == Contracts.AUTHORITY_A else "observer-b",
		"process_id": OS.get_process_id(),
		"time_msec": Time.get_ticks_msec(),
		"authority_id": _viewer_authority_id,
		"writer_count": 0,
	}
	for key in details.keys():
		event[key] = details[key]
	print("[SM0_EVENT] %s" % JSON.stringify(event, "", false, true))


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
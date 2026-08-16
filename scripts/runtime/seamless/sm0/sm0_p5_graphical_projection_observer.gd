extends Node3D

signal finished(exit_code: int)

const Contracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")
const ViewContract = preload("res://scripts/runtime/seamless/sm0/sm0_p5_projection_view_contract.gd")

const VIEW_MESSAGE := "P5_PROJECTION_VIEW"
const STOP_POLL_INTERVAL_MS := 250
const VIEW_SCALE := 1.0

var _viewer_authority_id := ""
var _expected_local_player_id := ""
var _expected_remote_player_id := ""
var _listen_host := "127.0.0.1"
var _listen_port := 0
var _stop_file := ""
var _socket: PacketPeerUDP
var _last_stop_poll_ms := 0
var _last_view_sequence := 0
var _last_view_checksum := ""
var _local_view: Dictionary = {}
var _remote_view: Dictionary = {}
var _local_avatar: MeshInstance3D
var _remote_avatar: MeshInstance3D
var _hud: Label
var _status: Label
var _local_target := Vector3.ZERO
var _remote_target := Vector3.ZERO
var _local_visible_logged := false
var _remote_visible_logged := false
var _local_motion_logged := false
var _remote_motion_logged := false


func setup(config: Dictionary) -> Dictionary:
	_viewer_authority_id = String(config.get("viewer_authority_id", "")).strip_edges()
	_listen_host = String(config.get("listen_host", "127.0.0.1")).strip_edges()
	_listen_port = int(config.get("listen_port", 0))
	_stop_file = String(config.get("stop_file", "")).strip_edges()
	_expected_local_player_id = "a" if _viewer_authority_id == Contracts.AUTHORITY_A else "b"
	_expected_remote_player_id = "b" if _expected_local_player_id == "a" else "a"
	if _viewer_authority_id not in [Contracts.AUTHORITY_A, Contracts.AUTHORITY_B] or _listen_port < 1:
		return _failure("SM0_P5_GRAPHICAL_INVALID_CONFIGURATION")
	_build_world()
	_socket = PacketPeerUDP.new()
	var bind_error := _socket.bind(_listen_port, _listen_host)
	if bind_error != OK:
		return _failure("SM0_P5_GRAPHICAL_VIEW_BIND_FAILED", {"error": bind_error, "port": _listen_port})
	set_process(true)
	_event("SM0_P5_GRAPHICAL_VIEW_READY", {
		"listen_port": _listen_port,
		"expected_local_player_id": _expected_local_player_id,
		"expected_remote_player_id": _expected_remote_player_id,
		"command_channel": false,
	})
	return _success()


func _process(delta: float) -> void:
	_poll_view_packets()
	if _local_avatar != null and _local_avatar.visible:
		_local_avatar.position = _local_avatar.position.lerp(_local_target, clampf(delta * 12.0, 0.0, 1.0))
	if _remote_avatar != null and _remote_avatar.visible:
		_remote_avatar.position = _remote_avatar.position.lerp(_remote_target, clampf(delta * 12.0, 0.0, 1.0))
	var now := Time.get_ticks_msec()
	if not _stop_file.is_empty() and now - _last_stop_poll_ms >= STOP_POLL_INTERVAL_MS:
		_last_stop_poll_ms = now
		if FileAccess.file_exists(_stop_file):
			shutdown(0, "stop-file")


func _poll_view_packets() -> void:
	if _socket == null:
		return
	while _socket.get_available_packet_count() > 0:
		var message := Contracts.decode_message(_socket.get_packet())
		var message_check := Contracts.validate_message(message)
		if not bool(message_check.get("success", false)):
			_event("SM0_P5_GRAPHICAL_VIEW_REJECTED", {"error_code": String(message_check.get("error_code", "SM0_P5_GRAPHICAL_MESSAGE_INVALID"))})
			continue
		if String(message.get("type", "")) != VIEW_MESSAGE:
			continue
		accept_view_for_tests(Dictionary(message.get("payload", {})))


func accept_view_for_tests(view: Dictionary) -> Dictionary:
	var validation := ViewContract.validate(view)
	if not bool(validation.get("success", false)):
		return _view_rejected(String(validation.get("error_code", "SM0_P5_GRAPHICAL_VIEW_INVALID")))
	if String(view.get("viewer_authority_id", "")) != _viewer_authority_id:
		return _view_rejected("SM0_P5_GRAPHICAL_VIEWER_AUTHORITY_MISMATCH")
	var sequence := int(view.get("view_sequence", 0))
	var checksum := String(view.get("checksum", ""))
	if sequence < _last_view_sequence:
		return _success({"stale": true})
	if sequence == _last_view_sequence and _last_view_sequence > 0:
		if checksum != _last_view_checksum:
			return _view_rejected("SM0_P5_GRAPHICAL_SAME_SEQUENCE_MUTATION")
		return _success({"replay": true})
	var previous_local_position: Dictionary = Dictionary(_local_view.get("position", {})).duplicate(true)
	var previous_remote_position: Dictionary = Dictionary(_remote_view.get("position", {})).duplicate(true)
	_last_view_sequence = sequence
	_last_view_checksum = checksum
	_local_view = Dictionary(view.get("local_player", {})).duplicate(true)
	_remote_view = Dictionary(view.get("remote_projection", {})).duplicate(true)
	_update_presentations(previous_local_position, previous_remote_position)
	return _success({"view_sequence": sequence})


func _update_presentations(previous_local_position: Dictionary = {}, previous_remote_position: Dictionary = {}) -> void:
	var local_position := Dictionary(_local_view.get("position", {}))
	_local_target = _to_view_position(local_position)
	_local_avatar.visible = not _local_view.is_empty()
	if _local_avatar.visible and not _local_visible_logged:
		_local_visible_logged = true
		_event("SM0_P5_GRAPHICAL_LOCAL_VISIBLE", {
			"logical_player_id": String(_local_view.get("logical_player_id", "")),
			"owner_authority_id": String(_local_view.get("owner_authority_id", "")),
			"derived_view": true,
		})
	if (
		_local_avatar.visible
		and not _local_motion_logged
		and not previous_local_position.is_empty()
		and local_position != previous_local_position
	):
		_local_motion_logged = true
		_event("SM0_P5_GRAPHICAL_LOCAL_MOVED", {
			"logical_player_id": String(_local_view.get("logical_player_id", "")),
			"from_x": float(previous_local_position.get("x", 0.0)),
			"to_x": float(local_position.get("x", 0.0)),
			"state_revision": int(_local_view.get("state_revision", 0)),
			"derived_view": true,
		})
	if _remote_view.is_empty():
		_remote_avatar.visible = false
	else:
		var remote_position: Dictionary = Dictionary(_remote_view.get("position", {}))
		_remote_target = _to_view_position(remote_position)
		_remote_avatar.visible = true
		if not _remote_visible_logged:
			_remote_visible_logged = true
			_event("SM0_P5_GRAPHICAL_REMOTE_VISIBLE", {
				"logical_player_id": String(_remote_view.get("logical_player_id", "")),
				"owner_authority_id": String(_remote_view.get("owner_authority_id", "")),
				"read_only": bool(_remote_view.get("read_only", false)),
				"command_channel": false,
			})
		if (
			not _remote_motion_logged
			and not previous_remote_position.is_empty()
			and remote_position != previous_remote_position
		):
			_remote_motion_logged = true
			_event("SM0_P5_GRAPHICAL_REMOTE_MOVED", {
				"logical_player_id": String(_remote_view.get("logical_player_id", "")),
				"from_x": float(previous_remote_position.get("x", 0.0)),
				"to_x": float(remote_position.get("x", 0.0)),
				"state_revision": int(_remote_view.get("state_revision", 0)),
				"read_only": bool(_remote_view.get("read_only", false)),
				"command_channel": false,
			})
	_update_hud()


func status_for_tests() -> Dictionary:
	return {
		"viewer_authority_id": _viewer_authority_id,
		"local_player_id": String(_local_view.get("logical_player_id", "")),
		"remote_player_id": String(_remote_view.get("logical_player_id", "")),
		"local_visible": _local_avatar != null and _local_avatar.visible,
		"remote_visible": _remote_avatar != null and _remote_avatar.visible,
		"remote_read_only": bool(_remote_view.get("read_only", false)),
		"command_channel": false,
		"view_sequence": _last_view_sequence,
		"local_motion_observed": _local_motion_logged,
		"remote_motion_observed": _remote_motion_logged,
		"local_position": Dictionary(_local_view.get("position", {})).duplicate(true),
		"remote_position": Dictionary(_remote_view.get("position", {})).duplicate(true),
	}


func shutdown(exit_code: int = 0, reason: String = "test") -> void:
	if _socket != null:
		_socket.close()
	set_process(false)
	_event("SM0_P5_GRAPHICAL_PROCESS_EXIT", {"exit_code": exit_code, "reason": reason})
	finished.emit(exit_code)


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
	sun.light_energy = 1.1
	add_child(sun)
	_add_floor_half("WestAuthorityA", Vector3(-6.0, -0.08, 0.0), Color(0.10, 0.30, 0.52))
	_add_floor_half("EastAuthorityB", Vector3(6.0, -0.08, 0.0), Color(0.56, 0.27, 0.08))
	_add_boundary()
	_local_avatar = _create_avatar("LocalCanonicalDerivedView", Color(0.92, 0.95, 1.0))
	_remote_avatar = _create_avatar("RemoteReadOnlyProjection", Color(0.35, 0.95, 0.55))
	_local_avatar.visible = false
	_remote_avatar.visible = false
	add_child(_local_avatar)
	add_child(_remote_avatar)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 10.5, 12.5)
	camera.fov = 55.0
	add_child(camera)
	camera.look_at_from_position(camera.position, Vector3.ZERO, Vector3.UP)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(18.0, 18.0)
	panel.custom_minimum_size = Vector2(520.0, 180.0)
	canvas.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "SM0-P5.1 — CROSS-AUTHORITY PROJECTION VIEW"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	_hud = Label.new()
	_hud.text = "Waiting for projection view..."
	_hud.add_theme_font_size_override("font_size", 16)
	box.add_child(_hud)
	_status = Label.new()
	_status.text = "WHITE = local derived view · GREEN = remote read-only projection · observer has no command channel"
	_status.add_theme_font_size_override("font_size", 14)
	box.add_child(_status)


func _create_avatar(node_name: String, color: Color) -> MeshInstance3D:
	var avatar := MeshInstance3D.new()
	avatar.name = node_name
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.38
	capsule.height = 1.5
	avatar.mesh = capsule
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.4
	avatar.material_override = material
	return avatar


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


func _to_view_position(position: Dictionary) -> Vector3:
	return Vector3(float(position.get("x", 0.0)) * VIEW_SCALE, 0.75, float(position.get("z", 0.0)) * VIEW_SCALE)


func _update_hud() -> void:
	if _hud == null:
		return
	_hud.text = "Viewer: %s\nLocal: %s rev=%d\nRemote: %s rev=%d read-only=%s\nView sequence: %d · command channel: NONE" % [
		_viewer_authority_id,
		String(_local_view.get("player_entity_id", "")),
		int(_local_view.get("state_revision", 0)),
		String(_remote_view.get("player_entity_id", "none")),
		int(_remote_view.get("state_revision", 0)),
		str(bool(_remote_view.get("read_only", false))),
		_last_view_sequence,
	]


func _view_rejected(error_code: String) -> Dictionary:
	_event("SM0_P5_GRAPHICAL_VIEW_REJECTED", {"error_code": error_code})
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

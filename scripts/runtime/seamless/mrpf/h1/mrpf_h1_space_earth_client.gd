extends SceneTree

const Composer = preload("res://scripts/runtime/seamless/mrpf/mrpf_h0_hierarchical_composer.gd")
const Datagram = preload("res://scripts/runtime/seamless/mrpf/h1/mrpf_h1_projection_datagram.gd")
const Fixture = preload("res://scripts/runtime/seamless/mrpf/h1/mrpf_h1_space_earth_fixture.gd")

const EARTH_RADIUS := 1.6

var _composer := Composer.new()
var _space_peer := PacketPeerUDP.new()
var _earth_peer := PacketPeerUDP.new()
var _space_port := 0
var _earth_port := 0
var _evidence_path := ""
var _route_timeout_ms := 700
var _space_last_seen_ms := 0
var _earth_last_seen_ms := 0
var _space_alive := false
var _earth_alive := false
var _earth_active_revision := 0
var _route_sessions := {}
var _route_sequences := {}
var _phase := "WAIT_SPACE"
var _ever_fine := false
var _ever_fallback := false
var _errors: Array[String] = []
var _earth_visual: MeshInstance3D
var _camera: Camera3D
var _hud: Label
var _world: Node3D
var _last_selected_key := ""
var _visual_mode := "none"
var _visual_radial_segments := 0

func _initialize() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	_space_port = int(args.get("space-port", "0"))
	_earth_port = int(args.get("earth-port", "0"))
	_evidence_path = String(args.get("evidence-path", ""))
	_route_timeout_ms = max(200, int(args.get("route-timeout-ms", "700")))
	if _space_port < 1 or _earth_port < 1 or _evidence_path.is_empty():
		_record_error("MRPF_H1_CLIENT_ARGUMENT_INVALID")
		quit(2)
		return
	var err := _space_peer.bind(_space_port, "127.0.0.1")
	if err != OK:
		_record_error("MRPF_H1_SPACE_BIND_FAILED:%d" % err)
		quit(2)
		return
	err = _earth_peer.bind(_earth_port, "127.0.0.1")
	if err != OK:
		_record_error("MRPF_H1_EARTH_BIND_FAILED:%d" % err)
		quit(2)
		return
	_build_graphical_stand()
	_write_evidence()
	print("MRPF_H1_CLIENT_READY space_port=%d earth_port=%d" % [_space_port, _earth_port])

func _process(delta: float) -> bool:
	_poll_route(_space_peer, Fixture.SPACE_ROUTE_ID)
	_poll_route(_earth_peer, Fixture.EARTH_ROUTE_ID)
	_update_liveness()
	_update_composed_view()
	_update_camera(delta)
	return false

func _poll_route(peer: PacketPeerUDP, expected_route_id: String) -> void:
	while peer.get_available_packet_count() > 0:
		var decoded := Datagram.decode(peer.get_packet())
		if not bool(decoded.get("success", false)):
			_record_error("MRPF_H1_DATAGRAM_REJECTED:%s" % String(decoded.get("error_code", "")))
			continue
		var details: Dictionary = Dictionary(decoded["details"])
		var route_id := String(details.get("source_route_id", ""))
		if route_id != expected_route_id:
			_record_error("MRPF_H1_ROUTE_MISMATCH:%s:%s" % [expected_route_id, route_id])
			continue
		var session_id := String(details.get("source_session_id", ""))
		var sequence := int(details.get("sequence", 0))
		if _route_sessions.get(route_id, "") != session_id:
			_route_sessions[route_id] = session_id
			_route_sequences[route_id] = 0
		var last_sequence := int(_route_sequences.get(route_id, 0))
		if sequence <= last_sequence:
			continue
		_route_sequences[route_id] = sequence
		var representation: Dictionary = Dictionary(details.get("payload", {}))
		var accepted := _composer.accept_representation(representation)
		if not bool(accepted.get("success", false)):
			var code := String(accepted.get("error_code", ""))
			if code == "MRPF_H0_TOMBSTONED_REPLAY":
				continue
			_record_error("MRPF_H1_COMPOSER_REJECTED:%s" % code)
			continue
		var now := Time.get_ticks_msec()
		if route_id == Fixture.SPACE_ROUTE_ID:
			_space_last_seen_ms = now
			_space_alive = true
		else:
			_earth_last_seen_ms = now
			_earth_alive = true
			_earth_active_revision = int(representation.get("source_revision", 0))

func _update_liveness() -> void:
	var now := Time.get_ticks_msec()
	if _space_alive and now - _space_last_seen_ms > _route_timeout_ms:
		_space_alive = false
	if _earth_alive and now - _earth_last_seen_ms > _route_timeout_ms:
		_earth_alive = false
		if _earth_active_revision > 0:
			var removed := _composer.remove_representation(Fixture.EARTH_FINE_ID, _earth_active_revision)
			if not bool(removed.get("success", false)):
				_record_error("MRPF_H1_FINE_REMOVE_FAILED:%s" % String(removed.get("error_code", "")))
			_earth_active_revision = 0

func _update_composed_view() -> void:
	var composed := _composer.compose_view()
	if not bool(composed.get("success", false)):
		_record_error("MRPF_H1_COMPOSE_FAILED:%s" % String(composed.get("error_code", "")))
		return
	var details: Dictionary = Dictionary(composed["details"])
	var representations: Array = Array(details.get("representations", []))
	if representations.is_empty():
		return
	var selected: Dictionary = Dictionary(representations[0])
	if String(selected.get("canonical_subject_id", "")) != Fixture.EARTH_SUBJECT_ID:
		_record_error("MRPF_H1_SELECTED_SUBJECT_INVALID")
		return
	var selected_key := "%s:%d:%s" % [
		String(selected.get("representation_id", "")),
		int(selected.get("source_revision", 0)),
		String(details.get("view_hash", "")),
	]
	var domain := String(selected.get("domain_level", ""))
	var revision := int(selected.get("source_revision", 0))
	var next_phase := _phase
	if domain == "SPACE" and not _ever_fine:
		next_phase = "COARSE"
	elif domain == "EARTH":
		_ever_fine = true
		if _ever_fallback and revision >= 2:
			next_phase = "REFINED"
		else:
			next_phase = "FINE"
	elif domain == "SPACE" and _ever_fine:
		_ever_fallback = true
		next_phase = "FALLBACK"
	if selected_key != _last_selected_key or next_phase != _phase:
		_phase = next_phase
		_last_selected_key = selected_key
		_apply_visual(selected)
		_write_evidence(details, selected)
		print("MRPF_H1_CLIENT_PHASE phase=%s selected=%s revision=%d view_hash=%s" % [
			_phase,
			String(selected.get("representation_id", "")),
			revision,
			String(details.get("view_hash", "")),
		])

func _build_graphical_stand() -> void:
	_world = Node3D.new()
	_world.name = "MRPFH1World"
	get_root().add_child(_world)

	_earth_visual = MeshInstance3D.new()
	_earth_visual.name = "Earth"
	_world.add_child(_earth_visual)

	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.position = Vector3(0.0, 0.0, 8.0)
	_world.add_child(_camera)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25.0, -35.0, 0.0)
	light.light_energy = 1.6
	_world.add_child(light)

	var canvas := CanvasLayer.new()
	get_root().add_child(canvas)
	_hud = Label.new()
	_hud.position = Vector2(24.0, 24.0)
	_hud.text = "MRPF-H1 waiting for SPACE projection"
	canvas.add_child(_hud)

func _apply_visual(selected: Dictionary) -> void:
	var domain := String(selected.get("domain_level", ""))
	var mesh := SphereMesh.new()
	mesh.radius = EARTH_RADIUS
	mesh.height = EARTH_RADIUS * 2.0
	if domain == "EARTH":
		mesh.radial_segments = 48
		mesh.rings = 24
		_visual_mode = "fine"
		_visual_radial_segments = 48
	else:
		mesh.radial_segments = 12
		mesh.rings = 6
		_visual_mode = "coarse"
		_visual_radial_segments = 12
	var material := StandardMaterial3D.new()
	if domain == "EARTH":
		material.albedo_color = Color(0.08, 0.34, 0.82, 1.0)
		material.roughness = 0.6
	else:
		material.albedo_color = Color(0.12, 0.22, 0.52, 1.0)
		material.roughness = 0.9
	mesh.material = material
	_earth_visual.mesh = mesh
	_hud.text = "MRPF-H1  phase=%s\nSPACE=%s  EARTH=%s\nselected=%s  rev=%d  LOD=%d" % [
		_phase,
		"UP" if _space_alive else "DOWN",
		"UP" if _earth_alive else "DOWN",
		domain,
		int(selected.get("source_revision", 0)),
		int(selected.get("lod_level", -1)),
	]

func _update_camera(delta: float) -> void:
	if _camera == null:
		return
	var target_z := 4.8 if _phase in ["FINE", "REFINED"] else 8.0
	_camera.position.z = move_toward(_camera.position.z, target_z, delta * 2.2)
	_camera.look_at(Vector3.ZERO, Vector3.UP)

func _write_evidence(composed_details: Dictionary = {}, selected: Dictionary = {}) -> void:
	if _evidence_path.is_empty():
		return
	var state := {
		"schema": "distributed_world_simulator.mrpf_h1_client_evidence.v1",
		"phase": _phase,
		"space_route_alive": _space_alive,
		"earth_route_alive": _earth_alive,
		"selected_representation_id": String(selected.get("representation_id", "")),
		"selected_canonical_subject_id": String(selected.get("canonical_subject_id", "")),
		"selected_domain_level": String(selected.get("domain_level", "")),
		"selected_lod_level": int(selected.get("lod_level", -1)),
		"selected_source_revision": int(selected.get("source_revision", 0)),
		"view_hash": String(composed_details.get("view_hash", "")),
		"presentation_only": bool(composed_details.get("presentation_only", true)),
		"canonical_state_generated": bool(composed_details.get("canonical_state_generated", false)),
		"representation_count": _composer.representation_count(),
		"earth_node_count": 1 if _earth_visual != null and is_instance_valid(_earth_visual) else 0,
		"visual_mode": _visual_mode,
		"visual_radial_segments": _visual_radial_segments,
		"error_count": _errors.size(),
		"errors": _errors.duplicate(),
	}
	var temp_path := "%s.tmp.%d" % [_evidence_path, OS.get_process_id()]
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		printerr("MRPF_H1_EVIDENCE_WRITE_FAILED:%s" % temp_path)
		return
	file.store_string(JSON.stringify(state))
	file.flush()
	file = null
	if FileAccess.file_exists(_evidence_path):
		DirAccess.remove_absolute(_evidence_path)
	var rename_error := DirAccess.rename_absolute(temp_path, _evidence_path)
	if rename_error != OK:
		printerr("MRPF_H1_EVIDENCE_RENAME_FAILED:%d" % rename_error)

func _record_error(message: String) -> void:
	_errors.append(message)
	printerr(message)
	_write_evidence()

func _parse_args(raw_args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	for raw in raw_args:
		var text := String(raw)
		if not text.begins_with("--"):
			continue
		var body := text.substr(2)
		var split := body.split("=", true, 1)
		if split.size() == 2:
			result[String(split[0])] = String(split[1])
	return result

extends Node3D

# Two instances of this scene are ordinary graphical clients of one gateway.
# Visual bodies and the camera are created once and updated from read-only owner
# snapshots; an authority transition never recreates presentation objects.
const Protocol = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_process_protocol.gd")
const Support = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")
const InputDTO = preload("res://scripts/runtime/networked_gameplay/contracts/player_input_command.gd")

var cfg: Dictionary = {}
var actor := ""
var key := ""
var peer := "peer/enet/mvp3/live-gateway"
var boundary = null
var connected := 0
var disconnects := 0
var rpc_sequence := 0
var input_sequence := 0
var pending_kind := ""
var pending_rpc := 0
var last_send_ms := 0
var local_body: MeshInstance3D
var remote_body: MeshInstance3D
var camera: Camera3D
var hud: Label
var body_ids: Dictionary = {}
var route_history: Array[String] = []
var snapshots := 0
var both_visible_snapshots := 0
var failures: Array[String] = []
var finishing := false


func _ready() -> void:
	get_window().size = Vector2i(720, 480)
	cfg = Protocol.read_config()
	if cfg.is_empty() or cfg.get("role") not in ["client/a", "client/b"]:
		get_tree().quit(2)
		return
	actor = String(cfg["role"]).trim_prefix("client/")
	key = String(cfg.get("client_key", ""))
	if not Protocol.valid_key(key):
		finish(false, "MVP3_CLIENT_KEY_INVALID")
		return
	build_world()
	boundary = Support.make_boundary()
	if boundary == null:
		finish(false, "MVP3_CLIENT_BOUNDARY_FAILED")
		return
	var result: Dictionary = boundary.connect_client(Support.endpoint("127.0.0.1", int(cfg.get("gateway_port", 0))), peer, Protocol.session(cfg, actor), "route/mvp3/live/" + actor, 1)
	if not bool(result.get("success", false)):
		finish(false, "MVP3_CLIENT_CONNECT_FAILED")
		return
	get_window().title = "DWS MVP3 live client " + actor.to_upper()


func material(color: Color) -> StandardMaterial3D:
	var value := StandardMaterial3D.new()
	value.albedo_color = color
	value.metallic = 0.05
	value.roughness = 0.72
	return value


func player_mesh(name_value: String, color: Color) -> MeshInstance3D:
	var body := MeshInstance3D.new()
	body.name = name_value
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.45
	capsule.height = 1.8
	body.mesh = capsule
	body.material_override = material(color)
	add_child(body)
	return body


func build_world() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("17213a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b8c8eb")
	env.ambient_light_energy = 0.55
	environment.environment = env
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	light.light_energy = 1.15
	add_child(light)
	var ground := MeshInstance3D.new()
	ground.name = "SharedWorldGround"
	var box := BoxMesh.new()
	box.size = Vector3(24.0, 0.15, 10.0)
	ground.mesh = box
	ground.position.y = -1.0
	ground.material_override = material(Color("334b58"))
	add_child(ground)
	var seam := MeshInstance3D.new()
	seam.name = "AuthoritySeam"
	var seam_box := BoxMesh.new()
	seam_box.size = Vector3(0.08, 0.02, 10.0)
	seam.mesh = seam_box
	seam.position.y = -0.9
	seam.material_override = material(Color("f2b84b"))
	add_child(seam)
	local_body = player_mesh("LocalPlayerBody", Color("62d5ff") if actor == "a" else Color("ff8fb1"))
	remote_body = player_mesh("RemotePlayerBody", Color("ff8fb1") if actor == "a" else Color("62d5ff"))
	camera = Camera3D.new()
	camera.name = "PersistentPlayerCamera"
	camera.position = Vector3(0.0, 8.5, 12.0)
	camera.rotation_degrees = Vector3(-28.0, 0.0, 0.0)
	camera.current = true
	add_child(camera)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.name = "MVP3Status"
	hud.position = Vector2(20, 18)
	hud.add_theme_font_size_override("font_size", 19)
	layer.add_child(hud)
	body_ids = {"local": local_body.get_instance_id(), "remote": remote_body.get_instance_id(), "camera": camera.get_instance_id()}


func send_request(kind: String, body: Dictionary = {}) -> void:
	if not pending_kind.is_empty() or finishing:
		return
	rpc_sequence += 1
	pending_rpc = rpc_sequence
	pending_kind = kind
	var request := body.duplicate(true)
	request["kind"] = kind
	var packet := Protocol.seal(cfg, "client/" + actor, "gateway", rpc_sequence, request, key)
	var sent := Protocol.send(boundary, peer, packet)
	if not bool(sent.get("success", false)):
		finish(false, "MVP3_CLIENT_SEND_FAILED:" + String(sent.get("error_code", "")))
		return
	boundary.flush_outbound(32)
	last_send_ms = Time.get_ticks_msec()


func send_move(dx: float) -> void:
	input_sequence += 1
	var operation := "operation/mvp3/graphical/%s/%d" % [actor, input_sequence]
	var wire := InputDTO.create("message/mvp3/graphical/%s/%d" % [actor, input_sequence], operation, actor, Protocol.session(cfg, actor), 1, 1, input_sequence, "MOVEMENT_DELTA", {"delta_x": dx, "delta_z": 0.0})
	send_request("MOVE", {"wire": wire})


func apply_snapshot(snapshot: Dictionary) -> void:
	var players: Dictionary = snapshot.get("players", {})
	var a: Dictionary = players.get("a", {})
	var b: Dictionary = players.get("b", {})
	if a.is_empty() or b.is_empty():
		failures.append("MVP3_BOTH_PLAYERS_NOT_VISIBLE")
		return
	snapshots += 1
	both_visible_snapshots += 1
	var own: Dictionary = players[actor]
	var other: Dictionary = players["b" if actor == "a" else "a"]
	local_body.position = vector(own.get("position", {}))
	remote_body.position = vector(other.get("position", {}))
	var a_route := String(snapshot.get("decisions", {}).get("a", {}).get("active_authority_id", ""))
	if route_history.is_empty() or route_history.back() != a_route:
		route_history.append(a_route)
	var manual_hint := "\nManual: A/D or Left/Right; Esc when both routes are complete" if not bool(cfg.get("automated", false)) else ""
	hud.text = "MVP3 LIVE CLIENT %s\nGateway session: CONNECTED (%d)\nA route: %s  epoch: %s\nA x: %.2f  B x: %.2f\nLocal input sequence: %d\nBody/camera instances: %s / %s%s" % [actor.to_upper(), connected, a_route, str(snapshot.get("decisions", {}).get("a", {}).get("authority_epoch", "?")), float(a.get("position", {}).get("x", 0.0)), float(b.get("position", {}).get("x", 0.0)), input_sequence, str(body_ids["local"]), str(body_ids["camera"]), manual_hint]


func vector(value: Dictionary) -> Vector3:
	return Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0)))


func next_automated(snapshot: Dictionary) -> void:
	if not bool(cfg.get("automated", false)):
		return
	if not bool(snapshot.get("both_clients_ready", false)):
		send_request("OBSERVE")
		return
	if actor == "a":
		var decision: Dictionary = snapshot.get("decisions", {}).get("a", {})
		var complete := bool(snapshot.get("a_roundtrip_complete", false))
		if complete:
			send_request("FINISH")
		elif decision.get("active_authority_id") == "authority/b":
			send_move(-0.25)
		else:
			send_move(0.25)
	else:
		if bool(snapshot.get("a_roundtrip_complete", false)) and input_sequence >= 2:
			send_request("FINISH")
		else:
			send_move(0.25 if input_sequence % 2 == 0 else -0.25)


func handle_reply(packet: Dictionary) -> void:
	if not Protocol.verify(cfg, packet, "gateway", "client/" + actor, key) or int(packet.get("sequence", 0)) != pending_rpc:
		finish(false, "MVP3_CLIENT_REPLY_AUTH_INVALID")
		return
	var requested_kind := pending_kind
	pending_kind = ""
	var response: Dictionary = packet["body"]
	if not bool(response.get("success", false)):
		finish(false, "MVP3_CLIENT_COMMAND_REJECTED:" + String(response.get("error_code", "")))
		return
	var details: Dictionary = response.get("details", {})
	var snapshot: Dictionary = details.get("snapshot", {})
	apply_snapshot(snapshot)
	if requested_kind == "FINISH":
		finishing = true
		call_deferred("finish", true, "")
	else:
		next_automated(snapshot)


func _process(_delta: float) -> void:
	if boundary == null or finishing:
		return
	var polled: Dictionary = boundary.poll_events(64)
	if not bool(polled.get("success", false)):
		finish(false, "MVP3_CLIENT_POLL_FAILED")
		return
	for raw in polled.get("details", {}).get("events", []):
		var event: Dictionary = raw
		if event.get("event_type") == "PEER_CONNECTED":
			connected += 1
			if connected != 1 or not Support.mark_ready(boundary, peer):
				finish(false, "MVP3_CLIENT_RECONNECT_FORBIDDEN")
				return
			send_request("HELLO")
		elif event.get("event_type") == "PEER_DISCONNECTED":
			disconnects += 1
			finish(false, "MVP3_CLIENT_GATEWAY_DISCONNECTED")
			return
		elif event.get("event_type") == "MESSAGE_RECEIVED":
			handle_reply(Protocol.payload(event))
	boundary.flush_outbound(64)
	if not pending_kind.is_empty() and Time.get_ticks_msec() - last_send_ms > int(cfg.get("client_reply_timeout_ms", 30000)):
		finish(false, "MVP3_CLIENT_REPLY_TIMEOUT")


func _unhandled_input(event: InputEvent) -> void:
	if bool(cfg.get("automated", false)) or not event.is_pressed() or event.is_echo() or not pending_kind.is_empty():
		return
	if event is InputEventKey:
		if event.physical_keycode in [KEY_D, KEY_RIGHT]:
			send_move(0.25)
		elif event.physical_keycode in [KEY_A, KEY_LEFT]:
			send_move(-0.25)
		elif event.physical_keycode == KEY_ESCAPE:
			send_request("FINISH")


func finish(passed: bool, error_code: String) -> void:
	if finishing and not error_code.is_empty():
		return
	finishing = true
	if not error_code.is_empty():
		failures.append(error_code)
	var screenshot_path := String(cfg.get("screenshot_file", ""))
	var screenshot_saved := false
	if not screenshot_path.is_empty():
		var image := get_viewport().get_texture().get_image()
		screenshot_saved = image != null and image.get_width() > 0 and image.get_height() > 0 and image.save_png(screenshot_path) == OK
	var final_ids := {"local": local_body.get_instance_id() if local_body != null else 0, "remote": remote_body.get_instance_id() if remote_body != null else 0, "camera": camera.get_instance_id() if camera != null else 0}
	var report := {"schema": "distributed_world_simulator.mvp3_graphical_client.v1", "passed": passed and failures.is_empty() and connected == 1 and disconnects == 0 and body_ids == final_ids and both_visible_snapshots > 0, "subject_head": cfg.get("subject_head", ""), "run_id": cfg.get("run_id", ""), "actor": actor, "process_id": OS.get_process_id(), "transport_session_id": Protocol.session(cfg, actor), "connects": connected, "disconnects": disconnects, "input_sequence": input_sequence, "snapshots": snapshots, "both_visible_snapshots": both_visible_snapshots, "route_history": route_history, "initial_instance_ids": body_ids, "final_instance_ids": final_ids, "screenshot_file": screenshot_path, "screenshot_saved": screenshot_saved, "failures": failures, "reconnects": 0, "respawns": 0, "mvp3_predicate_verified": false}
	Support.write_json(String(cfg.get("result_file", "")), report)
	if boundary != null:
		boundary.stop()
	print("MVP3_GRAPHICAL_CLIENT actor=%s snapshots=%d passed=%s" % [actor, snapshots, report["passed"]])
	get_tree().quit(0 if bool(report["passed"]) else 1)

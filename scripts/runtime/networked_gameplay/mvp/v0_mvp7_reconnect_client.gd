extends SceneTree

const Protocol = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_process_protocol.gd")
const Support = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")
const InputDTO = preload("res://scripts/runtime/networked_gameplay/contracts/player_input_command.gd")
const RuntimeView6 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_derived_construction_runtime_view.gd")

var cfg: Dictionary = {}
var actor := "a"
var key := ""
var peer := "peer/enet/mvp7/reconnect-a"
var boundary = null
var sequence := 0
var pending := ""
var pending_sequence := 0
var last_send_ms := 0
var started_ms := 0
var failures: Array[String] = []
var hello_digest := ""
var after_digest := ""
var construction_checksum := ""
var matter_store_hash := ""
var matter_state_hash := ""
var material_digest := ""
var collision_part_count := 0
var position_before: Dictionary = {}
var position_after: Dictionary = {}
var fixed_receipt := false
var view = null


func _initialize() -> void:
	call_deferred("start7")


func fail7(code: String) -> void:
	if code not in failures:
		failures.append(code)
	finish7(false)


func start7() -> void:
	cfg = Protocol.read_config()
	if cfg.is_empty() or cfg.get("role") != "client/a":
		quit(2)
		return
	key = String(cfg.get("client_key", ""))
	if not Protocol.valid_key(key):
		fail7("MVP7_RECONNECT_CLIENT_KEY_INVALID")
		return
	boundary = Support.make_boundary()
	if boundary == null:
		fail7("MVP7_RECONNECT_BOUNDARY_FAILED")
		return
	var connected: Dictionary = boundary.connect_client(
		Support.endpoint("127.0.0.1", int(cfg.get("gateway_port", 0))),
		peer,
		Protocol.session(cfg, actor),
		"route/mvp7/reconnect/a",
		1
	)
	if not bool(connected.get("success", false)):
		fail7("MVP7_RECONNECT_CONNECT_FAILED")
		return
	started_ms = Time.get_ticks_msec()


func send7(kind: String, body: Dictionary = {}) -> void:
	if not pending.is_empty():
		return
	sequence += 1
	pending_sequence = sequence
	pending = kind
	var request := body.duplicate(true)
	request["kind"] = kind
	var packet := Protocol.seal(cfg, "client/a", "gateway", sequence, request, key)
	var sent := Protocol.send(boundary, peer, packet)
	if not bool(sent.get("success", false)):
		fail7("MVP7_RECONNECT_SEND_FAILED")
		return
	boundary.flush_outbound(32)
	last_send_ms = Time.get_ticks_msec()


func validate_current7(current: Dictionary, digest: String) -> bool:
	var snapshot: Dictionary = current.get("snapshot", {})
	var matter_source: Dictionary = current.get("matter_source", {})
	var construction: Dictionary = current.get("construction", {})
	var material: Dictionary = current.get("material", {})
	var player: Dictionary = current.get("player", {})
	if digest.length() != 64 or int(matter_source.get("stream_sequence", 0)) < 1:
		failures.append("MVP7_CURRENT_TERRAIN_REQUIRED")
		return false
	# MVP5 observers describe the pre-Construction checkpoint. Construction
	# legitimately consumes ore afterwards, so current recovery must validate
	# the fresh owner projection below rather than require that historical
	# material projection to remain byte-identical.
	if snapshot.get("mvp4", {}).get("both_observed") != true or snapshot.get("mvp6", {}).get("complete") != true:
		failures.append("MVP7_CURRENT_WORLD_NOT_COMPLETE")
		return false
	if Array(construction.get("parts", [])).size() != 100 or String(construction.get("checksum", "")).length() != 64:
		failures.append("MVP7_CURRENT_CONSTRUCTION_REQUIRED")
		return false
	if String(material.get("material_digest", "")).length() != 64 or String(material.get("item_graph_checksum", "")).length() != 64:
		failures.append("MVP7_CURRENT_ITEM_MATERIAL_REQUIRED")
		return false
	if String(player.get("logical_player_id", "")) != actor or String(player.get("transport_session_id", "")) != Protocol.session(cfg, actor):
		failures.append("MVP7_CURRENT_PLAYER_IDENTITY_INVALID")
		return false
	if view == null:
		view = RuntimeView6.new()
		get_root().add_child(view)
		var configured: Dictionary = view.setup("client/mvp7/reconnect/a")
		if not bool(configured.get("success", false)):
			failures.append("MVP7_RECONNECT_VIEW_SETUP_FAILED")
			return false
	var applied: Dictionary = view.apply_snapshot(construction)
	if not bool(applied.get("success", false)) or int(applied.get("part_count", 0)) != 100 or int(applied.get("collision_part_count", 0)) != 100:
		failures.append("MVP7_RECONNECT_COLLISION_DERIVATION_FAILED")
		return false
	construction_checksum = String(construction["checksum"])
	matter_store_hash = String(matter_source.get("store_hash", ""))
	matter_state_hash = String(matter_source.get("state_hash", ""))
	material_digest = String(material["material_digest"])
	collision_part_count = int(applied["collision_part_count"])
	return true


func handle_reply7(packet: Dictionary) -> void:
	if not Protocol.verify(cfg, packet, "gateway", "client/a", key) or int(packet.get("sequence", 0)) != pending_sequence:
		fail7("MVP7_RECONNECT_REPLY_AUTH_INVALID")
		return
	var requested := pending
	pending = ""
	var response: Dictionary = packet.get("body", {})
	if not bool(response.get("success", false)):
		fail7("MVP7_RECONNECT_COMMAND_REJECTED:" + String(response.get("error_code", "")))
		return
	var details: Dictionary = response.get("details", {})
	if requested == "MVP7_RECONNECT_HELLO":
		var current: Dictionary = details.get("current", {})
		hello_digest = String(details.get("world_digest", ""))
		if not validate_current7(current, hello_digest):
			finish7(false)
			return
		position_before = Dictionary(current.get("player", {}).get("position", {})).duplicate(true)
		var snapshot: Dictionary = current.get("snapshot", {})
		var input_sequence := int(snapshot.get("input_sequences", {}).get(actor, 0)) + 1
		var ownership_epoch := int(current.get("player", {}).get("ownership_epoch", 1))
		var operation := "operation/mvp7/reconnect/a/%d" % input_sequence
		var wire := InputDTO.create(
			"message/mvp7/reconnect/a/%d" % input_sequence,
			operation,
			actor,
			Protocol.session(cfg, actor),
			1,
			ownership_epoch,
			input_sequence,
			"MOVEMENT_INTENT",
			{"move_x": 0.35, "move_z": 0.0, "look_yaw": 0.0, "look_pitch": 0.0, "jump_pressed": false, "sprint": false, "delta_seconds": 1.0 / 60.0}
		)
		send7("MVP7_RECONNECT_CONTINUE", {"wire": wire})
	elif requested == "MVP7_RECONNECT_CONTINUE":
		after_digest = String(details.get("world_digest_after", ""))
		position_after = Dictionary(details.get("position_after", {})).duplicate(true)
		var current: Dictionary = details.get("current", {})
		if not bool(details.get("position_changed", false)) or position_after == position_before or after_digest != hello_digest or String(details.get("world_digest_before", "")) != hello_digest:
			fail7("MVP7_RECONNECT_CONTINUITY_INVALID")
			return
		if not validate_current7(current, after_digest):
			finish7(false)
			return
		var simulation: Dictionary = details.get("outcome", {}).get("details", {}).get("route_result", {}).get("outcome", {}).get("details", {}).get("server_simulation", {})
		fixed_receipt = simulation.get("fixed_tick") == true and is_equal_approx(float(simulation.get("delta_seconds", 0.0)), 1.0 / 60.0)
		if not fixed_receipt:
			fail7("MVP7_RECONNECT_FIXED_RECEIPT_MISSING")
			return
		send7("MVP7_RECONNECT_FINISH")
	elif requested == "MVP7_RECONNECT_FINISH":
		if details.get("reconnect_proved") != true:
			fail7("MVP7_RECONNECT_FINISH_NOT_PROVED")
			return
		finish7(true)


func _process(_delta: float) -> bool:
	if boundary == null:
		return false
	var polled: Dictionary = boundary.poll_events(64)
	if not bool(polled.get("success", false)):
		fail7("MVP7_RECONNECT_CLIENT_POLL_FAILED")
		return false
	for raw in polled.get("details", {}).get("events", []):
		var event: Dictionary = raw
		if event.get("event_type") == "PEER_CONNECTED":
			if not Support.mark_ready(boundary, peer):
				fail7("MVP7_RECONNECT_MARK_READY_FAILED")
				return false
			send7("MVP7_RECONNECT_HELLO")
		elif event.get("event_type") == "PEER_DISCONNECTED":
			fail7("MVP7_RECONNECT_GATEWAY_DISCONNECTED")
			return false
		elif event.get("event_type") == "MESSAGE_RECEIVED":
			handle_reply7(Protocol.payload(event))
	boundary.flush_outbound(64)
	if not pending.is_empty() and Time.get_ticks_msec() - last_send_ms > int(cfg.get("client_reply_timeout_ms", 30000)):
		fail7("MVP7_RECONNECT_REPLY_TIMEOUT")
	elif started_ms > 0 and Time.get_ticks_msec() - started_ms > 90000:
		fail7("MVP7_RECONNECT_CLIENT_TIMEOUT")
	return false


func finish7(requested_pass: bool) -> void:
	var passed := (
		requested_pass
		and failures.is_empty()
		and hello_digest.length() == 64
		and after_digest == hello_digest
		and position_before != position_after
		and collision_part_count == 100
		and fixed_receipt
	)
	var report := {
		"schema": "distributed_world_simulator.mvp7_enet_reconnect_client.v1",
		"passed": passed,
		"subject_head": cfg.get("subject_head", ""),
		"run_id": cfg.get("run_id", ""),
		"actor": actor,
		"process_id": OS.get_process_id(),
		"transport_session_id": Protocol.session(cfg, actor),
		"hello_world_digest": hello_digest,
		"after_world_digest": after_digest,
		"construction_checksum": construction_checksum,
		"matter_store_hash": matter_store_hash,
		"matter_state_hash": matter_state_hash,
		"material_digest": material_digest,
		"collision_part_count": collision_part_count,
		"position_before": position_before,
		"position_after": position_after,
		"position_changed": position_before != position_after and not position_before.is_empty(),
		"fixed_input_receipt": fixed_receipt,
		"failures": failures,
		"canonical_state_owned": false,
		"mvp7_predicate_verified": false,
	}
	Support.write_json(String(cfg.get("result_file", "")), report)
	if boundary != null:
		boundary.stop()
	print("MVP7_ENET_RECONNECT_CLIENT passed=", passed, " failures=", failures.size())
	quit(0 if passed else 1)

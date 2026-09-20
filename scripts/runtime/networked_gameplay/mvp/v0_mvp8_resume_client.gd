extends SceneTree

const Protocol8 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_process_protocol.gd")
const Support8 = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")
const InputDTO8 = preload("res://scripts/runtime/networked_gameplay/contracts/player_input_command.gd")
const RuntimeView8 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_derived_construction_runtime_view.gd")

var cfg: Dictionary = {}
var actor := ""
var key := ""
var peer := ""
var boundary = null
var rpc_sequence := 0
var pending_kind := ""
var pending_rpc := 0
var last_send_ms := 0
var started_ms := 0
var connects := 0
var disconnects := 0
var failures: Array[String] = []
var latest_snapshot: Dictionary = {}
var latest_current: Dictionary = {}
var moved_round := -1
var neutral_round := -1
var rounds_seen: Array[int] = []
var fixed_receipts := 0
var max_reply_ms := 0
var current_send_ms := 0
var collision_parts := 0
var construction_parts := 0
var construction_counts_seen: Array[int] = []
var current_world_digest := ""
var matter_resynced := false
var final_round := -1
var view = null


func _initialize() -> void:
	call_deferred("start8")


func fail8(code: String) -> void:
	if code not in failures:
		failures.append(code)
	finish8(false)


func start8() -> void:
	cfg = Protocol8.read_config()
	if cfg.is_empty() or cfg.get("role") not in ["client/a", "client/b"]:
		quit(2)
		return
	actor = String(cfg["role"]).trim_prefix("client/")
	key = String(cfg.get("client_key", ""))
	if not Protocol8.valid_key(key):
		fail8("MVP8_CLIENT_KEY_INVALID")
		return
	peer = "peer/enet/mvp8/%s/%s/%d" % [String(cfg.get("mvp8_client_phase", "resume")), actor, OS.get_process_id()]
	boundary = Support8.make_boundary()
	if boundary == null:
		fail8("MVP8_CLIENT_BOUNDARY_FAILED")
		return
	var connected: Dictionary = boundary.connect_client(
		Support8.endpoint("127.0.0.1", int(cfg.get("gateway_port", 0))),
		peer,
		Protocol8.session(cfg, actor),
		"route/mvp8/" + String(cfg.get("mvp8_client_phase", "resume")) + "/" + actor,
		1
	)
	if not bool(connected.get("success", false)):
		fail8("MVP8_CLIENT_CONNECT_FAILED")
		return
	started_ms = Time.get_ticks_msec()


func send8(kind: String, body: Dictionary = {}) -> void:
	if not pending_kind.is_empty():
		return
	rpc_sequence += 1
	pending_rpc = rpc_sequence
	pending_kind = kind
	var request := body.duplicate(true)
	request["kind"] = kind
	var packet := Protocol8.seal(cfg, "client/" + actor, "gateway", rpc_sequence, request, key)
	var sent := Protocol8.send(boundary, peer, packet)
	if not bool(sent.get("success", false)):
		fail8("MVP8_CLIENT_SEND_FAILED:" + String(sent.get("error_code", "")))
		return
	boundary.flush_outbound(32)
	last_send_ms = Time.get_ticks_msec()
	current_send_ms = last_send_ms


func _validate_current8(current: Dictionary, digest: String = "") -> bool:
	if current.is_empty():
		failures.append("MVP8_CURRENT_STATE_REQUIRED")
		return false
	var construction: Dictionary = current.get("construction", {})
	var material: Dictionary = current.get("material", {})
	var matter: Dictionary = current.get("matter", {})
	var player: Dictionary = current.get("player", {})
	var snapshot: Dictionary = current.get("snapshot", {})
	var workload: Dictionary = snapshot.get("mvp8", {})
	var action_counts: Dictionary = workload.get("action_counts", {})
	# Reuse the already accepted MVP6 phase contract. A completed ADD exposes
	# 101 parts/colliders until the matching REMOVE returns the same construct to
	# 100. Requiring 100 at every sample falsely rejects the legitimate round-10
	# intermediate state; final completion still requires 100 below.
	var expected_parts := 101 if int(action_counts.get("BUILD_ADD", 0)) > int(action_counts.get("BUILD_REMOVE", 0)) else 100
	construction_parts = Array(construction.get("parts", [])).size()
	if construction_parts != expected_parts or String(construction.get("checksum", "")).length() != 64:
		failures.append("MVP8_CURRENT_CONSTRUCTION_REQUIRED")
		return false
	if construction_parts not in construction_counts_seen:
		construction_counts_seen.append(construction_parts)
	if String(material.get("item_graph_checksum", "")).length() != 64 or int(matter.get("stream_sequence", -1)) < 1:
		failures.append("MVP8_CURRENT_ITEM_MATTER_REQUIRED")
		return false
	if String(player.get("logical_player_id", "")) != actor or String(player.get("transport_session_id", "")) != Protocol8.session(cfg, actor):
		failures.append("MVP8_CURRENT_PLAYER_INVALID")
		return false
	if view == null:
		view = RuntimeView8.new()
		get_root().add_child(view)
		var configured: Dictionary = view.setup("client/mvp8/" + actor)
		if not bool(configured.get("success", false)):
			failures.append("MVP8_RUNTIME_VIEW_SETUP_FAILED")
			return false
	var applied: Dictionary = view.apply_snapshot(construction)
	if not bool(applied.get("success", false)) or int(applied.get("collision_part_count", 0)) != expected_parts:
		failures.append("MVP8_CURRENT_COLLISION_REQUIRED")
		return false
	collision_parts = int(applied.get("collision_part_count", 0))
	if not digest.is_empty():
		current_world_digest = digest
	latest_current = current.duplicate(true)
	return true


func _send_move8(snapshot: Dictionary, round_index: int, neutral: bool = false) -> void:
	var player: Dictionary = snapshot.get("players", {}).get(actor, {})
	var epoch := int(player.get("ownership_epoch", 0))
	var input_sequence := int(snapshot.get("input_sequences", {}).get(actor, 0)) + 1
	if epoch < 1 or input_sequence < 1:
		fail8("MVP8_MOVE_WATERMARK_INVALID")
		return
	var decision: Dictionary = snapshot.get("decisions", {}).get("a", {})
	var axis := 0.0 if neutral else 1.0
	if not neutral:
		if actor == "a":
			axis = -1.0 if String(decision.get("active_authority_id", "authority/a")) == "authority/b" else 1.0
		else:
			var x := float(player.get("position", {}).get("x", 0.0))
			# Fresh/recovered B uses the same bounded controller as the original
			# client: always steer toward x=0, then send the explicit neutral tick.
			axis = -1.0 if x > 0.0 else 1.0
	var phase_tag := "neutral" if neutral else "move"
	var operation := "operation/mvp8/%s/round-%02d/%s-%d" % [actor, round_index, phase_tag, input_sequence]
	var wire := InputDTO8.create(
		"message/mvp8/%s/round-%02d/%s-%d" % [actor, round_index, phase_tag, input_sequence],
		operation,
		actor,
		Protocol8.session(cfg, actor),
		1,
		epoch,
		input_sequence,
		"MOVEMENT_INTENT",
		{"move_x": axis, "move_z": 0.0, "look_yaw": 0.0, "look_pitch": 0.0, "jump_pressed": false, "sprint": false, "delta_seconds": 1.0 / 60.0}
	)
	if neutral:
		neutral_round = round_index
	else:
		moved_round = round_index
	send8("MOVE", {"wire": wire})


func _advance8(snapshot: Dictionary) -> void:
	latest_snapshot = snapshot.duplicate(true)
	var state: Dictionary = snapshot.get("mvp8", {})
	if state.is_empty():
		send8("MVP8_STATUS")
		return
	var round_index := int(state.get("round", -1))
	final_round = round_index
	if round_index >= 0 and round_index not in rounds_seen:
		rounds_seen.append(round_index)
	if bool(state.get("recovery_boot", false)) and not matter_resynced:
		send8("MVP8_MATTER_CONNECT")
		return
	if bool(state.get("complete", false)) or bool(state.get("checkpointed", false)):
		send8("MVP8_PHASE_FINISH")
		return
	if bool(state.get("checkpoint_due", false)):
		if actor == "a":
			send8("MVP8_CHECKPOINT")
		else:
			send8("MVP8_STATUS")
		return
	if bool(state.get("reconnect_due", false)):
		# This client is the admitted replacement. The gateway flips
		# reconnect_complete before HELLO is handled, so a persistent due flag is
		# a protocol defect.
		fail8("MVP8_RECONNECT_STILL_DUE_AFTER_REPLACEMENT")
		return
	if moved_round != round_index:
		_send_move8(snapshot, round_index)
		return
	if neutral_round != round_index:
		_send_move8(snapshot, round_index, true)
		return
	var moves: Dictionary = state.get("round_moves", {})
	if actor == "a" and bool(moves.get("a", false)) and bool(moves.get("b", false)):
		send8("MVP8_ROUND", {"round": round_index})
	else:
		send8("MVP8_STATUS")


func handle_reply8(packet: Dictionary) -> void:
	if not Protocol8.verify(cfg, packet, "gateway", "client/" + actor, key) or int(packet.get("sequence", 0)) != pending_rpc:
		fail8("MVP8_CLIENT_REPLY_AUTH_INVALID")
		return
	max_reply_ms = maxi(max_reply_ms, Time.get_ticks_msec() - current_send_ms)
	var requested := pending_kind
	pending_kind = ""
	var response: Dictionary = packet.get("body", {})
	if not bool(response.get("success", false)):
		fail8("MVP8_CLIENT_COMMAND_REJECTED:" + requested + ":" + String(response.get("error_code", "")))
		return
	var details: Dictionary = response.get("details", {})
	var snapshot: Dictionary = details.get("snapshot", {})
	if requested == "MOVE":
		var simulation: Dictionary = details.get("outcome", {}).get("details", {}).get("route_result", {}).get("outcome", {}).get("details", {}).get("server_simulation", {})
		if simulation.get("fixed_tick") != true or not is_equal_approx(float(simulation.get("delta_seconds", 0.0)), 1.0 / 60.0):
			fail8("MVP8_FIXED_TICK_RECEIPT_MISSING")
			return
		fixed_receipts += 1
	elif requested == "MVP8_MATTER_CONNECT":
		matter_resynced = true
	elif requested == "MVP8_STATUS":
		var current: Dictionary = details.get("current", {})
		if not _validate_current8(current, String(current.get("world_digest", details.get("world_digest", "")))):
			finish8(false)
			return
	elif requested == "MVP8_ROUND":
		var current: Dictionary = details.get("current", {})
		if not current.is_empty() and not _validate_current8(current, String(current.get("world_digest", ""))):
			finish8(false)
			return
	if requested == "MVP8_PHASE_FINISH":
		finish8(true)
		return
	if snapshot.is_empty() and details.get("current", {}) is Dictionary:
		snapshot = Dictionary(details.get("current", {})).get("snapshot", {})
	if snapshot.is_empty():
		send8("MVP8_STATUS")
		return
	_advance8(snapshot)


func _process(_delta: float) -> bool:
	if boundary == null:
		return false
	var polled: Dictionary = boundary.poll_events(64)
	if not bool(polled.get("success", false)):
		fail8("MVP8_CLIENT_POLL_FAILED")
		return false
	for raw in polled.get("details", {}).get("events", []):
		var event: Dictionary = raw
		if event.get("event_type") == "PEER_CONNECTED":
			connects += 1
			if connects != 1 or not Support8.mark_ready(boundary, peer):
				fail8("MVP8_CLIENT_CONNECT_COUNT_INVALID")
				return false
			send8("HELLO")
		elif event.get("event_type") == "PEER_DISCONNECTED":
			disconnects += 1
			fail8("MVP8_CLIENT_GATEWAY_DISCONNECTED")
			return false
		elif event.get("event_type") == "MESSAGE_RECEIVED":
			handle_reply8(Protocol8.payload(event))
	boundary.flush_outbound(64)
	if not pending_kind.is_empty() and Time.get_ticks_msec() - last_send_ms > int(cfg.get("client_reply_timeout_ms", 90000)):
		fail8("MVP8_CLIENT_REPLY_TIMEOUT")
	elif started_ms > 0 and Time.get_ticks_msec() - started_ms > int(cfg.get("timeout_ms", 360000)):
		fail8("MVP8_CLIENT_TIMEOUT")
	return false


func finish8(requested_pass: bool) -> void:
	var passed := (
		requested_pass
		and failures.is_empty()
		and connects == 1
		and disconnects == 0
		and fixed_receipts > 0
		and collision_parts == 100
		and max_reply_ms > 0
	)
	var report := {
		"schema": "distributed_world_simulator.mvp8_resume_client.v1",
		"passed": passed,
		"subject_head": cfg.get("subject_head", ""),
		"subject_tree": cfg.get("subject_tree", ""),
		"run_id": cfg.get("run_id", ""),
		"actor": actor,
		"phase": cfg.get("mvp8_client_phase", ""),
		"process_id": OS.get_process_id(),
		"peer": peer,
		"connects": connects,
		"disconnects": disconnects,
		"rounds_seen": rounds_seen.duplicate(),
		"final_round": final_round,
		"neutral_round": neutral_round,
		"fixed_input_receipts": fixed_receipts,
		"max_reply_ms": max_reply_ms,
		"collision_part_count": collision_parts,
		"construction_part_count": construction_parts,
		"construction_counts_seen": construction_counts_seen.duplicate(),
		"current_world_digest": current_world_digest,
		"matter_resynced": matter_resynced,
		"failures": failures,
		"canonical_state_owned": false,
		"mvp8_predicate_verified": false,
	}
	Support8.write_json(String(cfg.get("result_file", "")), report)
	if boundary != null:
		boundary.stop()
	print("MVP8_RESUME_CLIENT actor=", actor, " phase=", cfg.get("mvp8_client_phase", ""), " passed=", passed)
	quit(0 if passed else 1)

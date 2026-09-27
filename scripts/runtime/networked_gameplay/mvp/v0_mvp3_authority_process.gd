extends SceneTree

# One native M3 Service instance per authority process. The thin derived
# Service adds a fixed-input receipt method to that same canonical owner.
const Protocol = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_process_protocol.gd")
const Support = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")
const Service = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_fixed_tick_gameplay_service.gd")
const Views = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_remote_owner_views.gd")
const Scheduler = preload("res://scripts/network/simulation/fixed_tick_scheduler.gd")
var cfg: Dictionary = {}
var boundary = null
var service = null
var live_port = null
var clock = null
var decisions: Dictionary = {}
var source_view = null
var authority := ""
var gateway_peer := ""
var key := ""
var received_sequence := 0
var received_requests := 0
var auth_rejections := 0
var connected_peers: Dictionary = {}
var disconnects_during_workload := 0
var input_accepts := {"a": 0, "b": 0}
var fixed_input_accepts := {"a": 0, "b": 0}
var held_simulation_ticks := {"a": 0, "b": 0}
# Input buffers are noncanonical transport state; no player state is stored.
# A target starts neutral and waits for fresh client input after activation.
var held_inputs: Dictionary = {}
var pending_fixed_wire: Dictionary = {}
var pending_fixed_sequence := 0
var lifecycle: Array[Dictionary] = []
var started_ms := 0
var closing_ms := 0
var error_code := ""
var initial_snapshot: Dictionary = {}
var initial_graph: Dictionary = {}

func _initialize() -> void:
	call_deferred("start")

func start() -> void:
	cfg = Protocol.read_config()
	if cfg.is_empty() or cfg.get("role") not in ["authority/a", "authority/b"]:
		quit(2)
		return
	authority = String(cfg["role"])
	key = String(cfg.get("internal_keys", {}).get(authority, ""))
	var port := int(cfg.get("ports", {}).get(authority, 0))
	if not Protocol.valid_key(key) or port < 1 or port > 65535:
		finish(false, "MVP3_AUTHORITY_CONFIG_INVALID")
		return
	boundary = Support.make_boundary()
	if boundary == null or not bool(boundary.start_server(Support.endpoint("127.0.0.1", port)).get("success", false)):
		finish(false, "MVP3_AUTHORITY_LISTEN_FAILED")
		return
	started_ms = Time.get_ticks_msec()
	Support.write_state(String(cfg["result_file"]), "LISTENING", {"subject_head": cfg["subject_head"], "run_id": cfg["run_id"], "authority_id": authority})

func send_reply(sequence_value: int, response: Dictionary) -> bool:
	var signed := Protocol.seal(cfg, authority, "gateway", sequence_value, response, key)
	if not bool(Protocol.send(boundary, gateway_peer, signed).get("success", false)):
		finish(false, "MVP3_AUTHORITY_REPLY_FAILED")
		return false
	return true

func native_envelope(kind: String, actor: String, result: Dictionary, operation_id: String = "") -> Dictionary:
	var receipt: Dictionary = service.export_live_player_replay(actor).get(operation_id, {}) if kind == "MOVE" and service != null else {}
	return Protocol.success({"kind": kind, "actor": actor, "result": result, "snapshot": service.create_snapshot() if service != null else {}, "receipt": receipt, "authority_id": authority, "authority_process_id": OS.get_process_id()})

func simulate_inputs_for_tick() -> bool:
	for actor in ["a", "b"]:
		if not live_port.actor_ready(actor):
			held_inputs.erase(actor)
		var first_step_applied := false
		if not pending_fixed_wire.is_empty() and pending_fixed_wire.get("logical_player_id") == actor:
			var wire := pending_fixed_wire.duplicate(true)
			var sequence_value := pending_fixed_sequence
			pending_fixed_wire.clear()
			pending_fixed_sequence = 0
			var result: Dictionary = service.handle_live_fixed_player_input(wire, 1.0 / 60.0)
			first_step_applied = bool(result.get("success", false)) and not bool(result.get("replay", false))
			if first_step_applied:
				held_inputs[actor] = wire
				input_accepts[actor] += 1
				fixed_input_accepts[actor] += 1
			if not send_reply(sequence_value, native_envelope("MOVE", actor, result, String(wire["operation_id"]))):
				return false
		if first_step_applied or not held_inputs.has(actor) or not live_port.actor_ready(actor):
			continue
		var held: Dictionary = held_inputs[actor]
		var intent: Dictionary = Dictionary(held["payload"]).duplicate(true)
		# Edge-triggered jump cannot be repeated by holding the same packet.
		intent["jump_pressed"] = false
		var simulated: Dictionary = service.simulate_fixed_movement_tick(actor, String(held["transport_session_id"]), int(held["ownership_epoch"]), int(held["input_sequence"]), intent, 1.0 / 60.0)
		if not bool(simulated.get("success", false)):
			finish(false, "MVP3_HELD_FIXED_INPUT_REJECTED:" + String(simulated.get("error_code", "")))
			return false
		held_simulation_ticks[actor] += 1
	return true

func _process(delta: float) -> bool:
	if boundary == null:
		return false
	if clock != null and closing_ms == 0:
		var advanced: Dictionary = clock.advance(delta)
		if not bool(advanced.get("success", false)):
			finish(false, "MVP3_FIXED_CLOCK_FAILED")
			return false
		var ticks: Dictionary = advanced["details"]
		for tick in range(int(ticks["first_tick"]), int(ticks["last_tick"]) + 1) if int(ticks["tick_count"]) > 0 else []:
			if not bool(service.advance_fixed_server_tick(tick).get("success", false)):
				finish(false, "MVP3_NATIVE_FIXED_CLOCK_FAILED")
				return false
			if not simulate_inputs_for_tick():
				return false
	var polled: Dictionary = boundary.poll_events(128)
	if not bool(polled.get("success", false)):
		finish(false, "MVP3_AUTHORITY_POLL_FAILED")
		return false
	for raw in polled.get("details", {}).get("events", []):
		var event: Dictionary = raw
		var peer := String(event.get("peer_id", ""))
		if event.get("event_type") == "PEER_CONNECTED":
			connected_peers[peer] = true
			Support.mark_ready(boundary, peer)
		elif event.get("event_type") == "PEER_DISCONNECTED" and peer == gateway_peer and closing_ms == 0:
			disconnects_during_workload += 1
			finish(false, "MVP3_GATEWAY_DISCONNECTED")
			return false
		elif event.get("event_type") == "MESSAGE_RECEIVED":
			var packet := Protocol.payload(event)
			if not Protocol.verify(cfg, packet, "gateway", authority, key):
				auth_rejections += 1
				continue
			if not gateway_peer.is_empty() and gateway_peer != peer:
				auth_rejections += 1
				continue
			if int(packet["sequence"]) != received_sequence + 1:
				auth_rejections += 1
				continue
			if not pending_fixed_wire.is_empty():
				finish(false, "MVP3_RPC_DURING_PENDING_FIXED_INPUT")
				return false
			gateway_peer = peer
			received_sequence = int(packet["sequence"])
			received_requests += 1
			var response := handle_rpc(packet["body"])
			if pending_fixed_wire.is_empty():
				if not send_reply(received_sequence, response):
					return false
			else:
				pending_fixed_sequence = received_sequence
	boundary.flush_outbound(128)
	if closing_ms > 0 and Time.get_ticks_msec() >= closing_ms:
		finish(true, "")
	elif closing_ms == 0 and Time.get_ticks_msec() - started_ms > int(cfg.get("timeout_ms", 180000)):
		finish(false, "MVP3_AUTHORITY_TIMEOUT")
	return false

func ingest_decisions(body: Dictionary) -> Dictionary:
	var incoming: Dictionary = body.get("decisions", {})
	var completed: Dictionary = body.get("completed", {})
	for actor in ["a", "b"]:
		if not incoming.get(actor) is Dictionary:
			return Protocol.failure("MVP3_AUTHENTICATED_DECISIONS_REQUIRED")
		if not decisions.has(actor):
			decisions[actor] = Views.DecisionView.new()
		var ingested: Dictionary = decisions[actor].ingest(actor, incoming[actor], completed.get(actor, {}))
		if not bool(ingested.get("success", false)):
			return ingested
	return Protocol.success()

func initialize_owner() -> Dictionary:
	service = Service.new()
	var setup: Dictionary = service.setup(authority, 1, 0, {"profile": Service.PROFILE_MULTIPLAYER_CORE, "topology_adapter": "ENET", "region_id": "region/mvp3/" + authority, "fixed_tick_authority": true})
	if not bool(setup.get("success", false)):
		return setup
	if authority == "authority/a":
		for actor in ["a", "b"]:
			var joined: Dictionary = service.join(actor, Protocol.session(cfg, actor), "operation/mvp3/" + String(cfg["run_id"]) + "/join/" + actor)
			if not bool(joined.get("success", false)):
				return joined
	initial_snapshot = service.create_snapshot()
	initial_graph = service.create_canonical_item_graph_snapshot()
	live_port = service.get_live_player_transfer_port()
	if live_port == null:
		return Protocol.failure("MVP3_NATIVE_LIVE_PORT_MISSING")
	var other := "authority/b" if authority == "authority/a" else "authority/a"
	source_view = Views.SourceReceiptView.new()
	source_view.config = cfg.duplicate(true)
	source_view.source_authority = other
	source_view.source_key = String(cfg["internal_keys"][other])
	var peer_setup: Dictionary = live_port.register_peer(other, source_view)
	if not bool(peer_setup.get("success", false)):
		return peer_setup
	for actor in ["a", "b"]:
		var bound: Dictionary = live_port.bind_player(actor, Protocol.session(cfg, actor), 1, decisions[actor])
		if not bool(bound.get("success", false)):
			return bound
	clock = Scheduler.new()
	return clock.configure(60, 8, 0)

func handle_rpc(body: Dictionary) -> Dictionary:
	var kind := String(body.get("kind", ""))
	if closing_ms > 0:
		return Protocol.failure("MVP3_AUTHORITY_STOPPING")
	var views_ready := ingest_decisions(body)
	if not bool(views_ready.get("success", false)):
		return views_ready
	var actor := String(body.get("actor", ""))
	var result: Dictionary
	if kind == "INIT":
		if service != null:
			return Protocol.failure("MVP3_DUPLICATE_NATIVE_BOOTSTRAP")
		result = initialize_owner()
	elif service == null:
		return Protocol.failure("MVP3_NATIVE_OWNER_NOT_INITIALIZED")
	elif kind == "SYNC":
		result = Protocol.success({"ready": {"a": live_port.actor_ready("a"), "b": live_port.actor_ready("b")}})
	elif kind == "LOOKUP":
		if actor not in ["a", "b"]:
			return Protocol.failure("MVP3_UNKNOWN_ACTOR")
		result = Protocol.success({"ready": live_port.actor_ready(actor), "receipt": service.export_live_player_replay(actor).get(String(body.get("operation_id", "")), {}), "player": service.get_player(actor)})
	elif kind == "MOVE":
		if actor not in ["a", "b"] or not body.get("wire") is Dictionary or body["wire"].get("logical_player_id") != actor or body["wire"].get("transport_session_id") != Protocol.session(cfg, actor):
			return Protocol.failure("MVP3_INPUT_ACTOR_BINDING_INVALID")
		if body["wire"].get("input_kind") == "MOVEMENT_INTENT":
			# Reply only after an actual canonical fixed tick produced a receipt.
			pending_fixed_wire = Dictionary(body["wire"]).duplicate(true)
			return {}
		result = service.handle_live_player_input(body["wire"])
		if bool(result.get("success", false)) and not bool(result.get("replay", false)):
			input_accepts[actor] += 1
	elif kind in ["EXPORT", "STAGE", "RETIRE", "ACTIVATE", "ABORT_STAGE"]:
		if actor not in ["a", "b"]:
			return Protocol.failure("MVP3_UNKNOWN_ACTOR")
		var transfer_id := String(body.get("transfer_id", ""))
		if kind in ["STAGE", "ACTIVATE"]:
			var attested: Dictionary = source_view.ingest(body.get("source_attestation", {}))
			if not bool(attested.get("success", false)):
				return attested
		match kind:
			"EXPORT": result = live_port.prepare_export(actor, transfer_id, body.get("manifest", {}))
			"STAGE": result = live_port.stage_export(actor, body.get("packet", {}))
			"RETIRE": result = live_port.retire_source(actor, transfer_id, String(body.get("commit_token", "")))
			"ACTIVATE": result = live_port.activate_target(actor, transfer_id, String(body.get("commit_token", "")))
			"ABORT_STAGE": result = live_port.discard_aborted_stage(actor, transfer_id)
		if bool(result.get("success", false)) and kind in ["EXPORT", "RETIRE", "ACTIVATE", "ABORT_STAGE"]:
			held_inputs.erase(actor)
		lifecycle.append({"kind": kind, "actor": actor, "transfer_id": transfer_id, "success": result.get("success", false), "error_code": result.get("error_code", ""), "ready_after": live_port.actor_ready(actor), "rpc_sequence": received_sequence, "process_id": OS.get_process_id()})
	elif kind == "REPORT":
		result = Protocol.success({"report": report(false, "RUNNING")})
	elif kind == "STOP":
		closing_ms = Time.get_ticks_msec() + 100
		held_inputs.clear()
		result = Protocol.success()
	else:
		return Protocol.failure("MVP3_UNKNOWN_RPC")
	return native_envelope(kind, actor, result, String(body.get("wire", {}).get("operation_id", "")))

func report(passed: bool, phase: String) -> Dictionary:
	return {"schema": "distributed_world_simulator.mvp3_native_authority_process.v1", "state": phase, "passed": passed, "error": error_code, "subject_head": cfg.get("subject_head", ""), "run_id": cfg.get("run_id", ""), "process_id": OS.get_process_id(), "authority_id": authority, "authenticated_gateway_connections": 1 if not gateway_peer.is_empty() else 0, "disconnects_during_workload": disconnects_during_workload, "auth_rejections": auth_rejections, "received_requests": received_requests, "input_accepts": input_accepts.duplicate(), "fixed_input_accepts": fixed_input_accepts.duplicate(), "held_simulation_ticks": held_simulation_ticks.duplicate(), "lifecycle": lifecycle.duplicate(true), "initial_snapshot": initial_snapshot, "final_snapshot": service.create_snapshot() if service != null else {}, "initial_item_graph": initial_graph, "final_item_graph": service.create_canonical_item_graph_snapshot() if service != null else {}, "clock": clock.get_report() if clock != null else {}, "live_port": live_port.get_report() if live_port != null else {}, "mvp3_predicate_verified": false}

func finish(passed: bool, code: String) -> void:
	error_code = code
	var saved := Support.write_json(String(cfg.get("result_file", "")), report(passed, "COMPLETE" if passed else "FAILED"))
	if boundary != null:
		boundary.stop()
		boundary = null
	if service != null:
		service.shutdown()
	key = ""
	print("MVP3_NATIVE_AUTHORITY %s passed=%s error=%s" % [authority, passed, code])
	quit(0 if passed and saved else 1)

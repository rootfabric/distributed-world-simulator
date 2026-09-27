extends SceneTree

# Headless product gateway composition for two native M3 authority processes.
# Canonical player state stays in those processes. Existing P6 and SM1 objects
# remain the identity/replay/admission and transfer-decision owners.
const Protocol = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_process_protocol.gd")
const BackendLink = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_backend_link.gd")
const RemoteRoute = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_remote_player_command_route.gd")
const Identity = preload("res://scripts/runtime/networked_gameplay/p6/p6_identity_registry.gd")
const Ledger = preload("res://scripts/runtime/networked_gameplay/p6/p6_operation_ledger.gd")
const Admission = preload("res://scripts/runtime/networked_gameplay/p6/p6_mutation_admission.gd")
const Closure = preload("res://scripts/runtime/networked_gameplay/p6/p6_closure_adapter.gd")
const Coordinator = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_authority_transfer_coordinator.gd")
const Carry = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_player_carrying_domain.gd")
const Pivot = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_gateway_route_pivot.gd")
const InputDTO = preload("res://scripts/runtime/networked_gameplay/contracts/player_input_command.gd")
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Support = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")

var cfg: Dictionary = {}
var links: Dictionary = {}
var coordinators: Dictionary = {}
var carrying: Dictionary = {}
var pivots: Dictionary = {}
var routes: Array = []
var completed_ids := {"a": "", "b": ""}
var sequences := {"a": 0, "b": 0}
var last_commands: Dictionary = {}
var operation_fingerprints: Dictionary = {}
var assertions := 0
var failures: Array[String] = []
var transfers: Array[Dictionary] = []
# Bounded read-only copies of actual native receipts, not another player owner.
var input_observations := {"a": [], "b": []}
var identity = null
var ledger = null
var admission = null
var closure = null
var interactive := false
var client_boundary = null
var client_peers: Dictionary = {}
var client_sequences := {"a": 0, "b": 0}
var client_hello := {"a": false, "b": false}
var client_finished := {"a": false, "b": false}
var pending_continuity := {"a": "", "b": ""}
var closing_at_ms := 0
var started_at_ms := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> bool:
	assertions += 1
	if not ok:
		failures.append(message)
		push_error(message)
	return ok


func success(result: Dictionary, message: String) -> bool:
	return check(bool(result.get("success", false)), message + ": " + String(result.get("error_code", "")))


func decision_payload() -> Dictionary:
	var decisions: Dictionary = {}
	var completed: Dictionary = {}
	for actor in ["a", "b"]:
		decisions[actor] = coordinators[actor].snapshot()
		var transfer_id := String(completed_ids[actor])
		var prior: Dictionary = coordinators[actor].get_completed_transfer(transfer_id) if not transfer_id.is_empty() else {}
		completed[actor] = prior if prior.get("target_epoch") == decisions[actor].get("authority_epoch") else {}
	return {"decisions": decisions, "completed": completed}


func operation_fingerprint(actor: String, operation_id: String) -> String:
	return String(operation_fingerprints.get(actor + "\n" + operation_id, ""))


func record_operation_fingerprint(actor: String, operation_id: String, fingerprint: String) -> void:
	var key := actor + "\n" + operation_id
	if not operation_fingerprints.has(key):
		operation_fingerprints[key] = fingerprint


func call_authority(authority: String, body: Dictionary) -> Dictionary:
	if not links.has(authority):
		return Protocol.failure("MVP3_GATEWAY_AUTHORITY_UNKNOWN")
	var request := body.duplicate(true)
	var views := decision_payload()
	request["decisions"] = views["decisions"]
	request["completed"] = views["completed"]
	return links[authority].rpc_call(request)


func command(actor: String, sequence: int, dx: float, suffix: String = "") -> Dictionary:
	# Historical native diagnostic uses the original public delta contract.
	# Interactive clients below are required to submit fixed-tick intent.
	var operation := "operation/mvp3/process/%s/%d%s" % [actor, sequence, suffix]
	var wire := InputDTO.create("message/mvp3/process/%s/%d%s" % [actor, sequence, suffix], operation, actor, Protocol.session(cfg, actor), 1, 1, sequence, "MOVEMENT_DELTA", {"delta_x": dx, "delta_z": 0.0})
	return {"domain_id": "p6-domain/outpost-world-state", "command_kind": "PLAYER_INTERACTION", "operation_id": operation, "wire": wire}


func move(actor: String, dx: float) -> Dictionary:
	sequences[actor] += 1
	var cmd := command(actor, int(sequences[actor]), dx)
	var result: Dictionary = pivots[actor].route_command("client-session/mvp3/" + actor, cmd["operation_id"], cmd)
	if success(result, "independent native movement " + actor):
		last_commands[actor] = cmd
	return result


func native_result(rpc: Dictionary) -> Dictionary:
	return Dictionary(rpc.get("details", {}).get("result", {})).duplicate(true) if bool(rpc.get("success", false)) else rpc


func lookup(authority: String, actor: String) -> Dictionary:
	var rpc := call_authority(authority, {"kind": "LOOKUP", "actor": actor, "operation_id": String(last_commands.get(actor, {}).get("operation_id", ""))})
	return Dictionary(rpc.get("details", {}).get("result", {}).get("details", {}).get("player", {})).duplicate(true) if bool(rpc.get("success", false)) else {}


func cross(actor: String, target: String, transfer_id: String, prove_other_input: bool = true, prove_post_input: bool = true) -> bool:
	var coordinator = coordinators[actor]
	var carry = carrying[actor]
	var pivot = pivots[actor]
	var decision: Dictionary = coordinator.snapshot()
	var source := String(decision["active_authority_id"])
	var source_epoch := int(decision["authority_epoch"])
	var requested_before := lookup(source, actor)
	var route_identity: Dictionary = pivot.get_client_route_identity()
	if not check(not requested_before.is_empty(), "source canonical actor exists") or not success(coordinator.begin_transfer(transfer_id, source, target, source_epoch), "SM1 source freeze"):
		return false
	var other := "b" if actor == "a" else "a"
	if prove_other_input and not bool(move(other, -0.25).get("success", false)):
		return false
	var prepared: Dictionary = carry.prepare_transfer(transfer_id, "client-session/mvp3/" + actor, int(sequences[actor]), String(last_commands[actor]["operation_id"]))
	if not success(prepared, "P6 carrying manifest"):
		return false
	var exported_rpc := call_authority(source, {"kind": "EXPORT", "actor": actor, "transfer_id": transfer_id, "manifest": prepared["details"]["manifest"]})
	var exported := native_result(exported_rpc)
	if not success(exported, "native source export"):
		return false
	var packet: Dictionary = exported["details"]["packet"]
	check(not packet.has("players") and not packet.has("canonical_item_graph"), "transfer remains player bounded")
	# The authoritative freeze cut is the native source export after it has
	# ingested the SM1 freeze. A pre-request observation may precede real ticks;
	# its position is not a legitimate restore target. Identity/input watermark
	# must be unchanged, and the frozen record must be installed byte-for-byte.
	var before: Dictionary = Dictionary(packet.get("player", {})).duplicate(true)
	for field in ["logical_player_id", "player_entity_id", "transport_session_id", "ownership_epoch", "last_input_sequence"]:
		if not check(before.get(field) == requested_before.get(field), "native freeze identity and input cut " + field):
			return false
	if not check(int(before.get("state_revision", -1)) >= int(requested_before.get("state_revision", 0)), "native freeze revision cannot regress"):
		return false
	var source_attestation: Dictionary = links[source].last_signed_reply.duplicate(true)
	var staged_rpc := call_authority(target, {"kind": "STAGE", "actor": actor, "transfer_id": transfer_id, "packet": packet, "source_attestation": source_attestation})
	var staged := native_result(staged_rpc)
	if not success(staged, "native target stage"):
		return false
	check(lookup(target, actor).is_empty(), "warm target not writable or authoritative")
	var warm: Dictionary = carry.build_composite_warm_report(transfer_id, staged["details"]["shadow_report"])
	if not success(warm, "composite WARM report") or not success(coordinator.validate_warm_target(transfer_id, target, warm["details"]["warm_report"]), "SM1 WARM validation"):
		return false
	var committed: Dictionary = coordinator.commit_ownership(transfer_id, source, target, source_epoch, source_epoch + 1)
	if not success(committed, "SM1 ownership commit"):
		return false
	var token := String(committed["details"]["commit_token"])
	var early := native_result(call_authority(target, {"kind": "ACTIVATE", "actor": actor, "transfer_id": transfer_id, "commit_token": token, "source_attestation": source_attestation}))
	check(not bool(early.get("success", false)), "target cannot activate before source retirement")
	var retired_rpc := call_authority(source, {"kind": "RETIRE", "actor": actor, "transfer_id": transfer_id, "commit_token": token})
	if not success(native_result(retired_rpc), "native source retirement"):
		return false
	var retirement_attestation: Dictionary = links[source].last_signed_reply.duplicate(true)
	if not success(coordinator.retire_source(transfer_id, source, token), "SM1 source retirement") or not success(coordinator.activate_target(transfer_id, target, source_epoch + 1, token), "SM1 target activation"):
		return false
	completed_ids[actor] = transfer_id
	var activated := native_result(call_authority(target, {"kind": "ACTIVATE", "actor": actor, "transfer_id": transfer_id, "commit_token": token, "source_attestation": retirement_attestation}))
	if not success(activated, "native target activation"):
		return false
	check(lookup(source, actor).is_empty(), "source no longer owns actor")
	var installed := lookup(target, actor)
	check(installed == before, "identity position velocity and input watermark preserved")
	check(pivot.get_client_route_identity() == route_identity, "external gateway identity unchanged")
	var prior: Dictionary = last_commands[actor]
	var native_replay := native_result(call_authority(target, {"kind": "MOVE", "actor": actor, "wire": prior["wire"]}))
	check(bool(native_replay.get("success", false)) and bool(native_replay.get("replay", false)), "native exact replay survives process seam")
	var conflict := prior.duplicate(true)
	conflict["wire"] = Dictionary(prior["wire"]).duplicate(true)
	conflict["wire"]["payload"] = Dictionary(prior["wire"]["payload"]).duplicate(true)
	var axis := "move_x" if prior["wire"].get("input_kind") == "MOVEMENT_INTENT" else "delta_x"
	var original_axis := float(prior["wire"]["payload"].get(axis, 0.0))
	conflict["wire"]["payload"][axis] = -original_axis if not is_zero_approx(original_axis) else 1.0
	conflict["wire"] = Utils.finalize_json_checksum(conflict["wire"])
	check(pivot.route_command("client-session/mvp3/" + actor, prior["operation_id"], conflict).get("error_code") == "OPERATION_REPLAY_CONFLICT", "conflicting replay rejected at stable gateway")
	var after := installed
	if prove_post_input:
		var moved := move(actor, 0.25)
		if not bool(moved.get("success", false)):
			return false
		after = lookup(target, actor)
		check(after.get("last_input_sequence") == sequences[actor] and after.get("position") != before.get("position"), "input continues on receiving authority")
		if not success(carry.validate_after_activation(transfer_id, "client-session/mvp3/" + actor, int(sequences[actor]), String(last_commands[actor]["operation_id"]), coordinator), "P6 continuity after activation"):
			return false
	else:
		pending_continuity[actor] = transfer_id
	transfers.append({"actor": actor, "transfer_id": transfer_id, "source": source, "target": target, "source_epoch": source_epoch, "target_epoch": source_epoch + 1, "before_request": requested_before, "before": before, "after": after, "freeze_cut": "NATIVE_SOURCE_EXPORT", "packet_checksum": packet["checksum"], "post_activation_movement_proven": prove_post_input and after.get("position") != before.get("position")})
	return true


func route_client_input(actor: String, wire: Dictionary) -> Dictionary:
	if wire.get("input_kind") != "MOVEMENT_INTENT":
		return Protocol.failure("MVP3_GRAPHICAL_FIXED_INTENT_REQUIRED")
	var input_sequence := int(wire.get("input_sequence", -1))
	if input_sequence != int(sequences[actor]) + 1:
		return Protocol.failure("MVP3_CLIENT_INPUT_SEQUENCE_GAP")
	var active_authority := String(coordinators[actor].snapshot().get("active_authority_id", ""))
	var before_input := lookup(active_authority, actor)
	var operation_id := String(wire.get("operation_id", ""))
	var command_value := {"domain_id": "p6-domain/outpost-world-state", "command_kind": "PLAYER_INTERACTION", "operation_id": operation_id, "wire": wire}
	var result: Dictionary = pivots[actor].route_command("client-session/mvp3/" + actor, operation_id, command_value)
	if not bool(result.get("success", false)):
		return result
	var native: Dictionary = result.get("details", {}).get("route_result", {}).get("outcome", {}).get("details", {})
	var after_input: Dictionary = native.get("player", {})
	var fixed_step: Dictionary = native.get("server_simulation", {})
	if after_input.get("logical_player_id") != actor or fixed_step.get("fixed_tick") != true or not is_equal_approx(float(fixed_step.get("delta_seconds", 0.0)), 1.0 / 60.0):
		return Protocol.failure("MVP3_TARGET_MOVEMENT_RECEIPT_REQUIRED")
	if input_observations[actor].size() >= 128:
		input_observations[actor].pop_front()
	input_observations[actor].append({"operation_id": operation_id, "authority_id": active_authority, "before": before_input, "after": after_input.duplicate(true), "server_simulation": fixed_step.duplicate(true), "server_tick": native.get("server_tick", -1)})
	sequences[actor] = input_sequence
	last_commands[actor] = command_value
	var pending := String(pending_continuity[actor])
	if not pending.is_empty():
		var transfer_index := -1
		for index in range(transfers.size()):
			if transfers[index].get("transfer_id") == pending and transfers[index].get("actor") == actor:
				transfer_index = index
		if transfer_index < 0:
			return Protocol.failure("MVP3_TRANSFER_EVIDENCE_NOT_FOUND")
		var transfer: Dictionary = transfers[transfer_index]
		var frozen: Dictionary = transfer["before"]
		if active_authority != transfer.get("target") or after_input.get("player_entity_id") != frozen.get("player_entity_id") or after_input.get("transport_session_id") != frozen.get("transport_session_id") or after_input.get("ownership_epoch") != frozen.get("ownership_epoch"):
			return Protocol.failure("MVP3_POST_ACTIVATION_IDENTITY_CHANGED")
		# A neutral receipt or replay cannot complete a crossing. Keep waiting
		# for an actual target step with both new input and physical displacement.
		var displacement := absf(float(after_input.get("position", {}).get("x", 0.0)) - float(frozen.get("position", {}).get("x", 0.0)))
		if displacement > 0.000001 and int(after_input.get("last_input_sequence", -1)) > int(frozen.get("last_input_sequence", 0)) and int(after_input.get("state_revision", -1)) > int(frozen.get("state_revision", 0)):
			var continuity: Dictionary = carrying[actor].validate_after_activation(pending, "client-session/mvp3/" + actor, input_sequence, operation_id, coordinators[actor])
			if not bool(continuity.get("success", false)):
				return continuity
			transfer["after"] = after_input.duplicate(true)
			transfer["post_activation_operation_id"] = operation_id
			transfer["post_activation_server_tick"] = native.get("server_tick", -1)
			transfer["post_activation_server_simulation"] = fixed_step.duplicate(true)
			transfer["post_activation_movement_proven"] = true
			transfers[transfer_index] = transfer
			pending_continuity[actor] = ""
	return result


func world_snapshot() -> Dictionary:
	var players: Dictionary = {}
	var decisions: Dictionary = {}
	for actor in ["a", "b"]:
		var decision: Dictionary = coordinators[actor].snapshot()
		decisions[actor] = decision
		players[actor] = lookup(String(decision["active_authority_id"]), actor)
	return {"players": players, "decisions": decisions, "transfer_count": transfers.size(), "a_roundtrip_complete": transfers.filter(func(row): return row.get("actor") == "a").size() >= 2 and String(pending_continuity["a"]).is_empty(), "both_clients_ready": bool(client_hello["a"]) and bool(client_hello["b"]), "input_sequences": sequences.duplicate(), "gateway_sessions": {"a": pivots["a"].get_client_route_identity(), "b": pivots["b"].get_client_route_identity()}}


func maybe_cross_a() -> bool:
	var decision: Dictionary = coordinators["a"].snapshot()
	var player := lookup(String(decision["active_authority_id"]), "a")
	var a_transfers: int = transfers.filter(func(row): return row.get("actor") == "a").size()
	if a_transfers == 0 and decision.get("active_authority_id") == "authority/a" and float(player.get("position", {}).get("x", -999.0)) >= 0.0:
		return cross("a", "authority/b", "transfer/mvp3/graphical/a-out", false, false)
	if a_transfers == 1 and decision.get("active_authority_id") == "authority/b" and float(player.get("position", {}).get("x", 999.0)) < 0.0:
		return cross("a", "authority/a", "transfer/mvp3/graphical/a-back", false, false)
	return true


func setup_control() -> bool:
	identity = Identity.new()
	ledger = Ledger.new()
	admission = Admission.new()
	closure = Closure.new()
	# Fail-closed ledger sized for the full interactive session envelope
	# (see Protocol.MAX_INTERACTIVE_LEDGER_OPERATIONS). No eviction: the
	# retirement policy of the P6 guard is unchanged.
	if not success(ledger.configure(Protocol.MAX_INTERACTIVE_LEDGER_OPERATIONS), "P6 ledger"):
		return false
	for actor in ["a", "b"]:
		if not success(identity.bind("client-session/mvp3/" + actor, "player/mvp3/" + actor, "entity/mvp3/" + actor), "P6 identity " + actor):
			return false
	if not success(admission.configure(identity, ledger), "P6 admission") or not success(closure.configure(identity, ledger), "P6 closure"):
		return false
	for actor in ["a", "b"]:
		var coordinator = Coordinator.new()
		if not success(coordinator.configure("authority/a", 1, {"logical_player_id": "player/mvp3/" + actor, "player_entity_id": "entity/mvp3/" + actor, "last_input_sequence": 0, "last_operation_id": ""}), "SM1 coordinator " + actor):
			return false
		coordinators[actor] = coordinator
		var carry = Carry.new()
		if not success(carry.configure(identity, ledger, closure, coordinator), "SM1 carrying " + actor):
			return false
		carrying[actor] = carry
		var by_authority: Dictionary = {}
		for authority in ["authority/a", "authority/b"]:
			var route = RemoteRoute.new()
			if not success(route.configure(self, authority, actor, Protocol.session(cfg, actor), identity, ledger, admission, closure), "remote owner route"):
				return false
			routes.append(route)
			by_authority[authority] = route
		var pivot = Pivot.new()
		if not success(pivot.configure(by_authority, coordinator, "gateway/mvp3/" + String(cfg["run_id"]), "client-session/mvp3/" + actor), "stable gateway pivot"):
			return false
		pivots[actor] = pivot
	return true


func initialize_native() -> bool:
	var okay := setup_control()
	for authority in ["authority/a", "authority/b"]:
		if not okay:
			break
		var link = BackendLink.new()
		links[authority] = link
		okay = success(link.start(cfg, authority, int(cfg["ports"][authority]), String(cfg["internal_keys"][authority])), "authenticated backend " + authority)
	if okay:
		for authority in ["authority/a", "authority/b"]:
			if not success(call_authority(authority, {"kind": "INIT"}), "native owner init " + authority):
				okay = false
				break
	return okay


func run() -> void:
	cfg = Protocol.read_config()
	if cfg.is_empty() or cfg.get("role") != "gateway":
		quit(2)
		return
	started_at_ms = Time.get_ticks_msec()
	var okay := initialize_native()
	interactive = String(cfg.get("mode", "scripted")) == "interactive"
	if interactive:
		if okay:
			client_boundary = Support.make_boundary()
			okay = client_boundary != null and bool(client_boundary.start_server(Support.endpoint("127.0.0.1", int(cfg.get("gateway_port", 0)))).get("success", false))
		if not okay:
			finish_interactive(false, "MVP3_INTERACTIVE_GATEWAY_START_FAILED")
			return
		Support.write_state(String(cfg["result_file"]), "LISTENING", {"subject_head": cfg["subject_head"], "run_id": cfg["run_id"], "gateway_process_id": OS.get_process_id()})
		return
	if okay:
		okay = bool(move("a", 0.25).get("success", false)) and bool(move("b", -0.25).get("success", false))
	if okay:
		okay = cross("a", "authority/b", "transfer/mvp3/process/a-out") and cross("a", "authority/a", "transfer/mvp3/process/a-back")
	if okay:
		okay = cross("b", "authority/b", "transfer/mvp3/process/b-out") and cross("b", "authority/a", "transfer/mvp3/process/b-back")
	finish_scripted(okay)


func authority_reports() -> Dictionary:
	var reports: Dictionary = {}
	for authority in ["authority/a", "authority/b"]:
		if links.has(authority):
			var report_rpc := call_authority(authority, {"kind": "REPORT"})
			reports[authority] = report_rpc.get("details", {}).get("result", {}).get("details", {}).get("report", {}) if bool(report_rpc.get("success", false)) else {}
	return reports


func base_report(schema: String, passed: bool, graphical: bool) -> Dictionary:
	var report := {"schema": schema, "passed": passed and failures.is_empty(), "subject_head": cfg["subject_head"], "run_id": cfg["run_id"], "gateway_process_id": OS.get_process_id(), "assertions": assertions, "failures": failures, "transfers": transfers, "sequences": sequences, "input_observations": input_observations.duplicate(true), "identity": identity.get_report() if identity != null else {}, "ledger": ledger.get_report() if ledger != null else {}, "authority_reports": authority_reports(), "backend_links": {}, "route_identity": {"a": pivots["a"].get_client_route_identity(), "b": pivots["b"].get_client_route_identity()} if pivots.size() == 2 else {}, "two_independent_players": true, "gateway_reconnects": 0, "respawns": 0, "graphical_scene_proven": graphical, "mvp3_predicate_verified": false}
	for authority in links:
		report["backend_links"][authority] = {"connects": links[authority].connects, "disconnects": links[authority].disconnects, "sequence": links[authority].sequence, "failure_code": links[authority].failure_code, "idle_service_count": links[authority].idle_service_count}
	return report


func stop_native() -> void:
	for authority in links:
		call_authority(authority, {"kind": "STOP"})
		links[authority].shutdown()
	for route in routes:
		route.shutdown()


func finish_scripted(okay: bool) -> void:
	var report := base_report("distributed_world_simulator.mvp3_native_process_roundtrip.v1", okay, false)
	Support.write_json(String(cfg["result_file"]), report)
	stop_native()
	print("MVP3_NATIVE_PROCESS_ROUNDTRIP assertions=%d failures=%d passed=%s" % [assertions, failures.size(), report["passed"]])
	quit(0 if bool(report["passed"]) else 1)


func finish_interactive(okay: bool, error_code: String = "") -> void:
	if not error_code.is_empty():
		check(false, error_code)
	var report := base_report("distributed_world_simulator.mvp3_graphical_gateway.v1", okay, true)
	report["client_sessions"] = client_peers.duplicate()
	report["client_finished"] = client_finished.duplicate()
	report["world_snapshot"] = world_snapshot() if okay else {}
	Support.write_json(String(cfg["result_file"]), report)
	if client_boundary != null:
		client_boundary.stop()
	stop_native()
	print("MVP3_GRAPHICAL_GATEWAY assertions=%d failures=%d passed=%s" % [assertions, failures.size(), report["passed"]])
	quit(0 if bool(report["passed"]) else 1)


func identify_client(packet: Dictionary) -> String:
	for actor in ["a", "b"]:
		var key := String(cfg.get("client_keys", {}).get(actor, ""))
		if Protocol.verify(cfg, packet, "client/" + actor, "gateway", key):
			return actor
	return ""


func handle_client(actor: String, body: Dictionary) -> Dictionary:
	var kind := String(body.get("kind", ""))
	if kind == "HELLO":
		client_hello[actor] = true
		return Protocol.success({"kind": kind, "actor": actor, "snapshot": world_snapshot()})
	if kind == "OBSERVE":
		# Held input continues on server ticks even with no new key messages.
		# Sampling a shared snapshot must therefore observe a real seam crossing.
		if bool(client_hello["a"]) and bool(client_hello["b"]) and not bool(client_finished["a"]) and not maybe_cross_a():
			return Protocol.failure("MVP3_AUTOMATIC_HANDOFF_FAILED")
		return Protocol.success({"kind": kind, "actor": actor, "snapshot": world_snapshot()})
	if kind == "MOVE":
		if not body.get("wire") is Dictionary or body["wire"].get("logical_player_id") != actor or body["wire"].get("transport_session_id") != Protocol.session(cfg, actor):
			return Protocol.failure("MVP3_CLIENT_INPUT_BINDING_INVALID")
		var moved := route_client_input(actor, body["wire"])
		if not bool(moved.get("success", false)):
			return moved
		if actor == "a" and not maybe_cross_a():
			return Protocol.failure("MVP3_AUTOMATIC_HANDOFF_FAILED")
		return Protocol.success({"kind": kind, "actor": actor, "outcome": moved, "snapshot": world_snapshot()})
	if kind == "FINISH":
		client_finished[actor] = true
		if bool(client_finished["a"]) and bool(client_finished["b"]):
			closing_at_ms = Time.get_ticks_msec() + 250
		return Protocol.success({"kind": kind, "actor": actor, "snapshot": world_snapshot()})
	return Protocol.failure("MVP3_CLIENT_COMMAND_UNKNOWN")


func _process(_delta: float) -> bool:
	if not interactive or client_boundary == null:
		return false
	var polled: Dictionary = client_boundary.poll_events(128)
	if not bool(polled.get("success", false)):
		finish_interactive(false, "MVP3_CLIENT_GATEWAY_POLL_FAILED")
		return false
	for raw in polled.get("details", {}).get("events", []):
		var event: Dictionary = raw
		var peer := String(event.get("peer_id", ""))
		if event.get("event_type") == "PEER_CONNECTED":
			Support.mark_ready(client_boundary, peer)
		elif event.get("event_type") == "PEER_DISCONNECTED":
			for actor in client_peers:
				if client_peers[actor] == peer and not bool(client_finished[actor]):
					finish_interactive(false, "MVP3_CLIENT_DISCONNECTED_DURING_WORKLOAD")
					return false
		elif event.get("event_type") == "MESSAGE_RECEIVED":
			var packet := Protocol.payload(event)
			var actor := identify_client(packet)
			if actor.is_empty() or (client_peers.has(actor) and client_peers[actor] != peer) or int(packet.get("sequence", 0)) != int(client_sequences.get(actor, 0)) + 1:
				continue
			client_peers[actor] = peer
			client_sequences[actor] = int(packet["sequence"])
			var response := handle_client(actor, packet["body"])
			var signed := Protocol.seal(cfg, "gateway", "client/" + actor, int(packet["sequence"]), response, String(cfg["client_keys"][actor]))
			var sent := Protocol.send(client_boundary, peer, signed)
			if not bool(sent.get("success", false)):
				finish_interactive(false, "MVP3_CLIENT_GATEWAY_REPLY_FAILED")
				return false
	client_boundary.flush_outbound(128)
	if closing_at_ms > 0 and Time.get_ticks_msec() >= closing_at_ms:
		var a_transfers: int = transfers.filter(func(row): return row.get("actor") == "a").size()
		finish_interactive(a_transfers == 2 and String(pending_continuity["a"]).is_empty() and int(sequences["b"]) >= 2)
	elif Time.get_ticks_msec() - started_at_ms > int(cfg.get("timeout_ms", 120000)):
		finish_interactive(false, "MVP3_GRAPHICAL_GATEWAY_TIMEOUT")
	return false

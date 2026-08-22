extends SceneTree

## EG4 sim server worker — DUAL ROLE over real ENET:
##
##   --role=ACTIVE      the authoritative Sim A endpoint: admits ingress
##                      envelopes for N logical gateway sessions, applies
##                      WORLD_OPERATION receipts + INPUT_MOVEMENT intents under
##                      the GATEWAY-GRANTED logical player identity, and answers
##                      with reliable results plus AUTHORITATIVE_SNAPSHOT egress
##                      (the EG1..EG3 data plane, single backend peer).
##
##   --role=PROJECTION  a PROJECTION source (Sim B): admits projection_subscribe
##                      / projection_withdraw control operations and streams
##                      synthetic READ-ONLY WORLD_PROJECTION frames per
##                      subscribed (gateway session, world) pair. After
##                      --inject-after-frames healthy frames it sends ONE
##                      mutation-shaped frame (write injection attempt) that
##                      the gateway fence must reject end to end.
##
## With --death-marker-file set, the worker EXITS ABRUPTLY when the marker
## appears (the orchestrator may also OS.kill it — a killed UDP process is
## protocol-silent either way; the gateway detects loss by traffic watchdog or
## disconnect event).

const Support = preload("res://tools/network/eg4_process_support.gd")
const BoundaryScript = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const EnetPortScript = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
const IngressEnvelopeScript = preload("res://scripts/network/gateway/gateway_ingress_envelope.gd")
const EgressEnvelopeScript = preload("res://scripts/network/gateway/gateway_egress_envelope.gd")
const GatewayUtils = preload("res://scripts/network/gateway/gateway_contract_utils.gd")

const OPTION_SPEC := {
	"role": {"kind": "string", "default": "ACTIVE"},
	"host": {"kind": "string", "default": "127.0.0.1"},
	"port": {"kind": "int", "default": 0, "required": true},
	"result-file": {"kind": "string", "default": "", "required": true},
	"player-binding-file": {"kind": "string", "default": ""},
	"expected-operations": {"kind": "int", "default": 2},
	"expected-movements": {"kind": "int", "default": 2},
	"stay-alive": {"kind": "string", "default": "1"},
	"inject-after-frames": {"kind": "int", "default": Support.INJECTION_AFTER_FRAMES},
	"projection-beat-ms": {"kind": "int", "default": Support.PROJECTION_BEAT_MS},
	"link-drop-marker-file": {"kind": "string", "default": ""},
	"death-marker-file": {"kind": "string", "default": ""},
	"timeout-ms": {"kind": "int", "default": 120000},
	"user-data-dir": {"kind": "string", "default": ""},
}

var _options: Dictionary = {}
var _boundary
var _service
var _is_projection := false
# ---- ACTIVE role state ---------------------------------------------------------
var _ledgers_by_gateway_session: Dictionary = {}
var _movements_by_gateway_session: Dictionary = {}
var _bindings_by_gateway_session: Dictionary = {}
var _joined_players: Dictionary = {}
var _pending_admissions: Array = []
var _egress_counter: int = 0
# ---- PROJECTION role state -----------------------------------------------------
# "<gateway_session_id>|<world_id>" -> true
var _subscriptions: Dictionary = {}
var _ignored_operations: int = 0
var _injected_frames: int = 0
var _frames_per_subscription: Dictionary = {}
var _source_revision: int = 0
var _next_projection_due_ms: int = 0
# ---- shared ---------------------------------------------------------------------
var _peer_id := ""
var _backend_wire_session := ""
var _physical_peers_seen: Dictionary = {}
var _link_dropped := false
var _started_ms: int = 0
var _heartbeat_at_ms: int = 0
var _last_traffic_at_ms: int = 0
var _finished := false
var _final_report_written := false


func _initialize() -> void:
	var parsed: Dictionary = Support.parse_options(OS.get_cmdline_user_args(), OPTION_SPEC)
	if not bool(parsed.get("success", false)):
		_finish_failure("INVALID_OPTIONS", {"errors": parsed.get("errors", [])})
		return
	_options = parsed["options"]
	_is_projection = String(_options["role"]) == "PROJECTION"
	if not _is_projection:
		_service = Support.ServiceScript.new()
		var setup: Dictionary = _service.setup(
				Support.AUTHORITY_OWNER_ID, Support.AUTHORITY_EPOCH, Support.SERVER_TICK,
				Support.SERVICE_CONFIG.duplicate(true))
		if not bool(setup.get("success", false)):
			_finish_failure("SERVICE_SETUP_FAILED", {"error_code": String(setup.get("error_code", ""))})
			return

	_boundary = BoundaryScript.new()
	var configured: Dictionary = _boundary.configure(EnetPortScript.new(), 1048576, 512, 4194304)
	if not bool(configured.get("success", false)):
		_finish_failure(String(configured.get("error_code", "CONFIGURE_FAILED")), {})
		return
	var started: Dictionary = _boundary.start_server(Support.enet_endpoint(String(_options["host"]), int(_options["port"])))
	if not bool(started.get("success", false)):
		_finish_failure(String(started.get("error_code", "START_FAILED")), {})
		return
	_started_ms = Time.get_ticks_msec()
	Support.write_state(String(_options["result-file"]), "LISTENING", {
		"mode": "EG4_%s" % String(_options["role"]),
	})
	print("EG4_SIM_LISTENING role=%s port=%d" % [String(_options["role"]), int(_options["port"])])


func _process(_delta: float) -> bool:
	if _finished or _boundary == null:
		return false
	var polled: Dictionary = _boundary.poll_events(256)
	if not bool(polled.get("success", false)):
		_finish_failure(String(polled.get("error_code", "POLL_FAILED")), {})
		return false
	for event_value in polled.get("details", {}).get("events", []):
		_handle_event(Dictionary(event_value))
	_boundary.flush_outbound(256)
	_drain_pending_admissions()
	if not _link_dropped and not String(_options["link-drop-marker-file"]).is_empty() \
			and FileAccess.file_exists(String(_options["link-drop-marker-file"])):
		_link_dropped = true
		_write_final_report()
		_boundary.stop()
		_finished = true
		return false
	if not String(_options["death-marker-file"]).is_empty() \
			and FileAccess.file_exists(String(_options["death-marker-file"])):
		# Abrupt death on marker: NO report update, NO graceful close — the
		# process simply disappears like a killed worker would.
		_finished = true
		quit(0)
		return true
	if _is_projection:
		_pump_projections()
	else:
		_maybe_complete_active()
	_heartbeat()
	if Time.get_ticks_msec() - _started_ms > int(_options["timeout-ms"]):
		_finish_failure("SIM_TIMEOUT", {})
		return false
	return false


func _heartbeat() -> void:
	var now := Time.get_ticks_msec()
	if now - _heartbeat_at_ms < 500:
		return
	_heartbeat_at_ms = now
	var payload := {
		"schema": "planet_simulator.eg4_sim_heartbeat.v1",
		"role": String(_options["role"]),
		"peers": _physical_peers_seen.keys(),
		"link_dropped": _link_dropped,
	}
	if _is_projection:
		payload["active_subscriptions"] = _subscriptions.keys().size()
		payload["projection_frames_sent"] = _source_revision
		payload["injections_sent"] = _injected_frames
	else:
		payload["totals"] = {"operations": _total_operations(), "movements": _total_movements()}
		payload["pending_admissions"] = _pending_admissions.size()
	Support.write_json(String(_options["result-file"]) + ".heartbeat.json", payload)


## ---- events ---------------------------------------------------------------------


func _handle_event(event: Dictionary) -> void:
	match String(event.get("event_type", "")):
		"PEER_CONNECTED":
			_peer_id = String(event["peer_id"])
			_physical_peers_seen[_peer_id] = true
			_ensure_peer_ready()
		"PEER_DISCONNECTED":
			_link_dropped = true
		"MESSAGE_RECEIVED":
			_peer_id = String(event["peer_id"])
			_physical_peers_seen[_peer_id] = true
			_last_traffic_at_ms = Time.get_ticks_msec()
			_backend_wire_session = String(Dictionary(event.get("frame", {})).get("session_id", _backend_wire_session))
			_ensure_peer_ready()
			_admit(Dictionary(event.get("frame", {})).get("payload", {}))
		_:
			pass


func _ensure_peer_ready() -> void:
	if _peer_id.is_empty():
		return
	var snapshot: Dictionary = _boundary.get_peer_snapshot(_peer_id)
	match String(snapshot.get("state", "")):
		"TRANSPORT_CONNECTED":
			_boundary.mark_peer_handshaking(_peer_id)
			_boundary.mark_peer_synchronizing(_peer_id)
			_boundary.mark_peer_ready(_peer_id)


func _admit(payload) -> void:
	if not (payload is Dictionary) or String(Dictionary(payload).get("schema", "")) != IngressEnvelopeScript.SCHEMA:
		_finish_failure("NON_ENVELOPE_BACKEND_PAYLOAD", {})
		return
	var envelope: Dictionary = Dictionary(payload)
	var gateway_session_id := String(envelope.get("gateway_session_id", ""))
	if _is_projection:
		_admit_projection_control(gateway_session_id, Dictionary(envelope.get("frame", {})))
		return
	var logical_player_id := _resolve_player_id(gateway_session_id)
	if logical_player_id.is_empty():
		_pending_admissions.append({"player_id": "", "envelope": envelope.duplicate(true)})
		return
	_apply_admission(logical_player_id, envelope)


func _drain_pending_admissions() -> void:
	if _is_projection or _pending_admissions.is_empty():
		return
	_refresh_bindings()
	_ensure_peer_ready()
	while not _pending_admissions.is_empty():
		var pending: Dictionary = _pending_admissions[0]
		var logical_player_id := String(pending["player_id"])
		if logical_player_id.is_empty():
			logical_player_id = _resolve_player_id(String(pending["envelope"]["gateway_session_id"]))
			if logical_player_id.is_empty():
				return
			pending["player_id"] = logical_player_id
		_pending_admissions.pop_front()
		_apply_admission(logical_player_id, Dictionary(pending["envelope"]))


func _apply_admission(logical_player_id: String, envelope: Dictionary) -> void:
	if not _joined_players.has(logical_player_id):
		var joined: Dictionary = _service.join(
				logical_player_id, Support.sim_transport_session_for(logical_player_id),
				Support.join_operation_id_for(logical_player_id))
		if not bool(joined.get("success", false)):
			_finish_failure("PLAYER_JOIN_FAILED", {"error_code": String(joined.get("error_code", ""))})
			return
		_joined_players[logical_player_id] = true
	var inner: Dictionary = envelope.get("frame", {})
	match String(inner.get("channel", "")):
		"WORLD_OPERATION":
			_admit_item(inner, logical_player_id)
		"INPUT_MOVEMENT":
			_admit_movement(inner, logical_player_id)
		_:
			pass # ACTIVE sim ignores non-gameplay channels


func _resolve_player_id(gateway_session_id: String) -> String:
	if gateway_session_id.is_empty():
		return ""
	if _bindings_by_gateway_session.has(gateway_session_id):
		return String(_bindings_by_gateway_session[gateway_session_id])
	_refresh_bindings()
	return String(_bindings_by_gateway_session.get(gateway_session_id, ""))


func _refresh_bindings() -> void:
	var path := String(_options.get("player-binding-file", ""))
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary and Dictionary(parsed).has("bindings"):
		var bindings: Dictionary = Dictionary(parsed)["bindings"]
		for gateway_session_id_value in bindings.keys():
			var row: Dictionary = Dictionary(bindings[String(gateway_session_id_value)])
			var player_id := String(row.get("logical_player_id", ""))
			if not player_id.is_empty():
				_bindings_by_gateway_session[String(gateway_session_id_value)] = player_id


## ---- ACTIVE role admission ---------------------------------------------------------


func _admit_item(inner: Dictionary, logical_player_id: String) -> void:
	var gateway_session_id := String(inner["gateway_session_id"])
	var payload: Dictionary = Dictionary(inner.get("payload", {}))
	var operation_id := String(payload.get("operation_id", ""))
	if operation_id.is_empty():
		_finish_failure("OPERATION_WITHOUT_ID", {"gateway_session_id": gateway_session_id})
		return
	var ledger: Array = _ledgers_by_gateway_session.get(gateway_session_id, [])
	if operation_id in ledger:
		return
	var result: Dictionary = _service.handle_canonical_item_command(
			logical_player_id, Support.sim_transport_session_for(logical_player_id), 1,
			operation_id, "inventory.select_hotbar",
			{"selected_hotbar_index": 1 + (operation_id.hash() % 8)})
	if not bool(result.get("success", false)):
		_finish_failure("SIM_ITEM_COMMAND_FAILED", {"operation_id": operation_id})
		return
	ledger.append(operation_id)
	ledger.sort()
	_ledgers_by_gateway_session[gateway_session_id] = ledger
	_send_egress(inner, "WORLD_OPERATION", {
		"operation_id": operation_id,
		"command": "inventory.select_hotbar",
		"target_id": String(payload.get("target_id", "entity/eg4-l2-scenario")),
	}, "planet_simulator.test_world_operation.v1")


func _admit_movement(inner: Dictionary, logical_player_id: String) -> void:
	var gateway_session_id := String(inner["gateway_session_id"])
	var input_seq := int(Dictionary(inner.get("payload", {})).get("input_seq", 0))
	var receipt_key := "%s|%d" % [gateway_session_id, input_seq]
	var moved: Dictionary = _service.submit_movement_intent(
			logical_player_id, Support.sim_transport_session_for(logical_player_id), 1,
			input_seq, Support.MOVEMENT_INTENT.duplicate(true),
			"operation/eg4/l2/move/%s/%d" % [gateway_session_id.replace("/", "-"), input_seq])
	if not bool(moved.get("success", false)) \
			and String(moved.get("error_code", "")) != "STALE_OR_DUPLICATE_INPUT_SEQUENCE":
		_finish_failure("SIM_MOVEMENT_INTENT_FAILED", {"input_seq": input_seq})
		return
	_movements_by_gateway_session[gateway_session_id] \
			= int(_movements_by_gateway_session.get(gateway_session_id, 0)) + 1
	_send_egress(inner, "WORLD_OPERATION", {
		"operation_id": "operation/eg4/l2/move-ack/%s/%d" % [
			gateway_session_id.replace("/", "-"), input_seq],
		"command": "input.accepted",
		"target_id": "entity/eg4-l2-scenario",
	}, "planet_simulator.test_world_operation.v1")
	_send_egress(inner, "AUTHORITATIVE_SNAPSHOT", {"revision": _total_movements()},
			"planet_simulator.test_snapshot.v1")


func _send_egress(request_inner: Dictionary, egress_channel: String, egress_payload: Dictionary, payload_schema: String) -> void:
	_egress_counter += 1
	var gateway_session_id := String(request_inner["gateway_session_id"])
	var inner: Dictionary = Support.ClientWorldFrameScript.create(
			"frame/eg4/l2/result/%06d" % _egress_counter,
			gateway_session_id,
			"WORLD_TO_CLIENT",
			egress_channel,
			maxi(int(request_inner["sequence"]), 1),
			payload_schema,
			egress_payload)
	var envelope: Dictionary = EgressEnvelopeScript.create(
			"gateway-envelope/eg4/l2/w2c/%06d" % _egress_counter,
			"gateway/eg4/l2-worker",
			"backend-link/eg4/l2-sim-a",
			gateway_session_id,
			1, 1, 1,
			Support.AUTHORITY_ID,
			Support.SERVER_INSTANCE_ID,
			"ACTIVE",
			inner)
	var wire: Dictionary = Support.FrameScript.create(
			"frame/eg4/l2/backend-down/%06d" % _egress_counter,
			_backend_wire_session, _egress_counter,
			GatewayUtils.eg1_physical_channel_for(egress_channel),
			GatewayUtils.eg1_delivery_mode_for(egress_channel),
			"planet_simulator.gateway_egress_envelope.v1", envelope)
	var sent: Dictionary = _boundary.send_to_peer(_peer_id, wire)
	if not bool(sent.get("success", false)):
		_finish_failure(String(sent.get("error_code", "EGRESS_SEND_FAILED")), {"egress": _egress_counter})


## ---- PROJECTION role ------------------------------------------------------------------


func _admit_projection_control(gateway_session_id: String, inner: Dictionary) -> void:
	if String(inner.get("channel", "")) != "WORLD_OPERATION":
		return # projection sources admit only subscribe/withdraw control ops
	var payload: Dictionary = Dictionary(inner.get("payload", {}))
	match String(payload.get("command", "")):
		"projection_subscribe":
			var world_id := Support.world_from_entity_slug(String(payload.get("target_id", "")))
			if not world_id.is_empty():
				_subscriptions["%s|%s" % [gateway_session_id, world_id]] = true
		"projection_withdraw":
			var withdrawn_world := Support.world_from_entity_slug(String(payload.get("target_id", "")))
			_subscriptions.erase("%s|%s" % [gateway_session_id, withdrawn_world])
		_:
			_ignored_operations += 1


func _pump_projections() -> void:
	if _subscriptions.is_empty() or _link_dropped:
		return
	var now := Time.get_ticks_msec()
	if now < _next_projection_due_ms:
		return
	_next_projection_due_ms = now + int(_options["projection-beat-ms"])
	for sub_key_value in _subscriptions.keys():
		var sub_key := String(sub_key_value)
		var split := sub_key.find("|")
		var gateway_session_id := sub_key.substr(0, split)
		var world_id := sub_key.substr(split + 1)
		_source_revision += 1
		var frames_sent := int(_frames_per_subscription.get(sub_key, 0))
		_frames_per_subscription[sub_key] = frames_sent + 1
		if frames_sent % maxi(int(_options["inject-after-frames"]), 1) == 0:
			# Mutation-shaped write injection attempt. Sent ALONE in its own
			# beat and REPEATED every inject-after-frames frames per pair: the
			# boundary coalesces same-stream queued frames latest-wins, so a
			# one-shot attempt can legally be swallowed by a newer healthy
			# frame under load — repeated solo beats make at-least-one-arrival
			# deterministic while the read-only fence rejects every attempt.
			_injected_frames += 1
			var injection_envelope: Dictionary = Support.mutation_injection_envelope(
					_source_revision, gateway_session_id)
			var injected_send: Dictionary = Support.send_envelope(
					_boundary, _peer_id, _backend_wire_session, _source_revision,
					"WORLD_PROJECTION", injection_envelope, "sim-b")
			if not bool(injected_send.get("success", false)):
				_finish_failure(String(injected_send.get("error_code", "EGRESS_SEND_FAILED")), {})
				return
			return
		var envelope: Dictionary = Support.projection_egress_envelope(
				_source_revision, gateway_session_id, world_id, _source_revision, true)
		var sent: Dictionary = Support.send_envelope(
				_boundary, _peer_id, _backend_wire_session, _source_revision,
				"WORLD_PROJECTION", envelope, "sim-b")
		if not bool(sent.get("success", false)):
			_finish_failure(String(sent.get("error_code", "EGRESS_SEND_FAILED")), {})
			return


## ---- completion & reports ---------------------------------------------------------------


func _total_operations() -> int:
	var total := 0
	for ledger_value in _ledgers_by_gateway_session.values():
		total += (ledger_value as Array).size()
	return total


func _total_movements() -> int:
	var total := 0
	for count_value in _movements_by_gateway_session.values():
		total += int(count_value)
	return total


func _maybe_complete_active() -> void:
	if _completion_at >= 0:
		return
	if _total_operations() < int(_options["expected-operations"]):
		return
	if _total_movements() < int(_options["expected-movements"]):
		return
	if not _pending_admissions.is_empty() or _joined_players.is_empty():
		return
	if Time.get_ticks_msec() - _last_traffic_at_ms < 1500:
		return
	_completion_at = Time.get_ticks_msec()
	_write_final_report()


var _completion_at: int = -1


func _write_final_report() -> void:
	if _final_report_written:
		return
	_final_report_written = true
	var report := {
		"schema": "planet_simulator.eg4_sim_server_report.v1",
		"state": "DRAINING",
		"passed": true,
		"mode": "EG4_%s" % String(_options["role"]),
		"process_id": OS.get_process_id(),
		"physical_peers_seen": _physical_peers_seen.keys(),
		"totals": {"operations": _total_operations(), "movements": _total_movements()},
		"backend_link_dropped": _link_dropped,
		"user_data_dir": String(_options["user-data-dir"]),
	}
	if _is_projection:
		report["state"] = "DRAINING"
		report["projection_frames_sent"] = _source_revision
		report["injections_sent"] = _injected_frames
		report["ignored_operations"] = _ignored_operations
		report["served_pairs"] = _subscriptions.keys()
		report["frames_per_subscription"] = _frames_per_subscription.duplicate(true)
	else:
		report["operation_ledger_by_session"] = _ledgers_by_gateway_session.duplicate(true)
		report["movement_receipts_by_session"] = _movements_by_gateway_session.duplicate(true)
		report["session_bindings"] = _bindings_by_gateway_session.duplicate(true)
		report["joined_players"] = _joined_players.keys()
	Support.write_json(String(_options["result-file"]), report)


func _finish_failure(error_code: String, details: Dictionary) -> void:
	_finished = true
	var report: Dictionary = {
		"schema": "planet_simulator.eg4_sim_server_report.v1",
		"state": "FAILED",
		"passed": false,
		"failure_code": error_code,
		"details": details,
		"role": String(_options["role"]),
		"process_id": OS.get_process_id(),
	}
	if not String(_options.get("result-file", "")).is_empty():
		Support.write_json(String(_options["result-file"]), report)
	push_error("EG4 sim worker failed (%s): %s" % [String(_options["role"]), error_code])
	if _boundary != null:
		_boundary.stop()
	quit(1)

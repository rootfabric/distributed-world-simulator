extends SceneTree

## EG3 sim server worker: authoritative endpoint of the shared-multiplexed
## topology. ONE physical ENET peer (the gateway) carries N logical sessions;
## every ingress envelope is DEMUXED by its inner gateway_session_id, bound to
## the GATEWAY-GRANTED logical player id from the published binding sidecar,
## and applied to the domain under that identity. Per-session operation
## ledgers are the cross-session leakage oracle. Flood inputs (seq >=
## FLOOD_INPUT_SEQ_BASE) are counted but never answered: they exist to
## pressure the tunnel while other sessions' P0-P2 traffic must keep flowing.
## With --stay-alive=1 the worker keeps running after reaching its expected
## totals so the orchestrator can drop the backend link later in the scenario.

const Support = preload("res://tools/network/eg3_process_support.gd")
const BoundaryScript = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const EnetPortScript = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
const IngressEnvelopeScript = preload("res://scripts/network/gateway/gateway_ingress_envelope.gd")
const EgressEnvelopeScript = preload("res://scripts/network/gateway/gateway_egress_envelope.gd")

const OPTION_SPEC := {
	"host": {"kind": "string", "default": "127.0.0.1"},
	"port": {"kind": "int", "default": 0, "required": true},
	"result-file": {"kind": "string", "default": "", "required": true},
	"player-binding-file": {"kind": "string", "default": ""},
	"expected-operations": {"kind": "int", "default": 12},
	"expected-movements": {"kind": "int", "default": 35},
	"stay-alive": {"kind": "string", "default": "1"},
	## When this file appears the sim CLOSES the backend listener gracefully:
	## UDP/ENet has no teardown on process kill, so an abrupt kill would take
	## the gateway ~30s of silence to notice. A graceful close delivers the
	## disconnect immediately and deterministically.
	"link-drop-marker-file": {"kind": "string", "default": ""},
	"timeout-ms": {"kind": "int", "default": 90000},
	"user-data-dir": {"kind": "string", "default": ""},
}

var _options: Dictionary = {}
var _boundary
var _service
# gateway_session_id -> sorted distinct applied WORLD_OPERATION ids.
var _ledgers_by_gateway_session: Dictionary = {}
# gateway_session_id -> receipted non-flood movement count.
var _movements_by_gateway_session: Dictionary = {}
# gateway_session_id -> flood input count (counted, never answered).
var _flood_inputs_by_gateway_session: Dictionary = {}
# "gateway_session_id|input_seq" -> true: idempotent receipt dedup.
var _movement_receipts: Dictionary = {}
# gateway_session_id -> granted logical player id (identity-binding oracle).
var _bindings_by_gateway_session: Dictionary = {}
var _joined_players: Dictionary = {}
# Ingress envelopes whose session identity was not yet published: parked in
# wire order until the binding sidecar carries their gateway_session_id.
var _pending_admissions: Array = []
var _peer_id := ""
var _backend_wire_session := ""
var _physical_peers_seen: Dictionary = {}
var _link_dropped := false
var _egress_counter: int = 0
var _started_ms: int = 0
var _heartbeat_at_ms: int = 0
var _last_admission_at_ms: int = 0
var _finished := false
var _final_report_written := false
var _completion_at_ms: int = -1


func _initialize() -> void:
	var parsed: Dictionary = Support.parse_options(OS.get_cmdline_user_args(), OPTION_SPEC)
	if not bool(parsed.get("success", false)):
		_finish_failure("INVALID_OPTIONS", {"errors": parsed.get("errors", [])})
		return
	_options = parsed["options"]
	_service = Support.ServiceScript.new()
	var setup: Dictionary = _service.setup(
			Support.AUTHORITY_OWNER_ID, Support.AUTHORITY_EPOCH, Support.SERVER_TICK,
			Support.SERVICE_CONFIG.duplicate(true))
	if not bool(setup.get("success", false)):
		_finish_failure("SERVICE_SETUP_FAILED", {"error_code": String(setup.get("error_code", ""))})
		return
	# NOTE: no eager fixed-identity join here. Domain players are joined lazily
	# under the GATEWAY-GRANTED logical_player_id resolved from the binding
	# sidecar, keyed by the inner gateway_session_id of each ingress envelope.

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
	Support.write_state(String(_options["result-file"]), "LISTENING", {"mode": "EG3_GATEWAY"})
	print("EG3_SIM_LISTENING port=%d" % int(_options["port"]))


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
		# Graceful backend link drop (scenario f): close the listener so the
		# gateway observes the disconnect deterministically (a process kill on
		# UDP/ENet is silent for ~30s of protocol silence). Finalize the
		# report with whatever state exists NOW and freeze this worker; the
		# orchestrator reaps it during teardown.
		_link_dropped = true
		_boundary.stop()
		_write_final_report()
		_finished = true
		return false
	_maybe_complete()
	var now := Time.get_ticks_msec()
	if _completion_at_ms < 0 and now - _heartbeat_at_ms >= 2000:
		_heartbeat_at_ms = now
		Support.write_json(String(_options["result-file"]) + ".heartbeat.json", {
			"schema": "planet_simulator.eg3_sim_heartbeat.v1",
			"totals": _totals(),
			"ledgers": _ledgers_by_gateway_session.duplicate(true),
			"floods": _flood_inputs_by_gateway_session.duplicate(true),
			"receipts": _movements_by_gateway_session.duplicate(true),
			"bindings": _bindings_by_gateway_session.duplicate(true),
			"pending_admissions": _pending_admissions.size(),
			"peers": _physical_peers_seen.keys(),
			"link_dropped": _link_dropped,
		})
	if _completion_at_ms >= 0:
		# DRAINING report is durable; stay alive so the orchestrator can drop
		# the backend link as a later scenario step (or exit in run-to-completion mode).
		if String(_options["stay-alive"]) != "1" \
				and Time.get_ticks_msec() - _completion_at_ms >= 500:
			quit(0)
		if Time.get_ticks_msec() - _started_ms > int(_options["timeout-ms"]):
			_finish_failure("SIM_TIMEOUT", {"totals": _totals()})
		return false
	if Time.get_ticks_msec() - _started_ms > int(_options["timeout-ms"]):
		_finish_failure("SIM_TIMEOUT", {"totals": _totals()})
	return false


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
	# Demux by the INNER gateway session: every logical player session shares
	# one physical backend link, and its granted identity binds the domain
	# application. Unresolved identities park in wire order (the binding
	# sidecar may lag the first envelope by a tick).
	var logical_player_id := _resolve_player_id(gateway_session_id)
	if logical_player_id.is_empty():
		_pending_admissions.append({"player_id": "", "envelope": envelope.duplicate(true)})
		return
	_apply_admission(logical_player_id, envelope)


## FIFO drain of parked envelopes; stops at the first still-unresolved head so
## wire order is preserved. The backend peer is driven READY before any parked
## application runs outside a message event.
func _drain_pending_admissions() -> void:
	if _pending_admissions.is_empty():
		return
	_refresh_bindings()
	_ensure_peer_ready()
	var snapshot: Dictionary = _boundary.get_peer_snapshot(_peer_id) if not _peer_id.is_empty() else {}
	if snapshot.is_empty() or String(snapshot.get("state", "")) != "READY":
		return
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
	if not _ensure_player_joined(logical_player_id):
		return
	_last_admission_at_ms = Time.get_ticks_msec()
	var inner: Dictionary = envelope.get("frame", {})
	match String(inner.get("channel", "")):
		"WORLD_OPERATION":
			_admit_item(inner, logical_player_id)
		"INPUT_MOVEMENT":
			_admit_movement(inner, logical_player_id)
		_:
			_finish_failure("UNEXPECTED_SIM_CHANNEL", {"channel": String(inner.get("channel", ""))})


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


## Lazy domain join under the GRANTED identity with its derived per-player
## transport session (identical to any DIRECT baseline's derivation).
func _ensure_player_joined(logical_player_id: String) -> bool:
	if _joined_players.has(logical_player_id):
		return true
	var joined: Dictionary = _service.join(
			logical_player_id, Support.sim_transport_session_for(logical_player_id),
			Support.join_operation_id_for(logical_player_id))
	if not bool(joined.get("success", false)):
		_finish_failure("PLAYER_JOIN_FAILED", {"error_code": String(joined.get("error_code", ""))})
		return false
	_joined_players[logical_player_id] = true
	return true


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
		_finish_failure("SIM_ITEM_COMMAND_FAILED", {
			"operation_id": operation_id,
			"error_code": String(result.get("error_code", "")),
		})
		return
	ledger.append(operation_id)
	ledger.sort()
	_ledgers_by_gateway_session[gateway_session_id] = ledger
	_send_egress(inner, "WORLD_OPERATION", {
		"operation_id": operation_id,
		"command": "inventory.select_hotbar",
		"target_id": String(payload.get("target_id", "entity/eg3-l2-scenario")),
	})


func _admit_movement(inner: Dictionary, logical_player_id: String) -> void:
	var gateway_session_id := String(inner["gateway_session_id"])
	var input_seq := int(Dictionary(inner.get("payload", {})).get("input_seq", 0))
	if input_seq >= Support.FLOOD_INPUT_SEQ_BASE:
		# Flood pressure: COUNTED, never answered.
		var count: int = _flood_inputs_by_gateway_session.get(gateway_session_id, 0)
		_flood_inputs_by_gateway_session[gateway_session_id] = int(count) + 1
		return
	var receipt_key := "%s|%d" % [gateway_session_id, input_seq]
	if _movement_receipts.has(receipt_key):
		# Idempotent receipt: a client retry for a movement that already
		# landed must be answered again, never failed as a duplicate.
		_send_egress(inner, "WORLD_OPERATION", {
			"operation_id": "operation/eg3/l2/move-ack/%s/%d" % [
				gateway_session_id.replace("/", "-"), input_seq],
			"command": "input.accepted",
			"target_id": "entity/eg3-l2-scenario",
		})
		return
	var movement_operation_id := "operation/eg3/l2/move/%s/%d" % [
		gateway_session_id.replace("/", "-"), input_seq]
	var moved: Dictionary = _service.submit_movement_intent(
			logical_player_id, Support.sim_transport_session_for(logical_player_id), 1,
			input_seq, Support.MOVEMENT_INTENT.duplicate(true), movement_operation_id)
	if not bool(moved.get("success", false)):
		var error_code := String(moved.get("error_code", ""))
		if error_code == "STALE_OR_DUPLICATE_INPUT_SEQUENCE":
			# Another envelope of this very input already advanced the player;
			# treat as received and answer idempotently instead of failing.
			_movement_receipts[receipt_key] = true
			_bump_receipt_count(gateway_session_id)
			_send_egress(inner, "WORLD_OPERATION", {
				"operation_id": "operation/eg3/l2/move-ack/%s/%d" % [
					gateway_session_id.replace("/", "-"), input_seq],
				"command": "input.accepted",
				"target_id": "entity/eg3-l2-scenario",
			})
			return
		_finish_failure("SIM_MOVEMENT_INTENT_FAILED", {
			"operation_id": movement_operation_id,
			"error_code": error_code,
		})
		return
	_movement_receipts[receipt_key] = true
	_bump_receipt_count(gateway_session_id)
	_send_egress(inner, "WORLD_OPERATION", {
		"operation_id": "operation/eg3/l2/move-ack/%s/%d" % [
			gateway_session_id.replace("/", "-"), input_seq],
		"command": "input.accepted",
		"target_id": "entity/eg3-l2-scenario",
	})
	_send_egress(inner, "AUTHORITATIVE_SNAPSHOT", {"revision": _total_movements()})


func _bump_receipt_count(gateway_session_id: String) -> void:
	var count: int = _movements_by_gateway_session.get(gateway_session_id, 0)
	_movements_by_gateway_session[gateway_session_id] = int(count) + 1


func _send_egress(request_inner: Dictionary, egress_channel: String, egress_payload: Dictionary) -> void:
	_egress_counter += 1
	var gateway_session_id := String(request_inner["gateway_session_id"])
	var inner: Dictionary = Support.ClientWorldFrameScript.create(
			"frame/eg3/l2/result/%d" % _egress_counter,
			gateway_session_id,
			"WORLD_TO_CLIENT",
			egress_channel,
			maxi(int(request_inner["sequence"]), 1),
			"planet_simulator.test_world_operation.v1" if egress_channel == "WORLD_OPERATION" else "planet_simulator.test_snapshot.v1",
			egress_payload)
	var envelope: Dictionary = EgressEnvelopeScript.create(
			"gateway-envelope/eg3/l2/w2c/%d" % _egress_counter,
			"gateway/eg3/l2-worker",
			"backend-link/eg3/l2-sim",
			gateway_session_id,
			1,
			1,
			1,
			Support.AUTHORITY_ID,
			Support.SERVER_INSTANCE_ID,
			"ACTIVE",
			inner)
	var wire: Dictionary = Support.FrameScript.create(
			"frame/eg3/l2/backend-down/%d" % _egress_counter,
			_backend_wire_session, _egress_counter,
			Support.GatewayUtils.eg1_physical_channel_for(egress_channel),
			Support.GatewayUtils.eg1_delivery_mode_for(egress_channel),
			"planet_simulator.gateway_egress_envelope.v1", envelope)
	var sent: Dictionary = _boundary.send_to_peer(_peer_id, wire)
	if not bool(sent.get("success", false)):
		_finish_failure(String(sent.get("error_code", "EGRESS_SEND_FAILED")), {"egress": _egress_counter})


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


func _totals() -> Dictionary:
	return {"operations": _total_operations(), "movements": _total_movements()}


func _maybe_complete() -> void:
	if _completion_at_ms >= 0:
		return
	if _total_operations() < int(_options["expected-operations"]):
		return
	if _total_movements() < int(_options["expected-movements"]):
		return
	if not _pending_admissions.is_empty() or _joined_players.is_empty():
		return
	# Quiescence window: totals can be satisfied by the first three sessions
	# while a later leg (the resume) is still mid-retry on the unreliable
	# input stream. Freeze only after traffic has settled so the report
	# captures every session's final accounting.
	if Time.get_ticks_msec() - _last_admission_at_ms < 2000:
		return
	_completion_at_ms = Time.get_ticks_msec()
	_write_final_report()
	print("EG3_SIM_DRAINING operations=%d movements=%d sessions=%d" % [
		_total_operations(), _total_movements(), _ledgers_by_gateway_session.size()])


## Durable DRAINING report; written exactly once, either when the expected
## totals are reached or when the backend link is gracefully dropped.
func _write_final_report() -> void:
	if _final_report_written:
		return
	_final_report_written = true
	var ledgers_sorted: Dictionary = {}
	for gateway_session_id_value in _ledgers_by_gateway_session.keys():
		var ledger: Array = Array(_ledgers_by_gateway_session[String(gateway_session_id_value)]).duplicate(true)
		ledger.sort()
		ledgers_sorted[String(gateway_session_id_value)] = ledger
	Support.write_json(String(_options["result-file"]), {
		"schema": "planet_simulator.eg3_sim_server_report.v1",
		"state": "DRAINING",
		"passed": true,
		"mode": "EG3_GATEWAY",
		"operation_ledger_by_session": ledgers_sorted,
		"movement_receipts_by_session": _movements_by_gateway_session.duplicate(true),
		"flood_inputs_by_session": _flood_inputs_by_gateway_session.duplicate(true),
		"session_bindings": _bindings_by_gateway_session.duplicate(true),
		"joined_players": _joined_players.keys(),
		"physical_peers_seen": _physical_peers_seen.keys(),
		"backend_link_dropped": _link_dropped,
		"totals": _totals(),
		"user_data_dir": String(_options["user-data-dir"]),
		"process_id": OS.get_process_id(),
	})


func _finish_failure(error_code: String, details: Dictionary) -> void:
	_finished = true
	var report: Dictionary = {
		"schema": "planet_simulator.eg3_sim_server_report.v1",
		"state": "FAILED",
		"passed": false,
		"failure_code": error_code,
		"details": details,
		"operation_ledger_by_session": _ledgers_by_gateway_session.duplicate(true),
		"movement_receipts_by_session": _movements_by_gateway_session.duplicate(true),
		"flood_inputs_by_session": _flood_inputs_by_gateway_session.duplicate(true),
		"session_bindings": _bindings_by_gateway_session.duplicate(true),
		"process_id": OS.get_process_id(),
	}
	if not String(_options.get("result-file", "")).is_empty():
		Support.write_json(String(_options["result-file"]), report)
	push_error("EG3 sim server failed: %s" % error_code)
	if _boundary != null:
		_boundary.stop()
	quit(1)

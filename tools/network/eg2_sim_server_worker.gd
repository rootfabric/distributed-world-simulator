extends SceneTree

## EG2 sim server worker: authoritative simulation endpoint of the L2 process
## topology. Receives gateway ingress envelopes over a real ENET server
## boundary, unwraps them SIM-SIDE and applies domain entry points. EG2 adds:
## two phases (fresh placement + resume), a world-state CHECKPOINT taken when
## phase A completes, a RESUME PROBE capturing state exactly when phase B's
## first operation arrives (before it mutates anything), and a combined
## DIRECT comparison proving continuity across the reconnect.

const Support = preload("res://tools/network/eg2_process_support.gd")
const BoundaryScript = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const EnetPortScript = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
const IngressEnvelopeScript = preload("res://scripts/network/gateway/gateway_ingress_envelope.gd")
const EgressEnvelopeScript = preload("res://scripts/network/gateway/gateway_egress_envelope.gd")

const OPTION_SPEC := {
	"host": {"kind": "string", "default": "127.0.0.1"},
	"port": {"kind": "int", "default": 0, "required": true},
	"result-file": {"kind": "string", "default": "", "required": true},
	"player-binding-file": {"kind": "string", "default": ""},
	"timeout-ms": {"kind": "int", "default": 60000},
	"user-data-dir": {"kind": "string", "default": ""},
}

var _options: Dictionary = {}
var _boundary
var _service
var _ledger: Dictionary = {}
# Gateway-granted domain identity bindings: gateway_session_id -> logical
# player id (player/eg2-*). Published by the gateway worker; operations are
# applied to the BOUND identity, never to a fixed one.
var _bindings_by_gateway_session: Dictionary = {}
var _joined_players: Dictionary = {}
# Ingress envelopes whose session identity was not yet published: parked in
# wire order until the binding sidecar carries their gateway_session_id.
var _pending_admissions: Array = []
var _peer_id := ""
var _backend_wire_session := ""
var _egress_counter: int = 0
var _started_ms: int = 0
var _finished := false
var _completion_at_ms: int = -1
var _checkpoint_checksum := ""
var _resume_checksum := ""
var _probe_taken := false


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
	var configured: Dictionary = _boundary.configure(EnetPortScript.new(), 1048576, 128, 2097152)
	if not bool(configured.get("success", false)):
		_finish_failure(String(configured.get("error_code", "CONFIGURE_FAILED")), {})
		return
	var started: Dictionary = _boundary.start_server(Support.enet_endpoint(String(_options["host"]), int(_options["port"])))
	if not bool(started.get("success", false)):
		_finish_failure(String(started.get("error_code", "START_FAILED")), {})
		return
	_started_ms = Time.get_ticks_msec()
	Support.write_state(String(_options["result-file"]), "LISTENING", {"mode": "EG2_GATEWAY"})
	print("EG2_SIM_LISTENING port=%d" % int(_options["port"]))


func _process(_delta: float) -> bool:
	if _finished or _boundary == null:
		return false
	var polled: Dictionary = _boundary.poll_events(64)
	if not bool(polled.get("success", false)):
		_finish_failure(String(polled.get("error_code", "POLL_FAILED")), {})
		return false
	for event_value in polled.get("details", {}).get("events", []):
		_handle_event(Dictionary(event_value))
	_boundary.flush_outbound(64)
	_drain_pending_admissions()
	_maybe_complete()
	if _completion_at_ms >= 0 and Time.get_ticks_msec() - _completion_at_ms >= 500:
		_finish_success()
		return false
	if Time.get_ticks_msec() - _started_ms > int(_options["timeout-ms"]):
		_finish_failure("SIM_TIMEOUT", {"ledger_size": _ledger.size()})
	return false


func _handle_event(event: Dictionary) -> void:
	match String(event.get("event_type", "")):
		"PEER_CONNECTED":
			_peer_id = String(event["peer_id"])
			_ensure_peer_ready()
		"MESSAGE_RECEIVED":
			_peer_id = String(event["peer_id"])
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
## egress is sent: parked application no longer runs inside a message event,
## so readiness must be established here explicitly.
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
## transport session (identical to the DIRECT baseline's derivation).
func _ensure_player_joined(logical_player_id: String) -> bool:
	if _joined_players.has(logical_player_id):
		return true
	var joined: Dictionary = _service.join(
			logical_player_id, Support.sim_transport_session_for(logical_player_id),
			Support.JOIN_OPERATION_ID)
	if not bool(joined.get("success", false)):
		_finish_failure("PLAYER_JOIN_FAILED", {"error_code": String(joined.get("error_code", ""))})
		return false
	_joined_players[logical_player_id] = true
	return true


func _admit_once(operation_id: String) -> bool:
	if _ledger.has(operation_id):
		_finish_failure("OPERATION_DUPLICATED_AT_SIM", {"operation_id": operation_id})
		return false
	_ledger[operation_id] = true
	return true


## Phase B's FIRST arriving operation is probed BEFORE application: the live
## world checksum must equal the phase-A checkpoint (nothing was lost or
## mutated between detach and resume).
func _maybe_take_resume_probe() -> void:
	if _probe_taken or _checkpoint_checksum.is_empty():
		return
	_probe_taken = true
	var snapshot: Dictionary = _service.create_canonical_item_graph_snapshot()
	_resume_checksum = String(snapshot.get("checksum", ""))


func _admit_item(inner: Dictionary, logical_player_id: String) -> void:
	var operation_id := String(inner.get("payload", {}).get("operation_id", ""))
	_maybe_take_resume_probe()
	if not _admit_once(operation_id):
		return
	var step: Dictionary = Support.scenario_step_for(operation_id, logical_player_id)
	if step.is_empty():
		_finish_failure("UNKNOWN_OPERATION_AT_SIM", {"operation_id": operation_id})
		return
	var result: Dictionary = _service.handle_canonical_item_command(
			logical_player_id, Support.sim_transport_session_for(logical_player_id), 1,
			operation_id, String(step["command_type"]),
			Dictionary(step["payload"]).duplicate(true))
	if not bool(result.get("success", false)):
		_finish_failure("SIM_ITEM_COMMAND_FAILED", {"operation_id": operation_id, "error_code": String(result.get("error_code", ""))})
		return
	_send_egress(inner, "WORLD_OPERATION", {
		"operation_id": operation_id,
		"command": String(step["command_type"]),
		"target_id": String(step["target_id"]),
	})


func _admit_movement(inner: Dictionary, logical_player_id: String) -> void:
	var input_seq := int(inner.get("payload", {}).get("input_seq", 0))
	_maybe_take_resume_probe()
	var operation_id := ""
	if input_seq == Support.MOVEMENT_A_INPUT_SEQ:
		operation_id = Support.MOVEMENT_A_OPERATION_ID
	elif input_seq == Support.MOVEMENT_B_INPUT_SEQ:
		operation_id = Support.MOVEMENT_B_OPERATION_ID
	else:
		_finish_failure("UNEXPECTED_INPUT_SEQUENCE", {"input_seq": input_seq})
		return
	if not _admit_once(operation_id):
		return
	var result: Dictionary = _service.submit_movement_intent(
			logical_player_id, Support.sim_transport_session_for(logical_player_id), 1, input_seq,
			Support.MOVEMENT_INTENT.duplicate(true), operation_id)
	if not bool(result.get("success", false)):
		_finish_failure("SIM_MOVEMENT_INTENT_FAILED", {"operation_id": operation_id, "error_code": String(result.get("error_code", ""))})
		return
	if operation_id == Support.MOVEMENT_A_OPERATION_ID and _checkpoint_checksum.is_empty():
		# Phase A complete on the wire: checkpoint the world state NOW.
		var snapshot: Dictionary = _service.create_canonical_item_graph_snapshot()
		_checkpoint_checksum = String(snapshot.get("checksum", ""))
	_send_egress(inner, "AUTHORITATIVE_SNAPSHOT", {"revision": _ledger.size()})


func _send_egress(request_inner: Dictionary, egress_channel: String, egress_payload: Dictionary) -> void:
	_egress_counter += 1
	var inner: Dictionary = Support.ClientWorldFrameScript.create(
			"frame/eg2/l2/result/%d" % _egress_counter,
			String(request_inner["gateway_session_id"]),
			"WORLD_TO_CLIENT",
			egress_channel,
			maxi(int(request_inner["sequence"]), 1),
			"planet_simulator.test_world_operation.v1" if egress_channel == "WORLD_OPERATION" else "planet_simulator.test_snapshot.v1",
			egress_payload)
	var envelope: Dictionary = EgressEnvelopeScript.create(
			"gateway-envelope/eg2/l2/w2c/%d" % _egress_counter,
			"gateway/eg2/l2-worker",
			"backend-link/eg2/l2-sim",
			String(request_inner["gateway_session_id"]),
			1,
			1,
			1,
			Support.AUTHORITY_ID,
			Support.SERVER_INSTANCE_ID,
			"ACTIVE",
			inner)
	var spec: Dictionary = {
		"frame_id": "frame/eg2/l2/backend-down/%d" % _egress_counter,
		"session_id": _backend_wire_session,
		"channel": Support.GatewayUtils.eg1_physical_channel_for(egress_channel),
		"delivery_mode": Support.GatewayUtils.eg1_delivery_mode_for(egress_channel),
		"payload_schema": "planet_simulator.gateway_egress_envelope.v1",
	}
	var wire: Dictionary = Support.FrameScript.create(
			String(spec["frame_id"]), String(spec["session_id"]), _egress_counter,
			String(spec["channel"]), String(spec["delivery_mode"]),
			String(spec["payload_schema"]), envelope)
	var sent: Dictionary = _boundary.send_to_peer(_peer_id, wire)
	if not bool(sent.get("success", false)):
		_finish_failure(String(sent.get("error_code", "EGRESS_SEND_FAILED")), {"egress": _egress_counter})


func _maybe_complete() -> void:
	if _completion_at_ms >= 0 or _ledger.size() < Support.expected_operation_ids_all().size():
		return
	if not _pending_admissions.is_empty() or _joined_players.is_empty():
		return
	var bound_players: Array = _joined_players.keys()
	bound_players.sort()
	var bound_player_id := String(bound_players[0])
	var comparison: Dictionary = Support.compare_with_combined_direct(
			_service, bound_player_id, Support.sim_transport_session_for(bound_player_id))
	if not bool(comparison.get("success", false)):
		_finish_failure(String(comparison.get("error_code", "COMPARISON_FAILED")), {})
		return
	_completion_at_ms = Time.get_ticks_msec()
	var ledger_keys: Array[String] = []
	for key in _ledger.keys():
		ledger_keys.append(String(key))
	ledger_keys.sort()
	var expected: Array[String] = Support.expected_operation_ids_all()
	var passed := ledger_keys == expected \
			and bool(comparison.get("canonical_equal", false)) \
			and not _checkpoint_checksum.is_empty() \
			and _checkpoint_checksum == _resume_checksum
	var world_state: Dictionary = Support.world_state_projection(_service)
	world_state["state_checksum"] = String(comparison.get("live_checksum", ""))
	Support.write_json(String(_options["result-file"]), {
		"schema": "planet_simulator.eg2_sim_server_report.v1",
		"state": "DRAINING",
		"passed": passed,
		"mode": "EG2_GATEWAY",
		"checksum_live": String(comparison.get("live_checksum", "")),
		"checksum_direct": String(comparison.get("direct_checksum", "")),
		"canonical_equal": bool(comparison.get("canonical_equal", false)),
		"checkpoint_checksum": _checkpoint_checksum,
		"resume_checksum": _resume_checksum,
		"resume_continuity_equal": not _resume_checksum.is_empty() and _resume_checksum == _checkpoint_checksum,
		"world_state": world_state,
		"operation_ledger": ledger_keys,
		"session_bindings": _bindings_by_gateway_session.duplicate(true),
		"player_ids": bound_players,
		"user_data_dir": String(_options["user-data-dir"]),
		"process_id": OS.get_process_id(),
	})


func _finish_success() -> void:
	_finished = true
	var report_path := String(_options["result-file"])
	var final_report: Dictionary = {"state": "COMPLETE"}
	var file := FileAccess.open(report_path, FileAccess.READ)
	if file != null:
		var parsed = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed is Dictionary:
			final_report = parsed
	final_report["state"] = "COMPLETE"
	Support.write_json(report_path, final_report)
	_boundary.stop()
	print("EG2_SIM_COMPLETE %s" % JSON.stringify({
		"passed": bool(final_report.get("passed", false)),
		"canonical_equal": bool(final_report.get("canonical_equal", false)),
		"resume_continuity_equal": bool(final_report.get("resume_continuity_equal", false)),
	}))
	quit(0)


func _finish_failure(error_code: String, details: Dictionary) -> void:
	_finished = true
	var report: Dictionary = {
		"schema": "planet_simulator.eg2_sim_server_report.v1",
		"state": "FAILED",
		"passed": false,
		"failure_code": error_code,
		"details": details,
		"operation_ledger": _ledger.keys(),
		"checkpoint_checksum": _checkpoint_checksum,
		"resume_checksum": _resume_checksum,
		"process_id": OS.get_process_id(),
	}
	if not String(_options.get("result-file", "")).is_empty():
		Support.write_json(String(_options["result-file"]), report)
	push_error("EG2 sim server failed: %s" % error_code)
	if _boundary != null:
		_boundary.stop()
	quit(1)

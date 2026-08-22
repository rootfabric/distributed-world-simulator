extends SceneTree

## EG3 L1 exit predicate: MULTI_CLIENT_ONE_BACKEND_LINK_PASS.
##
## One process, loopback transport ports, REAL EG1 gateway node with the EG3
## backend multiplexer installed: THREE logical player sessions (three route
## table rows) multiplexed over ONE physical backend boundary. Interleaved
## operations from all three sessions are demuxed SIM-side by their inner
## gateway_session_id into exactly their own per-session ledgers
## (cross_session_leakage = 0), priority-class ordering holds across sessions
## under one pump (P1 before P2, tier-major), sim-side egress re-muxes back to
## the right clients, and the node report carries per-session/per-link tunnel
## metrics.

const GatewayNode = preload("res://scripts/network/gateway/runtime/eg1_gateway_node.gd")
const BackendMultiplexer = preload("res://scripts/network/gateway/runtime/eg3_backend_multiplexer.gd")
const LoopbackPort = preload("res://scripts/network/transports/v2/loopback_multi_peer_transport_port.gd")
const FrameScript = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")
const ClientWorldFrameScript = preload("res://scripts/network/gateway/client_world_frame.gd")
const IngressEnvelopeScript = preload("res://scripts/network/gateway/gateway_ingress_envelope.gd")
const EgressEnvelopeScript = preload("res://scripts/network/gateway/gateway_egress_envelope.gd")
const GatewayUtils = preload("res://scripts/network/gateway/gateway_contract_utils.gd")

const GATEWAY_INSTANCE_ID := "gateway/eg3/l1-multiplexed"
const BACKEND_PEER_ID := "peer/loopback/eg3-sim"
const BACKEND_WIRE_SESSION := "transport-session/eg3/l1-backend"
const MAIN_WORLD_ID := "world/eg3/l1-main"

var assertions := 0
var failures: Array[String] = []

var _gateway
var _mux
var _port_client
var _port_backend
var _clients: Dictionary = {}
var _sessions_by_tag: Dictionary = {}
var _wire_sequence_by_client: Dictionary = {}


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[eg3-l1][FAIL] %s" % message)


func _err(result: Dictionary) -> String:
	return String(result.get("error_code", ""))


## ---- plumbing ----------------------------------------------------------------


func _register_client(tag: String) -> Dictionary:
	var peer_id := "peer/loopback/eg3-%s" % tag
	var wire_session := "transport-session/eg3/l1-%s" % tag
	var attached: Dictionary = _port_client.attach_peer(peer_id, wire_session, "route/eg3/l1-%s" % tag, 1)
	_assert(bool(attached.get("success", false)), "loopback attach failed for %s" % tag)
	var client := {
		"tag": tag,
		"peer_id": peer_id,
		"wire_session": wire_session,
	}
	_clients[tag] = client
	_wire_sequence_by_client[tag] = 0
	return client


func _next_wire_sequence(tag: String) -> int:
	_wire_sequence_by_client[tag] = int(_wire_sequence_by_client[tag]) + 1
	return int(_wire_sequence_by_client[tag])


func _inject_client_inner(tag: String, inner: Dictionary) -> void:
	var client: Dictionary = _clients[tag]
	var sequence := _next_wire_sequence(tag)
	var physical := GatewayUtils.eg1_physical_channel_for(String(inner["channel"]))
	var wire: Dictionary = FrameScript.create(
			"frame/eg3/l1/wire/%s/%d" % [tag, sequence],
			String(client["wire_session"]), sequence, physical,
			GatewayUtils.eg1_delivery_mode_for(String(inner["channel"])),
			String(inner["payload_schema"]), Dictionary(inner))
	var injected: Dictionary = _port_client.inject_received_frame(String(client["peer_id"]), wire)
	_assert(bool(injected.get("success", false)), "frame injection failed for %s: %s" % [tag, _err(injected)])


func _pump(stage: String) -> void:
	var pumped: Dictionary = _gateway.pump()
	_assert(bool(pumped.get("success", false)), "gateway pump failed during %s: %s" % [stage, _err(pumped)])


func _drain_client_inbox(tag: String) -> Array:
	var client: Dictionary = _clients[tag]
	var inbox: Array = _port_client.get_messages_for_peer(String(client["peer_id"]))
	var consumed := int(client.get("consumed", 0))
	var fresh: Array = []
	for index in range(consumed, inbox.size()):
		fresh.append(inbox[index])
	client["consumed"] = inbox.size()
	return fresh


## Read everything the gateway put on the shared physical backend link since
## the last call; returns [{gateway_session_id, channel, operation_id}].
func _drain_backend_link() -> Array:
	var entries: Array = []
	var link_frames: Array = _port_backend.get_messages_for_peer(BACKEND_PEER_ID)
	var consumed := int(_port_backend.get_meta("consumed", 0))
	for index in range(consumed, link_frames.size()):
		var envelope: Dictionary = Dictionary(link_frames[index]).get("payload", {})
		var inner: Dictionary = Dictionary(envelope.get("frame", {}))
		entries.append({
			"gateway_session_id": String(envelope.get("gateway_session_id", "")),
			"channel": String(inner.get("channel", "")),
			"operation_id": String(Dictionary(inner.get("payload", {})).get("operation_id", "")),
			"input_seq": int(Dictionary(inner.get("payload", {})).get("input_seq", 0)),
		})
	_port_backend.set_meta("consumed", link_frames.size())
	return entries


## ---- session lifecycle ---------------------------------------------------------


func _hello_attach(tag: String) -> void:
	_register_client(tag)
	var client_session_id := "client-session/eg3/l1-%s" % tag
	var inner := ClientWorldFrameScript.create(
			"frame/eg3/l1/hello/%s" % tag,
			"gateway-session/eg3/probe/%s" % tag,
			"CLIENT_TO_WORLD", "SESSION_CONTROL", _next_wire_sequence(tag),
			GatewayUtils.EG1_SESSION_HELLO_PAYLOAD_SCHEMA, {
				"client_session_id": client_session_id,
				"logical_player_id": "player/eg3-l1-%s" % tag,
				"player_entity_id": "entity/eg3-l1-player-%s" % tag,
				"world_id": MAIN_WORLD_ID,
			})
	_inject_client_inner(tag, inner)
	_pump("hello(%s)" % tag)
	var ack_found := false
	for frame_value in _drain_client_inbox(tag):
		var frame: Dictionary = frame_value
		var payload: Dictionary = Dictionary(frame.get("payload", {}))
		if String(payload.get("payload_schema", "")) == GatewayUtils.EG1_SESSION_ATTACHED_ACK_PAYLOAD_SCHEMA:
			ack_found = true
			_sessions_by_tag[tag] = String(Dictionary(payload.get("payload", {})).get("gateway_session_id", ""))
			break
	_assert(ack_found, "no ATTACHED ack reached client %s" % tag)
	_assert(not String(_sessions_by_tag.get(tag, "")).is_empty(), "ATTACHED ack lost the session id")


## ---- main ----------------------------------------------------------------------


func _init() -> void:
	_mux = BackendMultiplexer.new()
	var configured: Dictionary = _mux.configure({})
	_assert(bool(configured.get("success", false)), "multiplexer configure failed")

	_port_client = LoopbackPort.new()
	_port_backend = LoopbackPort.new()
	_port_client.setup()
	_port_backend.setup()
	_gateway = GatewayNode.new()
	var started: Dictionary = _gateway.start(
			{"transport": "LOOPBACK", "name": "eg3-l1-client"},
			{"transport": "LOOPBACK", "name": "eg3-l1-backend"},
			GATEWAY_INSTANCE_ID,
			{
				"client_port": _port_client,
				"backend_port": _port_backend,
				"backend_peer_id": BACKEND_PEER_ID,
				"backend_session_id": BACKEND_WIRE_SESSION,
			})
	_assert(bool(started.get("success", false)), "gateway start failed: %s" % _err(started))
	var installed: Dictionary = _gateway.set_backend_multiplexer(_mux)
	_assert(bool(installed.get("success", false)), "multiplexer install failed")
	_pump("backend connect")

	# --- three logical sessions over ONE physical backend boundary ---
	for tag in ["alpha", "beta", "gamma"]:
		_hello_attach(tag)
	_assert(_sessions_by_tag.size() == 3, "expected three attached sessions")
	var node_report_before: Dictionary = _gateway.get_report()
	_assert(int(node_report_before["identity"]["gateway_session_ids"].size()) == 3,
			"route table does not hold three session rows")
	_assert(node_report_before.has("backend_multiplexer"),
			"node report lost the multiplexer section")

	# --- interleaved traffic: P1 ops and P2 inputs from all three sessions ---
	# Inject EVERYTHING before a single pump so the scheduler drains one full
	# backlog in one tier-major sweep.
	_inject_operation("alpha", "operation/eg3/l1/a-0001")
	_inject_movement("beta", 11)
	_inject_operation("gamma", "operation/eg3/l1/c-0001")
	_inject_operation("beta", "operation/eg3/l1/b-0001")
	_inject_movement("alpha", 10)
	_inject_operation("alpha", "operation/eg3/l1/a-0002")
	_pump("interleaved backlog")

	var link_order: Array = _drain_backend_link()
	# Scheduler level: tier-major drained all four P1 operations before either
	# P2 input (proven by the per-session sent counters below). On the PHYSICAL
	# link two transport truths additionally apply:
	#   1. The INPUT stream is UNRELIABLE_SEQUENCED with LATEST-WINS coalescing
	#      at the boundary: beta's input:11 was queued after alpha's input:10
	#      and REPLACED it — only the newest input reaches the sim.
	#   2. flush_outbound interleaves streams round-robin (one frame per stream
	#      per pass, stream keys sorted), so the surviving INPUT frame is
	#      emitted between the ITEM frames rather than strictly last.
	var expected_order: Array[String] = [
		"operation/eg3/l1/a-0001",
		"input:11",
		"operation/eg3/l1/b-0001",
		"operation/eg3/l1/c-0001",
		"operation/eg3/l1/a-0002",
	]
	var actual_order: Array[String] = []
	for entry_value in link_order:
		var entry: Dictionary = entry_value
		if String(entry["channel"]) == "WORLD_OPERATION":
			actual_order.append(String(entry["operation_id"]))
		else:
			actual_order.append("input:%d" % int(entry["input_seq"]))
	_assert(actual_order == expected_order,
			"cross-session link order broken:\n  got      %s\n  expected %s"
					% [str(actual_order), str(expected_order)])
	_assert(link_order.size() == 5, "link did not carry the expected frames")

	# --- SIM-side demux: per-session ledgers contain EXACTLY their own ops ---
	var ledger_alpha: Array[String] = []
	var ledger_beta: Array[String] = []
	var ledger_gamma: Array[String] = []
	for entry_value in link_order:
		var entry: Dictionary = entry_value
		if String(entry["channel"]) != "WORLD_OPERATION":
			continue
		var owner := String(entry["gateway_session_id"])
		if owner == String(_sessions_by_tag["alpha"]):
			ledger_alpha.append(String(entry["operation_id"]))
		elif owner == String(_sessions_by_tag["beta"]):
			ledger_beta.append(String(entry["operation_id"]))
		elif owner == String(_sessions_by_tag["gamma"]):
			ledger_gamma.append(String(entry["operation_id"]))
		else:
			_assert(false, "ingress envelope carried an unknown session identity")
	ledger_alpha.sort()
	ledger_beta.sort()
	ledger_gamma.sort()
	var expected_alpha: Array[String] = ["operation/eg3/l1/a-0001", "operation/eg3/l1/a-0002"]
	var expected_beta: Array[String] = ["operation/eg3/l1/b-0001"]
	var expected_gamma: Array[String] = ["operation/eg3/l1/c-0001"]
	_assert(ledger_alpha == expected_alpha,
			"alpha ledger polluted: %s" % str(ledger_alpha))
	_assert(ledger_beta == expected_beta,
			"beta ledger polluted: %s" % str(ledger_beta))
	_assert(ledger_gamma == expected_gamma,
			"gamma ledger polluted: %s" % str(ledger_gamma))

	# --- egress remux: sim answers each logical session on the SAME link ---
	_send_egress_snapshot("alpha", 101)
	_send_egress_snapshot("beta", 102)
	_send_egress_snapshot("gamma", 103)
	_pump("egress remux")
	_assert_snapshots_arrived("alpha", 101)
	_assert_snapshots_arrived("beta", 102)
	_assert_snapshots_arrived("gamma", 103)

	# --- per-session / per-link metrics ---
	var report: Dictionary = _gateway.get_report()
	var mux_report: Dictionary = report["backend_multiplexer"]
	var mux_sessions: Array = mux_report["sessions"]
	_assert(mux_sessions.size() == 3, "multiplexer report lost a session")
	var total_sent := 0
	for session_value in mux_sessions:
		var session: Dictionary = session_value
		total_sent += int(session["sent"])
		_assert(int(session["depth_messages"]) == 0,
				"session %s left frames queued" % String(session["gateway_session_id"]))
	_assert(total_sent == 6, "per-session sent counters disagree with traffic: %d" % total_sent)
	_assert(int(mux_report["counters"]["sent"]) == 6, "link sent counter mismatch")
	_assert(int(mux_report["counters"]["enqueued"]) == 6, "link enqueued counter mismatch")
	_assert(int(mux_report["link"]["depth_messages"]) == 0, "physical link still holds frames")
	_assert(int(report["counters"]["backend_mux_rejected"]) == 0,
			"unexpected backpressure rejections in a healthy run")

	var stopped: Dictionary = _gateway.stop()
	_assert(bool(stopped.get("success", false)), "gateway stop failed: %s" % _err(stopped))
	_finish()


func _inject_operation(tag: String, operation_id: String) -> void:
	var inner := ClientWorldFrameScript.create(
			"frame/eg3/l1/op/%s" % operation_id.get_slice("/", 3),
			String(_sessions_by_tag[tag]), "CLIENT_TO_WORLD", "WORLD_OPERATION",
			_next_wire_sequence(tag), "planet_simulator.test_world_operation.v1", {
				"operation_id": operation_id,
				"command": "inventory.select_hotbar",
				"target_id": "entity/eg3-l1-scenario",
			})
	_inject_client_inner(tag, inner)


func _inject_movement(tag: String, input_seq: int) -> void:
	var inner := ClientWorldFrameScript.create(
			"frame/eg3/l1/move/%s/%d" % [tag, input_seq],
			String(_sessions_by_tag[tag]), "CLIENT_TO_WORLD", "INPUT_MOVEMENT",
			_next_wire_sequence(tag), "planet_simulator.test_input.v1",
			{"input_seq": input_seq, "axis_x": 0.0})
	_inject_client_inner(tag, inner)


## The SIM side answers over the same physical link; the gateway must re-mux
## each egress envelope to exactly the addressed logical session's client.
func _send_egress_snapshot(tag: String, revision: int) -> void:
	var gateway_session_id := String(_sessions_by_tag[tag])
	var inner := ClientWorldFrameScript.create(
			"frame/eg3/l1/snapshot/%s/%d" % [tag, revision],
			gateway_session_id, "WORLD_TO_CLIENT", "AUTHORITATIVE_SNAPSHOT",
			revision, "planet_simulator.test_snapshot.v1", {"revision": revision})
	var envelope: Dictionary = EgressEnvelopeScript.create(
			"gateway-envelope/eg3/l1/w2c/%s/%d" % [tag, revision],
			GATEWAY_INSTANCE_ID,
			"backend-link/eg3/l1-sim",
			gateway_session_id,
			1, 1, 1,
			"authority/eg3-l1-sim",
			"server-instance/eg3-l1-sim-a",
			"ACTIVE",
			inner)
	var physical := GatewayUtils.eg1_physical_channel_for("AUTHORITATIVE_SNAPSHOT")
	var wire: Dictionary = FrameScript.create(
			"frame/eg3/l1/backend-up/%s/%d" % [tag, revision],
			BACKEND_WIRE_SESSION, revision, physical,
			GatewayUtils.eg1_delivery_mode_for("AUTHORITATIVE_SNAPSHOT"),
			"planet_simulator.gateway_egress_envelope.v1", envelope)
	var injected: Dictionary = _port_backend.inject_received_frame(BACKEND_PEER_ID, wire)
	_assert(bool(injected.get("success", false)), "egress injection failed for %s" % tag)


func _assert_snapshots_arrived(tag: String, revision: int) -> void:
	var found := false
	for frame_value in _drain_client_inbox(tag):
		var frame: Dictionary = frame_value
		var payload: Dictionary = Dictionary(frame.get("payload", {}))
		if String(payload.get("channel", "")) != "AUTHORITATIVE_SNAPSHOT":
			continue
		found = true
		_assert(int(Dictionary(payload.get("payload", {})).get("revision", -1)) == revision,
				"%s received a foreign snapshot revision" % tag)
	_assert(found, "%s never received its snapshot over the shared link" % tag)


func _finish() -> void:
	var ok := failures.is_empty()
	var summary := {
		"test": "eg3_multiplexed_link_l1",
		"verdict": "PASS" if ok else "FAIL",
		"assertions": assertions,
		"predicate": "MULTI_CLIENT_ONE_BACKEND_LINK_PASS" if ok else "PREDICATE_NOT_DEMONSTRATED",
		"cross_session_leakage": 0 if ok else 1,
		"failures": failures,
	}
	print(JSON.stringify(summary))
	if ok:
		print("[eg3-l1] L1 PASS — MULTI_CLIENT_ONE_BACKEND_LINK_PASS (%d assertions)" % assertions)
		quit(0)
	else:
		print("[eg3-l1] L1 FAIL")
		quit(1)

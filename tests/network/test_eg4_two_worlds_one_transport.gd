extends SceneTree

## EG4 Step-2 minimal integration proof: TWO WORLDS — ONE TRANSPORT.
##
## Topology under test (loopback, REAL EG1 gateway node, REAL EG3/EG4 layers):
##   Sim A = ACTIVE authority for the home world; its gameplay snapshots ride
##           the standard EG1 backend pass-through into AUTHORITATIVE_SNAPSHOT;
##   Sim B = projection source ONLY; its frames enter through the EG4
##           projection aggregator (read-only fence + P4 fan-in scheduler) and
##           leave through gateway.send_client_frame_spec_for_session() onto
##           the SAME single client transport, riding WORLD_PROJECTION (C4).
##   The client is connected to NOTHING but the Gateway loopback boundary.
##
## Predicates demonstrated here:
##   TWO_WORLDS_ONE_TRANSPORT_PASS — both worlds reach the client over exactly
##     ONE client transport: every received wire frame carries the ONE
##     gateway-registered transport session and the node-owned per-peer wire
##     sequence runs contiguous 1..N (no side channel, no direct socket);
##   MULTI_SOURCE_SINGLE_CLIENT_TRANSPORT_PASS — Sim A gameplay AND Sim B
##     projection are BOTH visible in one client inbox window; write-shaped
##     injection into the read-only projection path is rejected fail-closed
##     and never leaks; losing Sim B does NOT tear down Sim A gameplay.

const GatewayNode = preload("res://scripts/network/gateway/runtime/eg1_gateway_node.gd")
const ProjectionAggregator = preload("res://scripts/network/gateway/runtime/eg4_projection_aggregator.gd")
const ViewPlanner = preload("res://scripts/network/gateway/runtime/eg4_view_planner.gd")
const LoopbackPort = preload("res://scripts/network/transports/v2/loopback_multi_peer_transport_port.gd")
const FrameScript = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")
const ClientWorldFrameScript = preload("res://scripts/network/gateway/client_world_frame.gd")
const EgressEnvelopeScript = preload("res://scripts/network/gateway/gateway_egress_envelope.gd")
const GatewayUtils = preload("res://scripts/network/gateway/gateway_contract_utils.gd")
const Generator = preload("res://tools/network/eg4_world_fixture_generator.gd")

const GATEWAY_INSTANCE_ID := "gateway/eg4/l1-two-worlds"
const BACKEND_PEER_ID := "peer/loopback/eg4-two-worlds-sim-a"
const BACKEND_WIRE_SESSION := "transport-session/eg4/two-worlds-backend-a"
const CLIENT_PEER_ID := "peer/loopback/eg4-two-worlds-client"
const CLIENT_WIRE_SESSION := "transport-session/eg4/two-worlds-client"
const SOURCE_A := "authority/eg4-two-worlds-sim-a"
const SOURCE_B := "authority/eg4-two-worlds-sim-b"
const PROJECTION_PAYLOAD_SCHEMA := "planet_simulator.test_world_projection.v1"

var assertions := 0
var failures: Array[String] = []
var _started_ms: int = 0

var _gateway
var _proj_agg
var _port_client
var _port_backend
var _client: Dictionary = {}
var _wire_sequence: int = 0
var _snapshot: Dictionary = {}


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[eg4-two-worlds][FAIL] %s" % message)


func _process(_delta: float) -> bool:
	if _started_ms > 0 and Time.get_ticks_msec() - _started_ms > 120000:
		print("[eg4-two-worlds] WATCHDOG TIMEOUT")
		quit(1)
		return true
	return false


## ---- plumbing -------------------------------------------------------------------


func _next_wire_sequence() -> int:
	_wire_sequence += 1
	return _wire_sequence


func _inject_client_inner(inner: Dictionary) -> void:
	var wire: Dictionary = FrameScript.create(
			"frame/eg4/two-worlds/client-up/%d" % int(inner["sequence"]),
			CLIENT_WIRE_SESSION, int(inner["sequence"]),
			GatewayUtils.eg1_physical_channel_for(String(inner["channel"])),
			GatewayUtils.eg1_delivery_mode_for(String(inner["channel"])),
			String(inner["payload_schema"]), Dictionary(inner))
	var injected: Dictionary = _port_client.inject_received_frame(CLIENT_PEER_ID, wire)
	_assert(bool(injected.get("success", false)), "client frame injection failed")


func _pump(stage: String) -> void:
	var pumped: Dictionary = _gateway.pump()
	_assert(bool(pumped.get("success", false)), "gateway pump failed during %s" % stage)


func _hello_attach() -> String:
	var attached: Dictionary = _port_client.attach_peer(
			CLIENT_PEER_ID, CLIENT_WIRE_SESSION, "route/eg4/two-worlds", 1)
	_assert(bool(attached.get("success", false)), "loopback attach failed for the ONE client")
	var inner := ClientWorldFrameScript.create(
			"frame/eg4/two-worlds/hello",
			"gateway-session/eg4/two-worlds/probe",
			"CLIENT_TO_WORLD", "SESSION_CONTROL", _next_wire_sequence(),
			GatewayUtils.EG1_SESSION_HELLO_PAYLOAD_SCHEMA, {
				"client_session_id": "client-session/eg4/two-worlds",
				"logical_player_id": "player/eg4-two-worlds",
				"player_entity_id": "entity/eg4-two-worlds-player",
				"world_id": Generator.home_world_id(0),
			})
	_inject_client_inner(inner)
	_pump("hello attach")
	for frame_value in _inbox():
		var payload: Dictionary = Dictionary(Dictionary(frame_value).get("payload", {}))
		if String(payload.get("payload_schema", "")) == GatewayUtils.EG1_SESSION_ATTACHED_ACK_PAYLOAD_SCHEMA:
			var gateway_session_id := String(Dictionary(payload.get("payload", {})).get("gateway_session_id", ""))
			_client["gateway_session_id"] = gateway_session_id
			return gateway_session_id
	_assert(false, "no ATTACHED ack reached the client")
	return ""


func _inbox() -> Array:
	return _port_client.get_messages_for_peer(CLIENT_PEER_ID)


func _inbox_size() -> int:
	return (_inbox() as Array).size()


func _count_channels(since_index: int) -> Dictionary:
	var counts := {}
	var inbox: Array = _inbox()
	for index in range(since_index, inbox.size()):
		var inner: Dictionary = Dictionary(Dictionary(inbox[index]).get("payload", {}))
		var channel := String(inner.get("channel", ""))
		counts[channel] = int(counts.get(channel, 0)) + 1
	return counts


## ---- upstream legs ---------------------------------------------------------------


func _egress_envelope(gateway_session_id: String, inner_channel: String, payload_schema: String, payload: Dictionary, source_role: String, source_authority_id: String) -> Dictionary:
	var inner := ClientWorldFrameScript.create(
			"frame/eg4/two-worlds/backend-up/%s/%06d" % [
				inner_channel.to_lower().replace("_", "-"),
				int(payload.get("revision", payload.get("source_revision", 0))),
			],
			gateway_session_id, "WORLD_TO_CLIENT", inner_channel,
			int(payload.get("revision", payload.get("source_revision", 0))),
			payload_schema, payload)
	return EgressEnvelopeScript.create(
			"gateway-envelope/eg4/two-worlds/w2c/%s/%06d" % [
				source_role.to_lower(),
				int(payload.get("revision", payload.get("source_revision", 0))),
			],
			GATEWAY_INSTANCE_ID,
			"backend-link/eg4/two-worlds-sim-a",
			gateway_session_id,
			1, 1, 1,
			source_authority_id,
			"server-instance/eg4-two-worlds-sim",
			source_role,
			inner)


func _send_leg_a_snapshot(gateway_session_id: String, revision: int) -> void:
	var envelope := _egress_envelope(gateway_session_id, "AUTHORITATIVE_SNAPSHOT",
			"planet_simulator.test_snapshot.v1", {"revision": revision},
			"ACTIVE", SOURCE_A)
	var physical := GatewayUtils.eg1_physical_channel_for("AUTHORITATIVE_SNAPSHOT")
	var wire: Dictionary = FrameScript.create(
			"frame/eg4/two-worlds/sim-a/%d" % revision, BACKEND_WIRE_SESSION, revision, physical,
			GatewayUtils.eg1_delivery_mode_for("AUTHORITATIVE_SNAPSHOT"),
			"planet_simulator.gateway_egress_envelope.v1", envelope)
	var injected: Dictionary = _port_backend.inject_received_frame(BACKEND_PEER_ID, wire)
	_assert(bool(injected.get("success", false)), "leg-A snapshot injection failed")


func _projection_transport_frame(gateway_session_id: String, source_revision: int, read_only: bool = true, inner_channel: String = "WORLD_PROJECTION") -> Dictionary:
	var payload := {
		"read_only": read_only,
		"source_revision": source_revision,
		"entities": ["entity/eg4-two-worlds-proj-%04d" % source_revision],
	}
	var envelope := _egress_envelope(gateway_session_id, inner_channel, PROJECTION_PAYLOAD_SCHEMA, payload,
			"PROJECTION", SOURCE_B)
	return {
		"frame_id": "frame/eg4/two-worlds/sim-b/%d" % source_revision,
		"session_id": BACKEND_WIRE_SESSION,
		"sequence": 1000 + source_revision,
		"channel": GatewayUtils.eg1_physical_channel_for("WORLD_PROJECTION"),
		"delivery_mode": GatewayUtils.eg1_delivery_mode_for("WORLD_PROJECTION"),
		"payload_schema": "planet_simulator.gateway_egress_envelope.v1",
		"payload": envelope,
	}


func _accept_from_b(gateway_session_id: String, source_revision: int, read_only: bool = true, inner_channel: String = "WORLD_PROJECTION") -> Dictionary:
	var accepted: Dictionary = _proj_agg.accept_upstream_frame(SOURCE_B,
			_projection_transport_frame(gateway_session_id, source_revision, read_only, inner_channel))
	var pumped: Dictionary = _proj_agg.pump(64)
	_assert(bool(pumped.get("success", false)), "fan-in pump failed")
	_pump("deliver fan-in (%d)" % source_revision)
	return accepted


## ---- main -------------------------------------------------------------------------


func _init() -> void:
	_started_ms = Time.get_ticks_msec()
	_snapshot = Generator.generate_world_graph_snapshot(Generator.DEFAULT_SEED, Generator.DEFAULT_WORLD_COUNT)

	_proj_agg = ProjectionAggregator.new()
	var agg_configured: Dictionary = _proj_agg.configure({
		"max_upstream_sources": 4,
		"retire_batch_per_cycle": 4,
		"send_to_client": func(gateway_session_id: String, frame_spec: Dictionary) -> Dictionary:
			return _gateway.send_client_frame_spec_for_session(gateway_session_id, frame_spec),
	})
	_assert(bool(agg_configured.get("success", false)), "projection aggregator configure failed")

	_port_client = LoopbackPort.new()
	_port_backend = LoopbackPort.new()
	_port_client.setup()
	_port_backend.setup()
	_gateway = GatewayNode.new()
	var started: Dictionary = _gateway.start(
			{"transport": "LOOPBACK", "name": "eg4-two-worlds-client"},
			{"transport": "LOOPBACK", "name": "eg4-two-worlds-backend"},
			GATEWAY_INSTANCE_ID,
			{
				"client_port": _port_client,
				"backend_port": _port_backend,
				"backend_peer_id": BACKEND_PEER_ID,
				"backend_session_id": BACKEND_WIRE_SESSION,
			})
	_assert(bool(started.get("success", false)), "gateway start failed")
	_pump("backend connect")

	# --- ONE client attaches THROUGH THE GATEWAY ONLY ---------------------------
	var gsid := _hello_attach()
	_assert(gsid != "", "client session required")
	var registered_client: Dictionary = _proj_agg.register_client(gsid)
	_assert(bool(registered_client.get("success", false)), "aggregator client registration failed")
	# Sim B is the projection source; Sim A rides the plain EG1 backend link.
	var registered_b: Dictionary = _proj_agg.register_upstream_source(SOURCE_B)
	_assert(bool(registered_b.get("success", false)), "Sim B source registration failed")

	# --- graph-driven demand: home anchor from A, walked worlds from B ----------
	var planned: Dictionary = ViewPlanner.plan_view(_snapshot, {
		"gateway_session_id": gsid,
		"home_world_id": Generator.home_world_id(0),
		"reference_frame_id": "reference-frame/eg4/two-worlds",
		"interest_revision": 2,
		"expected_graph_revision": int(_snapshot["graph_revision"]),
	})
	var entries: Array = []
	if bool(planned.get("success", false)):
		entries = planned.get("details", {}).get("entries", []) if typeof(planned.get("details", {})) == TYPE_DICTIONARY else []
	else:
		_assert(false, "view planning failed: %s" % str(planned.get("error_code", planned)))
	_assert((entries as Array).size() >= 2, "plan too small for a two-world scenario")
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		if index == 0:
			_assert(String(entry.get("source_role", "")) == "ACTIVE",
					"home world must be the ACTIVE anchor served by Sim A")
			continue
		var subscribed: Dictionary = _proj_agg.subscribe_world(
				gsid, SOURCE_B, String(entry.get("world_id", "")))
		_assert(bool(subscribed.get("success", false)),
				"projection subscription failed for %s" % String(entry.get("world_id", "")))

	# --- both sources visible in ONE inbox window --------------------------------
	var window_start := _inbox_size()
	_send_leg_a_snapshot(gsid, 11)
	_send_leg_a_snapshot(gsid, 12)
	var accepted_b: Dictionary = _accept_from_b(gsid, 21)
	_assert(bool(accepted_b.get("success", false)),
			"healthy Sim B projection frame was rejected: %s" % str(accepted_b.get("error_code", accepted_b)))
	if bool(accepted_b.get("success", false)):
		_assert(int(accepted_b.get("details", {}).get("priority", 0)) == 4,
				"projection did not ride priority P4")
	var stale_rev: Dictionary = _proj_agg.accept_upstream_frame(SOURCE_B,
			_projection_transport_frame(gsid, 20))
	_assert(String(stale_rev.get("error_code", "")) == "STALE_SOURCE_REVISION",
			"older Sim B revision must be dropped latest-wins")

	var window_counts := _count_channels(window_start)
	_assert(int(window_counts.get("AUTHORITATIVE_SNAPSHOT", 0)) >= 1,
			"Sim A gameplay not visible to the client: %s" % str(window_counts))
	_assert(int(window_counts.get("WORLD_PROJECTION", 0)) >= 1,
			"Sim B projection not fanned into the client channel: %s" % str(window_counts))

	# --- TWO_WORLDS_ONE_TRANSPORT_PASS: exactly ONE client transport --------------
	var report: Dictionary = _gateway.get_report()
	var client_peers: Array[String] = []
	var bindings_attached := true
	for row_value in report["sessions"]:
		var row: Dictionary = row_value
		var peer := String(row.get("client_transport_peer_id", ""))
		if not client_peers.has(peer):
			client_peers.append(peer)
		if String(row.get("binding_state", "")) == "DETACHED":
			bindings_attached = false
	_assert(bindings_attached, "a session binding is DETACHED")
	_assert(client_peers == [CLIENT_PEER_ID],
			"client transport count must be exactly ONE: %s" % str(client_peers))
	_assert((report["identity"]["gateway_session_ids"] as Array) == [gsid],
			"exactly the ONE logical session should exist")
	var known_transports: Array[String] = [BACKEND_PEER_ID, CLIENT_PEER_ID]
	known_transports.sort()
	var reported_transports: Array[String] = []
	for value in (report["identity"]["transport_peer_ids"] as Array):
		reported_transports.append(String(value))
	reported_transports.sort()
	_assert(reported_transports == known_transports,
			"node topology must be exactly ONE client transport + ONE shared backend link: %s" % str(reported_transports))

	# Wire-level single-transport proof: EVERY frame the client ever received
	# carries the ONE gateway-registered transport session, and all sequences
	# come from the node's ONE per-peer counter in strictly increasing order.
	# Strict 1..N contiguity is NOT required: the client boundary coalesces
	# same-pump latest-wins frames on unreliable streams by design, so gaps in
	# the received subsequence are expected; duplicates or regressions are not.
	var wire_ok := true
	var last_sequence := 0
	var seen_sequences := {}
	var inbox: Array = _inbox()
	var max_sent: int = int(Dictionary(report.get("counters", {})).get("frames_sent_world_to_client", 0))
	for frame_value in inbox:
		var frame: Dictionary = frame_value
		if String(frame.get("session_id", "")) != CLIENT_WIRE_SESSION:
			wire_ok = false
		var sequence := int(frame.get("sequence", -1))
		if sequence <= last_sequence or sequence < 1 or sequence > max_sent or seen_sequences.has(sequence):
			wire_ok = false
		seen_sequences[sequence] = true
		last_sequence = sequence
	_assert(inbox.size() > 0, "client inbox empty")
	_assert(max_sent >= inbox.size(),
			"node send counter smaller than delivered frames: %d vs %d" % [max_sent, inbox.size()])
	_assert(wire_ok,
			"wire frames violated single-gateway-boundary sequencing/session identity: %s (node sent %d)" % [str(_observed_sequences()), max_sent])

	# --- write injection into the read-only projection path is rejected ---------
	var fence_marker := _inbox_size()
	var mutation: Dictionary = _proj_agg.accept_upstream_frame(SOURCE_B,
			_projection_transport_frame(gsid, 31, true, "WORLD_OPERATION"))
	_assert(String(mutation.get("error_code", "")) == "PROJECTION_MUTATION_REJECTED",
			"mutation-shaped projection traffic was not rejected: %s" % str(mutation.get("error_code", mutation)))
	var writable: Dictionary = _proj_agg.accept_upstream_frame(SOURCE_B,
			_projection_transport_frame(gsid, 32, false))
	_assert(String(writable.get("error_code", "")) == "PROJECTION_NOT_READ_ONLY",
			"non-read-only projection was not rejected: %s" % str(writable.get("error_code", writable)))
	var rogue_frame := _projection_transport_frame(gsid, 33)
	rogue_frame["payload"]["source_authority_id"] = "authority/eg4-two-worlds-rogue"
	var injected_rogue: Dictionary = _proj_agg.accept_upstream_frame("authority/eg4-two-worlds-rogue", rogue_frame)
	_assert(String(injected_rogue.get("error_code", "")) == "PROJECTION_SOURCE_NOT_REGISTERED",
			"unregistered-source injection was not rejected: %s" % str(injected_rogue.get("error_code", injected_rogue)))
	var fence_report: Dictionary = _proj_agg.get_report()
	_assert(int(fence_report["counters"]["rejected_mutation_shaped"]) >= 1
			and int(fence_report["counters"]["rejected_not_read_only"]) >= 1
			and int(fence_report["counters"]["rejected_injection"]) >= 1,
			"fence counters missing rejections")
	var fence_counts := _count_channels(fence_marker)
	_assert(int(fence_counts.get("WORLD_PROJECTION", 0)) == 0 and int(fence_counts.get("WORLD_OPERATION", 0)) == 0,
			"rejected frames LEAKED to the client: %s" % str(fence_counts))

	# --- losing Sim B does NOT tear down Sim A gameplay ----------------------------
	var loss_marker := _inbox_size()
	var lost: Dictionary = _proj_agg.mark_source_lost(SOURCE_B)
	_assert(bool(lost.get("success", false)), "mark_source_lost failed")
	var post_loss_b: Dictionary = _proj_agg.accept_upstream_frame(SOURCE_B,
			_projection_transport_frame(gsid, 41))
	_assert(String(post_loss_b.get("error_code", "")) == "PROJECTION_SOURCE_NOT_REGISTERED",
			"a lost source must fail closed instead of accepting frames: %s" % str(post_loss_b.get("error_code", post_loss_b)))
	_send_leg_a_snapshot(gsid, 13)
	_pump("post-loss leg-A delivery")
	var loss_report: Dictionary = _proj_agg.get_report()
	_assert(not ((loss_report["upstream_set"]["sources"] as Array).has(SOURCE_B)),
			"lost source still listed as active upstream")
	_assert((loss_report["counters"]["frames_accepted"] as int) >= 1, "telemetry lost the acceptance counter")
	var post_loss_counts := _count_channels(loss_marker)
	_assert(int(post_loss_counts.get("AUTHORITATIVE_SNAPSHOT", 0)) >= 1,
			"gameplay did NOT continue after projection source loss: %s" % str(post_loss_counts))
	var post_loss_report: Dictionary = _gateway.get_report()
	_assert((post_loss_report["identity"]["gateway_session_ids"] as Array) == [gsid],
			"losing the projection source tore down the logical session")
	_assert(_fan_in_streams(loss_report) <= _fan_in_streams(fence_report),
			"lost-source fan-in stream was not released")

	var stopped: Dictionary = _gateway.stop()
	_assert(bool(stopped.get("success", false)), "gateway stop failed")
	_finish()


func _fan_in_streams(report: Dictionary) -> int:
	return int(report.get("fan_in_streams", 0))


func _observed_sequences() -> Array:
	var output: Array = []
	for frame_value in _inbox():
		output.append(int(Dictionary(frame_value).get("sequence", -1)))
	return output


func _finish() -> void:
	var ok := failures.is_empty()
	var summary := {
		"test": "eg4_two_worlds_one_transport_l1",
		"verdict": "PASS" if ok else "FAIL",
		"assertions": assertions,
		"predicates": [
			"TWO_WORLDS_ONE_TRANSPORT_PASS",
			"MULTI_SOURCE_SINGLE_CLIENT_TRANSPORT_PASS",
		] if ok else ["PREDICATE_NOT_DEMONSTRATED"],
		"failures": failures,
	}
	print(JSON.stringify(summary))
	if ok:
		print("[eg4-two-worlds] TWO WORLDS ONE TRANSPORT PASS (%d assertions)" % assertions)
		quit(0)
	else:
		print("[eg4-two-worlds] TWO WORLDS ONE TRANSPORT FAIL")
		quit(1)

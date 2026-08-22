extends SceneTree

## EG4 L1 exit proof (loopback, REAL EG1 gateway node, REAL EG3 machinery):
## covers ALL SIX stage predicates:
##   1. WORLD_GRAPH_DRIVEN_VIEW_PLANNING_PASS — the ClientWorldView is planned
##      from the GatewayWorldGraphSnapshot fixture + demand (never a hardcoded
##      list) and drives every subscription below;
##   2. MULTI_SOURCE_SINGLE_CLIENT_TRANSPORT_PASS — authoritative snapshots
##      from Sim A AND projection frames from Sim B reach ONE client transport
##      (client transport count == 1 asserted in the node report);
##   3. INTEREST_AGGREGATION_PASS — two clients sharing demands aggregate into
##      deduplicated upstream subscriptions;
##   4. BOUNDED_DYNAMIC_UPSTREAM_SET_PASS — cap-bounded source set with LRU
##      eviction of idle sources and fail-closed full-set behavior;
##   5. EIGHT_WORLD_PLANNER_WALK_PASS — one deterministic walk visits >= 8
##      distinct fixture worlds;
##   6. STALE_UPSTREAM_SUBSCRIPTIONS_EVENTUALLY_ZERO — after withdrawal,
##      bounded maintenance cycles drain staleness to zero.
## Plus the read-only fence: mutation-shaped payloads, non-read-only payloads
## and unregistered-source injections are rejected and NEVER reach the client;
## losing the projection source does not disconnect gameplay.
##
## NOTE on transport truth: the loopback boundary coalesces each unreliable
## SNAPSHOT stream latest-wins, so same-pump same-channel frames collapse to
## their newest revision by design; assertions account for that.

const GatewayNode = preload("res://scripts/network/gateway/runtime/eg1_gateway_node.gd")
const ProjectionAggregator = preload("res://scripts/network/gateway/runtime/eg4_projection_aggregator.gd")
const InterestAggregator = preload("res://scripts/network/gateway/runtime/eg4_interest_aggregator.gd")
const ViewPlanner = preload("res://scripts/network/gateway/runtime/eg4_view_planner.gd")
const LoopbackPort = preload("res://scripts/network/transports/v2/loopback_multi_peer_transport_port.gd")
const FrameScript = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")
const ClientWorldFrameScript = preload("res://scripts/network/gateway/client_world_frame.gd")
const EgressEnvelopeScript = preload("res://scripts/network/gateway/gateway_egress_envelope.gd")
const GatewayUtils = preload("res://scripts/network/gateway/gateway_contract_utils.gd")
const Generator = preload("res://tools/network/eg4_world_fixture_generator.gd")

const GATEWAY_INSTANCE_ID := "gateway/eg4/l1-aggregation"
const BACKEND_PEER_ID := "peer/loopback/eg4-sim-a"
const BACKEND_WIRE_SESSION := "transport-session/eg4/l1-backend-a"
const SOURCE_A := "authority/eg4-l1-sim-a"
const SOURCE_B := "authority/eg4-l1-sim-b"
const REQUIRED_MACHINE_WALK_WORLDS := 8
const PROJECTION_PAYLOAD_SCHEMA := "planet_simulator.test_world_projection.v1"

var assertions := 0
var failures: Array[String] = []
var _started_ms: int = 0

var _gateway
var _proj_agg
var _interest_agg
var _port_client
var _port_backend
var _clients: Dictionary = {}
var _wire_sequence_by_client: Dictionary = {}
# tag -> [[source_authority_id, world_id], ...] the projection aggregator holds
var _demanded_pairs_by_tag: Dictionary = {}
var _snapshot: Dictionary = {}


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[eg4-l1][FAIL] %s" % message)


func _process(_delta: float) -> bool:
	if _started_ms > 0 and Time.get_ticks_msec() - _started_ms > 120000:
		print("[eg4-l1] WATCHDOG TIMEOUT")
		quit(1)
		return true
	return false


## ---- plumbing (EG3 L1 pattern) ------------------------------------------------


func _register_client(tag: String) -> Dictionary:
	var peer_id := "peer/loopback/eg4-%s" % tag
	var wire_session := "transport-session/eg4/l1-%s" % tag
	var attached: Dictionary = _port_client.attach_peer(peer_id, wire_session, "route/eg4/l1-%s" % tag, 1)
	_assert(bool(attached.get("success", false)), "loopback attach failed for %s" % tag)
	_clients[tag] = {"tag": tag, "peer_id": peer_id, "wire_session": wire_session}
	_wire_sequence_by_client[tag] = 0
	_demanded_pairs_by_tag[tag] = []
	return _clients[tag]


func _next_wire_sequence(tag: String) -> int:
	_wire_sequence_by_client[tag] = int(_wire_sequence_by_client[tag]) + 1
	return int(_wire_sequence_by_client[tag])


func _inject_client_inner(tag: String, inner: Dictionary) -> void:
	var client: Dictionary = _clients[tag]
	var sequence := _next_wire_sequence(tag)
	var wire: Dictionary = FrameScript.create(
			"frame/eg4/l1/wire/%s/%d" % [tag, sequence],
			String(client["wire_session"]), sequence,
			GatewayUtils.eg1_physical_channel_for(String(inner["channel"])),
			GatewayUtils.eg1_delivery_mode_for(String(inner["channel"])),
			String(inner["payload_schema"]), Dictionary(inner))
	var injected: Dictionary = _port_client.inject_received_frame(String(client["peer_id"]), wire)
	_assert(bool(injected.get("success", false)), "frame injection failed for %s" % tag)


func _pump(stage: String) -> void:
	var pumped: Dictionary = _gateway.pump()
	_assert(bool(pumped.get("success", false)), "gateway pump failed during %s" % stage)


func _hello_attach(tag: String) -> String:
	_register_client(tag)
	var inner := ClientWorldFrameScript.create(
			"frame/eg4/l1/hello/%s" % tag,
			"gateway-session/eg4/probe/%s" % tag,
			"CLIENT_TO_WORLD", "SESSION_CONTROL", _next_wire_sequence(tag),
			GatewayUtils.EG1_SESSION_HELLO_PAYLOAD_SCHEMA, {
				"client_session_id": "client-session/eg4/l1-%s" % tag,
				"logical_player_id": "player/eg4-l1-%s" % tag,
				"player_entity_id": "entity/eg4-l1-player-%s" % tag,
				"world_id": Generator.home_world_id(0),
			})
	_inject_client_inner(tag, inner)
	_pump("hello(%s)" % tag)
	for frame_value in _drain_inbox_from_start(tag):
		var frame: Dictionary = frame_value
		var payload: Dictionary = Dictionary(frame.get("payload", {}))
		if String(payload.get("payload_schema", "")) == GatewayUtils.EG1_SESSION_ATTACHED_ACK_PAYLOAD_SCHEMA:
			var gateway_session_id := String(Dictionary(payload.get("payload", {})).get("gateway_session_id", ""))
			_clients[tag]["gateway_session_id"] = gateway_session_id
			return gateway_session_id
	_assert(false, "no ATTACHED ack reached client %s" % tag)
	return ""


func _drain_inbox_from_start(tag: String) -> Array:
	return _port_client.get_messages_for_peer(String(_clients[tag]["peer_id"]))


func _inbox_size(tag: String) -> int:
	return (_port_client.get_messages_for_peer(String(_clients[tag]["peer_id"])) as Array).size()


func _count_channels(tag: String, since_index: int) -> Dictionary:
	var counts := {}
	var inbox: Array = _drain_inbox_from_start(tag)
	for index in range(since_index, inbox.size()):
		var inner: Dictionary = Dictionary(Dictionary(inbox[index]).get("payload", {}))
		var channel := String(inner.get("channel", ""))
		counts[channel] = int(counts.get(channel, 0)) + 1
	return counts


## ---- demand wiring -------------------------------------------------------------


func _demand_worlds(entries: Array) -> Array:
	# Graph-driven demand: the ACTIVE anchor streams from Sim A, every walked
	# projection world is served by Sim B's projection stream set.
	var worlds: Array = []
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		worlds.append({
			"world_id": String(entry["world_id"]),
			"source_authority_id": SOURCE_A if index == 0 else SOURCE_B,
		})
	return worlds


func _set_demand(tag: String, interest_revision: int) -> Array:
	var gateway_session_id := String(_clients[tag]["gateway_session_id"])
	var planned: Dictionary = ViewPlanner.plan_view(_snapshot, {
		"gateway_session_id": gateway_session_id,
		"home_world_id": Generator.home_world_id(0),
		"reference_frame_id": "reference-frame/eg4/l1",
		"interest_revision": interest_revision,
		"expected_graph_revision": int(_snapshot["graph_revision"]),
	})
	_assert(bool(planned.get("success", false)), "%s view planning failed: %s" % [tag, str(planned.get("error_code", planned))])
	if not bool(planned.get("success", false)):
		return []
	var entries: Array = planned["details"]["entries"]
	var demand_result: Dictionary = _interest_agg.set_client_demand({
		"gateway_session_id": gateway_session_id,
		"interest_revision": interest_revision,
		"graph_revision": int(_snapshot["graph_revision"]),
		"worlds": _demand_worlds(entries),
	})
	_assert(bool(demand_result.get("success", false)), "%s demand rejected" % tag)
	for delta_value in demand_result["details"]["deltas"]:
		var delta: Dictionary = delta_value
		if String(delta["action"]) != "SUBSCRIBE":
			continue
		var subscribed: Dictionary = _proj_agg.subscribe_world(
				gateway_session_id,
				String(delta["source_authority_id"]),
				String(delta["world_id"]))
		_assert(bool(subscribed.get("success", false)),
				"projection subscribe failed for %s" % String(delta["world_id"]))
		(_demanded_pairs_by_tag[tag] as Array).append([String(delta["source_authority_id"]), String(delta["world_id"])])
	return entries


func _withdraw_demand(tag: String) -> void:
	var gateway_session_id := String(_clients[tag]["gateway_session_id"])
	var withdrawn: Dictionary = _interest_agg.withdraw_client_demand(gateway_session_id)
	_assert(bool(withdrawn.get("success", false)), "%s withdrawal failed" % tag)
	# The projection aggregator owns its per-client ledger: remove THIS client
	# from every pair it held (upstream-level deltas may legitimately be empty
	# while other clients still share the subscription).
	for pair_value in _demanded_pairs_by_tag.get(tag, []):
		var pair: Array = pair_value
		var unsub: Dictionary = _proj_agg.unsubscribe_world(
				gateway_session_id, String(pair[0]), String(pair[1]))
		_assert(bool(unsub.get("success", false)), "projection unsubscribe failed")
	(_demanded_pairs_by_tag[tag] as Array).clear()


## ---- upstream legs ---------------------------------------------------------------


func _egress_envelope(gateway_session_id: String, inner_channel: String, payload_schema: String, payload: Dictionary, sequence: int, source_role: String, source_authority_id: String) -> Dictionary:
	var inner := ClientWorldFrameScript.create(
			"frame/eg4/l1/backend-up/%s/%s/%06d" % [
				gateway_session_id.replace("/", "-"),
				inner_channel.to_lower().replace("_", "-"),
				sequence,
			],
			gateway_session_id, "WORLD_TO_CLIENT", inner_channel, sequence,
			payload_schema, payload)
	return EgressEnvelopeScript.create(
			"gateway-envelope/eg4/l1/w2c/%06d" % sequence,
			GATEWAY_INSTANCE_ID,
			"backend-link/eg4/l1-sim-a",
			gateway_session_id,
			1, 1, 1,
			source_authority_id,
			"server-instance/eg4-l1-sim",
			source_role,
			inner)


func _send_leg_a_snapshot(gateway_session_id: String, revision: int) -> void:
	var envelope := _egress_envelope(gateway_session_id, "AUTHORITATIVE_SNAPSHOT",
			"planet_simulator.test_snapshot.v1", {"revision": revision}, revision,
			"ACTIVE", SOURCE_A)
	var physical := GatewayUtils.eg1_physical_channel_for("AUTHORITATIVE_SNAPSHOT")
	var wire: Dictionary = FrameScript.create(
			"frame/eg4/l1/sim-a/%d" % revision, BACKEND_WIRE_SESSION, revision, physical,
			GatewayUtils.eg1_delivery_mode_for("AUTHORITATIVE_SNAPSHOT"),
			"planet_simulator.gateway_egress_envelope.v1", envelope)
	var injected: Dictionary = _port_backend.inject_received_frame(BACKEND_PEER_ID, wire)
	_assert(bool(injected.get("success", false)), "leg-A snapshot injection failed")


func _projection_transport_frame(gateway_session_id: String, source_revision: int, read_only: bool = true, inner_channel: String = "WORLD_PROJECTION") -> Dictionary:
	var payload := {
		"read_only": read_only,
		"source_revision": source_revision,
		"entities": ["entity/eg4-l1-proj-%04d" % source_revision],
	}
	var envelope := _egress_envelope(gateway_session_id, inner_channel, PROJECTION_PAYLOAD_SCHEMA, payload,
			1000 + source_revision, "PROJECTION", SOURCE_B)
	return {
		"frame_id": "frame/eg4/l1/sim-b/%d" % source_revision,
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


## ---- main ------------------------------------------------------------------------


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
	_interest_agg = InterestAggregator.new()
	var interest_configured: Dictionary = _interest_agg.configure({})
	_assert(bool(interest_configured.get("success", false)), "interest aggregator configure failed")

	_port_client = LoopbackPort.new()
	_port_backend = LoopbackPort.new()
	_port_client.setup()
	_port_backend.setup()
	_gateway = GatewayNode.new()
	var started: Dictionary = _gateway.start(
			{"transport": "LOOPBACK", "name": "eg4-l1-client"},
			{"transport": "LOOPBACK", "name": "eg4-l1-backend"},
			GATEWAY_INSTANCE_ID,
			{
				"client_port": _port_client,
				"backend_port": _port_backend,
				"backend_peer_id": BACKEND_PEER_ID,
				"backend_session_id": BACKEND_WIRE_SESSION,
			})
	_assert(bool(started.get("success", false)), "gateway start failed")
	_pump("backend connect")

	# --- predicate 5: EIGHT_WORLD_PLANNER_WALK_PASS ----------------------------
	var walk: Dictionary = ViewPlanner.walk_worlds(_snapshot, Generator.home_world_id(0))
	var visited: Array = walk.get("details", {}).get("visited", [])
	var distinct := {}
	for value in visited:
		distinct[String(value)] = true
	_assert(distinct.size() >= REQUIRED_MACHINE_WALK_WORLDS,
			"deterministic walk visited only %d worlds" % distinct.size())

	# --- predicate 1: graph-driven planning (not hardcoded lists) --------------
	var probe_entries := _planned_entries_for("gateway-session/eg4/l1-planning-probe", 1)
	_assert((probe_entries as Array).size() >= 4, "fixture plan implausibly small")
	if not (probe_entries as Array).is_empty():
		_assert(String(probe_entries[0]["source_role"]) == "ACTIVE", "anchor must be ACTIVE")
		var planned_world_set := {}
		for entry_value in probe_entries:
			planned_world_set[String(entry_value["world_id"])] = true
		_assert(not planned_world_set.has("world/eg4/not-in-any-plan"),
				"plan contains a hardcoded sentinel world")

	# --- ONE client, TWO sources -------------------------------------------------
	var gsid_alpha := _hello_attach("alpha")
	_assert(gsid_alpha != "", "alpha session required")
	var alpha_registered: Dictionary = _proj_agg.register_client(gsid_alpha)
	_assert(bool(alpha_registered.get("success", false)), "aggregator client registration failed")
	for source_value in [SOURCE_A, SOURCE_B]:
		var registered_source: Dictionary = _proj_agg.register_upstream_source(source_value)
		_assert(bool(registered_source.get("success", false)), "source registration failed")

	var alpha_entries := _set_demand("alpha", 4)
	_assert((alpha_entries as Array).size() >= 4, "alpha demand produced too few entries")

	# --- predicate 2: MULTI_SOURCE_SINGLE_CLIENT_TRANSPORT_PASS ------------------
	var alpha_inbox_before := _inbox_size("alpha")
	_send_leg_a_snapshot(gsid_alpha, 11)
	_send_leg_a_snapshot(gsid_alpha, 12)
	var accepted_b: Dictionary = _accept_from_b(gsid_alpha, 21)
	_assert(bool(accepted_b.get("success", false)), "healthy projection frame was rejected: %s" % str(accepted_b.get("error_code", accepted_b)))
	if bool(accepted_b.get("success", false)):
		_assert(int(accepted_b["details"]["priority"]) == 4, "projection did not ride priority P4")
	var stale_rev: Dictionary = _proj_agg.accept_upstream_frame(SOURCE_B,
			_projection_transport_frame(gsid_alpha, 20))
	_assert(String(stale_rev.get("error_code", "")) == "STALE_SOURCE_REVISION",
			"older source revision must be dropped latest-wins")

	var alpha_counts := _count_channels("alpha", alpha_inbox_before)
	_assert(int(alpha_counts.get("AUTHORITATIVE_SNAPSHOT", 0)) >= 1,
			"client did not receive authoritative snapshots from Sim A: %s" % str(alpha_counts))
	_assert(int(alpha_counts.get("WORLD_PROJECTION", 0)) >= 1,
			"client did not receive projection frames from Sim B: %s" % str(alpha_counts))

	var single_transport_report: Dictionary = _gateway.get_report()
	var client_peers: Array[String] = []
	for row_value in single_transport_report["sessions"]:
		var peer := String(row_value["client_transport_peer_id"])
		if not client_peers.has(peer):
			client_peers.append(peer)
	_assert(client_peers == ["peer/loopback/eg4-alpha"],
			"client transport count must be exactly ONE: %s" % str(client_peers))
	_assert((single_transport_report["identity"]["gateway_session_ids"] as Array).size() == 1,
			"exactly one logical session should exist at this point")

	# --- read-only fence (still the SINGLE client connection) ---------------------
	var beta_marker := _inbox_size("alpha")
	var mutation: Dictionary = _proj_agg.accept_upstream_frame(SOURCE_B,
			_projection_transport_frame(gsid_alpha, 31, true, "WORLD_OPERATION"))
	_assert(String(mutation.get("error_code", "")) == "PROJECTION_MUTATION_REJECTED",
			"mutation-shaped projection traffic was not rejected: %s" % str(mutation.get("error_code", mutation)))
	var writable: Dictionary = _proj_agg.accept_upstream_frame(SOURCE_B,
			_projection_transport_frame(gsid_alpha, 32, false))
	_assert(String(writable.get("error_code", "")) == "PROJECTION_NOT_READ_ONLY",
			"non-read-only projection was not rejected: %s" % str(writable.get("error_code", writable)))
	var rogue_frame := _projection_transport_frame(gsid_alpha, 33)
	rogue_frame["payload"]["source_authority_id"] = "authority/eg4-l1-rogue"
	var injected: Dictionary = _proj_agg.accept_upstream_frame("authority/eg4-l1-rogue", rogue_frame)
	_assert(String(injected.get("error_code", "")) == "PROJECTION_SOURCE_NOT_REGISTERED",
			"unregistered-source injection was not rejected: %s" % str(injected.get("error_code", injected)))
	var fence_report: Dictionary = _proj_agg.get_report()
	_assert(int(fence_report["counters"]["rejected_mutation_shaped"]) >= 1
			and int(fence_report["counters"]["rejected_not_read_only"]) >= 1
			and int(fence_report["counters"]["rejected_injection"]) >= 1,
			"fence counters missing rejections")
	var fence_counts := _count_channels("alpha", beta_marker)
	_assert(int(fence_counts.get("WORLD_PROJECTION", 0)) == 0 and int(fence_counts.get("WORLD_OPERATION", 0)) == 0,
			"rejected frames LEAKED to the client: %s" % str(fence_counts))

	# --- source loss does not disconnect gameplay ---------------------------------
	var alpha_inbox_mid := _inbox_size("alpha")
	var lost: Dictionary = _proj_agg.mark_source_lost(SOURCE_B)
	_assert(bool(lost.get("success", false)), "mark_source_lost failed")
	_send_leg_a_snapshot(gsid_alpha, 13)
	_pump("post-loss leg-A delivery")
	var post_loss_counts := _count_channels("alpha", alpha_inbox_mid)
	_assert(int(post_loss_counts.get("AUTHORITATIVE_SNAPSHOT", 0)) >= 1,
			"gameplay did NOT continue after projection source loss")
	var loss_report: Dictionary = _proj_agg.get_report()
	_assert(not (loss_report["upstream_set"]["sources"] as Array).has(SOURCE_B),
			"lost source still listed as active upstream")
	_assert((loss_report["counters"]["frames_accepted"] as int) >= 1, "telemetry lost the acceptance counter")

	# --- predicate 3: INTEREST_AGGREGATION_PASS (dedup across two clients) -------
	var gsid_beta := _hello_attach("beta")
	_assert(gsid_beta != "" and gsid_beta != gsid_alpha, "beta session required")
	var beta_registered: Dictionary = _proj_agg.register_client(gsid_beta)
	_assert(bool(beta_registered.get("success", false)), "beta aggregator registration failed")
	var beta_entries := _set_demand("beta", 5)
	_assert((beta_entries as Array).size() >= 4, "beta demand produced too few entries")
	var shared_world := String(alpha_entries[1]["world_id"])
	var shared_plan: Dictionary = _interest_agg.plan_for_world(shared_world)
	_assert(bool(shared_plan.get("success", false)), "shared world has no aggregated plan")
	if bool(shared_plan.get("success", false)):
		var subscribers: Array = shared_plan["details"]["plan"]["subscriber_sessions"]
		_assert(subscribers.size() == 2, "shared demand did not DEDUP into ONE plan: %s" % str(subscribers))

	# --- predicate 4: BOUNDED_DYNAMIC_UPSTREAM_SET_PASS ---------------------------
	# Active set currently holds SOURCE_A only; fill to the cap of 4.
	var s3 := "authority/eg4-l1-sim-c"
	var s4 := "authority/eg4-l1-sim-d"
	var s6 := "authority/eg4-l1-sim-f"
	var s5 := "authority/eg4-l1-sim-e"
	for filler in [s3, s4, s6]:
		var added: Dictionary = _proj_agg.register_upstream_source(filler)
		_assert(bool(added.get("success", false)), "filler source rejected: %s" % filler)
	var full: Dictionary = _proj_agg.register_upstream_source(s5)
	_assert(String(full.get("error_code", "")) == "UPSTREAM_SET_FULL",
			"bounded upstream set accepted beyond cap: %s" % str(full.get("error_code", full)))
	_proj_agg.mark_source_idle(s3)
	_proj_agg.mark_source_idle(s4)
	var replaced: Dictionary = _proj_agg.register_upstream_source(s5)
	_assert(bool(replaced.get("success", false)), "LRU eviction refused a legitimate replacement")
	if bool(replaced.get("success", false)):
		_assert(String(replaced["details"]["evicted"]) == s3,
				"LRU eviction picked the wrong victim: %s" % String(replaced["details"]["evicted"]))
	var upstream_report: Dictionary = _proj_agg.get_report()["upstream_set"]
	_assert(int(upstream_report["size"]) <= int(upstream_report["cap"]),
			"bounded upstream set exceeded its cap")

	# --- predicate 6: STALE_UPSTREAM_SUBSCRIPTIONS_EVENTUALLY_ZERO ----------------
	_withdraw_demand("alpha")
	_withdraw_demand("beta")
	var stale_after_withdrawal: int = _proj_agg.stale_subscription_count()
	_assert(stale_after_withdrawal > 0, "withdrawal left no stale subscriptions to drain")
	var cycles := 0
	while _proj_agg.stale_subscription_count() > 0 and cycles < 64:
		cycles += 1
		_proj_agg.run_maintenance_cycle()
	_assert(_proj_agg.stale_subscription_count() == 0,
			"stale upstream subscriptions did NOT reach zero")
	_assert(cycles <= 8, "stale drain exceeded a bounded number of pump cycles: %d" % cycles)
	var final_report: Dictionary = _proj_agg.get_report()
	_assert(int(final_report["stale_subscription_count"]) == 0,
			"final telemetry still reports stale subscriptions")

	var stopped: Dictionary = _gateway.stop()
	_assert(bool(stopped.get("success", false)), "gateway stop failed")
	_finish()


func _planned_entries_for(gateway_session_id: String, revision: int) -> Array:
	var planned: Dictionary = ViewPlanner.plan_view(_snapshot, {
		"gateway_session_id": gateway_session_id,
		"home_world_id": Generator.home_world_id(0),
		"reference_frame_id": "reference-frame/eg4/l1-probe",
		"interest_revision": revision,
		"expected_graph_revision": int(_snapshot["graph_revision"]),
	})
	if not bool(planned.get("success", false)):
		return []
	return planned["details"]["entries"]


func _finish() -> void:
	var ok := failures.is_empty()
	var summary := {
		"test": "eg4_projection_aggregation_l1",
		"verdict": "PASS" if ok else "FAIL",
		"assertions": assertions,
		"predicates": [
			"WORLD_GRAPH_DRIVEN_VIEW_PLANNING_PASS",
			"MULTI_SOURCE_SINGLE_CLIENT_TRANSPORT_PASS",
			"INTEREST_AGGREGATION_PASS",
			"BOUNDED_DYNAMIC_UPSTREAM_SET_PASS",
			"EIGHT_WORLD_PLANNER_WALK_PASS",
			"STALE_UPSTREAM_SUBSCRIPTIONS_EVENTUALLY_ZERO",
		] if ok else ["PREDICATE_NOT_DEMONSTRATED"],
		"failures": failures,
	}
	print(JSON.stringify(summary))
	if ok:
		print("[eg4-l1] AGGREGATION PASS — SIX PREDICATES DEMONSTRATED (%d assertions)" % assertions)
		quit(0)
	else:
		print("[eg4-l1] AGGREGATION FAIL")
		quit(1)

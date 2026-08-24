extends SceneTree

## EG4 review R2 regression proof: projection state never outlives its session.
##
## Part 1 (review R2-A): repeated register→subscribe→accept→release churn
## WITHOUT any withdraw must leave NO residue — subscription pairs drain to
## zero through the bounded stale-retirement path, fan-in slots are released,
## and the per-(session, source) latest-wins revision map returns to empty.
##
## Part 2 (review R2-B): dropping the client transport peer (or an explicit
## DETACH) inside the REAL eg1_gateway_node releases the session's projection
## state through the installed lifecycle hook — subscriptions turn stale and
## drain to zero, the egress hook fails closed for the dead session, and the
## release is idempotent across repeated pumps.

const GatewayNode = preload("res://scripts/network/gateway/runtime/eg1_gateway_node.gd")
const ProjectionAggregator = preload("res://scripts/network/gateway/runtime/eg4_projection_aggregator.gd")
const LoopbackPort = preload("res://scripts/network/transports/v2/loopback_multi_peer_transport_port.gd")
const FrameScript = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")
const ClientWorldFrameScript = preload("res://scripts/network/gateway/client_world_frame.gd")
const EgressEnvelopeScript = preload("res://scripts/network/gateway/gateway_egress_envelope.gd")
const GatewayUtils = preload("res://scripts/network/gateway/gateway_contract_utils.gd")
const Generator = preload("res://tools/network/eg4_world_fixture_generator.gd")

const GATEWAY_INSTANCE_ID := "gateway/eg4/l1-lifecycle"
const BACKEND_PEER_ID := "peer/loopback/eg4-lifecycle-sim-b"
const BACKEND_WIRE_SESSION := "transport-session/eg4/lifecycle-backend-b"
const CLIENT_PEER_ID := "peer/loopback/eg4-lifecycle-client"
const CLIENT_WIRE_SESSION := "transport-session/eg4/lifecycle-client"
const SOURCE_B := "authority/eg4-lifecycle-sim-b"
const CHURN_CYCLES := 32
const PROJECTION_PAYLOAD_SCHEMA := "planet_simulator.test_world_projection.v1"

var assertions := 0
var failures: Array[String] = []
var _started_ms: int = 0


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[eg4-lifecycle][FAIL] %s" % message)


func _process(_delta: float) -> bool:
	if _started_ms > 0 and Time.get_ticks_msec() - _started_ms > 120000:
		print("[eg4-lifecycle] WATCHDOG TIMEOUT")
		quit(1)
		return true
	return false


## ---- shared frame builders -------------------------------------------------------


func _projection_transport_frame(gateway_session_id: String, source_revision: int) -> Dictionary:
	var inner := ClientWorldFrameScript.create(
			"frame/eg4/lifecycle/backend-up/%06d" % source_revision,
			gateway_session_id, "WORLD_TO_CLIENT", "WORLD_PROJECTION", source_revision,
			PROJECTION_PAYLOAD_SCHEMA, {
				"read_only": true,
				"source_revision": source_revision,
				"entities": ["entity/eg4-lifecycle-proj-%04d" % source_revision],
			})
	var envelope := EgressEnvelopeScript.create(
			"gateway-envelope/eg4/lifecycle/w2c/%06d" % source_revision,
			GATEWAY_INSTANCE_ID,
			"backend-link/eg4/lifecycle-sim-b",
			gateway_session_id,
			1, 1, 1,
			SOURCE_B,
			"server-instance/eg4-lifecycle-sim-b",
			"PROJECTION",
			inner)
	return {
		"frame_id": "frame/eg4/lifecycle/sim-b/%d" % source_revision,
		"session_id": BACKEND_WIRE_SESSION,
		"sequence": 1000 + source_revision,
		"channel": GatewayUtils.eg1_physical_channel_for("WORLD_PROJECTION"),
		"delivery_mode": GatewayUtils.eg1_delivery_mode_for("WORLD_PROJECTION"),
		"payload_schema": "planet_simulator.gateway_egress_envelope.v1",
		"payload": envelope,
	}


## ---- part 1: pure aggregator churn (review R2-A) -----------------------------------


func _run_churn_part() -> void:
	var aggregator = ProjectionAggregator.new()
	var configured: Dictionary = aggregator.configure({
		"max_upstream_sources": 4,
		"retire_batch_per_cycle": 4,
		"send_to_client": func(_gateway_session_id: String, _frame_spec: Dictionary) -> Dictionary:
			return {"success": true},
	})
	_assert(bool(configured.get("success", false)), "churn aggregator configure failed")
	var registered_source: Dictionary = aggregator.register_upstream_source(SOURCE_B)
	_assert(bool(registered_source.get("success", false)), "churn source registration failed")

	for cycle in range(CHURN_CYCLES):
		var gateway_session_id := "gateway-session/eg4/churn/%04d" % cycle
		var registered: Dictionary = aggregator.register_client(gateway_session_id)
		if not bool(registered.get("success", false)):
			_assert(false, "churn cycle %d: register_client failed" % cycle)
			break
		var world_id := Generator.world_id_at(cycle % 6)
		var subscribed: Dictionary = aggregator.subscribe_world(gateway_session_id, SOURCE_B, world_id)
		if not bool(subscribed.get("success", false)):
			_assert(false, "churn cycle %d: subscribe_world failed" % cycle)
			break
		var accepted: Dictionary = aggregator.accept_upstream_frame(
				SOURCE_B, _projection_transport_frame(gateway_session_id, cycle + 1))
		if not bool(accepted.get("success", false)):
			_assert(false, "churn cycle %d: accept failed: %s" % [cycle, str(accepted.get("error_code", accepted))])
			break
		var pumped: Dictionary = aggregator.pump(8)
		if not bool(pumped.get("success", false)):
			_assert(false, "churn cycle %d: pump failed" % cycle)
			break
		# Disconnect churn: NO withdraw call — release must clean everything.
		var released: Dictionary = aggregator.release_client(gateway_session_id)
		if not bool(released.get("success", false)):
			_assert(false, "churn cycle %d: release_client failed" % cycle)
			break
		var report: Dictionary = aggregator.get_report()
		if (report["clients"] as Array).size() > 0 or int(report["fan_in_streams"]) > 0:
			_assert(false, "churn cycle %d: residue after release: clients=%s fan_in=%d" % [
				cycle, str(report["clients"]), int(report["fan_in_streams"])])
			break

	var mid_report: Dictionary = aggregator.get_report()
	_assert((mid_report["clients"] as Array).is_empty(), "churn left registered clients behind")
	_assert(int(mid_report["fan_in_streams"]) == 0, "churn left fan-in slots behind")
	_assert(Dictionary(mid_report["last_source_revisions"]).is_empty(),
			"churn left latest-wins stream revisions behind: %s" % str(mid_report["last_source_revisions"]))
	_assert(int(mid_report["active_subscriptions"]) == 0, "churn left ACTIVE subscriptions behind")

	# Released pairs retired through the BOUNDED stale path, not silently.
	var cycles_run := 0
	while int(mid_report["stale_subscription_count"]) > 0 and cycles_run < 64:
		cycles_run += 1
		aggregator.run_maintenance_cycle()
		mid_report = aggregator.get_report()
	_assert(int(mid_report["stale_subscription_count"]) == 0,
			"churn stale subscriptions did not drain to zero")
	_assert(cycles_run <= 8, "churn stale drain exceeded bounded cycles: %d" % cycles_run)
	var final_report: Dictionary = aggregator.get_report()
	_assert(int(final_report["counters"]["stale_retired"]) >= 1,
			"telemetry lost the stale-retired counter")


## ---- part 2: gateway-driven lifecycle on session drop (review R2-B) -----------------


func _run_gateway_drop_part() -> void:
	var aggregator = ProjectionAggregator.new()
	var _configured: Dictionary = aggregator.configure({
		"max_upstream_sources": 4,
		"retire_batch_per_cycle": 4,
		"send_to_client": func(gateway_session_id: String, frame_spec: Dictionary) -> Dictionary:
			return _gateway.send_client_frame_spec_for_session(gateway_session_id, frame_spec),
	})
	var port_client: LoopbackPort = LoopbackPort.new()
	var port_backend: LoopbackPort = LoopbackPort.new()
	port_client.setup()
	port_backend.setup()
	_gateway = GatewayNode.new()
	var started: Dictionary = _gateway.start(
			{"transport": "LOOPBACK", "name": "eg4-lifecycle-client"},
			{"transport": "LOOPBACK", "name": "eg4-lifecycle-backend"},
			GATEWAY_INSTANCE_ID,
			{
				"client_port": port_client,
				"backend_port": port_backend,
				"backend_peer_id": BACKEND_PEER_ID,
				"backend_session_id": BACKEND_WIRE_SESSION,
			})
	_assert(bool(started.get("success", false)), "gateway start failed")
	var hooked: Dictionary = _gateway.set_projection_lifecycle_handler(aggregator)
	_assert(bool(hooked.get("success", false)), "projection lifecycle hook rejected")
	var bad_hook: Dictionary = _gateway.set_projection_lifecycle_handler(self)
	_assert(String(bad_hook.get("error_code", "")) == "INVALID_PROJECTION_LIFECYCLE_HANDLER",
			"invalid lifecycle handler must be rejected")
	var _re_hooked: Dictionary = _gateway.set_projection_lifecycle_handler(aggregator)
	_pump("backend connect")

	var registered_source: Dictionary = aggregator.register_upstream_source(SOURCE_B)
	_assert(bool(registered_source.get("success", false)), "gateway-part source registration failed")

	var attached: Dictionary = port_client.attach_peer(
			CLIENT_PEER_ID, CLIENT_WIRE_SESSION, "route/eg4/lifecycle", 1)
	_assert(bool(attached.get("success", false)), "loopback attach failed")
	var hello := ClientWorldFrameScript.create(
			"frame/eg4/lifecycle/hello",
			"gateway-session/eg4/lifecycle/probe",
			"CLIENT_TO_WORLD", "SESSION_CONTROL", 1,
			GatewayUtils.EG1_SESSION_HELLO_PAYLOAD_SCHEMA, {
				"client_session_id": "client-session/eg4/lifecycle",
				"logical_player_id": "player/eg4-lifecycle",
				"player_entity_id": "entity/eg4-lifecycle-player",
				"world_id": Generator.home_world_id(0),
			})
	var wire: Dictionary = FrameScript.create(
			"frame/eg4/lifecycle/client-up/1", CLIENT_WIRE_SESSION, 1,
			GatewayUtils.eg1_physical_channel_for("SESSION_CONTROL"),
			GatewayUtils.eg1_delivery_mode_for("SESSION_CONTROL"),
			String(hello["payload_schema"]), hello)
	var injected: Dictionary = port_client.inject_received_frame(CLIENT_PEER_ID, wire)
	_assert(bool(injected.get("success", false)), "hello injection failed")
	_pump("hello attach")
	var gateway_session_id := ""
	for frame_value in port_client.get_messages_for_peer(CLIENT_PEER_ID):
		var payload: Dictionary = Dictionary(Dictionary(frame_value).get("payload", {}))
		if String(payload.get("payload_schema", "")) == GatewayUtils.EG1_SESSION_ATTACHED_ACK_PAYLOAD_SCHEMA:
			gateway_session_id = String(Dictionary(payload.get("payload", {})).get("gateway_session_id", ""))
			break
	_assert(gateway_session_id != "", "no ATTACHED ack reached the client")
	var registered_client: Dictionary = aggregator.register_client(gateway_session_id)
	_assert(bool(registered_client.get("success", false)), "aggregator client registration failed")

	var subscribed: Dictionary = aggregator.subscribe_world(
			gateway_session_id, SOURCE_B, Generator.world_id_at(0))
	_assert(bool(subscribed.get("success", false)), "subscribe failed")
	var accepted: Dictionary = aggregator.accept_upstream_frame(
			SOURCE_B, _projection_transport_frame(gateway_session_id, 5))
	_assert(bool(accepted.get("success", false)), "projection accept failed")
	var pumped: Dictionary = aggregator.pump(8)
	_assert(bool(pumped.get("success", false)), "aggregator pump failed")
	_pump("deliver projection")

	var before_drop: Dictionary = aggregator.get_report()
	_assert((before_drop["clients"] as Array).has(gateway_session_id),
			"client missing from aggregator before drop")
	_assert(int(before_drop["active_subscriptions"]) >= 1, "subscription missing before drop")
	_assert(int(before_drop["fan_in_streams"]) >= 1, "fan-in slot missing before drop")

	# --- THE DROP: client transport peer disconnects, gateway pumps -------------
	var disconnected: Dictionary = port_client.disconnect_peer(CLIENT_PEER_ID, CLIENT_WIRE_SESSION)
	_assert(bool(disconnected.get("success", false)), "peer disconnect failed")
	_pump("process peer drop")
	_pump("idempotency pump")

	var gateway_report: Dictionary = _gateway.get_report()
	_assert(int(gateway_report["counters"]["projection_session_releases"]) == 1,
			"gateway did not release the session exactly once: %d" % int(gateway_report["counters"]["projection_session_releases"]))
	var rows: Array = gateway_report["sessions"]
	for row_value in rows:
		var row: Dictionary = row_value
		if String(row.get("gateway_session_id", "")) == gateway_session_id:
			_assert(String(row.get("binding_state", "")) == "DETACHED",
					"dropped session binding is not DETACHED")

	var after_drop: Dictionary = aggregator.get_report()
	_assert(not (after_drop["clients"] as Array).has(gateway_session_id),
			"dropped session still registered in the aggregator")
	_assert(int(after_drop["fan_in_streams"]) == 0, "dropped session left a fan-in slot behind")
	_assert(Dictionary(after_drop["last_source_revisions"]).is_empty(),
			"dropped session left stream revisions behind")
	_assert(int(after_drop["active_subscriptions"]) == 0, "dropped session left an ACTIVE subscription")
	_assert(int(after_drop["stale_subscription_count"]) >= 1,
			"dropped session subscription did not turn stale for bounded retirement")
	var drain_cycles := 0
	while int(after_drop["stale_subscription_count"]) > 0 and drain_cycles < 64:
		drain_cycles += 1
		aggregator.run_maintenance_cycle()
		after_drop = aggregator.get_report()
	_assert(int(after_drop["stale_subscription_count"]) == 0,
			"dropped session subscriptions did not drain to zero")

	# Egress hook must fail closed for the dead session; lifecycle stays idempotent.
	var dead_egress: Dictionary = _gateway.send_client_frame_spec_for_session(
			gateway_session_id, {"frame_id": "frame/eg4/lifecycle/dead", "channel": "WORLD_PROJECTION"})
	_assert(String(dead_egress.get("error_code", "")) == "GATEWAY_SESSION_DETACHED",
			"egress hook accepted a frame for a DETACHED session: %s" % str(dead_egress.get("error_code", dead_egress)))
	var repeat_drop: Dictionary = aggregator.on_gateway_session_detached(gateway_session_id)
	_assert(bool(repeat_drop.get("success", false)), "repeat lifecycle release must be a successful no-op")

	var stopped: Dictionary = _gateway.stop()
	_assert(bool(stopped.get("success", false)), "gateway stop failed")


var _gateway


func _pump(stage: String) -> void:
	var pumped: Dictionary = _gateway.pump()
	_assert(bool(pumped.get("success", false)), "gateway pump failed during %s" % stage)


func _init() -> void:
	_started_ms = Time.get_ticks_msec()
	_run_churn_part()
	_run_gateway_drop_part()
	_finish()


func _finish() -> void:
	var ok := failures.is_empty()
	var summary := {
		"test": "eg4_projection_lifecycle_l1",
		"verdict": "PASS" if ok else "FAIL",
		"assertions": assertions,
		"predicates": [
			"PROJECTION_SESSION_LIFECYCLE_PASS",
		] if ok else ["PREDICATE_NOT_DEMONSTRATED"],
		"failures": failures,
	}
	print(JSON.stringify(summary))
	if ok:
		print("[eg4-lifecycle] PROJECTION SESSION LIFECYCLE PASS (%d assertions)" % assertions)
		quit(0)
	else:
		print("[eg4-lifecycle] PROJECTION SESSION LIFECYCLE FAIL")
		quit(1)

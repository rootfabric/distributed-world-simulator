extends SceneTree

## EG4 gateway worker: ONE gateway process, ONE client-facing transport, and a
## BOUNDED dynamic set of upstream legs:
##   - leg A: Sim A (ACTIVE authority) through the REAL EG1 gateway node with
##     EG2 auth/directory/placement and the EG3 shared backend multiplexer;
##   - leg B: Sim B (PROJECTION source) owned by the EG4 projection aggregator,
##     whose fan-in remuxes read-only WORLD_PROJECTION frames into each
##     client's SINGLE client-facing transport via P4 scheduling.
##
## Client-driven demand: SESSION_CONTROL frames with payload_schema
## planet_simulator.eg4_projection_demand.v1 are intercepted by an additive
## placement-handler wrapper (EG1 session control reports UNSUPPORTED for
## them; every other schema DELEGATES to the real EG2 placement flow). The
## demanded worlds are resolved against the COMMITTED world-graph fixture via
## the EG4 view planner (graph-driven, never hardcoded), folded into the
## interest aggregator, and pushed to Sim B as subscribe/withdraw operations.
##
## Source liveness: a SUBSCRIBED projection source silent longer than
## --source-loss-timeout-ms is marked LOST (killed UDP peers stay protocol-
## silent); its demands are withdrawn and bounded maintenance cycles drain
## stale upstream subscriptions to zero while gameplay continues over Sim A.

const Support = preload("res://tools/network/eg4_process_support.gd")
const BusUtilsScript = preload("res://scripts/network/bus/message_bus_contract_utils.gd")
const GatewayNodeScript = preload("res://scripts/network/gateway/runtime/eg1_gateway_node.gd")
const AuthServiceScript = preload("res://scripts/network/gateway/runtime/eg2_auth_session_service.gd")
const WorldDirectoryScript = preload("res://scripts/network/gateway/runtime/eg2_world_directory.gd")
const PlacementFlowScript = preload("res://scripts/network/gateway/runtime/eg2_placement_flow.gd")
const BackendMultiplexerScript = preload("res://scripts/network/gateway/runtime/eg3_backend_multiplexer.gd")
const ProjectionAggregatorScript = preload("res://scripts/network/gateway/runtime/eg4_projection_aggregator.gd")
const InterestAggregatorScript = preload("res://scripts/network/gateway/runtime/eg4_interest_aggregator.gd")
const ViewPlannerScript = preload("res://scripts/network/gateway/runtime/eg4_view_planner.gd")
const SnapshotScript = preload("res://scripts/network/gateway/gateway_world_graph_snapshot.gd")
const EgressEnvelopeScript = preload("res://scripts/network/gateway/gateway_egress_envelope.gd")
const IngressEnvelopeScript = preload("res://scripts/network/gateway/gateway_ingress_envelope.gd")
const ClientWorldFrameScript = preload("res://scripts/network/gateway/client_world_frame.gd")
const BoundaryScript = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const EnetPortScript = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
const Generator = preload("res://tools/network/eg4_world_fixture_generator.gd")
const GatewayUtils = preload("res://scripts/network/gateway/gateway_contract_utils.gd")

const OPTION_SPEC := {
	"client-host": {"kind": "string", "default": "127.0.0.1"},
	"client-port": {"kind": "int", "default": 0, "required": true},
	"sim-a-host": {"kind": "string", "default": "127.0.0.1"},
	"sim-a-port": {"kind": "int", "default": 0, "required": true},
	"sim-b-host": {"kind": "string", "default": "127.0.0.1"},
	"sim-b-port": {"kind": "int", "default": 0, "required": true},
	"authority-id-a": {"kind": "string", "default": Support.AUTHORITY_ID_EG4_A},
	"server-instance-id-a": {"kind": "string", "default": Support.SERVER_INSTANCE_EG4_A},
	"authority-id-b": {"kind": "string", "default": Support.AUTHORITY_ID_EG4_B},
	"premint-client-sessions": {"kind": "string", "default": "", "required": true},
	"expected-placements": {"kind": "int", "default": 1},
	"expected-detachments": {"kind": "int", "default": 1},
	"demand-projection-worlds": {"kind": "int", "default": 4},
	"source-loss-timeout-ms": {"kind": "int", "default": Support.SOURCE_LOSS_TIMEOUT_MS},
	"result-file": {"kind": "string", "default": "", "required": true},
	"player-binding-file": {"kind": "string", "default": ""},
	"timeout-ms": {"kind": "int", "default": 120000},
	"user-data-dir": {"kind": "string", "default": ""},
}

var _options: Dictionary = {}
var _node
var _auth_service
var _directory
var _placement
var _multiplexer
var _proj_agg
var _interest_agg
var _snapshot: Dictionary = {}
var _leg_b_boundary
var _leg_b_peer_id := "peer/enet/eg4-gateway-leg-b"
var _leg_b_wire_session := "transport-session/eg4/gateway-leg-b"
var _leg_b_sequence: int = 0
var _leg_b_connected := false
var _demand_worlds: Array[String] = []
# gateway_session_id -> [[source_authority_id, world_id], ...] held pairs
var _pairs_by_session: Dictionary = {}
var _last_source_traffic_ms: Dictionary = {}
var _source_lost_reported := false
var _loss_was_graceful_disconnect := false
var _lost_world_count: int = -1
var _clients_registered: Dictionary = {}
var _published_bindings: Dictionary = {}
var _started_ms: int = 0
var _finished := false
var _completion_at_ms: int = -1


func _initialize() -> void:
	var parsed: Dictionary = Support.parse_options(OS.get_cmdline_user_args(), OPTION_SPEC)
	if not bool(parsed.get("success", false)):
		_finish_failure("INVALID_OPTIONS", {"errors": parsed.get("errors", [])})
		return
	_options = parsed["options"]

	var fixture_text := FileAccess.get_file_as_string("res://tests/network/fixtures/eg4_world_graph_fixture.json")
	var fixture = JSON.parse_string(fixture_text)
	if not (fixture is Dictionary) or not Dictionary(fixture).has("snapshot"):
		_finish_failure("FIXTURE_UNAVAILABLE", {})
		return
	_snapshot = Dictionary(fixture["snapshot"])
	if not bool(SnapshotScript.validate(_snapshot).get("success", false)):
		_finish_failure("FIXTURE_INVALID", {})
		return

	_auth_service = AuthServiceScript.new()
	if not bool(_auth_service.configure({}).get("success", false)):
		_finish_failure("AUTH_CONFIGURE_FAILED", {})
		return
	_directory = WorldDirectoryScript.new()
	var registered: Dictionary = _directory.register_world(
			Support.HOME_WORLD_ID_EG4, String(_options["authority-id-a"]),
			String(_options["server-instance-id-a"]), 1)
	if not bool(registered.get("success", false)):
		_finish_failure("WORLD_REGISTRATION_FAILED", {})
		return
	_placement = PlacementFlowScript.new()
	if not bool(_placement.configure(_auth_service, _directory).get("success", false)):
		_finish_failure("PLACEMENT_CONFIGURE_FAILED", {})
		return
	_multiplexer = BackendMultiplexerScript.new()
	if not bool(_multiplexer.configure({}).get("success", false)):
		_finish_failure("MULTIPLEXER_CONFIGURE_FAILED", {})
		return

	for index in range(int(_options["demand-projection-worlds"])):
		_demand_worlds.append(Support.l2_world_id(index + 1))

	_proj_agg = ProjectionAggregatorScript.new()
	var agg_configured: Dictionary = _proj_agg.configure({
		"max_upstream_sources": 4,
		"retire_batch_per_cycle": 4,
		"send_to_client": func(gateway_session_id: String, frame_spec: Dictionary) -> Dictionary:
			return _node.send_client_frame_spec_for_session(gateway_session_id, frame_spec),
	})
	if not bool(agg_configured.get("success", false)):
		_finish_failure("PROJECTION_AGGREGATOR_CONFIGURE_FAILED", {})
		return
	_interest_agg = InterestAggregatorScript.new()
	if not bool(_interest_agg.configure({}).get("success", false)):
		_finish_failure("INTEREST_AGGREGATOR_CONFIGURE_FAILED", {})
		return

	_node = GatewayNodeScript.new()
	var started: Dictionary = _node.start(
			Support.enet_endpoint(String(_options["client-host"]), int(_options["client-port"])),
			Support.enet_endpoint(String(_options["sim-a-host"]), int(_options["sim-a-port"])),
			"gateway/eg4/l2-worker",
			{
				"client_port": EnetPortScript.new(),
				"backend_port": EnetPortScript.new(),
				"backend_peer_id": "peer/enet/eg4-gateway-backend-a",
				"backend_session_id": "transport-session/eg4/gateway-backend-a",
				"backend_route_id": "route/eg4/gateway-backend-a",
				"backend_link_id": "backend-link/eg4/l2-sim-a",
			})
	if not bool(started.get("success", false)):
		_finish_failure(String(started.get("error_code", "GATEWAY_START_FAILED")), {})
		return
	if not bool(_node.set_placement_handler(self).get("success", false)):
		_finish_failure("PLACEMENT_HANDLER_INSTALL_FAILED", {})
		return
	if not bool(_node.set_backend_multiplexer(_multiplexer).get("success", false)):
		_finish_failure("MULTIPLEXER_INSTALL_FAILED", {})
		return
	# Review R2-B integration at process level: a dropped/detached client
	# session releases its projection state through the aggregator hook.
	if not bool(_node.set_projection_lifecycle_handler(_proj_agg).get("success", false)):
		_finish_failure("PROJECTION_LIFECYCLE_INSTALL_FAILED", {})
		return

	var source_registered: Dictionary = _proj_agg.register_upstream_source(String(_options["authority-id-b"]))
	if not bool(source_registered.get("success", false)):
		_finish_failure("SOURCE_B_REGISTRATION_FAILED", {})
		return
	_last_source_traffic_ms[String(_options["authority-id-b"])] = Time.get_ticks_msec()

	_leg_b_boundary = BoundaryScript.new()
	var leg_configured: Dictionary = _leg_b_boundary.configure(EnetPortScript.new(), 1048576, 512, 4194304)
	if not bool(leg_configured.get("success", false)):
		_finish_failure(String(leg_configured.get("error_code", "LEG_B_CONFIGURE_FAILED")), {})
		return
	var leg_connected: Dictionary = _leg_b_boundary.connect_client(
			Support.enet_endpoint(String(_options["sim-b-host"]), int(_options["sim-b-port"])),
			_leg_b_peer_id, _leg_b_wire_session, "route/eg4/gateway-leg-b", 1)
	if not bool(leg_connected.get("success", false)):
		_finish_failure(String(leg_connected.get("error_code", "LEG_B_CONNECT_FAILED")), {})
		return

	var tickets: Dictionary = {}
	for client_session_id_value in String(_options["premint-client-sessions"]).split(",", false):
		var minted: Dictionary = _auth_service.mint_auth_ticket(client_session_id_value.strip_edges())
		if not bool(minted.get("success", false)):
			_finish_failure("TICKET_PREMINT_FAILED", {})
			return
		var key := String(client_session_id_value).strip_edges()
		if not tickets.has(key):
			tickets[key] = []
		tickets[key].append(String(minted["details"]["ticket_id"]))

	_started_ms = Time.get_ticks_msec()
	Support.write_json(String(_options["result-file"]), {
		"schema": "planet_simulator.eg4_gateway_state.v1",
		"state": "LISTENING",
		"passed": false,
		"process_id": OS.get_process_id(),
		"tickets": tickets,
	})
	print("EG4_GATEWAY_LISTENING client_port=%d sim_a_port=%d sim_b_port=%d tickets=%d" % [
		int(_options["client-port"]), int(_options["sim-a-port"]), int(_options["sim-b-port"]), tickets.size()])


func _process(_delta: float) -> bool:
	if _finished or _node == null:
		return false
	var pumped: Dictionary = _node.pump(64)
	if not bool(pumped.get("success", false)):
		_finish_failure(String(pumped.get("error_code", "PUMP_FAILED")), {})
		return false
	_poll_leg_b()
	_publish_player_bindings()
	_drive_projection_fan_in()
	_watch_source_liveness()
	_run_stale_maintenance()
	_write_heartbeat()
	_check_completion()
	if Time.get_ticks_msec() - _started_ms > int(_options["timeout-ms"]):
		_finish_failure("GATEWAY_TIMEOUT", {"report": _proj_agg.get_report()})
	return false


var _heartbeat_at_ms: int = 0
var _leg_b_disconnect_details: String = ""
# Rolling histogram of inner channels seen on the leg-B ingress — proves the
# mutation-shaped injection frame actually REACHED the read-only fence.
var _leg_b_inner_channels: Dictionary = {}


func _write_heartbeat() -> void:
	var now := Time.get_ticks_msec()
	if now - _heartbeat_at_ms < 500:
		return
	_heartbeat_at_ms = now
	var agg_report: Dictionary = _proj_agg.get_report()
	Support.write_json(String(_options["result-file"]) + ".heartbeat.json", {
		"schema": "planet_simulator.eg4_gateway_heartbeat.v1",
		"leg_b_connected": _leg_b_connected,
		"leg_b_state": String(_leg_b_boundary.get_peer_snapshot(_leg_b_peer_id).get("state", "")),
		"leg_b_incoming_sequences": Dictionary(
				_leg_b_boundary.get_snapshot().get("peers", {}).get(_leg_b_peer_id, {}))
				.get("incoming_sequences", {}),
		"leg_b_inner_channels": _leg_b_inner_channels.duplicate(true),
		"last_traffic_age_ms": now - int(_last_source_traffic_ms.get(String(_options["authority-id-b"]), now)),
		"fan_in_streams": int(agg_report["fan_in_streams"]),
		"frames_accepted": int(agg_report["counters"]["frames_accepted"]),
		"active_subscriptions": int(agg_report["active_subscriptions"]),
		"stale_subscriptions": int(agg_report["stale_subscription_count"]),
		"placements": int(_placement.get_report().get("counters", {}).get("placements_created", 0)),
		"source_lost": _source_lost_reported,
		"leg_b_disconnect_details": _leg_b_disconnect_details,
	})


## ---- leg B (projection upstream) ----------------------------------------------


func _poll_leg_b() -> void:
	var polled: Dictionary = _leg_b_boundary.poll_events(64)
	if not bool(polled.get("success", false)):
		_finish_failure(String(polled.get("error_code", "LEG_B_POLL_FAILED")), {})
		return
	for event_value in polled.get("details", {}).get("events", []):
		var event: Dictionary = event_value
		match String(event.get("event_type", "")):
			"MESSAGE_RECEIVED":
				_leg_b_connected = true
				_last_source_traffic_ms[String(_options["authority-id-b"])] = Time.get_ticks_msec()
				var leg_b_frame: Dictionary = event.get("frame", {})
				var inner_channel := String(Dictionary(leg_b_frame.get("payload", {}))
						.get("frame", {}).get("channel", ""))
				_leg_b_inner_channels[inner_channel] = int(_leg_b_inner_channels.get(inner_channel, 0)) + 1
				var accepted: Dictionary = _proj_agg.accept_upstream_frame(
						String(_options["authority-id-b"]), leg_b_frame)
				if not bool(accepted.get("success", false)) \
						and String(accepted.get("error_code", "")) == "NON_ENVELOPE_BACKEND_PAYLOAD":
					_finish_failure("LEG_B_NON_ENVELOPE", {})
					return
			"PEER_CONNECTED":
				_leg_b_connected = true
				_ensure_leg_b_ready()
			"PEER_DISCONNECTED":
				print("EG4_LEG_B_DISCONNECT details=%s" % JSON.stringify(event))
				_leg_b_disconnect_details = String(JSON.stringify(event.get("details", event)))
				_handle_projection_source_loss(true)
			_:
				pass
	_ensure_leg_b_ready()
	_leg_b_boundary.flush_outbound(64)


func _ensure_leg_b_ready() -> void:
	var snapshot: Dictionary = _leg_b_boundary.get_peer_snapshot(_leg_b_peer_id)
	match String(snapshot.get("state", "")):
		"TRANSPORT_CONNECTED":
			_leg_b_boundary.mark_peer_handshaking(_leg_b_peer_id)
			_leg_b_boundary.mark_peer_synchronizing(_leg_b_peer_id)
			_leg_b_boundary.mark_peer_ready(_leg_b_peer_id)


func _send_leg_b_operation(gateway_session_id: String, command: String, world_id: String) -> void:
	_leg_b_sequence += 1
	var inner := ClientWorldFrameScript.create(
			"frame/eg4/l2/sub-op/%s/%06d" % [command.replace("_", "-"), _leg_b_sequence],
			gateway_session_id,
			"CLIENT_TO_WORLD", "WORLD_OPERATION", _leg_b_sequence,
			"planet_simulator.test_world_operation.v1",
			{
				"operation_id": "operation/eg4/l2/%s/%s/%06d" % [
					command.replace("_", "-"), world_id.replace("/", "-"), _leg_b_sequence],
				"command": command,
				"target_id": Support.world_entity_slug(world_id),
			})
	var envelope: Dictionary = IngressEnvelopeScript.create(
			"gateway-envelope/eg4/l2/c2w/%06d" % _leg_b_sequence,
			"gateway/eg4/l2-worker",
			"backend-link/eg4/l2-sim-b",
			gateway_session_id,
			1, 1, 1,
			String(_options["authority-id-a"]),
			String(_options["server-instance-id-a"]),
			"PROJECTION",
			inner)
	var wire: Dictionary = Support.FrameScript.create(
			"frame/eg4/l2/backend-b/%06d" % _leg_b_sequence,
			_leg_b_wire_session, _leg_b_sequence,
			GatewayUtils.eg1_physical_channel_for("WORLD_OPERATION"),
			GatewayUtils.eg1_delivery_mode_for("WORLD_OPERATION"),
			"planet_simulator.gateway_ingress_envelope.v1", envelope)
	var sent: Dictionary = _leg_b_boundary.send_to_peer(_leg_b_peer_id, wire)
	if not bool(sent.get("success", false)) and not String(sent.get("error_code", "")) in ["PEER_NOT_READY", "UNKNOWN_PEER"]:
		_finish_failure(String(sent.get("error_code", "LEG_B_SEND_FAILED")), {})


## ---- demand handling (additive placement-handler dispatch) ---------------------


func handle_session_control(transport_frame: Dictionary, route_table, client_transport_peer_id: String) -> Dictionary:
	var inner: Dictionary = transport_frame.get("payload", {})
	if String(inner.get("payload_schema", "")) != Support.DEMAND_PAYLOAD_SCHEMA:
		# Delegate EVERYTHING else to the real EG2 auth/placement flow.
		return _placement.handle_session_control(transport_frame, route_table, client_transport_peer_id)
	return _handle_demand(inner)


func on_client_peer_gone(peer_id: String) -> void:
	_placement.on_client_peer_gone(peer_id)


func _handle_demand(frame: Dictionary) -> Dictionary:
	var payload: Dictionary = Dictionary(frame.get("payload", {}))
	var gateway_session_id := String(frame.get("gateway_session_id", ""))
	if not BusUtilsScript.is_canonical_id(gateway_session_id, "gateway-session"):
		return {"success": false, "error_code": "INVALID_DEMAND_SESSION", "details": {}}
	var demand_kind := String(payload.get("demand_kind", ""))
	var worlds_raw: Array = payload.get("worlds", [])
	if typeof(worlds_raw) != TYPE_ARRAY or worlds_raw.is_empty():
		return {"success": false, "error_code": "INVALID_DEMAND_WORLDS", "details": {}}
	var worlds: Array[String] = []
	for value in worlds_raw:
		var world_id := String(value)
		if not BusUtilsScript.is_canonical_id(world_id, "world"):
			return {"success": false, "error_code": "INVALID_DEMAND_WORLD_ID", "details": {"world_id": world_id}}
		worlds.append(world_id)

	# Graph-driven source resolution: plan THIS session's view from the fixture
	# snapshot; ACTIVE anchor stays on leg A, everything else maps to the
	# registered PROJECTION source.
	var graph_revision := int(_snapshot["graph_revision"])
	var planned: Dictionary = ViewPlannerScript.plan_view(_snapshot, {
		"gateway_session_id": gateway_session_id,
		"home_world_id": Support.HOME_WORLD_ID_EG4,
		"reference_frame_id": "reference-frame/eg4/l2",
		"interest_revision": maxi(cycle_demand_revision(), 1),
		"expected_graph_revision": graph_revision,
	})
	if not bool(planned.get("success", false)):
		return {"success": false, "error_code": String(planned.get("error_code", "PLAN_FAILED")), "details": {}}
	var projection_plan_worlds := {}
	for entry_index in range((planned["details"]["entries"] as Array).size()):
		if entry_index == 0:
			continue
		projection_plan_worlds[String(planned["details"]["entries"][entry_index]["world_id"])] = true
	for world_id in worlds:
		if world_id == Support.HOME_WORLD_ID_EG4:
			continue
		if not projection_plan_worlds.has(world_id):
			return {"success": false, "error_code": "DEMAND_WORLD_NOT_IN_GRAPH_PLAN", "details": {"world_id": world_id}}

	match demand_kind:
		Support.DEMAND_KIND_SUBSCRIBE:
			_apply_demand(gateway_session_id, worlds, cycle_demand_revision(), true)
		Support.DEMAND_KIND_WITHDRAW:
			_withdraw_demand(gateway_session_id)
		_:
			return {"success": false, "error_code": "UNKNOWN_DEMAND_KIND", "details": {}}
	_send_demand_ack(gateway_session_id, demand_kind, worlds.size())
	return {"success": true, "details": {"handled": true}}


var _demand_revision_counter: int = 0


func cycle_demand_revision() -> int:
	_demand_revision_counter += 1
	return _demand_revision_counter


func _apply_demand(gateway_session_id: String, worlds: Array[String], revision: int, subscribe_leg_b: bool) -> void:
	if not _clients_registered.has(gateway_session_id):
		var registered: Dictionary = _proj_agg.register_client(gateway_session_id)
		if bool(registered.get("success", false)):
			_clients_registered[gateway_session_id] = true
	var demand_entries: Array = [{
		"world_id": Support.HOME_WORLD_ID_EG4,
		"source_authority_id": String(_options["authority-id-a"]),
	}]
	for world_id in worlds:
		demand_entries.append({
			"world_id": world_id,
			"source_authority_id": String(_options["authority-id-b"]),
		})
	var demand_result: Dictionary = _interest_agg.set_client_demand({
		"gateway_session_id": gateway_session_id,
		"interest_revision": revision,
		"graph_revision": int(_snapshot["graph_revision"]),
		"worlds": demand_entries,
	})
	if not bool(demand_result.get("success", false)):
		return
	if not _pairs_by_session.has(gateway_session_id):
		_pairs_by_session[gateway_session_id] = []
	for delta_value in demand_result["details"]["deltas"]:
		var delta: Dictionary = delta_value
		if String(delta["action"]) != "SUBSCRIBE":
			continue
		var source_authority_id := String(delta["source_authority_id"])
		var world_id := String(delta["world_id"])
		if source_authority_id != String(_options["authority-id-b"]):
			continue
		var subscribed: Dictionary = _proj_agg.subscribe_world(gateway_session_id, source_authority_id, world_id)
		if bool(subscribed.get("success", false)):
			(_pairs_by_session[gateway_session_id] as Array).append([source_authority_id, world_id])
			if subscribe_leg_b:
				_send_leg_b_operation(gateway_session_id, "projection_subscribe", world_id)


func _withdraw_demand(gateway_session_id: String) -> void:
	_interest_agg.withdraw_client_demand(gateway_session_id)
	for pair_value in _pairs_by_session.get(gateway_session_id, []):
		var pair: Array = pair_value
		_proj_agg.unsubscribe_world(gateway_session_id, String(pair[0]), String(pair[1]))
		_send_leg_b_operation(gateway_session_id, "projection_withdraw", String(pair[1]))
	_pairs_by_session[gateway_session_id] = []


func _withdraw_everything_for_loss(loss_result: Dictionary) -> void:
	for gateway_session_id_value in _pairs_by_session.keys():
		var gateway_session_id := String(gateway_session_id_value)
		if (_pairs_by_session[gateway_session_id] as Array).is_empty():
			continue
		_interest_agg.withdraw_client_demand(gateway_session_id)
		for pair_value in _pairs_by_session[gateway_session_id]:
			var pair: Array = pair_value
			_proj_agg.unsubscribe_world(gateway_session_id, String(pair[0]), String(pair[1]))
		(_pairs_by_session[gateway_session_id] as Array).clear()


func _send_demand_ack(gateway_session_id: String, demand_kind: String, accepted: int) -> void:
	var ack_frame := ClientWorldFrameScript.create(
			"frame/eg4/l2/demand-ack/%s/%06d" % [demand_kind.replace("_", "-"), _leg_b_sequence],
			gateway_session_id,
			"WORLD_TO_CLIENT", "SESSION_CONTROL", 1,
			Support.DEMAND_ACK_PAYLOAD_SCHEMA,
			{"demand_kind": demand_kind, "accepted_worlds": accepted})
	var spec := {
		"frame_id": String(ack_frame["frame_id"]),
		"channel": GatewayUtils.eg1_physical_channel_for("SESSION_CONTROL"),
		"delivery_mode": GatewayUtils.eg1_delivery_mode_for("SESSION_CONTROL"),
		"payload_schema": Support.DEMAND_ACK_PAYLOAD_SCHEMA,
		"payload": ack_frame,
	}
	_node.send_client_frame_spec_for_session(gateway_session_id, spec)


## ---- fan-in, liveness, maintenance ----------------------------------------------


func _drive_projection_fan_in() -> void:
	var pumped: Dictionary = _proj_agg.pump(64)
	if not bool(pumped.get("success", false)):
		_finish_failure(String(pumped.get("error_code", "FAN_IN_PUMP_FAILED")), {})


func _watch_source_liveness() -> void:
	if _source_lost_reported:
		return
	if _proj_agg.active_subscription_count() < 1 and _proj_agg.stale_subscription_count() < 1:
		_last_source_traffic_ms[String(_options["authority-id-b"])] = Time.get_ticks_msec()
		return
	var last := int(_last_source_traffic_ms.get(String(_options["authority-id-b"]), Time.get_ticks_msec()))
	if Time.get_ticks_msec() - last > int(_options["source-loss-timeout-ms"]):
		_handle_projection_source_loss(false)


func _handle_projection_source_loss(graceful_disconnect: bool) -> void:
	if _source_lost_reported:
		return
	_source_lost_reported = true
	_loss_was_graceful_disconnect = graceful_disconnect
	var lost: Dictionary = _proj_agg.mark_source_lost(String(_options["authority-id-b"]))
	_lost_world_count = (lost.get("details", {}).get("affected_worlds", []) as Array).size() \
			if bool(lost.get("success", false)) else -1
	_withdraw_everything_for_loss(lost)


func _run_stale_maintenance() -> void:
	if _proj_agg.stale_subscription_count() > 0:
		_proj_agg.run_maintenance_cycle()
	# The interest aggregator drains its own stale demand ledger through the
	# same bounded-cycle discipline; without this the withdrawal residue would
	# never reach zero in gateway telemetry.
	if _interest_agg.stale_subscription_count() > 0:
		_interest_agg.run_maintenance_cycle()


func _check_completion() -> void:
	if _completion_at_ms >= 0:
		if Time.get_ticks_msec() - _completion_at_ms >= 4000:
			_finish_success()
		return
	var flow_counters: Dictionary = _placement.get_report().get("counters", {})
	var placements := int(flow_counters.get("placements_created", 0)) \
			+ int(flow_counters.get("placements_resumed", 0))
	var detached := int(_node.get_report()["counters"].get("session_control_detached", 0))
	if placements >= int(_options["expected-placements"]) \
			and detached >= int(_options["expected-detachments"]) \
			and _source_lost_reported \
			and _proj_agg.stale_subscription_count() == 0:
		_completion_at_ms = Time.get_ticks_msec()


## ---- reporting --------------------------------------------------------------------


func _publish_player_bindings() -> void:
	var path := String(_options.get("player-binding-file", ""))
	if path.is_empty():
		return
	var flow_report: Dictionary = _placement.get_report()
	var dirty := false
	for entry_value in flow_report.get("live_placements", []):
		var entry: Dictionary = entry_value
		var gateway_session_id := String(entry["gateway_session_id"])
		if _published_bindings.has(gateway_session_id):
			continue
		var session_result: Dictionary = _auth_service.get_session(gateway_session_id)
		if not bool(session_result.get("success", false)):
			continue
		var session: Dictionary = session_result.get("details", {}).get("session", {})
		if session.is_empty():
			continue
		_published_bindings[gateway_session_id] = {
			"gateway_session_id": gateway_session_id,
			"client_session_id": String(session["client_session_id"]),
			"logical_player_id": String(session["logical_player_id"]),
			"player_entity_id": String(session["player_entity_id"]),
		}
		dirty = true
	if dirty:
		Support.write_json(path, {
			"schema": "planet_simulator.eg3_player_bindings.v1",
			"bindings": _published_bindings.duplicate(true),
		})


func _finish_success() -> void:
	_finished = true
	_publish_player_bindings()
	var node_report: Dictionary = _node.get_report()
	var report := {
		"schema": "planet_simulator.eg4_gateway_worker_report.v1",
		"state": "COMPLETE",
		"passed": true,
		"gateway_node": node_report,
		"placement_flow": _placement.get_report(),
		"projection_aggregation": _proj_agg.get_report(),
		"interest_aggregation": _interest_agg.get_report(),
		"source_lost_reported": _source_lost_reported,
		"loss_was_graceful_disconnect": _loss_was_graceful_disconnect,
		"lost_world_count": _lost_world_count,
		"upstream_legs": {"active": String(_options["authority-id-a"]), "projection": String(_options["authority-id-b"])},
		"user_data_dir": String(_options["user-data-dir"]),
		"process_id": OS.get_process_id(),
	}
	Support.write_json(String(_options["result-file"]), report)
	_node.stop()
	_leg_b_boundary.stop()
	print("EG4_GATEWAY_COMPLETE stale=%d rejected_injection=%d lost=%s" % [
		int(report["projection_aggregation"]["stale_subscription_count"]),
		int(report["projection_aggregation"]["counters"]["rejected_injection"]),
		str(_source_lost_reported),
	])
	quit(0)


func _finish_failure(error_code: String, details: Dictionary) -> void:
	_finished = true
	var report: Dictionary = {
		"schema": "planet_simulator.eg4_gateway_worker_report.v1",
		"state": "FAILED",
		"passed": false,
		"failure_code": error_code,
		"details": details,
		"process_id": OS.get_process_id(),
	}
	if _proj_agg != null:
		report["projection_aggregation"] = _proj_agg.get_report()
	if _node != null:
		_node.stop()
	if _leg_b_boundary != null:
		_leg_b_boundary.stop()
	if not String(_options.get("result-file", "")).is_empty():
		Support.write_json(String(_options["result-file"]), report)
	push_error("EG4 gateway worker failed: %s" % error_code)
	quit(1)

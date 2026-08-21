extends SceneTree

## EG1 L1 exit predicate: DIRECT_GATEWAY_CANONICAL_EQUIVALENCE_PASS.
##
## In ONE process, over loopback transport ports: (a) a DIRECT run applies the
## fixed scenario (3 canonical item commands + 1 movement intent, fixed ids)
## straight through NetworkedGameplayService; (b) a GATEWAY run drives the same
## scenario through the real gateway node (client frame -> gateway -> sim-side
## admission -> egress), where the SIM side unwraps ingress envelopes and calls
## the SAME service entry points. The gateway itself never touches domain code.
## (c) canonical snapshots, payload hashes, the sim-side operation ledger and
## gateway counters must all line up.

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ServiceScript = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
const GatewayNode = preload("res://scripts/network/gateway/runtime/eg1_gateway_node.gd")
const LoopbackPort = preload("res://scripts/network/transports/v2/loopback_multi_peer_transport_port.gd")
const FrameScript = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")
const ClientWorldFrameScript = preload("res://scripts/network/gateway/client_world_frame.gd")
const IngressEnvelopeScript = preload("res://scripts/network/gateway/gateway_ingress_envelope.gd")
const EgressEnvelopeScript = preload("res://scripts/network/gateway/gateway_egress_envelope.gd")
const ForwarderScript = preload("res://scripts/network/gateway/runtime/eg1_gateway_forwarder.gd")
const GatewayUtils = preload("res://scripts/network/gateway/gateway_contract_utils.gd")

const AUTHORITY_OWNER_ID := "simulation/eg1/gateway-equivalence"
const AUTHORITY_EPOCH := 9
const SERVER_TICK := 500
const SERVICE_CONFIG := {
	"profile": "MULTIPLAYER_CORE",
	"region_id": "region/eg1/equivalence",
	"topology_adapter": "LOOPBACK",
	"playable_sandbox": true,
}
const LOGICAL_PLAYER_ID := "a"
const PLAYER_TRANSPORT_SESSION := "transport-session/eg1/player-a"
const JOIN_OPERATION_ID := "operation/eg1/scenario/join"

# Fixed scenario: identical order and ids for DIRECT and GATEWAY runs.
const SCENARIO_ITEM_COMMANDS := [
	{"operation_id": "operation/eg1/scenario/0001", "command_type": "item.split", "payload": {"item_id": "item/player/a/beacons", "quantity": 1}, "target_id": "entity/eg1-scenario-1"},
	{"operation_id": "operation/eg1/scenario/0002", "command_type": "inventory.assign_hotbar", "payload": {"item_id": "item/player/a/battery", "slot_index": 5}, "target_id": "entity/eg1-scenario-2"},
	{"operation_id": "operation/eg1/scenario/0003", "command_type": "inventory.select_hotbar", "payload": {"selected_hotbar_index": 2}, "target_id": "entity/eg1-scenario-3"},
]
const MOVEMENT_OPERATION_ID := "operation/eg1/scenario/move/0001"
const MOVEMENT_INPUT_SEQ := 1
const MOVEMENT_INTENT := {
	"move_x": 0.0, "move_z": 0.0, "look_yaw": 0.0, "look_pitch": 0.0,
	"jump_pressed": false, "sprint": false, "delta_seconds": 0.05,
}

const GATEWAY_INSTANCE_ID := "gateway/eg1/l1-loopback"
const CLIENT_PEER_ID := "peer/loopback/eg1-client-a"
const CLIENT_WIRE_SESSION := "transport-session/eg1/l1-client"
const CLIENT_SESSION_ID := "client-session/eg1/l1-alpha"
const BACKEND_LINK_PEER_ID := "peer/loopback/eg1-backend-link"

var assertions := 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[eg1-l1][FAIL] %s" % message)


func _err(result: Dictionary) -> String:
	return String(result.get("error_code", ""))


func _build_service() -> Object:
	var service = ServiceScript.new()
	var setup: Dictionary = service.setup(AUTHORITY_OWNER_ID, AUTHORITY_EPOCH, SERVER_TICK, SERVICE_CONFIG.duplicate(true))
	_assert(bool(setup.get("success", false)), "service setup failed: %s" % _err(setup))
	var joined: Dictionary = service.join(LOGICAL_PLAYER_ID, PLAYER_TRANSPORT_SESSION, JOIN_OPERATION_ID)
	_assert(bool(joined.get("success", false)), "player join failed: %s" % _err(joined))
	return service


func _apply_item_direct(service, step: Dictionary) -> void:
	var result: Dictionary = service.handle_canonical_item_command(
			LOGICAL_PLAYER_ID, PLAYER_TRANSPORT_SESSION, 1,
			String(step["operation_id"]), String(step["command_type"]),
			Dictionary(step["payload"]).duplicate(true))
	_assert(bool(result.get("success", false)), "direct item command failed (%s): %s" % [step["operation_id"], _err(result)])


func _run_direct() -> Dictionary:
	var service := _build_service()
	for step in SCENARIO_ITEM_COMMANDS:
		_apply_item_direct(service, step)
	var moved: Dictionary = service.submit_movement_intent(
			LOGICAL_PLAYER_ID, PLAYER_TRANSPORT_SESSION, 1, MOVEMENT_INPUT_SEQ,
			MOVEMENT_INTENT.duplicate(true), MOVEMENT_OPERATION_ID)
	_assert(bool(moved.get("success", false)), "direct movement intent failed: %s" % _err(moved))
	return {
		"snapshot": service.create_canonical_item_graph_snapshot(),
	}


## ---- GATEWAY RUN -----------------------------------------------------------

var _gateway
var _port_client
var _port_backend
var _sim_service
var _sim_ledger: Dictionary = {}
var _client_inbox_index: int = 0
var _backend_inbox_index: int = 0
var _item_wire_sequence: int = 0
var _minted_gateway_session_id := ""
var _sim_snapshot_revision_counter: int = 0


func _inject_client_frame(frame_spec: Dictionary) -> void:
	var wire: Dictionary = FrameScript.create(
			String(frame_spec["frame_id"]), String(frame_spec["session_id"]),
			int(frame_spec["sequence"]), String(frame_spec["channel"]),
			String(frame_spec["delivery_mode"]), String(frame_spec["payload_schema"]),
			Dictionary(frame_spec["payload"]))
	var injected: Dictionary = _port_client.inject_received_frame(CLIENT_PEER_ID, wire)
	_assert(bool(injected.get("success", false)), "client frame injection failed")


func _send_hello() -> void:
	var hello_payload: Dictionary = ClientWorldFrameScript.create(
			"frame/eg1/l1/hello/1", "gateway-session/eg1/probe/l1", "CLIENT_TO_WORLD",
			"SESSION_CONTROL", 1, GatewayUtils.EG1_SESSION_HELLO_PAYLOAD_SCHEMA,
			{
				"client_session_id": CLIENT_SESSION_ID,
				"logical_player_id": "player/eg1-l1",
				"player_entity_id": "entity/eg1-player-l1",
				"world_id": "world/main",
			})
	_inject_client_frame({
		"frame_id": "frame/eg1/l1/hello-wire/1",
		"session_id": CLIENT_WIRE_SESSION,
		"sequence": 1,
		"channel": "CONTROL",
		"delivery_mode": "RELIABLE_ORDERED",
		"payload_schema": GatewayUtils.EG1_SESSION_HELLO_PAYLOAD_SCHEMA,
		"payload": hello_payload,
	})


func _send_scenario_frame(step: Dictionary) -> void:
	_item_wire_sequence += 1
	var inner := ClientWorldFrameScript.create(
			"frame/eg1/l1/op/%s" % String(step["operation_id"]).get_slice("/", 3),
			_minted_gateway_session_id, "CLIENT_TO_WORLD", "WORLD_OPERATION",
			_item_wire_sequence, "planet_simulator.test_world_operation.v1",
			{
				"operation_id": String(step["operation_id"]),
				"command": String(step["command_type"]),
				"target_id": String(step["target_id"]),
			})
	_inject_client_frame(_client_wire_spec(inner, "ITEM"))


func _send_movement_frame() -> void:
	var inner := ClientWorldFrameScript.create(
			"frame/eg1/l1/move/%d" % MOVEMENT_INPUT_SEQ,
			_minted_gateway_session_id, "CLIENT_TO_WORLD", "INPUT_MOVEMENT",
			MOVEMENT_INPUT_SEQ, "planet_simulator.test_input.v1",
			{"input_seq": MOVEMENT_INPUT_SEQ, "axis_x": 0.0})
	_inject_client_frame(_client_wire_spec(inner, "INPUT"))


func _client_wire_spec(inner: Dictionary, physical_channel: String) -> Dictionary:
	return {
		"frame_id": "frame/eg1/l1/wire/%s/%d" % [physical_channel.to_lower(), int(inner["sequence"])],
		"session_id": CLIENT_WIRE_SESSION,
		"sequence": maxi(int(inner["sequence"]), 1),
		"channel": physical_channel,
		"delivery_mode": ForwarderScript.delivery_mode_for(String(inner["channel"])),
		"payload_schema": String(inner["payload_schema"]),
		"payload": inner.duplicate(true),
	}


## SIM-side admission: unwrap the ingress envelope and apply the SAME domain
## entry points as the DIRECT run. This is sim code, not gateway code.
func _sim_process_pending() -> void:
	var inbox: Array = _port_backend.get_messages_for_peer(BACKEND_LINK_PEER_ID)
	while _backend_inbox_index < inbox.size():
		var transport_frame: Dictionary = inbox[_backend_inbox_index]
		_backend_inbox_index += 1
		var envelope: Dictionary = transport_frame.get("payload", {})
		if String(envelope.get("schema", "")) != IngressEnvelopeScript.SCHEMA:
			_fail("sim received a non-envelope backend payload")
			continue
		var inner: Dictionary = envelope["frame"]
		var channel := String(inner["channel"])
		match channel:
			"WORLD_OPERATION":
				_sim_admit_item_command(envelope, inner)
			"INPUT_MOVEMENT":
				_sim_admit_movement(envelope, inner)
			_:
				_fail("sim received unexpected channel %s" % channel)


func _sim_admit_once(operation_id: String) -> bool:
	if _sim_ledger.has(operation_id):
		_fail("operation %s reached the sim twice (continuity broken)" % operation_id)
		return false
	_sim_ledger[operation_id] = true
	return true


func _sim_admit_item_command(envelope: Dictionary, inner: Dictionary) -> void:
	var operation_id := String(inner["payload"]["operation_id"])
	if not _sim_admit_once(operation_id):
		return
	var step: Dictionary = _scenario_step(operation_id)
	var result: Dictionary = _sim_service.handle_canonical_item_command(
			LOGICAL_PLAYER_ID, PLAYER_TRANSPORT_SESSION, 1,
			operation_id, String(step["command_type"]),
			Dictionary(step["payload"]).duplicate(true))
	_assert(bool(result.get("success", false)), "sim-side item command failed (%s): %s" % [operation_id, _err(result)])
	_sim_send_egress(inner, "WORLD_OPERATION", {
		"operation_id": operation_id,
		"command": String(step["command_type"]),
		"target_id": String(step["target_id"]),
	})


func _sim_admit_movement(envelope: Dictionary, inner: Dictionary) -> void:
	var input_seq := int(inner["payload"]["input_seq"])
	if input_seq != MOVEMENT_INPUT_SEQ:
		_fail("sim received unexpected input_seq %d" % input_seq)
		return
	if not _sim_admit_once(MOVEMENT_OPERATION_ID):
		return
	var result: Dictionary = _sim_service.submit_movement_intent(
			LOGICAL_PLAYER_ID, PLAYER_TRANSPORT_SESSION, 1, input_seq,
			MOVEMENT_INTENT.duplicate(true), MOVEMENT_OPERATION_ID)
	_assert(bool(result.get("success", false)), "sim-side movement intent failed: %s" % _err(result))
	_sim_snapshot_revision_counter += 1
	_sim_send_egress(inner, "AUTHORITATIVE_SNAPSHOT", {"revision": _sim_snapshot_revision_counter})


func _sim_send_egress(request_inner: Dictionary, egress_channel: String, egress_payload: Dictionary) -> void:
	_sim_snapshot_revision_counter += 1 if egress_channel != "AUTHORITATIVE_SNAPSHOT" else 0
	var row: Dictionary = _route_row()
	var inner := ClientWorldFrameScript.create(
			"frame/eg1/l1/result/%d" % _sim_snapshot_revision_counter,
			_minted_gateway_session_id, "WORLD_TO_CLIENT", egress_channel,
			maxi(int(request_inner["sequence"]), 1),
			"planet_simulator.test_world_operation.v1" if egress_channel == "WORLD_OPERATION" else "planet_simulator.test_snapshot.v1",
			egress_payload)
	var envelope: Dictionary = EgressEnvelopeScript.create(
			"gateway-envelope/eg1/l1/w2c/%d" % _sim_snapshot_revision_counter,
			GATEWAY_INSTANCE_ID,
			String(row["backend_link_id"]),
			_minted_gateway_session_id,
			int(row["session_slot"]),
			int(row["route_revision"]),
			int(row["observed_authority_epoch"]),
			"authority/eg1-local-sim",
			"server-instance/eg1-sim-a",
			"ACTIVE",
			inner)
	var envelope_check: Dictionary = EgressEnvelopeScript.validate(envelope)
	_assert(bool(envelope_check.get("success", false)), "sim produced an invalid egress envelope: %s %s" % [_err(envelope_check), str(envelope_check.get("message", ""))])
	var spec: Dictionary = {
		"frame_id": "frame/eg1/l1/backend-down/%d" % _sim_snapshot_revision_counter,
		"session_id": "transport-session/eg1/gateway-backend",
		"sequence": _backend_inbox_index,
		"channel": ForwarderScript.physical_channel_for(egress_channel),
		"delivery_mode": ForwarderScript.delivery_mode_for(egress_channel),
		"payload_schema": "planet_simulator.gateway_egress_envelope.v1",
		"payload": envelope,
	}
	var wire: Dictionary = FrameScript.create(
			String(spec["frame_id"]), String(spec["session_id"]), maxi(int(spec["sequence"]), 1),
			String(spec["channel"]), String(spec["delivery_mode"]),
			String(spec["payload_schema"]), Dictionary(spec["payload"]))
	var injected: Dictionary = _port_backend.inject_received_frame(BACKEND_LINK_PEER_ID, wire)
	_assert(bool(injected.get("success", false)), "sim egress injection failed")


func _scenario_step(operation_id: String) -> Dictionary:
	for step in SCENARIO_ITEM_COMMANDS:
		if String(step["operation_id"]) == operation_id:
			return step
	return {}


func _route_row() -> Dictionary:
	var report: Dictionary = _gateway.get_report()
	for session in report["sessions"]:
		if String(session["gateway_session_id"]) == _minted_gateway_session_id:
			return {
				"session_slot": int(session["session_slot"]),
				"route_revision": int(session["route_revision"]),
				"backend_link_id": String(session["backend_link_id"]),
				"observed_authority_epoch": 1,
			}
	_fail("route row vanished for %s" % _minted_gateway_session_id)
	return {"session_slot": 1, "route_revision": 1, "backend_link_id": "backend-link/eg1/local-sim", "observed_authority_epoch": 1}


func _fail(message: String) -> void:
	failures.append(message)
	print("[eg1-l1][FAIL] %s" % message)


func _drain_client_inbox() -> Array:
	var inbox: Array = _port_client.get_messages_for_peer(CLIENT_PEER_ID)
	var fresh: Array = []
	while _client_inbox_index < inbox.size():
		fresh.append(inbox[_client_inbox_index])
		_client_inbox_index += 1
	return fresh


func _run_gateway() -> Dictionary:
	_sim_service = _build_service()
	_port_client = LoopbackPort.new()
	_port_backend = LoopbackPort.new()
	_port_client.setup()
	_port_backend.setup()
	_gateway = GatewayNode.new()
	var started: Dictionary = _gateway.start(
			{"transport": "LOOPBACK", "name": "eg1-l1-client"},
			{"transport": "LOOPBACK", "name": "eg1-l1-backend"},
			GATEWAY_INSTANCE_ID,
			{
				"client_port": _port_client,
				"backend_port": _port_backend,
				"backend_peer_id": BACKEND_LINK_PEER_ID,
			})
	_assert(bool(started.get("success", false)), "gateway start failed: %s" % _err(started))
	if not bool(started.get("success", false)):
		return {}

	var attached: Dictionary = _port_client.attach_peer(CLIENT_PEER_ID, CLIENT_WIRE_SESSION, "route/eg1/l1-client", 1)
	_assert(bool(attached.get("success", false)), "loopback client attach failed")

	# HELLO -> ATTACHED ack
	_send_hello()
	_assert(bool(_gateway.pump().get("success", false)), "gateway pump failed during hello")
	var ack_found := false
	for frame_value in _drain_client_inbox():
		var frame: Dictionary = frame_value
		var payload: Dictionary = frame.get("payload", {})
		if String(payload.get("channel", "")) == "SESSION_CONTROL":
			ack_found = true
			_minted_gateway_session_id = String(payload["payload"]["gateway_session_id"])
			_assert(String(payload["payload"]["state"]) == "ATTACHED", "hello ack did not report ATTACHED")
	_assert(ack_found, "no SESSION_CONTROL ack reached the client leg")
	_assert(_minted_gateway_session_id.begins_with("gateway-session/eg1/"), "minted id outside its namespace")

	# Scenario through the full pipeline.
	_sim_process_pending()
	for index in range(SCENARIO_ITEM_COMMANDS.size()):
		_send_scenario_frame(SCENARIO_ITEM_COMMANDS[index])
		_assert(bool(_gateway.pump().get("success", false)), "gateway pump failed forwarding op %d" % index)
		_sim_process_pending()
		_assert(bool(_gateway.pump().get("success", false)), "gateway pump failed returning op %d" % index)
	_send_movement_frame()
	_assert(bool(_gateway.pump().get("success", false)), "gateway pump failed forwarding movement")
	_sim_process_pending()
	_assert(bool(_gateway.pump().get("success", false)), "gateway pump failed returning movement")
	# One extra pump drains any tail frames queued mid-pump.
	_assert(bool(_gateway.pump().get("success", false)), "gateway tail pump failed")

	var result_frames := {"WORLD_OPERATION": 0, "AUTHORITATIVE_SNAPSHOT": 0}
	for frame_value in _drain_client_inbox():
		var payload: Dictionary = frame_value.get("payload", {})
		var channel := String(payload.get("channel", ""))
		if result_frames.has(channel):
			result_frames[channel] = int(result_frames[channel]) + 1
	_assert(int(result_frames["WORLD_OPERATION"]) == SCENARIO_ITEM_COMMANDS.size(),
			"client leg did not receive every item result")
	_assert(int(result_frames["AUTHORITATIVE_SNAPSHOT"]) == 1,
			"client leg did not receive the movement snapshot reply")

	return {"snapshot": _sim_service.create_canonical_item_graph_snapshot()}


func _init() -> void:
	var direct := _run_direct()
	var gateway_run := _run_gateway()

	# --- (c) THE EXIT PREDICATE ---
	var direct_snapshot: Dictionary = direct.get("snapshot", {})
	var gateway_snapshot: Dictionary = gateway_run.get("snapshot", {})
	_assert(not direct_snapshot.is_empty() and not gateway_snapshot.is_empty(), "snapshots missing")
	_assert(Utils.canonical_json(direct_snapshot) == Utils.canonical_json(gateway_snapshot),
			"DIRECT and GATEWAY canonical snapshots differ")
	_assert(String(direct_snapshot.get("checksum", "")) == String(gateway_snapshot.get("checksum", ""))
			and not String(gateway_snapshot.get("checksum", "")).is_empty(),
			"payload hash equality failed")

	# Operation ledger continuity on the sim side: every scenario operation
	# exactly once, nothing else.
	var expected_ops: Array[String] = [MOVEMENT_OPERATION_ID]
	for step in SCENARIO_ITEM_COMMANDS:
		expected_ops.append(String(step["operation_id"]))
	expected_ops.sort()
	var ledger_keys: Array[String] = []
	for key in _sim_ledger.keys():
		ledger_keys.append(String(key))
	ledger_keys.sort()
	_assert(ledger_keys == expected_ops, "sim ledger mismatch: %s" % str(ledger_keys))

	# Gateway counters: everything forwarded, nothing dropped, no silent send failures.
	var report: Dictionary = _gateway.get_report()
	var counters: Dictionary = report["counters"]
	var forwarder_counters: Dictionary = counters.get("forwarder", {})
	_assert(int(forwarder_counters.get("forwarded_client_to_world", 0)) == SCENARIO_ITEM_COMMANDS.size() + 1,
			"unexpected client->world forward count: %s" % str(forwarder_counters))
	_assert(int(forwarder_counters.get("forwarded_world_to_client", 0)) == SCENARIO_ITEM_COMMANDS.size() + 1,
			"unexpected world->client forward count: %s" % str(forwarder_counters))
	_assert(int(forwarder_counters.get("dropped_client_to_world", -1)) == 0
			and int(forwarder_counters.get("dropped_world_to_client", -1)) == 0,
			"gateway dropped frames")
	_assert(int(counters.get("backend_send_failures", -1)) == 0 and int(counters.get("client_send_failures", -1)) == 0,
			"gateway recorded send failures: %s" % str(counters.get("failure_codes", {})))
	_assert(int(counters.get("frames_sent_client_to_world", 0)) >= SCENARIO_ITEM_COMMANDS.size() + 1,
			"gateway sent too few upstream frames")
	_assert(int(counters.get("frames_sent_world_to_client", 0)) >= SCENARIO_ITEM_COMMANDS.size() + 2,
			"gateway sent too few downstream frames")

	# Identity namespaces strictly separated; slots are ints, never PlayerIds.
	var identity: Dictionary = report["identity"]
	for peer_id in identity["transport_peer_ids"]:
		_assert(String(peer_id).begins_with("peer/"), "transport peer id outside its namespace: %s" % str(peer_id))
	for gsid in identity["gateway_session_ids"]:
		_assert(String(gsid).begins_with("gateway-session/"), "gateway session id outside its namespace")
		_assert(String(gsid) != String(identity["client_session_ids"][0]), "gateway session collided with client session")
	for csid in identity["client_session_ids"]:
		_assert(String(csid).begins_with("client-session/"), "client session id outside its namespace")
	for slot_value in identity["session_slots"]:
		_assert(typeof(slot_value) == TYPE_INT, "session_slot must be an integer, never a PlayerId string")
	_assert(int(identity["session_slots"][0]) != 0, "session slot not allocated")

	# Report carries NO domain data.
	_assert(_has_no_domain_fields(report, ""), "gateway report leaked domain fields")

	var stopped: Dictionary = _gateway.stop()
	_assert(bool(stopped.get("success", false)), "gateway stop failed: %s" % _err(stopped))

	_finish()


func _has_no_domain_fields(value, path: String) -> bool:
	var forbidden := ["logical_player_id", "player_entity_id", "world_id", "canonical_multiplayer_item_graph", "canonical_item_graph", "checksum", "operation_ledger", "inventories", "items"]
	match typeof(value):
		TYPE_DICTIONARY:
			for raw_key in value.keys():
				var key := String(raw_key)
				var next_path := "%s.%s" % [path, key]
				if forbidden.has(key):
					print("[eg1-l1][FAIL] domain field at %s" % next_path)
					return false
				if not _has_no_domain_fields(value[raw_key], next_path):
					return false
		TYPE_ARRAY:
			for index in range(value.size()):
				if not _has_no_domain_fields(value[index], "%s[%d]" % [path, index]):
					return false
	return true


func _finish() -> void:
	if _gateway != null:
		_gateway.stop()
	var summary := {
		"test": "eg1_gateway_loopback_equivalence_l1",
		"verdict": "PASS" if failures.is_empty() else "FAIL",
		"assertions": assertions,
		"predicate": "DIRECT_GATEWAY_CANONICAL_EQUIVALENCE_PASS" if failures.is_empty() else "PREDICATE_NOT_DEMONSTRATED",
		"failures": failures,
	}
	print(JSON.stringify(summary))
	if failures.is_empty():
		print("[eg1-l1] L1 PASS — DIRECT_GATEWAY_CANONICAL_EQUIVALENCE_PASS (%d assertions)" % assertions)
		quit(0)
	else:
		print("[eg1-l1] L1 FAIL")
		quit(1)

extends SceneTree

## EG1 L0 session control: gateway_session_id minting namespaces, ack shapes,
## duplicate attach fences, detach semantics, unknown-session handling.

const RouteTable = preload("res://scripts/network/gateway/runtime/eg1_gateway_route_table.gd")
const SessionControl = preload("res://scripts/network/gateway/runtime/eg1_gateway_session_control.gd")
const ClientWorldFrameScript = preload("res://scripts/network/gateway/client_world_frame.gd")
const GatewayUtils = preload("res://scripts/network/gateway/gateway_contract_utils.gd")

const AUTHORITY_ID := "authority/sim-a"
const SERVER_INSTANCE_ID := "server-instance/sim-a-eg1"

var assertions := 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[eg1-session-control][FAIL] %s" % message)


func _err(result: Dictionary) -> String:
	return String(result.get("error_code", ""))


func _client_world_frame(
		frame_id: String,
		channel: String,
		direction: String,
		sequence: int,
		payload_schema: String,
		payload: Dictionary
) -> Dictionary:
	return {
		"schema": ClientWorldFrameScript.SCHEMA,
		"protocol_version": ClientWorldFrameScript.PROTOCOL_VERSION,
		"frame_id": frame_id,
		"gateway_session_id": "gateway-session/eg1/probe/%s" % frame_id.replace("/", "-"),
		"direction": direction,
		"channel": channel,
		"sequence": sequence,
		"payload_schema": payload_schema,
		"payload": payload,
	}


func _hello_payload(client_suffix: String) -> Dictionary:
	return {
		"client_session_id": "client-session/eg1/%s" % client_suffix,
		"logical_player_id": "player/eg1-%s" % client_suffix,
		"player_entity_id": "entity/eg1-player-%s" % client_suffix,
		"world_id": "world/main",
	}


func _hello_transport_frame(
		wire_session: String,
		sequence: int,
		client_suffix: String,
		mutation: String = ""
) -> Dictionary:
	var payload := _hello_payload(client_suffix)
	match mutation:
		"MISSING_PLAYER":
			payload.erase("logical_player_id")
		"CROSS_NAMESPACE_PLAYER":
			payload["logical_player_id"] = "entity/not-a-player"
		"EXTRA_FORBIDDEN_FIELD":
			payload["backend_endpoint"] = "127.0.0.1:7777"
	return {
		"frame_id": "frame/eg1/transport-hello/%d" % sequence,
		"session_id": wire_session,
		"sequence": sequence,
		"channel": "CONTROL",
		"delivery_mode": "RELIABLE_ORDERED",
		"payload_schema": "planet_simulator.protocol_frame_test_probe.v1",
		"payload": _client_world_frame(
				"frame/eg1/hello/%d" % sequence,
				"SESSION_CONTROL",
				"CLIENT_TO_WORLD",
				sequence,
				GatewayUtils.EG1_SESSION_HELLO_PAYLOAD_SCHEMA,
				payload),
	}


func _detach_transport_frame(wire_session: String, sequence: int, gateway_session_id: String) -> Dictionary:
	var frame := _client_world_frame(
			"frame/eg1/detach/%d" % sequence,
			"SESSION_CONTROL",
			"CLIENT_TO_WORLD",
			sequence,
			GatewayUtils.EG1_SESSION_DETACH_PAYLOAD_SCHEMA,
			{})
	frame["gateway_session_id"] = gateway_session_id
	return {
		"frame_id": "frame/eg1/transport-detach/%d" % sequence,
		"session_id": wire_session,
		"sequence": sequence,
		"channel": "CONTROL",
		"delivery_mode": "RELIABLE_ORDERED",
		"payload_schema": "planet_simulator.protocol_frame_test_probe.v1",
		"payload": frame,
	}


func _init() -> void:
	var table := RouteTable.new()
	var control := SessionControl.new()
	_assert(_err(control.configure("not-an-authority", SERVER_INSTANCE_ID)) == "INVALID_AUTHORITY_ID",
			"invalid authority id was accepted by configure")
	_assert(bool(control.configure(AUTHORITY_ID, SERVER_INSTANCE_ID).get("success", false)),
			"session control configure failed")

	# --- HELLO happy path ---
	var hello_a := control.handle_session_control(
			_hello_transport_frame("transport-session/eg1/wire-a", 4, "alpha"),
			table,
			"peer/enet/7/eg1-wire-a")
	_assert(bool(hello_a.get("success", false)), "hello attach failed: %s" % _err(hello_a))
	if bool(hello_a.get("success", false)):
		var details: Dictionary = hello_a["details"]
		_assert(String(details["action"]) == "ATTACH", "hello did not report ATTACH")
		var gateway_session_id := String(details["gateway_session_id"])
		_assert(gateway_session_id == "gateway-session/eg1/eg1-alpha/1",
				"minted gateway session id unexpected: %s" % gateway_session_id)
		var row: Dictionary = details["row"]
		_assert(String(row["client_transport_peer_id"]) == "peer/enet/7/eg1-wire-a",
				"row lost the transport-event peer id")
		_assert(String(row["binding"]["client_session_id"]) == "client-session/eg1/alpha",
				"row lost client_session_id from payload")
		_assert(String(row["binding"]["logical_player_id"]) == "player/eg1-alpha",
				"row lost logical_player_id from payload")
		_assert(String(row["binding"]["player_entity_id"]) == "entity/eg1-player-alpha",
				"row lost player_entity_id from payload")
		_assert(String(row["binding"]["world_id"]) == "world/main",
				"row lost world_id from payload")
		_assert(String(row["binding"]["state"]) == "ATTACHED", "attached row must start ATTACHED")
		_assert(String(row["route_binding"]["route_role"]) == "ACTIVE", "attached route must start ACTIVE")
		# identity namespace separation inside one row
		_assert(gateway_session_id.begins_with("gateway-session/")
				and String(row["binding"]["client_session_id"]).begins_with("client-session/")
				and String(row["client_transport_peer_id"]).begins_with("peer/enet/")
				and String(row["binding"]["logical_player_id"]).begins_with("player/")
				and String(row["binding"]["player_entity_id"]).begins_with("entity/")
				and typeof(row["session_slot"]) == TYPE_INT,
				"identity namespaces are not strictly separated in the attached row")
		# ack shapes
		var ack: Dictionary = details["ack"]
		_assert(bool(ClientWorldFrameScript.validate(ack).get("success", false)),
				"ATTACHED ack failed ClientWorldFrame validation")
		_assert(String(ack["direction"]) == "WORLD_TO_CLIENT", "ack must be WORLD_TO_CLIENT")
		_assert(String(ack["channel"]) == "SESSION_CONTROL", "ack channel mismatch")
		_assert(String(ack["gateway_session_id"]) == gateway_session_id, "ack bound to wrong session")
		_assert(int(ack["sequence"]) == 4, "ack did not mirror the request sequence")
		_assert(String(ack["payload_schema"]) == GatewayUtils.EG1_SESSION_ATTACHED_ACK_PAYLOAD_SCHEMA,
				"ack payload schema mismatch")
		_assert(String(ack["payload"]["gateway_session_id"]) == gateway_session_id, "ack payload session mismatch")
		_assert(int(ack["payload"]["session_slot"]) == int(row["session_slot"]), "ack slot mismatch")
		_assert(String(ack["payload"]["state"]) == "ATTACHED", "ack state mismatch")
		var ack_transport: Dictionary = details["ack_transport_frame"]
		_assert(String(ack_transport["session_id"]) == "transport-session/eg1/wire-a",
				"ack transport frame must echo the client wire session")
		_assert(String(ack_transport["channel"]) == "CONTROL", "ack physical channel must be CONTROL")
		_assert(String(ack_transport["delivery_mode"]) == "RELIABLE_ORDERED", "ack delivery mode mismatch")
		_assert(int(ack_transport["sequence"]) == 1, "first ack must use outgoing sequence 1")

	# --- minting counter keeps sessions unique ---
	var hello_b := control.handle_session_control(
			_hello_transport_frame("transport-session/eg1/wire-b", 1, "beta"),
			table,
			"peer/enet/8/eg1-wire-b")
	_assert(bool(hello_b.get("success", false)), "second hello attach failed")
	if bool(hello_b.get("success", false)):
		_assert(String(hello_b["details"]["gateway_session_id"]) == "gateway-session/eg1/eg1-beta/2",
				"mint counter did not advance")
		_assert(int(hello_b["details"]["ack_transport_frame"]["sequence"]) == 2,
				"ack outgoing sequence did not advance")

	# --- duplicate attach: same transport peer is rejected ---
	var dup_hello := control.handle_session_control(
			_hello_transport_frame("transport-session/eg1/wire-dup", 1, "dup"),
			table,
			"peer/enet/7/eg1-wire-a")
	_assert(_err(dup_hello) == "CLIENT_TRANSPORT_PEER_ALREADY_BOUND",
			"duplicate attach for the same transport peer was accepted: %s" % _err(dup_hello))

	# --- same client-session suffix on a new peer mints a NEW gateway session ---
	var hello_c := control.handle_session_control(
			_hello_transport_frame("transport-session/eg1/wire-c", 2, "alpha"),
			table,
			"peer/enet/9/eg1-wire-c")
	_assert(bool(hello_c.get("success", false)), "reattach with fresh peer failed")
	if bool(hello_c.get("success", false)):
		var reminted := String(hello_c["details"]["gateway_session_id"])
		_assert(reminted != "gateway-session/eg1/eg1-alpha/1" and reminted.begins_with("gateway-session/eg1/eg1-alpha/"),
				"reminted session collided with the released-or-live original: %s" % reminted)

	# --- invalid hello payloads stay fail-closed ---
	var missing_field := control.handle_session_control(
			_hello_transport_frame("transport-session/eg1/wire-x", 1, "x", "MISSING_PLAYER"),
			table,
			"peer/enet/10/eg1-wire-x")
	_assert(_err(missing_field) == "INVALID_CLIENT_PAYLOAD",
			"missing logical_player_id kept the wrong error: %s" % _err(missing_field))
	var bad_namespace := control.handle_session_control(
			_hello_transport_frame("transport-session/eg1/wire-y", 1, "y", "CROSS_NAMESPACE_PLAYER"),
			table,
			"peer/enet/11/eg1-wire-y")
	_assert(_err(bad_namespace) == "INVALID_CLIENT_PAYLOAD",
			"cross-namespace player id was accepted: %s" % _err(bad_namespace))
	var extra_field := control.handle_session_control(
			_hello_transport_frame("transport-session/eg1/wire-z", 1, "z", "EXTRA_FORBIDDEN_FIELD"),
			table,
			"peer/enet/12/eg1-wire-z")
	_assert(_err(extra_field) == "CLIENT_PAYLOAD_SCHEMA_VIOLATION",
			"unregistered extra field was admitted: %s" % _err(extra_field))

	# --- envelope fences: wrong channel / wrong direction / non-frame payload ---
	var wrong_channel: Dictionary = _hello_transport_frame("transport-session/eg1/wire-ch", 1, "ch")
	wrong_channel["payload"]["channel"] = "INPUT_MOVEMENT"
	_assert(_err(control.handle_session_control(wrong_channel, table, "peer/enet/13/x")) == "INVALID_CHANNEL",
			"non-SESSION_CONTROL frame reached session control")
	var wrong_direction: Dictionary = _hello_transport_frame("transport-session/eg1/wire-dir", 1, "dir")
	wrong_direction["payload"]["direction"] = "WORLD_TO_CLIENT"
	_assert(_err(control.handle_session_control(wrong_direction, table, "peer/enet/14/x")) == "INVALID_FRAME_DIRECTION",
			"WORLD_TO_CLIENT frame reached session control")
	var empty_payload: Dictionary = _hello_transport_frame("transport-session/eg1/wire-empty", 1, "empty")
	empty_payload["payload"] = {}
	_assert(_err(control.handle_session_control(empty_payload, table, "peer/enet/15/x")) == "INVALID_SESSION_CONTROL_FRAME",
			"non-frame payload was accepted by session control")

	# --- detach semantics ---
	var detach := control.handle_session_control(
			_detach_transport_frame("transport-session/eg1/wire-c", 5, "gateway-session/eg1/eg1-alpha/3"),
			table,
			"peer/enet/9/eg1-wire-c")
	_assert(bool(detach.get("success", false)), "detach failed: %s" % _err(detach))
	if bool(detach.get("success", false)):
		_assert(String(detach["details"]["action"]) == "DETACH", "detach did not report DETACH")
		var row: Dictionary = detach["details"]["row"]
		_assert(String(row["binding"]["state"]) == "DETACHED", "detach did not persist DETACHED")
		_assert(String(row["route_binding"]["route_role"]) == "DRAIN", "detach did not drain the route")
		_assert(_err(table.can_admit_frame("SESSION_CONTROL", String(detach["details"]["gateway_session_id"]))) == "GATEWAY_SESSION_DETACHED",
				"detached session still admitted SESSION_CONTROL")
		_assert(_err(table.can_admit_frame("WORLD_OPERATION", String(detach["details"]["gateway_session_id"]))) == "GATEWAY_SESSION_DETACHED",
				"detached session still admitted WORLD_OPERATION")
		var ack: Dictionary = detach["details"]["ack"]
		_assert(bool(ClientWorldFrameScript.validate(ack).get("success", false)),
				"DETACHED ack failed ClientWorldFrame validation")
		_assert(String(ack["payload_schema"]) == GatewayUtils.EG1_SESSION_DETACHED_ACK_PAYLOAD_SCHEMA,
				"detached ack payload schema mismatch")
		_assert(String(ack["payload"]["state"]) == "DETACHED", "detached ack state mismatch")
		_assert(not ack["payload"].has("session_slot"), "detached ack leaked unregistered fields")

	# --- unknown session ---
	var ghost_detach := control.handle_session_control(
			_detach_transport_frame("transport-session/eg1/wire-ghost", 1, "gateway-session/eg1/ghost/99"),
			table,
			"peer/enet/16/eg1-wire-ghost")
	_assert(_err(ghost_detach) == "UNKNOWN_GATEWAY_SESSION",
			"unknown session detach was accepted: %s" % _err(ghost_detach))

	# --- unsupported session-control schema ---
	var rogue: Dictionary = _hello_transport_frame("transport-session/eg1/wire-rogue", 1, "rogue")
	rogue["payload"]["payload_schema"] = "planet_simulator.test_snapshot.v1"
	rogue["payload"]["payload"] = {"revision": 1}
	_assert(_err(control.handle_session_control(rogue, table, "peer/enet/17/x")) == "UNSUPPORTED_SESSION_CONTROL_SCHEMA",
			"non-session-control schema was handled by session control")

	# --- live rows survive: alpha/1 and beta/2 remain attached, alpha/3 detached ---
	_assert(table.session_count() >= 2, "live session rows disappeared")
	_assert(String(table.lookup("gateway-session/eg1/eg1-beta/2")["details"]["row"]["binding"]["state"]) == "ATTACHED",
			"unrelated session was mutated by detach traffic")

	_finish()


func _finish() -> void:
	var summary := {
		"test": "eg1_gateway_session_control_l0",
		"verdict": "PASS" if failures.is_empty() else "FAIL",
		"assertions": assertions,
		"failures": failures,
	}
	print(JSON.stringify(summary))
	if failures.is_empty():
		print("[eg1-session-control] L0 PASS (%d assertions)" % assertions)
		quit(0)
	else:
		print("[eg1-session-control] L0 FAIL")
		quit(1)

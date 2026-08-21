extends SceneTree

## EG1 forwarder unit contracts: verbatim OperationId/frame passthrough,
## envelope binding to the route row, drop accounting, channel mapping.

const RouteTable = preload("res://scripts/network/gateway/runtime/eg1_gateway_route_table.gd")
const Forwarder = preload("res://scripts/network/gateway/runtime/eg1_gateway_forwarder.gd")
const ClientWorldFrameScript = preload("res://scripts/network/gateway/client_world_frame.gd")
const IngressEnvelopeScript = preload("res://scripts/network/gateway/gateway_ingress_envelope.gd")
const EgressEnvelopeScript = preload("res://scripts/network/gateway/gateway_egress_envelope.gd")

const GATEWAY_ID := "gateway/eg1/spike"
const BACKEND_SESSION := "transport-session/eg1/backend-sim-a"

var assertions := 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[eg1-forwarder][FAIL] %s" % message)


func _err(result: Dictionary) -> String:
	return String(result.get("error_code", ""))


func _client_frame(sequence: int, operation_id: String) -> Dictionary:
	return ClientWorldFrameScript.create(
			"frame/eg1/client-op/%d" % sequence,
			"gateway-session/eg1/fwd",
			"CLIENT_TO_WORLD",
			"WORLD_OPERATION",
			sequence,
			"planet_simulator.test_world_operation.v1",
			{"operation_id": operation_id, "command": "mine_tile", "target_id": "entity/eg1-tile-17"}
	)


func _init() -> void:
	var table := RouteTable.new()
	var attach := table.attach(
			"gateway-session/eg1/fwd",
			"peer/enet/eg1-fwd-client",
			"client-session/eg1/fwd",
			"player/eg1-fwd",
			"entity/eg1-player-fwd",
			"world/main",
			"authority/sim-a",
			"server-instance/sim-a-eg0"
	)
	_assert(bool(attach.get("success", false)), "attach failed: %s" % _err(attach))
	var backend_link := "backend-link/eg1/sim-a"
	_assert(bool(table.bind_backend_link("gateway-session/eg1/fwd", backend_link).get("success", false)), "backend link bind failed")

	var forwarder := Forwarder.new()
	_assert(bool(forwarder.configure(GATEWAY_ID).get("success", false)), "forwarder configure failed")

	# --- published channel mapping is total and deterministic ---
	for channel in ["SESSION_CONTROL", "INPUT_MOVEMENT", "AUTHORITATIVE_SNAPSHOT", "WORLD_OPERATION", "RECOVERY_FULL_STATE", "TELEMETRY", "WORLD_PROJECTION"]:
		_assert(not Forwarder.physical_channel_for(channel).is_empty(), "channel mapping incomplete for %s" % channel)
	_assert(Forwarder.physical_channel_for("WORLD_OPERATION") == "ITEM", "WORLD_OPERATION must map to ITEM")
	_assert(Forwarder.physical_channel_for("INPUT_MOVEMENT") == "INPUT", "INPUT_MOVEMENT must map to INPUT")
	_assert(Forwarder.delivery_mode_for("INPUT_MOVEMENT") == "UNRELIABLE_SEQUENCED", "input must stay unreliable-sequenced")
	_assert(Forwarder.delivery_mode_for("WORLD_OPERATION") == "RELIABLE_ORDERED", "operations must stay reliable")

	# --- ingress: frame passes through with identity intact ---
	var upstream := {
		"frame_id": "frame/eg1/transport/up/1",
		"session_id": "client-session/eg1/wire",
		"sequence": 1,
		"channel": "ITEM",
		"delivery_mode": "RELIABLE_ORDERED",
		"payload_schema": "planet_simulator.client_world_frame.v1",
		"payload": _client_frame(7, "operation/eg1/fwd/0001"),
	}
	var c2w := forwarder.forward_client_to_world(upstream, table, BACKEND_SESSION)
	_assert(bool(c2w.get("success", false)), "ingress forward failed: %s" % str(c2w))
	if bool(c2w.get("success", false)):
		var backend_frame: Dictionary = c2w["details"]["backend_frame"]
		_assert(String(backend_frame["session_id"]) == BACKEND_SESSION, "backend frame must use the backend session id")
		_assert(String(backend_frame["channel"]) == "ITEM", "backend physical channel mismatch")
		_assert(String(backend_frame["payload_schema"]) == Forwarder.INGRESS_PAYLOAD_SCHEMA, "backend payload schema must be the ingress envelope")
		var envelope: Dictionary = backend_frame["payload"]
		_assert(bool(IngressEnvelopeScript.validate(envelope).get("success", false)), "produced ingress envelope failed validation")
		_assert(String(envelope["backend_link_id"]) == backend_link, "envelope did not bind the backend link")
		_assert(int(envelope["session_slot"]) == int(attach["details"]["row"]["session_slot"]), "envelope slot mismatch")
		_assert(int(envelope["route_revision"]) == 1, "envelope route revision mismatch")
		_assert(String(envelope["route_role"]) == "ACTIVE", "envelope role mismatch")
		_assert(String(envelope["frame"]["payload"]["operation_id"]) == "operation/eg1/fwd/0001", "OperationId corrupted on ingress")
		_assert(String(c2w["details"]["operation_id"]) == "operation/eg1/fwd/0001", "ingress result lost OperationId")

	# --- egress mirror ---
	var inner_down := ClientWorldFrameScript.create(
			"frame/eg1/client-down/1",
			"gateway-session/eg1/fwd",
			"WORLD_TO_CLIENT",
			"WORLD_OPERATION",
			9,
			"planet_simulator.test_world_operation.v1",
			{"operation_id": "operation/eg1/fwd/0001", "command": "result", "target_id": "entity/eg1-tile-17"}
	)
	var egress_envelope := EgressEnvelopeScript.create(
			"gateway-envelope/eg1/w2c/1",
			GATEWAY_ID,
			backend_link,
			"gateway-session/eg1/fwd",
			int(attach["details"]["row"]["session_slot"]),
			1,
			1,
			"authority/sim-a",
			"server-instance/sim-a-eg0",
			"ACTIVE",
			inner_down
	)
	var downstream := {
		"frame_id": "frame/eg1/transport/down/1",
		"session_id": BACKEND_SESSION,
		"sequence": 2,
		"channel": "ITEM",
		"delivery_mode": "RELIABLE_ORDERED",
		"payload_schema": Forwarder.EGRESS_PAYLOAD_SCHEMA,
		"payload": egress_envelope,
	}
	var w2c := forwarder.forward_world_to_client(downstream, table)
	_assert(bool(w2c.get("success", false)), "egress forward failed: %s" % str(w2c))
	if bool(w2c.get("success", false)):
		_assert(String(w2c["details"]["client_transport_peer_id"]) == "peer/enet/eg1-fwd-client", "egress resolved wrong client peer")
		var client_frame: Dictionary = w2c["details"]["client_transport_frame"]["payload"]
		_assert(String(client_frame["payload"]["operation_id"]) == "operation/eg1/fwd/0001", "OperationId corrupted on egress")
		_assert(int(client_frame["sequence"]) == 9, "frame sequence altered on egress")
		_assert(String(client_frame["direction"]) == "WORLD_TO_CLIENT", "egress direction must be WORLD_TO_CLIENT")

	# --- drop accounting ---
	var bad_frame := upstream.duplicate(true)
	bad_frame["payload"] = _client_frame(8, "operation/eg1/fwd/0002")
	bad_frame["payload"]["gateway_session_id"] = "gateway-session/eg1/unknown"
	var unknown := forwarder.forward_client_to_world(bad_frame, table, BACKEND_SESSION)
	_assert(_err(unknown) == "UNKNOWN_GATEWAY_SESSION", "unknown session was not rejected: %s" % _err(unknown))
	table.set_route_role("gateway-session/eg1/fwd", "WARM")
	var warm_drop := forwarder.forward_client_to_world(upstream, table, BACKEND_SESSION)
	_assert(_err(warm_drop) == "ROUTE_ROLE_REJECTS_MUTATIONS", "WARM route admitted a mutation: %s" % _err(warm_drop))
	var counters := forwarder.get_counters()
	_assert(int(counters["forwarded_client_to_world"]) == 1 and int(counters["forwarded_world_to_client"]) == 1, "forward counters wrong: %s" % str(counters))
	_assert(int(counters["dropped_client_to_world"]) == 2, "drop counter wrong")
	_assert(int(counters["drop_reasons"].get("UNKNOWN_GATEWAY_SESSION", 0)) == 1, "per-reason drop accounting wrong")
	_assert(int(counters["drop_reasons"].get("ROUTE_ROLE_REJECTS_MUTATIONS", 0)) == 1, "per-reason drop accounting wrong (role)")

	_finish()


func _finish() -> void:
	var summary := {
		"test": "eg1_gateway_forwarder_l0",
		"verdict": "PASS" if failures.is_empty() else "FAIL",
		"assertions": assertions,
		"failures": failures,
	}
	print(JSON.stringify(summary))
	if failures.is_empty():
		print("[eg1-forwarder] L0 PASS (%d assertions)" % assertions)
		quit(0)
	else:
		print("[eg1-forwarder] L0 FAIL")
		quit(1)

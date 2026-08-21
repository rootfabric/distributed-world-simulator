extends RefCounted

## EG1 session control: the minimal SESSION_CONTROL plane over the route table.
##
## HELLO  -> mint a gateway_session_id ("gateway-session/eg1/<client-session
##           suffix>/<counter>"), attach the route/session row (client transport
##           peer id comes from the transport event, identity fields come from
##           the registered hello payload), and emit a WORLD_TO_CLIENT
##           SESSION_CONTROL ATTACHED ack.
## DETACH -> flip the binding state to DETACHED (which also drains the route)
##           and emit a DETACHED ack. The row itself stays until an explicit
##           release so in-flight egress can still be accounted.
##
## Session control is the only EG1 component allowed to mutate route-table
## state, and it never interprets domain payloads: the hello payload carries
## identity namespaces only.

const ClientWorldFrameScript = preload("res://scripts/network/gateway/client_world_frame.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")
const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SESSION_CONTROL_SCHEMA := "planet_simulator.eg1_gateway_session_control.v1"
const HELLO_PAYLOAD_SCHEMA: String = GatewayUtilsScript.EG1_SESSION_HELLO_PAYLOAD_SCHEMA
const DETACH_PAYLOAD_SCHEMA: String = GatewayUtilsScript.EG1_SESSION_DETACH_PAYLOAD_SCHEMA
const ATTACHED_ACK_PAYLOAD_SCHEMA: String = GatewayUtilsScript.EG1_SESSION_ATTACHED_ACK_PAYLOAD_SCHEMA
const DETACHED_ACK_PAYLOAD_SCHEMA: String = GatewayUtilsScript.EG1_SESSION_DETACHED_ACK_PAYLOAD_SCHEMA

const GATEWAY_SESSION_PREFIX := "gateway-session/eg1/"
const CLIENT_SESSION_PREFIX := "client-session/"

var authority_id := ""
var server_instance_id := ""
var _mint_counter: int = 0
var _ack_frame_counter: int = 0
var _ack_sequence: int = 0


func configure(p_authority_id: String, p_server_instance_id: String) -> Dictionary:
	var authority_check: Dictionary = GatewayUtilsScript.require_id(
			{"authority_id": p_authority_id}, "authority_id", "authority")
	if not bool(authority_check.get("success", false)):
		return _failure("INVALID_AUTHORITY_ID", {"authority_id": p_authority_id})
	var instance_check: Dictionary = GatewayUtilsScript.require_id(
			{"server_instance_id": p_server_instance_id}, "server_instance_id", "server-instance")
	if not bool(instance_check.get("success", false)):
		return _failure("INVALID_SERVER_INSTANCE_ID", {"server_instance_id": p_server_instance_id})
	authority_id = p_authority_id
	server_instance_id = p_server_instance_id
	return _success({})


## Handle one client-facing SESSION_CONTROL transport frame.
## client_transport_peer_id is the server-side logical peer id taken from the
## transport event (never trusted from the wire payload).
func handle_session_control(
		transport_frame: Dictionary,
		route_table,
		client_transport_peer_id: String
) -> Dictionary:
	var envelope_check := _validate_frame_envelope(transport_frame.get("payload", {}))
	if not bool(envelope_check.get("success", false)):
		return _failure(
				String(envelope_check.get("error_code", "INVALID_SESSION_CONTROL_FRAME")),
				{"message": String(envelope_check.get("message", ""))})
	var frame: Dictionary = transport_frame["payload"]
	var wire_session := String(transport_frame["session_id"])
	var payload_schema := String(frame["payload_schema"])
	match payload_schema:
		HELLO_PAYLOAD_SCHEMA:
			return _handle_hello(frame, route_table, client_transport_peer_id, wire_session)
		DETACH_PAYLOAD_SCHEMA:
			return _handle_detach(frame, route_table, wire_session)
		_:
			return _failure("UNSUPPORTED_SESSION_CONTROL_SCHEMA", {"payload_schema": payload_schema})


func _handle_hello(frame: Dictionary, route_table, client_transport_peer_id: String, wire_session: String) -> Dictionary:
	var payload: Dictionary = frame["payload"]
	var payload_check: Dictionary = GatewayUtilsScript.validate_client_surface_payload(
			payload, HELLO_PAYLOAD_SCHEMA)
	if not bool(payload_check.get("success", false)):
		return _failure(
				String(payload_check.get("error_code", "INVALID_SESSION_HELLO")),
				{"message": String(payload_check.get("message", ""))})
	var client_session_id := String(payload["client_session_id"])
	# The mint counter is only committed when the attach actually succeeds so
	# rejected hellos never burn gateway-session ids.
	var gateway_session_id := "%s%s/%d" % [
		GATEWAY_SESSION_PREFIX,
		client_session_id.trim_prefix(CLIENT_SESSION_PREFIX).replace("/", "-"),
		_mint_counter + 1,
	]
	var attach: Dictionary = route_table.attach(
			gateway_session_id,
			client_transport_peer_id,
			client_session_id,
			String(payload["logical_player_id"]),
			String(payload["player_entity_id"]),
			String(payload["world_id"]),
			authority_id,
			server_instance_id
	)
	if not bool(attach.get("success", false)):
		return _failure(
				String(attach.get("error_code", "ATTACH_FAILED")),
				attach.get("details", {}))
	_mint_counter += 1
	var row: Dictionary = attach["details"]["row"]
	var ack := _ack_frame(
			wire_session,
			gateway_session_id,
			int(frame["sequence"]),
			ATTACHED_ACK_PAYLOAD_SCHEMA,
			{
				"gateway_session_id": gateway_session_id,
				"session_slot": int(row["session_slot"]),
				"state": "ATTACHED",
			}
	)
	return _success({
		"action": "ATTACH",
		"gateway_session_id": gateway_session_id,
		"row": row,
		"ack": ack["frame"],
		"ack_transport_frame": ack["transport_frame"],
	})


func _handle_detach(frame: Dictionary, route_table, wire_session: String) -> Dictionary:
	var gateway_session_id := String(frame["gateway_session_id"])
	var payload: Dictionary = frame["payload"]
	var payload_check: Dictionary = GatewayUtilsScript.validate_client_surface_payload(
			payload, DETACH_PAYLOAD_SCHEMA)
	if not bool(payload_check.get("success", false)):
		return _failure(
				String(payload_check.get("error_code", "INVALID_SESSION_DETACH")),
				{"message": String(payload_check.get("message", ""))})
	var lookup: Dictionary = route_table.lookup(gateway_session_id)
	if not bool(lookup.get("success", false)):
		return _failure(
				String(lookup.get("error_code", "UNKNOWN_GATEWAY_SESSION")),
				lookup.get("details", {}))
	var detach: Dictionary = route_table.set_binding_state(gateway_session_id, "DETACHED")
	if not bool(detach.get("success", false)):
		return _failure(
				String(detach.get("error_code", "DETACH_FAILED")),
				detach.get("details", {}))
	var row: Dictionary = route_table.lookup(gateway_session_id)["details"]["row"]
	var ack := _ack_frame(
			wire_session,
			gateway_session_id,
			int(frame["sequence"]),
			DETACHED_ACK_PAYLOAD_SCHEMA,
			{
				"gateway_session_id": gateway_session_id,
				"state": "DETACHED",
			}
	)
	return _success({
		"action": "DETACH",
		"gateway_session_id": gateway_session_id,
		"row": row,
		"ack": ack["frame"],
		"ack_transport_frame": ack["transport_frame"],
	})


## Structural validation of the ClientWorldFrame envelope carrying session
## control. Pre-attach HELLO frames cannot pass the full frame validator
## because no gateway_session_id has been minted yet, so session control
## validates exactly the fields it owns and leaves the assigned id to the
## mint step.
func _validate_frame_envelope(frame) -> Dictionary:
	if frame is Dictionary == false or Dictionary(frame).is_empty():
		return NetworkUtilsScript.validation_failure("INVALID_SESSION_CONTROL_FRAME", "payload must be a non-empty Dictionary")
	var value: Dictionary = Dictionary(frame)
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, ClientWorldFrameScript.FIELDS)
	if not bool(exact.get("success", false)):
		return NetworkUtilsScript.validation_failure("INVALID_SESSION_CONTROL_FRAME", "unexpected ClientWorldFrame fields")
	for check in [
		GatewayUtilsScript.validate_schema(value, ClientWorldFrameScript.SCHEMA),
		GatewayUtilsScript.require_id(value, "frame_id", "frame"),
		GatewayUtilsScript.require_enum(value, "direction", GatewayUtilsScript.DIRECTIONS),
		GatewayUtilsScript.require_positive_integer(value, "sequence"),
		GatewayUtilsScript.require_payload_schema(value),
	]:
		if not bool(check.get("success", false)):
			return check
	if String(value["direction"]) != "CLIENT_TO_WORLD":
		return NetworkUtilsScript.validation_failure("INVALID_FRAME_DIRECTION", "session control must be CLIENT_TO_WORLD")
	if String(value["channel"]) != "SESSION_CONTROL":
		return NetworkUtilsScript.validation_failure("INVALID_CHANNEL", "session control requires the SESSION_CONTROL channel")
	return NetworkUtilsScript.validation_success()


func _ack_frame(wire_session: String, gateway_session_id: String, request_sequence: int, payload_schema: String, payload: Dictionary) -> Dictionary:
	_ack_frame_counter += 1
	var ack := ClientWorldFrameScript.create(
			"frame/eg1/session-ack/%d" % _ack_frame_counter,
			gateway_session_id,
			"WORLD_TO_CLIENT",
			"SESSION_CONTROL",
			maxi(request_sequence, 1),
			payload_schema,
			payload
	)
	_ack_sequence += 1
	var transport_frame := {
		"frame_id": "frame/eg1/session-ack-transport/%d" % _ack_frame_counter,
		"session_id": wire_session,
		"sequence": _ack_sequence,
		"channel": "CONTROL",
		"delivery_mode": "RELIABLE_ORDERED",
		"payload_schema": payload_schema,
		"payload": ack.duplicate(true),
	}
	return {"frame": ack, "transport_frame": transport_frame}


func _success(details: Dictionary) -> Dictionary:
	return {"success": true, "details": details}


func _failure(error_code: String, details: Dictionary) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details}

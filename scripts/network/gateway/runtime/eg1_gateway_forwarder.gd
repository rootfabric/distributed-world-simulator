extends RefCounted

## EG1 forwarder: the gateway's data plane.
##
## CLIENT_TO_WORLD: extract the ClientWorldFrame DTO from the client-facing
## transport frame, validate it, check route-table admission, wrap it in a
## GatewayIngressEnvelope bound to the session row, and reframe it for the
## backend leg.
##
## WORLD_TO_CLIENT: extract the GatewayEgressEnvelope from the backend frame,
## validate it, resolve the session row, and reframe the inner ClientWorldFrame
## for delivery to the client-facing transport peer.
##
## The forwarder never interprets domain payloads: it forwards operation ids,
## sequences and payload bytes verbatim. Counters are the only side effects.

const ClientWorldFrameScript = preload("res://scripts/network/gateway/client_world_frame.gd")
const IngressEnvelopeScript = preload("res://scripts/network/gateway/gateway_ingress_envelope.gd")
const EgressEnvelopeScript = preload("res://scripts/network/gateway/gateway_egress_envelope.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")

const FORWARDER_SCHEMA := "planet_simulator.eg1_gateway_forwarder.v1"
const INGRESS_PAYLOAD_SCHEMA := "planet_simulator.gateway_ingress_envelope.v1"
const EGRESS_PAYLOAD_SCHEMA := "planet_simulator.gateway_egress_envelope.v1"

var gateway_instance_id := ""
var _envelope_counter := 0
var _counters := {
	"forwarded_client_to_world": 0,
	"forwarded_world_to_client": 0,
	"dropped_client_to_world": 0,
	"dropped_world_to_client": 0,
	"drop_reasons": {},
}


func configure(p_gateway_instance_id: String) -> Dictionary:
	if not p_gateway_instance_id.begins_with("gateway/"):
		return _failure("INVALID_GATEWAY_INSTANCE_ID", {"gateway_instance_id": p_gateway_instance_id})
	gateway_instance_id = p_gateway_instance_id
	return _success({})


func forward_client_to_world(transport_frame: Dictionary, route_table, backend_session_id: String) -> Dictionary:
	var payload: Dictionary = transport_frame.get("payload", {})
	var frame_check := ClientWorldFrameScript.validate(payload)
	if not bool(frame_check.get("success", false)):
		return _drop("client_to_world", String(frame_check.get("error_code", "INVALID_CLIENT_WORLD_FRAME")), {"detail": frame_check.get("details", {})})
	var gateway_session_id := String(payload["gateway_session_id"])
	var admission: Dictionary = route_table.can_admit_frame(String(payload["channel"]), gateway_session_id)
	if not bool(admission.get("success", false)):
		return _drop("client_to_world", String(admission.get("error_code", "ADMISSION_DENIED")), {"detail": admission.get("details", {})})
	var row: Dictionary = route_table.lookup(gateway_session_id)["details"]["row"]
	_envelope_counter += 1
	var envelope := IngressEnvelopeScript.create(
			"gateway-envelope/eg1/c2w/%d" % _envelope_counter,
			gateway_instance_id,
			String(row["backend_link_id"]),
			gateway_session_id,
			int(row["session_slot"]),
			int(row["route_binding"]["route_revision"]),
			int(row["route_binding"]["observed_authority_epoch"]),
			String(row["route_binding"]["authority_id"]),
			String(row["route_binding"]["server_instance_id"]),
			String(row["route_binding"]["route_role"]),
			payload
	)
	var envelope_check := IngressEnvelopeScript.validate(envelope)
	if not bool(envelope_check.get("success", false)):
		return _drop("client_to_world", String(envelope_check.get("error_code", "INVALID_INGRESS_ENVELOPE")), {"detail": envelope_check.get("details", {})})
	var backend_frame := _reframe(
			"frame/eg1/backend/%d" % _envelope_counter,
			backend_session_id,
			String(payload["channel"]),
			INGRESS_PAYLOAD_SCHEMA,
			envelope
	)
	if backend_frame.is_empty():
		return _drop("client_to_world", "UNMAPPED_CLIENT_CHANNEL", {"channel": String(payload["channel"])})
	_counters["forwarded_client_to_world"] = int(_counters["forwarded_client_to_world"]) + 1
	return _success({
		"backend_frame": backend_frame,
		"envelope_id": String(envelope["envelope_id"]),
		"operation_id": String(payload.get("payload", {}).get("operation_id", "")),
		"gateway_session_id": gateway_session_id,
		"session_slot": int(row["session_slot"]),
	})


func forward_world_to_client(transport_frame: Dictionary, route_table) -> Dictionary:
	var payload: Dictionary = transport_frame.get("payload", {})
	var envelope_check := EgressEnvelopeScript.validate(payload)
	if not bool(envelope_check.get("success", false)):
		return _drop("world_to_client", String(envelope_check.get("error_code", "INVALID_EGRESS_ENVELOPE")), {"detail": envelope_check.get("details", {})})
	var gateway_session_id := String(payload["gateway_session_id"])
	var lookup: Dictionary = route_table.lookup(gateway_session_id)
	if not bool(lookup.get("success", false)):
		return _drop("world_to_client", "UNKNOWN_GATEWAY_SESSION", {"gateway_session_id": gateway_session_id})
	var row: Dictionary = lookup["details"]["row"]
	if String(row["binding"]["state"]) == "DETACHED":
		return _drop("world_to_client", "GATEWAY_SESSION_DETACHED", {"gateway_session_id": gateway_session_id})
	var inner: Dictionary = payload["frame"]
	var frame_check := ClientWorldFrameScript.validate(inner)
	if not bool(frame_check.get("success", false)):
		return _drop("world_to_client", String(frame_check.get("error_code", "INVALID_CLIENT_WORLD_FRAME")), {"detail": frame_check.get("details", {})})
	var client_frame := ClientWorldFrameScript.create(
			String(inner["frame_id"]),
			gateway_session_id,
			"WORLD_TO_CLIENT",
			String(inner["channel"]),
			int(inner["sequence"]),
			String(inner["payload_schema"]),
			inner.get("payload", {})
	)
	var reframe_check := ClientWorldFrameScript.validate(client_frame)
	if not bool(reframe_check.get("success", false)):
		return _drop("world_to_client", String(reframe_check.get("error_code", "INVALID_EGRESS_REFRAME")), {"detail": reframe_check.get("details", {})})
	_envelope_counter += 1
	var client_transport_frame := _reframe(
			"frame/eg1/client/%d" % _envelope_counter,
			gateway_session_id,
			String(client_frame["channel"]),
			String(client_frame["payload_schema"]),
			client_frame
	)
	if client_transport_frame.is_empty():
		return _drop("world_to_client", "UNMAPPED_CLIENT_CHANNEL", {"channel": String(client_frame["channel"])})
	_counters["forwarded_world_to_client"] = int(_counters["forwarded_world_to_client"]) + 1
	return _success({
		"client_frame": client_frame,
		"client_transport_frame": client_transport_frame,
		"client_transport_peer_id": String(row["client_transport_peer_id"]),
		"gateway_session_id": gateway_session_id,
		"session_slot": int(row["session_slot"]),
	})


func get_counters() -> Dictionary:
	return _counters.duplicate(true)


## EG1 published channel mapping: client-facing semantic channel -> ENET physical
## channel. Deterministic and fail-closed. Delegates to the shared contract
## utils so sim-side endpoints encode the same mapping without touching the
## gateway runtime.
static func physical_channel_for(client_channel: String) -> String:
	return GatewayUtilsScript.eg1_physical_channel_for(client_channel)


static func delivery_mode_for(client_channel: String) -> String:
	return GatewayUtilsScript.eg1_delivery_mode_for(client_channel)


func _reframe(frame_id: String, session_id: String, client_channel: String, payload_schema: String, payload: Dictionary) -> Dictionary:
	var physical_channel := physical_channel_for(client_channel)
	if physical_channel.is_empty():
		return {}
	return {
		"frame_id": frame_id,
		"session_id": session_id,
		"sequence": 1,
		"channel": physical_channel,
		"delivery_mode": delivery_mode_for(client_channel),
		"payload_schema": payload_schema,
		"payload": payload.duplicate(true),
	}


func _drop(direction: String, error_code: String, details: Dictionary) -> Dictionary:
	var key := "dropped_" + direction
	_counters[key] = int(_counters[key]) + 1
	var reasons: Dictionary = _counters["drop_reasons"]
	reasons[error_code] = int(reasons.get(error_code, 0)) + 1
	return _failure(error_code, details)


func _success(details: Dictionary) -> Dictionary:
	return {"success": true, "details": details}


func _failure(error_code: String, details: Dictionary) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details}

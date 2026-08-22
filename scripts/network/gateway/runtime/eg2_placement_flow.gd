extends RefCounted

## EG2 placement flow: orchestrates AUTHENTICATE -> CREATE_OR_RESUME_SESSION ->
## RESOLVE_CURRENT_AUTHORITY (directory truth) -> route attach pointing at that
## authority/server instance -> WORLD_READY, on top of the EG1 gateway parts
## (route table + node backend leg).
##
## Endpoint discipline: the ONLY client-delivered payloads this module builds
## are the registered EG2 acks — identifiers and placement summary fields,
## never a host/port endpoint. The directory resolution never leaves the
## gateway side; clients see its identifier projection exclusively.
##
## Cache discipline: _last_known_resolution is a DERIVED CACHE used only to
## degrade gracefully during a directory outage (route role WARM: mutations are
## rejected until the directory is restored). It is never ownership truth.
##
## Identity discipline: logical identity comes from the auth service's grant;
## resumes preserve it across new gateway sessions and new transport peers.

const ClientWorldFrameScript = preload("res://scripts/network/gateway/client_world_frame.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")
const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const PLACEMENT_FLOW_SCHEMA := "planet_simulator.eg2_placement_flow.v1"
const AUTHENTICATE_PAYLOAD_SCHEMA: String = GatewayUtilsScript.EG2_SESSION_AUTHENTICATE_PAYLOAD_SCHEMA
const PLACE_REQUEST_PAYLOAD_SCHEMA: String = GatewayUtilsScript.EG2_SESSION_PLACE_REQUEST_PAYLOAD_SCHEMA
const AUTH_ACK_PAYLOAD_SCHEMA: String = GatewayUtilsScript.EG2_SESSION_AUTH_ACK_PAYLOAD_SCHEMA
const WORLD_READY_ACK_PAYLOAD_SCHEMA: String = GatewayUtilsScript.EG2_WORLD_READY_ACK_PAYLOAD_SCHEMA
const PLACEMENT_DEGRADED_ACK_PAYLOAD_SCHEMA: String = GatewayUtilsScript.EG2_PLACEMENT_DEGRADED_ACK_PAYLOAD_SCHEMA

var _auth_service
var _directory
var _auth_by_peer: Dictionary = {}
var _live_placement_by_client_session: Dictionary = {}
var _last_known_resolution: Dictionary = {}
var _ack_frame_counter: int = 0
# Transport-level ack sequences are PER CLIENT WIRE SESSION: the client
# boundary enforces gap-free outgoing sequencing per peer, so a single global
# counter would strand every ack after the first client's exchanges.
var _ack_sequence_by_wire_session: Dictionary = {}
var _counters := {
	"authenticate_frames": 0,
	"authenticate_ok": 0,
	"authenticate_rejected": 0,
	"place_requests": 0,
	"placements_created": 0,
	"placements_resumed": 0,
	"placements_degraded_warm": 0,
	"placements_pending": 0,
	"placement_frames_rejected": 0,
}


func configure(p_auth_service, p_directory) -> Dictionary:
	if p_auth_service == null or not p_auth_service.has_method("create_or_resume_session"):
		return _failure("INVALID_AUTH_SERVICE", {})
	if p_directory == null or not p_directory.has_method("resolve_current_authority"):
		return _failure("INVALID_DIRECTORY", {})
	_auth_service = p_auth_service
	_directory = p_directory
	return _success({})


## Handle one client-facing SESSION_CONTROL transport frame on behalf of the
## gateway node. client_transport_peer_id is the server-side transport-event
## peer id (never trusted from the wire). Unsupported schemas fail with
## UNSUPPORTED_SESSION_CONTROL_SCHEMA so additive handler chains keep working.
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
	var payload_schema := String(frame["payload_schema"])
	match payload_schema:
		AUTHENTICATE_PAYLOAD_SCHEMA:
			return _handle_authenticate(transport_frame, frame, client_transport_peer_id)
		PLACE_REQUEST_PAYLOAD_SCHEMA:
			return _handle_place_request(transport_frame, frame, route_table, client_transport_peer_id)
		_:
			return _failure("UNSUPPORTED_SESSION_CONTROL_SCHEMA", {"payload_schema": payload_schema})


func get_report() -> Dictionary:
	var live_placements: Array = []
	for client_session_id in _live_placement_by_client_session.keys():
		var entry: Dictionary = _live_placement_by_client_session[client_session_id]
		live_placements.append({
			"client_session_id": String(client_session_id),
			"gateway_session_id": String(entry["gateway_session_id"]),
			"world_id": String(entry["world_id"]),
		})
	var cached_resolutions: Array = []
	for world_id in _last_known_resolution.keys():
		var resolution: Dictionary = _last_known_resolution[world_id]
		cached_resolutions.append({
			"world_id": String(world_id),
			"authority_id": String(resolution["authority_id"]),
			"server_instance_id": String(resolution["server_instance_id"]),
			"catalog_revision": int(resolution["catalog_revision"]),
		})
	return {
		"schema": PLACEMENT_FLOW_SCHEMA,
		"counters": _counters.duplicate(true),
		"cache_status": "DERIVED_CACHE_NOT_OWNERSHIP_TRUTH",
		"live_placements": live_placements,
		"cached_resolutions": cached_resolutions,
	}


## ---- authenticate -----------------------------------------------------------


func _handle_authenticate(transport_frame: Dictionary, frame: Dictionary, client_transport_peer_id: String) -> Dictionary:
	_counters["authenticate_frames"] = int(_counters["authenticate_frames"]) + 1
	var payload: Dictionary = frame["payload"]
	var payload_check: Dictionary = GatewayUtilsScript.validate_client_surface_payload(
			payload, AUTHENTICATE_PAYLOAD_SCHEMA)
	if not bool(payload_check.get("success", false)):
		_counters["placement_frames_rejected"] = int(_counters["placement_frames_rejected"]) + 1
		return _failure(
				String(payload_check.get("error_code", "INVALID_SESSION_AUTH")),
				{"message": String(payload_check.get("message", ""))})
	var client_session_id := String(payload["client_session_id"])
	var ticket_id := String(payload["ticket_id"])
	var result: Dictionary = _auth_service.authenticate(ticket_id)
	var ticket_status := "OK"
	if bool(result.get("success", false)):
		_counters["authenticate_ok"] = int(_counters["authenticate_ok"]) + 1
	else:
		_counters["authenticate_rejected"] = int(_counters["authenticate_rejected"]) + 1
		match String(result.get("error_code", "")):
			"TICKET_REUSED":
				ticket_status = "REUSED"
			"TICKET_EXPIRED":
				ticket_status = "EXPIRED"
			_:
				ticket_status = "UNKNOWN_TICKET"
	if ticket_status == "OK":
		# Bind this transport peer to the authenticated pair; placement must
		# present exactly this pair afterwards.
		_auth_by_peer[client_transport_peer_id] = {
			"client_session_id": client_session_id,
			"ticket_id": ticket_id,
		}
	var ack := _ack_frame(
			String(transport_frame["session_id"]),
			String(frame["gateway_session_id"]),
			int(frame["sequence"]),
			AUTH_ACK_PAYLOAD_SCHEMA,
			{
				"client_session_id": client_session_id,
				"ticket_status": ticket_status,
			})
	return _success({
		"action": "AUTHENTICATE",
		"ticket_status": ticket_status,
		"ack": ack["frame"],
		"ack_transport_frame": ack["transport_frame"],
	})


## ---- place ------------------------------------------------------------------


func _handle_place_request(transport_frame: Dictionary, frame: Dictionary, route_table, client_transport_peer_id: String) -> Dictionary:
	_counters["place_requests"] = int(_counters["place_requests"]) + 1
	var payload: Dictionary = frame["payload"]
	var payload_check: Dictionary = GatewayUtilsScript.validate_client_surface_payload(
			payload, PLACE_REQUEST_PAYLOAD_SCHEMA)
	if not bool(payload_check.get("success", false)):
		_counters["placement_frames_rejected"] = int(_counters["placement_frames_rejected"]) + 1
		return _failure(
				String(payload_check.get("error_code", "INVALID_PLACE_REQUEST")),
				{"message": String(payload_check.get("message", ""))})
	var client_session_id := String(payload["client_session_id"])
	var ticket_id := String(payload["ticket_id"])
	var resume_token := String(payload["resume_token"])
	var world_id := String(payload["world_id"])
	var auth_state: Dictionary = _auth_by_peer.get(client_transport_peer_id, {})
	if auth_state.is_empty() \
			or String(auth_state["client_session_id"]) != client_session_id \
			or String(auth_state["ticket_id"]) != ticket_id:
		_counters["placement_frames_rejected"] = int(_counters["placement_frames_rejected"]) + 1
		return _failure("PLACEMENT_NOT_AUTHENTICATED", {"peer": client_transport_peer_id})
	var session_result: Dictionary = _auth_service.create_or_resume_session(
			client_session_id, ticket_id, resume_token)
	if not bool(session_result.get("success", false)):
		_counters["placement_frames_rejected"] = int(_counters["placement_frames_rejected"]) + 1
		return _failure(
				String(session_result.get("error_code", "SESSION_EXCHANGE_FAILED")),
				session_result.get("details", {}))
	var session_details: Dictionary = session_result["details"]
	var resolution: Dictionary = _directory.resolve_current_authority(world_id)
	if bool(resolution.get("success", false)):
		return _attach_and_ack_world_ready(
				transport_frame, frame, route_table, client_transport_peer_id,
				session_details, world_id, Dictionary(resolution["details"]))
	if String(resolution.get("error_code", "")) == "DIRECTORY_UNAVAILABLE":
		return _degrade_and_ack(transport_frame, frame, route_table, client_transport_peer_id, session_details, world_id)
	_counters["placement_frames_rejected"] = int(_counters["placement_frames_rejected"]) + 1
	return _failure(
			String(resolution.get("error_code", "PLACEMENT_RESOLUTION_FAILED")),
			resolution.get("details", {}))


func _attach_and_ack_world_ready(
		transport_frame: Dictionary,
		frame: Dictionary,
		route_table,
		client_transport_peer_id: String,
		session_details: Dictionary,
		world_id: String,
		resolution: Dictionary
) -> Dictionary:
	var attach: Dictionary = _attach_route_row(
			route_table, client_transport_peer_id, session_details, world_id, resolution)
	if not bool(attach.get("success", false)):
		return _failure(
				String(attach.get("error_code", "ROUTE_ATTACH_FAILED")),
				attach.get("details", {}))
	_last_known_resolution[world_id] = resolution.duplicate(true)
	var row: Dictionary = attach["details"]["row"]
	var resumed := bool(session_details["resumed"])
	# Record the live placement so a later placement of the SAME client session
	# (resume over a new transport peer, re-placement) supersedes this row
	# instead of stranding the old transport-peer binding.
	_live_placement_by_client_session[String(session_details["client_session_id"])] = {
		"gateway_session_id": String(session_details["gateway_session_id"]),
		"world_id": world_id,
	}
	if resumed:
		_counters["placements_resumed"] = int(_counters["placements_resumed"]) + 1
	else:
		_counters["placements_created"] = int(_counters["placements_created"]) + 1
	var gateway_session_id := String(session_details["gateway_session_id"])
	var ack_payload := {
		"world_id": world_id,
		"authority_id": String(row["route_binding"]["authority_id"]),
		"server_instance_id": String(row["route_binding"]["server_instance_id"]),
		"gateway_session_id": gateway_session_id,
		"session_slot": int(row["session_slot"]),
		"route_role": String(row["route_binding"]["route_role"]),
		"resumed": resumed,
		"logical_player_id": String(session_details["logical_player_id"]),
		"player_entity_id": String(session_details["player_entity_id"]),
		"resume_token": String(session_details["resume_token"]),
	}
	var ack_check: Dictionary = GatewayUtilsScript.validate_eg2_gateway_ack_payload(
			ack_payload, WORLD_READY_ACK_PAYLOAD_SCHEMA)
	if not bool(ack_check.get("success", false)):
		return _failure("WORLD_READY_ACK_INVALID", {"message": String(ack_check.get("message", ""))})
	var ack := _ack_frame(
			String(transport_frame["session_id"]),
			gateway_session_id,
			int(frame["sequence"]),
			WORLD_READY_ACK_PAYLOAD_SCHEMA,
			ack_payload)
	return _success({
		"action": "PLACE",
		"placement_state": "ACTIVE",
		"gateway_session_id": gateway_session_id,
		"row": row,
		"ack": ack["frame"],
		"ack_transport_frame": ack["transport_frame"],
	})


func _degrade_and_ack(
		transport_frame: Dictionary,
		frame: Dictionary,
		route_table,
		client_transport_peer_id: String,
		session_details: Dictionary,
		world_id: String
) -> Dictionary:
	var gateway_session_id := String(session_details["gateway_session_id"])
	var cached: Dictionary = _last_known_resolution.get(world_id, {})
	var status := ""
	var row := {}
	if cached.is_empty():
		# No cache, no truth, no route row: the session handle exists but the
		# client gets no placement yet.
		status = "PLACEMENT_PENDING"
		_counters["placements_pending"] = int(_counters["placements_pending"]) + 1
	else:
		var attach: Dictionary = _attach_route_row(
				route_table, client_transport_peer_id, session_details, world_id, cached)
		if not bool(attach.get("success", false)):
			return _failure(
					String(attach.get("error_code", "ROUTE_ATTACH_FAILED")),
					attach.get("details", {}))
		row = attach["details"]["row"]
		var warm: Dictionary = route_table.set_route_role(gateway_session_id, "WARM")
		if not bool(warm.get("success", false)):
			return _failure(
					String(warm.get("error_code", "ROUTE_DEGRADE_FAILED")),
					warm.get("details", {}))
		row["route_binding"]["route_role"] = "WARM"
		# A degraded placement still CREATED its (warm) route row.
		_counters["placements_created"] = int(_counters["placements_created"]) + 1
		_live_placement_by_client_session[String(session_details["client_session_id"])] = {
			"gateway_session_id": gateway_session_id,
			"world_id": world_id,
		}
		status = "WARM"
		_counters["placements_degraded_warm"] = int(_counters["placements_degraded_warm"]) + 1
	var ack_payload := {
		"world_id": world_id,
		"status": status,
		"gateway_session_id": gateway_session_id,
	}
	var ack_check: Dictionary = GatewayUtilsScript.validate_eg2_gateway_ack_payload(
			ack_payload, PLACEMENT_DEGRADED_ACK_PAYLOAD_SCHEMA)
	if not bool(ack_check.get("success", false)):
		return _failure("PLACEMENT_DEGRADED_ACK_INVALID", {"message": String(ack_check.get("message", ""))})
	var ack := _ack_frame(
			String(transport_frame["session_id"]),
			gateway_session_id,
			int(frame["sequence"]),
			PLACEMENT_DEGRADED_ACK_PAYLOAD_SCHEMA,
			ack_payload)
	return _success({
		"action": "PLACE",
		"placement_state": status,
		"gateway_session_id": gateway_session_id,
		"row": row,
		"ack": ack["frame"],
		"ack_transport_frame": ack["transport_frame"],
	})


## ---- shared internals -------------------------------------------------------


func _attach_route_row(
		route_table,
		client_transport_peer_id: String,
		session_details: Dictionary,
		world_id: String,
		resolution: Dictionary
) -> Dictionary:
	var superseded := _supersede_live_placement(
			String(session_details["client_session_id"]),
			String(session_details["gateway_session_id"]),
			route_table)
	if not bool(superseded.get("success", false)):
		return superseded
	return route_table.attach(
			String(session_details["gateway_session_id"]),
			client_transport_peer_id,
			String(session_details["client_session_id"]),
			String(session_details["logical_player_id"]),
			String(session_details["player_entity_id"]),
			world_id,
			String(resolution["authority_id"]),
			String(resolution["server_instance_id"]))


## Release the previous live row of this client session so re-placement over
## the same or a new transport peer cannot strand the peer binding.
func _supersede_live_placement(client_session_id: String, gateway_session_id: String, route_table) -> Dictionary:
	var previous: Dictionary = _live_placement_by_client_session.get(client_session_id, {})
	if previous.is_empty():
		return _success({})
	var previous_gsid := String(previous["gateway_session_id"])
	if previous_gsid == gateway_session_id:
		return _success({})
	var released: Dictionary = route_table.release(previous_gsid)
	if not bool(released.get("success", false)) \
			and String(released.get("error_code", "")) != "UNKNOWN_GATEWAY_SESSION":
		return released
	_live_placement_by_client_session.erase(client_session_id)
	return _success({})


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
			"frame/eg2/session-ack/%d" % _ack_frame_counter,
			gateway_session_id,
			"WORLD_TO_CLIENT",
			"SESSION_CONTROL",
			maxi(request_sequence, 1),
			payload_schema,
			payload
	)
	_ack_sequence_by_wire_session[wire_session] = int(_ack_sequence_by_wire_session.get(wire_session, 0)) + 1
	var wire_ack_sequence := int(_ack_sequence_by_wire_session[wire_session])
	var transport_frame := {
		"frame_id": "frame/eg2/session-ack-transport/%d" % _ack_frame_counter,
		"session_id": wire_session,
		"sequence": wire_ack_sequence,
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

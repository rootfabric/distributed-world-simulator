extends RefCounted

## EG1 route/session table: the gateway's single source of routing identity.
## Owns the mapping gateway_session_id -> client transport peer, ephemeral
## session_slot, session binding and route binding rows.
##
## Zero-ownership discipline: gameplay traffic NEVER mutates table state.
## Only the explicit session-control operations below change revisions or roles;
## frame admission checks are read-only.

const SessionBindingScript = preload("res://scripts/network/gateway/gateway_session_binding.gd")
const RouteBindingScript = preload("res://scripts/network/gateway/gateway_route_binding.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")

const TABLE_SCHEMA := "planet_simulator.eg1_gateway_route_table.v1"

var _rows: Dictionary = {}
var _by_client_peer: Dictionary = {}
var _slot_counter: int = 0
var _route_counter: int = 0


func attach(
		gateway_session_id: String,
		client_transport_peer_id: String,
		client_session_id: String,
		logical_player_id: String,
		player_entity_id: String,
		world_id: String,
		authority_id: String,
		server_instance_id: String
) -> Dictionary:
	if _rows.has(gateway_session_id):
		return _failure("GATEWAY_SESSION_EXISTS", {"gateway_session_id": gateway_session_id})
	if _by_client_peer.has(client_transport_peer_id):
		return _failure("CLIENT_TRANSPORT_PEER_ALREADY_BOUND", {"peer": client_transport_peer_id})
	var binding := SessionBindingScript.create(
			gateway_session_id, client_session_id, logical_player_id,
			player_entity_id, world_id, 1, "ATTACHED"
	)
	var binding_check := SessionBindingScript.validate(binding)
	if not bool(binding_check.get("success", false)):
		return _failure(String(binding_check.get("error_code", "INVALID_SESSION_BINDING")), {"detail": binding_check.get("details", {})})
	_slot_counter += 1
	_route_counter += 1
	var route_binding := RouteBindingScript.create(
			_mint_route_binding_id(gateway_session_id),
			gateway_session_id,
			player_entity_id,
			authority_id,
			server_instance_id,
			1,
			1,
			"ACTIVE"
	)
	var route_check := RouteBindingScript.validate(route_binding)
	if not bool(route_check.get("success", false)):
		_slot_counter -= 1
		_route_counter -= 1
		return _failure(String(route_check.get("error_code", "INVALID_ROUTE_BINDING")), {"detail": route_check.get("details", {})})
	var row := {
		"gateway_session_id": gateway_session_id,
		"client_transport_peer_id": client_transport_peer_id,
		"session_slot": _slot_counter,
		"binding": binding,
		"route_binding": route_binding,
		"backend_link_id": "",
	}
	_rows[gateway_session_id] = row
	_by_client_peer[client_transport_peer_id] = gateway_session_id
	return _success({"row": row.duplicate(true)})


func bind_backend_link(gateway_session_id: String, backend_link_id: String) -> Dictionary:
	if not _rows.has(gateway_session_id):
		return _failure("UNKNOWN_GATEWAY_SESSION", {"gateway_session_id": gateway_session_id})
	if backend_link_id.is_empty():
		return _failure("EMPTY_FIELD", {"field": "backend_link_id"})
	_rows[gateway_session_id]["backend_link_id"] = backend_link_id
	return _success({})


func lookup(gateway_session_id: String) -> Dictionary:
	if not _rows.has(gateway_session_id):
		return _failure("UNKNOWN_GATEWAY_SESSION", {"gateway_session_id": gateway_session_id})
	return _success({"row": Dictionary(_rows[gateway_session_id]).duplicate(true)})


func lookup_by_client_peer(client_transport_peer_id: String) -> Dictionary:
	if not _by_client_peer.has(client_transport_peer_id):
		return _failure("UNKNOWN_CLIENT_TRANSPORT_PEER", {"peer": client_transport_peer_id})
	return lookup(String(_by_client_peer[client_transport_peer_id]))


## Read-only admission check. Never mutates anything: gameplay traffic cannot
## change route roles or revisions by construction.
func can_admit_frame(channel: String, gateway_session_id: String) -> Dictionary:
	if not _rows.has(gateway_session_id):
		return _failure("UNKNOWN_GATEWAY_SESSION", {"gateway_session_id": gateway_session_id})
	var row: Dictionary = _rows[gateway_session_id]
	var state := String(row["binding"]["state"])
	var role := String(row["route_binding"]["route_role"])
	if state == "DETACHED":
		return _failure("GATEWAY_SESSION_DETACHED", {"channel": channel})
	if GatewayUtilsScript.is_mutating_client_channel(channel) and role != "ACTIVE":
		return _failure("ROUTE_ROLE_REJECTS_MUTATIONS", {"channel": channel, "route_role": role})
	if GatewayUtilsScript.is_mutating_client_channel(channel) and state != "ATTACHED":
		return _failure("GATEWAY_SESSION_NOT_ATTACHED", {"channel": channel, "state": state})
	return _success({"admitted": true})


## Session-control plane only. Route role changes bump route_revision exactly once
## per actual change; identical-role calls are no-ops.
func set_route_role(gateway_session_id: String, route_role: String) -> Dictionary:
	if not _rows.has(gateway_session_id):
		return _failure("UNKNOWN_GATEWAY_SESSION", {"gateway_session_id": gateway_session_id})
	if not GatewayUtilsScript.ROUTE_ROLES.has(route_role):
		return _failure("INVALID_ROUTE_ROLE", {"route_role": route_role})
	var row: Dictionary = _rows[gateway_session_id]
	if String(row["route_binding"]["route_role"]) == route_role:
		return _success({"changed": false})
	row["route_binding"]["route_role"] = route_role
	row["route_binding"]["route_revision"] = int(row["route_binding"]["route_revision"]) + 1
	return _success({"changed": true, "route_revision": int(row["route_binding"]["route_revision"])})


## Session-control plane only. Binding state changes bump binding_revision exactly
## once per actual change; detaching also drains the route.
func set_binding_state(gateway_session_id: String, state: String) -> Dictionary:
	if not _rows.has(gateway_session_id):
		return _failure("UNKNOWN_GATEWAY_SESSION", {"gateway_session_id": gateway_session_id})
	if not GatewayUtilsScript.SESSION_STATES.has(state):
		return _failure("INVALID_SESSION_STATE", {"state": state})
	var row: Dictionary = _rows[gateway_session_id]
	if String(row["binding"]["state"]) == state:
		return _success({"changed": false})
	row["binding"]["state"] = state
	row["binding"]["binding_revision"] = int(row["binding"]["binding_revision"]) + 1
	if state == "DETACHED":
		row["route_binding"]["route_role"] = "DRAIN"
		row["route_binding"]["route_revision"] = int(row["route_binding"]["route_revision"]) + 1
	return _success({
		"changed": true,
		"binding_revision": int(row["binding"]["binding_revision"]),
		"route_revision": int(row["route_binding"]["route_revision"]),
	})


func release(gateway_session_id: String) -> Dictionary:
	if not _rows.has(gateway_session_id):
		return _failure("UNKNOWN_GATEWAY_SESSION", {"gateway_session_id": gateway_session_id})
	var row: Dictionary = _rows[gateway_session_id]
	_by_client_peer.erase(String(row["client_transport_peer_id"]))
	_rows.erase(gateway_session_id)
	return _success({})


func session_count() -> int:
	return _rows.size()


func snapshot() -> Dictionary:
	var rows: Array = []
	for key in _rows.keys():
		rows.append(Dictionary(_rows[key]).duplicate(true))
	return {
		"schema": TABLE_SCHEMA,
		"session_count": _rows.size(),
		"allocated_session_slots": _slot_counter,
		"rows": rows,
	}


func _mint_route_binding_id(gateway_session_id: String) -> String:
	var suffix := gateway_session_id.trim_prefix("gateway-session/").replace("/", "-")
	return "gateway-route/eg1/%s/%d" % [suffix, _route_counter]


func _success(details: Dictionary) -> Dictionary:
	return {"success": true, "details": details}


func _failure(error_code: String, details: Dictionary) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details}

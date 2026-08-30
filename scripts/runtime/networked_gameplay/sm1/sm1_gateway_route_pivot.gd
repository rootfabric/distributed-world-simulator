extends RefCounted

## SM1.4 gateway-preserving internal authority route pivot.
##
## The client-facing Gateway endpoint/session are immutable for the lifetime of
## this adapter. The current internal authority is DERIVED on every command from
## SM1.2 and is never cached as ownership truth. During handoff, when SM1.2 is
## not ACTIVE, gameplay routing fails closed instead of guessing a target.

const SCHEMA := "distributed_world_simulator.v0_sm1_gateway_route_pivot.v1"
const CLIENT_VISIBLE_ROUTE := "EDGE_GATEWAY_ONLY"

var _routes_by_authority: Dictionary = {}
var _transfer_coordinator = null
var _gateway_endpoint_id: String = ""
var _client_session_id: String = ""
var _counters := {
	"routed": 0,
	"executed": 0,
	"rejected": 0,
	"frozen_during_transfer": 0,
	"replays": 0,
}


func configure(routes_by_authority: Dictionary, transfer_coordinator, gateway_endpoint_id: String, client_session_id: String) -> Dictionary:
	if routes_by_authority.is_empty():
		return _failure("SM1_ROUTE_AUTHORITY_ROUTES_REQUIRED")
	if transfer_coordinator == null \
			or not transfer_coordinator.has_method("snapshot") \
			or not transfer_coordinator.has_method("authorize_write"):
		return _failure("SM1_ROUTE_INVALID_TRANSFER_COORDINATOR")
	if gateway_endpoint_id.strip_edges().is_empty() or client_session_id.strip_edges().is_empty():
		return _failure("SM1_ROUTE_GATEWAY_IDENTITY_REQUIRED")
	var copied: Dictionary = {}
	for authority_value in routes_by_authority.keys():
		var authority_id := String(authority_value)
		var route = routes_by_authority[authority_value]
		if authority_id.strip_edges().is_empty() or route == null or not route.has_method("route_command"):
			return _failure("SM1_ROUTE_INVALID_AUTHORITY_ROUTE", {"authority_id": authority_id})
		copied[authority_id] = route
	_routes_by_authority = copied
	_transfer_coordinator = transfer_coordinator
	_gateway_endpoint_id = gateway_endpoint_id
	_client_session_id = client_session_id
	return _success({
		"result": "CONFIGURED",
		"client_route": get_client_route_identity(),
	})


func route_command(client_session_id: String, operation_id: String, command: Dictionary) -> Dictionary:
	_counters["routed"] = int(_counters["routed"]) + 1
	if client_session_id != _client_session_id:
		return _reject("SM1_ROUTE_CLIENT_SESSION_CHANGED", {"client_session_id": client_session_id})
	if operation_id.strip_edges().is_empty():
		return _reject("SM1_ROUTE_OPERATION_ID_REQUIRED")
	if _transfer_coordinator == null:
		return _reject("SM1_ROUTE_NOT_CONFIGURED")

	var projection: Dictionary = get_internal_route_projection()
	if String(projection.get("transfer_state", "")) != "ACTIVE":
		_counters["frozen_during_transfer"] = int(_counters["frozen_during_transfer"]) + 1
		return _reject("SM1_ROUTE_FROZEN_DURING_AUTHORITY_TRANSFER", {
			"client_route": get_client_route_identity(),
			"transfer_state": String(projection.get("transfer_state", "")),
		})
	var authority_id := String(projection.get("internal_authority_id", ""))
	var authority_epoch := int(projection.get("authority_epoch", 0))
	if not _routes_by_authority.has(authority_id):
		return _reject("SM1_ROUTE_ACTIVE_AUTHORITY_TARGET_MISSING")
	var authorization: Dictionary = _transfer_coordinator.authorize_write(authority_id, authority_epoch)
	if not bool(authorization.get("success", false)):
		return _reject(String(authorization.get("error_code", "SM1_ROUTE_AUTHORITY_NOT_WRITABLE")))

	var route = _routes_by_authority[authority_id]
	var routed: Variant = route.route_command(client_session_id, operation_id, command)
	if typeof(routed) != TYPE_DICTIONARY:
		return _reject("SM1_ROUTE_MALFORMED_P6_ROUTE_RESULT")
	var route_result: Dictionary = Dictionary(routed)
	if not bool(route_result.get("success", false)):
		return _reject(String(route_result.get("error_code", "SM1_ROUTE_P6_REJECTED")), {
			"client_route": get_client_route_identity(),
			"route_error": route_result.duplicate(true),
		})

	var result_code := String(route_result.get("details", {}).get("result", ""))
	if result_code == "ALREADY_APPLIED":
		_counters["replays"] = int(_counters["replays"]) + 1
	else:
		_counters["executed"] = int(_counters["executed"]) + 1
	return _success({
		"result": result_code,
		"operation_id": operation_id,
		"gateway_endpoint_id": _gateway_endpoint_id,
		"gateway_session_id": _client_session_id,
		"client_visible_route": CLIENT_VISIBLE_ROUTE,
		"simulation_endpoint_disclosed": false,
		"route_result": Dictionary(route_result.get("details", {})).duplicate(true),
	})


## This is safe to expose to the client/UI. It intentionally contains no
## simulation authority id, epoch or endpoint.
func get_client_route_identity() -> Dictionary:
	return {
		"gateway_endpoint_id": _gateway_endpoint_id,
		"gateway_session_id": _client_session_id,
		"client_visible_route": CLIENT_VISIBLE_ROUTE,
		"simulation_endpoint_disclosed": false,
	}


## Server-side diagnostics only. Ownership is derived from the coordinator on
## every call and is not stored by this adapter.
func get_internal_route_projection() -> Dictionary:
	if _transfer_coordinator == null:
		return {
			"transfer_state": "UNCONFIGURED",
			"internal_authority_id": "",
			"authority_epoch": 0,
			"ownership_source": "SM1_TRANSFER_COORDINATOR_DERIVED",
			"private_ownership_truth": false,
		}
	var snap: Dictionary = _transfer_coordinator.snapshot()
	return {
		"transfer_state": String(snap.get("state", "")),
		"internal_authority_id": String(snap.get("active_authority_id", "")),
		"authority_epoch": int(snap.get("authority_epoch", 0)),
		"ownership_source": "SM1_TRANSFER_COORDINATOR_DERIVED",
		"private_ownership_truth": false,
		"client_route": get_client_route_identity(),
	}


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"client_route": get_client_route_identity(),
		"internal_route_projection": get_internal_route_projection(),
		"route_target_count": _routes_by_authority.size(),
		"ownership_source": "SM1_TRANSFER_COORDINATOR_DERIVED",
		"private_ownership_truth": false,
		"gateway_authoritative": false,
		"counters": _counters.duplicate(true),
	}


func _success(details: Dictionary) -> Dictionary:
	return {"success": true, "error_code": "", "details": details}


func _reject(error_code: String, details: Dictionary = {}) -> Dictionary:
	_counters["rejected"] = int(_counters["rejected"]) + 1
	return _failure(error_code, details)


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details}

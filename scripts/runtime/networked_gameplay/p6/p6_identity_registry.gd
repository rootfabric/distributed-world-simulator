extends RefCounted

## P6.2 topology-neutral player identity registry.
##
## Binds opaque client session ids to logical player identities. The registry
## is deliberately TOPOLOGY-NEUTRAL: session ids are treated as opaque strings,
## and the registry never branches on transport flavor (direct / gateway /
## ENet / loopback all behave identically). A transport change is expressed as
## rebind_on_transport_change(old_session, new_session): the logical identity
## is preserved verbatim, a NEW binding row supersedes the old one, history is
## retained, and revisions increment.
##
## Single-writer discipline: this registry owns ONLY the
## PLAYER_IDENTITY_BINDINGS domain declared in p6_ownership_map.gd; it never
## touches persistence, gateway routing, or any other domain.

const OwnershipMapScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_ownership_map.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")

const SCHEMA := "planet_simulator.p6_identity_registry.v1"
const DOMAIN_ID := "p6-domain/player-identity-bindings"

# client_session_id -> live binding row
var _live_by_session: Dictionary = {}
# logical_player_id -> Array of binding rows (superseded first, live last)
var _history_by_player: Dictionary = {}
var _next_binding_number: int = 0
var _counters := {
	"binds": 0,
	"rebinds": 0,
	"resolves": 0,
	"idempotent_binds": 0,
	"rejections": 0,
}


func _validate_id(value: String, field: String, prefix: String) -> Dictionary:
	var holder := {field: value}
	return GatewayUtilsScript.require_id(holder, field, prefix)


func _reject(error_code: String, details: Dictionary) -> Dictionary:
	_counters["rejections"] = int(_counters["rejections"]) + 1
	return {"success": false, "error_code": error_code, "details": details}


func _ok(details: Dictionary) -> Dictionary:
	return {"success": true, "details": details}


## Bind a client session to a logical player identity. Idempotent for the
## exact same triple; fails closed otherwise.
func bind(client_session_id: String, logical_player_id: String, player_entity_id: String) -> Dictionary:
	var domain: Dictionary = OwnershipMapScript.find_domain(DOMAIN_ID)
	if domain.is_empty():
		return _reject("OWNERSHIP_DOMAIN_UNDECLARED", {"domain_id": DOMAIN_ID})
	for pair in [
		["client_session_id", client_session_id, "client-session"],
		["logical_player_id", logical_player_id, "player"],
		["player_entity_id", player_entity_id, "entity"],
	]:
		var check: Dictionary = _validate_id(String(pair[1]), String(pair[0]), String(pair[2]))
		if not bool(check.get("success", false)):
			return _reject("INVALID_ID_NAMESPACE", {"field": pair[0]})
	if _live_by_session.has(client_session_id):
		var existing: Dictionary = _live_by_session[client_session_id]
		if String(existing["logical_player_id"]) == logical_player_id \
				and String(existing["player_entity_id"]) == player_entity_id:
			_counters["idempotent_binds"] = int(_counters["idempotent_binds"]) + 1
			return _ok({"binding": existing.duplicate(true), "idempotent": true})
		return _reject("IDENTITY_ALREADY_BOUND", {
			"client_session_id": client_session_id,
			"bound_logical_player_id": String(existing["logical_player_id"]),
		})
	for session_value in _live_by_session.keys():
		var row: Dictionary = _live_by_session[session_value]
		if String(row["logical_player_id"]) == logical_player_id:
			return _reject("LOGICAL_PLAYER_ALREADY_LIVE", {
				"logical_player_id": logical_player_id,
				"existing_client_session_id": String(row["client_session_id"]),
			})
	_next_binding_number += 1
	var row := {
		"schema": SCHEMA,
		"binding_id": "p6-identity-binding/%06d" % _next_binding_number,
		"binding_revision": 1,
		"client_session_id": client_session_id,
		"logical_player_id": logical_player_id,
		"player_entity_id": player_entity_id,
		"state": "LIVE",
	}
	_live_by_session[client_session_id] = row
	_append_history(logical_player_id, row)
	_counters["binds"] = int(_counters["binds"]) + 1
	return _ok({"binding": row.duplicate(true), "idempotent": false})


## Transport change: supersede the old session's binding with a new session id
## while preserving the logical identity verbatim. Fails closed when the old
## session is unknown or the new session already carries a live binding.
func rebind_on_transport_change(old_client_session_id: String, new_client_session_id: String) -> Dictionary:
	if not _live_by_session.has(old_client_session_id):
		return _reject("UNKNOWN_SESSION", {"client_session_id": old_client_session_id})
	if old_client_session_id == new_client_session_id:
		return _reject("SAME_SESSION_REBIND", {"client_session_id": old_client_session_id})
	if _live_by_session.has(new_client_session_id):
		return _reject("NEW_SESSION_ALREADY_LIVE", {"client_session_id": new_client_session_id})
	var old_row: Dictionary = _live_by_session[old_client_session_id]
	var logical: String = String(old_row["logical_player_id"])
	var entity: String = String(old_row["player_entity_id"])
	_next_binding_number += 1
	var new_row := {
		"schema": SCHEMA,
		"binding_id": "p6-identity-binding/%06d" % _next_binding_number,
		"binding_revision": int(old_row["binding_revision"]) + 1,
		"client_session_id": new_client_session_id,
		"logical_player_id": logical,
		"player_entity_id": entity,
		"state": "LIVE",
		"supersedes_binding_id": String(old_row["binding_id"]),
	}
	old_row["state"] = "SUPERSEDED"
	_live_by_session.erase(old_client_session_id)
	_live_by_session[new_client_session_id] = new_row
	# propagate SUPERSEDED into the retained history so supersede is observable
	for history_value in (_history_by_player.get(logical, []) as Array):
		var history_row: Dictionary = Dictionary(history_value)
		if String(history_row.get("binding_id", "")) == String(old_row["binding_id"]):
			history_row["state"] = "SUPERSEDED"
	_append_history(logical, new_row)
	_counters["rebinds"] = int(_counters["rebinds"]) + 1
	return _ok({"binding": new_row.duplicate(true), "preserved_logical_player_id": logical})


func resolve_by_session(client_session_id: String) -> Dictionary:
	_counters["resolves"] = int(_counters["resolves"]) + 1
	if not _live_by_session.has(client_session_id):
		return _reject("UNKNOWN_SESSION", {"client_session_id": client_session_id})
	return _ok({"binding": Dictionary(_live_by_session[client_session_id]).duplicate(true)})


func resolve(logical_player_id: String) -> Dictionary:
	_counters["resolves"] = int(_counters["resolves"]) + 1
	for session_value in _live_by_session.keys():
		var row: Dictionary = _live_by_session[session_value]
		if String(row["logical_player_id"]) == logical_player_id:
			return _ok({"binding": row.duplicate(true)})
	return _reject("UNKNOWN_PLAYER", {"logical_player_id": logical_player_id})


func list_bindings_for_player(logical_player_id: String) -> Array:
	var history_value: Variant = _history_by_player.get(logical_player_id, [])
	var rows: Array = []
	for row_value in (history_value as Array):
		rows.append(Dictionary(row_value).duplicate(true))
	return rows


func live_count() -> int:
	return _live_by_session.size()


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"domain_id": DOMAIN_ID,
		"topology_neutral": true,
		"live_count": _live_by_session.size(),
		"counters": _counters.duplicate(true),
	}


func _append_history(logical_player_id: String, row: Dictionary) -> void:
	if not _history_by_player.has(logical_player_id):
		_history_by_player[logical_player_id] = []
	_history_by_player[logical_player_id].append(row.duplicate(true))

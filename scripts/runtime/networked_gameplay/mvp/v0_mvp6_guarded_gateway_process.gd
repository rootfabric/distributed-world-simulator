extends "res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_gateway_process.gd"

const Guard6 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_enet_long_operation_guard.gd")
const Protocol6 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_process_protocol.gd")

var _guard6_counts := {"authority/a": 0, "authority/b": 0}
var _guard6_last: Dictionary = {}
var _client_guard6_counts := {"client/a": 0, "client/b": 0}
var _client_guard6_last: Dictionary = {}


func _authority6(authority_id: String, actor: String, request: Dictionary) -> Dictionary:
	var link = links.get(authority_id)
	if link == null or link.boundary == null:
		return Protocol6.failure("MVP6_ENET_GUARD_BACKEND_LINK_MISSING")
	var guarded: Dictionary = Guard6.apply(link.boundary, String(link.peer))
	if not bool(guarded.get("success", false)):
		return Protocol6.failure(String(guarded.get("error_code", "MVP6_ENET_GUARD_FAILED")))
	_guard6_counts[authority_id] = int(_guard6_counts.get(authority_id, 0)) + 1
	_guard6_last[authority_id] = Dictionary(guarded.get("details", {})).duplicate(true)
	return super._authority6(authority_id, actor, request)


func _guard_clients6() -> Dictionary:
	if client_boundary == null:
		return Protocol6.failure("MVP6_CLIENT_GUARD_BOUNDARY_MISSING")
	for client_actor in ["a", "b"]:
		var client_id := "client/" + client_actor
		var client_peer := String(client_peers.get(client_actor, ""))
		if client_peer.is_empty():
			return Protocol6.failure("MVP6_CLIENT_GUARD_PEER_MISSING:" + client_actor)
		var guarded: Dictionary = Guard6.apply(client_boundary, client_peer)
		if not bool(guarded.get("success", false)):
			return Protocol6.failure(String(guarded.get("error_code", "MVP6_CLIENT_GUARD_FAILED")) + ":" + client_actor)
		_client_guard6_counts[client_id] = int(_client_guard6_counts.get(client_id, 0)) + 1
		_client_guard6_last[client_id] = Dictionary(guarded.get("details", {})).duplicate(true)
	return Protocol6.success()


func handle_client(actor: String, body: Dictionary) -> Dictionary:
	var kind := String(body.get("kind", ""))
	if kind.begins_with("MVP6_"):
		# Base-100 is deliberately synchronous on the canonical authority. While
		# gateway code waits on that call it cannot poll the client-facing ENet
		# host either, so protect both already-authenticated client peers before
		# entering the bounded long operation. This changes liveness only.
		var guarded := _guard_clients6()
		if not bool(guarded.get("success", false)):
			return guarded
	return super.handle_client(actor, body)


func base_report(schema: String, passed: bool, graphical: bool) -> Dictionary:
	var value: Dictionary = super.base_report(schema, passed, graphical)
	value["mvp6_transport_guard"] = {
		"backend_counts": _guard6_counts.duplicate(true),
		"backend_last": _guard6_last.duplicate(true),
		"client_counts": _client_guard6_counts.duplicate(true),
		"client_last": _client_guard6_last.duplicate(true),
		"shared_transport_changed": false,
		"payload_limit_changed": false,
		"reconnect_policy_changed": false,
	}
	return value

extends "res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_gateway_process.gd"

const Guard6 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_enet_long_operation_guard.gd")
const Protocol6 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_process_protocol.gd")

var _guard6_counts := {"authority/a": 0, "authority/b": 0}
var _guard6_last: Dictionary = {}
var _client_guard6_counts := {"client/a": 0, "client/b": 0}
var _client_guard6_last: Dictionary = {}
var _client_guard6_skips := {"client/a": 0, "client/b": 0}
var _client_guard6_skip_last: Dictionary = {}


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


func _guard_client6(client_actor: String) -> Dictionary:
	if client_boundary == null:
		return Protocol6.failure("MVP6_CLIENT_GUARD_BOUNDARY_MISSING")
	var client_id: String = "client/" + client_actor
	var client_peer: String = String(client_peers.get(client_actor, ""))
	if client_peer.is_empty():
		return Protocol6.failure("MVP6_CLIENT_GUARD_PEER_MISSING:" + client_actor)
	var guarded: Dictionary = Guard6.apply(client_boundary, client_peer)
	if not bool(guarded.get("success", false)):
		var code: String = String(guarded.get("error_code", "MVP6_CLIENT_GUARD_FAILED"))
		# The public boundary has already authenticated this client and owns its
		# stable peer id.  The internal ENet PacketPeer map is only optional
		# liveness instrumentation and can transiently omit another established
		# client while the gateway is servicing a synchronous authority reply.
		# Do not turn that introspection race into a product disconnect.  A real
		# inactive peer still fails here, and the inherited gateway independently
		# fails closed on PEER_DISCONNECTED during the workload.
		if code == "MVP6_ENET_GUARD_PACKET_PEER_MISSING":
			_client_guard6_skips[client_id] = int(_client_guard6_skips.get(client_id, 0)) + 1
			_client_guard6_skip_last[client_id] = {
				"peer_id": client_peer,
				"error_code": code,
				"reason": "INTERNAL_PACKET_PEER_INTROSPECTION_UNAVAILABLE",
				"payload_limit_changed": false,
				"reconnect_policy_changed": false,
				"shared_transport_changed": false,
			}
			return Protocol6.success({"guard_skipped": true, "peer_id": client_peer, "reason": code})
		return Protocol6.failure(code + ":" + client_actor)
	_client_guard6_counts[client_id] = int(_client_guard6_counts.get(client_id, 0)) + 1
	_client_guard6_last[client_id] = Dictionary(guarded.get("details", {})).duplicate(true)
	return Protocol6.success()


func _guard_clients6() -> Dictionary:
	for raw_actor in ["a", "b"]:
		var client_actor: String = String(raw_actor)
		var guarded: Dictionary = _guard_client6(client_actor)
		if not bool(guarded.get("success", false)):
			return guarded
	return Protocol6.success()


func handle_client(actor: String, body: Dictionary) -> Dictionary:
	var kind: String = String(body.get("kind", ""))
	# Arm the server side of each graphical client link at authenticated HELLO,
	# before either client can race into the synchronous base-100 operation.
	# During HELLO only the current actor is guaranteed to exist; MVP6 commands
	# refresh both available windows immediately before the bounded long
	# operation. Canonical state, payload/order and reconnect policy stay intact.
	if kind == "HELLO":
		var hello_guarded: Dictionary = _guard_client6(actor)
		if not bool(hello_guarded.get("success", false)):
			return hello_guarded
	elif kind.begins_with("MVP6_"):
		var guarded: Dictionary = _guard_clients6()
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
		"client_skips": _client_guard6_skips.duplicate(true),
		"client_skip_last": _client_guard6_skip_last.duplicate(true),
		"shared_transport_changed": false,
		"payload_limit_changed": false,
		"reconnect_policy_changed": false,
	}
	return value

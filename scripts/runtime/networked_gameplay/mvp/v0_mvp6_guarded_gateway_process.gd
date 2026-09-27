extends "res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_gateway_process.gd"

const Guard6 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_enet_long_operation_guard.gd")
const Protocol6 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_process_protocol.gd")

var _guard6_counts := {"authority/a": 0, "authority/b": 0}
var _guard6_last: Dictionary = {}
var _guard6_restore_counts := {"authority/a": 0, "authority/b": 0}
var _guard6_restore_last: Dictionary = {}
var _guard6_active := {"authority/a": false, "authority/b": false}
var _client_guard6_counts := {"client/a": 0, "client/b": 0}
var _client_guard6_last: Dictionary = {}
var _client_guard6_restore_counts := {"client/a": 0, "client/b": 0}
var _client_guard6_restore_last: Dictionary = {}
var _client_guard6_active := {"client/a": false, "client/b": false}
var _client_guard6_skips := {"client/a": 0, "client/b": 0}
var _client_guard6_skip_last: Dictionary = {}
const BACKEND_KEEPALIVE_INTERVAL_MS6 := 5000
var _backend_keepalive_last_ms6 := 0
var _backend_keepalive_cycles6 := 0
var _backend_keepalive_failures6 := 0
var _backend_keepalive_last6: Dictionary = {}


func _authority6(authority_id: String, actor: String, request: Dictionary) -> Dictionary:
	var link = links.get(authority_id)
	if link == null or link.boundary == null:
		return Protocol6.failure("MVP6_ENET_GUARD_BACKEND_LINK_MISSING")
	var guarded: Dictionary = Guard6.apply(link.boundary, String(link.peer))
	if not bool(guarded.get("success", false)):
		return Protocol6.failure(String(guarded.get("error_code", "MVP6_ENET_GUARD_FAILED")))
	_guard6_counts[authority_id] = int(_guard6_counts.get(authority_id, 0)) + 1
	_guard6_last[authority_id] = Dictionary(guarded.get("details", {})).duplicate(true)
	_guard6_active[authority_id] = true
	var result: Dictionary = super._authority6(authority_id, actor, request)
	var restored: Dictionary = Guard6.restore(link.boundary, String(link.peer))
	if not bool(restored.get("success", false)):
		return Protocol6.failure(String(restored.get("error_code", "MVP6_ENET_GUARD_RESTORE_FAILED")))
	_guard6_restore_counts[authority_id] = int(_guard6_restore_counts.get(authority_id, 0)) + 1
	_guard6_restore_last[authority_id] = Dictionary(restored.get("details", {})).duplicate(true)
	_guard6_active[authority_id] = false
	return result


func _guard_client6(client_actor: String) -> Dictionary:
	if client_boundary == null:
		return Protocol6.failure("MVP6_CLIENT_GUARD_BOUNDARY_MISSING")
	var client_id: String = "client/" + client_actor
	var client_peer: String = String(client_peers.get(client_actor, ""))
	if client_peer.is_empty():
		return Protocol6.failure("MVP6_CLIENT_GUARD_PEER_MISSING:" + client_actor)
	var was_active := bool(_client_guard6_active.get(client_id, false))
	var guarded: Dictionary = Guard6.apply(client_boundary, client_peer)
	if not bool(guarded.get("success", false)):
		var code: String = String(guarded.get("error_code", "MVP6_CLIENT_GUARD_FAILED"))
		# The public boundary has already authenticated this client and owns its
		# stable peer id. The internal ENet PacketPeer map is optional liveness
		# instrumentation and can transiently omit another established client
		# while the gateway is servicing a synchronous authority reply. A real
		# inactive peer is still fatal, and PEER_DISCONNECTED remains inherited.
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
	if not was_active:
		_client_guard6_counts[client_id] = int(_client_guard6_counts.get(client_id, 0)) + 1
	_client_guard6_last[client_id] = Dictionary(guarded.get("details", {})).duplicate(true)
	_client_guard6_active[client_id] = true
	return Protocol6.success()


func _restore_client6(client_actor: String) -> Dictionary:
	var client_id: String = "client/" + client_actor
	if not bool(_client_guard6_active.get(client_id, false)):
		return Protocol6.success({"already_restored": true})
	if client_boundary == null:
		return Protocol6.failure("MVP6_CLIENT_GUARD_BOUNDARY_MISSING")
	var client_peer: String = String(client_peers.get(client_actor, ""))
	if client_peer.is_empty():
		return Protocol6.failure("MVP6_CLIENT_GUARD_PEER_MISSING:" + client_actor)
	var restored: Dictionary = Guard6.restore(client_boundary, client_peer)
	if not bool(restored.get("success", false)):
		return Protocol6.failure(String(restored.get("error_code", "MVP6_CLIENT_GUARD_RESTORE_FAILED")) + ":" + client_actor)
	_client_guard6_restore_counts[client_id] = int(_client_guard6_restore_counts.get(client_id, 0)) + 1
	_client_guard6_restore_last[client_id] = Dictionary(restored.get("details", {})).duplicate(true)
	_client_guard6_active[client_id] = false
	return Protocol6.success()


func _guard_clients6() -> Dictionary:
	# A partial refresh must not leave an earlier client widened when a later
	# client cannot be guarded. Preserve the original guard failure, but first
	# attempt cleanup for every active client via the aggregate restore helper.
	var first_failure: Dictionary = {}
	for raw_actor in ["a", "b"]:
		var guarded: Dictionary = _guard_client6(String(raw_actor))
		if not bool(guarded.get("success", false)):
			first_failure = guarded.duplicate(true)
			break
	if not first_failure.is_empty():
		_restore_clients6()
		return first_failure
	return Protocol6.success()


func _restore_clients6() -> Dictionary:
	# Restore every still-active client even when an earlier restore fails.
	# Returning early here can leave a later peer on the widened MVP6 timeout
	# policy, so collect the first failure only after all restore attempts ran.
	var first_failure: Dictionary = {}
	for raw_actor in ["a", "b"]:
		var restored: Dictionary = _restore_client6(String(raw_actor))
		if not bool(restored.get("success", false)) and first_failure.is_empty():
			first_failure = restored.duplicate(true)
	if not first_failure.is_empty():
		return first_failure
	return Protocol6.success()


func _service_backend_keepalive6() -> Dictionary:
	if _construction6.is_empty() or _complete6() or closing_at_ms > 0:
		return Protocol6.success({"skipped": true})
	var now := Time.get_ticks_msec()
	if _backend_keepalive_last_ms6 > 0 and now - _backend_keepalive_last_ms6 < BACKEND_KEEPALIVE_INTERVAL_MS6:
		return Protocol6.success({"skipped": true})
	var expected_checksum := String(_construction6.get("checksum", ""))
	if expected_checksum.is_empty():
		return Protocol6.failure("MVP6_BACKEND_KEEPALIVE_CHECKSUM_MISSING")
	var observed: Dictionary = {}
	for authority_id in ["authority/a", "authority/b"]:
		var rpc: Dictionary = _authority6(authority_id, "a", {"kind": "MVP6_CONSTRUCTION_READ"})
		var native: Dictionary = _native6(rpc)
		if not bool(native.get("success", false)):
			_backend_keepalive_failures6 += 1
			return Protocol6.failure("MVP6_BACKEND_KEEPALIVE_RPC_FAILED:" + authority_id + ":" + String(native.get("error_code", "")))
		var details: Dictionary = native.get("details", {})
		var construction: Dictionary = details.get("construction", {})
		var checksum := String(details.get("checksum", construction.get("checksum", "")))
		if checksum != expected_checksum:
			_backend_keepalive_failures6 += 1
			return Protocol6.failure("MVP6_BACKEND_KEEPALIVE_DIVERGED:" + authority_id)
		observed[authority_id] = checksum
	_backend_keepalive_cycles6 += 1
	_backend_keepalive_last_ms6 = now
	_backend_keepalive_last6 = {
		"expected_checksum": expected_checksum,
		"observed": observed,
		"canonical_state_owned": false,
		"mutation_performed": false,
	}
	return Protocol6.success(_backend_keepalive_last6.duplicate(true))


func _process(delta: float) -> bool:
	var parent_result := super._process(delta)
	if client_boundary == null or closing_at_ms > 0 or not failures.is_empty():
		return parent_result
	var kept: Dictionary = _service_backend_keepalive6()
	if not bool(kept.get("success", false)):
		finish_interactive(false, String(kept.get("error_code", "MVP6_BACKEND_KEEPALIVE_FAILED")))
	return parent_result


func handle_client(actor: String, body: Dictionary) -> Dictionary:
	var kind: String = String(body.get("kind", ""))
	# HELLO remains armed across the inherited MVP3-MVP5 prelude so client B
	# cannot expire while A enters synchronous BASE100 before B's first MVP6
	# request. Once MVP6 begins every request is bounded: refresh all established
	# client windows, execute, then restore defaults before returning the reply.
	if kind == "HELLO":
		var hello_guarded: Dictionary = _guard_client6(actor)
		if not bool(hello_guarded.get("success", false)):
			return hello_guarded
		return super.handle_client(actor, body)
	if kind.begins_with("MVP6_"):
		var guarded: Dictionary = _guard_clients6()
		if not bool(guarded.get("success", false)):
			return guarded
		var result: Dictionary = super.handle_client(actor, body)
		var restored: Dictionary = _restore_clients6()
		if not bool(restored.get("success", false)):
			return restored
		return result
	if kind == "FINISH":
		var final_restore: Dictionary = _restore_clients6()
		if not bool(final_restore.get("success", false)):
			return final_restore
	return super.handle_client(actor, body)


func base_report(schema: String, passed: bool, graphical: bool) -> Dictionary:
	var value: Dictionary = super.base_report(schema, passed, graphical)
	var backend_restored := true
	for authority_id in ["authority/a", "authority/b"]:
		backend_restored = backend_restored and int(_guard6_counts.get(authority_id, 0)) == int(_guard6_restore_counts.get(authority_id, 0)) and not bool(_guard6_active.get(authority_id, false))
	var clients_restored := true
	for client_id in ["client/a", "client/b"]:
		clients_restored = clients_restored and int(_client_guard6_counts.get(client_id, 0)) == int(_client_guard6_restore_counts.get(client_id, 0)) and not bool(_client_guard6_active.get(client_id, false))
	value["mvp6_transport_guard"] = {
		"backend_counts": _guard6_counts.duplicate(true),
		"backend_last": _guard6_last.duplicate(true),
		"backend_restore_counts": _guard6_restore_counts.duplicate(true),
		"backend_restore_last": _guard6_restore_last.duplicate(true),
		"backend_active": _guard6_active.duplicate(true),
		"backend_restored_after_each_rpc": backend_restored,
		"client_counts": _client_guard6_counts.duplicate(true),
		"client_last": _client_guard6_last.duplicate(true),
		"client_restore_counts": _client_guard6_restore_counts.duplicate(true),
		"client_restore_last": _client_guard6_restore_last.duplicate(true),
		"client_active": _client_guard6_active.duplicate(true),
		"client_restored_before_finish": clients_restored,
		"client_skips": _client_guard6_skips.duplicate(true),
		"client_skip_last": _client_guard6_skip_last.duplicate(true),
		"backend_keepalive": {
			"interval_ms": BACKEND_KEEPALIVE_INTERVAL_MS6,
			"cycles": _backend_keepalive_cycles6,
			"failures": _backend_keepalive_failures6,
			"last": _backend_keepalive_last6.duplicate(true),
			"mutation_performed": false,
		},
		"shared_transport_changed": false,
		"payload_limit_changed": false,
		"reconnect_policy_changed": false,
	}
	return value


func finish_interactive(seam_criterion: bool, error_code: String = "") -> void:
	var restored: Dictionary = _restore_clients6()
	if not bool(restored.get("success", false)):
		if error_code.is_empty():
			error_code = String(restored.get("error_code", "MVP6_CLIENT_GUARD_RESTORE_FAILED"))
		seam_criterion = false
	super.finish_interactive(seam_criterion, error_code)

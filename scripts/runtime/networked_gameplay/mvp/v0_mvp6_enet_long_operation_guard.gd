extends RefCounted

# MVP6-only guard for the intentionally heavy synchronous base-100 Construction
# command on pinned CI hardware. It does NOT change the shared transport,
# payload cap, ordering or reconnect policy. The guard reaches the already-
# established ENetPacketPeer, widens only its liveness window around bounded
# synchronous work, then restores the unchanged ENet default timeout policy.
const TIMEOUT_LIMIT := 128
const TIMEOUT_MIN_MS := 60000
const TIMEOUT_MAX_MS := 120000
const DEFAULT_TIMEOUT_LIMIT := 32
const DEFAULT_TIMEOUT_MIN_MS := 5000
const DEFAULT_TIMEOUT_MAX_MS := 30000


static func apply(boundary, peer_id: String) -> Dictionary:
	var resolved: Dictionary = _resolve(boundary, peer_id)
	if not bool(resolved.get("success", false)):
		return resolved
	var packet_peer = resolved.get("packet_peer")
	packet_peer.set_timeout(TIMEOUT_LIMIT, TIMEOUT_MIN_MS, TIMEOUT_MAX_MS)
	return _success(peer_id, TIMEOUT_LIMIT, TIMEOUT_MIN_MS, TIMEOUT_MAX_MS, false)


static func restore(boundary, peer_id: String) -> Dictionary:
	var resolved: Dictionary = _resolve(boundary, peer_id)
	if not bool(resolved.get("success", false)):
		return resolved
	var packet_peer = resolved.get("packet_peer")
	packet_peer.set_timeout(DEFAULT_TIMEOUT_LIMIT, DEFAULT_TIMEOUT_MIN_MS, DEFAULT_TIMEOUT_MAX_MS)
	return _success(peer_id, DEFAULT_TIMEOUT_LIMIT, DEFAULT_TIMEOUT_MIN_MS, DEFAULT_TIMEOUT_MAX_MS, true)


static func _resolve(boundary, peer_id: String) -> Dictionary:
	if boundary == null or peer_id.strip_edges().is_empty():
		return _failure("MVP6_ENET_GUARD_ARGUMENT_INVALID")
	var port = boundary.get("_port")
	if port == null:
		return _failure("MVP6_ENET_GUARD_PORT_MISSING")
	var peers = port.get("_packet_peer_by_peer")
	if not peers is Dictionary:
		return _failure("MVP6_ENET_GUARD_PEER_MAP_MISSING")
	var packet_peer = peers.get(peer_id)
	if packet_peer == null or not packet_peer.has_method("set_timeout") or not packet_peer.has_method("is_active"):
		return _failure("MVP6_ENET_GUARD_PACKET_PEER_MISSING")
	if not bool(packet_peer.is_active()):
		return _failure("MVP6_ENET_GUARD_PACKET_PEER_INACTIVE")
	return {"success": true, "error_code": "", "details": {}, "packet_peer": packet_peer}


static func _success(peer_id: String, limit: int, minimum_ms: int, maximum_ms: int, restored: bool) -> Dictionary:
	return {
		"success": true,
		"error_code": "",
		"details": {
			"peer_id": peer_id,
			"timeout_limit": limit,
			"timeout_min_ms": minimum_ms,
			"timeout_max_ms": maximum_ms,
			"restored_default": restored,
			"payload_limit_changed": false,
			"reconnect_policy_changed": false,
			"shared_transport_changed": false,
		},
	}


static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "details": {}}

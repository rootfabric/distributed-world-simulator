extends RefCounted

# MVP6-only guard for the intentionally heavy synchronous base-100 Construction
# command on pinned CI hardware. It does NOT change the shared transport,
# payload cap, ordering, reconnect policy, or any MVP3-MVP5 default. The guard
# reaches the already-established ENetPacketPeer and only widens ENet's liveness
# window while that authority is unable to poll during the canonical command.
const TIMEOUT_LIMIT := 128
const TIMEOUT_MIN_MS := 60000
const TIMEOUT_MAX_MS := 120000


static func apply(boundary, peer_id: String) -> Dictionary:
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
	packet_peer.set_timeout(TIMEOUT_LIMIT, TIMEOUT_MIN_MS, TIMEOUT_MAX_MS)
	return {
		"success": true,
		"error_code": "",
		"details": {
			"peer_id": peer_id,
			"timeout_limit": TIMEOUT_LIMIT,
			"timeout_min_ms": TIMEOUT_MIN_MS,
			"timeout_max_ms": TIMEOUT_MAX_MS,
			"payload_limit_changed": false,
			"reconnect_policy_changed": false,
			"shared_transport_changed": false,
		},
	}


static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "details": {}}

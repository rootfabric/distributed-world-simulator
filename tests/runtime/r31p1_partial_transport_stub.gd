extends "res://scripts/network/transports/v2/network_transport_port_v2.gd"

# Native deterministic real-boundary fixture: no ENet socket, but uses the
# ACTUAL NetworkTransportBoundaryV2 queues, session, coalescing and receipts.
const Frame = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")
const Wire = preload("res://scripts/network/contracts/network_contract_utils.gd")

var fail_peer_once := ""
var accepted: Array[Dictionary] = []
var attempted: Array[Dictionary] = []


func get_descriptor() -> Dictionary:
	return {
		"schema": SCHEMA,
		"transport_kind": "ENET_MULTI_PEER",
		"supports_server": true,
		"supports_client": false,
		"synchronous_delivery": false,
		"multi_peer": true,
		"max_peers": 16,
	}


func start_server(_endpoint: Dictionary) -> Dictionary:
	return TransportUtilsScript.success()


func send_to_peer(peer_id: String, frame: Dictionary) -> Dictionary:
	var native: Dictionary = Frame.validate(frame)
	if not bool(native.get("success", false)):
		return native
	attempted.append({
		"peer": peer_id, "frame_id": String(frame.get("frame_id", "")),
		"session_id": String(frame.get("session_id", "")),
		"sequence": int(frame.get("sequence", 0)),
	})
	if peer_id == fail_peer_once:
		fail_peer_once = ""
		return TransportUtilsScript.failure("TEST_ENET_SEND_FAILED")
	accepted.append({
		"peer": peer_id, "frame_id": String(frame.get("frame_id", "")),
		"session_id": String(frame.get("session_id", "")),
		"sequence": int(frame.get("sequence", 0)),
		"payload_checksum": String(frame.get("payload_checksum", "")),
	})
	return TransportUtilsScript.success({
		"packet_bytes": Wire.canonical_json(frame).to_utf8_buffer().size()})


func stop() -> Dictionary:
	return TransportUtilsScript.success()

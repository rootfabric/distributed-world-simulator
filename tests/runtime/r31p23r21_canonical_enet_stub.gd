extends "res://scripts/network/transports/v2/network_transport_port_v2.gd"

# Native test-only ENet-contract delegate. This is NOT a product replacement
# for ENet. It retains exact FrameScript validation/encode and returns actual
# canonical bytes, allowing deterministic LOCAL passthrough size parity tests.
const Frame = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")

var enabled := false
var omit_packet_size := false
var accepted: Array[Dictionary] = []


func get_descriptor() -> Dictionary:
    return {
        "schema": SCHEMA,
        "transport_kind": "ENET_MULTI_PEER",
        "supports_server": true,
        "supports_client": true,
        "synchronous_delivery": false,
        "multi_peer": true,
        "max_peers": 32,
    }


func configure_r31p23r21_single_pass_compact(value: bool) -> Dictionary:
    enabled = value
    return TransportUtilsScript.success({"enabled": enabled})


func start_server(_endpoint: Dictionary) -> Dictionary:
    return TransportUtilsScript.success()


func send_to_peer(peer_id: String, frame: Dictionary) -> Dictionary:
    var native_validation: Dictionary = Frame.validate(frame)
    if not bool(native_validation.get("success", false)):
        return TransportUtilsScript.failure(String(native_validation.get(
            "error_code", "INVALID_FRAME")))
    var packet_result: Dictionary = Frame.encode(frame)
    if not bool(packet_result.get("success", false)):
        return packet_result
    var packet_bytes: PackedByteArray = Dictionary(packet_result.get(
        "details", {})).get("packet", PackedByteArray())
    accepted.append({
        "peer_id": peer_id,
        "frame": frame.duplicate(true),
        "packet": packet_bytes.duplicate(),
        "packet_bytes": packet_bytes.size(),
    })
    if omit_packet_size:
        return TransportUtilsScript.success({"enqueued":true})
    return TransportUtilsScript.success({
        "enqueued": true,
        "packet_bytes": packet_bytes.size(),
    })


func stop() -> Dictionary:
    return TransportUtilsScript.success()

extends SceneTree

# NET-SMOOTH1 R31 P2.3 R2.1 — EXACT SAME canonical packet bytes on/off,
# with the full checksum validator invoked in the original ENet send path.
# No transport session or M6 authority state may be passed to a worker.
const Runtime = preload(
    "res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd")
const Frame = preload(
    "res://scripts/network/transports/v2/protocol_frame_v2.gd")
const Enet = preload(
    "res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
const Wire = preload(
    "res://scripts/network/contracts/network_contract_utils.gd")

var checks := 0
var errors: Array[String] = []


func _init() -> void:
    call_deferred("_run")


func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        errors.append(label)


func _port() -> int:
    var socket := PacketPeerUDP.new()
    if socket.bind(0, "127.0.0.1") != OK:
        return 0
    var port: int = socket.get_local_port()
    socket.close()
    return port


func _path(label: String) -> String:
    return ProjectSettings.globalize_path(
        "res://artifacts/net-smooth1/r31p23r21-%s-%d" % [
            label, Time.get_ticks_usec()])


func _config(label: String, enabled: bool = false) -> Dictionary:
    var result: Dictionary = {
        "host": "127.0.0.1", "port": _port(),
        "playable_sandbox": true, "product_seam_enabled": true,
        "persistence_root": _path(label),
    }
    if enabled:
        result.merge({
            "r3c4_periodic_frame_pacing_canary": true,
            "r3c4r2_worker_envelope_canary": true,
            "r3c4r31_replay_projection_canary": true,
            "r3c4r31b_durable_attribution_canary": true,
            "r31bp1_durable_chunks_canary": true,
            "r31p22_loop_attribution_canary": true,
            "r31p23r2_flush_attribution_canary": true,
            "r31p23r21_single_pass_compact_canary": true,
        })
    return result


func _source_checksum(frame: Dictionary) -> String:
    return Wire.canonical_json(frame).sha256_text()


func _packet_parity() -> void:
    var port = Enet.new()
    check(bool(port.configure_r31p23r21_single_pass_compact(true).get(
        "success", false)), "internal ENet canary config")
    # Immutable, canonical, pure value snapshots: NO mutable Node/Resource.
    for i in range(1, 33):
        var payload: Dictionary = {
            "type": "COMPACT_GAMEPLAY_SNAPSHOT",
            "server_sent_at_ms": 1700 + i,
            "reason": "MOVEMENT_NETWORK_TICK",
            "snapshot": {
                "schema": "planet_simulator.compact_gameplay_snapshot.v1",
                "revision": i,
                "server_tick": i * 3,
                "players": [{"id": "player/alpha", "x": float(i) / 3.0,
                             "inventory": ["object/safe", i],
                             "alive": true}],
            },
        }
        var frame: Dictionary = Frame.create(
            "frame/peer-a/%d" % i,
            "transport-session/peer-a/a",
            i, "SNAPSHOT", "UNRELIABLE_SEQUENCED",
            "planet_simulator.m3_network_message.v1", payload)
        var check_result: Dictionary = Frame.validate(frame)
        check(bool(check_result.get("success", false)),
              "full native checksum validation for input %d" % i)
        if not bool(check_result.get("success", false)):
            continue
        var before_hash: String = _source_checksum(frame)
        var normal: Dictionary = Frame.encode(frame, 1048576)
        var fast: Dictionary = port.call(
            "_r31p23r21_encode_after_frame_validate", frame, 1048576)
        check(bool(normal.get("success", false)) and
              bool(fast.get("success", false)),
              "both encoders accept same validated snapshot %d" % i)
        if bool(normal.get("success", false)) and bool(fast.get("success", false)):
            var normal_bytes: PackedByteArray = Dictionary(normal.get(
                "details", {})).get("packet", PackedByteArray())
            var fast_bytes: PackedByteArray = Dictionary(fast.get(
                "details", {})).get("packet", PackedByteArray())
            check(normal_bytes == fast_bytes,
                  "byte-for-byte canonical equality %d" % i)
            check(normal_bytes.size() == fast_bytes.size(),
                  "packet byte-length identity %d" % i)
            var decoded: Dictionary = Frame.decode(fast_bytes)
            check(bool(decoded.get("success", false)),
                  "full RECEIVER checksum + canonical packet verification %d" % i)
            if bool(decoded.get("success", false)):
                check(Dictionary(decoded.get("details", {})).get("frame") == frame,
                      "decoded wire frame exactly equals original %d" % i)
        check(_source_checksum(frame) == before_hash,
              "encode must not mutate caller-owned frame %d" % i)

    # Exactly the SAME error codes/byte-count for packet limit on a VALID
    # previously checked frame; no skipping 1MB transport guards.
    var bigger_payload: Dictionary = {
        "type": "COMPACT_GAMEPLAY_SNAPSHOT",
        "data": "packet-limit-must-fail-but-not-lose-checksum"
    }
    var large_frame: Dictionary = Frame.create(
        "frame/peer-a/99", "transport-session/peer-a/a", 99,
        "SNAPSHOT", "UNRELIABLE_SEQUENCED",
        "planet_simulator.m3_network_message.v1", bigger_payload)
    check(bool(Frame.validate(large_frame).get("success",false)),
          "oversize test input is correctly checksum validated")
    var regular_limited: Dictionary = Frame.encode(large_frame, 32)
    var fast_limited: Dictionary = port.call(
        "_r31p23r21_encode_after_frame_validate", large_frame, 32)
    check(not bool(regular_limited.get("success",true)) and
          not bool(fast_limited.get("success",true)),
          "both encoders enforce packet byte limit")
    check(String(regular_limited.get("error_code","")) ==
          String(fast_limited.get("error_code","")) and
          String(fast_limited.get("error_code",""))=="PACKET_TOO_LARGE",
          "oversized error code identity")
    check(Dictionary(regular_limited.get("details",{})).get("packet_bytes")==
          Dictionary(fast_limited.get("details",{})).get("packet_bytes"),
          "oversized actual packet size preserved")

    # RED: invalid source is ALWAYS checked by the real original
    # FrameScript.validate(frame) before any R2.1 helper can be called.
    var tampered: Dictionary = large_frame.duplicate(true)
    tampered["payload"]["data"] = "changed AFTER full checksum"
    var validation: Dictionary = Frame.validate(tampered)
    var baseline: Dictionary = Frame.encode(tampered,1048576)
    check(not bool(validation.get("success",true)) and
          String(validation.get("error_code",""))=="PAYLOAD_CHECKSUM_MISMATCH",
          "native frame validator catches tampered nested payload")
    check(not bool(baseline.get("success",true)) and
          String(baseline.get("error_code",""))=="PAYLOAD_CHECKSUM_MISMATCH",
          "baseline encoder rejects nested checksum mismatch")
    for key in ["session_id","sequence","channel","delivery_mode"]:
        var bad: Dictionary = large_frame.duplicate(true)
        if key=="sequence":
            bad[key]=0
        elif key=="channel":
            bad[key]="NOT_A_CHANNEL"
        elif key=="delivery_mode":
            bad[key]="NOT_A_DELIVERY"
        else:
            bad[key]="not-a-canonical-session"
        var left: Dictionary = Frame.validate(bad)
        var right: Dictionary = Frame.encode(bad)
        check(not bool(left.get("success",true)) and
              String(left.get("error_code","")) ==
              String(right.get("error_code","")),
              "invalid %s keeps exact original error" % key)
    port.free()


func _run() -> void:
    OS.set_environment("DWS_NET_R31P23R21_SINGLE_PASS_COMPACT","invalid")
    var invalid = Runtime.new()
    var bad: Dictionary = invalid.setup(_config("invalid"))
    check(not bool(bad.get("success",false)) and
        String(bad.get("error_code",""))=="R31P23R21_INVALID_MODE",
        "invalid R2.1 opt-in fails before startup")
    invalid.free()
    OS.set_environment("DWS_NET_R31P23R21_SINGLE_PASS_COMPACT","")

    var denied = Runtime.new()
    var denied_config: Dictionary = _config("denied")
    denied_config["r31p23r21_single_pass_compact_canary"]=true
    var denied_result: Dictionary = denied.setup(denied_config)
    check(not bool(denied_result.get("success",false)) and
        String(denied_result.get("error_code",""))==
        "R31P23R21_REQUIRES_R2P0_FLUSH_ATTRIBUTION",
        "R2.1 requires frozen R2.0 profile/USER1/P1 lineage")
    denied.free()

    var off = Runtime.new()
    var regular: Dictionary = off.setup(_config("off"))
    check(bool(regular.get("success",false)),
          "original default server starts")
    if bool(regular.get("success",false)):
        off.set_process(false)
        check(not bool(off.get("_r31p23r21_single_pass_compact_enabled")),
              "R2.1 server OFF by default")
        var boundary = off.get("_boundary")
        check(boundary!=null and not bool(boundary.get(
            "_r31p23r21_single_pass_compact_enabled")),
            "boundary OFF by default")
        if boundary!=null:
            var sim = boundary.get("_port")
            check(sim!=null and not bool(sim.get(
                "_r31p23r21_single_pass_compact_enabled")),
                "simulator OFF by default")
            if sim!=null:
                var enet = sim.get("_delegate")
                check(enet!=null and not bool(enet.get(
                    "_r31p23r21_single_pass_compact_enabled")),
                    "ENet OFF by default")
        check(bool(off.stop().get("success",false)),
              "unchanged M6 default shutdown")
    off.free()

    var on = Runtime.new()
    var ready: Dictionary = on.setup(_config("on",true))
    check(bool(ready.get("success",false)),
          "R2.1 exact server + native M6 stack starts")
    if bool(ready.get("success",false)):
        on.set_process(false)
        check(bool(on.get("_r31p23r21_single_pass_compact_enabled")),
              "R2.1 main server ON")
        var boundary = on.get("_boundary")
        check(boundary!=null and bool(boundary.get(
            "_r31p23r21_single_pass_compact_enabled")),
            "R2.1 boundary ON")
        if boundary!=null:
            var sim = boundary.get("_port")
            check(sim!=null and bool(sim.get(
                "_r31p23r21_single_pass_compact_enabled")),
                "R2.1 simulator ON")
            if sim!=null:
                var enet = sim.get("_delegate")
                check(enet!=null and bool(enet.get(
                    "_r31p23r21_single_pass_compact_enabled")),
                    "R2.1 ENet ON")
        check(bool(on.stop().get("success",false)),
              "unchanged native durable M6 shutdown")
    on.free()
    _packet_parity()

    for error in errors:
        push_error("NET_SMOOTH_R31P23R21_FAIL:" + error)
    print("NET_SMOOTH_R31P23R21 %s assertions=%d failures=%d" % [
        "PASS" if errors.is_empty() else "FAIL",checks,errors.size()])
    quit(0 if errors.is_empty() else 1)

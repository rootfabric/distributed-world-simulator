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
const ConditionSimulator = preload(
    "res://scripts/network/conditions/network_condition_simulator_port.gd")
const ConditionProfile = preload(
    "res://scripts/network/conditions/network_condition_profile.gd")
const Stub = preload(
    "res://tests/runtime/r31p23r21_canonical_enet_stub.gd")

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
                var decoded_frame: Dictionary = Dictionary(
                    decoded.get("details", {})).get("frame", {})
                # Godot JSON can retype numeric Variant scalars on roundtrip;
                # strict Dictionary == is NOT the wire-byte identity contract.
                # Frame.decode already checks native payload hash and exact
                # canonical packet text against these same bytes.
                check(Wire.canonical_json(decoded_frame) ==
                      Wire.canonical_json(frame),
                      "decoded canonical JSON bytes exactly match original %d" % i)
                check(String(decoded_frame.get("payload_checksum", "")) ==
                      String(frame.get("payload_checksum", "")),
                      "decoded native payload checksum identity %d" % i)
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
    port = null


# Real ConditionSimulatorPort LOCAL/passthrough path with an exact
# FrameScript-validating ENet-contract delegate. Proves the optimized byte
# count is the SAME as actual encoded canonical wire bytes; malformed frames
# are still rejected before a delegate call.
func _simulator_passthrough_parity() -> void:
    var delegate = Stub.new()
    var simulated = ConditionSimulator.new()
    var profile: Dictionary = ConditionProfile.create("LOCAL", {})
    check(bool(ConditionProfile.validate(profile).get("success", false)),
          "valid canonical LOCAL zero-condition profile")
    check(bool(simulated.setup(delegate, profile).get("success", false)),
          "real simulator setup with test-only canonical ENet delegate")
    check(bool(simulated.start_server({}).get("success", false)),
          "real simulator starts same LOCAL passthrough path")

    var frame: Dictionary = Frame.create(
        "frame/test-r21/1", "transport-session/test-r21/a", 1,
        "SNAPSHOT", "UNRELIABLE_SEQUENCED",
        "planet_simulator.m3_network_message.v1",
        {"type":"COMPACT_GAMEPLAY_SNAPSHOT",
         "server_sent_at_ms":12,
         "snapshot":{"schema":"planet_simulator.compact_gameplay_snapshot.v1",
                     "revision":3,"server_tick":90}})
    check(bool(Frame.validate(frame).get("success",false)),
          "simulator test frame checksum valid")
    var before: Dictionary = frame.duplicate(true)
    var legacy: Dictionary = simulated.send_to_peer("peer/test-r21",frame)
    check(bool(legacy.get("success", false)),
          "legacy simulator passthrough sends exactly one frame")
    var baseline_bytes: int = int(Dictionary(
        legacy.get("details", {})).get("packet_bytes",-1))
    check(delegate.accepted.size()==1, "legacy delegate invoked once")

    check(bool(simulated.configure_r31p23r21_single_pass_compact(
        true).get("success",false)), "opt-in propagated to canonical delegate")
    check(bool(delegate.enabled), "R21 propagated to actual ENet contract")
    var fast: Dictionary = simulated.send_to_peer("peer/test-r21",frame)
    check(bool(fast.get("success",false)), "R21 LOCAL passthrough sends one frame")
    check(delegate.accepted.size()==2, "R21 no extra packet/retry")
    var new_bytes: int = int(Dictionary(
        fast.get("details",{})).get("packet_bytes",-1))
    check(new_bytes==baseline_bytes and new_bytes>0,
          "exact canonical encoded packet size reused")
    if delegate.accepted.size()==2:
        var old_packet: PackedByteArray = Dictionary(delegate.accepted[0]).get(
            "packet", PackedByteArray())
        var new_packet: PackedByteArray = Dictionary(delegate.accepted[1]).get(
            "packet", PackedByteArray())
        check(old_packet==new_packet, "LOCAL real canonical wire bytes bit equal")
        check(old_packet.size()==new_bytes,
              "delegate's validated packet exact bytes = simulator count")
    check(frame==before, "simulator cannot mutate caller-owned validated frame")

    var corrupted: Dictionary = frame.duplicate(true)
    corrupted["payload"]["snapshot"]["revision"]=999
    var rejected: Dictionary = simulated.send_to_peer(
        "peer/test-r21",corrupted)
    check(not bool(rejected.get("success",true)) and
          String(rejected.get("error_code",""))=="PAYLOAD_CHECKSUM_MISMATCH",
          "R21 still catches tampered nested frame before ENet")
    check(delegate.accepted.size()==2,
          "tampered frame never sent to delegate")
    delegate.omit_packet_size=true
    var unproven: Dictionary = simulated.send_to_peer(
        "peer/test-r21",frame)
    check(not bool(unproven.get("success",true)) and
          String(unproven.get("error_code",""))==
          "R31P23R21_DELEGATE_PACKET_SIZE_MISSING",
          "fail closed if canonical delegate has no proved encoded size")
    simulated.stop()

    # Under nonpassthrough network conditions R21 must retain the ORIGINAL
    # size calculation and scheduling; no immediate delegated packet exists.
    var delayed_port = Stub.new()
    var delayed = ConditionSimulator.new()
    var delayed_profile: Dictionary = ConditionProfile.create(
        "LATENCY_TEST", {"outgoing_latency_min_ms": 5,
                         "outgoing_latency_max_ms": 5})
    check(bool(delayed.setup(delayed_port, delayed_profile).get(
        "success", false)), "delayed profile actual ConditionSimulator setup")
    check(bool(delayed.start_server({}).get("success", false)),
          "delayed network condition profile server started")
    check(bool(delayed.configure_r31p23r21_single_pass_compact(
        true).get("success",false)), "R21 optin does not bypass simulated conditions")
    var delay_result: Dictionary = delayed.send_to_peer("peer/test-r21",frame)
    check(bool(delay_result.get("success",false)) and
          bool(Dictionary(delay_result.get("details",{})).get("simulated",false)),
          "simulated profile still queues instead of pretending ENet success")
    check(delayed_port.accepted.is_empty(),
          "simulated packet not falsely considered immediately sent")
    check(int(Dictionary(delay_result.get("details",{})).get(
        "packet_bytes",-1))==baseline_bytes,
        "nonpassthrough packet sizing remains exact legacy JSON")
    delayed.stop()
    delayed_port = null
    delegate = null


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
    _simulator_passthrough_parity()

    for error in errors:
        push_error("NET_SMOOTH_R31P23R21_FAIL:" + error)
    print("NET_SMOOTH_R31P23R21 %s assertions=%d failures=%d" % [
        "PASS" if errors.is_empty() else "FAIL",checks,errors.size()])
    quit(0 if errors.is_empty() else 1)

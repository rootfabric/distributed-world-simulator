extends SceneTree

# NET-SMOOTH1 P2.3 R2.0 — real native server boundary/simulator/ENet opt-in.
# No COMPACT wire protocol, sequence, ACK or fixed tick source is changed.
const Runtime = preload(
    "res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
    call_deferred("_run")


func check(ok: bool, label: String) -> void:
    assertions += 1
    if not ok:
        failures.append(label)


func _port() -> int:
    var sock := PacketPeerUDP.new()
    if sock.bind(0, "127.0.0.1") != OK:
        return 0
    var n := sock.get_local_port()
    sock.close()
    return n


func _path(label: String) -> String:
    return ProjectSettings.globalize_path(
        "res://artifacts/net-smooth1/r31p23r2-%s-%d" % [
            label, Time.get_ticks_usec()])


func _config(label: String, enabled: bool = false) -> Dictionary:
    var config := {
        "host": "127.0.0.1", "port": _port(),
        "playable_sandbox": true,
        "product_seam_enabled": true,
        "persistence_root": _path(label),
    }
    if enabled:
        config.merge({
            "r3c4_periodic_frame_pacing_canary": true,
            "r3c4r2_worker_envelope_canary": true,
            "r3c4r31_replay_projection_canary": true,
            "r3c4r31b_durable_attribution_canary": true,
            "r31bp1_durable_chunks_canary": true,
            "r31p22_loop_attribution_canary": true,
            "r31p23r2_flush_attribution_canary": true,
        })
    return config


func _run() -> void:
    OS.set_environment("DWS_NET_R31P23R2_FLUSH_ATTRIBUTION", "invalid")
    var bad = Runtime.new()
    var result: Dictionary = bad.setup(_config("invalid"))
    check(not bool(result.get("success", false)) and
        String(result.get("error_code", "")) == "R31P23R2_INVALID_MODE",
        "invalid mode rejected before transport startup")
    bad.free()
    OS.set_environment("DWS_NET_R31P23R2_FLUSH_ATTRIBUTION", "")

    var denied = Runtime.new()
    var cfg := _config("denied")
    cfg["r31p23r2_flush_attribution_canary"] = true
    var no_parent: Dictionary = denied.setup(cfg)
    check(not bool(no_parent.get("success", false)) and
        String(no_parent.get("error_code", "")) ==
            "R31P23R2_REQUIRES_R31P22_LOOP_ATTRIBUTION",
        "R2.0 cannot run without R31P22/M6/USER1 stack")
    denied.free()

    var default = Runtime.new()
    var normal: Dictionary = default.setup(_config("default"))
    check(bool(normal.get("success", false)), "default server setup unchanged")
    if bool(normal.get("success", false)):
        default.set_process(false)
        check(not bool(default.get("_r31p23r2_flush_attribution_enabled")),
              "server flush attribution default OFF")
        var b = default.get("_boundary")
        check(b != null and not bool(b.get("_r31p23r2_attribution_enabled")),
              "transport boundary probe default OFF")
        if b != null:
            var simulator = b.get("_port")
            check(simulator != null and not bool(simulator.get("_r31p23r2_attribution_enabled")),
                  "network simulator probe default OFF")
            if simulator != null:
                var enet = simulator.get("_delegate")
                check(enet != null and not bool(enet.get("_r31p23r2_attribution_enabled")),
                      "ENet probe default OFF")
        check(bool(default.stop().get("success", false)),
              "default shutdown and ACK/durability barrier preserved")
    default.free()

    var runtime = Runtime.new()
    var active: Dictionary = runtime.setup(_config("on", true))
    check(bool(active.get("success", false)), "full-stack R2.0 server boot")
    if bool(active.get("success", false)):
        runtime.set_process(false)
        check(bool(runtime.get("_r31p23r2_flush_attribution_enabled")),
              "R2.0 server canary active")
        var boundary = runtime.get("_boundary")
        check(boundary != null and
              bool(boundary.get("_r31p23r2_attribution_enabled")),
              "boundary probe receives explicit server flag")
        if boundary != null:
            var sim = boundary.get("_port")
            check(sim != null and bool(sim.get("_r31p23r2_attribution_enabled")),
                  "simulation layer stage probe configured")
            if sim != null:
                var enet = sim.get("_delegate")
                check(enet != null and bool(enet.get("_r31p23r2_attribution_enabled")),
                      "real ENet layer receives same opt-in")
        check(bool(runtime.stop().get("success", false)),
              "R2.0 real M6 shutdown unchanged")
    runtime.free()

    for msg in failures:
        push_error("NET_SMOOTH_R31P23R2_FAIL:" + msg)
    print("NET_SMOOTH_R31P23R2 %s assertions=%d failures=%d" % [
        "PASS" if failures.is_empty() else "FAIL",
        assertions, failures.size()])
    quit(0 if failures.is_empty() else 1)

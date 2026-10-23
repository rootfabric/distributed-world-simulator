extends SceneTree

# NET-SMOOTH1 R31 P2.3 R0 — exact mode gates for completion-only attribution.
# This suite never asks the writer to block, and does not alter M6 protocol.
const Runtime = preload(
    "res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
    call_deferred("_run")


func check(ok: bool, message: String) -> void:
    assertions += 1
    if not ok:
        failures.append(message)


func _path(name: String) -> String:
    return ProjectSettings.globalize_path(
        "res://artifacts/net-smooth1/r31p23-%s-%d" % [name, Time.get_ticks_usec()])


func _port() -> int:
    var socket := PacketPeerUDP.new()
    if socket.bind(0, "127.0.0.1") != OK:
        return 0
    var port := socket.get_local_port()
    socket.close()
    return port


func _run() -> void:
    OS.set_environment("DWS_NET_R31P23_COMPLETION_ATTRIBUTION", "invalid")
    var invalid = Runtime.new()
    var invalid_result: Dictionary = invalid.setup({
        "host": "127.0.0.1", "port": _port(),
        "playable_sandbox": true, "product_seam_enabled": true,
        "persistence_root": _path("invalid"),
    })
    check(not bool(invalid_result.get("success", false)) and
        String(invalid_result.get("error_code", "")) == "R31P23_INVALID_MODE",
        "invalid environment is rejected without starting a server")
    invalid.free()
    OS.set_environment("DWS_NET_R31P23_COMPLETION_ATTRIBUTION", "")

    var not_allowed = Runtime.new()
    var denied: Dictionary = not_allowed.setup({
        "host": "127.0.0.1", "port": _port(),
        "playable_sandbox": true, "product_seam_enabled": true,
        "persistence_root": _path("denied"),
        "r31p23_completion_attribution_canary": true,
    })
    check(not bool(denied.get("success", false)) and
        String(denied.get("error_code", "")) ==
            "R31P23_REQUIRES_R31P22_LOOP_ATTRIBUTION",
        "P2.3 R0 requires P2.2 / owner-native canary")
    not_allowed.free()

    var normal = Runtime.new()
    var normal_result: Dictionary = normal.setup({
        "host": "127.0.0.1", "port": _port(),
        "playable_sandbox": true, "product_seam_enabled": true,
        "persistence_root": _path("normal"),
    })
    check(bool(normal_result.get("success", false)), "existing server still boots")
    if bool(normal_result.get("success", false)):
        normal.set_process(false)
        check(not bool(normal.get("_r31p23_completion_attribution_enabled")),
            "P2.3 diagnostic disabled by default")
        check(bool(normal.stop().get("success", false)),
            "normal single M6 shutdown barrier unchanged")
    normal.free()

    var server = Runtime.new()
    var live: Dictionary = server.setup({
        "host": "127.0.0.1", "port": _port(),
        "playable_sandbox": true, "product_seam_enabled": true,
        "persistence_root": _path("live"),
        "r3c4_periodic_frame_pacing_canary": true,
        "r3c4r2_worker_envelope_canary": true,
        "r3c4r31_replay_projection_canary": true,
        "r3c4r31b_durable_attribution_canary": true,
        "r31bp1_durable_chunks_canary": true,
        "r31p22_loop_attribution_canary": true,
        "r31p23_completion_attribution_canary": true,
    })
    check(bool(live.get("success", false)), "real P2.3 canary full-stack server")
    if bool(live.get("success", false)):
        server.set_process(false)
        check(bool(server.get("_r31p22_loop_attribution_enabled")),
            "P2.2 frame identity active")
        check(bool(server.get("_r31p23_completion_attribution_enabled")),
            "P2.3 completion attribution active")
        check(bool(server.stop().get("success", false)),
            "P2.3 still uses unchanged M6 shutdown fence")
    server.free()

    for error in failures:
        push_error("R31P23_R0_FAIL:" + error)
    print("NET_SMOOTH_R31P23_R0 %s assertions=%d failures=%d" % [
        "PASS" if failures.is_empty() else "FAIL",
        assertions, failures.size()])
    quit(0 if failures.is_empty() else 1)

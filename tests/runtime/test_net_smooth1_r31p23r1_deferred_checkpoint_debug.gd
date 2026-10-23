extends SceneTree

# NET-SMOOTH1 P2.3 R1: actual server owner/debug FIFO and safety gates.
# The guarded stdout path is not part of gameplay authority or M6 durable ACK.
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
    var port := sock.get_local_port()
    sock.close()
    return port


func _path(label: String) -> String:
    return ProjectSettings.globalize_path(
        "res://artifacts/net-smooth1/r31p23r1-%s-%d" % [
            label, Time.get_ticks_usec()])


func _config(label: String, enable: bool = false) -> Dictionary:
    var value: Dictionary = {
        "host": "127.0.0.1", "port": _port(),
        "playable_sandbox": true,
        "persistence_root": _path(label),
        "product_seam_enabled": true,
    }
    if enable:
        value.merge({
            "r3c4_periodic_frame_pacing_canary": true,
            "r3c4r2_worker_envelope_canary": true,
            "r3c4r31_replay_projection_canary": true,
            "r3c4r31b_durable_attribution_canary": true,
            "r31bp1_durable_chunks_canary": true,
            "r31p22_loop_attribution_canary": true,
            "r31p23_completion_attribution_canary": true,
            "r31p23r1_defer_checkpoint_debug_canary": true,
        })
    return value


func _run() -> void:
    OS.set_environment("DWS_NET_R31P23R1_DEFER_CHECKPOINT_DEBUG", "invalid")
    var bad = Runtime.new()
    var invalid: Dictionary = bad.setup(_config("invalid"))
    check(not bool(invalid.get("success", false)) and
        String(invalid.get("error_code", "")) == "R31P23R1_INVALID_MODE",
        "invalid environment rejected before gameplay startup")
    bad.free()
    OS.set_environment("DWS_NET_R31P23R1_DEFER_CHECKPOINT_DEBUG", "")

    var missing = Runtime.new()
    var denied: Dictionary = _config("missing")
    denied["r31p23r1_defer_checkpoint_debug_canary"] = true
    var missing_result: Dictionary = missing.setup(denied)
    check(not bool(missing_result.get("success", false)) and
        String(missing_result.get("error_code", "")) ==
            "R31P23R1_REQUIRES_P23_COMPLETION_ATTRIBUTION",
        "R1 requires exact measured P23 completion stack")
    missing.free()

    var off = Runtime.new()
    var started: Dictionary = off.setup(_config("default"))
    check(bool(started.get("success", false)), "default production server boots")
    if bool(started.get("success", false)):
        off.set_process(false)
        check(not bool(off.get("_r31p23r1_deferred_checkpoint_debug_enabled")),
              "R1 OFF without explicit canary")
        check(not bool(off.get_r31p23r1_debug_report().get("enabled", true)),
              "default debug queue cannot intercept periodic output")
        check(bool(off.stop().get("success", false)),
              "default M6 shutdown unchanged")
    off.free()

    var server = Runtime.new()
    var live: Dictionary = server.setup(_config("on", true))
    check(bool(live.get("success", false)), "real P23R1 opt-in server boots")
    if bool(live.get("success", false)):
        server.set_process(false)
        check(bool(server.get("_r31p23r1_deferred_checkpoint_debug_enabled")),
              "P23R1 flag active")
        # Avoid introducing a noisy LIVE2 watchdog into this headless test.
        # Actual Godot GUI always sets --network-debug through the harness.
        server.set("_debug_logging", true)
        var frame: int = Engine.get_process_frames()
        server.call("_r31p23r1_enqueue_completion_debug", 100)
        server.call("_r31p23r1_enqueue_completion_debug", 101)
        var queued: Dictionary = server.get_r31p23r1_debug_report()
        check(int(queued.get("queued", -1)) == 2, "two immutable generation logs queued")
        check(int(queued.get("pending", -1)) == 2, "both entries remain pending")
        check(int(queued.get("flushed", -1)) == 0, "nothing printed on completion")
        check(int(queued.get("overflow_sync", -1)) == 0, "no overflow fallback")

        var premature: Dictionary = server.call("_r31p23r1_take_next_debug_line", frame)
        check(premature.is_empty(), "same-frame print forbidden")
        check(int(server.get_r31p23r1_debug_report().get("pending", -1)) == 2,
              "same-frame read cannot remove FIFO entry")
        var first: Dictionary = server.call("_r31p23r1_take_next_debug_line", frame + 1)
        check(int(first.get("generation", -1)) == 100, "FIFO generation order")
        var line: String = String(first.get("line", ""))
        check(line.begins_with("[m7_server] "), "exact legacy debug prefix")
        var parsed = JSON.parse_string(line.trim_prefix("[m7_server] "))
        check(parsed is Dictionary, "deferred line is valid JSON")
        if parsed is Dictionary:
            check(String(parsed.get("event", "")) == "MOVEMENT_CHECKPOINT_COMMITTED",
                  "original debug event name kept")
            check(int(parsed.get("process_id", 0)) == OS.get_process_id(),
                  "original actual main process ID kept")
            check(int(parsed.get("time_msec", 0)) > 0,
                  "original completion event time retained")
            check(int(parsed.get("details", {}).get("generation", -1)) == 100,
                  "generation identity survives deferral")
            check(bool(parsed.get("details", {}).get("async", false)),
                  "async completion flag retained")
        var next: Dictionary = server.call("_r31p23r1_take_next_debug_line", frame + 1)
        check(int(next.get("generation", -1)) == 101,
              "next FIFO entry never silently replaced")
        check(int(server.get_r31p23r1_debug_report().get("pending", -1)) == 0,
              "queue drained after exact reads")

        server.call("_r31p23r1_enqueue_completion_debug", 102)
        var before_generation: int = int(server.get("_checkpoint_generation"))
        check(bool(server.stop().get("success", false)),
              "graceful shutdown drains debug queue without changing M6 ACK")
        check(int(server.get("_checkpoint_generation")) >= before_generation,
              "M6 generation cannot decrease from log drain")
        var after: Dictionary = server.get_r31p23r1_debug_report()
        check(int(after.get("pending", -1)) == 0,
              "graceful stop never leaves a debug line behind")
        check(int(after.get("flushed", -1)) >= 1,
              "queued debug entry prints at shutdown")
    server.free()

    for reason in failures:
        push_error("R31P23R1_FAIL:" + reason)
    print("NET_SMOOTH_R31P23R1 %s assertions=%d failures=%d" % [
        "PASS" if failures.is_empty() else "FAIL",
        assertions, failures.size()])
    quit(0 if failures.is_empty() else 1)

extends SceneTree

# NET-SMOOTH1 R31b P2.0 — exactly ONE native validation, stage timing only.
# Falsifies byte parity and error-code identity on real USER1 ProductSeam
# durable state. P1 cache, disk schema, M6 ACK are not changed.
const SeamService = preload(
    "res://scripts/runtime/networked_gameplay/user1/user1_product_seam_gameplay_service.gd")
const Adapter = preload(
    "res://scripts/runtime/networked_gameplay/m6/m6_dedicated_gameplay_authority_adapter.gd")
const Runtime = preload(
    "res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd")
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

var assertions := 0
var failures: Array[String] = []

const P20_REQUIRED_STAGES := [
    "total_ms", "base_layer_total_ms", "envelope_ms",
    "outer_checksum_validation_ms", "player_registry_ms",
    "ownership_ms", "shared_item_ms", "item_validator_setup_ms",
    "item_validator_validate_ms", "cross_domain_ms", "json_safety_ms",
    "resource_validator_ms", "resource_authority_ms",
]


func _init() -> void:
    call_deferred("_run")


func check(ok: bool, label: String) -> void:
    assertions += 1
    if not ok:
        failures.append(label)


func _run() -> void:
    OS.set_environment("DWS_NET_R31BP20_VALIDATOR_ATTRIBUTION", "")
    _test_real_ownership_validation_and_negative_cases()
    _test_runtime_mode_guard()
    for reason in failures:
        push_error("R31BP20_FAIL:" + reason)
    print("NET_SMOOTH_R31BP20_VALIDATOR %s assertions=%d failures=%d" % [
        "PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
    quit(0 if failures.is_empty() else 1)


func _path(name: String) -> String:
    return ProjectSettings.globalize_path(
        "res://artifacts/net-smooth1/r31bp20-%s-%d" % [name, Time.get_ticks_usec()])


func _port() -> int:
    var socket := PacketPeerUDP.new()
    if socket.bind(0, "127.0.0.1") != OK:
        return 0
    var port := socket.get_local_port()
    socket.close()
    return port


func _make_live_service():
    var service = SeamService.new()
    var configured: Dictionary = service.setup("authority/m3/p20", 1, 0, {
        "profile": "MULTIPLAYER_CORE",
        "topology_adapter": "ENET",
        "region_id": "region/m3/single-server",
        "playable_sandbox": true,
        "fixed_tick_authority": true,
    })
    check(bool(configured.get("success", false)), "USER1 native owner setup")
    if not bool(configured.get("success", false)):
        return null
    var joined: Dictionary = service.join(
        "p20-player", "transport-session/p20/a", "operation/p20/join/a")
    check(bool(joined.get("success", false)), "P20 real JOIN")
    if not bool(joined.get("success", false)):
        service.shutdown()
        return null
    var bound: Dictionary = service.call("_ensure_seam_binding", "p20-player")
    check(bool(bound.get("success", false)), "P20 real active seam")
    if not bool(bound.get("success", false)):
        service.shutdown()
        return null
    var ticked: Dictionary = service.advance_fixed_server_tick(1)
    check(bool(ticked.get("success", false)), "owner tick advances to joined_tick")
    if not bool(ticked.get("success", false)):
        service.shutdown()
        return null
    return service


func _assert_same_validation(service, value: Dictionary, label: String) -> void:
    var plain: Dictionary = service.validate_durable_state(value)
    var observed: Dictionary = service.validate_durable_state_p20_profiled(value)
    var timed: Dictionary = Dictionary(observed.get("validation", {}))
    check(plain == timed, label + ": exact result/cause parity")
    check(String(plain.get("error_code", "")) ==
          String(timed.get("error_code", "")), label + ": exact error-code parity")
    var stages: Dictionary = Dictionary(observed.get("stages", {}))
    check(float(stages.get("total_ms", -1.0)) >= 0.0, label + ": bounded profiler total")
    if bool(plain.get("success", false)):
        for stage in P20_REQUIRED_STAGES:
            check(float(stages.get(stage, -1.0)) >= 0.0,
                  label + ": stage " + stage)
        check(float(stages.get("base_layer_total_ms", -1.0)) <=
              float(stages.get("total_ms", 0.0)) + 1.0,
              label + ": base duration within total")
    var repeat: Dictionary = service.validate_durable_state(value)
    check(repeat == plain, label + ": instrumented call leaves no active sink")


func _test_real_ownership_validation_and_negative_cases() -> void:
    var service = _make_live_service()
    if service == null:
        return
    var canonical: Dictionary = service.export_durable_state()
    check(not canonical.is_empty(), "valid USER1 canonical durable JSON")
    if canonical.is_empty():
        service.shutdown()
        return
    _assert_same_validation(service, canonical, "valid source")

    var original_periodic: Dictionary = service.export_durable_state_r31b_profiled()
    check(Dictionary(original_periodic.get("value", {})) == canonical,
          "P20 default OFF periodic source exact")
    var original_stages: Dictionary = Dictionary(original_periodic.get("stages", {}))
    check(Dictionary(original_stages.get("r31bp20_validation_stages", {})).is_empty(),
          "P20 default OFF no stage capture")
    var canary: Dictionary = service.configure_r31bp20_validation_attribution(true)
    check(bool(canary.get("success", false)), "P20 server canary enables profiling")
    var with_attribution: Dictionary = service.export_durable_state_r31b_profiled()
    check(Dictionary(with_attribution.get("value", {})) == canonical,
          "P20 ON periodic durable payload checksum exact")
    var timing: Dictionary = Dictionary(with_attribution.get("stages", {}))
    var details: Dictionary = Dictionary(timing.get("r31bp20_validation_stages", {}))
    for stage in P20_REQUIRED_STAGES:
        check(float(details.get(stage, -1.0)) >= 0.0,
              "P20 real periodic " + stage)
    check(int(timing.get("seam_coordinator_count", 0)) >= 1,
          "P20 actual active seam measured")
    check(bool(timing.get("valid", false)), "P20 whole native validation still called")

    # Explicit negative states, not only a valid-source stopwatch.
    var broken_schema: Dictionary = canonical.duplicate(true)
    broken_schema["schema"] = "wrong"
    _assert_same_validation(service, broken_schema, "bad schema")

    var broken_checksum: Dictionary = canonical.duplicate(true)
    broken_checksum["checksum"] = "tampered"
    _assert_same_validation(service, broken_checksum, "bad outer checksum")

    var missing_players: Dictionary = canonical.duplicate(true)
    missing_players.erase("players")
    _assert_same_validation(service, missing_players, "missing players")

    var tampered_item: Dictionary = canonical.duplicate(true)
    var item: Dictionary = Dictionary(tampered_item.get("canonical_item_graph", {}))
    item["checksum"] = "tampered-item"
    tampered_item["canonical_item_graph"] = item
    tampered_item["checksum"] = ""
    tampered_item = Utils.finalize_json_checksum(tampered_item)
    _assert_same_validation(service, tampered_item, "bad nested M4 checksum")

    var tampered_resource: Dictionary = canonical.duplicate(true)
    var resource: Dictionary = Dictionary(tampered_resource.get("resource_mining", {}))
    resource["checksum"] = "tampered-resource"
    tampered_resource["resource_mining"] = resource
    tampered_resource["checksum"] = ""
    tampered_resource = Utils.finalize_json_checksum(tampered_resource)
    _assert_same_validation(service, tampered_resource, "bad mining checksum")

    var adapter = Adapter.new()
    check(bool(adapter.setup(service).get("success", false)), "M6 adapter setup")
    var direct: Dictionary = adapter.export_recovery_state()
    check(not direct.is_empty(), "direct M6 legacy export")
    var periodic_frozen: Dictionary = adapter.capture_frozen_gameplay_source_r31b_profiled()
    var source: Dictionary = Dictionary(periodic_frozen.get("frozen_gameplay", {}))
    var wrapped: Dictionary = Adapter.wrap_frozen_gameplay_source(source)
    check(wrapped == direct, "P20 periodic envelope exactly equals direct M6")
    service.shutdown()


func _test_runtime_mode_guard() -> void:
    OS.set_environment("DWS_NET_R31BP20_VALIDATOR_ATTRIBUTION", "garbage")
    var invalid = Runtime.new()
    var bad: Dictionary = invalid.setup({
        "host": "127.0.0.1", "port": _port(),
        "playable_sandbox": true, "persistence_root": _path("invalid"),
        "product_seam_enabled": true})
    check(not bool(bad.get("success", false)) and
          String(bad.get("error_code", "")) == "R31BP20_INVALID_MODE",
          "P20 invalid env fails closed")
    invalid.free()
    OS.set_environment("DWS_NET_R31BP20_VALIDATOR_ATTRIBUTION", "")

    var denied = Runtime.new()
    var no_p1: Dictionary = denied.setup({
        "host": "127.0.0.1", "port": _port(),
        "playable_sandbox": true, "product_seam_enabled": true,
        "persistence_root": _path("no-p1"),
        "r31bp20_validator_attribution_canary": true,
    })
    check(not bool(no_p1.get("success", false)) and
          String(no_p1.get("error_code", "")) ==
          "R31BP20_REQUIRES_P1_P0_REPLAY_R2_PERSISTENCE_SEAM",
          "P20 cannot run without P1/R31a/R2")
    denied.free()

    var live = Runtime.new()
    var ready: Dictionary = live.setup({
        "host": "127.0.0.1", "port": _port(),
        "playable_sandbox": true, "product_seam_enabled": true,
        "persistence_root": _path("ready"),
        "r3c4_periodic_frame_pacing_canary": true,
        "r3c4r2_worker_envelope_canary": true,
        "r3c4r31_replay_projection_canary": true,
        "r3c4r31b_durable_attribution_canary": true,
        "r31bp1_durable_chunks_canary": true,
        "r31bp20_validator_attribution_canary": true,
    })
    check(bool(ready.get("success", false)), "P20 real runtime initialized")
    if bool(ready.get("success", false)):
        live.set_process(false)
        check(bool(live.get("_r31bp20_validator_attribution_enabled")),
              "P20 server canary actually active")
        var real_service = live.get("_service")
        check(real_service != null and
              bool(real_service.get("_r31bp20_validation_attribution_enabled")),
              "P20 service is bound to real owner only")
        check(bool(live.stop().get("success", false)),
              "P20 unchanged M6 shutdown barrier")
    live.free()

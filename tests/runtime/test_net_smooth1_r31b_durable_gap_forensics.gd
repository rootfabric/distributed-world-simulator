extends SceneTree

# R3.1b P0: per-domain timing must retain EXACT durable bytes/hash,
# including actual USER1 active-seam snapshots and detached worker disk.
# The implementation is diagnostic only; no gameplay COW is claimed.
const SeamService = preload("res://scripts/runtime/networked_gameplay/user1/user1_product_seam_gameplay_service.gd")
const Adapter = preload("res://scripts/runtime/networked_gameplay/m6/m6_dedicated_gameplay_authority_adapter.gd")
const Outbox = preload("res://scripts/runtime/networked_gameplay/m6/m6_durable_replay_outbox.gd")
const Writer = preload("res://scripts/persistence/async_checkpoint_writer.gd")
const Repository = preload("res://scripts/persistence/authoritative_recovery_repository.gd")
const Checkpoint = preload("res://scripts/persistence/authoritative_checkpoint.gd")
const Runtime = preload("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	OS.set_environment("DWS_NET_R3C4_R31B_DURABLE_ATTRIBUTION", "")
	_test_real_seam_profile_parity()
	_test_server_gates()
	for failure in failures:
		push_error("R31B_FAIL:" + failure)
	print("NET_SMOOTH_R31B_DURABLE_GAP_FORENSICS %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _port() -> int:
	var peer := PacketPeerUDP.new()
	if peer.bind(0, "127.0.0.1") != OK:
		return 0
	var port := peer.get_local_port()
	peer.close()
	return port

func _path(label: String) -> String:
	return ProjectSettings.globalize_path(
		"res://artifacts/net-smooth1/r31b-%s-%d" % [label, Time.get_ticks_usec()])

func _test_real_seam_profile_parity() -> void:
	var service = SeamService.new()
	var configured: Dictionary = service.setup(
		"authority/network/r31b", 1, 0, {
			"profile": "MULTIPLAYER_CORE",
			"topology_adapter": "ENET",
			"region_id": "region/m3/single-server",
			"playable_sandbox": true,
			"fixed_tick_authority": true,
		}
	)
	check(bool(configured.get("success", false)), "USER1 product service configured")
	if not bool(configured.get("success", false)):
		return
	var joined: Dictionary = service.join(
		"seam-player", "transport-session/r31b/a",
		"operation/r31b/join/a")
	check(bool(joined.get("success", false)), "real seam player joined")
	if not bool(joined.get("success", false)):
		service.shutdown()
		return
	var default_fallback: Dictionary = service.export_durable_state()
	var profiled_fallback: Dictionary = service.export_durable_state_r31b_profiled()
	check(default_fallback == Dictionary(profiled_fallback.get("value", {})),
		"seam-unbound fallback exact checksum parity")
	check(float(profiled_fallback.get("stages", {}).get("fallback_ms", -1)) >= 0.0,
		"unbound fallback timing valid")
	var bound: Dictionary = service.call("_ensure_seam_binding", "seam-player")
	check(bool(bound.get("success", false)), "real active seam binding established")
	if not bool(bound.get("success", false)):
		service.shutdown()
		return
	# Join records joined_tick=1 in the ownership registry while a fresh unit
	# service still stands at _tick=0; advance the fixed tick so the durable
	# export validation (PLAYER_OWNERSHIP_TICK_AHEAD_OF_SERVER) sees a
	# consistent authority tick, exactly as a real server frame would.
	var ticked: Dictionary = service.advance_fixed_server_tick(1)
	check(bool(ticked.get("success", false)), "fixed server tick advanced after join")
	if not bool(ticked.get("success", false)):
		service.shutdown()
		return
	var original: Dictionary = service.export_durable_state()
	var profiled: Dictionary = service.export_durable_state_r31b_profiled()
	var actual: Dictionary = Dictionary(profiled.get("value", {}))
	check(not original.is_empty(), "original seam durable state exists")
	check(original == actual, "active seam durable DTO byte-equivalent")
	check(String(original.get("checksum", "")) == String(actual.get("checksum", "")),
		"active seam checksum parity")
	var stages: Dictionary = Dictionary(profiled.get("stages", {}))
	for name in [
		"snapshot_ms", "players_ms", "ownership_ms", "shared_item_ms",
		"item_graph_ms", "resource_ms", "final_checksum_ms",
		"validation_ms", "total_ms",
	]:
		check(float(stages.get(name, -1)) >= 0.0, "timing nonnegative %s" % name)
	check(bool(stages.get("valid", false)), "active seam validated")
	check(int(stages.get("seam_coordinator_count", 0)) == 1,
		"bound product seam counted exactly once")
	check(int(stages.get("player_count", -1)) == 1,
		"one real player in measured durable source")

	var adapter = Adapter.new()
	check(bool(adapter.setup(service).get("success", false)), "M6 adapter configured")
	var profiled_source: Dictionary = adapter.capture_frozen_gameplay_source_r31b_profiled()
	var frozen: Dictionary = Dictionary(profiled_source.get("frozen_gameplay", {}))
	check(Dictionary(frozen.get("durable_state", {})) == actual,
		"M6 adapter does not change profiled durable state")
	check(not Dictionary(profiled_source.get("stages", {})).is_empty(),
		"M6 adapter exposes source stage durations")
	var wrapped: Dictionary = Adapter.wrap_frozen_gameplay_source(frozen)
	var canonical: Dictionary = adapter.export_recovery_state()
	check(wrapped == canonical, "exact M6 envelope equality")
	var replay_outbox = Outbox.new()
	check(bool(replay_outbox.setup(service).get("success", false)), "outbox configured")
	var replay: Dictionary = replay_outbox.to_dict()
	var expected: Dictionary = Checkpoint.create(
		"checkpoint/r31b/test/1", 1, 0, canonical, replay, "",
		int(canonical.get("server_tick", -1)))
	check(bool(Checkpoint.validate(expected).get("success", false)),
		"unmodified checkpoint validates")
	var disk_root: String = _path("disk")
	var writer = Writer.new()
	var ready: Dictionary = writer.setup(disk_root)
	check(bool(ready.get("success", false)), "single writer configured")
	if bool(ready.get("success", false)):
		var submit: Dictionary = writer.submit_frozen_gameplay_source(
			frozen, replay, "checkpoint/r31b/test/1", 1, 0)
		check(bool(submit.get("success", false)), "single writer source accepted")
		check(writer.is_busy(), "no pre-ACK completion")
		var caller_durable: Dictionary = Dictionary(frozen.get("durable_state", {}))
		caller_durable["checksum"] = "caller-poison"
		replay.clear()
		var complete: Dictionary = writer.wait_completed()
		check(bool(complete.get("success", false)), "writer durable commit")
		var repository = Repository.new()
		check(bool(repository.configure(disk_root).get("success", false)),
			"recovery repository opened")
		var loaded: Dictionary = repository.load_committed()
		check(bool(loaded.get("success", false)), "disk state recovered")
		if bool(loaded.get("success", false)):
			check(Dictionary(loaded.get("details", {}).get("checkpoint", {})) == expected,
				"checkpoint content/hash unaffected by instrumentation/alias")
		writer.stop()
	service.shutdown()

func _test_server_gates() -> void:
	var denied = Runtime.new()
	var invalid: Dictionary = denied.setup({
		"host": "127.0.0.1", "port": _port(),
		"playable_sandbox": true, "persistence_root": _path("denied"),
		"r3c4r31b_durable_attribution_canary": true,
	})
	check(not bool(invalid.get("success", false)) and
		String(invalid.get("error_code", "")) ==
			"R3C4_R31B_REQUIRES_R31_REPLAY_PROJECTION",
		"R31b refuses attribution without R31")
	denied.free()
	var wrong_service = Runtime.new()
	var wrong: Dictionary = wrong_service.setup({
		"host": "127.0.0.1", "port": _port(),
		"playable_sandbox": true, "persistence_root": _path("wrong-service"),
		"r3c4_periodic_frame_pacing_canary": true,
		"r3c4r2_worker_envelope_canary": true,
		"r3c4r31_replay_projection_canary": true,
		"r3c4r31b_durable_attribution_canary": true,
	})
	check(not bool(wrong.get("success", false)) and
		String(wrong.get("error_code", "")) == "R3C4_R31B_REQUIRES_PRODUCT_SEAM",
		"R31b refuses non-USER1 owner before any worker starts")
	wrong_service.free()
	var live = Runtime.new()
	var result: Dictionary = live.setup({
		"host": "127.0.0.1", "port": _port(),
		"playable_sandbox": true, "product_seam_enabled": true,
		"persistence_root": _path("runtime"),
		"r3c4_periodic_frame_pacing_canary": true,
		"r3c4r2_worker_envelope_canary": true,
		"r3c4r31_replay_projection_canary": true,
		"r3c4r31b_durable_attribution_canary": true,
	})
	check(bool(result.get("success", false)), "R31b real server configured")
	if not bool(result.get("success", false)):
		live.free()
		return
	live.set_process(false)
	check(bool(live.get("_r3c4r31b_durable_attribution_enabled")),
		"R31b attribution explicitly enabled")
	var before: int = int(live.get("_checkpoint_generation"))
	live.set("_last_movement_snapshot_tick", -1)
	live.set("_movement_checkpoint_dirty", true)
	live.set("_movement_commands_since_checkpoint", 3)
	live.set("_last_movement_checkpoint_ms", -10000)
	live.call("_maybe_persist_movement_checkpoint")
	check(live.get("_movement_checkpoint_writer").is_busy(),
		"real R31b periodic generation submitted")
	check(int(live.get("_checkpoint_generation")) == before,
		"no early durable generation advance")
	live.call("_complete_async_movement_checkpoint", true)
	check(not bool(live.get("_fatal_persistence_failure")),
		"no new persistence failure")
	check(int(live.get("_checkpoint_generation")) == before+1,
		"generation advances after exact disk commit")
	check(bool(live.stop().get("success", false)),
		"shutdown durable barrier unchanged")
	live.free()

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures.append(label)

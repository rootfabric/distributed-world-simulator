extends SceneTree

# R3.1a: Exact replay parity, immutable cache isolation, source mutation fence,
# outbox admission/delivery generation, M6 disk, R2 gate. No perf claim here.
const Service = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
const Adapter = preload("res://scripts/runtime/networked_gameplay/m6/m6_dedicated_gameplay_authority_adapter.gd")
const Outbox = preload("res://scripts/runtime/networked_gameplay/m6/m6_durable_replay_outbox.gd")
const Writer = preload("res://scripts/persistence/async_checkpoint_writer.gd")
const Checkpoint = preload("res://scripts/persistence/authoritative_checkpoint.gd")
const Repository = preload("res://scripts/persistence/authoritative_recovery_repository.gd")
const Runtime = preload("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd")
var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	OS.set_environment("DWS_NET_R3C4_R31_REPLAY_PROJECTION", "")
	OS.set_environment("DWS_NET_R3C4_R30_STAGE_ATTRIBUTION", "")
	_test_replay_projection_parity()
	_test_runtime_canary()
	for failure in failures:
		push_error("R3C4_R31_FAIL:" + failure)
	print("NET_SMOOTH_R3C4_R31 %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _path(label: String) -> String:
	return ProjectSettings.globalize_path(
		"res://artifacts/net-smooth1/r3c4-r31-%s-%d" % [label, Time.get_ticks_usec()])

func _port() -> int:
	var sock := PacketPeerUDP.new()
	if sock.bind(0, "127.0.0.1") != OK:
		return 0
	var port := sock.get_local_port()
	sock.close()
	return port

func _test_replay_projection_parity() -> void:
	var service = Service.new()
	var configured: Dictionary = service.setup("simulation/r3c4/r31", 1, 0, {
		"profile": Service.PROFILE_MULTIPLAYER_CORE,
		"topology_adapter": "ENET",
		"region_id": "region/r3c4/r31",
		"fixed_tick_authority": true,
	})
	check(bool(configured.get("success", false)), "service ready")
	if not bool(configured.get("success", false)):
		return
	check(bool(service.join("a", "transport-session/r31/a/1",
		"operation/r31/join/a").get("success", false)), "join durable source")
	var outbox = Outbox.new()
	check(bool(outbox.setup(service).get("success", false)), "outbox ready")
	var legacy: Dictionary = outbox.to_dict()
	var rebuilt: Dictionary = outbox.to_dict_r31_versioned()
	check(Dictionary(rebuilt.get("value", {})) == legacy, "cold miss byte-for-byte")
	check(not bool(rebuilt.get("cache_hit", true)), "first capture cache miss")
	check(String(rebuilt.get("bypassed", "")).is_empty(), "source fence available")
	var stable_fence: Dictionary = service.get_r31_replay_source_fence()
	check(not stable_fence.is_empty(), "monotone replay source fence exposed")
	var reused: Dictionary = outbox.to_dict_r31_versioned()
	check(bool(reused.get("cache_hit", false)), "identical source cache hit")
	check(Dictionary(reused.get("value", {})) == legacy, "cached replay exact")
	var caller_replay: Dictionary = Dictionary(reused.get("value", {}))
	caller_replay["checksum"] = "tampered"
	var caller_gameplay: Dictionary = Dictionary(caller_replay.get("gameplay_replay", {}))
	caller_gameplay["checksum"] = "poison"
	check(Dictionary(outbox.to_dict_r31_versioned().get("value", {})) == legacy,
		"caller mutable alias cannot poison cache")
	var advanced: Dictionary = service.advance_fixed_server_tick(1)
	check(bool(advanced.get("success", false)), "fixed tick advanced")
	check(service.get_r31_replay_source_fence() == stable_fence,
		"movement clock never invalidates replay cache")
	check(bool(outbox.to_dict_r31_versioned().get("cache_hit", false)),
		"cache reuse across movement ticks")
	var item_before: Dictionary = service.get_r31_replay_source_fence()
	var item_action: Dictionary = service.handle_canonical_item_command(
		"a", "transport-session/r31/a/1", 1,
		"operation/r31/item/hotbar/a", "inventory.select_hotbar",
		{"selected_hotbar_index": 1})
	check(bool(item_action.get("success", false)), "canonical ITEM changes real ledger")
	check(service.get_r31_replay_source_fence() != item_before,
		"item graph replay generation invalidates projection")
	var after_item: Dictionary = outbox.to_dict_r31_versioned()
	check(not bool(after_item.get("cache_hit", true)),
		"item mutation forces replay rebuild")
	check(Dictionary(after_item.get("value", {})) == outbox.to_dict(),
		"item mutation replay byte parity")
	check(bool(service.join("b", "transport-session/r31/b/1",
		"operation/r31/join/b").get("success", false)), "second command replay mutation")
	check(service.get_r31_replay_source_fence() != stable_fence,
		"ledger mutation invalidates source fence")
	var after_join: Dictionary = outbox.to_dict()
	var rebuilt2: Dictionary = outbox.to_dict_r31_versioned()
	check(not bool(rebuilt2.get("cache_hit", true)), "service mutation cache miss")
	check(Dictionary(rebuilt2.get("value", {})) == after_join,
		"mutated replay recomputed canonically")
	var stage: Dictionary = outbox.stage_committed(
		"operation/r31/join/a", "JOIN", {"success": true})
	check(bool(stage.get("success", false)), "committed outbox stage")
	var staged: Dictionary = outbox.to_dict_r31_versioned()
	check(not bool(staged.get("cache_hit", true)), "outbox append invalidates")
	check(Dictionary(staged.get("value", {})) == outbox.to_dict(),
		"outbox staged payload parity")
	var attempt: Dictionary = outbox.mark_delivery_attempt(1)
	check(bool(attempt.get("success", false)), "delivery attempt recorded")
	check(not bool(outbox.to_dict_r31_versioned().get("cache_hit", true)),
		"delivery attempt invalidates")
	var delivered: Dictionary = outbox.mark_delivered(1)
	check(bool(delivered.get("success", false)), "delivery recorded")
	check(not bool(outbox.to_dict_r31_versioned().get("cache_hit", true)),
		"delivery status invalidates")
	var replay_final: Dictionary = outbox.to_dict()
	check(bool(outbox.load_dict(replay_final).get("success", false)), "restore replay state")
	check(not bool(outbox.to_dict_r31_versioned().get("cache_hit", true)),
		"restore invalidates cached revision")
	check(Dictionary(outbox.to_dict_r31_versioned().get("value", {})) == outbox.to_dict(),
		"postrestore replay cache exact")
	var adapter = Adapter.new()
	check(bool(adapter.setup(service).get("success", false)), "M6 adapter ready")
	var frozen: Dictionary = adapter.capture_frozen_gameplay_source_for_worker()
	var auth: Dictionary = Adapter.wrap_frozen_gameplay_source(frozen)
	var replay_disk: Dictionary = Dictionary(outbox.to_dict_r31_versioned().get("value", {}))
	var expected: Dictionary = Checkpoint.create(
		"checkpoint/r3c4/r31/1", 1, 0, auth, replay_disk, "",
		int(auth.get("server_tick", -1)))
	check(bool(Checkpoint.validate(expected).get("success", false)), "checkpoint canonical")
	var disk_root: String = _path("disk")
	var writer = Writer.new()
	check(bool(writer.setup(disk_root).get("success", false)), "single writer setup")
	var submit: Dictionary = writer.submit_frozen_gameplay_source(
		frozen, replay_disk, "checkpoint/r3c4/r31/1", 1, 0)
	check(bool(submit.get("success", false)), "single M6 generation queued")
	check(writer.is_busy(), "no early disk completion before ACK")
	replay_disk.clear()
	var completed: Dictionary = writer.wait_completed()
	check(bool(completed.get("success", false)), "writer persisted cached replay")
	var repository = Repository.new()
	check(bool(repository.configure(disk_root).get("success", false)), "recovery repo")
	var loaded: Dictionary = repository.load_committed()
	check(bool(loaded.get("success", false)), "disk commit recovered")
	if bool(loaded.get("success", false)):
		check(Dictionary(loaded.get("details", {}).get("checkpoint", {})) == expected,
			"disk checkpoint bytes/hash identical despite mutated caller")
	writer.stop()
	service.shutdown()

func _test_runtime_canary() -> void:
	var denied = Runtime.new()
	var result: Dictionary = denied.setup({
		"host": "127.0.0.1", "port": _port(),
		"playable_sandbox": true, "persistence_root": _path("denied"),
		"r3c4r31_replay_projection_canary": true})
	check(not bool(result.get("success", false)) and
		String(result.get("error_code", "")) ==
		"R3C4_R31_REQUIRES_R2_WORKER_ENVELOPE",
		"R31 requires frozen R2 writer")
	denied.free()
	var conflict = Runtime.new()
	var declined: Dictionary = conflict.setup({
		"host": "127.0.0.1", "port": _port(),
		"playable_sandbox": true, "persistence_root": _path("conflict"),
		"r3c4_periodic_frame_pacing_canary": true,
		"r3c4r2_worker_envelope_canary": true,
		"r3c4r30_stage_attribution_canary": true,
		"r3c4r31_replay_projection_canary": true})
	check(not bool(declined.get("success", false)) and
		String(declined.get("error_code", "")) ==
		"R3C4_R31_R30_ATTRIBUTION_MODE_CONFLICT",
		"cannot relabel R30 uncached attribution as R31")
	conflict.free()
	var live = Runtime.new()
	var ready: Dictionary = live.setup({
		"host": "127.0.0.1", "port": _port(),
		"playable_sandbox": true, "persistence_root": _path("runtime"),
		"r3c4_periodic_frame_pacing_canary": true,
		"r3c4r2_worker_envelope_canary": true,
		"r3c4r31_replay_projection_canary": true})
	check(bool(ready.get("success", false)), "real M3 R31 runtime configured")
	if not bool(ready.get("success", false)):
		live.free()
		return
	live.set_process(false)
	check(bool(live.get("_r3c4r31_replay_projection_enabled")), "R31 opt-in true")
	var generation: int = int(live.get("_checkpoint_generation"))
	live.set("_last_movement_snapshot_tick", -1)
	live.set("_movement_checkpoint_dirty", true)
	live.set("_movement_commands_since_checkpoint", 3)
	live.set("_last_movement_checkpoint_ms", -10000)
	live.call("_maybe_persist_movement_checkpoint")
	check(live.get("_movement_checkpoint_writer").is_busy(), "R31 periodic enqueued")
	check(int(live.get("_checkpoint_generation")) == generation,
		"ACK fence unchanged before durable commit")
	live.call("_complete_async_movement_checkpoint", true)
	check(not bool(live.get("_fatal_persistence_failure")), "R31 no fatal persistence")
	check(int(live.get("_checkpoint_generation")) == generation + 1,
		"R31 generation advances after disk commit")
	check(bool(live.stop().get("success", false)), "R31 shutdown barrier")
	live.free()

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures.append(label)

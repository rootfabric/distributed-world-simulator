extends SceneTree

# R31b P1 real USER1 product owner: exact baseline parity, immutable chunk
# alias poison, M4/replay/Resource restore invalidation, on-disk M6 and
# durable-before-ACK. No GUI performance inferred from this headless suite.
const Service = preload(
	"res://scripts/runtime/networked_gameplay/user1/user1_product_seam_gameplay_service.gd")
const Graph = preload(
	"res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd")
const Adapter = preload(
	"res://scripts/runtime/networked_gameplay/m6/m6_dedicated_gameplay_authority_adapter.gd")
const Outbox = preload(
	"res://scripts/runtime/networked_gameplay/m6/m6_durable_replay_outbox.gd")
const Writer = preload("res://scripts/persistence/async_checkpoint_writer.gd")
const Repository = preload(
	"res://scripts/persistence/authoritative_recovery_repository.gd")
const Checkpoint = preload("res://scripts/persistence/authoritative_checkpoint.gd")
const Runtime = preload(
	"res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd")

# Synthetic detached port targets the cache boundary only; production cache
# still uses real M4/ResourceMining owners in the integration test below.
class FakeDurablePort extends RefCounted:
	var generation := 1
	var payload_bytes := 32
	var mutate_during_export := false
	func get_r31bp1_durable_source_fence() -> Dictionary:
		return {"schema": "test-only", "generation": generation}
	func export_durable_state() -> Dictionary:
		var value: Dictionary = {"schema": "test-only", "payload": "x".repeat(payload_bytes)}
		if mutate_during_export:
			generation += 1
		return value

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	OS.set_environment("DWS_NET_R31BP1_DURABLE_CHUNKS", "")
	_test_reject_changed_fence_and_memory_budget()
	_test_owner_native_m4_fence()
	_test_cached_immutable_real_seam()
	_test_real_server_config()
	for reason in failures:
		push_error("R31BP1_FAIL:" + reason)
	print("NET_SMOOTH_R31BP1 %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, label: String) -> void:
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
		"res://artifacts/net-smooth1/r31bp1-%s-%d" % [label, Time.get_ticks_usec()])


func _test_reject_changed_fence_and_memory_budget() -> void:
	var service = Service.new()
	var fake = FakeDurablePort.new()
	fake.mutate_during_export = true
	var rejected: Dictionary = service.call("_r31bp1_export_chunk", fake, "item_graph")
	_check(String(rejected.get("bypass", "")) == "FENCE_CHANGED",
		"source version changed during export is explicitly rejected")
	_check(Dictionary(rejected.get("value", {})).is_empty(),
		"changed source fence cannot produce a disk-bound DTO")
	fake.mutate_during_export = false
	var first: Dictionary = service.call("_r31bp1_export_chunk", fake, "item_graph")
	_check(not bool(first.get("cache_hit", true)), "new exact fake version miss")
	var second: Dictionary = service.call("_r31bp1_export_chunk", fake, "item_graph")
	_check(bool(second.get("cache_hit", false)), "identical frozen fake cache hit")
	fake.generation += 1
	fake.payload_bytes = 4 * 1024 * 1024
	var oversize: Dictionary = service.call("_r31bp1_export_chunk", fake, "item_graph")
	_check(String(oversize.get("bypass", "")) == "CHUNK_MEMORY_BUDGET",
		"over 4MiB source bypasses private cache")
	_check(not Dictionary(oversize.get("value", {})).is_empty(),
		"over-budget case retains canonical legacy source")
	var repeated: Dictionary = service.call("_r31bp1_export_chunk", fake, "item_graph")
	_check(not bool(repeated.get("cache_hit", true)),
		"over-budget values never become cached authority")


func _test_owner_native_m4_fence() -> void:
	var graph = Graph.new()
	var boot: Dictionary = graph.setup("authority/r31bp1/m4", 1, {
		"playable_sandbox": true})
	_check(bool(boot.get("success", false)), "M4 source graph setup")
	if not bool(boot.get("success", false)):
		return
	var before: Dictionary = graph.get_r31bp1_durable_source_fence()
	graph.ensure_player("new-actor")
	var after: Dictionary = graph.get_r31bp1_durable_source_fence()
	_check(after != before, "new player and P5 tool invalidate M4 durable source")
	_check(int(before.get("revision", -1)) == int(after.get("revision", -2)),
		"inventory seeding changes durable rows WITHOUT global item revision")
	var stable: Dictionary = graph.export_durable_state()
	_check(not stable.is_empty(), "M4 durable state exists")
	var restored: Dictionary = graph.restore_durable_state(stable)
	_check(bool(restored.get("success", false)), "M4 restore exact")
	_check(graph.get_r31bp1_durable_source_fence() != after,
		"restore cannot resurrect stale source fence via revision ABA")
	var live_graph = Graph.new()
	var live_boot: Dictionary = live_graph.setup("authority/r31bp1/live-m4", 1, {
		"playable_sandbox": false})
	_check(bool(live_boot.get("success", false)), "native M4 bootstrap")
	if bool(live_boot.get("success", false)):
		var previous: Dictionary = live_graph.get_r31bp1_durable_source_fence()
		var configured: Dictionary = live_graph.configure_live_items(true, true)
		_check(bool(configured.get("success", false)), "live item fixture opt-in")
		_check(live_graph.get_r31bp1_durable_source_fence() != previous,
			"live policy and transform boot invalidates source stamp")


func _test_cached_immutable_real_seam() -> void:
	var service = Service.new()
	var setup: Dictionary = service.setup(
		"authority/network/r31bp1", 1, 0, {
			"profile": "MULTIPLAYER_CORE",
			"topology_adapter": "ENET",
			"region_id": "region/m3/single-server",
			"playable_sandbox": true,
			"fixed_tick_authority": true,
		})
	_check(bool(setup.get("success", false)), "USER1 owner ready")
	if not bool(setup.get("success", false)):
		return
	_check(bool(service.join("a", "transport-session/r31bp1/a",
		"operation/r31bp1/join/a").get("success", false)),
		"real joined player")
	var fallback: Dictionary = service.export_durable_state_r31bp1_chunks()
	_check(
		Dictionary(fallback.get("value", {})) == service.export_durable_state(),
		"no-seam canonical fallback exact")
	var bound: Dictionary = service.call("_ensure_seam_binding", "a")
	_check(bool(bound.get("success", false)), "active seam binding")
	if not bool(bound.get("success", false)):
		service.shutdown()
		return
	# Actual joined_tick is 1; do not test ProductSeam durable state at
	# synthetic server tick 0 (PLAYER_OWNERSHIP_TICK_AHEAD_OF_SERVER).
	var ticked: Dictionary = service.advance_fixed_server_tick(1)
	_check(bool(ticked.get("success", false)), "owner tick >= joined_tick")
	if not bool(ticked.get("success", false)):
		service.shutdown()
		return
	var baseline: Dictionary = service.export_durable_state()
	_check(not baseline.is_empty(), "accepted baseline durable DTO")
	var first: Dictionary = service.export_durable_state_r31bp1_chunks()
	var first_stages: Dictionary = Dictionary(first.get("stages", {}))
	_check(Dictionary(first.get("value", {})) == baseline, "first export byte parity")
	_check(not bool(first_stages.get("item_graph_cache_hit", true)),
		"M4 first export cache miss")
	_check(not bool(first_stages.get("resource_cache_hit", true)),
		"resource first export cache miss")
	_check(bool(first_stages.get("valid", false)), "full legacy validation performed")
	_check(int(first_stages.get("item_graph_cache_bytes", -1)) > 0,
		"M4 chunk has bounded bytes")
	_check(int(first_stages.get("resource_cache_bytes", -1)) > 0,
		"resource chunk has bounded bytes")
	var second: Dictionary = service.export_durable_state_r31bp1_chunks()
	var second_stages: Dictionary = Dictionary(second.get("stages", {}))
	_check(bool(second_stages.get("item_graph_cache_hit", false)),
		"same M4 version cache hit")
	_check(bool(second_stages.get("resource_cache_hit", false)),
		"same resource generation cache hit")
	_check(Dictionary(second.get("value", {})) == baseline,
		"warm cached durable DTO exactly equal")
	var caller: Dictionary = Dictionary(second.get("value", {}))
	caller["checksum"] = "caller-tamper"
	var item_caller: Dictionary = Dictionary(caller.get("canonical_item_graph", {}))
	item_caller["checksum"] = "caller-nested-poison"
	var resource_caller: Dictionary = Dictionary(caller.get("resource_mining", {}))
	resource_caller["checksum"] = "caller-resource-poison"
	var untampered: Dictionary = service.export_durable_state_r31bp1_chunks()
	_check(Dictionary(untampered.get("value", {})) == baseline,
		"private M4/resource chunks immune to mutable caller aliases")
	_check(bool(untampered.get("stages", {}).get("item_graph_cache_hit", false)),
		"caller poison did not invalidate or corrupt private M4")

	# Real ItemGraph command changes revision even if the mining domain did not.
	var m4: Dictionary = service.handle_canonical_item_command(
		"a", "transport-session/r31bp1/a", 1,
		"operation/r31bp1/item/hotbar",
		"inventory.select_hotbar", {"selected_hotbar_index": 1})
	_check(bool(m4.get("success", false)), "real M4 ITEM mutation")
	if bool(m4.get("success", false)):
		var after_item: Dictionary = service.export_durable_state_r31bp1_chunks()
		_check(not bool(after_item.get("stages", {}).get(
			"item_graph_cache_hit", true)), "canonical ITEM forces M4 rebuild")
		_check(bool(after_item.get("stages", {}).get(
			"resource_cache_hit", false)), "unchanged resource still reused")
		_check(Dictionary(after_item.get("value", {})) ==
			service.export_durable_state(), "M4 mutation exact parity")

	# Resource restore may reload different rows with the SAME generation,
	# so the independent source_serial must invalidate (ABA falsifier).
	var mining = service.get_resource_mining_port()
	_check(mining != null, "canonical ResourceMining port ready")
	if mining != null:
		var before_resource: Dictionary = mining.get_r31bp1_durable_source_fence()
		var frozen_resource: Dictionary = mining.export_durable_state()
		var restored: Dictionary = mining.restore_durable_state(frozen_resource)
		_check(bool(restored.get("success", false)), "resource reset/restore valid")
		_check(mining.get_r31bp1_durable_source_fence() != before_resource,
			"same generation replay/restore changes resource reset serial")
		var after_restore: Dictionary = service.export_durable_state_r31bp1_chunks()
		_check(not bool(after_restore.get("stages", {}).get(
			"resource_cache_hit", true)), "resource ABA forces miss")
		_check(bool(after_restore.get("stages", {}).get(
			"item_graph_cache_hit", false)), "unmodified M4 still cache hit")
		_check(Dictionary(after_restore.get("value", {})) ==
			service.export_durable_state(), "resource restored durable parity")

	var adapter = Adapter.new()
	_check(bool(adapter.setup(service).get("success", false)), "M6 adapter ready")
	var outbox = Outbox.new()
	_check(bool(outbox.setup(service).get("success", false)), "M6 replay outbox ready")
	var source: Dictionary = adapter.capture_frozen_gameplay_source_r31bp1_chunks()
	var frozen: Dictionary = Dictionary(source.get("frozen_gameplay", {}))
	var wrapped: Dictionary = Adapter.wrap_frozen_gameplay_source(frozen)
	_check(wrapped == adapter.export_recovery_state(), "R2 worker envelope parity")
	var replay: Dictionary = outbox.to_dict()
	var expected: Dictionary = Checkpoint.create(
		"checkpoint/r31bp1/test/1", 1, 0, wrapped, replay, "",
		int(wrapped.get("server_tick", -1)))
	_check(bool(Checkpoint.validate(expected).get("success", false)),
		"exact M6 checkpoint valid")
	var root_path: String = _path("disk")
	var writer = Writer.new()
	var started: Dictionary = writer.setup(root_path)
	_check(bool(started.get("success", false)), "one real async writer")
	if bool(started.get("success", false)):
		var submitted: Dictionary = writer.submit_frozen_gameplay_source(
			frozen, replay, "checkpoint/r31bp1/test/1", 1, 0)
		_check(bool(submitted.get("success", false)), "M6 generation accepted")
		_check(writer.is_busy(), "no early ACK or durability")
		var inner: Dictionary = Dictionary(frozen.get("durable_state", {}))
		inner["checksum"] = "after-submit-mutation"
		replay.clear()
		var done: Dictionary = writer.wait_completed()
		_check(bool(done.get("success", false)), "disk fsync completed")
		var repository = Repository.new()
		_check(bool(repository.configure(root_path).get("success", false)),
			"recovery repository configured")
		var loaded: Dictionary = repository.load_committed()
		_check(bool(loaded.get("success", false)), "disk restart recovery succeeded")
		if bool(loaded.get("success", false)):
			_check(Dictionary(loaded.get("details", {}).get("checkpoint", {})) ==
				expected, "disk checkpoint bytes / SHA parity after alias mutation")
		writer.stop()
	service.shutdown()

func _test_real_server_config() -> void:
	var denied = Runtime.new()
	var invalid: Dictionary = denied.setup({
		"host": "127.0.0.1", "port": _port(),
		"playable_sandbox": true, "persistence_root": _path("denied"),
		"r31bp1_durable_chunks_canary": true,
	})
	_check(not bool(invalid.get("success", false)) and
		String(invalid.get("error_code", "")) ==
			"R31BP1_REQUIRES_R31B_DURABLE_ATTRIBUTION",
		"P1 cannot run without R31b P0")
	denied.free()
	var active = Runtime.new()
	var configured: Dictionary = active.setup({
		"host": "127.0.0.1", "port": _port(),
		"playable_sandbox": true,
		"product_seam_enabled": true,
		"persistence_root": _path("runtime"),
		"r3c4_periodic_frame_pacing_canary": true,
		"r3c4r2_worker_envelope_canary": true,
		"r3c4r31_replay_projection_canary": true,
		"r3c4r31b_durable_attribution_canary": true,
		"r31bp1_durable_chunks_canary": true,
	})
	_check(bool(configured.get("success", false)), "P1 real server boot")
	if not bool(configured.get("success", false)):
		active.free()
		return
	active.set_process(false)
	_check(bool(active.get("_r3c4r31bp1_durable_chunks_enabled")),
		"P1 explicit opt-in active")
	var initial: int = int(active.get("_checkpoint_generation"))
	active.set("_last_movement_snapshot_tick", -1)
	active.set("_movement_checkpoint_dirty", true)
	active.set("_movement_commands_since_checkpoint", 3)
	active.set("_last_movement_checkpoint_ms", -10000)
	active.call("_maybe_persist_movement_checkpoint")
	_check(active.get("_movement_checkpoint_writer").is_busy(),
		"periodic generation enqueued on unchanged M6 writer")
	_check(int(active.get("_checkpoint_generation")) == initial,
		"no durability generation / ACK before disk completion")
	active.call("_complete_async_movement_checkpoint", true)
	_check(not bool(active.get("_fatal_persistence_failure")), "no M6 persistence fatal")
	_check(int(active.get("_checkpoint_generation")) == initial + 1,
		"generation advances exactly once after durable write")
	_check(bool(active.stop().get("success", false)),
		"shutdown barrier unchanged")
	active.free()

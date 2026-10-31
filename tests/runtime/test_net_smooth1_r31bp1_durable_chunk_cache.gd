extends SceneTree

# R31b P1 — source-fenced immutable durable chunk cache falsifiers.
#
# Covers: first miss then warm hit for BOTH chunks with exact durable
# JSON/checksum parity; caller nested poison isolation; zero-revision player
# inventory/P5 tool seeding invalidation; ITEM command invalidates only M4;
# same-generation resource restore invalidates only resource (ABA); oversize
# bypass measured; fail-closed mode gates; default OFF; no early ACK change.

const SeamService = preload("res://scripts/runtime/networked_gameplay/user1/user1_product_seam_gameplay_service.gd")
const ChunkCache = preload("res://scripts/runtime/networked_gameplay/m6/r31bp1_durable_chunk_cache.gd")
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
	OS.set_environment("DWS_NET_R31BP1_DURABLE_CHUNKS", "")
	_test_cache_disabled_fails_closed()
	_test_miss_then_hit_and_exact_parity()
	_test_nested_poison_isolation()
	_test_invalidation_fences()
	_test_oversize_bypass()
	_test_changed_source_fence()
	_test_exact_m6_disk_periodic_vs_direct_export()
	_test_runtime_gates()
	for failure in failures:
		push_error("R31BP1_FAIL:" + failure)
	print("NET_SMOOTH_R31BP1_DURABLE_CHUNK_CACHE %s assertions=%d failures=%d" % [
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
		"res://artifacts/net-smooth1/r31bp1-%s-%d" % [label, Time.get_ticks_usec()])


# Builds a real USER1 service with one joined player on an active seam and a
# warm tick, exactly like the normative P0 parity test.
func _make_bound_service(label: String):
	var service = SeamService.new()
	var configured: Dictionary = service.setup(
		"authority/network/r31bp1-%s" % label, 1, 0, {
			"profile": "MULTIPLAYER_CORE",
			"topology_adapter": "ENET",
			"region_id": "region/m3/single-server",
			"playable_sandbox": true,
			"fixed_tick_authority": true,
		}
	)
	check(bool(configured.get("success", false)), label + ": service configured")
	if not bool(configured.get("success", false)):
		return null
	var joined: Dictionary = service.join(
		"seam-player", "transport-session/r31bp1/a", "operation/r31bp1/join/%s" % label)
	check(bool(joined.get("success", false)), label + ": real seam player joined")
	var bound: Dictionary = service.call("_ensure_seam_binding", "seam-player")
	check(bool(bound.get("success", false)), label + ": seam binding established")
	var ticked: Dictionary = service.advance_fixed_server_tick(1)
	check(bool(ticked.get("success", false)), label + ": tick advanced")
	return service


func _periodic_durable(service) -> Dictionary:
	# Only this R31b P0 profiler call is allowed to use P1 chunks.
	# The direct export_durable_state() is reserved for legacy command M6.
	return Dictionary(service.export_durable_state_r31b_profiled().get("value", {}))


func _test_cache_disabled_fails_closed() -> void:
	var cache = ChunkCache.new()
	var rejected: Dictionary = cache.export_component(ChunkCache.new(), "item_graph")
	check(not bool(rejected.get("success", false))
		and String(rejected.get("error_code", "")) == "R31BP1_CHUNK_CACHE_DISABLED",
		"unconfigured cache refuses exports (fail closed)")
	var bad_kind: Dictionary = cache.configure(true)
	check(bool(bad_kind.get("success", false)), "cache configures when enabled")
	if bool(bad_kind.get("success", false)):
		var invalid: Dictionary = cache.export_component(ChunkCache.new(), "shared_item")
		check(not bool(invalid.get("success", false))
			and String(invalid.get("error_code", "")) == "R31BP1_CHUNK_CACHE_COMPONENT_INVALID",
			"unknown component kind refused")
	# A service without the cache attached uses the legacy export unchanged.
	var service = _make_bound_service("disabled")
	if service != null:
		check(not service.is_r31bp1_durable_chunks_enabled(),
			"default OFF: no cache attached")
		var legacy: Dictionary = service.export_durable_state()
		check(not legacy.is_empty(), "default OFF legacy export valid")
		service.shutdown()


func _test_miss_then_hit_and_exact_parity() -> void:
	var service = _make_bound_service("parity")
	if service == null:
		return
	var legacy: Dictionary = service.export_durable_state()
	check(not legacy.is_empty(), "parity: legacy durable export valid")
	var cache = ChunkCache.new()
	check(bool(cache.configure(true).get("success", false)), "parity: cache enabled")
	check(bool(service.configure_r31bp1_durable_chunk_cache(cache).get("success", false)),
		"parity: cache attached")
	check(service.is_r31bp1_durable_chunks_enabled(), "parity: service reports ON")
	var before_direct: Dictionary = cache.get_report()
	var command_source: Dictionary = service.export_durable_state()
	check(command_source == legacy, "direct command durable exporter stays exact legacy")
	check(cache.get_report() == before_direct,
		"direct command / ACK durability never consults P1 cache")
	var first: Dictionary = _periodic_durable(service)
	var second: Dictionary = _periodic_durable(service)
	check(first == legacy, "parity: first (miss) export byte-equal to legacy")
	check(second == legacy, "parity: warm-hit export byte-equal to legacy")
	check(String(first.get("checksum", "")) == String(second.get("checksum", "")),
		"parity: outer checksum unchanged across hit")
	var report: Dictionary = cache.get_report()
	check(int(report.get("item_graph", {}).get("hits", -1)) >= 1,
		"parity: item graph warm hit recorded")
	check(int(report.get("resource_mining", {}).get("hits", -1)) >= 1,
		"parity: resource warm hit recorded")
	check(int(report.get("item_graph", {}).get("misses", -1)) >= 1,
		"parity: item graph first miss recorded")
	check(int(report.get("item_graph", {}).get("bytes", -1)) > 0,
		"parity: item chunk size measured")
	check(int(report.get("resource_mining", {}).get("bytes", -1)) > 0,
		"parity: resource chunk size measured")
	var profiled: Dictionary = service.export_durable_state_r31b_profiled()
	var stages: Dictionary = Dictionary(profiled.get("stages", {}))
	check(Dictionary(profiled.get("value", {})) == legacy,
		"profiled: cached path byte-equal to legacy")
	check(bool(stages.get("r31bp1_item_graph_cache_hit", false)),
		"profiled: item graph cache hit flagged")
	check(bool(stages.get("r31bp1_resource_cache_hit", false)),
		"profiled: resource cache hit flagged")
	check(bool(stages.get("r31bp1_chunks_enabled", false)),
		"profiled: cache-enabled flag exposed")
	# Fences must change after a real command and remain stable otherwise.
	var fence_before: Dictionary = cache.get_report().get("item_graph", {}).get("fence", {})
	check(not fence_before.is_empty(), "parity: cached fence recorded")
	service.shutdown()


func _test_nested_poison_isolation() -> void:
	var service = _make_bound_service("poison")
	if service == null:
		return
	var legacy: Dictionary = service.export_durable_state()
	var cache = ChunkCache.new()
	check(bool(cache.configure(true).get("success", false)), "poison: cache enabled")
	check(bool(service.configure_r31bp1_durable_chunk_cache(cache).get("success", false)),
		"poison: cache attached")
	var first: Dictionary = _periodic_durable(service)
	# Caller-side deep poison of the returned DTO, including nested structures.
	var poisoned: Dictionary = first
	poisoned["checksum"] = "caller-poison"
	var item_value = poisoned.get("canonical_item_graph", {})
	if item_value is Dictionary:
		Dictionary(item_value)["checksum"] = "nested-poison"
		var snapshot = Dictionary(item_value).get("snapshot", {})
		if snapshot is Dictionary:
			Dictionary(snapshot)["revision"] = 999999
	var resource_value = poisoned.get("resource_mining", {})
	if resource_value is Dictionary:
		Dictionary(resource_value)["checksum"] = "resource-poison"
	var second: Dictionary = _periodic_durable(service)
	check(second == legacy, "poison: warm hit unaffected by caller mutation")
	check(String(second.get("checksum", "")) != "caller-poison",
		"poison: outer checksum intact")
	var third: Dictionary = _periodic_durable(service)
	check(third == legacy, "poison: repeated hits remain pristine")
	# Disk checkpoint parity through the unchanged legacy finalize path is
	# covered by exact whole-DTO equality above (same finalize_json_checksum).
	service.shutdown()


func _test_invalidation_fences() -> void:
	# 1) Zero-revision player join (inventory + P5 tool seeding) invalidates M4
	#    only; resource chunk stays warm.
	var service = _make_bound_service("fences")
	if service == null:
		return
	var cache = ChunkCache.new()
	check(bool(cache.configure(true).get("success", false)), "fences: cache enabled")
	check(bool(service.configure_r31bp1_durable_chunk_cache(cache).get("success", false)),
		"fences: cache attached")
	check(not _periodic_durable(service).is_empty(), "fences: first export")
	var warm: Dictionary = _periodic_durable(service)
	check(not warm.is_empty(), "fences: warm export")
	var report_warm: Dictionary = cache.get_report()
	check(int(report_warm.get("item_graph", {}).get("hits", 0)) >= 1,
		"fences: item graph warm before join")
	var joined: Dictionary = service.join(
		"seam-player-b", "transport-session/r31bp1/b", "operation/r31bp1/join/b")
	check(bool(joined.get("success", false)), "fences: second player joined (seeded)")
	var bound_b: Dictionary = service.call("_ensure_seam_binding", "seam-player-b")
	check(bool(bound_b.get("success", false)), "fences: second seam binding established")
	var ticked_b: Dictionary = service.advance_fixed_server_tick(2)
	check(bool(ticked_b.get("success", false)), "fences: tick advanced after second join")
	check(not _periodic_durable(service).is_empty(), "fences: post-join export")
	var after_join: Dictionary = cache.get_report()
	check(int(after_join.get("item_graph", {}).get("misses", 0))
		> int(report_warm.get("item_graph", {}).get("misses", 0)),
		"fences: zero-revision player/tool seeding invalidates item graph")
	check(int(after_join.get("resource_mining", {}).get("misses", 0))
		== int(report_warm.get("resource_mining", {}).get("misses", 0)),
		"fences: player join does NOT invalidate resource chunk")
	# 2) ITEM command invalidates only M4.
	check(not _periodic_durable(service).is_empty(), "fences: re-warm export")
	var report_warm2: Dictionary = cache.get_report()
	var actor: Dictionary = service.get_player("seam-player")
	var epoch := int(actor.get("ownership_epoch", 1))
	var tool_id := "item/player/seam-player/p5-mining-tool"
	var item: Dictionary = service.handle_canonical_item_command(
		"seam-player", "transport-session/r31bp1/a",
		epoch,
		"operation/r31bp1/item/1", "item.equip",
		{"item_id": tool_id, "slot_id": "tool/main"})
	check(bool(item.get("success", false)),
		"fences: real ITEM command applied (%s)" % String(item.get("error_code", "")))
	check(not _periodic_durable(service).is_empty(), "fences: post-item export")
	var report_after_item: Dictionary = cache.get_report()
	check(int(report_after_item.get("item_graph", {}).get("misses", 0))
		> int(report_warm2.get("item_graph", {}).get("misses", 0)),
		"fences: ITEM invalidates item graph")
	check(int(report_after_item.get("resource_mining", {}).get("misses", 0))
		== int(report_warm2.get("resource_mining", {}).get("misses", 0)),
		"fences: ITEM does NOT invalidate resource chunk")
	# 3) Same-generation resource restore invalidates only resource (ABA).
	check(not _periodic_durable(service).is_empty(), "fences: re-warm before restore")
	var report_warm3: Dictionary = cache.get_report()
	var mining = service.get("_resource_mining")
	check(mining != null, "fences: resource service reachable")
	if mining != null:
		var snapshot: Dictionary = mining.export_durable_state()
		check(bool(snapshot.get("success", false)) or not snapshot.is_empty(),
			"fences: resource export ok")
		var restored: Dictionary = mining.restore_durable_state(snapshot)
		check(bool(restored.get("success", false)), "fences: same-generation restore applied")
	check(not _periodic_durable(service).is_empty(), "fences: post-restore export")
	var report_after_restore: Dictionary = cache.get_report()
	check(int(report_after_restore.get("resource_mining", {}).get("misses", 0))
		> int(report_warm3.get("resource_mining", {}).get("misses", 0)),
		"fences: same-generation restore invalidates resource chunk (ABA)")
	check(int(report_after_restore.get("item_graph", {}).get("misses", 0))
		== int(report_warm3.get("item_graph", {}).get("misses", 0)),
		"fences: resource restore does NOT invalidate item graph")
	service.shutdown()


class _HugeSource:
	extends RefCounted
	var generation := 1
	var bytes := 5 * 1024 * 1024
	func get_r31bp1_chunk_fence() -> Dictionary:
		return {"kind": "resource_mining", "instance_id": get_instance_id(),
			"authority_owner_id": "authority/x", "authority_epoch": 1,
			"generation": generation, "state_serial": 1}
	func export_durable_state() -> Dictionary:
		var big: PackedByteArray = PackedByteArray()
		big.resize(bytes)
		return {"schema": "x", "blob": big.hex_encode(), "checksum": ""}


func _test_oversize_bypass() -> void:
	var cache = ChunkCache.new()
	check(bool(cache.configure(true).get("success", false)), "oversize: cache enabled")
	var huge = _HugeSource.new()
	var exported: Dictionary = cache.export_component(huge, "resource_mining")
	check(Dictionary(exported).has("value") and not Dictionary(exported.get("value", {})).is_empty(),
		"oversize: full component export still returned")
	check(String(exported.get("bypass", "")) == "CHUNK_OVERSIZE",
		"oversize: bypass recorded, not hidden")
	check(int(exported.get("bytes", 0)) > 4 * 1024 * 1024,
		"oversize: measured byte size above budget")
	var report: Dictionary = cache.get_report()
	check(int(report.get("resource_mining", {}).get("bypasses", 0)) == 1,
		"oversize: bypass counter exposed")
	check(report.get("resource_mining", {}).get("cached", true) == false,
		"oversize: component NOT cached")



class _ChangingSource:
	extends RefCounted
	var serial := 1
	func get_r31bp1_chunk_fence() -> Dictionary:
		return {
			"kind": "item_graph", "instance_id": get_instance_id(),
			"authority_owner_id": "authority/test", "authority_epoch": 1,
			"revision": 5, "tick": 5, "state_serial": serial,
		}
	func export_durable_state() -> Dictionary:
		# Adversarial *synchronous* source mutation while exporting, even if
		# no threads or await appear in production source methods.
		serial += 1
		return {"schema": "test", "value": serial, "checksum": "test-only"}


func _test_changed_source_fence() -> void:
	var cache = ChunkCache.new()
	check(bool(cache.configure(true).get("success", false)),
		"changed fence cache configured")
	var source = _ChangingSource.new()
	var before: Dictionary = source.get_r31bp1_chunk_fence()
	var first: Dictionary = cache.export_component(source, "item_graph")
	check(source.get_r31bp1_chunk_fence() != before,
		"source serial actually changed synchronously during export")
	check(String(first.get("bypass", "")) == "SOURCE_FENCE_CHANGED",
		"post-export fence mismatch classified")
	check(Dictionary(first.get("value", {})).is_empty(),
		"changed source cannot yield any cacheable durable DTO")
	var report: Dictionary = cache.get_report()
	check(report.get("item_graph", {}).get("cached", true) == false,
		"changed source never populates private cache")
	check(int(report.get("item_graph", {}).get(
		"bypass_reasons", {}).get("SOURCE_FENCE_CHANGED", 0)) == 1,
		"fail-closed SOURCE_FENCE_CHANGED reason recorded")
	var service = _make_bound_service("changed-source")
	if service == null:
		return
	check(bool(service.configure_r31bp1_durable_chunk_cache(cache).get(
		"success", false)), "real ProductSeam attaches cache")
	var mediated: Dictionary = service.call(
		"_r31bp1_export_component", source, "item_graph")
	check(mediated.is_empty(),
		"ProductSeam does not hide changed source with a second live export")
	service.shutdown()


func _test_exact_m6_disk_periodic_vs_direct_export() -> void:
	var service = _make_bound_service("m6-periodic")
	if service == null:
		return
	var adapter = Adapter.new()
	check(bool(adapter.setup(service).get("success", false)),
		"M6 adapter configured")
	var cache = ChunkCache.new()
	check(bool(cache.configure(true).get("success", false)),
		"M6 active cache configured")
	check(bool(service.configure_r31bp1_durable_chunk_cache(cache).get(
		"success", false)), "M6 owner P1 cache attached")
	var canonical: Dictionary = adapter.export_recovery_state()
	check(not canonical.is_empty(), "M6 direct command export valid")
	var before_direct: Dictionary = cache.get_report()
	adapter.export_recovery_state()
	check(cache.get_report() == before_direct,
		"M6 direct command export never hits P1 cache")
	var source: Dictionary = adapter.capture_frozen_gameplay_source_r31b_profiled()
	var frozen: Dictionary = Dictionary(source.get("frozen_gameplay", {}))
	var wrapped: Dictionary = Adapter.wrap_frozen_gameplay_source(frozen)
	check(wrapped == canonical,
		"periodic P1 frozen M6 envelope exactly matches legacy direct M6")
	var replay_owner = Outbox.new()
	check(bool(replay_owner.setup(service).get("success", false)),
		"M6 outbox ready")
	var replay: Dictionary = replay_owner.to_dict()
	var expected: Dictionary = Checkpoint.create(
		"checkpoint/r31bp1/fence/1", 1, 0, wrapped, replay, "",
		int(wrapped.get("server_tick", -1)))
	check(bool(Checkpoint.validate(expected).get("success", false)),
		"M6 checksum and canonical checkpoint validate")
	var disk_root := _path("fenced-disk")
	var writer = Writer.new()
	var ready: Dictionary = writer.setup(disk_root)
	check(bool(ready.get("success", false)), "one M6 disk writer configured")
	if bool(ready.get("success", false)):
		var submitted: Dictionary = writer.submit_frozen_gameplay_source(
			frozen, replay, "checkpoint/r31bp1/fence/1", 1, 0)
		check(bool(submitted.get("success", false)), "durable generation admitted")
		check(writer.is_busy(), "no pre-disk generation ACK")
		var source_mutable: Dictionary = Dictionary(frozen.get("durable_state", {}))
		source_mutable["checksum"] = "tampered-after-submit"
		replay.clear()
		var finished: Dictionary = writer.wait_completed()
		check(bool(finished.get("success", false)), "writer committed checkpoint")
		var repository = Repository.new()
		check(bool(repository.configure(disk_root).get("success", false)),
			"recovery root configured")
		var saved: Dictionary = repository.load_committed()
		check(bool(saved.get("success", false)), "disk checkpoint restored")
		if bool(saved.get("success", false)):
			check(Dictionary(saved.get("details", {}).get("checkpoint", {})) == expected,
				"disk checksum/DTO parity despite caller alias poison")
		writer.stop()
	service.shutdown()


func _test_runtime_gates() -> void:
	# Invalid environment mode fails closed.
	OS.set_environment("DWS_NET_R31BP1_DURABLE_CHUNKS", "2")
	var bad_mode = Runtime.new()
	var bad: Dictionary = bad_mode.setup({
		"host": "127.0.0.1", "port": _port(),
		"playable_sandbox": true, "persistence_root": _path("bad-mode"),
		"r3c4_periodic_frame_pacing_canary": true,
		"r3c4r2_worker_envelope_canary": true,
		"r3c4r31_replay_projection_canary": true,
		"r3c4r31b_durable_attribution_canary": true,
		"product_seam_enabled": true,
	})
	check(not bool(bad.get("success", false))
		and String(bad.get("error_code", "")) == "R31BP1_INVALID_MODE",
		"bad env mode fails closed")
	bad_mode.free()
	OS.set_environment("DWS_NET_R31BP1_DURABLE_CHUNKS", "")
	# P1 flag with replay/R2/persistence/seam but WITHOUT P0 attribution: the
	# P1 gate itself must fail closed.
	var missing = Runtime.new()
	var missing_result: Dictionary = missing.setup({
		"host": "127.0.0.1", "port": _port(),
		"playable_sandbox": true, "product_seam_enabled": true,
		"persistence_root": _path("missing"),
		"r3c4_periodic_frame_pacing_canary": true,
		"r3c4r2_worker_envelope_canary": true,
		"r3c4r31_replay_projection_canary": true,
		"r31bp1_durable_chunks_canary": true,
	})
	check(not bool(missing_result.get("success", false))
		and String(missing_result.get("error_code", "")) == "R31BP1_REQUIRES_P0_ATTRIBUTION_REPLAY_R2_PERSISTENCE",
		"P1 without full P0 stack fails closed (%s)" % String(missing_result.get("error_code", "no-error")))
	missing.free()
	# Full stack: server starts, cache attached, exports flow through cache.
	var live = Runtime.new()
	var result: Dictionary = live.setup({
		"host": "127.0.0.1", "port": _port(),
		"playable_sandbox": true, "product_seam_enabled": true,
		"persistence_root": _path("runtime"),
		"r3c4_periodic_frame_pacing_canary": true,
		"r3c4r2_worker_envelope_canary": true,
		"r3c4r31_replay_projection_canary": true,
		"r3c4r31b_durable_attribution_canary": true,
		"r31bp1_durable_chunks_canary": true,
	})
	check(bool(result.get("success", false)), "P1 real server configured with full stack")
	if bool(result.get("success", false)):
		live.set_process(false)
		check(bool(live.get("_r31bp1_durable_chunks_enabled")),
			"P1 flag explicitly enabled on server")
		var service = live.get("_service")
		check(service != null and service.is_r31bp1_durable_chunks_enabled(),
			"P1 cache attached to the USER1 service")
		var stopped: Dictionary = live.stop()
		check(bool(stopped.get("success", false)), "P1 server shutdown barrier intact")
	live.free()


func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures.append(label)

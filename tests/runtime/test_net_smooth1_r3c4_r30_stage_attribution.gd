extends SceneTree

# R3C.4 R3.0 does NOT optimize persistence: only a traced decomposition
# of replay export/checksum and main-thread deep copy. Exact disk and M6
# parity with R2 are mandatory before any COW R3.1 implementation.
const Service = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
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
	OS.set_environment("DWS_NET_R3C4_R30_STAGE_ATTRIBUTION", "")
	_test_parity_and_writer()
	_test_runtime_gate()
	for item in failures:
		push_error("R3C4_R30_FAIL:" + item)
	print("NET_SMOOTH_R3C4_R30 %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _path(tag: String) -> String:
	return ProjectSettings.globalize_path(
		"res://artifacts/net-smooth1/r3c4-r30-%s-%d" % [tag, Time.get_ticks_usec()])

func _port() -> int:
	var peer := PacketPeerUDP.new()
	if peer.bind(0, "127.0.0.1") != OK:
		return 0
	var port: int = peer.get_local_port()
	peer.close()
	return port

func _test_parity_and_writer() -> void:
	var service = Service.new()
	var setup: Dictionary = service.setup("simulation/r3c4/r30", 1, 0, {
		"profile": Service.PROFILE_MULTIPLAYER_CORE,
		"topology_adapter": "ENET", "region_id": "region/r3c4/r30"})
	check(bool(setup.get("success", false)), "service configured")
	if not bool(setup.get("success", false)):
		return
	check(bool(service.join("a", "transport-session/r3c4/r30/a",
		"operation/r3c4/r30/join/a").get("success", false)), "join accepted")
	var adapter = Adapter.new()
	check(bool(adapter.setup(service).get("success", false)), "adapter configured")
	var outbox = Outbox.new()
	check(bool(outbox.setup(service).get("success", false)), "outbox configured")
	var original: Dictionary = outbox.to_dict()
	var measured: Dictionary = outbox.to_dict_profiled()
	var replay: Dictionary = Dictionary(measured.get("value", {}))
	check(original == replay, "profiled replay byte-equivalent to default path")
	var metrics: Dictionary = Dictionary(measured.get("metrics", {}))
	check(float(metrics.get("gameplay_export_ms", -1.0)) >= 0.0,
		"service replay export duration exposed")
	check(float(metrics.get("checksum_detach_ms", -1.0)) >= 0.0,
		"outbox checksum + detached serialization duration exposed")
	check(int(metrics.get("service_ledger_count", -1)) >= 1,
		"replay operation ledger size exposed")
	var source: Dictionary = adapter.capture_frozen_gameplay_source_for_worker()
	var authority: Dictionary = Adapter.wrap_frozen_gameplay_source(source)
	var expected: Dictionary = Checkpoint.create(
		"checkpoint/r3c4/r30/1", 1, 0, authority, replay, "",
		int(authority.get("server_tick", -1)))
	check(bool(Checkpoint.validate(expected).get("success", false)),
		"accepted checkpoint parity baseline valid")
	var root_path: String = _path("writer")
	var writer = Writer.new()
	var configured: Dictionary = writer.setup(root_path)
	check(bool(configured.get("success", false)), "single worker configured")
	if not bool(configured.get("success", false)):
		service.shutdown()
		return
	var submitted: Dictionary = writer.submit_frozen_gameplay_source(
		source, replay, "checkpoint/r3c4/r30/1", 1, 0, true)
	check(bool(submitted.get("success", false)), "profiled source submission")
	check(float(submitted.get("details", {}).get("handoff_copy_ms", -1.0)) >= 0.0,
		"measured deep copy on submitting frame")
	check(writer.is_busy(), "durable generation still in flight")
	var nested: Dictionary = source.get("durable_state", {})
	nested["checksum"] = "poison"
	replay.clear()
	var completed: Dictionary = writer.wait_completed()
	check(bool(completed.get("success", false)), "worker committed despite caller mutation")
	var repository = Repository.new()
	check(bool(repository.configure(root_path).get("success", false)),
		"disk repo configured")
	var disk: Dictionary = repository.load_committed()
	check(bool(disk.get("success", false)), "exact disk checkpoint restored")
	if bool(disk.get("success", false)):
		check(Dictionary(disk.get("details", {}).get("checkpoint", {})) == expected,
			"recorded timing does not change persisted bytes")
	writer.stop()
	service.shutdown()

func _test_runtime_gate() -> void:
	var denied = Runtime.new()
	var result: Dictionary = denied.setup({
		"host": "127.0.0.1", "port": _port(),
		"playable_sandbox": true, "persistence_root": _path("denied"),
		"r3c4r30_stage_attribution_canary": true})
	check(not bool(result.get("success", false)) and
		String(result.get("error_code", "")) ==
			"R3C4_R30_REQUIRES_R2_WORKER_ENVELOPE",
		"R3.0 refuses activation without R2")
	denied.free()
	var runtime = Runtime.new()
	var correct: Dictionary = runtime.setup({
		"host": "127.0.0.1", "port": _port(),
		"playable_sandbox": true, "persistence_root": _path("enabled"),
		"r3c4_periodic_frame_pacing_canary": true,
		"r3c4r2_worker_envelope_canary": true,
		"r3c4r30_stage_attribution_canary": true})
	check(bool(correct.get("success", false)), "real server R3.0 configured")
	if not bool(correct.get("success", false)):
		runtime.free()
		return
	runtime.set_process(false)
	check(bool(runtime.get("_r3c4r30_stage_attribution_enabled")),
		"attribution strictly opt-in on server")
	var before: int = int(runtime.get("_checkpoint_generation"))
	runtime.set("_last_movement_snapshot_tick", -1)
	runtime.set("_movement_checkpoint_dirty", true)
	runtime.set("_movement_commands_since_checkpoint", 3)
	runtime.set("_last_movement_checkpoint_ms", -10000)
	runtime.call("_maybe_persist_movement_checkpoint")
	check(runtime.get("_movement_checkpoint_writer").is_busy(),
		"periodic worker actually enqueued")
	check(int(runtime.get("_checkpoint_generation")) == before,
		"no early generation before disk commit")
	runtime.call("_complete_async_movement_checkpoint", true)
	check(not bool(runtime.get("_fatal_persistence_failure")),
		"no persistence fatal")
	check(int(runtime.get("_checkpoint_generation")) == before + 1,
		"generation advances only on completion")
	check(bool(runtime.stop().get("success", false)),
		"shutdown maintains final durable barrier")
	runtime.free()

func check(pass_value: bool, label: String) -> void:
	assertions += 1
	if not pass_value:
		failures.append(label)

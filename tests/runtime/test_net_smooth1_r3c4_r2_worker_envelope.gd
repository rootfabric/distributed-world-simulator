extends SceneTree

# Exact frozen DTO / M6 worker-disk parity, fail-closed invalid envelope,
# caller alias mutation, and real server default-off/opt-in generation.
const Service = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
const Adapter = preload("res://scripts/runtime/networked_gameplay/m6/m6_dedicated_gameplay_authority_adapter.gd")
const Outbox = preload("res://scripts/runtime/networked_gameplay/m6/m6_durable_replay_outbox.gd")
const Checkpoint = preload("res://scripts/persistence/authoritative_checkpoint.gd")
const Writer = preload("res://scripts/persistence/async_checkpoint_writer.gd")
const Repository = preload("res://scripts/persistence/authoritative_recovery_repository.gd")
const Runtime = preload("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd")
var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	OS.set_environment("DWS_NET_R3C4_R2_WORKER_ENVELOPE", "")
	_test_worker_checkpoint_parity()
	_test_actual_runtime(false)
	_test_actual_runtime(true)
	_test_invalid_opt_in()
	for failure in failures: push_error("R3C4_R2_FAIL:" + failure)
	print("NET_SMOOTH_R3C4_R2_WORKER_ENVELOPE %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _path(tag: String) -> String:
	return ProjectSettings.globalize_path(
		"res://artifacts/net-smooth1/r3c4-r2-%s-%d" % [tag, Time.get_ticks_usec()])

func _port() -> int:
	var sock := PacketPeerUDP.new()
	if sock.bind(0, "127.0.0.1") != OK: return 0
	var port: int = sock.get_local_port()
	sock.close()
	return port

func _test_worker_checkpoint_parity() -> void:
	var service = Service.new()
	var setup: Dictionary = service.setup("simulation/r3c4/r2", 1, 0, {
		"profile": Service.PROFILE_MULTIPLAYER_CORE,
		"topology_adapter": "ENET", "region_id": "region/r3c4/r2"})
	check(bool(setup.get("success", false)), "real service configured")
	if not bool(setup.get("success", false)): return
	check(bool(service.join("a", "transport-session/r3c4/a/1",
		"operation/r3c4/join/1").get("success", false)), "canonical joined player")
	var adapter = Adapter.new()
	check(bool(adapter.setup(service).get("success", false)), "M6 adapter configured")
	var outbox = Outbox.new()
	check(bool(outbox.setup(service).get("success", false)), "M6 outbox configured")
	var legacy: Dictionary = adapter.export_recovery_state()
	var source: Dictionary = adapter.capture_frozen_gameplay_source_for_worker()
	check(not source.is_empty(), "source DTO captured atomically")
	var wrapped: Dictionary = Adapter.wrap_frozen_gameplay_source(source)
	check(wrapped == legacy, "worker envelope matches legacy exact DTO")
	var replay: Dictionary = outbox.to_dict()
	var expected: Dictionary = Checkpoint.create(
		"checkpoint/r3c4/r2/1", 1, 0, legacy, replay, "",
		int(legacy.get("server_tick", -1)))
	check(bool(Checkpoint.validate(expected).get("success", false)),
		"legacy checkpoint valid")
	var path: String = _path("dto")
	var writer = Writer.new()
	check(bool(writer.setup(path).get("success", false)), "writer setup")
	check(bool(writer.submit_frozen_gameplay_source(source, replay,
		"checkpoint/r3c4/r2/1", 1, 0).get("success", false)),
		"frozen source queued on single writer")
	check(writer.is_busy(), "generation in-flight before ACK")
	# This mutation MUST NOT touch the worker's copies.
	var inner: Dictionary = source.get("durable_state", {})
	inner["checksum"] = "caller-mutated-after-submit"
	source["logical_session_id"] = "mutated/caller"
	replay.clear()
	var completed: Dictionary = writer.wait_completed()
	check(bool(completed.get("success", false)), "detached state persisted")
	check(float(completed.get("details", {}).get("wrap_ms", -1.0)) >= 0.0,
		"envelope timing measured by worker")
	var repo = Repository.new()
	check(bool(repo.configure(path).get("success", false)), "disk repo configured")
	var readout: Dictionary = repo.load_committed()
	check(bool(readout.get("success", false)), "checkpoint recovered from disk")
	if bool(readout.get("success", false)):
		check(Dictionary(readout["details"]["checkpoint"]) == expected,
			"disk checkpoint AND SHA exactly equal old envelope")
	var bad: Dictionary = {
		"logical_session_id": "bad session", "durable_state": {"schema": "invalid"}}
	check(bool(writer.submit_frozen_gameplay_source(bad, outbox.to_dict(),
		"checkpoint/r3c4/r2/2", 2, 1).get("success", false)),
		"bad DTO submitted for negative test")
	var rejected: Dictionary = writer.wait_completed()
	check(not bool(rejected.get("success", false)) and
		String(rejected.get("error_code", "")) == "R3C4_R2_WORKER_ENVELOPE_INVALID",
		"worker rejects invalid envelope before repository")
	check(int(repo.load_committed().get("details", {}).get("checkpoint", {}).get(
		"generation", -1)) == 1, "rejected DTO cannot overwrite durable generation")
	writer.stop()
	service.shutdown()

func _test_actual_runtime(enabled: bool) -> void:
	var runtime = Runtime.new()
	root.add_child(runtime)
	var path: String = _path("runtime-on" if enabled else "runtime-off")
	var setup: Dictionary = runtime.setup({
		"host": "127.0.0.1", "port": _port(),
		"playable_sandbox": true, "persistence_root": path,
		"r3c4_periodic_frame_pacing_canary": true,
		"r3c4r2_worker_envelope_canary": enabled})
	check(bool(setup.get("success", false)), "real M3 setup")
	if not bool(setup.get("success", false)):
		runtime.free()
		return
	runtime.set_process(false)
	check(bool(runtime.get("_r3c4r2_worker_envelope_enabled")) == enabled,
		"default off / opt in correctly fenced")
	var generation: int = int(runtime.get("_checkpoint_generation"))
	runtime.set("_last_movement_snapshot_tick", -1)
	runtime.set("_movement_checkpoint_dirty", true)
	runtime.set("_movement_commands_since_checkpoint", 3)
	runtime.set("_last_movement_checkpoint_ms", -10000)
	runtime.call("_maybe_persist_movement_checkpoint")
	check(runtime.get("_movement_checkpoint_writer").is_busy(),
		"periodic in-flight: no early ACK or generation advance")
	check(int(runtime.get("_checkpoint_generation")) == generation,
		"submit does not publish checkpoint generation")
	runtime.call("_complete_async_movement_checkpoint", true)
	check(not bool(runtime.get("_fatal_persistence_failure")),
		"completion does not PERSISTENCE_FATAL")
	check(int(runtime.get("_checkpoint_generation")) == generation+1,
		"durability completion advances generation once")
	var gate = runtime.get("_durable_ack_gate")
	check(int(gate.get_report().get("generation", -1)) == generation+1,
		"ACK gate remains aligned with durable generations")
	var done: Dictionary = runtime.get("_async_checkpoint_last")
	check(float(done.get("wrap_ms", -1.0)) >= 0.0,
		"worker reports envelope construction time")
	var repo = Repository.new()
	check(bool(repo.configure(path).get("success", false)), "independent repo setup")
	check(int(repo.load_committed().get("details", {}).get("checkpoint", {}).get(
		"generation", -1)) == generation+1, "disk recovery exact generation")
	check(bool(runtime.stop().get("success", false)), "real runtime shutdown barrier")
	runtime.free()

func _test_invalid_opt_in() -> void:
	var runtime = Runtime.new()
	var result: Dictionary = runtime.setup({
		"host": "127.0.0.1", "port": _port(),
		"playable_sandbox": true, "persistence_root": _path("bad"),
		"r3c4r2_worker_envelope_canary": true})
	check(not bool(result.get("success", false)) and
		String(result.get("error_code", "")) ==
		"R3C4_R2_REQUIRES_PERIODIC_PERSISTENT_MODE",
		"R2 refuses active mode without R1 pacing")
	runtime.free()

func check(value: bool, label: String) -> void:
	assertions += 1
	if not value: failures.append(label)

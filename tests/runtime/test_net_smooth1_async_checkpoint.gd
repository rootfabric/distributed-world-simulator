extends SceneTree
const Writer = preload("res://scripts/persistence/async_checkpoint_writer.gd")
const Service = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
const Adapter = preload("res://scripts/runtime/networked_gameplay/m6/m6_dedicated_gameplay_authority_adapter.gd")
const Outbox = preload("res://scripts/runtime/networked_gameplay/m6/m6_durable_replay_outbox.gd")
const Repository = preload("res://scripts/persistence/authoritative_recovery_repository.gd")
const Checkpoint = preload("res://scripts/persistence/authoritative_checkpoint.gd")
const Runtime = preload("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd")
var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func run() -> void:
	test_writer()
	test_runtime_dirty_and_barrier()
	check(assertions == 37, "all expected runtime assertions executed")
	for f in failures: push_error(f)
	print("NET_SMOOTH1_ASYNC: %s assertions=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

func test_writer() -> void:
	var path := ProjectSettings.globalize_path("res://artifacts/net-smooth1/async-unit-%d" % Time.get_ticks_usec())
	var service = Service.new()
	check(ok(service.setup("simulation/smooth/test", 1, 0, {"profile": Service.PROFILE_MULTIPLAYER_CORE, "topology_adapter":"ENET", "region_id":"region/smooth/test"})), "service setup")
	check(ok(service.join("a", "transport-session/smooth/a/1", "operation/smooth/join/1")), "join")
	var adapter = Adapter.new()
	check(ok(adapter.setup(service)), "adapter setup")
	var outbox = Outbox.new()
	check(ok(outbox.setup(service)), "outbox setup")
	var authority: Dictionary = adapter.export_recovery_state()
	var replay: Dictionary = outbox.to_dict()
	var reference: Dictionary = Checkpoint.create("checkpoint/smooth/1", 1, 0, authority, replay, "", int(authority["server_tick"]))
	var writer = Writer.new()
	check(not ok(writer.submit({}, {}, "x", 1, 0)), "submit before setup rejected")
	check(ok(writer.setup(path)), "persistent worker setup")
	check(not ok(writer.setup(path)), "double setup rejected")
	check(ok(writer.submit(authority, replay, "checkpoint/smooth/1", 1, 0)), "first snapshot queued")
	check(writer.is_busy(), "busy until completion consumed")
	check(not ok(writer.submit(authority, replay, "checkpoint/smooth/2", 2, 1)), "bounded queue refuses second snapshot")
	# Deliberately corrupt caller-owned containers AFTER submission: worker must
	# retain the detached originals. Live state also advances independently.
	authority["session_id"] = "bad/caller/mutation"
	replay.clear()
	check(ok(service.move_player("a", "transport-session/smooth/a/1", 1, 1, 0.1, 0.0, "operation/smooth/move/1")), "live state advances while worker owns old snapshot")
	var result: Dictionary = writer.wait_completed()
	check(ok(result), "worker persisted detached snapshot")
	check(not writer.is_busy(), "completion releases slot")
	check(int(result.get("details", {}).get("generation", 0)) == 1, "generation returned")
	check(float(result.get("details", {}).get("worker_ms", -1.0)) >= 0.0, "worker duration returned")
	var repo = Repository.new()
	check(ok(repo.configure(path)), "read repository")
	var loaded: Dictionary = repo.load_committed()
	check(ok(loaded), "load worker checkpoint")
	check(String(loaded.get("details", {}).get("checkpoint", {}).get("checksum", "")) == String(reference.get("checksum", "!")), "exact JSON/checksum compatibility and capture isolation")
	check(ok(writer.submit(adapter.export_recovery_state(), outbox.to_dict(), "checkpoint/smooth/1", 1, 0)), "stale generation queued for validation")
	check(not ok(writer.wait_completed()), "repository progression rejects stale generation")
	check(ok(writer.submit(adapter.export_recovery_state(), outbox.to_dict(), "checkpoint/smooth/2", 2, 1)), "new generation queued")
	var stopped: Dictionary = writer.stop()
	check(ok(stopped), "shutdown drains pending checkpoint")
	check(int(repo.load_committed().get("details", {}).get("checkpoint", {}).get("generation", 0)) == 2, "shutdown persisted final generation")
	check(writer.stop().is_empty(), "repeated stop safe")
	service.shutdown()

func test_runtime_dirty_and_barrier() -> void:
	var socket := PacketPeerUDP.new()
	check(socket.bind(0, "127.0.0.1") == OK, "allocate unique port")
	var port := socket.get_local_port()
	socket.close()
	var path := ProjectSettings.globalize_path("res://artifacts/net-smooth1/async-runtime-%d" % Time.get_ticks_usec())
	var runtime = Runtime.new()
	get_root().add_child(runtime)
	var setup: Dictionary = runtime.setup({"host":"127.0.0.1", "port":port, "playable_sandbox":true, "persistence_root":path})
	check(ok(setup), "real server runtime setup")
	if not ok(setup):
		runtime.free()
		return
	runtime.set_process(false)
	var before := int(runtime.get("_checkpoint_generation"))
	runtime.set("_movement_checkpoint_dirty", true)
	runtime.set("_movement_commands_since_checkpoint", 4)
	runtime.set("_last_movement_checkpoint_ms", -10000)
	runtime.call("_maybe_persist_movement_checkpoint")
	check(runtime.get("_movement_checkpoint_writer").is_busy(), "runtime submitted async checkpoint")
	check(int(runtime.get("_checkpoint_generation")) == before, "submission does NOT publish generation")
	# Simulate movement arriving after capture. Completion must preserve it.
	runtime.set("_movement_checkpoint_dirty", true)
	runtime.set("_movement_commands_since_checkpoint", 7)
	runtime.call("_complete_async_movement_checkpoint", true)
	check(not bool(runtime.get("_fatal_persistence_failure")), "completion succeeds")
	check(int(runtime.get("_checkpoint_generation")) == before + 1, "only completion advances generation")
	check(bool(runtime.get("_movement_checkpoint_dirty")), "newer movement remains dirty")
	check(int(runtime.get("_movement_commands_since_checkpoint")) == 7, "newer command count retained")
	runtime.set("_last_movement_checkpoint_ms", -10000)
	runtime.call("_maybe_persist_movement_checkpoint")
	check(runtime.get("_movement_checkpoint_writer").is_busy(), "second movement snapshot queued")
	var sync: Dictionary = runtime.call("_persist_checkpoint", "")
	check(ok(sync), "sync durability barrier succeeds after in-flight periodic writer")
	check(int(runtime.get("_checkpoint_generation")) == before + 3, "async then sync generations strictly ordered")
	check(ok(runtime.stop()), "real runtime shutdown joins worker and commits final state")
	check(runtime.get("_movement_checkpoint_writer") == null, "worker released")
	runtime.free()

func ok(result: Dictionary) -> bool:
	return bool(result.get("success", false))

func check(value: bool, label: String) -> void:
	assertions += 1
	if not value: failures.append(label)

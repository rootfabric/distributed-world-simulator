extends SceneTree

# NET-SMOOTH1 R3C.4 R1: real server+single-writer checkpoint scheduling.
# The opt-in only changes the *frame* of a periodic capture. It must not
# change the durable generation, replay order, or ACK eligibility.
const Runtime = preload("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd")
const Repository = preload("res://scripts/persistence/authoritative_recovery_repository.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_requires_persistent_playable_world()
	_test_r3c4_enabled_same_frame_defer_and_bounded_force()
	_test_default_off_remains_immediate()
	for error in failures:
		push_error("R3C4_FAIL:" + error)
	print("NET_SMOOTH_R3C4_PERIODIC_FRAME_HEADROOM %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()
	])
	quit(0 if failures.is_empty() else 1)


func _port() -> int:
	var socket := PacketPeerUDP.new()
	if socket.bind(0, "127.0.0.1") != OK:
		return 0
	var result: int = socket.get_local_port()
	socket.close()
	return result


func _root_path(label: String) -> String:
	return ProjectSettings.globalize_path(
		"res://artifacts/net-smooth1/r3c4-%s-%d" % [label, Time.get_ticks_usec()]
	)


func _new_runtime(label: String, enabled: bool) -> Dictionary:
	var runtime = Runtime.new()
	root.add_child(runtime)
	var path: String = _root_path(label)
	var result: Dictionary = runtime.setup({
		"host": "127.0.0.1",
		"port": _port(),
		"playable_sandbox": true,
		"persistence_root": path,
		"r3c4_periodic_frame_pacing_canary": enabled,
	})
	check(bool(result.get("success", false)), label + " runtime configured")
	if not bool(result.get("success", false)):
		runtime.free()
		return {}
	runtime.set_process(false)
	return {"runtime": runtime, "path": path}


func _due(runtime) -> void:
	runtime.set("_movement_checkpoint_dirty", true)
	runtime.set("_movement_commands_since_checkpoint", 3)
	runtime.set("_last_movement_checkpoint_ms", -10000)


func _test_requires_persistent_playable_world() -> void:
	var runtime = Runtime.new()
	var result: Dictionary = runtime.setup({
		"host": "127.0.0.1", "port": _port(),
		"playable_sandbox": true,
		"r3c4_periodic_frame_pacing_canary": true,
	})
	check(not bool(result.get("success", false)) and
		String(result.get("error_code", "")) == "R3C4_PERSISTENT_PLAYABLE_WORLD_REQUIRED",
		"opt-in without persistent world fails closed")
	runtime.free()


func _test_r3c4_enabled_same_frame_defer_and_bounded_force() -> void:
	var state: Dictionary = _new_runtime("enabled", true)
	if state.is_empty():
		return
	var runtime = state["runtime"]
	var writer = runtime.get("_movement_checkpoint_writer")
	var initial_generation: int = int(runtime.get("_checkpoint_generation"))
	check(bool(runtime.get("_r3c4_periodic_frame_pacing")),
		"opt-in frame scheduler really enabled")

	_due(runtime)
	runtime.set("_r3c4_snapshot_published_this_frame", true)
	runtime.set("_r3c4_pre_capture_work_us", 7200)
	runtime.call("_maybe_persist_movement_checkpoint")
	check(not writer.is_busy(), "same-frame compact+periodic capture deferred")
	check(bool(runtime.get("_movement_checkpoint_dirty")), "deferred movement stays dirty")
	check(int(runtime.get("_checkpoint_generation")) == initial_generation,
		"deferred capture never advances durable generation")
	check(int(runtime.get("_r3c4_deferred_frames")) == 1,
		"one bounded frame deferral counted")
	check(int(runtime.get("_r3c4_due_since_ms")) >= 0,
		"bounded due timestamp retained")

	# Next available non-snapshot frame must use the exact existing M6 writer.
	runtime.set("_r3c4_snapshot_published_this_frame", false)
	runtime.set("_r3c4_pre_capture_work_us", 1000)
	runtime.call("_maybe_persist_movement_checkpoint")
	check(writer.is_busy(), "periodic checkpoint queued on independent frame")
	check(not bool(runtime.get("_movement_checkpoint_dirty")),
		"committed capture clears only captured dirty epoch")
	check(int(runtime.get("_checkpoint_generation")) == initial_generation,
		"generation advances only after durable writer completion")
	runtime.call("_complete_async_movement_checkpoint", true)
	check(not bool(runtime.get("_fatal_persistence_failure")),
		"actual worker completed without persistence fatal")
	check(int(runtime.get("_checkpoint_generation")) == initial_generation + 1,
		"one durable generation advanced exactly once")
	check(int(runtime.get("_durable_ack_gate").get_report().get("generation", -1)) ==
		initial_generation + 1, "M6 ACK generation observes periodic commit")
	check(int(runtime.get("_r3c4_due_since_ms")) == -1,
		"due latch reset after successful capture")

	# A constantly heavy frame cannot starve checkpoints: after the capped
	# delay the original capture is forced on the next periodic opportunity.
	_due(runtime)
	runtime.set("_r3c4_snapshot_published_this_frame", true)
	runtime.set("_r3c4_pre_capture_work_us", 7200)
	runtime.call("_maybe_persist_movement_checkpoint")
	check(not writer.is_busy(), "second heavy frame initially deferred")
	runtime.set("_r3c4_due_since_ms", Time.get_ticks_msec() - 80)
	runtime.call("_maybe_persist_movement_checkpoint")
	check(writer.is_busy(), "capture forced once maximum deferral exceeded")
	check(int(runtime.get("_r3c4_forced_captures")) == 1, "bounded force observed")
	runtime.call("_complete_async_movement_checkpoint", true)
	check(int(runtime.get("_checkpoint_generation")) == initial_generation + 2,
		"forced capture also strictly advances generation once")

	var disk = Repository.new()
	check(bool(disk.configure(String(state["path"])).get("success", false)),
		"independent disk repository setup")
	var restored: Dictionary = disk.load_committed()
	check(bool(restored.get("success", false)) and
		int(restored.get("details", {}).get("checkpoint", {}).get("generation", -1)) ==
		initial_generation + 2, "disk contains exact durable generation")
	check(bool(runtime.stop().get("success", false)), "R3C4 server shutdown barrier")
	runtime.free()


func _test_default_off_remains_immediate() -> void:
	var state: Dictionary = _new_runtime("legacy", false)
	if state.is_empty():
		return
	var runtime = state["runtime"]
	var writer = runtime.get("_movement_checkpoint_writer")
	var generation: int = int(runtime.get("_checkpoint_generation"))
	check(not bool(runtime.get("_r3c4_periodic_frame_pacing")),
		"default-off path is still original")
	_due(runtime)
	runtime.set("_r3c4_snapshot_published_this_frame", true)
	runtime.set("_r3c4_pre_capture_work_us", 9000)
	runtime.call("_maybe_persist_movement_checkpoint")
	check(writer.is_busy(), "default-off immediately queues existing periodic capture")
	check(int(runtime.get("_r3c4_deferred_frames")) == 0,
		"default-off never alters checkpoint scheduling")
	runtime.call("_complete_async_movement_checkpoint", true)
	check(not bool(runtime.get("_fatal_persistence_failure")) and
		int(runtime.get("_checkpoint_generation")) == generation + 1,
		"default-off generation and crash safety remain intact")
	check(bool(runtime.stop().get("success", false)), "legacy server stops safely")
	runtime.free()


func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures.append(label)

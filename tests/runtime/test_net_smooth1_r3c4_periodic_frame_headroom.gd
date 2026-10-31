extends SceneTree
# R3C.4 R1 falsifier: bounded periodic checkpoint frame headroom.
# Frame separation ONLY. The single-writer M6 pipeline, generation
# semantics and durable-before-ACK barrier must remain byte-identical.
const Runtime = preload("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd")
const Repository = preload("res://scripts/persistence/authoritative_recovery_repository.gd")
const ENV_VAR := "DWS_NET_R3C4_PERIODIC_FRAME_PACING"
var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func run() -> void:
	test_default_off_parity()
	test_opt_in_defer_and_low_work_submit()
	test_forced_bounded_capture_and_restore()
	test_invalid_mode_rejection()
	OS.set_environment(ENV_VAR, "")
	check(assertions >= 30, "all expected runtime assertions executed")
	for f in failures: push_error(f)
	print("NET_SMOOTH1_R3C4_FRAME_HEADROOM: %s assertions=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

func test_default_off_parity() -> void:
	OS.set_environment(ENV_VAR, "")
	var runtime := _setup(false)
	if runtime == null: return
	check(not bool(runtime.get("_r3c4_periodic_frame_pacing_enabled")), "default off without flag/env")
	_make_due_and_heavy(runtime)
	runtime.call("_maybe_persist_movement_checkpoint")
	check(runtime.get("_movement_checkpoint_writer").is_busy(), "flag OFF: heavy frame still submits immediately (exact prior behavior)")
	check(int(runtime.get("_r3c4_deferred_frames")) == 0, "flag OFF: no deferral accounting")
	var forced_before_stop := int(runtime.get("_r3c4_forced_captures"))
	drain_and_stop(runtime, "flag OFF: drain completion succeeds", "flag OFF: shutdown drains writer")
	check(forced_before_stop == 0, "flag OFF: no forced captures")

func test_opt_in_defer_and_low_work_submit() -> void:
	OS.set_environment(ENV_VAR, "")
	var runtime := _setup(true)
	if runtime == null: return
	check(bool(runtime.get("_r3c4_periodic_frame_pacing_enabled")), "config canary opt-in enables pacing")
	var before := int(runtime.get("_checkpoint_generation"))
	_make_due_and_heavy(runtime)
	runtime.call("_maybe_persist_movement_checkpoint")
	check(not runtime.get("_movement_checkpoint_writer").is_busy(), "opt-in: first deferred heavy frame does NOT submit")
	check(bool(runtime.get("_movement_checkpoint_dirty")), "opt-in: dirty data stays live across deferral")
	check(int(runtime.get("_checkpoint_generation")) == before, "opt-in: deferral publishes no generation")
	check(int(runtime.get("_r3c4_deferred_frames")) >= 1, "opt-in: deferral accounted")
	check(int(runtime.get("_r3c4_capture_slots")) == 0, "opt-in: no capture slot granted yet")
	# Durable command postcommit barrier is untouched by pacing.
	runtime.set("_r3c2_postcommit_pending", {"stage": 1, "pending": {}})
	runtime.set("_last_movement_snapshot_tick", int(runtime.get("_server_tick")) - 1)
	runtime.call("_maybe_persist_movement_checkpoint")
	check(not runtime.get("_movement_checkpoint_writer").is_busy(), "postcommit durable barrier still blocks periodic submit")
	runtime.set("_r3c2_postcommit_pending", {})
	# Next low-work frame grants the slot and submits through the unchanged pipeline.
	runtime.call("_maybe_persist_movement_checkpoint")
	check(runtime.get("_movement_checkpoint_writer").is_busy(), "opt-in: low-work frame submits via original pipeline")
	check(int(runtime.get("_checkpoint_generation")) == before, "submission does NOT publish generation (M6 parity)")
	check(int(runtime.get("_r3c4_capture_slots")) == 1, "exactly one capture slot granted")
	check(not bool(runtime.get("_fatal_persistence_failure")), "no failure during defer/submit cycle")
	# Completion parity: only completion advances generation, dirty retained.
	runtime.set("_movement_checkpoint_dirty", true)
	runtime.set("_movement_commands_since_checkpoint", 5)
	runtime.call("_complete_async_movement_checkpoint", true)
	check(not bool(runtime.get("_fatal_persistence_failure")), "completion succeeds")
	check(int(runtime.get("_checkpoint_generation")) == before + 1, "only completion advances generation")
	check(bool(runtime.get("_movement_checkpoint_dirty")), "newer movement remains dirty")
	drain_and_stop(runtime)

func test_forced_bounded_capture_and_restore() -> void:
	OS.set_environment(ENV_VAR, "1")
	var runtime := _setup(false)
	if runtime == null: return
	var before := int(runtime.get("_checkpoint_generation"))
	_make_due_and_heavy(runtime)
	# Simulate an unbroken heavy-frame streak older than the 64ms bound.
	runtime.set("_r3c4_deferral_started_ms", Time.get_ticks_msec() - 100)
	runtime.call("_maybe_persist_movement_checkpoint")
	check(runtime.get("_movement_checkpoint_writer").is_busy(), "due capture forced after 64ms even on heavy frame")
	check(int(runtime.get("_r3c4_forced_captures")) >= 1, "forced capture accounted")
	check(int(runtime.get("_r3c4_deferral_started_ms")) == 0, "deferral timer reset after forced slot")
	runtime.call("_complete_async_movement_checkpoint", true)
	check(int(runtime.get("_checkpoint_generation")) == before + 1, "forced capture completes as a normal generation")
	# Disk restore through the unchanged repository path.
	var repo = Repository.new()
	var root := String(runtime.get("_persistence_root"))
	check(ok(repo.configure(root)), "repository configured on checkpoint dir")
	var loaded: Dictionary = repo.load_committed()
	check(ok(loaded), "committed checkpoint loadable from disk")
	check(int(loaded.get("details", {}).get("checkpoint", {}).get("generation", 0)) == before + 1, "restored generation matches completion")
	check(not String(loaded.get("details", {}).get("checkpoint", {}).get("checksum", "")).is_empty(), "restored checksum present")
	check(ok(runtime.stop()), "shutdown joins worker and commits final state")
	check(runtime.get("_movement_checkpoint_writer") == null, "worker released on shutdown")
	runtime.free()

func test_invalid_mode_rejection() -> void:
	OS.set_environment(ENV_VAR, "sometimes")
	var runtime := _make_runtime()
	var result: Dictionary = runtime.setup(_config(_free_port(), false))
	check(not ok(result), "invalid R3C4 mode rejected")
	check(String(result.get("error_code", "")) == "R3C4_INVALID_PACING_MODE", "fail-closed error code")
	runtime.free()

func _setup(use_config_flag: bool) -> Object:
	var runtime := _make_runtime()
	var config := _config(_free_port(), use_config_flag)
	var result: Dictionary = runtime.setup(config)
	if not ok(result):
		failures.append("runtime setup failed: %s" % String(result.get("error_code", "?")))
		runtime.free()
		return null
	get_root().add_child(runtime)
	runtime.set_process(false)
	return runtime

func _make_runtime() -> Object:
	var runtime = Runtime.new()
	return runtime

func _config(port: int, config_flag: bool) -> Dictionary:
	var path := ProjectSettings.globalize_path("res://artifacts/net-smooth1/r3c4-headroom-%d" % Time.get_ticks_usec())
	var config: Dictionary = {"host": "127.0.0.1", "port": port, "playable_sandbox": true, "persistence_root": path}
	if config_flag:
		config["r3c4_periodic_frame_pacing_canary"] = true
	return config

func _free_port() -> int:
	var socket := PacketPeerUDP.new()
	check(socket.bind(0, "127.0.0.1") == OK, "allocate unique port")
	var port := socket.get_local_port()
	socket.close()
	return port

func _make_due_and_heavy(runtime: Object) -> void:
	runtime.set("_movement_checkpoint_dirty", true)
	runtime.set("_movement_commands_since_checkpoint", 3)
	runtime.set("_last_movement_checkpoint_ms", -10000)
	# Heavy frame marker: a 20Hz snapshot was prepared in this process frame.
	runtime.set("_last_movement_snapshot_tick", int(runtime.get("_server_tick")))

func drain_and_stop(runtime: Object, drain_label: String = "drain completion succeeds", stop_label: String = "shutdown drains writer") -> void:
	runtime.call("_complete_async_movement_checkpoint", true)
	check(not bool(runtime.get("_fatal_persistence_failure")), drain_label)
	check(ok(runtime.stop()), stop_label)
	runtime.free()

func ok(result: Dictionary) -> bool:
	return bool(result.get("success", false))

func check(value: bool, label: String) -> void:
	assertions += 1
	if not value: failures.append(label)

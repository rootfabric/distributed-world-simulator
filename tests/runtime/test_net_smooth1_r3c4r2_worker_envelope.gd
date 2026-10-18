extends SceneTree
# R3C.4 R2 falsifier: opt-in server worker-envelope capture.
# R2 must retain the exact R1 64ms periodic dispatch pacing, the existing
# single checkpoint worker, command durable-before-ACK ordering and the
# unchanged Checkpoint.create / repository.save_atomic pipeline. The wrapped
# envelope must be byte-equivalent to the legacy capture path.
const Runtime = preload("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd")
const Adapter = preload("res://scripts/runtime/networked_gameplay/m6/m6_dedicated_gameplay_authority_adapter.gd")
const Repository = preload("res://scripts/persistence/authoritative_recovery_repository.gd")
const Checkpoint = preload("res://scripts/persistence/authoritative_checkpoint.gd")
const R1_ENV := "DWS_NET_R3C4_PERIODIC_FRAME_PACING"
const R2_ENV := "DWS_NET_R3C4R2_WORKER_ENVELOPE"
var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func run() -> void:
	test_default_off()
	test_r2_requires_r1_fail_closed()
	test_invalid_modes_fail_closed()
	test_wrapped_envelope_equals_legacy()
	test_post_submit_mutation_cannot_alter_disk()
	test_invalid_dto_rejects_without_disk_mutation()
	test_r2_generation_and_ack_parity_with_r1_pacing()
	test_r2_checkpoint_disk_restore()
	OS.set_environment(R1_ENV, "")
	OS.set_environment(R2_ENV, "")
	check(assertions >= 40, "all expected runtime assertions executed")
	for f in failures: push_error(f)
	print("NET_SMOOTH1_R3C4R2_WORKER_ENVELOPE: %s assertions=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

func test_default_off() -> void:
	OS.set_environment(R1_ENV, "")
	OS.set_environment(R2_ENV, "")
	var runtime := _setup(false, false)
	if runtime == null: return
	check(not bool(runtime.get("_r3c4r2_worker_envelope_enabled")), "default off without flag/env")
	check(not bool(runtime.get("_r3c4_periodic_frame_pacing_enabled")), "R1 also default off")
	_make_due(runtime)
	runtime.call("_maybe_persist_movement_checkpoint")
	check(runtime.get("_movement_checkpoint_writer").is_busy(), "default off: legacy capture path submits unchanged")
	drain_and_stop(runtime)

func test_r2_requires_r1_fail_closed() -> void:
	OS.set_environment(R1_ENV, "")
	OS.set_environment(R2_ENV, "1")
	var runtime := _make_runtime()
	var result: Dictionary = runtime.setup(_config(_free_port(), false, false))
	check(not ok(result), "R2 without R1 is rejected")
	check(String(result.get("error_code", "")) == "R3C4R2_REQUIRES_PERIODIC_FRAME_PACING", "R2-without-R1 fail-closed error code")
	runtime.free()
	# Config canary cannot bypass the R1 dependency either.
	runtime = _make_runtime()
	result = runtime.setup(_config(_free_port(), false, true))
	check(not ok(result), "R2 canary without R1 is rejected")
	check(String(result.get("error_code", "")) == "R3C4R2_REQUIRES_PERIODIC_FRAME_PACING", "canary path fails closed too")
	runtime.free()

func test_invalid_modes_fail_closed() -> void:
	OS.set_environment(R1_ENV, "1")
	OS.set_environment(R2_ENV, "maybe")
	var runtime := _make_runtime()
	var result: Dictionary = runtime.setup(_config(_free_port(), false, false))
	check(not ok(result), "invalid R2 mode rejected")
	check(String(result.get("error_code", "")) == "R3C4R2_INVALID_WORKER_ENVELOPE_MODE", "invalid R2 mode error code")
	runtime.free()
	OS.set_environment(R2_ENV, "0")
	runtime = _make_runtime()
	result = runtime.setup(_config(_free_port(), false, false))
	check(ok(result), "R2 mode 0 is a valid explicit off")
	check(ok(runtime.stop()), "valid explicit-off runtime shuts down cleanly")
	runtime.free()

func test_wrapped_envelope_equals_legacy() -> void:
	OS.set_environment(R1_ENV, "1")
	OS.set_environment(R2_ENV, "1")
	var runtime := _setup(false, false)
	if runtime == null: return
	check(bool(runtime.get("_r3c4r2_worker_envelope_enabled")), "env opt-in enables R2 with R1")
	var service = runtime.get("_service")
	var adapter = runtime.get("_recovery_authority")
	var session := String(adapter.get("_logical_session_id"))
	# Unit equivalence: adapter export (re-exports live state) vs the pure R2
	# normalization of ONE detached durable DTO must produce equal envelopes.
	var legacy_authority: Dictionary = adapter.call("export_recovery_state")
	var dto: Dictionary = service.call("export_durable_state")
	check(not dto.is_empty(), "service durable DTO is non-empty")
	var wrapped: Dictionary = Adapter.normalize_durable_state(dto, session)
	check(not wrapped.is_empty(), "R2 normalized envelope is non-empty")
	check(legacy_authority == wrapped, "wrapped envelope equals legacy adapter envelope")
	check(String(wrapped.get("durable_state_checksum", "")) == String(dto.get("checksum", "")), "envelope binds the DTO checksum")
	# Full checkpoint equivalence: identical generations + replay produce an
	# identical normalized M6 checkpoint dictionary and SHA256.
	var replay: Dictionary = runtime.get("_replay_outbox").call("to_dict")
	check(not replay.is_empty(), "replay outbox projection is non-empty")
	var wrapped_cp: Dictionary = Checkpoint.create("checkpoint/m6/dedicated/9001", 9001, 9000, wrapped, replay, "", int(wrapped.get("server_tick", -1)))
	var legacy_cp: Dictionary = Checkpoint.create("checkpoint/m6/dedicated/9001", 9001, 9000, legacy_authority, replay, "", int(legacy_authority.get("server_tick", -1)))
	check(wrapped_cp == legacy_cp, "wrapped checkpoint dictionary equals legacy checkpoint dictionary")
	check(String(wrapped_cp.get("checksum", "")) == String(legacy_cp.get("checksum", "")), "wrapped checkpoint SHA256 equals legacy SHA256")
	check(ok(Checkpoint.validate(wrapped_cp)), "wrapped checkpoint passes unchanged validation")
	# Final disk equivalence: same job through the unchanged worker pipeline
	# lands byte-identical committed checkpoints on disk.
	var root_a := _tmp_root("r3c4r2-disk-a")
	var root_b := _tmp_root("r3c4r2-disk-b")
	var writer_a = _new_writer(root_a)
	var writer_b = _new_writer(root_b)
	check(ok(writer_a.call("submit", wrapped, replay.duplicate(true), "checkpoint/m6/dedicated/9002", 9002, 9001)), "wrapped job submitted")
	check(ok(writer_b.call("submit", legacy_authority, replay.duplicate(true), "checkpoint/m6/dedicated/9002", 9002, 9001)), "legacy job submitted")
	var done_a: Dictionary = writer_a.call("wait_completed")
	var done_b: Dictionary = writer_b.call("wait_completed")
	check(ok(done_a) and ok(done_b), "both worker jobs commit")
	var disk_a: Dictionary = _load_committed(root_a)
	var disk_b: Dictionary = _load_committed(root_b)
	check(ok(disk_a) and ok(disk_b), "both committed checkpoints load from disk")
	var cp_a: Dictionary = disk_a.get("details", {}).get("checkpoint", {})
	var cp_b: Dictionary = disk_b.get("details", {}).get("checkpoint", {})
	check(cp_a == cp_b, "final disk checkpoints are equal dictionaries")
	check(String(cp_a.get("checksum", "")) == String(cp_b.get("checksum", "")), "final disk checksums are equal")
	writer_a.call("stop")
	writer_b.call("stop")
	check(ok(runtime.stop()), "R2 runtime shutdown drains worker")
	runtime.free()

func test_post_submit_mutation_cannot_alter_disk() -> void:
	OS.set_environment(R1_ENV, "1")
	OS.set_environment(R2_ENV, "1")
	var runtime := _setup(false, false)
	if runtime == null: return
	var service = runtime.get("_service")
	var adapter = runtime.get("_recovery_authority")
	var session := String(adapter.get("_logical_session_id"))
	var dto: Dictionary = service.call("export_durable_state")
	var replay: Dictionary = runtime.get("_replay_outbox").call("to_dict")
	var wrapped: Dictionary = Adapter.normalize_durable_state(dto, session)
	var expected: Dictionary = Checkpoint.create("checkpoint/m6/dedicated/9101", 9101, 9100, wrapped, replay, "", int(wrapped.get("server_tick", -1)))
	var root := _tmp_root("r3c4r2-mutation")
	var writer = _new_writer(root)
	check(ok(writer.call("submit", wrapped, replay, "checkpoint/m6/dedicated/9101", 9101, 9100)), "job submitted from caller-owned trees")
	# Hostile caller mutates BOTH nested trees after submission; the worker's
	# pre-wakeup deep copy must isolate the durable bytes.
	_deep_mutate(wrapped)
	_deep_mutate(replay)
	var done: Dictionary = writer.call("wait_completed")
	check(ok(done), "mutated-caller job still commits")
	var loaded: Dictionary = _load_committed(root)
	check(ok(loaded), "committed checkpoint loadable after caller mutation")
	var disk_cp: Dictionary = loaded.get("details", {}).get("checkpoint", {})
	check(disk_cp == expected, "disk checkpoint equals pre-mutation checkpoint")
	check(String(disk_cp.get("checksum", "")) == String(expected.get("checksum", "")), "disk checksum unaffected by post-submit mutation")
	check(ok(Checkpoint.validate(disk_cp)), "disk checkpoint still validates")
	writer.call("stop")
	check(ok(runtime.stop()), "runtime shutdown clean")
	runtime.free()

func test_invalid_dto_rejects_without_disk_mutation() -> void:
	var session := "session/m6/dedicated"
	check(Adapter.normalize_durable_state({}, session).is_empty(), "empty DTO rejects to empty envelope")
	var root := _tmp_root("r3c4r2-invalid")
	var writer = _new_writer(root)
	var before := _dir_fingerprint(root)
	check(not ok(writer.call("submit", {}, {}, "checkpoint/m6/dedicated/9201", 9201, 9200)), "empty DTO/replay submit rejected fail-closed")
	var not_started = preload("res://scripts/persistence/async_checkpoint_writer.gd").new()
	check(not ok(not_started.call("submit", {"a": 1}, {"b": 2}, "checkpoint/x", 1, 0)), "unstarted writer rejects submit")
	var after := _dir_fingerprint(root)
	check(before == after, "disk untouched by rejected submits")
	writer.call("stop")

func test_r2_generation_and_ack_parity_with_r1_pacing() -> void:
	OS.set_environment(R1_ENV, "1")
	OS.set_environment(R2_ENV, "1")
	var runtime := _setup(false, false)
	if runtime == null: return
	check(bool(runtime.get("_r3c4_periodic_frame_pacing_enabled")), "R1 pacing retained under R2")
	var before := int(runtime.get("_checkpoint_generation"))
	_make_due_and_heavy(runtime)
	runtime.call("_maybe_persist_movement_checkpoint")
	check(not runtime.get("_movement_checkpoint_writer").is_busy(), "R2: heavy snapshot frame still defers (R1 pacing exact)")
	check(int(runtime.get("_r3c4_deferred_frames")) >= 1, "R2: deferral accounted")
	runtime.set("_last_movement_snapshot_tick", int(runtime.get("_server_tick")) - 1)
	runtime.call("_maybe_persist_movement_checkpoint")
	check(runtime.get("_movement_checkpoint_writer").is_busy(), "R2: low-work frame submits through unchanged pipeline")
	check(int(runtime.get("_checkpoint_generation")) == before, "submission does not publish generation (M6 parity)")
	runtime.set("_movement_checkpoint_dirty", true)
	runtime.call("_complete_async_movement_checkpoint", true)
	check(int(runtime.get("_checkpoint_generation")) == before + 1, "only completion advances generation under R2")
	var gate = runtime.get("_durable_ack_gate")
	if gate != null:
		var report: Dictionary = gate.call("get_report")
		check(not bool(report.get("pending", true)), "ACK gate not pending after periodic completion")
	drain_and_stop(runtime)

func test_r2_checkpoint_disk_restore() -> void:
	OS.set_environment(R1_ENV, "1")
	OS.set_environment(R2_ENV, "1")
	var runtime := _setup(false, false)
	if runtime == null: return
	var before := int(runtime.get("_checkpoint_generation"))
	_make_due(runtime)
	runtime.call("_maybe_persist_movement_checkpoint")
	check(runtime.get("_movement_checkpoint_writer").is_busy(), "restore: worker busy after due submit")
	runtime.call("_complete_async_movement_checkpoint", true)
	check(not bool(runtime.get("_fatal_persistence_failure")), "restore: no persistence failure")
	check(int(runtime.get("_checkpoint_generation")) == before + 1, "R2 completion advanced generation")
	var repo = Repository.new()
	var root := String(runtime.get("_persistence_root"))
	check(ok(repo.configure(root)), "repository configured on R2 checkpoint dir")
	var loaded: Dictionary = repo.call("load_committed")
	check(ok(loaded), "R2 committed checkpoint loadable from disk")
	var disk_cp: Dictionary = loaded.get("details", {}).get("checkpoint", {})
	check(int(disk_cp.get("generation", 0)) == before + 1, "restored generation matches completion")
	check(ok(Checkpoint.validate(disk_cp)), "restored R2 checkpoint validates with unchanged validator")
	# Durable-state round trip through the unchanged restore path.
	var adapter = runtime.get("_recovery_authority")
	var restore: Dictionary = adapter.call("restore_recovery_state", adapter.call("export_recovery_state"))
	check(ok(restore), "authority restore round-trip succeeds")
	check(ok(runtime.stop()), "shutdown joins worker")
	check(runtime.get("_movement_checkpoint_writer") == null, "worker released on shutdown")
	runtime.free()

func _setup(_cfg_flag_a: bool, _cfg_flag_b: bool) -> Object:
	var runtime := _make_runtime()
	var config := _config(_free_port(), false, false)
	var result: Dictionary = runtime.setup(config)
	if not ok(result):
		failures.append("runtime setup failed: %s" % String(result.get("error_code", "?")))
		runtime.free()
		return null
	get_root().add_child(runtime)
	runtime.set_process(false)
	return runtime

func _make_runtime() -> Object:
	return Runtime.new()

func _config(port: int, r1_flag: bool, r2_flag: bool) -> Dictionary:
	var path := ProjectSettings.globalize_path("res://artifacts/net-smooth1/r3c4r2-envelope-%d" % Time.get_ticks_usec())
	var config: Dictionary = {"host": "127.0.0.1", "port": port, "playable_sandbox": true, "persistence_root": path}
	if r1_flag:
		config["r3c4_periodic_frame_pacing_canary"] = true
	if r2_flag:
		config["r3c4r2_worker_envelope_canary"] = true
	return config

func _free_port() -> int:
	var socket := PacketPeerUDP.new()
	check(socket.bind(0, "127.0.0.1") == OK, "allocate unique port")
	var port := socket.get_local_port()
	socket.close()
	return port

func _make_due(runtime: Object) -> void:
	runtime.set("_movement_checkpoint_dirty", true)
	runtime.set("_movement_commands_since_checkpoint", 2)
	runtime.set("_last_movement_checkpoint_ms", -10000)
	# Low-work frame marker: no snapshot was prepared this process frame.
	runtime.set("_last_movement_snapshot_tick", int(runtime.get("_server_tick")) - 1)

func _make_due_and_heavy(runtime: Object) -> void:
	_make_due(runtime)
	runtime.set("_last_movement_snapshot_tick", int(runtime.get("_server_tick")))

func _new_writer(root: String) -> Object:
	var writer = preload("res://scripts/persistence/async_checkpoint_writer.gd").new()
	var started: Dictionary = writer.call("setup", root)
	if not ok(started):
		failures.append("writer setup failed: %s" % String(started.get("error_code", "?")))
	return writer

func _tmp_root(name: String) -> String:
	var path := ProjectSettings.globalize_path("res://artifacts/net-smooth1/%s-%d" % [name, Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(path)
	return path

func _load_committed(root: String) -> Dictionary:
	var repo = Repository.new()
	var configured: Dictionary = repo.call("configure", root)
	if not ok(configured):
		return {"success": false, "error_code": "TEST_REPO_CONFIGURE_FAILED"}
	return repo.call("load_committed")

func _dir_fingerprint(root: String) -> String:
	var parts: Array[String] = []
	if DirAccess.dir_exists_absolute(root):
		for file in _list_recursive(root):
			parts.append(file + ":" + str(FileAccess.get_file_as_string(file).length()))
	return "|".join(parts)

func _list_recursive(path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		var full := path.path_join(entry)
		if dir.current_is_dir():
			found.append_array(_list_recursive(full))
		else:
			found.append(full)
		entry = dir.get_next()
	found.sort()
	return found

func _deep_mutate(value: Dictionary) -> void:
	# Corrupt every nested dictionary the worker should have detached.
	for key in value.keys():
		var child: Variant = value[key]
		if child is Dictionary:
			_deep_mutate(child)
			child["__caller_mutation__"] = true
		elif child is Array:
			if not child.is_empty():
				if child[0] is Dictionary:
					child[0]["__caller_mutation__"] = true
				else:
					child.append("__caller_mutation__")
	value["__caller_mutation__"] = true

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

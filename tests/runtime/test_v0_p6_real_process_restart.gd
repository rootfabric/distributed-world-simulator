extends SceneTree

## P6 R3 REAL-PROCESS restart gate.
##
## Proof shape (nothing crosses generations except authoritative bytes):
##   1. spawn generation A as a SEPARATE OS process: it routes durable work,
##      persists an authoritative checkpoint through the REAL coordinator and
##      repository, leaves crash windows behind, then IDLES;
##   2. KILL generation A (hard crash, no graceful shutdown, no atexit);
##   3. spawn generation B as a SECOND OS process with a fresh isolated HOME:
##      it recovers canonical sources/replay/projection from the checkpoint
##      bytes only, proves checkpointed OperationIds are exactly-once and the
##      lost intents land exactly once;
##   4. the parent asserts the seed/recover fact JSONs agree and that the
##      persistence root contains only authoritative repository files.
##
## No memory, object, ledger snapshot or state is ever shared between the
## test process and the workers: only --persistence-root and result files.
##
## Scope note: the live M4/P4/P5/M6 production stack restart (real dedicated
## server + gameplay service + outbox) is covered by the accepted M6 process
## recovery runner (RUN_M6_DEDICATED_RECOVERY_TESTS.sh); this gate proves the
## P6 composition boundary itself across real processes.

const READY_TIMEOUT_MS := 60000
const EXIT_TIMEOUT_MS := 15000
const POLL_MS := 40

var assertions := 0
var failures: Array[String] = []
var child_pids: Array[int] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[p6-r3-real-restart][FAIL] %s" % message)


func _init() -> void:
	var executable := OS.get_executable_path()
	var project_root := ProjectSettings.globalize_path("res://")
	var root_path := ProjectSettings.globalize_path(
		"res://artifacts/test-results/p6-r3-real-process-restart-%d" % OS.get_process_id()
	)
	_remove_tree(root_path)
	DirAccess.make_dir_recursive_absolute(root_path)
	var persistence_root := root_path.path_join("persistence")
	var seed_result := root_path.path_join("seed-result.json")
	var recover_result := root_path.path_join("recover-result.json")

	# ================= GENERATION A (seed + hard crash) =================
	var seed_pid := _spawn_worker(executable, project_root, "seed", persistence_root, seed_result, root_path.path_join("worker-seed.log"), root_path.path_join("user-seed"))
	child_pids.append(seed_pid)
	_assert(seed_pid > 0, "seed worker process launched")
	var seed := _wait_state(seed_result, ["PERSISTED", "FAILED"], READY_TIMEOUT_MS)
	_assert(str(seed.get("state", "")) == "PERSISTED", "seed worker reached PERSISTED: %s" % JSON.stringify(seed))
	if str(seed.get("state", "")) != "PERSISTED":
		_finish()
		return
	_assert(int(seed.get("checkpointed_block_count", -1)) == 2, "seed checkpointed block count wrong")
	_assert(str(seed.get("checkpointed_projection_checksum", "")).length() == 64, "seed checkpointed projection checksum missing")
	_assert((seed.get("checkpointed_replay_ids", []) as Array).size() == 4, "seed checkpointed replay id count wrong")

	# persistence root already holds ONLY authoritative bytes
	_assert(_only_authoritative_files(persistence_root), "persistence root contains non-authoritative files before the crash")

	# HARD CRASH: kill generation A while it idles
	var kill_result := OS.kill(seed_pid)
	_assert(kill_result == OK, "seed worker killed (hard crash)")
	if kill_result == OK:
		child_pids.erase(seed_pid)
		OS.delay_msec(200)
	_assert(not OS.is_process_running(seed_pid), "seed worker process is gone")
	_assert(_only_authoritative_files(persistence_root), "persistence root contains non-authoritative files after the crash")

	# ================= GENERATION B (recover from bytes only) =================
	var recover_pid := _spawn_worker(executable, project_root, "recover", persistence_root, recover_result, root_path.path_join("worker-recover.log"), root_path.path_join("user-recover"))
	child_pids.append(recover_pid)
	_assert(recover_pid > 0, "recover worker process launched")
	var recover := _wait_state(recover_result, ["RECOVERED", "FAILED"], READY_TIMEOUT_MS)
	_assert(str(recover.get("state", "")) == "RECOVERED", "recover worker reached RECOVERED: %s" % JSON.stringify(recover))
	_wait_exit(recover_pid, EXIT_TIMEOUT_MS)
	child_pids.erase(recover_pid)
	if str(recover.get("state", "")) != "RECOVERED":
		_finish()
		return

	# --- canonical truth rebuilt exactly from the checkpointed bytes ---
	_assert(int(recover.get("checkpoint_generation", -1)) == 1, "recovered checkpoint generation mismatch")
	_assert(int(recover.get("recovered_block_count", -1)) == int(seed.get("checkpointed_block_count", -2)), "recovered block count diverged from checkpoint")
	_assert(str(recover.get("recovered_projection_checksum", "")) == str(seed.get("checkpointed_projection_checksum", "")), "recovered projection checksum diverged from checkpoint")
	var recovered_blocks: Dictionary = Dictionary(recover.get("recovered_blocks", {}))
	var checkpointed_blocks: Dictionary = Dictionary(seed.get("checkpointed_blocks", {}))
	_assert(JSON.stringify(_canonical(recovered_blocks)) == JSON.stringify(_canonical(checkpointed_blocks)), "recovered blocks diverged from checkpointed blocks")
	var replay_ids: Array = recover.get("recovered_replay_ids", [])
	for expected_id in (seed.get("checkpointed_replay_ids", []) as Array):
		_assert(replay_ids.has(expected_id), "recovered replay owner lost %s" % String(expected_id))
	_assert(not replay_ids.has("operation/p6-pr-wa") and not replay_ids.has("operation/p6-pr-wb"), "uncheckpointed work leaked into durable replay truth")
	var recovered_containers: Dictionary = Dictionary(recover.get("recovered_containers", {}))
	_assert(recovered_containers.has("crate-pr"), "recovered container lost")
	_assert((recovered_containers.get("crate-pr", []) as Array).has("pickaxe"), "recovered container item lost")
	_assert(not bool(recover.get("pending_survived", true)), "PENDING reservation survived as durable truth")

	# --- exactly-once across the process boundary ---
	_assert(str(recover.get("checkpointed_replay_result", "")) == "EXECUTED", "checkpointed replay route failed")
	_assert(str(recover.get("checkpointed_replay_error_code", "")) == "ALREADY_COMMITTED_AT_CANONICAL_OWNER", "checkpointed replay not rejected by the canonical owner")
	_assert(int(recover.get("blocks_after_checkpointed_replay", -1)) == int(seed.get("checkpointed_block_count", -2)), "checkpointed replay duplicated a canonical mutation")
	_assert(str(recover.get("window_a_result", "")) == "EXECUTED", "lost window A intent did not execute after recovery")
	_assert(str(recover.get("window_b_result", "")) == "EXECUTED", "lost window B intent did not re-land after recovery")
	_assert(str(recover.get("window_a_retry_result", "")) == "ALREADY_APPLIED", "recovered intent retry not deduplicated")
	_assert(int(recover.get("final_block_count", -1)) == 4, "final block count wrong: %s" % str(recover.get("final_block_count", -1)))
	var final_blocks: Dictionary = Dictionary(recover.get("final_blocks", {}))
	_assert(str(final_blocks.get("5,0,5", "")) == "glass", "window A block missing or wrong")
	_assert(str(final_blocks.get("6,0,6", "")) == "brick", "window B block missing or wrong")

	# clean shutdown footprint: nothing else appeared in the persistence root
	_assert(_only_authoritative_files(persistence_root), "persistence root contains non-authoritative files at the end")

	_finish()


func _spawn_worker(executable: String, project_root: String, phase: String, persistence_root: String, result_file: String, log_file: String, user_root: String) -> int:
	var arguments: Array[String] = [
		"--headless", "--quiet", "--path", project_root, "--log-file", log_file,
		"--script", "res://tests/runtime/support/p6_r3_process_worker.gd", "--",
		"--phase=%s" % phase,
		"--persistence-root=%s" % persistence_root,
		"--result-file=%s" % result_file,
	]
	var environment_names: Array[String] = [
		"HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA"
	]
	var captured: Dictionary = {}
	for name in environment_names:
		captured[name] = OS.get_environment(name)
	var data_path := user_root.path_join("data")
	var config_path := user_root.path_join("config")
	var cache_path := user_root.path_join("cache")
	for path in [user_root, data_path, config_path, cache_path]:
		DirAccess.make_dir_recursive_absolute(path)
	OS.set_environment("HOME", user_root)
	OS.set_environment("XDG_DATA_HOME", data_path)
	OS.set_environment("XDG_CONFIG_HOME", config_path)
	OS.set_environment("XDG_CACHE_HOME", cache_path)
	OS.set_environment("APPDATA", data_path)
	OS.set_environment("LOCALAPPDATA", data_path)
	var pid := OS.create_process(executable, arguments, false)
	for name in environment_names:
		OS.set_environment(name, String(captured[name]))
	return pid


func _wait_state(path: String, states: Array[String], timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	var last: Dictionary = {}
	while Time.get_ticks_msec() - started <= timeout_ms:
		last = _read_json(path)
		if String(last.get("state", "")) in states:
			return last
		OS.delay_msec(POLL_MS)
	return last


func _wait_exit(pid: int, timeout_ms: int) -> void:
	var started := Time.get_ticks_msec()
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() - started <= timeout_ms:
		OS.delay_msec(POLL_MS)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return Dictionary(parsed) if parsed is Dictionary else {}


func _only_authoritative_files(directory: String) -> bool:
	var dir := DirAccess.open(directory)
	if dir == null:
		return false
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and not entry.begins_with("authoritative-checkpoint"):
			dir.list_dir_end()
			return false
		entry = dir.get_next()
	dir.list_dir_end()
	return true


func _canonical(value):
	if value is Dictionary:
		var sorted_keys: Array = (value as Dictionary).keys()
		sorted_keys.sort()
		var out := {}
		for key in sorted_keys:
			out[key] = _canonical((value as Dictionary)[key])
		return out
	if value is Array:
		var arr_out: Array = []
		for item in (value as Array):
			arr_out.append(_canonical(item))
		return arr_out
	return value


func _finish() -> void:
	for pid in child_pids:
		if OS.is_process_running(pid):
			OS.kill(pid)
	if failures.is_empty():
		print("[p6-r3-real-restart] all %d assertions passed (two OS processes, hard kill, bytes-only recovery)" % assertions)
		print("[p6-r3-real-restart][stage] REAL_PROCESS_RESTART_DELEGATED_RECOVERY_PASS")
		print("[p6-r3-real-restart][scope] live M4/P4/P5/M6 production-stack restart remains covered by the accepted M6 process recovery runner")
		quit(0)
	else:
		print("[p6-r3-real-restart] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
		quit(1)


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := path.path_join(entry)
		if dir.current_is_dir():
			_remove_tree(full)
		else:
			DirAccess.remove_absolute(full)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)

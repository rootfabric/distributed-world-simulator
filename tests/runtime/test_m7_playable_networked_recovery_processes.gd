extends SceneTree

const POLL_MS := 50
const READY_TIMEOUT_MS := 45000
const CLIENT_TIMEOUT_MS := 60000
const EXIT_TIMEOUT_MS := 15000

var assertions := 0
var failures: Array[String] = []
var child_pids: Array[int] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var port := _find_port()
	_assert(port > 0, "M7 recovery UDP port allocated")
	if port <= 0:
		_finish()
		return
	var root_path := ProjectSettings.globalize_path("res://artifacts/test-results/m7-recovery-%d" % OS.get_process_id())
	_remove_tree(root_path)
	DirAccess.make_dir_recursive_absolute(root_path)
	var persistence_root := root_path.path_join("persistence")
	var server1_file := root_path.path_join("server-1.json")
	var server2_file := root_path.path_join("server-2.json")
	var seed_file := root_path.path_join("seed.json")
	var recover_file := root_path.path_join("recover.json")
	var executable := OS.get_executable_path()
	var project_root := ProjectSettings.globalize_path("res://")

	var server1 := _spawn_server(executable, project_root, port, persistence_root, server1_file, root_path.path_join("server-1.log"), root_path.path_join("user-server-1"))
	child_pids.append(server1)
	_assert(server1 > 0, "M7 persistent server generation one launched")
	var server1_ready := _wait_state(server1_file, ["READY", "FAILED"], READY_TIMEOUT_MS)
	_assert(String(server1_ready.get("state", "")) == "READY", "M7 persistent server generation one ready")
	if String(server1_ready.get("state", "")) != "READY":
		_finish()
		return
	_assert(bool(server1_ready.get("playable_sandbox", false)), "M7 generation one uses playable sandbox")
	_assert(bool(server1_ready.get("persistence", {}).get("enabled", false)), "M7 generation one persistence enabled")

	var seed_pid := _spawn_client(executable, project_root, port, "seed", seed_file, "", root_path.path_join("seed.log"), root_path.path_join("user-seed"))
	child_pids.append(seed_pid)
	_assert(seed_pid > 0, "M7 seed client launched")
	var seed := _wait_state(seed_file, ["SEED_COMPLETE", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(bool(seed.get("passed", false)), "M7 seed mutation completed: %s" % seed)
	_wait_exit(seed_pid, EXIT_TIMEOUT_MS)
	child_pids.erase(seed_pid)
	var seed_checksum := String(seed.get("details", {}).get("item_graph_checksum", ""))
	_assert(seed_checksum.length() == 64, "M7 seed Item Graph checksum captured")
	_assert(int(seed.get("details", {}).get("hotbar_size", 0)) == 10, "M7 seed hotbar contains ten slots")
	_assert(String(seed.get("details", {}).get("slot_9_item_id", "")) == "item/shared/beacon/1", "M7 seed slot nine assignment captured")
	var persisted := _wait_report(
		server1_file,
		func(report: Dictionary) -> bool:
			return (
				int(report.get("connected_peer_count", -1)) == 0
				and String(report.get("item_graph_snapshot", {}).get("checksum", "")) == seed_checksum
				and int(report.get("persistence", {}).get("checkpoint_generation", 0)) >= 5
			),
		CLIENT_TIMEOUT_MS
	)
	_assert(String(persisted.get("item_graph_snapshot", {}).get("checksum", "")) == seed_checksum, "M7 durable checkpoint contains seed Item Graph")
	_assert(_hotbar(persisted.get("item_graph_snapshot", {}), "a").size() == 10, "server report persists ten-slot hotbar")
	_assert(int(persisted.get("persistence", {}).get("failures", 0)) == 0, "M7 generation one persistence has no failures")

	if OS.is_process_running(server1):
		OS.kill(server1)
	OS.delay_msec(300)
	_assert(true, "M7 generation one termination signal sent to simulate restart")
	child_pids.erase(server1)
	OS.delay_msec(300)

	var server2 := _spawn_server(executable, project_root, port, persistence_root, server2_file, root_path.path_join("server-2.log"), root_path.path_join("user-server-2"))
	child_pids.append(server2)
	_assert(server2 > 0, "M7 recovered server generation two launched")
	var recovered := _wait_state(server2_file, ["READY", "FAILED"], READY_TIMEOUT_MS)
	_assert(String(recovered.get("state", "")) == "READY", "M7 recovered server generation two ready: %s" % recovered)
	if String(recovered.get("state", "")) != "READY":
		_finish()
		return
	_assert(bool(recovered.get("persistence", {}).get("recovered", false)), "M7 server reports durable recovery")
	_assert(not bool(recovered.get("persistence", {}).get("fatal_failure", true)), "M7 recovery avoids persistence fail-stop")
	_assert(String(recovered.get("item_graph_snapshot", {}).get("checksum", "")) == seed_checksum, "M7 recovered Item Graph checksum is byte-stable")
	_assert(bool(recovered.get("item_graph_snapshot", {}).get("playable_sandbox", false)), "M7 recovered snapshot preserves sandbox flag before validation")
	_assert(_hotbar(recovered.get("item_graph_snapshot", {}), "a").size() == 10, "M7 recovery validates ten-slot hotbar")
	_assert(String(_hotbar(recovered.get("item_graph_snapshot", {}), "a")[9]) == "item/shared/beacon/1", "M7 recovered slot nine assignment")
	_assert(String(recovered.get("last_error_code", "")).is_empty(), "M7 recovery has no INVALID_DURABLE_HOTBAR_SIZE error")

	var recover_pid := _spawn_client(executable, project_root, port, "recover", recover_file, seed_checksum, root_path.path_join("recover.log"), root_path.path_join("user-recover"))
	child_pids.append(recover_pid)
	_assert(recover_pid > 0, "M7 reconnect client launched")
	var continuation := _wait_state(recover_file, ["RECOVER_COMPLETE", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(bool(continuation.get("passed", false)), "M7 reconnect and continuation completed: %s" % continuation)
	_assert(int(continuation.get("details", {}).get("ownership_epoch", 0)) == 2, "M7 reconnect advances ownership epoch")
	_assert(int(continuation.get("details", {}).get("hotbar_size", 0)) == 10, "M7 reconnect observes ten-slot hotbar")
	_assert(String(continuation.get("details", {}).get("initial_item_graph_checksum", "")) == seed_checksum, "M7 reconnect starts from recovered checksum")
	_wait_exit(recover_pid, EXIT_TIMEOUT_MS)
	child_pids.erase(recover_pid)
	var final_report := _wait_report(
		server2_file,
		func(report: Dictionary) -> bool:
			return int(report.get("connected_peer_count", -1)) == 0 and int(report.get("leaves", 0)) >= 1,
		CLIENT_TIMEOUT_MS
	)
	_assert(String(final_report.get("item_graph_snapshot", {}).get("checksum", "")) == String(continuation.get("details", {}).get("final_item_graph_checksum", "")), "M7 server and reconnect client converge after continued mutation")
	_assert(int(final_report.get("persistence", {}).get("failures", 0)) == 0, "M7 recovered persistence remains healthy")
	_assert(not bool(final_report.get("persistence", {}).get("fatal_failure", true)), "M7 recovered server remains outside fail-stop")

	if OS.is_process_running(server2):
		OS.kill(server2)
	OS.delay_msec(300)
	_assert(true, "M7 generation two termination signal sent")
	child_pids.erase(server2)
	for log_name in ["server-1.log", "server-2.log", "seed.log", "recover.log"]:
		_assert_clean(root_path.path_join(log_name), log_name)
	_finish()


func _spawn_server(executable: String, project_root: String, port: int, persistence_root: String, result_file: String, log_file: String, user_root: String) -> int:
	return _spawn(executable, [
		"--headless", "--quiet", "--path", project_root,
		"--log-file", log_file, "--",
		"--role=dedicated-server", "--network-playground", "--world=playground",
		"--node-id=m7-recovery-server", "--server-address=127.0.0.1",
		"--server-port=%d" % port,
		"--m6-persistence-root=%s" % persistence_root,
		"--m7-result-file=%s" % result_file,
		"--shutdown-after-ms=180000",
	], user_root)


func _spawn_client(executable: String, project_root: String, port: int, mode: String, result_file: String, expected_checksum: String, log_file: String, user_root: String) -> int:
	var args: Array[String] = [
		"--headless", "--quiet", "--path", project_root,
		"--log-file", log_file,
		"--script", "res://tools/runtime/m7_playable_recovery_client.gd", "--",
		"--host=127.0.0.1", "--port=%d" % port,
		"--mode=%s" % mode, "--result-file=%s" % result_file,
	]
	if not expected_checksum.is_empty():
		args.append("--expected-item-checksum=%s" % expected_checksum)
	return _spawn(executable, args, user_root)


func _spawn(executable: String, args: Array[String], user_root: String) -> int:
	var names: Array[String] = ["HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA", "BREAKPOINT_RUNTIME_DISABLED", "GODOT_SILENCE_ROOT_WARNING"]
	var old: Dictionary = {}
	for name in names:
		old[name] = {"set": OS.has_environment(name), "value": OS.get_environment(name)}
	for path in [user_root, user_root.path_join("data"), user_root.path_join("config"), user_root.path_join("cache")]:
		DirAccess.make_dir_recursive_absolute(path)
	OS.set_environment("HOME", user_root)
	OS.set_environment("XDG_DATA_HOME", user_root.path_join("data"))
	OS.set_environment("XDG_CONFIG_HOME", user_root.path_join("config"))
	OS.set_environment("XDG_CACHE_HOME", user_root.path_join("cache"))
	OS.set_environment("APPDATA", user_root.path_join("data"))
	OS.set_environment("LOCALAPPDATA", user_root.path_join("data"))
	OS.set_environment("BREAKPOINT_RUNTIME_DISABLED", "1")
	OS.set_environment("GODOT_SILENCE_ROOT_WARNING", "1")
	var pid := OS.create_process(executable, args, false)
	for name in names:
		if bool(old[name]["set"]):
			OS.set_environment(name, String(old[name]["value"]))
		else:
			OS.unset_environment(name)
	return pid


func _wait_state(path: String, states: Array[String], timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	var report: Dictionary = {}
	while Time.get_ticks_msec() - started < timeout_ms:
		report = _read(path)
		if String(report.get("state", "")) in states:
			return report
		OS.delay_msec(POLL_MS)
	return report


func _wait_report(path: String, predicate: Callable, timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	var report: Dictionary = {}
	while Time.get_ticks_msec() - started < timeout_ms:
		report = _read(path)
		if bool(predicate.call(report)):
			return report
		OS.delay_msec(POLL_MS)
	return report


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return Dictionary(parsed) if parsed is Dictionary else {}


func _wait_exit(pid: int, timeout_ms: int) -> void:
	var started := Time.get_ticks_msec()
	while OS.is_process_running(pid) and Time.get_ticks_msec() - started < timeout_ms:
		OS.delay_msec(POLL_MS)


func _hotbar(snapshot: Dictionary, player_id: String) -> Array:
	return Array(Dictionary(snapshot.get("inventories", {})).get(player_id, {}).get("hotbar", []))


func _assert_clean(path: String, label: String) -> void:
	var text := FileAccess.get_file_as_string(path).to_lower() if FileAccess.file_exists(path) else ""
	_assert(not text.contains("script error") and not text.contains("invalid_durable_hotbar_size") and not text.contains("invalid_gameplay_item_graph_state"), "%s contains no recovery/runtime error" % label)


func _find_port() -> int:
	for candidate in range(46600 + OS.get_process_id() % 300, 48600):
		var udp := PacketPeerUDP.new()
		if udp.bind(candidate, "127.0.0.1") == OK:
			udp.close()
			return candidate
	return 0


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		var child := path.path_join(entry)
		if directory.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)


func _finish() -> void:
	for pid in child_pids:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
	print("M7 playable recovery processes: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

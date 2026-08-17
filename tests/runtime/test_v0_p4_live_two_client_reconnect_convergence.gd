extends SceneTree

const POLL_MS := 50
const READY_TIMEOUT_MS := 60000
const CLIENT_TIMEOUT_MS := 120000
const EXIT_TIMEOUT_MS := 15000

var assertions := 0
var failures: Array[String] = []
var child_pids: Array[int] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var port := _find_port()
	_assert(port > 0, "P4.6 UDP port allocated")
	if port <= 0:
		_finish()
		return
	var root_path := ProjectSettings.globalize_path(
		"res://artifacts/test-results/v0-p4-live-reconnect-%d" % OS.get_process_id()
	)
	_remove_tree(root_path)
	DirAccess.make_dir_recursive_absolute(root_path)
	var control_file := root_path.path_join("control.json")
	var server_log := root_path.path_join("server.log")
	var actor_file := root_path.path_join("actor.json")
	var before_file := root_path.path_join("b-before.json")
	var after_file := root_path.path_join("b-after.json")
	var actor_log := root_path.path_join("actor.log")
	var before_log := root_path.path_join("b-before.log")
	var after_log := root_path.path_join("b-after.log")
	var executable := OS.get_executable_path()
	var project_root := ProjectSettings.globalize_path("res://")
	_write_control(control_file, "BOOT")

	var server_pid := _spawn_server(executable, project_root, port, server_log, root_path.path_join("user-server"))
	child_pids.append(server_pid)
	_assert(server_pid > 0, "P4.6 dedicated server launched")
	if server_pid <= 0:
		_finish()
		return
	_assert(_wait_log_marker(server_pid, server_log, "\"event\":\"SERVER_READY\"", READY_TIMEOUT_MS), "P4.6 server reports SERVER_READY")
	_assert(_wait_log_marker(server_pid, server_log, "\"event\":\"earth_runtime_ready\"", READY_TIMEOUT_MS), "P4.6 Earth runtime ready")
	_assert(_wait_log_marker(server_pid, server_log, "\"runtime_role\":\"dedicated-server\"", READY_TIMEOUT_MS), "P4.6 dedicated-server role ready")

	var actor_pid := _spawn_client(executable, project_root, port, "actor", actor_file, control_file, {}, actor_log, root_path.path_join("user-actor"))
	child_pids.append(actor_pid)
	_assert(actor_pid > 0, "P4.6 actor A launched")
	var actor_ready := _wait_state(actor_file, ["ACTOR_READY", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(_passed_state(actor_ready, "ACTOR_READY"), "P4.6 actor A ready")
	if not _passed_state(actor_ready, "ACTOR_READY"):
		_finish()
		return

	var before_pid := _spawn_client(executable, project_root, port, "before", before_file, control_file, {}, before_log, root_path.path_join("user-b-before"))
	child_pids.append(before_pid)
	_assert(before_pid > 0, "P4.6 peer B launched")
	var b_ready := _wait_state(before_file, ["B_READY", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(_passed_state(b_ready, "B_READY"), "P4.6 B ready concurrently with A")
	if not _passed_state(b_ready, "B_READY"):
		_finish()
		return

	for stage_index in range(3):
		_write_control(control_file, "STAGE_%d" % stage_index)
		var actor_stage := _wait_state(actor_file, ["ACTOR_STAGE_%d" % stage_index, "FAILED"], CLIENT_TIMEOUT_MS)
		var b_stage := _wait_state(before_file, ["B_STAGE_%d" % stage_index, "FAILED"], CLIENT_TIMEOUT_MS)
		_assert(_passed_state(actor_stage, "ACTOR_STAGE_%d" % stage_index), "A completes stage-%d live mine/build" % stage_index)
		_assert(_passed_state(b_stage, "B_STAGE_%d" % stage_index), "B observes stage-%d live mine/build" % stage_index)
		if not _passed_state(actor_stage, "ACTOR_STAGE_%d" % stage_index) or not _passed_state(b_stage, "B_STAGE_%d" % stage_index):
			_finish()
			return
		_assert(_state_matches(actor_stage.get("details", {}), b_stage.get("details", {})), "A/B converge after stage-%d publication" % stage_index)
		var expected_remaining: int = int([6, 2, 0][stage_index])
		_assert(int(actor_stage.get("details", {}).get("remaining_units", -1)) == expected_remaining, "stage-%d canonical resource remaining is exact" % stage_index)
		_assert(int(actor_stage.get("details", {}).get("ore_quantity_a", -1)) == 0, "stage-%d leaves no unconsumed A ore" % stage_index)
		_assert(int(actor_stage.get("details", {}).get("completed_stage_count", -1)) == stage_index + 1, "stage-%d Construction progress exact" % stage_index)

	_write_control(control_file, "LEAVE_B")
	var before_done := _wait_state(before_file, ["BEFORE_COMPLETE", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(_passed_state(before_done, "BEFORE_COMPLETE"), "B captures final canonical state and leaves")
	_wait_exit(before_pid, EXIT_TIMEOUT_MS)
	_assert(not OS.is_process_running(before_pid), "B initial process exits")
	child_pids.erase(before_pid)
	var actor_left := _wait_state(actor_file, ["ACTOR_B_LEFT", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(_passed_state(actor_left, "ACTOR_B_LEFT"), "A observes B disconnected without state mutation")
	if not _passed_state(before_done, "BEFORE_COMPLETE") or not _passed_state(actor_left, "ACTOR_B_LEFT"):
		_finish()
		return
	_assert(_state_matches(before_done.get("details", {}), actor_left.get("details", {})), "A and departing B agree on final canonical state")

	var final: Dictionary = Dictionary(before_done.get("details", {}))
	var after_pid := _spawn_client(
		executable, project_root, port, "after", after_file, control_file,
		{
			"expected-item-checksum": String(final.get("item_graph_checksum", "")),
			"expected-resource-checksum": String(final.get("resource_checksum", "")),
			"expected-resource-generation": str(int(final.get("resource_generation", -1))),
			"expected-construction-checksum": String(final.get("construction_checksum", "")),
			"expected-construction-generation": str(int(final.get("construction_generation", -1))),
			"previous-session-id": String(final.get("transport_session_id", "")),
			"previous-player-entity-id": String(final.get("player_entity_id", "")),
			"previous-ownership-epoch": str(int(final.get("ownership_epoch", 0))),
		},
		after_log, root_path.path_join("user-b-after")
	)
	child_pids.append(after_pid)
	_assert(after_pid > 0, "P4.6 reconnect B launched")
	var reconnect_ready := _wait_state(after_file, ["RECONNECT_READY", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(_passed_state(reconnect_ready, "RECONNECT_READY"), "reconnected B reconstructs final Resource/Item/Construction state")
	var actor_reconnect := _wait_state(actor_file, ["ACTOR_RECONNECT_SEEN", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(_passed_state(actor_reconnect, "ACTOR_RECONNECT_SEEN"), "A remains live through B reconnect")
	if not _passed_state(reconnect_ready, "RECONNECT_READY") or not _passed_state(actor_reconnect, "ACTOR_RECONNECT_SEEN"):
		_finish()
		return
	_assert(_state_matches(reconnect_ready.get("details", {}), actor_reconnect.get("details", {})), "A/reconnected-B final canonical checksums converge")
	_assert(String(reconnect_ready.get("details", {}).get("transport_session_id", "")) != String(final.get("transport_session_id", "")), "B reconnect transport session changes")
	_assert(String(reconnect_ready.get("details", {}).get("player_entity_id", "")) == String(final.get("player_entity_id", "")), "B reconnect canonical entity preserved")
	_assert(int(reconnect_ready.get("details", {}).get("ownership_epoch", 0)) > int(final.get("ownership_epoch", 0)), "B reconnect ownership epoch advances")

	_write_control(control_file, "FINISH")
	var reconnect_done := _wait_state(after_file, ["RECONNECT_COMPLETE", "FAILED"], CLIENT_TIMEOUT_MS)
	var actor_done := _wait_state(actor_file, ["ACTOR_COMPLETE", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(_passed_state(reconnect_done, "RECONNECT_COMPLETE"), "reconnected B exits cleanly")
	_assert(_passed_state(actor_done, "ACTOR_COMPLETE"), "A exits cleanly")
	_wait_exit(after_pid, EXIT_TIMEOUT_MS)
	_wait_exit(actor_pid, EXIT_TIMEOUT_MS)
	_assert(not OS.is_process_running(after_pid) and not OS.is_process_running(actor_pid), "both P4.6 client processes exit")
	child_pids.erase(after_pid)
	child_pids.erase(actor_pid)
	if server_pid > 0 and OS.is_process_running(server_pid):
		OS.kill(server_pid)
		OS.delay_msec(300)
	child_pids.erase(server_pid)
	_assert(true, "P4.6 dedicated server termination signal sent")
	for entry in [
		{"path": server_log, "label": "server"},
		{"path": actor_log, "label": "actor-a"},
		{"path": before_log, "label": "client-b-before"},
		{"path": after_log, "label": "client-b-after"},
	]:
		_assert_clean(String(entry["path"]), String(entry["label"]))
	_finish()


func _state_matches(a_value, b_value) -> bool:
	if not a_value is Dictionary or not b_value is Dictionary:
		return false
	var a: Dictionary = a_value
	var b: Dictionary = b_value
	for key in [
		"resource_checksum", "resource_generation", "remaining_units",
		"item_graph_checksum", "item_graph_revision", "ore_quantity_a",
		"construction_checksum", "construction_generation",
		"completed_stage_count", "construction_complete", "construct_checksum",
	]:
		if a.get(key) != b.get(key):
			return false
	return true


func _spawn_server(executable: String, project_root: String, port: int, log_file: String, user_root: String) -> int:
	return _spawn(executable, [
		"--headless", "--path", project_root, "--log-file", log_file, "--",
		"--network-mvp", "--role=dedicated-server", "--world=earth",
		"--server-address=127.0.0.1", "--server-port=%d" % port,
		"--network-debug", "--network-debug-stay-open", "--shutdown-after-ms=240000",
	], user_root)


func _spawn_client(executable: String, project_root: String, port: int, mode: String, result_file: String, control_file: String, extra: Dictionary, log_file: String, user_root: String) -> int:
	var args: Array[String] = [
		"--headless", "--path", project_root, "--log-file", log_file,
		"--script", "res://tools/runtime/v0_p4_live_reconnect_client.gd", "--",
		"--host=127.0.0.1", "--port=%d" % port, "--mode=%s" % mode,
		"--result-file=%s" % result_file, "--control-file=%s" % control_file,
	]
	var keys := extra.keys()
	keys.sort()
	for key_value in keys:
		args.append("--%s=%s" % [String(key_value), String(extra[key_value])])
	return _spawn(executable, args, user_root)


func _spawn(executable: String, args: Array[String], user_root: String) -> int:
	var names: Array[String] = [
		"HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME",
		"APPDATA", "LOCALAPPDATA", "BREAKPOINT_RUNTIME_DISABLED", "GODOT_SILENCE_ROOT_WARNING",
	]
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
		if bool(old[name]["set"]): OS.set_environment(name, String(old[name]["value"]))
		else: OS.unset_environment(name)
	return pid


func _wait_state(path: String, states: Array[String], timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	var report: Dictionary = {}
	while Time.get_ticks_msec() - started < timeout_ms:
		report = _read(path)
		if String(report.get("state", "")) in states: return report
		OS.delay_msec(POLL_MS)
	return report


func _wait_log_marker(pid: int, path: String, marker: String, timeout_ms: int) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < timeout_ms:
		if pid > 0 and not OS.is_process_running(pid): return false
		if FileAccess.file_exists(path) and FileAccess.get_file_as_string(path).contains(marker): return true
		OS.delay_msec(POLL_MS)
	return false


func _wait_exit(pid: int, timeout_ms: int) -> void:
	var started := Time.get_ticks_msec()
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() - started < timeout_ms:
		OS.delay_msec(POLL_MS)


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return Dictionary(parsed) if parsed is Dictionary else {}


func _write_control(path: String, phase: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({"phase": phase}, "  "))
	file.close()


func _assert_clean(path: String, label: String) -> void:
	var content := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var clean := true
	for marker in ["SCRIPT ERROR:", "Parse Error:", "Compile Error:", "Failed to load script", "V0_P4_LIVE_RECONNECT_SERVER_DISCONNECTED"]:
		if content.contains(marker): clean = false
	_assert(clean, "%s log contains no P4.6/parser/runtime failure" % label)


func _passed_state(report: Dictionary, state: String) -> bool:
	return String(report.get("state", "")) == state and bool(report.get("passed", false))


func _find_port() -> int:
	for candidate in range(48920, 49020):
		var udp := PacketPeerUDP.new()
		var error := udp.bind(candidate, "127.0.0.1")
		udp.close()
		if error == OK: return candidate
	return 0


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path): return
	var dir := DirAccess.open(path)
	if dir == null: return
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty(): break
		if name == "." or name == "..": continue
		var child := path.path_join(name)
		if dir.current_is_dir(): _remove_tree(child)
		else: DirAccess.remove_absolute(child)
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition: print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)


func _finish() -> void:
	for pid in child_pids:
		if pid > 0 and OS.is_process_running(pid): OS.kill(pid)
	if failures.is_empty():
		print("V0-P4 live two-client reconnect convergence: %d assertions, 0 failures" % assertions)
		quit(0)
		return
	for failure in failures: push_error(failure)
	print("V0-P4 live two-client reconnect convergence: %d assertions, %d failures" % [assertions, failures.size()])
	quit(1)

extends SceneTree

const POLL_MS := 50
const READY_TIMEOUT_MS := 60000
const CLIENT_TIMEOUT_MS := 90000
const EXIT_TIMEOUT_MS := 15000
const BEACON_ID := "item/shared/beacon/1"
const CRATE_CONTAINER_ID := "container/shared/crate/1"

var assertions := 0
var failures: Array[String] = []
var child_pids: Array[int] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var port := _find_port()
	_assert(port > 0, "V0-P1 reconnect UDP port allocated")
	if port <= 0:
		_finish()
		return

	var root_path := ProjectSettings.globalize_path("res://artifacts/test-results/v0-p1-live-reconnect-%d" % OS.get_process_id())
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

	var server_pid := _spawn_server(
		executable,
		project_root,
		port,
		server_log,
		root_path.path_join("user-server")
	)
	child_pids.append(server_pid)
	_assert(server_pid > 0, "V0-P1 reconnect dedicated server launched")
	var server_ready := _wait_log_marker(server_pid, server_log, "\"event\":\"SERVER_READY\"", READY_TIMEOUT_MS)
	_assert(server_ready, "V0-P1 reconnect dedicated server reports SERVER_READY")
	if not server_ready:
		_finish()
		return

	var actor_pid := _spawn_client(
		executable,
		project_root,
		port,
		"actor",
		actor_file,
		control_file,
		{},
		actor_log,
		root_path.path_join("user-actor")
	)
	child_pids.append(actor_pid)
	_assert(actor_pid > 0, "V0-P1 reconnect actor A launched")
	var actor_ready := _wait_state(actor_file, ["ACTOR_READY", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(String(actor_ready.get("state", "")) == "ACTOR_READY" and bool(actor_ready.get("passed", false)), "actor A reaches ready state")
	if String(actor_ready.get("state", "")) != "ACTOR_READY" or not bool(actor_ready.get("passed", false)):
		_finish()
		return

	var before_pid := _spawn_client(
		executable,
		project_root,
		port,
		"before",
		before_file,
		control_file,
		{},
		before_log,
		root_path.path_join("user-b-before")
	)
	child_pids.append(before_pid)
	_assert(before_pid > 0, "V0-P1 initial B session launched")
	var before := _wait_state(before_file, ["BEFORE_COMPLETE", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(String(before.get("state", "")) == "BEFORE_COMPLETE" and bool(before.get("passed", false)), "initial B session captures pre-mutation state and leaves cleanly")
	_wait_exit(before_pid, EXIT_TIMEOUT_MS)
	_assert(not OS.is_process_running(before_pid), "initial B process exited before absent-peer mutation")
	child_pids.erase(before_pid)
	if String(before.get("state", "")) != "BEFORE_COMPLETE" or not bool(before.get("passed", false)):
		_finish()
		return

	var before_details: Dictionary = Dictionary(before.get("details", {}))
	var before_session := String(before_details.get("transport_session_id", ""))
	var before_entity := String(before_details.get("player_entity_id", ""))
	var before_epoch := int(before_details.get("ownership_epoch", 0))
	_assert(not before_session.is_empty(), "initial B transport session captured")
	_assert(not before_entity.is_empty(), "initial B canonical player entity captured")
	_assert(before_epoch >= 1, "initial B ownership epoch captured")

	_write_control(control_file, "MUTATE")
	var actor_mutated := _wait_state(actor_file, ["ACTOR_MUTATED", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(String(actor_mutated.get("state", "")) == "ACTOR_MUTATED" and bool(actor_mutated.get("passed", false)), "A mutates canonical shared state only after B is absent")
	if String(actor_mutated.get("state", "")) != "ACTOR_MUTATED" or not bool(actor_mutated.get("passed", false)):
		_finish()
		return

	var actor_details: Dictionary = Dictionary(actor_mutated.get("details", {}))
	var canonical_checksum := String(actor_details.get("item_graph_checksum", ""))
	_assert(canonical_checksum.length() == 64, "A post-mutation canonical Item Graph checksum captured")
	_assert(String(actor_details.get("beacon_location", "")) == "CONTAINER", "A moves shared beacon out of WORLD while B absent")
	_assert(String(actor_details.get("beacon_container_id", "")) == CRATE_CONTAINER_ID, "A absent-peer mutation targets canonical external crate")
	_assert(int(actor_details.get("beacon_slot_index", -1)) == 0, "A absent-peer mutation preserves canonical target slot")
	_assert(bool(actor_details.get("crate_contains_beacon", false)), "canonical crate membership contains shared beacon")
	_assert(not bool(Dictionary(actor_details.get("b_player", {})).get("connected", true)), "A mutation evidence records B disconnected")

	var after_pid := _spawn_client(
		executable,
		project_root,
		port,
		"after",
		after_file,
		control_file,
		{
			"expected-item-checksum": canonical_checksum,
			"previous-session-id": before_session,
			"previous-player-entity-id": before_entity,
			"previous-ownership-epoch": str(before_epoch),
		},
		after_log,
		root_path.path_join("user-b-after")
	)
	child_pids.append(after_pid)
	_assert(after_pid > 0, "V0-P1 reconnect B session launched")
	var after_ready := _wait_state(after_file, ["RECONNECT_READY", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(String(after_ready.get("state", "")) == "RECONNECT_READY" and bool(after_ready.get("passed", false)), "reconnected B reaches converged ready state")
	if String(after_ready.get("state", "")) != "RECONNECT_READY" or not bool(after_ready.get("passed", false)):
		_finish()
		return
	var after_details: Dictionary = Dictionary(after_ready.get("details", {}))
	_assert(String(after_details.get("item_graph_checksum", "")) == canonical_checksum, "reconnected B checksum equals A current canonical Item Graph")
	_assert(String(after_details.get("transport_session_id", "")) != before_session, "reconnected B has a new transport session")
	_assert(String(after_details.get("player_entity_id", "")) == before_entity, "reconnected B preserves player entity identity")
	_assert(int(after_details.get("ownership_epoch", 0)) > before_epoch, "reconnected B ownership epoch advances")
	_assert(String(after_details.get("beacon_location", "")) == "CONTAINER", "reconnected B sees world-item removal")
	_assert(String(after_details.get("beacon_container_id", "")) == CRATE_CONTAINER_ID, "reconnected B reconstructs canonical crate location")
	_assert(int(after_details.get("beacon_slot_index", -1)) == 0, "reconnected B reconstructs canonical crate slot")
	_assert(bool(after_details.get("crate_contains_beacon", false)), "reconnected B reconstructs external-container membership")
	_assert(_positions_close(Dictionary(actor_details.get("actor_player", {})), Dictionary(after_details.get("actor_player", {})), 0.05), "reconnected B converges to A authoritative transform after absent-peer movement")

	var actor_reconnect := _wait_state(actor_file, ["ACTOR_RECONNECT_SEEN", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(String(actor_reconnect.get("state", "")) == "ACTOR_RECONNECT_SEEN" and bool(actor_reconnect.get("passed", false)), "A stays connected and observes B return")
	if String(actor_reconnect.get("state", "")) != "ACTOR_RECONNECT_SEEN" or not bool(actor_reconnect.get("passed", false)):
		_finish()
		return

	_write_control(control_file, "FINISH")
	var after_complete := _wait_state(after_file, ["RECONNECT_COMPLETE", "FAILED"], CLIENT_TIMEOUT_MS)
	var actor_complete := _wait_state(actor_file, ["ACTOR_COMPLETE", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(String(after_complete.get("state", "")) == "RECONNECT_COMPLETE" and bool(after_complete.get("passed", false)), "reconnected B shuts down cleanly")
	_assert(String(actor_complete.get("state", "")) == "ACTOR_COMPLETE" and bool(actor_complete.get("passed", false)), "actor A remains healthy through complete reconnect cycle")
	_wait_exit(after_pid, EXIT_TIMEOUT_MS)
	_wait_exit(actor_pid, EXIT_TIMEOUT_MS)
	_assert(not OS.is_process_running(after_pid), "reconnected B process exits")
	_assert(not OS.is_process_running(actor_pid), "actor A process exits after reconnect cycle")
	child_pids.erase(after_pid)
	child_pids.erase(actor_pid)

	if server_pid > 0 and OS.is_process_running(server_pid):
		OS.kill(server_pid)
		OS.delay_msec(300)
	child_pids.erase(server_pid)
	_assert(true, "V0-P1 reconnect dedicated server termination signal sent")
	for entry in [
		{"path": server_log, "label": "server"},
		{"path": actor_log, "label": "actor-a"},
		{"path": before_log, "label": "client-b-before"},
		{"path": after_log, "label": "client-b-after"},
	]:
		_assert_clean(String(entry["path"]), String(entry["label"]))
	_finish()


func _spawn_server(executable: String, project_root: String, port: int, log_file: String, user_root: String) -> int:
	return _spawn(executable, [
		"--headless", "--path", project_root,
		"--log-file", log_file, "--",
		"--network-mvp", "--role=dedicated-server", "--world=earth",
		"--server-address=127.0.0.1", "--server-port=%d" % port,
		"--network-debug", "--network-debug-stay-open", "--shutdown-after-ms=180000",
	], user_root)


func _spawn_client(
	executable: String,
	project_root: String,
	port: int,
	mode: String,
	result_file: String,
	control_file: String,
	extra: Dictionary,
	log_file: String,
	user_root: String
) -> int:
	var args: Array[String] = [
		"--headless", "--path", project_root,
		"--log-file", log_file,
		"--script", "res://tools/runtime/v0_p1_live_reconnect_client.gd", "--",
		"--host=127.0.0.1", "--port=%d" % port,
		"--mode=%s" % mode,
		"--result-file=%s" % result_file,
		"--control-file=%s" % control_file,
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


func _wait_log_marker(pid: int, path: String, marker: String, timeout_ms: int) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < timeout_ms:
		if pid > 0 and not OS.is_process_running(pid):
			return false
		if FileAccess.file_exists(path) and FileAccess.get_file_as_string(path).contains(marker):
			return true
		OS.delay_msec(POLL_MS)
	return false


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return Dictionary(parsed) if parsed is Dictionary else {}


func _write_control(path: String, phase: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"phase": phase, "written_at_ms": Time.get_ticks_msec()}, "  "))
	file.close()


func _wait_exit(pid: int, timeout_ms: int) -> void:
	var started := Time.get_ticks_msec()
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() - started < timeout_ms:
		OS.delay_msec(POLL_MS)


func _positions_close(left: Dictionary, right: Dictionary, tolerance: float) -> bool:
	return _player_position(left).distance_to(_player_position(right)) <= tolerance


func _player_position(record: Dictionary) -> Vector3:
	var position: Dictionary = Dictionary(record.get("position", {}))
	return Vector3(
		float(position.get("x", 0.0)),
		float(position.get("y", 0.0)),
		float(position.get("z", 0.0))
	)


func _assert_clean(path: String, label: String) -> void:
	var text := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var lower := text.to_lower()
	var clean := (
		not lower.contains("script error")
		and not lower.contains("parse error")
		and not lower.contains("compile error")
		and not lower.contains("v0_p1_reconnect_")
	)
	_assert(clean, "%s log contains no reconnect/parser/runtime failure" % label)


func _find_port() -> int:
	for candidate in range(48600 + OS.get_process_id() % 250, 50600):
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
	print("V0-P1 live reconnect convergence: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

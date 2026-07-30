extends SceneTree

const Support = preload("res://scripts/runtime/networked_gameplay/m3/m3_process_support.gd")

const POLL_DELAY_MS := 50
const SERVER_TIMEOUT_MS := 45000
const CLIENT_TIMEOUT_MS := 180000
const EXIT_TIMEOUT_MS := 20000

var failures: Array[String] = []
var assertions := 0
var child_pids: Array[int] = []
var xvfb_pid := -1

func _init() -> void:
	var port := _find_available_port()
	_assert(port > 0, "UDP port allocation")
	if port <= 0: _finish(); return
	var root := ProjectSettings.globalize_path("res://artifacts/test-results/m3-graphical-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(root)
	var server_path := root.path_join("server.json")
	var a1_path := root.path_join("client-a-initial.json")
	var b_path := root.path_join("client-b.json")
	var a2_path := root.path_join("client-a-reconnect.json")
	var display_name := ""
	if OS.get_name() == "Linux":
		display_name = _start_virtual_display(root)
		_assert(not display_name.is_empty(), "virtual display started")
		if display_name.is_empty(): _finish(); return
	var executable := OS.get_executable_path()
	var project_root := ProjectSettings.globalize_path("res://")
	var server_pid := _spawn(executable, [
		"--headless", "--quiet", "--path", project_root, "--log-file", root.path_join("server.log"), "--",
		"--role=dedicated-server", "--world=moon", "--node-id=m3-dedicated-server",
		"--server-address=127.0.0.1", "--server-port=%d" % port,
		"--m3-result-file=%s" % server_path, "--shutdown-after-ms=300000",
	], root.path_join("user-server"), "")
	child_pids.append(server_pid); _assert(server_pid > 0, "dedicated server launched")
	var server_ready := _wait_state(server_path, ["READY", "FAILED"], SERVER_TIMEOUT_MS)
	_assert(String(server_ready.get("state", "")) == "READY", "dedicated server ready: %s" % server_ready)
	if String(server_ready.get("state", "")) != "READY": _finish(); return

	var a1_pid := _spawn_client(executable, project_root, port, "a", 1, a1_path, b_path, root.path_join("a1.log"), root.path_join("user-a1"), display_name)
	child_pids.append(a1_pid)
	_assert(a1_pid > 0, "graphical client A launched")
	var server_after_a_join := _wait_connected(server_path, 1, 90000)
	_assert(int(server_after_a_join.get("connected_peer_count", 0)) == 1, "client A connected before second graphical startup")
	var b_pid := _spawn_client(executable, project_root, port, "b", 2, b_path, a2_path, root.path_join("b.log"), root.path_join("user-b"), display_name)
	child_pids.append(b_pid)
	_assert(b_pid > 0, "second graphical client launched while A remains connected")
	var a1 := _wait_state(a1_path, ["COMPLETE", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(bool(a1.get("passed", false)), "client A initial completed: %s" % a1)
	var b_waiting := _wait_state(b_path, ["WAITING_RECONNECT", "FAILED", "COMPLETE"], CLIENT_TIMEOUT_MS)
	_assert(String(b_waiting.get("state", "")) == "WAITING_RECONNECT", "client B remained online after A leave: %s" % b_waiting)
	_wait_exit(a1_pid, EXIT_TIMEOUT_MS)
	_assert(not OS.is_process_running(a1_pid), "initial A process exited")
	child_pids.erase(a1_pid)
	var server_after_a := _wait_counts(server_path, 2, 1, 20000)
	_assert(int(server_after_a.get("connected_peer_count", -1)) == 1, "B remains connected while A is offline")

	var a2_pid := _spawn_client(executable, project_root, port, "a", 3, a2_path, b_path, root.path_join("a2.log"), root.path_join("user-a2"), display_name)
	child_pids.append(a2_pid); _assert(a2_pid > 0, "A reconnect graphical process launched")
	var a2 := _wait_state(a2_path, ["COMPLETE", "FAILED"], CLIENT_TIMEOUT_MS)
	var b := _wait_state(b_path, ["COMPLETE", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(bool(a2.get("passed", false)), "client A reconnect completed: %s" % a2)
	_assert(bool(b.get("passed", false)), "client B completed: %s" % b)
	_wait_exit(a2_pid, EXIT_TIMEOUT_MS); _wait_exit(b_pid, EXIT_TIMEOUT_MS)
	_assert(not OS.is_process_running(a2_pid), "reconnected A process exited")
	_assert(not OS.is_process_running(b_pid), "B process exited")
	child_pids.erase(a2_pid); child_pids.erase(b_pid)
	_assert_clean_shutdown_log(root.path_join("a1.log"), "client A initial")
	_assert_clean_shutdown_log(root.path_join("b.log"), "client B")
	_assert_clean_shutdown_log(root.path_join("a2.log"), "client A reconnect")
	var server_final := _wait_counts(server_path, 3, 3, 30000)
	_validate(a1, b, a2, server_final)
	_finish()

func _spawn_client(executable: String, project_root: String, port: int, client_id: String, phase: int, result_path: String, peer_path: String, log_path: String, user_root: String, display_name: String) -> int:
	return _spawn(executable, [
		"--quiet", "--path", project_root, "--rendering-method", "gl_compatibility", "--audio-driver", "Dummy", "--log-file", log_path, "--",
		"--role=game-client", "--world=moon", "--node-id=m3-client-%s" % client_id,
		"--server-address=127.0.0.1", "--server-port=%d" % port, "--player-identity=%s" % client_id,
		"--connect-timeout-ms=60000", "--command-timeout-ms=12000",
		"--m3-result-file=%s" % result_path, "--m3-peer-result-file=%s" % peer_path, "--m3-phase=%d" % phase,
	], user_root, display_name)

func _spawn(executable: String, args: Array[String], user_root: String, display_name: String) -> int:
	var names: Array[String] = ["HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA", "DISPLAY", "LIBGL_ALWAYS_SOFTWARE"]
	var captured := _capture_environment(names)
	var data := user_root.path_join("data"); var config := user_root.path_join("config"); var cache := user_root.path_join("cache")
	for path in [user_root, data, config, cache]: DirAccess.make_dir_recursive_absolute(path)
	OS.set_environment("HOME", user_root); OS.set_environment("XDG_DATA_HOME", data); OS.set_environment("XDG_CONFIG_HOME", config); OS.set_environment("XDG_CACHE_HOME", cache); OS.set_environment("APPDATA", data); OS.set_environment("LOCALAPPDATA", data)
	if not display_name.is_empty(): OS.set_environment("DISPLAY", display_name); OS.set_environment("LIBGL_ALWAYS_SOFTWARE", "1")
	var pid := OS.create_process(executable, args, false)
	_restore_environment(captured)
	return pid

func _start_virtual_display(root: String) -> String:
	if not FileAccess.file_exists("/usr/bin/Xvfb"): failures.append("Xvfb required"); return ""
	var base := 300 + (OS.get_process_id() % 400)
	for offset in range(20):
		var display_name := ":%d" % (base + offset)
		xvfb_pid = OS.create_process("/usr/bin/Xvfb", [display_name, "-screen", "0", "1280x720x24", "-nolisten", "tcp", "-noreset"], false)
		if xvfb_pid <= 0: continue
		OS.delay_msec(500)
		if OS.is_process_running(xvfb_pid): child_pids.append(xvfb_pid); return display_name
	return ""

func _validate(a1: Dictionary, b: Dictionary, a2: Dictionary, server: Dictionary) -> void:
	for report in [a1, b, a2]:
		_assert(String(report.get("display_server", "")).to_lower() not in ["", "headless", "dummy"], "client used graphical display")
		_assert(String(report.get("rendering_method", "")) == "gl_compatibility", "client used GL compatibility")
		_assert(int(report.get("client_runtime", {}).get("direct_authority_references", 1)) == 0, "client has no authority reference")
		_assert(bool(report.get("client_runtime", {}).get("automated_acceptance", false)), "automated client input is isolated")
		_assert(int(report.get("world", {}).get("remote_presenter_count", 0)) == 1, "client has one remote presenter")
		var presenters: Dictionary = report.get("world", {}).get("remote_presenters", {})
		for presenter_value in presenters.values():
			_assert(not bool(Dictionary(presenter_value).get("input_authority", true)), "remote presenter has no input authority")
	_assert(String(a1.get("client_runtime", {}).get("player_entity_id", "")) == "player/a", "A stable entity initial")
	_assert(String(a2.get("client_runtime", {}).get("player_entity_id", "")) == "player/a", "A stable entity reconnect")
	_assert(int(a1.get("client_runtime", {}).get("ownership_epoch", 0)) == 1, "A initial ownership epoch")
	_assert(int(a2.get("client_runtime", {}).get("ownership_epoch", 0)) == 2, "A reconnect ownership epoch")
	_assert(String(b.get("client_runtime", {}).get("player_entity_id", "")) == "player/b", "B stable entity")
	_assert(int(b.get("world", {}).get("remote_despawn_count", 0)) >= 1, "B despawned A on disconnect")
	_assert(int(b.get("world", {}).get("remote_spawn_count", 0)) >= 2, "B respawned A on reconnect")
	_assert(bool(b.get("second_move_result", {}).get("success", false)), "B continued movement while A offline")
	_assert(bool(a1.get("presentation_result", {}).get("success", false)), "A authoritative flashlight update succeeded")
	var b_remote_a: Dictionary = b.get("world", {}).get("remote_presenters", {}).get("a", {})
	_assert(bool(b_remote_a.get("flashlight_enabled", false)), "B observed A flashlight state")
	_assert(absf(float(b_remote_a.get("orientation_yaw", 99.0))) <= PI, "B observed canonical A orientation")
	_assert(String(a2.get("convergence_checksum", "")) == String(b.get("convergence_checksum", "")), "A and B canonical checksum convergence")
	_assert(String(server.get("last_two_connected_checksum", "")) == String(a2.get("convergence_checksum", "")), "server and clients checksum convergence")
	_assert(int(server.get("joins", 0)) == 3, "server saw A, B, A reconnect joins")
	_assert(int(server.get("leaves", 0)) == 3, "server saw all graceful leaves")
	_assert(int(server.get("rejections", -1)) == 0, "server rejected no valid movement")
	_assert(int(server.get("presentation_updates", 0)) >= 1, "server replicated presentation state")
	_assert(int(server.get("connected_peer_count", -1)) == 0, "server has no stale peers")
	var dirs := [String(server.get("resolved_user_data_dir", "")), String(a1.get("resolved_user_data_dir", "")), String(b.get("resolved_user_data_dir", "")), String(a2.get("resolved_user_data_dir", ""))]
	var unique: Dictionary = {}; for path in dirs: unique[path] = true
	_assert(unique.size() == 4, "server and graphical clients use isolated user data")

func _wait_state(path: String, states: Array[String], timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec(); var last: Dictionary = {}
	while Time.get_ticks_msec() - started <= timeout_ms:
		last = _read_json(path)
		if String(last.get("state", "")) in states: return last
		OS.delay_msec(POLL_DELAY_MS)
	return last
func _wait_counts(path: String, joins: int, leaves: int, timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec(); var last: Dictionary = {}
	while Time.get_ticks_msec() - started <= timeout_ms:
		last = _read_json(path)
		if int(last.get("joins", 0)) >= joins and int(last.get("leaves", 0)) >= leaves: return last
		OS.delay_msec(POLL_DELAY_MS)
	return last
func _wait_connected(path: String, connected: int, timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec(); var last: Dictionary = {}
	while Time.get_ticks_msec() - started <= timeout_ms:
		last = _read_json(path)
		if int(last.get("connected_peer_count", 0)) >= connected: return last
		OS.delay_msec(POLL_DELAY_MS)
	return last
func _wait_exit(pid: int, timeout_ms: int) -> void:
	var started := Time.get_ticks_msec()
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() - started <= timeout_ms: OS.delay_msec(POLL_DELAY_MS)
func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var parsed = JSON.parse_string(file.get_as_text()); file.close()
	return Dictionary(parsed) if parsed is Dictionary else {}
func _assert_clean_shutdown_log(path: String, label: String) -> void:
	var text := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var lowered := text.to_lower()
	_assert(not lowered.contains("objectdb instances leaked") and not lowered.contains("resources still in use"), "%s clean graphical shutdown" % label)
func _find_available_port() -> int:
	for port in range(39000 + (OS.get_process_id() % 1000), 41000):
		var udp := PacketPeerUDP.new()
		if udp.bind(port, "127.0.0.1") == OK: udp.close(); return port
	return 0
func _capture_environment(names: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	for name in names: result[name] = {"set": OS.has_environment(name), "value": OS.get_environment(name)}
	return result
func _restore_environment(values: Dictionary) -> void:
	for name in values.keys():
		if bool(values[name].get("set", false)): OS.set_environment(String(name), String(values[name].get("value", "")))
		else: OS.unset_environment(String(name))
func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition: print("PASS: %s" % message)
	else: failures.append(message); push_error("FAIL: %s" % message)
func _finish() -> void:
	for pid in child_pids.duplicate():
		if pid > 0 and OS.is_process_running(pid): OS.kill(pid)
	child_pids.clear()
	print("M3 graphical multiplayer: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

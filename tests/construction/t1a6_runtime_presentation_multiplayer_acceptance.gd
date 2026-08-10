extends SceneTree

const POLL_MS: int = 50
const SERVER_TIMEOUT_MS: int = 30000
const CLIENT_TIMEOUT_MS: int = 90000
const FINAL_TIMEOUT_MS: int = 15000

var failures: Array[String] = []
var assertions: int = 0
var pids: Array[int] = []
var xvfb_pid: int = -1


func _init() -> void:
	var port := _find_port()
	_assert(port > 0, "port allocation")
	if port <= 0:
		_finish()
		return
	var out := ProjectSettings.globalize_path("res://artifacts/test-results/t1a6-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(out)
	var server_file := out.path_join("server.json")
	var server_m3_file := out.path_join("server-m3.json")
	var a_file := out.path_join("a.json")
	var b_file := out.path_join("b.json")
	var display := ""
	if OS.get_name() == "Linux":
		display = _start_xvfb()
		_assert(not display.is_empty(), "Xvfb graphical display")
	var exe := OS.get_executable_path()
	var root_path := ProjectSettings.globalize_path("res://")

	var server := _spawn(
		exe,
		[
			"--headless", "--quiet", "--path", root_path,
			"--log-file", out.path_join("server.log"),
			"--script", "res://tools/runtime/t1a6_runtime_server.gd",
			"--",
			"--host=127.0.0.1",
			"--port=%d" % port,
			"--result-file=%s" % server_file,
			"--m3-result-file=%s" % server_m3_file,
			"--m0-root=user://t1a6-m0",
			"--shutdown-after-ms=180000",
		],
		out.path_join("user-server"),
		""
	)
	pids.append(server)
	_assert(server > 0, "T1A.6 dedicated server launch")
	var ready := _wait_state(server_file, ["READY", "FAILED"], SERVER_TIMEOUT_MS)
	_assert(String(ready.get("state", "")) == "READY", "T1A.6 dedicated server ready: %s" % ready)
	if String(ready.get("state", "")) != "READY":
		_finish()
		return

	var a := _spawn_client(exe, root_path, port, "a", 1, a_file, b_file, out.path_join("a.log"), out.path_join("user-a"), display)
	pids.append(a)
	_assert(a > 0, "graphical client A launch")
	var a_open := _wait_state(a_file, ["A_OPEN_DONE", "FAILED", "TIMEOUT", "OPEN_FAILED", "OPEN_REPLICA_TIMEOUT"], CLIENT_TIMEOUT_MS)
	_assert(String(a_open.get("state", "")) == "A_OPEN_DONE", "A opens authoritative door and receives presentation: %s" % a_open)
	if String(a_open.get("state", "")) != "A_OPEN_DONE":
		_finish()
		return

	var b := _spawn_client(exe, root_path, port, "b", 2, b_file, a_file, out.path_join("b.log"), out.path_join("user-b"), display)
	pids.append(b)
	_assert(b > 0, "graphical client B launch after door is open")
	var ar := _wait_state(a_file, ["COMPLETE", "FAILED", "TIMEOUT", "WAIT_B_LAMP_TIMEOUT", "FINAL_REPLICA_TIMEOUT"], CLIENT_TIMEOUT_MS)
	var br := _wait_state(b_file, ["COMPLETE", "FAILED", "TIMEOUT", "FINAL_DOOR_REPLICA_TIMEOUT", "DOOR_OPEN_PRESENTATION_MISMATCH"], CLIENT_TIMEOUT_MS)
	_assert(bool(ar.get("passed", false)), "client A runtime sequence complete: %s" % ar)
	_assert(bool(br.get("passed", false)), "client B runtime sequence complete: %s" % br)
	_wait_exit(a, 10000)
	_wait_exit(b, 10000)

	var a_snapshot: Dictionary = ar.get("runtime_snapshot", {})
	var b_snapshot: Dictionary = br.get("runtime_snapshot", {})
	var expected_state_checksum := String(a_snapshot.get("state_checksum", "")) if String(a_snapshot.get("state_checksum", "")) == String(b_snapshot.get("state_checksum", "")) else ""
	var final_server := _wait_server_runtime(server_file, expected_state_checksum, 7, FINAL_TIMEOUT_MS)
	var server_snapshot: Dictionary = final_server.get("t1a6", {}).get("runtime_snapshot", {})

	_assert(String(ar.get("display_server", "")).to_lower() not in ["", "headless", "dummy"], "A is graphical")
	_assert(String(br.get("display_server", "")).to_lower() not in ["", "headless", "dummy"], "B is graphical")
	_assert(int(a_snapshot.get("revision", 0)) >= 7, "A received final runtime revision")
	_assert(int(b_snapshot.get("revision", 0)) >= 7, "B received final runtime revision")
	_assert(int(server_snapshot.get("revision", 0)) >= 7, "server reached final runtime revision")
	_assert(not expected_state_checksum.is_empty(), "A and B runtime state checksum convergence")
	_assert(String(server_snapshot.get("state_checksum", "")) == expected_state_checksum, "server and clients runtime state checksum convergence")
	_assert(_final_presentation_ok(Dictionary(ar.get("presentation", {}))), "A final presentation matches canonical runtime")
	_assert(_final_presentation_ok(Dictionary(br.get("presentation", {}))), "B final presentation matches canonical runtime")
	_assert(int(Dictionary(ar.get("client", {})).get("t1a6", {}).get("runtime_snapshot_rejections", -1)) == 0, "A runtime replica has no rejection")
	_assert(int(Dictionary(br.get("client", {})).get("t1a6", {}).get("runtime_snapshot_rejections", -1)) == 0, "B runtime replica has no rejection")
	var server_t1a6: Dictionary = final_server.get("t1a6", {})
	_assert(int(server_t1a6.get("runtime_commands", 0)) == 3, "server executed exactly three runtime commands")
	_assert(int(server_t1a6.get("runtime_rejections", -1)) == 0, "server runtime commands have no rejection")
	_assert(int(server_t1a6.get("runtime_snapshots", 0)) >= 5, "server published join and mutation runtime snapshots")
	_assert_clean(out.path_join("a.log"), "A")
	_assert_clean(out.path_join("b.log"), "B")
	_assert_clean(out.path_join("server.log"), "server")
	_finish()


func _spawn_client(exe: String, root_path: String, port: int, client_id: String, phase: int, result: String, peer: String, log: String, user: String, display: String) -> int:
	return _spawn(
		exe,
		[
			"--quiet", "--path", root_path,
			"--rendering-method", "gl_compatibility",
			"--audio-driver", "Dummy",
			"--log-file", log,
			"--script", "res://tools/runtime/t1a6_runtime_client.gd",
			"--",
			"--host=127.0.0.1",
			"--port=%d" % port,
			"--client-id=%s" % client_id,
			"--phase=%d" % phase,
			"--result-file=%s" % result,
			"--peer-file=%s" % peer,
		],
		user,
		display
	)


func _spawn(exe: String, args: Array[String], user: String, display: String) -> int:
	var names := ["HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA", "DISPLAY", "LIBGL_ALWAYS_SOFTWARE"]
	var old: Dictionary = {}
	for name in names:
		old[name] = {"set": OS.has_environment(name), "value": OS.get_environment(name)}
	for path in [user, user.path_join("data"), user.path_join("config"), user.path_join("cache")]:
		DirAccess.make_dir_recursive_absolute(path)
	OS.set_environment("HOME", user)
	OS.set_environment("XDG_DATA_HOME", user.path_join("data"))
	OS.set_environment("XDG_CONFIG_HOME", user.path_join("config"))
	OS.set_environment("XDG_CACHE_HOME", user.path_join("cache"))
	OS.set_environment("APPDATA", user.path_join("data"))
	OS.set_environment("LOCALAPPDATA", user.path_join("data"))
	if not display.is_empty():
		OS.set_environment("DISPLAY", display)
		OS.set_environment("LIBGL_ALWAYS_SOFTWARE", "1")
	var pid := OS.create_process(exe, args, false)
	for name in names:
		if bool(old[name]["set"]):
			OS.set_environment(name, String(old[name]["value"]))
		else:
			OS.unset_environment(name)
	return pid


func _start_xvfb() -> String:
	if not FileAccess.file_exists("/usr/bin/Xvfb"):
		return ""
	var display := ":%d" % (600 + OS.get_process_id() % 300)
	xvfb_pid = OS.create_process("/usr/bin/Xvfb", [display, "-screen", "0", "1280x720x24", "-nolisten", "tcp", "-noreset"], false)
	pids.append(xvfb_pid)
	OS.delay_msec(500)
	return display if OS.is_process_running(xvfb_pid) else ""


func _wait_state(path: String, states: Array[String], timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	var value: Dictionary = {}
	while Time.get_ticks_msec() - started < timeout_ms:
		value = _read(path)
		if String(value.get("state", "")) in states:
			return value
		OS.delay_msec(POLL_MS)
	return value


func _wait_server_runtime(path: String, expected_checksum: String, minimum_revision: int, timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	var value: Dictionary = {}
	while Time.get_ticks_msec() - started < timeout_ms:
		value = _read(path)
		var snapshot: Dictionary = value.get("t1a6", {}).get("runtime_snapshot", {})
		if int(snapshot.get("revision", 0)) >= minimum_revision and not expected_checksum.is_empty() and String(snapshot.get("state_checksum", "")) == expected_checksum:
			return value
		OS.delay_msec(POLL_MS)
	return value


func _wait_exit(pid: int, timeout_ms: int) -> void:
	var started := Time.get_ticks_msec()
	while OS.is_process_running(pid) and Time.get_ticks_msec() - started < timeout_ms:
		OS.delay_msec(POLL_MS)


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return Dictionary(parsed) if parsed is Dictionary else {}


func _final_presentation_ok(value: Dictionary) -> bool:
	return not bool(value.get("door_open", true)) \
		and bool(value.get("lamp_visible", false)) \
		and bool(value.get("generator_running", false)) \
		and not bool(value.get("console_active", true))


func _assert_clean(path: String, label: String) -> void:
	var text := FileAccess.get_file_as_string(path).to_lower() if FileAccess.file_exists(path) else ""
	_assert(not text.contains("objectdb instances leaked") and not text.contains("resources still in use"), "%s clean shutdown" % label)


func _find_port() -> int:
	for port in range(44000 + OS.get_process_id() % 500, 46000):
		var udp := PacketPeerUDP.new()
		if udp.bind(port, "127.0.0.1") == OK:
			udp.close()
			return port
	return 0


func _assert(ok: bool, message: String) -> void:
	assertions += 1
	if ok:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)


func _finish() -> void:
	for pid in pids:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
	print("T1A.6 runtime presentation multiplayer: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

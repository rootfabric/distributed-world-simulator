extends SceneTree

const Support = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")

const POLL_MS := 50
const READY_TIMEOUT_MS := 30000
const COMPLETE_TIMEOUT_MS := 120000

var _failures: Array[String] = []
var _assertions := 0
var _pids: Array[int] = []
var _xvfb_pid := -1


func _init() -> void:
	var ports := _allocate_ports(3)
	_assert(ports.size() == 3, "three ENET ports allocated")
	if ports.size() != 3:
		_finish()
		return

	var out := ProjectSettings.globalize_path(
		"res://artifacts/test-results/v0-test-client-seam-%d" % OS.get_process_id()
	)
	DirAccess.make_dir_recursive_absolute(out)
	var display := ""
	if OS.get_name() == "Linux":
		display = _ensure_display()
		_assert(not display.is_empty(), "graphical display available")
		if display.is_empty():
			_finish()
			return

	var exe := OS.get_executable_path()
	var project_root := ProjectSettings.globalize_path("res://")
	var authority_a_file := out.path_join("authority-a.json")
	var authority_b_file := out.path_join("authority-b.json")
	var gateway_file := out.path_join("gateway.json")
	var client_a_file := out.path_join("client-a.json")
	var client_b_file := out.path_join("client-b.json")

	var authority_a := _spawn(exe, [
		"--headless", "--quiet", "--path", project_root,
		"--log-file", out.path_join("authority-a.log"),
		"--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_6_authority_worker.gd", "--",
		"--authority-id=%s" % Support.AUTHORITY_A,
		"--host=127.0.0.1", "--port=%d" % int(ports[1]),
		"--initial-active=true", "--initial-epoch=1",
		"--result-file=%s" % authority_a_file,
	], out.path_join("user-authority-a"), display)
	var authority_b := _spawn(exe, [
		"--headless", "--quiet", "--path", project_root,
		"--log-file", out.path_join("authority-b.log"),
		"--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_6_authority_worker.gd", "--",
		"--authority-id=%s" % Support.AUTHORITY_B,
		"--host=127.0.0.1", "--port=%d" % int(ports[2]),
		"--initial-active=false", "--initial-epoch=1",
		"--result-file=%s" % authority_b_file,
	], out.path_join("user-authority-b"), display)
	_pids.append(authority_a)
	_pids.append(authority_b)
	_assert(authority_a > 0 and authority_b > 0, "Authority A/B launched")

	var a_ready := _wait_state(authority_a_file, ["LISTENING", "FAILED"], READY_TIMEOUT_MS)
	var b_ready := _wait_state(authority_b_file, ["LISTENING", "FAILED"], READY_TIMEOUT_MS)
	_assert(String(a_ready.get("state", "")) == "LISTENING", "Authority A listening")
	_assert(String(b_ready.get("state", "")) == "LISTENING", "Authority B listening")
	if String(a_ready.get("state", "")) != "LISTENING" or String(b_ready.get("state", "")) != "LISTENING":
		_finish()
		return

	var gateway := _spawn(exe, [
		"--headless", "--quiet", "--path", project_root,
		"--log-file", out.path_join("gateway.log"),
		"--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_6_gateway_worker.gd", "--",
		"--client-host=127.0.0.1", "--client-port=%d" % int(ports[0]),
		"--authority-a-host=127.0.0.1", "--authority-a-port=%d" % int(ports[1]),
		"--authority-b-host=127.0.0.1", "--authority-b-port=%d" % int(ports[2]),
		"--result-file=%s" % gateway_file,
	], out.path_join("user-gateway"), display)
	_pids.append(gateway)
	_assert(gateway > 0, "Gateway launched")
	var gateway_ready := _wait_state(gateway_file, ["LISTENING", "FAILED"], READY_TIMEOUT_MS)
	_assert(String(gateway_ready.get("state", "")) == "LISTENING", "Gateway listening")
	if String(gateway_ready.get("state", "")) != "LISTENING":
		_finish()
		return

	var client_a := _spawn(exe, [
		"--quiet", "--path", project_root,
		"--rendering-method", "gl_compatibility",
		"--audio-driver", "Dummy",
		"--log-file", out.path_join("client-a.log"),
		"--script", "res://tests/fixtures/v0_playable_seamless/client/v0_test_client_seam.gd", "--",
		"--client-id=a", "--host=127.0.0.1", "--port=%d" % int(ports[0]),
		"--result-file=%s" % client_a_file,
	], out.path_join("user-client-a"), display)
	var client_b := _spawn(exe, [
		"--quiet", "--path", project_root,
		"--rendering-method", "gl_compatibility",
		"--audio-driver", "Dummy",
		"--log-file", out.path_join("client-b.log"),
		"--script", "res://tests/fixtures/v0_playable_seamless/client/v0_test_client_seam.gd", "--",
		"--client-id=b", "--host=127.0.0.1", "--port=%d" % int(ports[0]),
		"--result-file=%s" % client_b_file,
	], out.path_join("user-client-b"), display)
	_pids.append(client_a)
	_pids.append(client_b)
	_assert(client_a > 0 and client_b > 0, "two observable graphical clients launched")

	var a_report := _wait_state(client_a_file, ["COMPLETE", "FAILED"], COMPLETE_TIMEOUT_MS)
	var b_report := _wait_state(client_b_file, ["COMPLETE", "FAILED"], COMPLETE_TIMEOUT_MS)
	var gateway_report := _wait_state(gateway_file, ["COMPLETE", "FAILED"], COMPLETE_TIMEOUT_MS)

	for pair in [["client A", a_report], ["client B", b_report], ["Gateway", gateway_report]]:
		_assert(bool(Dictionary(pair[1]).get("passed", false)), "%s passed" % String(pair[0]))
	for report in [a_report, b_report]:
		_assert(
			String(report.get("display_server", "")).to_lower() not in ["", "headless", "dummy"],
			"client uses graphical DisplayServer"
		)
		_assert(int(report.get("connect_count", 0)) == 1, "client uses one Gateway connection")
		_assert(int(report.get("reconnect_count", -1)) == 0, "client performs zero reconnects")
		_assert(int(report.get("respawn_count", -1)) == 0, "client performs zero respawns")
		_assert(
			_strings(report.get("route_history", [])) == [Support.AUTHORITY_A, Support.AUTHORITY_B, Support.AUTHORITY_A],
			"client observes A->B->A route"
		)

	_assert(int(gateway_report.get("client_connection_count", 0)) == 2, "Gateway has two clients")
	_assert(int(gateway_report.get("handoff_count", 0)) == 2, "Gateway completes A->B->A handoff")
	print("V0_TEST_CLIENT_SEAM_ARTIFACTS=%s" % out)
	_finish()


func _spawn(exe: String, args: Array, user_root: String, display: String) -> int:
	for path in [user_root, user_root.path_join("data"), user_root.path_join("config"), user_root.path_join("cache")]:
		DirAccess.make_dir_recursive_absolute(path)
	var names := ["HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "DISPLAY", "LIBGL_ALWAYS_SOFTWARE"]
	var old: Dictionary = {}
	for name in names:
		old[name] = {"set": OS.has_environment(name), "value": OS.get_environment(name)}
	OS.set_environment("HOME", user_root)
	OS.set_environment("APPDATA", user_root.path_join("data"))
	OS.set_environment("LOCALAPPDATA", user_root.path_join("data"))
	OS.set_environment("XDG_DATA_HOME", user_root.path_join("data"))
	OS.set_environment("XDG_CONFIG_HOME", user_root.path_join("config"))
	OS.set_environment("XDG_CACHE_HOME", user_root.path_join("cache"))
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


func _ensure_display() -> String:
	var current := OS.get_environment("DISPLAY")
	if not current.is_empty():
		return current
	if not FileAccess.file_exists("/usr/bin/Xvfb"):
		return ""
	var display := ":%d" % (600 + OS.get_process_id() % 300)
	_xvfb_pid = OS.create_process("/usr/bin/Xvfb", [display, "-screen", "0", "1440x900x24", "-nolisten", "tcp", "-noreset"], false)
	_pids.append(_xvfb_pid)
	OS.delay_msec(500)
	return display if OS.is_process_running(_xvfb_pid) else ""


func _allocate_ports(count: int) -> Array[int]:
	var result: Array[int] = []
	var start := 43000 + OS.get_process_id() % 700
	for port in range(start, 47000):
		var udp := PacketPeerUDP.new()
		if udp.bind(port, "127.0.0.1") == OK:
			udp.close()
			result.append(port)
			if result.size() == count:
				return result
	return []


func _wait_state(path: String, states: Array[String], timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	var value: Dictionary = {}
	while Time.get_ticks_msec() - started <= timeout_ms:
		value = _read_json(path)
		if String(value.get("state", "")) in states:
			return value
		OS.delay_msec(POLL_MS)
	return value


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return Dictionary(parsed) if parsed is Dictionary else {}


func _strings(values) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(String(value))
	return result


func _assert(ok: bool, message: String) -> void:
	_assertions += 1
	if ok:
		print("PASS: %s" % message)
	else:
		_failures.append(message)
		push_error("FAIL: %s" % message)


func _finish() -> void:
	for pid in _pids:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
	print("V0 test client seam: %d assertions, %d failures" % [_assertions, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

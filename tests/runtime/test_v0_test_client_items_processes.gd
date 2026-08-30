extends SceneTree

const Support = preload("res://scripts/runtime/networked_gameplay/m5/m5_graphical_acceptance_support.gd")

const POLL_MS := 50
const READY_TIMEOUT_MS := 30000
const COMPLETE_TIMEOUT_MS := 120000

var _failures: Array[String] = []
var _assertions := 0
var _pids: Array[int] = []
var _xvfb_pid := -1


func _init() -> void:
	var port := _allocate_port()
	_assert(port > 0, "dedicated-server ENET port allocated")
	if port <= 0:
		_finish()
		return

	var out := ProjectSettings.globalize_path(
		"res://artifacts/test-results/v0-test-client-items-%d" % OS.get_process_id()
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
	var server_file := out.path_join("server.json")
	var client_a_file := out.path_join("client-a.json")
	var client_b_file := out.path_join("client-b.json")
	var step_ms := maxi(100, int(OS.get_environment("DWS_TEST_CLIENT_STEP_MS")))
	if step_ms == 100 and OS.get_environment("DWS_TEST_CLIENT_STEP_MS").is_empty():
		step_ms = 650

	var server := _spawn(exe, [
		"--headless", "--quiet", "--path", project_root,
		"--log-file", out.path_join("server.log"), "--",
		"--role=dedicated-server",
		"--world=moon",
		"--server-address=127.0.0.1",
		"--server-port=%d" % port,
		"--m3-result-file=%s" % server_file,
		"--shutdown-after-ms=180000",
	], out.path_join("user-server"), display)
	_pids.append(server)
	_assert(server > 0, "dedicated server launched")
	var ready := _wait_state(server_file, ["READY", "FAILED"], READY_TIMEOUT_MS)
	_assert(String(ready.get("state", "")) == "READY", "dedicated server READY")
	if String(ready.get("state", "")) != "READY":
		_finish()
		return

	var client_b := _spawn(exe, [
		"--quiet", "--path", project_root,
		"--rendering-method", "gl_compatibility",
		"--audio-driver", "Dummy",
		"--log-file", out.path_join("client-b.log"),
		"--script", "res://tests/fixtures/v0_playable_seamless/client/v0_test_client_items.gd", "--",
		"--host=127.0.0.1", "--port=%d" % port,
		"--client-id=b", "--step-ms=%d" % step_ms,
		"--result-file=%s" % client_b_file,
		"--peer-file=%s" % client_a_file,
	], out.path_join("user-client-b"), display)
	_pids.append(client_b)
	_assert(client_b > 0, "observable Item client B launched")
	var b_ready := _wait_state(client_b_file, ["B_READY", "FAILED"], READY_TIMEOUT_MS)
	_assert(String(b_ready.get("state", "")) == "B_READY", "Item client B ready as independent observer")
	if String(b_ready.get("state", "")) != "B_READY":
		_finish()
		return

	var client_a := _spawn(exe, [
		"--quiet", "--path", project_root,
		"--rendering-method", "gl_compatibility",
		"--audio-driver", "Dummy",
		"--log-file", out.path_join("client-a.log"),
		"--script", "res://tests/fixtures/v0_playable_seamless/client/v0_test_client_items.gd", "--",
		"--host=127.0.0.1", "--port=%d" % port,
		"--client-id=a", "--step-ms=%d" % step_ms,
		"--result-file=%s" % client_a_file,
		"--peer-file=%s" % client_b_file,
	], out.path_join("user-client-a"), display)
	_pids.append(client_a)
	_assert(client_a > 0, "observable Item client A launched")

	var a_report := _wait_state(client_a_file, ["COMPLETE", "FAILED"], COMPLETE_TIMEOUT_MS)
	var b_report := _wait_state(client_b_file, ["COMPLETE", "FAILED"], COMPLETE_TIMEOUT_MS)
	_assert(bool(a_report.get("passed", false)), "Item client A demo passed")
	_assert(bool(b_report.get("passed", false)), "Item client B convergence passed")

	for report in [a_report, b_report]:
		_assert(
			String(report.get("display_server", "")).to_lower() not in ["", "headless", "dummy"],
			"Item client uses graphical DisplayServer"
		)
		var snapshot: Dictionary = Dictionary(report.get("item_graph", {}))
		_assert(String(snapshot.get("checksum", "")).length() == 64, "Item Graph checksum is exact SHA-256")

	var a_checksum := String(a_report.get("item_graph", {}).get("checksum", ""))
	var b_checksum := String(b_report.get("item_graph", {}).get("checksum", ""))
	_assert(a_checksum == b_checksum and not a_checksum.is_empty(), "A/B final Item Graph checksums converge")
	_assert(_container_has(Dictionary(a_report.get("item_graph", {})), "container/shared/crate/1", "item/shared/beacon/1"), "beacon ends in shared crate")
	_assert(Array(a_report.get("command_results", [])).size() == 7, "Client A completed seven canonical demo commands")
	print("V0_TEST_CLIENT_ITEMS_ARTIFACTS=%s" % out)
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
	var display := ":%d" % (700 + OS.get_process_id() % 200)
	_xvfb_pid = OS.create_process("/usr/bin/Xvfb", [display, "-screen", "0", "1440x1000x24", "-nolisten", "tcp", "-noreset"], false)
	_pids.append(_xvfb_pid)
	OS.delay_msec(500)
	return display if OS.is_process_running(_xvfb_pid) else ""


func _allocate_port() -> int:
	var start := 44000 + OS.get_process_id() % 700
	for port in range(start, 48000):
		var udp := PacketPeerUDP.new()
		if udp.bind(port, "127.0.0.1") == OK:
			udp.close()
			return port
	return 0


func _wait_state(path: String, states: Array[String], timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	var value: Dictionary = {}
	while Time.get_ticks_msec() - started <= timeout_ms:
		value = Support.read(path)
		if String(value.get("state", "")) in states:
			return value
		OS.delay_msec(POLL_MS)
	return value


func _container_has(snapshot: Dictionary, container_id: String, item_id: String) -> bool:
	for raw_container in snapshot.get("containers", []):
		var container: Dictionary = Dictionary(raw_container)
		if String(container.get("container_id", "")) == container_id:
			return item_id in Array(container.get("slots", []))
	return false


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
	print("V0 test client items: %d assertions, %d failures" % [_assertions, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

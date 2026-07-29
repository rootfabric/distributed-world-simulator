extends SceneTree

const TIMEOUT_MS: int = 20000
const POLL_DELAY_MS: int = 25

var failures: Array[String] = []
var assertions: int = 0
var pids: Array[int] = []


func _init() -> void:
	var port: int = _find_available_port()
	_assert(port > 0, "Could not allocate UDP port")
	if port <= 0:
		_finish()
		return
	var root: String = ProjectSettings.globalize_path("res://artifacts/test-results/t1-multi-peer-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(root)
	var server_path: String = root.path_join("server.json")
	var client_a_path: String = root.path_join("client-a.json")
	var client_b_path: String = root.path_join("client-b.json")
	for path in [server_path, client_a_path, client_b_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	var executable: String = OS.get_executable_path()
	var project_root: String = ProjectSettings.globalize_path("res://")
	var server_pid: int = OS.create_process(executable, [
		"--headless", "--path", project_root,
		"--script", "res://tools/network/t1_multi_peer_server.gd", "--",
		"--host=127.0.0.1", "--port=%d" % port,
		"--result-file=%s" % server_path,
		"--timeout-ms=%d" % TIMEOUT_MS,
		"--expected-clients=2",
	], false)
	pids.append(server_pid)
	_assert(server_pid > 0, "Failed to launch T1 server")
	var listening: Dictionary = _wait_for_state(server_path, "LISTENING", 5000)
	_assert(bool(listening.get("success", false)), "T1 server did not become LISTENING: %s" % listening)
	if not bool(listening.get("success", false)):
		_finish()
		return
	var client_a_pid: int = _launch_client(executable, project_root, port, "a", client_a_path)
	var client_b_pid: int = _launch_client(executable, project_root, port, "b", client_b_path)
	pids.append(client_a_pid)
	pids.append(client_b_pid)
	_assert(client_a_pid > 0, "Failed to launch client A")
	_assert(client_b_pid > 0, "Failed to launch client B")
	var server: Dictionary = _wait_for_terminal(server_path, TIMEOUT_MS)
	var client_a: Dictionary = _wait_for_terminal(client_a_path, TIMEOUT_MS)
	var client_b: Dictionary = _wait_for_terminal(client_b_path, TIMEOUT_MS)
	_assert(bool(server.get("passed", false)), "T1 server failed: %s" % server)
	_assert(bool(client_a.get("passed", false)), "T1 client A failed: %s" % client_a)
	_assert(bool(client_b.get("passed", false)), "T1 client B failed: %s" % client_b)
	_assert(String(server.get("listener_state", "")) == "LISTENING", "Listener did not remain LISTENING with two peers")
	_assert(int(server.get("messages_received", 0)) == 2, "Server did not receive two probes")
	_assert(int(server.get("messages_sent", 0)) == 2, "Server did not send two targeted replies")
	_assert(int(server.get("peak_peer_count", 0)) == 2, "Server did not observe two simultaneous peer sessions")
	var clients: Array = server.get("received_clients", [])
	clients.sort()
	_assert(clients == ["a", "b"], "Server client set is incorrect")
	_assert(String(client_a.get("received_client_id", "")) == "a", "Client A received wrong targeted reply")
	_assert(String(client_b.get("received_client_id", "")) == "b", "Client B received wrong targeted reply")
	_assert(String(client_a.get("target_peer_id", "")) != String(client_b.get("target_peer_id", "")), "Server used one peer identity for both clients")
	_assert(String(client_a.get("session_id", "")) != String(client_b.get("session_id", "")), "Clients shared a transport session")
	for pid in pids:
		_wait_for_exit(pid, 3000)
		_assert(pid <= 0 or not OS.is_process_running(pid), "Child process remained running: %d" % pid)
	_write_summary(port, server, client_a, client_b)
	_finish()


func _launch_client(executable: String, project_root: String, port: int, client_id: String, result_path: String) -> int:
	return OS.create_process(executable, [
		"--headless", "--path", project_root,
		"--script", "res://tools/network/t1_multi_peer_client.gd", "--",
		"--host=127.0.0.1", "--port=%d" % port,
		"--result-file=%s" % result_path,
		"--timeout-ms=%d" % TIMEOUT_MS,
		"--client-id=%s" % client_id,
	], false)


func _find_available_port() -> int:
	var start: int = 21000 + (OS.get_process_id() % 20000)
	for offset in range(200):
		var port: int = 20000 + ((start + offset - 20000) % 30000)
		var probe := PacketPeerUDP.new()
		var error: Error = probe.bind(port, "127.0.0.1")
		probe.close()
		if error == OK:
			return port
	return 0


func _wait_for_state(path: String, state: String, timeout_ms: int) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= timeout_ms:
		var value: Dictionary = _read_json(path)
		if String(value.get("state", "")) == state:
			return {"success": true, "value": value}
		if String(value.get("state", "")) == "FAILED":
			return {"success": false, "value": value}
		OS.delay_msec(POLL_DELAY_MS)
	return {"success": false, "error_code": "TIMEOUT"}


func _wait_for_terminal(path: String, timeout_ms: int) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= timeout_ms:
		var value: Dictionary = _read_json(path)
		if String(value.get("state", "")) in ["COMPLETE", "FAILED"]:
			return value
		OS.delay_msec(POLL_DELAY_MS)
	return {}


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


func _wait_for_exit(pid: int, timeout_ms: int) -> void:
	if pid <= 0:
		return
	var started: int = Time.get_ticks_msec()
	while OS.is_process_running(pid) and Time.get_ticks_msec() - started <= timeout_ms:
		OS.delay_msec(POLL_DELAY_MS)


func _write_summary(port: int, server: Dictionary, client_a: Dictionary, client_b: Dictionary) -> void:
	var path: String = ProjectSettings.globalize_path("res://artifacts/test-results/t1-multi-peer-summary.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({
			"schema": "planet_simulator.t1_multi_peer_summary.v1",
			"checkpoint": "v16.9.1-runtime-h1-playable-listen-host",
			"build_id": "h1-playable-listen-host",
			"passed": failures.is_empty(), "port": port,
			"server": server, "client_a": client_a, "client_b": client_b,
		}, "  ", true, true) + "\n")
		file.close()


func _cleanup() -> void:
	for pid in pids:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	_cleanup()
	if failures.is_empty():
		print("T1 multi-peer transport processes: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("T1 multi-peer transport processes: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)

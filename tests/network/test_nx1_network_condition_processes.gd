extends SceneTree

const POLL_DELAY_MS := 25
const SERVER_TIMEOUT_MS := 30000
const PROBE_TIMEOUT_MS := 30000
const EXIT_TIMEOUT_MS := 10000
const SESSION_TOKEN := "session-id/nx1/process-acceptance"
const PROFILE_ID := "AVERAGE_BROADBAND"

var assertions: int = 0
var failures: Array[String] = []
var child_pids: Array[int] = []


func _init() -> void:
	var port: int = _find_available_port()
	_assert(port > 0, "NX1 UDP port allocation")
	if port <= 0:
		_finish()
		return
	var root: String = ProjectSettings.globalize_path(
		"res://artifacts/test-results/nx1-condition-%d" % OS.get_process_id()
	)
	DirAccess.make_dir_recursive_absolute(root)
	var server_path: String = root.path_join("server.json")
	var probe_path: String = root.path_join("probe.json")
	var executable: String = OS.get_executable_path()
	var project_root: String = ProjectSettings.globalize_path("res://")
	var server_pid: int = _spawn(executable, [
		"--headless", "--quiet", "--path", project_root,
		"--log-file", root.path_join("server.log"), "--",
		"--role=dedicated-server", "--world=moon", "--node-id=nx1-condition-server",
		"--server-address=127.0.0.1", "--server-port=%d" % port,
		"--network-session-token=%s" % SESSION_TOKEN,
		"--network-profile=%s" % PROFILE_ID,
		"--m3-result-file=%s" % server_path, "--shutdown-after-ms=120000",
	], root.path_join("user-server"))
	child_pids.append(server_pid)
	_assert(server_pid > 0, "NX1 dedicated server launched")
	var ready: Dictionary = _wait_state(server_path, ["READY", "FAILED"], SERVER_TIMEOUT_MS)
	_assert(String(ready.get("state", "")) == "READY", "NX1 dedicated server ready")
	_assert(String(ready.get("checkpoint", "")) in ["v16.11.0-network-nx1-deterministic-condition-simulator", "v16.12.0-network-nx2-realtime-traffic-separation"], "Server reports NX1 checkpoint")
	_assert(String(ready.get("network_conditions", {}).get("profile", {}).get("profile_id", "")) == PROFILE_ID, "Server activates requested profile")
	_assert(not bool(ready.get("network_conditions", {}).get("passthrough", true)), "Server profile is not passthrough")
	if String(ready.get("state", "")) != "READY":
		_finish()
		return

	var probe_pid: int = _spawn(executable, [
		"--headless", "--quiet", "--path", project_root,
		"--log-file", root.path_join("probe.log"),
		"--script", "res://tools/network/nx0_handshake_probe.gd", "--",
		"--host=127.0.0.1", "--port=%d" % port, "--world-id=moon",
		"--session-token=%s" % SESSION_TOKEN, "--result-file=%s" % probe_path,
		"--network-profile=%s" % PROFILE_ID,
	], root.path_join("user-probe"))
	child_pids.append(probe_pid)
	_assert(probe_pid > 0, "NX1 conditioned probe launched")
	var probe: Dictionary = _wait_state(probe_path, ["COMPLETE", "FAILED"], PROBE_TIMEOUT_MS)
	_assert(String(probe.get("state", "")) == "COMPLETE", "NX1 conditioned probe completed")
	_assert(String(probe.get("status", "")) == "ACK", "Conditioned handshake receives ACK")
	_assert(String(probe.get("error_code", "")) == "", "Conditioned handshake has no error")
	_assert(int(probe.get("handshake_elapsed_ms", 0)) >= 60, "Conditioned handshake exhibits measurable simulated latency")
	_assert(String(probe.get("network_conditions", {}).get("profile", {}).get("profile_id", "")) == PROFILE_ID, "Probe activates requested profile")
	var probe_counters: Dictionary = probe.get("network_conditions", {}).get("counters", {})
	_assert(int(probe_counters.get("network_simulator_outgoing_packets_queued", 0)) >= 1, "Probe queued outgoing conditioned packet")
	_assert(int(probe_counters.get("network_simulator_incoming_packets_queued", 0)) >= 1, "Probe queued incoming conditioned packet")
	_assert(int(probe_counters.get("network_simulator_outgoing_packets_delivered", 0)) >= 1, "Probe delivered outgoing conditioned packet")
	_assert(int(probe_counters.get("network_simulator_incoming_packets_delivered", 0)) >= 1, "Probe delivered incoming conditioned packet")
	_wait_exit(probe_pid, EXIT_TIMEOUT_MS)
	_assert(not OS.is_process_running(probe_pid), "NX1 probe exited")
	child_pids.erase(probe_pid)

	var final_report: Dictionary = _wait_handshake_accept(server_path, 15000)
	_assert(int(final_report.get("joins", -1)) == 0, "Conditioned handshake alone creates no gameplay join")
	_assert(int(final_report.get("compatibility_handshake", {}).get("accepts", 0)) >= 1, "Server accepts conditioned handshake")
	var server_counters: Dictionary = final_report.get("network_conditions", {}).get("counters", {})
	_assert(int(server_counters.get("network_simulator_outgoing_packets_queued", 0)) >= 1, "Server queued outgoing conditioned response")
	_assert(int(server_counters.get("network_simulator_incoming_packets_queued", 0)) >= 1, "Server queued incoming conditioned request")
	_assert(int(server_counters.get("network_simulator_outgoing_packets_delivered", 0)) >= 1, "Server delivered outgoing conditioned response")
	_assert(int(server_counters.get("network_simulator_incoming_packets_delivered", 0)) >= 1, "Server delivered incoming conditioned request")
	_assert(int(final_report.get("network_conditions", {}).get("outgoing_queue_messages", -1)) == 0, "Server outgoing simulator queue drains")
	_assert(int(final_report.get("network_conditions", {}).get("incoming_queue_messages", -1)) == 0, "Server incoming simulator queue drains")
	_assert_clean_log(root.path_join("server.log"), "NX1 server")
	_assert_clean_log(root.path_join("probe.log"), "NX1 probe")
	_finish()


func _spawn(executable: String, args: Array[String], user_root: String) -> int:
	var names: Array[String] = [
		"HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME",
		"APPDATA", "LOCALAPPDATA", "BREAKPOINT_RUNTIME_DISABLED",
	]
	var captured: Dictionary = _capture_environment(names)
	var data: String = user_root.path_join("data")
	var config: String = user_root.path_join("config")
	var cache: String = user_root.path_join("cache")
	for path in [user_root, data, config, cache]:
		DirAccess.make_dir_recursive_absolute(path)
	OS.set_environment("HOME", user_root)
	OS.set_environment("XDG_DATA_HOME", data)
	OS.set_environment("XDG_CONFIG_HOME", config)
	OS.set_environment("XDG_CACHE_HOME", cache)
	OS.set_environment("APPDATA", data)
	OS.set_environment("LOCALAPPDATA", data)
	OS.set_environment("BREAKPOINT_RUNTIME_DISABLED", "1")
	var pid: int = OS.create_process(executable, args, false)
	_restore_environment(captured)
	return pid


func _wait_state(path: String, states: Array[String], timeout_ms: int) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	var last: Dictionary = {}
	while Time.get_ticks_msec() - started <= timeout_ms:
		last = _read_json(path)
		if String(last.get("state", "")) in states:
			return last
		OS.delay_msec(POLL_DELAY_MS)
	return last


func _wait_handshake_accept(path: String, timeout_ms: int) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	var last: Dictionary = {}
	while Time.get_ticks_msec() - started <= timeout_ms:
		last = _read_json(path)
		if int(last.get("compatibility_handshake", {}).get("accepts", 0)) >= 1:
			return last
		OS.delay_msec(POLL_DELAY_MS)
	return last


func _wait_exit(pid: int, timeout_ms: int) -> void:
	var started: int = Time.get_ticks_msec()
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() - started <= timeout_ms:
		OS.delay_msec(POLL_DELAY_MS)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return Dictionary(parsed) if parsed is Dictionary else {}


func _find_available_port() -> int:
	for port in range(44000 + (OS.get_process_id() % 1000), 46000):
		var udp := PacketPeerUDP.new()
		if udp.bind(port, "127.0.0.1") == OK:
			udp.close()
			return port
	return 0


func _capture_environment(names: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	for name in names:
		result[name] = {"set": OS.has_environment(name), "value": OS.get_environment(name)}
	return result


func _restore_environment(values: Dictionary) -> void:
	for name in values.keys():
		if bool(values[name].get("set", false)):
			OS.set_environment(String(name), String(values[name].get("value", "")))
		else:
			OS.unset_environment(String(name))


func _assert_clean_log(path: String, label: String) -> void:
	var text: String = FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var lowered: String = text.to_lower()
	_assert(
		not lowered.contains("script error:")
		and not lowered.contains("parse error:")
		and not lowered.contains("compile error:"),
		"%s log has no script errors" % label
	)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)


func _finish() -> void:
	for pid in child_pids.duplicate():
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
	child_pids.clear()
	print("NX1 conditioned ENet processes: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

extends SceneTree

const POLL_DELAY_MS := 25
const SERVER_TIMEOUT_MS := 30000
const PROBE_TIMEOUT_MS := 30000
const EXIT_TIMEOUT_MS := 10000
const SESSION_TOKEN := "session-id/nx0/process-acceptance"

var assertions: int = 0
var failures: Array[String] = []
var child_pids: Array[int] = []


func _init() -> void:
	var port: int = _find_available_port()
	_assert(port > 0, "UDP port allocation")
	if port <= 0:
		_finish()
		return
	var root: String = ProjectSettings.globalize_path(
		"res://artifacts/test-results/nx0-handshake-%d" % OS.get_process_id()
	)
	DirAccess.make_dir_recursive_absolute(root)
	var server_path: String = root.path_join("server.json")
	var mismatch_path: String = root.path_join("mismatch.json")
	var matching_path: String = root.path_join("matching.json")
	var executable: String = OS.get_executable_path()
	var project_root: String = ProjectSettings.globalize_path("res://")
	var server_pid: int = _spawn(executable, [
		"--headless", "--quiet", "--path", project_root,
		"--log-file", root.path_join("server.log"), "--",
		"--role=dedicated-server", "--world=moon", "--node-id=nx0-handshake-server",
		"--server-address=127.0.0.1", "--server-port=%d" % port,
		"--network-session-token=%s" % SESSION_TOKEN,
		"--m3-result-file=%s" % server_path, "--shutdown-after-ms=120000",
	], root.path_join("user-server"))
	child_pids.append(server_pid)
	_assert(server_pid > 0, "NX0 dedicated server launched")
	var ready: Dictionary = _wait_state(server_path, ["READY", "FAILED"], SERVER_TIMEOUT_MS)
	_assert(String(ready.get("state", "")) == "READY", "NX0 dedicated server ready")
	_assert(String(ready.get("checkpoint", "")) in ["v16.11.0-network-nx1-deterministic-condition-simulator", "v16.12.0-network-nx2-realtime-traffic-separation", "v16.13.0-network-nx3-fixed-tick-authoritative-simulation"], "Server reports current network checkpoint")
	_assert(String(ready.get("network_fingerprint", {}).get("session_token", "")) == SESSION_TOKEN, "Server reports session binding")
	if String(ready.get("state", "")) != "READY":
		_finish()
		return

	var mismatch_pid: int = _spawn_probe(
		executable, project_root, port, "session-id/nx0/process-mismatch",
		mismatch_path, root.path_join("mismatch.log"), root.path_join("user-mismatch")
	)
	child_pids.append(mismatch_pid)
	_assert(mismatch_pid > 0, "Mismatched fingerprint probe launched")
	var mismatch: Dictionary = _wait_state(mismatch_path, ["COMPLETE", "FAILED"], PROBE_TIMEOUT_MS)
	_assert(String(mismatch.get("state", "")) == "COMPLETE", "Mismatched probe completed")
	_assert(String(mismatch.get("status", "")) == "REJECTED", "Mismatched probe received rejection")
	_assert(String(mismatch.get("error_code", "")) == "SESSION_TOKEN_MISMATCH", "Mismatched probe received deterministic code")
	_assert(String(mismatch.get("response", {}).get("error_code", "")) == "SESSION_TOKEN_MISMATCH", "Wire rejection preserves mismatch code")
	_wait_exit(mismatch_pid, EXIT_TIMEOUT_MS)
	_assert(not OS.is_process_running(mismatch_pid), "Mismatched probe exited")
	child_pids.erase(mismatch_pid)
	var after_mismatch: Dictionary = _wait_handshake_counts(server_path, 1, 0, 1, 15000)
	_assert(int(after_mismatch.get("joins", -1)) == 0, "Rejected fingerprint created no gameplay join")
	_assert(int(after_mismatch.get("compatibility_handshake", {}).get("rejections", 0)) >= 1, "Server counted fingerprint rejection")
	_assert(String(after_mismatch.get("compatibility_handshake", {}).get("last_error_code", "")) == "SESSION_TOKEN_MISMATCH", "Server reports last mismatch code")

	var matching_pid: int = _spawn_probe(
		executable, project_root, port, SESSION_TOKEN,
		matching_path, root.path_join("matching.log"), root.path_join("user-matching")
	)
	child_pids.append(matching_pid)
	_assert(matching_pid > 0, "Matching fingerprint probe launched")
	var matching: Dictionary = _wait_state(matching_path, ["COMPLETE", "FAILED"], PROBE_TIMEOUT_MS)
	_assert(String(matching.get("state", "")) == "COMPLETE", "Matching probe completed")
	_assert(String(matching.get("status", "")) == "ACK", "Matching probe received ACK")
	_assert(String(matching.get("error_code", "")) == "", "Matching probe has no error")
	_assert(String(matching.get("response", {}).get("server_fingerprint", {}).get("checksum", "")) == String(ready.get("network_fingerprint", {}).get("checksum", "")), "ACK binds server fingerprint")
	_wait_exit(matching_pid, EXIT_TIMEOUT_MS)
	_assert(not OS.is_process_running(matching_pid), "Matching probe exited")
	child_pids.erase(matching_pid)
	var final_report: Dictionary = _wait_handshake_counts(server_path, 2, 1, 1, 15000)
	_assert(int(final_report.get("joins", -1)) == 0, "Handshake-only client created no gameplay join")
	_assert(int(final_report.get("compatibility_handshake", {}).get("attempts", 0)) >= 2, "Server counted both handshake attempts")
	_assert(int(final_report.get("compatibility_handshake", {}).get("accepts", 0)) >= 1, "Server counted matching handshake")
	_assert(int(final_report.get("connected_peer_count", -1)) == 0, "Handshake probes left no gameplay peers")
	var telemetry: Dictionary = final_report.get("network_telemetry", {})
	_assert(String(telemetry.get("schema", "")) == "planet_simulator.network_observability_sample.v1", "Server emits observability sample")
	_assert(int(telemetry.get("counters", {}).get("handshake_attempts", 0)) >= 2, "Telemetry counted handshake attempts")
	_assert(int(telemetry.get("counters", {}).get("handshake_rejections", 0)) >= 1, "Telemetry counted handshake rejection")
	_assert(int(telemetry.get("channels", {}).get("control", {}).get("packets_sent", 0)) >= 2, "Telemetry measured CONTROL responses")
	_assert_clean_log(root.path_join("server.log"), "server")
	_assert_clean_log(root.path_join("mismatch.log"), "mismatch probe")
	_assert_clean_log(root.path_join("matching.log"), "matching probe")
	_finish()


func _spawn_probe(
	executable: String,
	project_root: String,
	port: int,
	session_token: String,
	result_path: String,
	log_path: String,
	user_root: String
) -> int:
	return _spawn(executable, [
		"--headless", "--quiet", "--path", project_root,
		"--log-file", log_path,
		"--script", "res://tools/network/nx0_handshake_probe.gd", "--",
		"--host=127.0.0.1", "--port=%d" % port, "--world-id=moon",
		"--session-token=%s" % session_token, "--result-file=%s" % result_path,
	], user_root)


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


func _wait_handshake_counts(path: String, attempts: int, accepts: int, rejections: int, timeout_ms: int) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	var last: Dictionary = {}
	while Time.get_ticks_msec() - started <= timeout_ms:
		last = _read_json(path)
		var handshake: Dictionary = last.get("compatibility_handshake", {})
		if (
			int(handshake.get("attempts", 0)) >= attempts
			and int(handshake.get("accepts", 0)) >= accepts
			and int(handshake.get("rejections", 0)) >= rejections
		):
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
	for port in range(42000 + (OS.get_process_id() % 1000), 44000):
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
	_assert(not lowered.contains("script error:") and not lowered.contains("parse error:") and not lowered.contains("compile error:"), "%s log has no script errors" % label)


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
	print("NX0 compatibility handshake processes: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

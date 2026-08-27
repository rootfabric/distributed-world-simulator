extends SceneTree

const Support = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")

const POLL_MS := 50
const READY_TIMEOUT_MS := 30000
const COMPLETE_TIMEOUT_MS := 90000
const EXIT_TIMEOUT_MS := 10000

var assertions := 0
var failures: Array[String] = []
var child_pids: Array[int] = []
var detached_pids: Array[int] = []
var xvfb_pid := -1


func _init() -> void:
	_run_gateway_restart()
	_finish()


func _run_gateway_restart() -> void:
	var ports := _allocate_ports(3)
	_assert(ports.size() == 3, "7.9 three isolated ENET ports allocated")
	if ports.size() != 3:
		return
	var root := ProjectSettings.globalize_path("res://artifacts/test-results/sm1-gateway-restart-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(root)
	var display := ""
	if OS.get_name() == "Linux":
		display = _start_xvfb()
		_assert(not display.is_empty(), "7.9 Xvfb graphical display started")
		if display.is_empty():
			return
	var project_root := ProjectSettings.globalize_path("res://")
	var exe := OS.get_executable_path()
	var a_path := root.path_join("authority-a.json")
	var b_path := root.path_join("authority-b.json")
	var gateway1_path := root.path_join("gateway-1.json")
	var gateway2_path := root.path_join("gateway-2.json")
	var client_a_path := root.path_join("client-a.json")
	var client_b_path := root.path_join("client-b.json")

	var authority_a_pid := _spawn(exe, [
		"--headless", "--quiet", "--path", project_root, "--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_6_authority_worker.gd", "--",
		"--authority-id=%s" % Support.AUTHORITY_A, "--host=127.0.0.1", "--port=%d" % int(ports[1]),
		"--initial-active=true", "--initial-epoch=1", "--result-file=%s" % a_path,
	], root.path_join("user-authority-a"), "", root.path_join("authority-a.log"))
	var authority_b_pid := _spawn(exe, [
		"--headless", "--quiet", "--path", project_root, "--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_6_authority_worker.gd", "--",
		"--authority-id=%s" % Support.AUTHORITY_B, "--host=127.0.0.1", "--port=%d" % int(ports[2]),
		"--initial-active=false", "--initial-epoch=1", "--result-file=%s" % b_path,
	], root.path_join("user-authority-b"), "", root.path_join("authority-b.log"))
	child_pids.append(authority_a_pid)
	child_pids.append(authority_b_pid)
	_assert(authority_a_pid > 0 and authority_b_pid > 0, "7.9 two authority processes launched")
	var a_ready := _wait_state(a_path, ["LISTENING", "FAILED"], READY_TIMEOUT_MS)
	var b_ready := _wait_state(b_path, ["LISTENING", "FAILED"], READY_TIMEOUT_MS)
	_assert(String(a_ready.get("state", "")) == "LISTENING", "7.9 Authority A listening")
	_assert(String(b_ready.get("state", "")) == "LISTENING", "7.9 Authority B listening")
	if String(a_ready.get("state", "")) != "LISTENING" or String(b_ready.get("state", "")) != "LISTENING":
		return

	var gateway1_pid := _spawn_gateway_detached(exe, project_root, root, ports, gateway1_path, "gateway-1")
	_assert(gateway1_pid > 0, "7.9 first Gateway detached crash target launched")
	if gateway1_pid <= 0:
		return
	detached_pids.append(gateway1_pid)
	var gateway1_ready := _wait_state(gateway1_path, ["LISTENING", "FAILED"], READY_TIMEOUT_MS)
	_assert(String(gateway1_ready.get("state", "")) == "LISTENING", "7.9 first Gateway listening")
	_assert(int(gateway1_ready.get("process_id", 0)) == gateway1_pid, "7.9 first Gateway reports exact crash-target PID")
	if String(gateway1_ready.get("state", "")) != "LISTENING":
		return

	var client_a_pid := _spawn(exe, [
		"--quiet", "--path", project_root, "--rendering-method", "gl_compatibility", "--audio-driver", "Dummy",
		"--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_7_gateway_restart_client.gd", "--",
		"--client-id=a", "--host=127.0.0.1", "--port=%d" % int(ports[0]), "--result-file=%s" % client_a_path,
	], root.path_join("user-client-a"), display, root.path_join("client-a.log"))
	var client_b_pid := _spawn(exe, [
		"--quiet", "--path", project_root, "--rendering-method", "gl_compatibility", "--audio-driver", "Dummy",
		"--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_7_gateway_restart_client.gd", "--",
		"--client-id=b", "--host=127.0.0.1", "--port=%d" % int(ports[0]), "--result-file=%s" % client_b_path,
	], root.path_join("user-client-b"), display, root.path_join("client-b.log"))
	child_pids.append(client_a_pid)
	child_pids.append(client_b_pid)
	_assert(client_a_pid > 0 and client_b_pid > 0, "7.9 two graphical clients launched")

	var client_a_waiting := _wait_state(client_a_path, ["WAITING_FOR_GATEWAY_FAILURE", "FAILED"], COMPLETE_TIMEOUT_MS)
	var client_b_waiting := _wait_state(client_b_path, ["WAITING_FOR_GATEWAY_FAILURE", "FAILED"], COMPLETE_TIMEOUT_MS)
	_assert(String(client_a_waiting.get("state", "")) == "WAITING_FOR_GATEWAY_FAILURE", "7.9 writer reaches completed A->B handoff before Gateway loss")
	_assert(String(client_b_waiting.get("state", "")) == "WAITING_FOR_GATEWAY_FAILURE", "7.9 observer sees completed A->B handoff before Gateway loss")
	for report in [client_a_waiting, client_b_waiting]:
		_assert(String(report.get("active_authority_id", "")) == Support.AUTHORITY_B and int(report.get("authority_epoch", 0)) == 2, "7.9 client checkpoint observes B epoch2")
		_assert(int(report.get("world_revision", 0)) == 1 and not String(report.get("state_checksum", "")).is_empty(), "7.9 client checkpoint carries revision1 observed-state identity")
	if String(client_a_waiting.get("state", "")) != "WAITING_FOR_GATEWAY_FAILURE" or String(client_b_waiting.get("state", "")) != "WAITING_FOR_GATEWAY_FAILURE":
		return

	var killed := OS.kill(gateway1_pid)
	_assert(killed == OK, "7.9 first Gateway receives real OS kill")
	_wait_detached_exit(gateway1_pid, EXIT_TIMEOUT_MS)
	_assert(not _pid_alive(gateway1_pid), "7.9 first Gateway process is actually dead")
	detached_pids.erase(gateway1_pid)
	_assert(_wait_udp_port_free(int(ports[0]), EXIT_TIMEOUT_MS), "7.9 client-facing Gateway port is released after crash")

	var gateway2_pid := _spawn(exe, [
		"--headless", "--quiet", "--path", project_root, "--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_6_gateway_worker.gd", "--",
		"--client-host=127.0.0.1", "--client-port=%d" % int(ports[0]),
		"--authority-a-host=127.0.0.1", "--authority-a-port=%d" % int(ports[1]),
		"--authority-b-host=127.0.0.1", "--authority-b-port=%d" % int(ports[2]),
		"--result-file=%s" % gateway2_path,
	], root.path_join("user-gateway-2"), "", root.path_join("gateway-2.log"))
	child_pids.append(gateway2_pid)
	_assert(gateway2_pid > 0 and gateway2_pid != gateway1_pid, "7.9 replacement Gateway launches as a new OS process")
	var gateway2_ready := _wait_state(gateway2_path, ["LISTENING", "FAILED"], READY_TIMEOUT_MS)
	_assert(String(gateway2_ready.get("state", "")) == "LISTENING", "7.9 replacement Gateway listens on the same logical endpoint")
	if String(gateway2_ready.get("state", "")) != "LISTENING":
		return

	var client_a := _wait_state(client_a_path, ["COMPLETE", "FAILED"], COMPLETE_TIMEOUT_MS)
	var client_b := _wait_state(client_b_path, ["COMPLETE", "FAILED"], COMPLETE_TIMEOUT_MS)
	var gateway2 := _wait_state(gateway2_path, ["COMPLETE", "FAILED"], COMPLETE_TIMEOUT_MS)
	var authority_a := _wait_state(a_path, ["COMPLETE", "FAILED"], COMPLETE_TIMEOUT_MS)
	var authority_b := _wait_state(b_path, ["COMPLETE", "FAILED"], COMPLETE_TIMEOUT_MS)
	_validate(client_a, client_b, gateway2, authority_a, authority_b, gateway1_pid, gateway2_pid)
	for pid in [client_a_pid, client_b_pid, gateway2_pid, authority_a_pid, authority_b_pid]:
		_wait_direct_child_exit(int(pid), EXIT_TIMEOUT_MS)
		_assert(not OS.is_process_running(int(pid)), "7.9 child process %d exited cleanly" % int(pid))


func _validate(client_a: Dictionary, client_b: Dictionary, gateway: Dictionary, authority_a: Dictionary, authority_b: Dictionary, gateway1_pid: int, gateway2_pid: int) -> void:
	for pair in [["client A", client_a], ["client B", client_b], ["replacement Gateway", gateway], ["Authority A", authority_a], ["Authority B", authority_b]]:
		_assert(bool(Dictionary(pair[1]).get("passed", false)), "7.9 %s process PASS: %s" % [String(pair[0]), Dictionary(pair[1])])
	var pids: Dictionary = {gateway1_pid: true, gateway2_pid: true}
	for report in [client_a, client_b, authority_a, authority_b]:
		pids[int(report.get("process_id", 0))] = true
	_assert(pids.size() == 6 and not pids.has(0), "7.9 crash/restart uses six distinct product OS process identities")

	for report in [client_a, client_b]:
		_assert(String(report.get("display_server", "")).to_lower() not in ["", "headless", "dummy"], "7.9 client uses real graphical DisplayServer")
		_assert(String(report.get("rendering_method", "")) == "gl_compatibility", "7.9 client uses GL compatibility renderer")
		_assert(int(report.get("connect_count", 0)) == 2 and int(report.get("reconnect_count", 0)) == 1, "7.9 client establishes one initial and one recovered Gateway connection")
		_assert(int(report.get("respawn_count", -1)) == 0, "7.9 Gateway crash causes zero respawns")
		_assert(int(report.get("disconnect_events", 0)) >= 1, "7.9 client observes the Gateway loss")
		var sessions: Array = Array(report.get("transport_session_ids", []))
		_assert(sessions.size() == 2 and String(sessions[0]) != String(sessions[1]), "7.9 recovered client uses a fresh transport-session identity")
		_assert(bool(report.get("resume_received", false)) and bool(report.get("session_ready_received", false)), "7.9 client completes RESUME plus recovered-session barrier")
		_assert(String(report.get("gateway_endpoint_id", "")) == Support.GATEWAY_ENDPOINT_ID, "7.9 logical Gateway endpoint remains unchanged")
		_assert(String(report.get("logical_player_id", "")) == Support.LOGICAL_PLAYER_ID and String(report.get("player_entity_id", "")) == Support.PLAYER_ENTITY_ID, "7.9 player identity remains stable")
		_assert(int(report.get("spawn_generation", 0)) == 1, "7.9 spawn generation remains one")
		_assert(_ints(report.get("epochs", [])) == [1, 2, 3], "7.9 client observes epochs 1->2->3")
		_assert(_ints(report.get("revisions", [])) == [1, 2, 3, 4], "7.9 client observes revisions 1..4")
		_assert(_strings(report.get("route_history", [])) == [Support.AUTHORITY_A, Support.AUTHORITY_B, Support.AUTHORITY_A], "7.9 client observes A->B->A despite Gateway replacement")
	_assert(int(client_a.get("commands_sent", 0)) == 4 and int(client_a.get("command_results", 0)) == 4, "7.9 writer completes four logical operations across Gateway replacement")
	_assert(int(client_b.get("commands_sent", -1)) == 0 and int(client_b.get("command_results", -1)) == 0, "7.9 observer remains read-only across Gateway replacement")

	var gateway_counters: Dictionary = Dictionary(gateway.get("counters", {}))
	_assert(bool(gateway.get("authority_recovery_complete", false)), "7.9 replacement Gateway completes authority recovery")
	_assert(String(gateway.get("bootstrap_authority_id", "")) == Support.AUTHORITY_B and int(gateway.get("bootstrap_authority_epoch", 0)) == 2, "7.9 replacement Gateway recovers B epoch2 from Authorities")
	_assert(String(gateway.get("active_authority_id", "")) == Support.AUTHORITY_A and int(gateway.get("authority_epoch", 0)) == 3, "7.9 replacement Gateway converges to final A epoch3")
	_assert(int(gateway.get("handoff_count", -1)) == 1, "7.9 replacement Gateway records only post-restart B->A handoff")
	_assert(int(gateway.get("last_world_revision", 0)) == 4, "7.9 replacement Gateway converges to revision4")
	_assert(int(gateway_counters.get("authority_status_queries", -1)) == 2 and int(gateway_counters.get("authority_recoveries", -1)) == 1, "7.9 recovery uses two read-only authority status queries and one selection")
	_assert(int(gateway_counters.get("restart_resume_sessions", -1)) == 2 and int(gateway_counters.get("resume_successes", -1)) == 2, "7.9 both clients are rebound through read-only resume")
	_assert(int(gateway_counters.get("session_ready_announcements", -1)) == 1, "7.9 replacement Gateway opens one recovered client session barrier")
	_assert(int(gateway_counters.get("commands", -1)) == 3 and int(gateway_counters.get("state_broadcasts", -1)) == 3, "7.9 replacement Gateway handles only post-restart commands/revisions")
	_assert(not bool(gateway.get("transfer_payload_retained", true)) and not bool(gateway.get("canonical_gameplay_owner", true)), "7.9 replacement Gateway remains non-canonical and retains no transfer payload")
	_assert(not bool(gateway.get("client_endpoint_changed", true)) and String(gateway.get("gateway_endpoint_id", "")) == Support.GATEWAY_ENDPOINT_ID, "7.9 logical client endpoint does not change")

	var state_a: Dictionary = Dictionary(authority_a.get("shared_state", {}))
	var expected_ops := ["operation/sm1/gateway-restart/1", "operation/sm1/gateway-restart/2", "operation/sm1/gateway-restart/3", "operation/sm1/graphical/5"]
	_assert(String(authority_a.get("authority_id", "")) == Support.AUTHORITY_A and bool(authority_a.get("active", false)) and int(authority_a.get("authority_epoch", 0)) == 3, "7.9 Authority A is sole final active writer")
	_assert(String(authority_b.get("authority_id", "")) == Support.AUTHORITY_B and not bool(authority_b.get("active", true)) and int(authority_b.get("authority_epoch", 0)) == 2, "7.9 Authority B retires after return handoff")
	_assert(int(state_a.get("world_revision", 0)) == 4 and int(state_a.get("last_input_sequence", 0)) == 4, "7.9 revision/input sequence remains monotonic through Gateway loss")
	_assert(_strings(state_a.get("operation_ids", [])) == expected_ops, "7.9 OperationId ledger contains each logical operation exactly once")
	_assert(float(state_a.get("position_x", 999.0)) == 0.0 and int(state_a.get("action_count", 0)) == 2, "7.9 final world state is correct")
	var counters_a: Dictionary = Dictionary(authority_a.get("counters", {}))
	var counters_b: Dictionary = Dictionary(authority_b.get("counters", {}))
	_assert(int(counters_a.get("executed", -1)) == 2 and int(counters_b.get("executed", -1)) == 2, "7.9 execution partitions exactly 2 on A + 2 on B")
	_assert(int(counters_a.get("replays", -1)) == 0 and int(counters_b.get("replays", -1)) == 0, "7.9 Gateway restart causes zero OperationId replay")
	_assert(int(counters_a.get("write_rejections", -1)) == 0 and int(counters_b.get("write_rejections", -1)) == 0, "7.9 Gateway restart causes zero stale authority writes")
	_assert(int(counters_a.get("status_queries", -1)) == 2 and int(counters_b.get("status_queries", -1)) == 2, "7.9 each Authority services one status query per Gateway lifetime")
	_assert(int(counters_b.get("state_queries", -1)) == 2 and int(counters_a.get("state_queries", -1)) == 0, "7.9 both client resumes read state only from recovered active B")
	_assert(not bool(authority_a.get("private_persistence_owner", true)) and not bool(authority_b.get("private_persistence_owner", true)), "7.9 authorities create no private persistence owner")


func _spawn_gateway_detached(executable: String, project_root: String, root: String, ports: Array, result_path: String, name: String) -> int:
	var args := [
		"--headless", "--quiet", "--path", project_root, "--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_6_gateway_worker.gd", "--",
		"--client-host=127.0.0.1", "--client-port=%d" % int(ports[0]),
		"--authority-a-host=127.0.0.1", "--authority-a-port=%d" % int(ports[1]),
		"--authority-b-host=127.0.0.1", "--authority-b-port=%d" % int(ports[2]),
		"--result-file=%s" % result_path,
	]
	return _spawn_detached(executable, args, root.path_join("user-%s" % name), root.path_join("%s.log" % name), root.path_join("%s.pid" % name))


func _spawn_detached(executable: String, args: Array, user_root: String, log_path: String, pid_path: String) -> int:
	var names := ["HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA", "BREAKPOINT_RUNTIME_DISABLED", "GODOT_SILENCE_ROOT_WARNING"]
	var captured := _capture_environment(names)
	var data := user_root.path_join("data")
	var config := user_root.path_join("config")
	var cache := user_root.path_join("cache")
	for path in [user_root, data, config, cache]:
		DirAccess.make_dir_recursive_absolute(path)
	OS.set_environment("HOME", user_root)
	OS.set_environment("XDG_DATA_HOME", data)
	OS.set_environment("XDG_CONFIG_HOME", config)
	OS.set_environment("XDG_CACHE_HOME", cache)
	OS.set_environment("APPDATA", data)
	OS.set_environment("LOCALAPPDATA", data)
	OS.set_environment("BREAKPOINT_RUNTIME_DISABLED", "1")
	OS.set_environment("GODOT_SILENCE_ROOT_WARNING", "1")
	var launcher_path := user_root.path_join("launch-detached.sh")
	var launcher := FileAccess.open(launcher_path, FileAccess.WRITE)
	if launcher == null:
		_restore_environment(captured)
		return -1
	launcher.store_string("#!/bin/sh\nlog=\"$1\"\npidfile=\"$2\"\nshift 2\n/usr/bin/setsid \"$@\" >\"$log\" 2>&1 < /dev/null &\necho $! >\"$pidfile\"\n")
	launcher.close()
	var full_args: Array = ["--log-file", log_path]
	full_args.append_array(args)
	var shell_args: Array = [launcher_path, log_path, pid_path, executable]
	shell_args.append_array(full_args)
	var output: Array[String] = []
	var exit_code := OS.execute("/bin/sh", shell_args, output, true, false)
	_restore_environment(captured)
	if exit_code != 0:
		return -1
	var started := Time.get_ticks_msec()
	while not FileAccess.file_exists(pid_path) and Time.get_ticks_msec() - started <= 3000:
		OS.delay_msec(POLL_MS)
	if not FileAccess.file_exists(pid_path):
		return -1
	var pid_file := FileAccess.open(pid_path, FileAccess.READ)
	if pid_file == null:
		return -1
	var pid := int(pid_file.get_as_text().strip_edges())
	pid_file.close()
	return pid


func _spawn(executable: String, args: Array, user_root: String, display: String, log_path: String) -> int:
	var names := ["HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA", "DISPLAY", "LIBGL_ALWAYS_SOFTWARE", "BREAKPOINT_RUNTIME_DISABLED", "GODOT_SILENCE_ROOT_WARNING"]
	var captured := _capture_environment(names)
	var data := user_root.path_join("data")
	var config := user_root.path_join("config")
	var cache := user_root.path_join("cache")
	for path in [user_root, data, config, cache]:
		DirAccess.make_dir_recursive_absolute(path)
	OS.set_environment("HOME", user_root)
	OS.set_environment("XDG_DATA_HOME", data)
	OS.set_environment("XDG_CONFIG_HOME", config)
	OS.set_environment("XDG_CACHE_HOME", cache)
	OS.set_environment("APPDATA", data)
	OS.set_environment("LOCALAPPDATA", data)
	OS.set_environment("BREAKPOINT_RUNTIME_DISABLED", "1")
	OS.set_environment("GODOT_SILENCE_ROOT_WARNING", "1")
	if not display.is_empty():
		OS.set_environment("DISPLAY", display)
		OS.set_environment("LIBGL_ALWAYS_SOFTWARE", "1")
	var full_args: Array = ["--log-file", log_path]
	full_args.append_array(args)
	var pid := OS.create_process(executable, full_args, false)
	_restore_environment(captured)
	return pid


func _start_xvfb() -> String:
	if not FileAccess.file_exists("/usr/bin/Xvfb"):
		failures.append("Xvfb is required for SM1.7 Gateway restart graphical process acceptance")
		return ""
	var base := 1040 + (OS.get_process_id() % 80)
	for offset in range(20):
		var display := ":%d" % (base + offset)
		xvfb_pid = OS.create_process("/usr/bin/Xvfb", [display, "-screen", "0", "1280x720x24", "-nolisten", "tcp", "-noreset"], false)
		if xvfb_pid <= 0:
			continue
		OS.delay_msec(400)
		if OS.is_process_running(xvfb_pid):
			child_pids.append(xvfb_pid)
			return display
	return ""


func _allocate_ports(count: int) -> Array:
	var result: Array = []
	var start := 37000 + (OS.get_process_id() % 12000)
	for offset in range(1000):
		var port := 20000 + ((start + offset - 20000) % 40000)
		if result.has(port):
			continue
		var probe := PacketPeerUDP.new()
		var error := probe.bind(port, "127.0.0.1")
		probe.close()
		if error == OK:
			result.append(port)
			if result.size() == count:
				break
	return result


func _wait_udp_port_free(port: int, timeout_ms: int) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= timeout_ms:
		var probe := PacketPeerUDP.new()
		var error := probe.bind(port, "127.0.0.1")
		probe.close()
		if error == OK:
			return true
		OS.delay_msec(POLL_MS)
	return false


func _wait_state(path: String, terminal_states: Array, timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= timeout_ms:
		var value := _read_json(path)
		if terminal_states.has(String(value.get("state", ""))):
			return value
		OS.delay_msec(POLL_MS)
	return _read_json(path)


func _wait_direct_child_exit(pid: int, timeout_ms: int) -> void:
	var started := Time.get_ticks_msec()
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() - started <= timeout_ms:
		OS.delay_msec(POLL_MS)


func _wait_detached_exit(pid: int, timeout_ms: int) -> void:
	var started := Time.get_ticks_msec()
	while _pid_alive(pid) and Time.get_ticks_msec() - started <= timeout_ms:
		OS.delay_msec(POLL_MS)


func _pid_alive(pid: int) -> bool:
	if pid <= 0:
		return false
	if OS.get_name() == "Linux":
		var path := "/proc/%d/stat" % pid
		if not FileAccess.file_exists(path):
			return false
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return false
		var text := file.get_as_text()
		file.close()
		var close_paren := text.rfind(")")
		if close_paren < 0 or close_paren + 2 >= text.length():
			return true
		var rest := text.substr(close_paren + 2).split(" ", false)
		return not rest.is_empty() and String(rest[0]) != "Z"
	return OS.is_process_running(pid)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return Dictionary(parsed) if parsed is Dictionary else {}


func _ints(values) -> Array:
	var result: Array = []
	if values is Array:
		for value in values:
			result.append(int(value))
	return result


func _strings(values) -> Array[String]:
	var result: Array[String] = []
	if values is Array:
		for value in values:
			result.append(String(value))
	return result


func _capture_environment(names: Array) -> Dictionary:
	var result: Dictionary = {}
	for name_value in names:
		var name := String(name_value)
		result[name] = {"set": OS.has_environment(name), "value": OS.get_environment(name)}
	return result


func _restore_environment(values: Dictionary) -> void:
	for name_value in values.keys():
		var name := String(name_value)
		if bool(Dictionary(values[name_value]).get("set", false)):
			OS.set_environment(name, String(Dictionary(values[name_value]).get("value", "")))
		else:
			OS.unset_environment(name)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("[sm1.7.9] PASS: %s" % message)
	else:
		failures.append(message)
		print("[sm1.7.9][FAIL] %s" % message)


func _finish() -> void:
	for pid in detached_pids.duplicate():
		if _pid_alive(int(pid)):
			OS.kill(int(pid))
	detached_pids.clear()
	for pid in child_pids.duplicate():
		if int(pid) > 0 and OS.is_process_running(int(pid)):
			OS.kill(int(pid))
	child_pids.clear()
	print("SM1.7.9 Gateway failure/restart: %d assertions, %d failures" % [assertions, failures.size()])
	if failures.is_empty():
		print("SM1_7_9_GATEWAY_FAILURE_RESTART_PASS")
	quit(0 if failures.is_empty() else 1)

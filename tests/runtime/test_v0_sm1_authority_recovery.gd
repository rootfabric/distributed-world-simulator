extends SceneTree

const Support = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")

const POLL_MS := 50
const READY_TIMEOUT_MS := 30000
const RECOVERY_TIMEOUT_MS := 45000
const COMPLETE_TIMEOUT_MS := 90000
const EXIT_TIMEOUT_MS := 10000

var assertions := 0
var failures: Array[String] = []
var child_pids: Array[int] = []
var detached_pids: Array[int] = []
var xvfb_pid := -1


func _init() -> void:
	_run_authority_recovery()
	_finish()


func _run_authority_recovery() -> void:
	var ports := _allocate_ports(3)
	_assert(ports.size() == 3, "7.10 three isolated ENET ports allocated")
	if ports.size() != 3:
		return
	var root := ProjectSettings.globalize_path("res://artifacts/test-results/sm1-authority-recovery-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(root)
	var display := ""
	if OS.get_name() == "Linux":
		display = _start_xvfb()
		_assert(not display.is_empty(), "7.10 Xvfb graphical display started")
		if display.is_empty():
			return
	var project_root := ProjectSettings.globalize_path("res://")
	var exe := OS.get_executable_path()
	var a1_path := root.path_join("authority-a-1.json")
	var a2_path := root.path_join("authority-a-2.json")
	var b1_path := root.path_join("authority-b-1.json")
	var b2_path := root.path_join("authority-b-2.json")
	var gateway_path := root.path_join("gateway.json")
	var client_a_path := root.path_join("client-a.json")
	var client_b_path := root.path_join("client-b.json")

	var a1_pid := _spawn_authority_detached(exe, project_root, root, Support.AUTHORITY_A, int(ports[1]), true, 1, a1_path, "authority-a-1")
	var b1_pid := _spawn_authority_detached(exe, project_root, root, Support.AUTHORITY_B, int(ports[2]), false, 1, b1_path, "authority-b-1")
	detached_pids.append(a1_pid)
	detached_pids.append(b1_pid)
	_assert(a1_pid > 0 and b1_pid > 0, "7.10 original Authority A/B processes launched")
	var a1_ready := _wait_state(a1_path, ["LISTENING", "FAILED"], READY_TIMEOUT_MS)
	var b1_ready := _wait_state(b1_path, ["LISTENING", "FAILED"], READY_TIMEOUT_MS)
	_assert(String(a1_ready.get("state", "")) == "LISTENING", "7.10 original Authority A listening")
	_assert(String(b1_ready.get("state", "")) == "LISTENING", "7.10 original Authority B listening")
	if String(a1_ready.get("state", "")) != "LISTENING" or String(b1_ready.get("state", "")) != "LISTENING":
		return

	var gateway_pid := _spawn(exe, [
		"--headless", "--quiet", "--path", project_root, "--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_6_gateway_worker.gd", "--",
		"--client-host=127.0.0.1", "--client-port=%d" % int(ports[0]),
		"--authority-a-host=127.0.0.1", "--authority-a-port=%d" % int(ports[1]),
		"--authority-b-host=127.0.0.1", "--authority-b-port=%d" % int(ports[2]),
		"--result-file=%s" % gateway_path,
	], root.path_join("user-gateway"), "", root.path_join("gateway.log"))
	child_pids.append(gateway_pid)
	_assert(gateway_pid > 0, "7.10 Gateway process launched")
	var gateway_ready := _wait_state(gateway_path, ["LISTENING", "FAILED"], READY_TIMEOUT_MS)
	_assert(String(gateway_ready.get("state", "")) == "LISTENING", "7.10 Gateway listening")
	if String(gateway_ready.get("state", "")) != "LISTENING":
		return

	var client_a_pid := _spawn(exe, [
		"--quiet", "--path", project_root, "--rendering-method", "gl_compatibility", "--audio-driver", "Dummy",
		"--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_7_authority_recovery_client.gd", "--",
		"--client-id=a", "--host=127.0.0.1", "--port=%d" % int(ports[0]), "--result-file=%s" % client_a_path,
	], root.path_join("user-client-a"), display, root.path_join("client-a.log"))
	var client_b_pid := _spawn(exe, [
		"--quiet", "--path", project_root, "--rendering-method", "gl_compatibility", "--audio-driver", "Dummy",
		"--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_7_authority_recovery_client.gd", "--",
		"--client-id=b", "--host=127.0.0.1", "--port=%d" % int(ports[0]), "--result-file=%s" % client_b_path,
	], root.path_join("user-client-b"), display, root.path_join("client-b.log"))
	child_pids.append(client_a_pid)
	child_pids.append(client_b_pid)
	_assert(client_a_pid > 0 and client_b_pid > 0, "7.10 two graphical clients launched")

	var client_a_wait := _wait_state(client_a_path, ["WAITING_FOR_STANDBY_FAILURE", "FAILED"], COMPLETE_TIMEOUT_MS)
	var client_b_wait := _wait_state(client_b_path, ["WAITING_FOR_STANDBY_FAILURE", "FAILED"], COMPLETE_TIMEOUT_MS)
	_assert(String(client_a_wait.get("state", "")) == "WAITING_FOR_STANDBY_FAILURE", "7.10 writer reaches B/epoch2 before standby crash")
	_assert(String(client_b_wait.get("state", "")) == "WAITING_FOR_STANDBY_FAILURE", "7.10 observer reaches B/epoch2 before standby crash")
	for report in [client_a_wait, client_b_wait]:
		_assert(String(report.get("active_authority_id", "")) == Support.AUTHORITY_B and int(report.get("authority_epoch", 0)) == 2, "7.10 checkpoint observes B epoch2")
		_assert(int(report.get("world_revision", 0)) == 1 and not String(report.get("state_checksum", "")).is_empty(), "7.10 checkpoint carries revision1 observed-state identity")
	if String(client_a_wait.get("state", "")) != "WAITING_FOR_STANDBY_FAILURE" or String(client_b_wait.get("state", "")) != "WAITING_FOR_STANDBY_FAILURE":
		return

	_assert(OS.kill(a1_pid) == OK, "7.10 retired Authority A receives real OS kill")
	_wait_detached_exit(a1_pid, EXIT_TIMEOUT_MS)
	_assert(not _pid_alive(a1_pid), "7.10 original retired Authority A is dead")
	detached_pids.erase(a1_pid)
	_assert(_wait_udp_port_free(int(ports[1]), EXIT_TIMEOUT_MS), "7.10 Authority A port released after crash")

	var a2_pid := _spawn(exe, [
		"--headless", "--quiet", "--path", project_root, "--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_6_authority_worker.gd", "--",
		"--authority-id=%s" % Support.AUTHORITY_A, "--host=127.0.0.1", "--port=%d" % int(ports[1]),
		"--initial-active=false", "--initial-epoch=1", "--result-file=%s" % a2_path,
	], root.path_join("user-authority-a-2"), "", root.path_join("authority-a-2.log"))
	child_pids.append(a2_pid)
	_assert(a2_pid > 0 and a2_pid != a1_pid, "7.10 replacement Authority A launches as new inactive process")
	var a2_ready := _wait_state(a2_path, ["LISTENING", "FAILED"], READY_TIMEOUT_MS)
	_assert(String(a2_ready.get("state", "")) == "LISTENING" and not bool(a2_ready.get("active", true)), "7.10 replacement A starts inactive and cannot self-promote")
	if String(a2_ready.get("state", "")) != "LISTENING":
		return

	var client_a_standby := _wait_state(client_a_path, ["STANDBY_RECOVERED", "FAILED"], RECOVERY_TIMEOUT_MS)
	var client_b_standby := _wait_state(client_b_path, ["STANDBY_RECOVERED", "FAILED"], RECOVERY_TIMEOUT_MS)
	_assert(String(client_a_standby.get("state", "")) == "STANDBY_RECOVERED", "7.10 writer observes zero-write standby A recovery")
	_assert(String(client_b_standby.get("state", "")) == "STANDBY_RECOVERED", "7.10 observer observes zero-write standby A recovery")
	for report in [client_a_standby, client_b_standby]:
		_assert(String(report.get("active_authority_id", "")) == Support.AUTHORITY_B and int(report.get("authority_epoch", 0)) == 2, "7.10 standby recovery leaves B/epoch2 ownership unchanged")
		_assert(int(report.get("world_revision", 0)) == 1, "7.10 standby recovery leaves world revision unchanged")
	if String(client_a_standby.get("state", "")) != "STANDBY_RECOVERED" or String(client_b_standby.get("state", "")) != "STANDBY_RECOVERED":
		return

	_assert(OS.kill(b1_pid) == OK, "7.10 active Authority B receives real OS kill")
	_wait_detached_exit(b1_pid, EXIT_TIMEOUT_MS)
	_assert(not _pid_alive(b1_pid), "7.10 original active Authority B is dead")
	detached_pids.erase(b1_pid)
	_assert(_wait_udp_port_free(int(ports[2]), EXIT_TIMEOUT_MS), "7.10 Authority B port released after crash")

	var b2_pid := _spawn(exe, [
		"--headless", "--quiet", "--path", project_root, "--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_6_authority_worker.gd", "--",
		"--authority-id=%s" % Support.AUTHORITY_B, "--host=127.0.0.1", "--port=%d" % int(ports[2]),
		"--initial-active=false", "--initial-epoch=1", "--result-file=%s" % b2_path,
	], root.path_join("user-authority-b-2"), "", root.path_join("authority-b-2.log"))
	child_pids.append(b2_pid)
	_assert(b2_pid > 0 and b2_pid != b1_pid, "7.10 replacement Authority B launches as new inactive process")
	var b2_ready := _wait_state(b2_path, ["LISTENING", "FAILED"], READY_TIMEOUT_MS)
	_assert(String(b2_ready.get("state", "")) == "LISTENING" and not bool(b2_ready.get("active", true)), "7.10 replacement B starts inactive and cannot self-promote")
	if String(b2_ready.get("state", "")) != "LISTENING":
		return

	var client_a := _wait_state(client_a_path, ["COMPLETE", "FAILED"], COMPLETE_TIMEOUT_MS)
	var client_b := _wait_state(client_b_path, ["COMPLETE", "FAILED"], COMPLETE_TIMEOUT_MS)
	var gateway := _wait_state(gateway_path, ["COMPLETE", "FAILED"], COMPLETE_TIMEOUT_MS)
	var authority_a := _wait_state(a2_path, ["COMPLETE", "FAILED"], COMPLETE_TIMEOUT_MS)
	var authority_b := _wait_state(b2_path, ["COMPLETE", "FAILED"], COMPLETE_TIMEOUT_MS)
	_validate(client_a, client_b, gateway, authority_a, authority_b, a1_pid, a2_pid, b1_pid, b2_pid, gateway_pid)
	for pid in [client_a_pid, client_b_pid, gateway_pid, a2_pid, b2_pid]:
		_wait_direct_child_exit(int(pid), EXIT_TIMEOUT_MS)
		_assert(not OS.is_process_running(int(pid)), "7.10 child process %d exited cleanly" % int(pid))


func _validate(client_a: Dictionary, client_b: Dictionary, gateway: Dictionary, authority_a: Dictionary, authority_b: Dictionary, a1_pid: int, a2_pid: int, b1_pid: int, b2_pid: int, gateway_pid: int) -> void:
	for pair in [["client A", client_a], ["client B", client_b], ["Gateway", gateway], ["replacement Authority A", authority_a], ["replacement Authority B", authority_b]]:
		_assert(bool(Dictionary(pair[1]).get("passed", false)), "7.10 %s process PASS: %s" % [String(pair[0]), Dictionary(pair[1])])
	var pids := {a1_pid: true, a2_pid: true, b1_pid: true, b2_pid: true, gateway_pid: true}
	pids[int(client_a.get("process_id", 0))] = true
	pids[int(client_b.get("process_id", 0))] = true
	_assert(pids.size() == 7 and not pids.has(0), "7.10 authority crash/restart uses seven distinct product OS process identities")

	for report in [client_a, client_b]:
		_assert(String(report.get("display_server", "")).to_lower() not in ["", "headless", "dummy"], "7.10 client uses real graphical DisplayServer")
		_assert(String(report.get("rendering_method", "")) == "gl_compatibility", "7.10 client uses GL compatibility renderer")
		_assert(int(report.get("connect_count", 0)) == 1 and int(report.get("reconnect_count", -1)) == 0, "7.10 clients remain on one Gateway transport connection")
		_assert(int(report.get("respawn_count", -1)) == 0, "7.10 Authority recovery causes zero respawn")
		_assert(bool(report.get("standby_recovered", false)) and bool(report.get("active_recovered", false)), "7.10 client observes standby and active Authority recovery")
		_assert(int(report.get("recovery_pending_events", 0)) == 2 and int(report.get("recovery_complete_events", 0)) == 2, "7.10 client observes exactly two recovery windows")
		_assert(String(report.get("gateway_endpoint_id", "")) == Support.GATEWAY_ENDPOINT_ID, "7.10 Gateway endpoint stays stable")
		_assert(String(report.get("logical_player_id", "")) == Support.LOGICAL_PLAYER_ID and String(report.get("player_entity_id", "")) == Support.PLAYER_ENTITY_ID, "7.10 player identity stays stable")
		_assert(int(report.get("spawn_generation", 0)) == 1, "7.10 spawn generation remains one")
		_assert(_ints(report.get("epochs", [])) == [1, 2, 3], "7.10 client sees epochs 1->2->3 with no recovery epoch inflation")
		_assert(_ints(report.get("revisions", [])) == [1, 2, 3, 4], "7.10 client sees revisions 1..4 without recovery mutation")
		_assert(_strings(report.get("route_history", [])) == [Support.AUTHORITY_A, Support.AUTHORITY_B, Support.AUTHORITY_A], "7.10 route changes only on gameplay handoffs")
	_assert(int(client_a.get("commands_sent", 0)) == 4 and int(client_a.get("command_results", 0)) == 4, "7.10 writer completes four logical operations across two Authority restarts")
	_assert(int(client_b.get("commands_sent", -1)) == 0, "7.10 observer remains read-only")

	var gc: Dictionary = Dictionary(gateway.get("counters", {}))
	_assert(String(gateway.get("active_authority_id", "")) == Support.AUTHORITY_A and int(gateway.get("authority_epoch", 0)) == 3, "7.10 final owner is A epoch3")
	_assert(int(gateway.get("handoff_count", 0)) == 2 and int(gateway.get("last_world_revision", 0)) == 4, "7.10 two gameplay handoffs and revision4 survive Authority restarts")
	_assert(int(gc.get("authority_disconnects", -1)) == 2 and int(gc.get("authority_reconnects", -1)) == 2, "7.10 Gateway observes and reconnects exactly two Authority processes")
	_assert(int(gc.get("authority_recovery_status_queries", -1)) == 2 and int(gc.get("authority_recovery_state_queries", -1)) == 2, "7.10 each replacement is validated and sourced read-only")
	_assert(int(gc.get("standby_syncs", -1)) == 2, "7.10 both replacements receive one zero-write standby sync")
	_assert(int(gc.get("active_authority_recoveries", -1)) == 1, "7.10 only the crashed active B is recovery-activated")
	_assert(int(gc.get("authority_recovery_events", -1)) == 2, "7.10 exactly two Authority recoveries complete")
	_assert(int(gc.get("commands", -1)) == 4 and int(gc.get("state_broadcasts", -1)) == 4, "7.10 recovery itself adds no gameplay revision")
	_assert(not bool(gateway.get("authority_runtime_recovery_pending", true)) and not bool(gateway.get("authority_recovery_blocks_writes", true)), "7.10 Gateway ends with no recovery pending or write block")
	_assert(not bool(gateway.get("transfer_payload_retained", true)) and not bool(gateway.get("canonical_gameplay_owner", true)), "7.10 Gateway remains non-canonical and retains no transfer payload")

	var state_a: Dictionary = Dictionary(authority_a.get("shared_state", {}))
	var expected_ops := ["operation/sm1/authority-recovery/1", "operation/sm1/authority-recovery/2", "operation/sm1/authority-recovery/3", "operation/sm1/graphical/5"]
	_assert(bool(authority_a.get("active", false)) and int(authority_a.get("authority_epoch", 0)) == 3, "7.10 replacement A becomes final active authority only through normal B->A handoff")
	_assert(not bool(authority_b.get("active", true)) and int(authority_b.get("authority_epoch", 0)) == 2, "7.10 recovered B retires normally after B->A")
	_assert(int(state_a.get("world_revision", 0)) == 4 and int(state_a.get("last_input_sequence", 0)) == 4, "7.10 final revision/input watermark is monotonic")
	_assert(_strings(state_a.get("operation_ids", [])) == expected_ops, "7.10 OperationId ledger contains each logical operation exactly once")
	_assert(float(state_a.get("position_x", 999.0)) == 0.0 and int(state_a.get("action_count", 0)) == 2, "7.10 final world state is correct")
	var ac: Dictionary = Dictionary(authority_a.get("counters", {}))
	var bc: Dictionary = Dictionary(authority_b.get("counters", {}))
	_assert(int(ac.get("standby_syncs", -1)) == 1 and int(ac.get("recovery_activations", -1)) == 0, "7.10 replacement A is synced zero-write and never recovery-self-activates")
	_assert(int(bc.get("standby_syncs", -1)) == 1 and int(bc.get("recovery_activations", -1)) == 1, "7.10 replacement B activates only after recovery sync")
	_assert(int(ac.get("recovery_state_queries", -1)) == 1, "7.10 recovered standby A supplies one read-only historical state query for B recovery")
	_assert(int(ac.get("executed", -1)) == 1 and int(bc.get("executed", -1)) == 2, "7.10 post-restart executions partition 1 on A + 2 on B")
	_assert(int(ac.get("replays", -1)) == 0 and int(bc.get("replays", -1)) == 0, "7.10 recovery causes zero OperationId replay")
	_assert(int(ac.get("write_rejections", -1)) == 0 and int(bc.get("write_rejections", -1)) == 0, "7.10 recovery causes zero stale-authority writes")
	_assert(not bool(authority_a.get("private_persistence_owner", true)) and not bool(authority_b.get("private_persistence_owner", true)), "7.10 replacements create no private persistence owner")


func _spawn_authority_detached(executable: String, project_root: String, root: String, authority_id: String, port: int, active: bool, epoch: int, result_path: String, name: String) -> int:
	var args := [
		"--headless", "--quiet", "--path", project_root, "--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_6_authority_worker.gd", "--",
		"--authority-id=%s" % authority_id, "--host=127.0.0.1", "--port=%d" % port,
		"--initial-active=%s" % ("true" if active else "false"), "--initial-epoch=%d" % epoch, "--result-file=%s" % result_path,
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
	var full_args: Array = ["--log-file", log_path]
	full_args.append_array(args)
	if OS.get_name() == "Windows":
		# The Unix detached launcher requires /bin/sh and setsid, which do not
		# exist on Windows; spawn the detached worker process directly instead.
		var spawned_pid := OS.create_process(executable, full_args, false)
		_restore_environment(captured)
		return spawned_pid
	var launcher_path := user_root.path_join("launch-detached.sh")
	var launcher := FileAccess.open(launcher_path, FileAccess.WRITE)
	if launcher == null:
		_restore_environment(captured)
		return -1
	launcher.store_string("#!/bin/sh\nlog=\"$1\"\npidfile=\"$2\"\nshift 2\n/usr/bin/setsid \"$@\" >\"$log\" 2>&1 < /dev/null &\necho $! >\"$pidfile\"\n")
	launcher.close()
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
		failures.append("Xvfb is required for SM1.7 Authority recovery graphical process acceptance")
		return ""
	var base := 1140 + (OS.get_process_id() % 80)
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
	var start := 39000 + (OS.get_process_id() % 10000)
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
		print("[sm1.7.10] PASS: %s" % message)
	else:
		failures.append(message)
		print("[sm1.7.10][FAIL] %s" % message)


func _finish() -> void:
	for pid in detached_pids.duplicate():
		if _pid_alive(int(pid)):
			OS.kill(int(pid))
	detached_pids.clear()
	for pid in child_pids.duplicate():
		if int(pid) > 0 and OS.is_process_running(int(pid)):
			OS.kill(int(pid))
	child_pids.clear()
	print("SM1.7.10 Authority recovery: %d assertions, %d failures" % [assertions, failures.size()])
	if failures.is_empty():
		print("SM1_7_10_AUTHORITY_RECOVERY_PASS")
	quit(0 if failures.is_empty() else 1)
